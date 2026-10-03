//
//  WindowDragManager.swift
//  Loop
//
//  Created by Kai Azim on 2023-09-04.
//

import Defaults
import os
import Scribe
import SwiftUI

@Loggable
@MainActor
final class WindowDragManager {
    static let shared = WindowDragManager()
    private init() {}

    private var resizeContext: ResizeContext?
    private var initialWindowFrame: CGRect?

    /// This is to avoid repeated window resolution attempts during a non-window drag (e.g. in games).
    private var didFailToResolveDraggedWindow: Bool = false

    private let previewController = PreviewController()

    /// Listen-only. Snap detection always goes through this, so a stall cannot swallow drags.
    private var leftMouseDraggedMonitor: PassiveEventMonitor?
    private var leftMouseUpMonitor: PassiveEventMonitor?

    /// Rewrites top-edge drag events. Exists only while a resolved window is moving and
    /// Suppress Mission Control is on. An active tap that stalls can block drags system-wide,
    /// so this must not outlive the drag.
    private var missionControlDragMonitor: ActiveEventMonitor?

    private var determineDraggedWindowTask: Task<(), Never>?
    private var accessibilityCheckerTask: Task<(), Never>?

    /// Previous drag Y, so a single crossing of a stacked-display seam is not treated as the top edge.
    private let topEdgeRewrite = OSAllocatedUnfairLock(initialState: MissionControlTopEdgeRewrite())

    /// Bumped on mouse-up so an in-flight drag task cannot install the active tap after the drag ends.
    private var dragSession = 0

    private var currentMousePosition: CGPoint {
        NSEvent.mouseLocation.flipY(screen: NSScreen.screens[0])
    }

    /// This is to avoid running global drag logic unless a feature actually depends on it.
    private var shouldMonitorDragActions: Bool {
        Defaults[.windowSnapping] ||
            Defaults[.restoreWindowFrameOnDrag] ||
            !Defaults[.stashManagerStashedWindows].isEmpty
    }

    func addObservers() {
        accessibilityCheckerTask = Task(priority: .background) { [weak self] in
            for await status in AccessibilityManager.shared.stream(initial: true) {
                guard let self, !Task.isCancelled else {
                    return
                }

                if status {
                    setupListeners()
                } else {
                    removeListeners()
                }
            }
        }
    }

    func shutdown() {
        accessibilityCheckerTask?.cancel()
        accessibilityCheckerTask = nil
        removeListeners()
        resetDragState()
        previewController.close()
    }

    private func setupListeners() {
        removeListeners()

        let leftMouseDraggedMonitor = PassiveEventMonitor(
            "snapping_left_mouse_dragged_monitor",
            events: [.leftMouseDragged],
            callback: leftMouseDragged
        )

        let leftMouseUpMonitor = PassiveEventMonitor(
            "snapping_left_mouse_up_monitor",
            events: [.leftMouseUp],
            callback: leftMouseUp
        )

        leftMouseDraggedMonitor.start()
        leftMouseUpMonitor.start()

        self.leftMouseDraggedMonitor = leftMouseDraggedMonitor
        self.leftMouseUpMonitor = leftMouseUpMonitor
    }

    private func removeListeners() {
        stopMissionControlDragMonitor()
        leftMouseUpMonitor?.stop()
        leftMouseDraggedMonitor?.stop()

        leftMouseUpMonitor = nil
        leftMouseDraggedMonitor = nil
    }

    /// Installs the active tap once a window drag is underway. Non-window drags never reach it.
    private func startMissionControlDragMonitorIfNeeded(session: Int) {
        guard session == dragSession, missionControlDragMonitor == nil else { return }
        guard Defaults[.windowSnapping], Defaults[.suppressMissionControlOnTopDrag] else { return }

        let monitor = ActiveEventMonitor(
            "mission_control_drag_monitor",
            events: [.leftMouseDragged]
        ) { [weak self] event -> Unmanaged<CGEvent>? in
            self?.rewriteTopEdgeDrag(event)
            return Unmanaged.passUnretained(event)
        }

        monitor.start()
        // Mouse-up can end the session while the tap is being created. A failed tap must not
        // stick around, or later drag events will skip trying again.
        guard session == dragSession, monitor.isEnabled else {
            monitor.stop()
            return
        }
        missionControlDragMonitor = monitor
    }

    private func stopMissionControlDragMonitor() {
        missionControlDragMonitor?.stop()
        missionControlDragMonitor = nil
        topEdgeRewrite.withLock { $0.previousY = nil }
    }

    /// Keeps Mission Control from opening during a top-edge window snap.
    ///
    /// Rewriting the event is smoother than `CGWarpMouseCursorPosition`, which fights the cursor
    /// every frame. CoreGraphics bounds are used because this runs on the event-tap thread.
    private nonisolated func rewriteTopEdgeDrag(_ event: CGEvent) {
        let frames = Self.activeDisplayFrames()
        topEdgeRewrite.withLock { state in
            if let adjusted = state.rewrittenLocation(event.location, displayFrames: frames) {
                event.location = adjusted
            }
        }
    }

    /// Top of the display under `point`, in CoreGraphics coordinates (`minY` is the top edge).
    ///
    /// Includes a point sitting up to 1pt past the edge. The cursor is usually clamped onto
    /// the edge, but some events are reported slightly above it.
    nonisolated static func topEdgeY(at point: CGPoint, displayFrames: [CGRect]) -> CGFloat? {
        let topEdges = displayFrames.filter { frame in
            point.x >= frame.minX && point.x <= frame.maxX &&
                point.y <= frame.minY && point.y >= frame.minY - 1
        }

        // More than one display can match on a shared corner. Use the edge nearest the pointer.
        return topEdges.min(by: {
            abs($0.minY - point.y) < abs($1.minY - point.y)
        })?.minY
    }

    private nonisolated static func activeDisplayFrames() -> [CGRect] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else {
            return []
        }

        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else {
            return []
        }

        return displays.prefix(Int(count)).map { CGDisplayBounds($0) }
    }

    private func leftMouseDragged(event _: CGEvent) {
        guard shouldMonitorDragActions else {
            return
        }

        Task {
            let session = dragSession

            // Process window (only ONCE during a window drag)
            if resizeContext == nil, !didFailToResolveDraggedWindow {
                setCurrentDraggingWindow()
            }

            if let window = resizeContext?.window,
               let initialFrame = initialWindowFrame,
               hasWindowResized(window.frame, initialFrame) {
                if hasWindowMoved(window.frame, initialFrame) {
                    if Defaults[.restoreWindowFrameOnDrag] {
                        await restoreInitialWindowSize(window)
                    }

                    if Defaults[.windowSnapping] {
                        startMissionControlDragMonitorIfNeeded(session: session)
                        processSnapAction()
                    }
                }

                StashManager.shared.onWindowManipulated(window.cgWindowID)
                await WindowRecords.shared.eraseRecords(for: window)
            }
        }
    }

    private func leftMouseUp(_: CGEvent) {
        Task {
            dragSession += 1
            stopMissionControlDragMonitor()

            guard Defaults[.windowSnapping] else {
                return
            }

            previewController.close()

            if let context = resizeContext,
               !context.action.direction.isNoOp,
               let window = context.window,
               let initialFrame = initialWindowFrame,
               hasWindowMoved(window.frame, initialFrame) {
                do {
                    _ = try await WindowActionEngine.shared.apply(context: context)
                } catch {
                    log.error("Failed to snap window: \(error.localizedDescription)")
                }
            }

            resetDragState()
        }
    }

    private func setCurrentDraggingWindow() {
        guard determineDraggedWindowTask == nil else {
            return
        }

        determineDraggedWindowTask = Task {
            defer {
                determineDraggedWindowTask = nil
            }

            guard let window = WindowUtility.windowAtPosition(currentMousePosition),
                  !window.isAppExcluded
            else {
                didFailToResolveDraggedWindow = true
                return
            }

            initialWindowFrame = window.frame

            let context = ResizeContext(
                window: window,
                initialMousePosition: currentMousePosition
            )
            await context.refreshResolvedState()
            self.resizeContext = context

            log.info("Determined window being dragged: \(window.description)")
        }
    }

    private func resetDragState() {
        resizeContext = nil
        didFailToResolveDraggedWindow = false
        initialWindowFrame = nil
        determineDraggedWindowTask?.cancel()
        determineDraggedWindowTask = nil
        stopMissionControlDragMonitor()
    }

    private func hasWindowMoved(_ windowFrame: CGRect, _ initialFrame: CGRect) -> Bool {
        !initialFrame.topLeftPoint.approximatelyEqual(to: windowFrame.topLeftPoint) &&
            !initialFrame.topRightPoint.approximatelyEqual(to: windowFrame.topRightPoint) &&
            !initialFrame.bottomLeftPoint.approximatelyEqual(to: windowFrame.bottomLeftPoint) &&
            !initialFrame.bottomRightPoint.approximatelyEqual(to: windowFrame.bottomRightPoint)
    }

    private func hasWindowResized(_ windowFrame: CGRect, _ initialFrame: CGRect) -> Bool {
        !initialFrame.topLeftPoint.approximatelyEqual(to: windowFrame.topLeftPoint) ||
            !initialFrame.topRightPoint.approximatelyEqual(to: windowFrame.topRightPoint) ||
            !initialFrame.bottomLeftPoint.approximatelyEqual(to: windowFrame.bottomLeftPoint) ||
            !initialFrame.bottomRightPoint.approximatelyEqual(to: windowFrame.bottomRightPoint)
    }

    private func restoreInitialWindowSize(_ window: Window) async {
        let startFrame = window.frame

        guard let initialFrame = await WindowRecords.shared.getInitialFrame(for: window) else {
            return
        }

        if let screen = NSScreen.screenWithMouse {
            var newWindowFrame = window.frame
            newWindowFrame.size = initialFrame.size
            newWindowFrame = newWindowFrame.pushInside(screen.displayBounds)
            await window.setFrame(newWindowFrame)
        } else {
            window.setSize(initialFrame.size)
        }

        // If the window doesn't contain the cursor, keep the original maxX
        if !window.frame.contains(currentMousePosition) {
            var newFrame = window.frame

            newFrame.origin.x = startFrame.maxX - newFrame.width
            await window.setFrame(newFrame)

            // If it still doesn't contain the cursor, move the window to be centered with the cursor
            if !newFrame.contains(currentMousePosition) {
                newFrame.origin.x = currentMousePosition.x - (newFrame.width / 2)
                await window.setFrame(newFrame)
            }
        }

        await WindowRecords.shared.eraseRecords(for: window)
    }

    private func processSnapAction() {
        guard let screen = NSScreen.screenWithMouse else {
            return
        }

        let mainScreen = NSScreen.screens[0]
        let screenFrame = screen.frame.flipY(screen: mainScreen)

        let inset = Defaults[.snapThreshold]
        let topInset = max(screen.menubarHeight / 2, inset)
        var ignoredFrame = screenFrame

        ignoredFrame.origin.x += inset
        ignoredFrame.size.width -= inset * 2
        ignoredFrame.origin.y += topInset
        ignoredFrame.size.height -= inset + topInset

        let oldDirection = resizeContext?.action.direction ?? .noAction

        if !ignoredFrame.contains(currentMousePosition) {
            let newDirection = WindowDirection.getSnapDirection(
                mouseLocation: currentMousePosition,
                currentDirection: oldDirection,
                screenFrame: screenFrame,
                ignoredFrame: ignoredFrame
            )

            // Only update if direction actually changed
            if newDirection != oldDirection {
                // Refresh accent colors in case user has enabled the wallpaper processor
                Task {
                    await AccentColorController.shared.refresh()
                }

                log.info("Window snapping direction changed: \(newDirection.debugDescription)")

                resizeContext?.setScreen(to: screen)
                resizeContext?.setAction(to: .init(newDirection), parent: nil)

                if let context = resizeContext {
                    previewController.open(context: context)
                }

                // Haptic feedback
                if newDirection != .noAction, Defaults[.hapticFeedback] {
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                }
            }
        } else if !oldDirection.isNoOp {
            // Only close if we were showing something
            resizeContext?.setAction(to: .init(.noAction), parent: nil)
            previewController.close()
        }
    }
}

/// Decides when a drag event should be moved 1pt off a display's top edge.
///
/// The first event that lands on an edge is left alone. Rewriting starts only when the previous
/// event was already on that same edge, which is what a held top-edge drag looks like. Crossing
/// the seam between stacked displays is a single event and is not rewritten.
struct MissionControlTopEdgeRewrite: Equatable {
    var previousY: CGFloat?

    mutating func rewrittenLocation(_ location: CGPoint, displayFrames: [CGRect]) -> CGPoint? {
        let currentY = location.y
        defer { previousY = currentY }

        guard let top = WindowDragManager.topEdgeY(at: location, displayFrames: displayFrames),
              let previousY,
              previousY <= top,
              previousY >= top - 1,
              currentY <= top
        else {
            return nil
        }

        var adjusted = location
        adjusted.y = top + 1
        return adjusted
    }
}
