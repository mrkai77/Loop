//
//  MouseInteractionObserver.swift
//  Loop
//
//  Created by Kai Azim on 2025-11-11.
//

import Defaults
import Scribe
import SwiftUI

@Loggable
final class MouseInteractionObserver {
    private static let directionalActionDistance: CGFloat = 50
    private static let noActionDistance: CGFloat = 10

    // Parameters
    private let windowActionCache: WindowActionCache
    private let changeAction: (WindowAction) -> ()
    private let advanceSelectedAction: (WindowAction?) -> ()
    private let canSelectNextCycleitem: () -> Bool
    private let checkIfLoopOpen: () -> Bool

    private var mouseMovementMonitor: PassiveEventMonitor?
    private var leftClickMonitor: ActiveEventMonitor?

    // State-keeping for previous calculations
    private var previousAngleToMouse: Angle = .zero
    private var previousDistanceToMouse: CGFloat = .zero
    private var pendingRepeatableAction: WindowAction?

    private var screenBounds: CGRect?
    private var shouldAccountForAbsoluteMousePosition: Bool = false
    private var initialMousePosition: CGPoint = .zero
    private var latestMousePosition: CGPoint = .zero

    private var radialMenuActions: [RadialMenuAction] {
        RadialMenuAction.userConfiguredActions
    }

    private static let failedToResolveKeybindAction: WindowAction = .init(.noAction) // This helps to keep a stable ID

    init(
        windowActionCache: WindowActionCache,
        changeAction: @escaping (WindowAction) -> (),
        advanceSelectedAction: @escaping (WindowAction?) -> (),
        canSelectNextCycleitem: @escaping () -> Bool,
        checkIfLoopOpen: @escaping () -> Bool
    ) {
        self.windowActionCache = windowActionCache
        self.changeAction = changeAction
        self.advanceSelectedAction = advanceSelectedAction
        self.canSelectNextCycleitem = canSelectNextCycleitem
        self.checkIfLoopOpen = checkIfLoopOpen
    }

    func start(initialMousePosition: CGPoint) {
        stop()

        screenBounds = NSScreen.screens.first(where: { $0.frame.contains(initialMousePosition) })?.frame

        if let screenBounds {
            // If the current mouse position isn't sufficient for accessing direcitonal actions due to being close to the screen's edge, then enable `shouldAccountForAbsoluteMousePosition`
            let closeToMinX = abs(initialMousePosition.x - screenBounds.minX) < Self.directionalActionDistance
            let closeToMaxX = abs(initialMousePosition.x - screenBounds.maxX) < Self.directionalActionDistance
            let closeToMinY = abs(initialMousePosition.y - screenBounds.minY) < Self.directionalActionDistance
            let closeToMaxY = abs(initialMousePosition.y - screenBounds.maxY) < Self.directionalActionDistance

            if closeToMinX || closeToMaxX || closeToMinY || closeToMaxY {
                shouldAccountForAbsoluteMousePosition = true
            }
        }

        self.initialMousePosition = initialMousePosition
        latestMousePosition = initialMousePosition

        let mouseMovementMonitor = PassiveEventMonitor(
            "mouse_movement_monitor",
            events: [
                .mouseMoved, // switch action when mouse is moved
                .otherMouseDragged // switch action when mouse is moved with the middle mouse button clicked
            ],
            callback: processNewMouseLocation
        )
        mouseMovementMonitor.start()
        self.mouseMovementMonitor = mouseMovementMonitor

        let leftClickMonitor = ActiveEventMonitor(
            "left_click_monitor",
            events: [.leftMouseDown], // Increment a cycle action on a left click
            callback: activateNextCycleAction
        )
        leftClickMonitor.start()
        self.leftClickMonitor = leftClickMonitor

        log.info("Started with initial mouse position: \(latestMousePosition.debugDescription)")
    }

    func stop() {
        mouseMovementMonitor?.stop()
        mouseMovementMonitor = nil

        leftClickMonitor?.stop()
        leftClickMonitor = nil

        previousAngleToMouse = .zero
        previousDistanceToMouse = .zero
        pendingRepeatableAction = nil

        screenBounds = nil
        shouldAccountForAbsoluteMousePosition = false
        initialMousePosition = .zero
        latestMousePosition = .zero

        log.success("Stopped, all stored states cleared.")
    }

    private func processNewMouseLocation(_ event: CGEvent) {
        guard checkIfLoopOpen() else { return }

        Task {
            let currentMousePosition = computeLatestMousePosition(event)
            let angleToMouse = initialMousePosition.angle(to: currentMousePosition) + .radians(.pi / 2)
            let distanceToMouse = initialMousePosition.distance(to: currentMousePosition)

            // Return if the mouse didn't move
            guard
                angleToMouse != previousAngleToMouse ||
                distanceToMouse != previousDistanceToMouse
            else {
                return
            }

            // Get angle & distance to mouse
            previousAngleToMouse = angleToMouse
            previousDistanceToMouse = distanceToMouse

            var newAction: RadialMenuAction? = nil

            // If mouse over 50 points away, select half or quarter positions
            if distanceToMouse > Self.directionalActionDistance - Defaults[.radialMenuThickness] {
                guard radialMenuActions.count > 1 else {
                    newAction = radialMenuActions.first
                    return
                }

                let actions = radialMenuActions.dropLast()
                let actionAngleSpan = 360.0 / CGFloat(actions.count)
                let halfAngleSpan = actionAngleSpan / 2.0
                let index = Int((angleToMouse.normalized().degrees + halfAngleSpan) / actionAngleSpan) % actions.count
                newAction = actions[index]
            } else if distanceToMouse > Self.noActionDistance {
                newAction = radialMenuActions.last
            }

            let resolvedAction: WindowAction? = switch newAction?.type {
            case let .custom(windowAction):
                windowAction
            case let .keybindReference(id):
                windowActionCache.actionsByIdentifier[id] ?? Self.failedToResolveKeybindAction
            case nil:
                .init(.noSelection)
            }

            if let resolvedAction, resolvedAction.allowsRapidRepeat {
                if pendingRepeatableAction?.id != resolvedAction.id {
                    changeAction(resolvedAction)
                }
                pendingRepeatableAction = resolvedAction
            } else {
                pendingRepeatableAction = nil
                changeAction(resolvedAction ?? .init(.noSelection))
            }
        }
    }

    /// Computes a resolved mouse position, compensating for macOS cursor clamping at screen edges.
    ///
    /// When enabled, this method continues tracking movement along an axis even after the system
    /// cursor becomes pinned to a screen edge by applying the event’s delta to the last known position,
    /// while clamping the result to a limited distance from the edge, just enough to access directional actions.
    ///
    /// - Parameter event: the CGEvent associated with this mouse movement
    /// - Returns: the computed absolute mouse position
    private func computeLatestMousePosition(_ event: CGEvent) -> CGPoint {
        let current = NSEvent.mouseLocation

        guard shouldAccountForAbsoluteMousePosition, let bounds = screenBounds else {
            latestMousePosition = current
            return latestMousePosition
        }

        let edgeThreshold: CGFloat = 1
        let deltaX = event.getDoubleValueField(.mouseEventDeltaX)
        let deltaY = event.getDoubleValueField(.mouseEventDeltaY)
        let maxOffset = Self.directionalActionDistance

        let atMinX = abs(current.x - bounds.minX) < edgeThreshold
        let atMaxX = abs(current.x - bounds.maxX) < edgeThreshold
        let atMinY = abs(current.y - bounds.minY) < edgeThreshold
        let atMaxY = abs(current.y - bounds.maxY) < edgeThreshold

        var resolved = current

        if atMinX || atMaxX {
            let unclampedX = latestMousePosition.x + deltaX
            let minX = bounds.minX - maxOffset
            let maxX = bounds.maxX + maxOffset

            resolved.x = min(max(unclampedX, minX), maxX)

        } else if atMinY || atMaxY {
            let unclampedY = latestMousePosition.y + deltaY
            let minY = bounds.minY - maxOffset
            let maxY = bounds.maxY + maxOffset

            resolved.y = min(max(unclampedY, minY), maxY)
        }

        latestMousePosition = resolved
        return resolved
    }

    private func activateNextCycleAction(_ event: CGEvent) -> ActiveEventMonitor.EventHandling {
        // Ensure that the source originates from the HID state ID.
        // Otherwise, this event was likely sent from Loop to focus the frontmost click (see `Window.focus` which sends a `SLSEvent` to the window)
        let sourceID = CGEventSourceStateID(rawValue: Int32(event.getIntegerValueField(.eventSourceStateID)))
        guard sourceID == .hidSystemState else {
            return .forward
        }

        guard checkIfLoopOpen() else {
            return .forward
        }

        if let pendingRepeatableAction {
            advanceSelectedAction(pendingRepeatableAction)
            self.pendingRepeatableAction = nil
            return .ignore
        }

        pendingRepeatableAction = nil

        guard canSelectNextCycleitem() else {
            return .forward
        }

        advanceSelectedAction(nil)

        return .ignore
    }
}
