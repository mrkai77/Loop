//
//  StashManager.swift
//  Loop
//
//  Created by Guillaume Clédat on 22/05/2025.
//

import Defaults
import Scribe
import SwiftUI

/// Manages the behavior of windows that can be temporarily hidden (stashed) and revealed on screen edges.
///
/// `StashManager` orchestrates a system for "stashing" windows by moving them to the edge of a screen,
/// revealing them when the mouse approaches, and hiding them again when the mouse leaves. It handles:
/// - Window stashing logic: deciding where and how to stash windows, and ensuring non-overlapping placements.
/// - Reveal/hide logic: dynamically revealing stashed windows when the mouse is nearby, and hiding them otherwise.
/// - Input events: listens to mouse movements to manage reveal/hide behavior efficiently.
/// - Cleanup and restore: restores windows when the app terminates or when a window is explicitly unstashed.
///
/// ## Key Features:
/// - Configurable animations for reveal/hide behaviors (see `Defaults[.animateStashedWindows]`).
/// - Configurable visibility padding to determine how much of a stashed window remains visible (see `Defaults[.stashedWindowVisiblePadding]`).
/// - Smart handling of overlapping stashed windows along the same screen edge, using vertical range tolerance.
/// - Debounced and throttled mouse movement handling to avoid performance issues.
/// - Automatic focus-shifting to another window when a window is hidden (optional) (see `Defaults[.shiftFocusWhenStashed]`).
///
/// ## Constants:
/// - `mouseMovedDebounceInterval`: The minimum time interval (in seconds) between processing consecutive mouse move events.
/// - `revealThrottleInterval`: The minimum time interval (in seconds) between revealing or hiding actions for a specific window.
/// - `minimumVisibleHeightToKeepWindowStacked`:
///     - The minimum required visible vertical height (in points) between two stashed windows on the same screen edge.
///     - Ensures that multiple stashed windows do not overlap too much vertically.
///     - Allows the user to move the mouse into the stash area and target a specific window, even if windows are stacked.
///
/// ## Considerations:
/// - Currently supports only one revealed window at a time.
@Loggable
@MainActor
final class StashManager {
    static let shared = StashManager()
    private init() {}

    /// Should the stashed windows be animated when revealed or hidden?
    private var animate: Bool {
        Defaults[.animateStashedWindows]
    }

    /// How many pixels of the window should be visible when stashed
    var stashedWindowVisiblePadding: CGFloat {
        Defaults[.stashedWindowVisiblePadding]
    }

    private var shiftFocusWhenStashed: Bool {
        Defaults[.shiftFocusWhenStashed]
    }

    /// The time interval to debounce mouse moved events to avoid excessive processing.
    private let mouseMovedDebounceInterval: TimeInterval = 0.05

    /// The throttle interval for revealing/hiding windows when the mouse moves.
    private let revealThrottleInterval: TimeInterval = 0.1

    /// Two windows can be stacked along the same edge of the screen as long as there is enough non-overlapping space
    /// to allow the user to easily position the cursor over either window.
    /// This applies to vertical space for horizontal edges (left/right) and horizontal space for vertical edges (bottom).
    private let minimumVisibleSizeToKeepWindowStacked: CGFloat = 100

    private lazy var store: StashedWindowsStore = {
        let store = StashedWindowsStore()
        store.delegate = self
        return store
    }()

    private var lastRevealTime: [CGWindowID: Date] = [:]
    private var mouseMonitor: PassiveEventMonitor?
    private var frontmostAppMonitor: Task<(), Never>?
    private var mouseMovedTask: Task<(), Never>?
    private var transitionIDs: [CGWindowID: UUID] = [:]

    // MARK: - Public methods

    func start() {
        Task {
            await store.restore()
        }
    }

    func onWindowManipulated(_ id: CGWindowID) {
        unmanage(windowID: id)
    }

    /// Cancels all monitoring and restores every stashed window to its initial frame.
    func shutdown() {
        mouseMovedTask?.cancel()
        mouseMovedTask = nil
        stopListeningToRevealTriggers()
        restoreAllStashedWindows()
    }

    func onConfigurationChanged() async {
        let stashedWindows = Array(store.stashed.values)

        for stashedWindow in stashedWindows {
            let updated = await stashedWindow.updatingStashedFrame(peekSize: stashedWindowVisiblePadding)

            store.setStashedWindow(cgWindowID: updated.window.cgWindowID, to: updated)

            // Don't animate when configuration changes
            await updated.window.setFrame(updated.stashedFrame)
        }
    }

    /// Returns the stashed window matching the given action and screen, if one exists.
    func stashedWindow(for action: WindowAction, on screen: NSScreen) -> StashedWindowInfo? {
        guard action.direction == .stash,
              let stashedWindow = store.stashedWindow(for: action, on: screen),
              !stashedWindow.window.isWindowHidden, !stashedWindow.window.isApplicationHidden
        else {
            return nil
        }

        return stashedWindow
    }

    /// Toggles the stashed window matching the given action and screen, if one exists.
    @discardableResult
    func toggleStashedWindow(for action: WindowAction, on screen: NSScreen) async -> Bool {
        guard let stashedWindow = stashedWindow(for: action, on: screen) else {
            return false
        }

        log.info("Toggling stashed window \(stashedWindow.window.description)")

        if store.isWindowRevealed(stashedWindow.window.cgWindowID) {
            await hideWindow(stashedWindow)
        } else {
            await revealWindow(stashedWindow)
        }

        return true
    }

    func getRevealedFrameForStashedWindow(id: CGWindowID) async -> CGRect? {
        store.stashed[id]?.revealedFrame
    }
}

// MARK: - StashedWindowsStoreDelegate

extension StashManager: StashedWindowsStoreDelegate {
    func onStashedWindowsRestored() {
        if !store.stashed.isEmpty {
            startListeningToRevealTriggers()
        }
    }
}

// MARK: - Stash and Unstash

extension StashManager {
    /// Handles `windowResized` notification for the specified window and action.
    func onWindowResized(action: WindowAction, window: Window, screen: NSScreen) async {
        if let edge = action.stashEdge {
            // Treat all screens as a unified virtual space. `getScreenForEdge` determines the appropriate screen based on the edge:
            // the leftmost screen for `.left` or the rightmost screen for `.right`. If the window's current screen differs from the target screen,
            // the function recursively adjusts the window's position to ensure it is stashed on the correct screen.
            if let screenForEdge = getScreenForEdge(currentScreen: screen, edge: edge), screen != screenForEdge {
                log.info("Attempting to stash window on the \(edge.debugDescription) edge, but \(screen.localizedName) is not the \(edge.debugDescription)most screen. Redirecting to the correct screen.")
                await onWindowResized(action: action, window: window, screen: screenForEdge)
            } else {
                let windowToStash = await StashedWindowInfo.create(
                    window: window,
                    screen: screen,
                    action: action,
                    peekSize: stashedWindowVisiblePadding
                )

                await stash(windowToStash)
            }
        } else if action.direction == .unstash {
            // No need to reset the frame here: the frame has already been moved to the stash area
            // by the code that sent the windowResized notification.
            await unstash(window.cgWindowID, resetFrame: false, resetFrameAnimated: animate)
        } else if action.direction == .undo {
            guard let action = await WindowRecords.shared.getCurrentAction(for: window) else { return }
            guard action.direction != .undo else { return }

            await onWindowResized(action: action, window: window, screen: screen)
        } else if action.direction.willGrow
            || action.direction.willShrink
            || action.direction.willAdjustSize {
            // Grow, shrink, or adjustSize actions won't work for predefined stash actions, since they have a custom size.

            // If the window’s frame is updated while it’s stashed and hidden, the update will cause the window to move back on-screen
            // without adding its id to `store.revealed`. We need to add it back so the hide animation can be triggered.
            if let stashedWindow = store.stashed[window.cgWindowID] {
                let currentScreen = ScreenUtility.screenContaining(window) ?? screen
                let updated = await stashedWindow.updatingFrames(screen: currentScreen, peekSize: stashedWindowVisiblePadding)
                store.setStashedWindow(cgWindowID: window.cgWindowID, to: updated)

                // If the window frame is fully on screen while the window ID is not in the `store.revealed` set, we add it.
                let isWindowFullyOnScreen = currentScreen.cgSafeScreenFrame.contains(window.frame)

                if isWindowFullyOnScreen, !store.isWindowRevealed(window.cgWindowID) {
                    store.markWindowAsRevealed(window.cgWindowID)
                }
            }
        } else if action.direction.willMove {
            // Since StashManager recomputes the frame on every show/dismiss, if the user moves a stashed window,
            // the next time the window is shown or hidden, its frame will be reset to its `Direction`.
            // This could be an improvement to consider adding later.
        } else {
            // The window will be moved by another command so it won't be stashed anymore:
            unmanage(windowID: window.cgWindowID)
        }
    }

    /// Add the given `StashWindow` to the list of monitored windows, move the window to the stashed area
    /// and start mouse moved listener if needed.
    private func stash(_ windowToStash: StashedWindowInfo) async {
        log.info("stash \(windowToStash.window.description)")

        await unstashOverlappingWindows(windowToStash)

        store.setStashedWindow(cgWindowID: windowToStash.window.cgWindowID, to: windowToStash)
        await hideWindow(windowToStash, allowUnrevealed: true, shouldThrottle: false)
        startListeningToRevealTriggers()
    }

    /// Stop monitoring the window with the given `CGWindowID`.
    private func unstash(_ windowID: CGWindowID, resetFrame: Bool, resetFrameAnimated: Bool) async {
        if let windowToUnstash = store.stashed[windowID] {
            await unstash(windowToUnstash, resetFrame: resetFrame, resetFrameAnimated: resetFrameAnimated)
        } else {
            unmanage(windowID: windowID)
        }
    }

    /// Stop monitoring the window. If `resetFrame` is true, the window will be moved to its initial frame.
    private func unstash(_ window: StashedWindowInfo, resetFrame: Bool, resetFrameAnimated: Bool) async {
        log.info("unstash \(window.window.description)")

        if resetFrame {
            if resetFrameAnimated {
                try? await window.window.setFrameAnimated(
                    window.restoreFrame,
                    bounds: .zero
                )
            } else {
                await window.window.setFrame(window.restoreFrame)
            }
        }

        unmanage(windowID: window.window.cgWindowID)
    }

    func restoreAllStashedWindows() {
        let stashedWindowIDs = Array(store.stashed.keys)

        for stashedWindowID in stashedWindowIDs {
            unstashSynchronously(stashedWindowID, resetFrame: true)
        }
    }

    private func unstashSynchronously(_ windowID: CGWindowID, resetFrame: Bool) {
        if let windowToUnstash = store.stashed[windowID] {
            unstashSynchronously(windowToUnstash, resetFrame: resetFrame)
        } else {
            unmanage(windowID: windowID)
        }
    }

    private func unstashSynchronously(_ window: StashedWindowInfo, resetFrame: Bool) {
        log.info("unstash \(window.window.description)")

        if resetFrame {
            window.window.setFrameSynchronously(window.restoreFrame)
        }

        unmanage(windowID: window.window.cgWindowID)
    }
}

// MARK: - Reveal and Hide

private extension StashManager {
    /// Reveals a stashed window by moving it to its reveal frame.
    func revealWindow(_ window: StashedWindowInfo) async {
        let windowID = window.window.cgWindowID

        guard !store.isWindowRevealed(windowID) else { return }
        guard !shouldThrottle(windowID: windowID) else { return }

        // Keep only one window as revealed
        for revealedWindowId in store.revealed {
            guard revealedWindowId != windowID else { continue }
            guard let revealedWindow = store.stashed[revealedWindowId] else { break }

            // Run on another thread to prevent this window's reveal from delaying
            Task {
                // No need to unfocus the previously revealed window, since we'll focus our window below anyway
                await hideWindow(revealedWindow, shouldUnfocus: false)
            }
        }

        let transitionID = beginTransition(windowID: windowID, revealed: true)
        let frame = window.revealedFrame

        if shiftFocusWhenStashed {
            Task { @MainActor in
                window.window.focus()
            }
        }

        do {
            if animate {
                try await window.window.setFrameAnimated(
                    frame,
                    bounds: .zero
                )
            } else {
                await window.window.setFrame(frame)
            }
        } catch is CancellationError {
            cancelTransition(windowID: windowID, transitionID: transitionID, fallbackRevealed: false)
            return
        } catch {
            cancelTransition(windowID: windowID, transitionID: transitionID, fallbackRevealed: false)
            log.error("Failed to revealWindow \(window.window.description): \(error.localizedDescription)")
            return
        }

        if finishTransition(windowID: windowID, transitionID: transitionID) {
            log.info("revealWindow \(window.window.description)")
        }
    }

    /// Hides a stashed window by moving it to its stashed frame.
    func hideWindow(_ window: StashedWindowInfo, shouldUnfocus: Bool = true, allowUnrevealed: Bool = false, shouldThrottle: Bool = true) async {
        let windowID = window.window.cgWindowID

        guard allowUnrevealed || store.isWindowRevealed(windowID) else {
            log.warn("Skipping hideWindow because window is not revealed: \(window.window.description)")
            return
        }

        guard !shouldThrottle || !self.shouldThrottle(windowID: windowID) else {
            log.warn("Skipping hideWindow because transition is throttled: \(window.window.description)")
            return
        }

        let transitionID = beginTransition(windowID: windowID, revealed: false)
        let frame = window.stashedFrame

        if shouldUnfocus {
            unfocus(windowID)
        }

        do {
            if animate {
                try await window.window.setFrameAnimated(
                    frame,
                    bounds: .zero
                )
            } else {
                await window.window.setFrame(frame)
            }
        } catch is CancellationError {
            cancelTransition(windowID: windowID, transitionID: transitionID, fallbackRevealed: true)
            return
        } catch {
            cancelTransition(windowID: windowID, transitionID: transitionID, fallbackRevealed: true)
            log.error("Failed to hideWindow \(window.window.description): \(error.localizedDescription)")
            return
        }

        if finishTransition(windowID: windowID, transitionID: transitionID) {
            log.info("hideWindow \(window.window.description)")
        }
    }

    /// Checks if the window reveal / hide should be throttled based on the last reveal time.
    func shouldThrottle(windowID: CGWindowID) -> Bool {
        let now = Date.now
        if let lastTime = lastRevealTime[windowID], now.timeIntervalSince(lastTime) < revealThrottleInterval {
            return true
        }
        lastRevealTime[windowID] = now
        return false
    }

    /// Attempts to unfocus (i.e., shift focus away from) a specified window.
    ///
    /// This method looks for the first (topmost) visible, non-minimized window on the same screen as the specified window,
    /// and tries to activate it (i.e., bring it to the foreground).
    func unfocus(_ windowID: CGWindowID) {
        guard shiftFocusWhenStashed else { return }
        guard let stashedWindow = store.stashed[windowID] else { return }
        guard let screen = ScreenUtility.screenContaining(stashedWindow.window) ?? NSScreen.main else { return }

        let focusWindow = WindowUtility.windowList().first { window in
            guard let currentWindowScreen = ScreenUtility.screenContaining(window) ?? NSScreen.main else { return false }
            guard screen.isSameScreen(currentWindowScreen) else { return false }

            return store.stashed[window.cgWindowID] == nil
                && window.cgWindowID != windowID
                && !window.isApplicationHidden
                && !window.isWindowHidden
                && !window.minimized
        }

        if let focusWindow {
            log.info("Focusing another window on the same screen: \(focusWindow.description).")
            Task { @MainActor in
                focusWindow.focus()
            }
        }
    }
}

// MARK: - Mouse moved listener

private extension StashManager {
    func startListeningToRevealTriggers() {
        guard mouseMonitor == nil else { return }

        log.info("Listening for reveal triggers…")

        let monitor = PassiveEventMonitor(
            "stash_mouse_movement_monitor",
            events: [
                .mouseMoved, // Normal mouse movement
                .leftMouseDragged // Dragging items to stashed windows
            ],
            callback: { [weak self] cgEvent in
                Task { @MainActor in
                    self?.handleMouseMoved(cgEvent: cgEvent)
                }
            }
        )
        monitor.start()
        mouseMonitor = monitor

        frontmostAppMonitor = Task { @MainActor [weak self] in
            guard let self else { return }

            let notifications = NSWorkspace.shared.notificationCenter.notifications(
                named: NSWorkspace.didActivateApplicationNotification
            )

            for await notification in notifications {
                guard !Task.isCancelled else { return }
                processFrontmostAppChange(with: notification)
            }
        }
    }

    func stopListeningToRevealTriggers() {
        guard mouseMonitor != nil else { return }

        log.info("Stopping listening for reveal triggers…")

        // Cancel tasks first
        frontmostAppMonitor?.cancel()
        frontmostAppMonitor = nil

        let monitor = mouseMonitor
        mouseMonitor = nil
        monitor?.stop()
        withExtendedLifetime(monitor) {}
    }

    /// Handles mouse movement events with a debounce to avoid excessive processing.
    private func handleMouseMoved(cgEvent _: CGEvent) {
        mouseMovedTask?.cancel()

        mouseMovedTask = Task {
            try? await Task.sleep(for: .seconds(mouseMovedDebounceInterval))

            guard !Task.isCancelled else {
                return
            }

            await processMouseMovement()
        }
    }

    /// Handles mouse movement events to reveal or hide stashed windows.
    private func processMouseMovement() async {
        let mouseLocation = NSEvent.mouseLocation.flipY(screen: NSScreen.screens[0])
        let windows = getZSortedStashedWindows()

        for window in windows {
            if store.isWindowRevealed(window.window.cgWindowID) {
                if await shouldHide(window: window, for: mouseLocation) {
                    await hideWindow(window)
                } else {
                    break
                }
            } else if await isMouseOverStashed(window: window, location: mouseLocation) {
                // The cursor is over the topmost stashed window that should be revealed
                // revealWindow will move it on screen and hide any other revealed window.
                await revealWindow(window)
                // Only one window can be revealed at a time, so stop processing.
                break
            }
        }
    }

    private func processFrontmostAppChange(with notification: Notification) {
        Task {
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let appWindow = try? Window(pid: app.processIdentifier)
            else {
                return
            }

            let mouseLocation = NSEvent.mouseLocation.flipY(screen: NSScreen.screens[0])
            let windows = getZSortedStashedWindows()

            for window in windows {
                if store.isWindowRevealed(window.window.cgWindowID) {
                    if appWindow.cgWindowID != window.window.cgWindowID,
                       await !isMouseOverStashed(window: window, location: mouseLocation) {
                        await hideWindow(window, shouldUnfocus: false) // No need to unfocus, since the user already did that
                    } else {
                        break
                    }
                } else {
                    if appWindow.cgWindowID == window.window.cgWindowID {
                        // The stashed window has been activated through non-mouse means (e.g. Spotlight, cmd+tab etc.)
                        // revealWindow will move it on screen and hide any other revealed window.
                        await revealWindow(window)
                        // Only one window can be revealed at a time, so stop processing.
                        break
                    }
                }
            }
        }
    }

    /// Returns the list of stashed windows sorted by their z-index (front to back).
    /// This sorting is essential because if multiple stashed windows overlap and the cursor
    /// is over their shared area, we should only reveal the topmost window.
    private func getZSortedStashedWindows() -> [StashedWindowInfo] {
        // Leverage the fact that WindowEngine returns windows sorted by z-index.
        // Map WindowEngine.windowList to store.stashed to retrieve the stashed windows in z-index order.
        WindowUtility.windowList().compactMap { store.stashed[$0.cgWindowID] }
    }

    /// Determines whether a revealed window should be hidden based on the mouse location.
    /// Adds a tolerance to the revealed frame to avoid hiding the window during minor cursor movement and on resize.
    private func shouldHide(window: StashedWindowInfo, for location: CGPoint) async -> Bool {
        // Hide the window if the cursor is neither over the revealedFrame nor the stashedFrame.
        let tolerance: CGFloat = 15
        let revealedFrame = window.revealedFrame.insetBy(dx: -tolerance, dy: -tolerance)
        let stashedFrame = window.stashedFrame
        return !revealedFrame.contains(location) && !stashedFrame.contains(location)
    }

    /// Checks if the mouse is currently hovering over the stashed frame of a window.
    private func isMouseOverStashed(window: StashedWindowInfo, location: CGPoint) async -> Bool {
        window.stashedFrame.contains(location)
    }
}

// MARK: - Overlap logic

private extension StashManager {
    /// Unstashes windows that overlap the newly stashed window, ensuring that all stashed windows on the same edge
    /// have sufficient non-overlapping space to remain individually accessible.
    ///
    /// This function scans all currently stashed windows (excluding the `window` just stashed) and checks for overlap
    /// using `isThereEnoughNonOverlappingSpace`.
    ///
    /// If there is not enough space, the stashed window will be unstashed (i.e., made fully visible and removed from the stash)
    /// and replaced by `windowToStash`
    func unstashOverlappingWindows(_ windowToStash: StashedWindowInfo) async {
        let newFrame = windowToStash.revealedFrame

        for (id, stashedWindow) in store.stashed {
            // windowToStash is already managed by StashManager. Can't overlap with itself.
            guard id != windowToStash.window.cgWindowID else { continue }
            // if windowToStash is not on the same edge of the screen as stashWindow, no need to check for overlap.
            guard windowToStash.action.stashEdge == stashedWindow.action.stashEdge else { continue }

            // Trying to store windowToStash in the same place as stashedWindow.
            // No need for frame comparaison, it will always overlap.
            if stashedWindow.action.id == windowToStash.action.id, stashedWindow.screen.isSameScreen(windowToStash.screen) {
                log.info("Trying to stash a window in the same place as another one. Replacing…")
                await unstash(stashedWindow, resetFrame: true, resetFrameAnimated: animate)
            } else {
                let currentFrame = stashedWindow.stashedFrame
                let tolerance = minimumVisibleSizeToKeepWindowStacked

                if !isThereEnoughNonOverlappingSpace(between: newFrame, and: currentFrame, edge: windowToStash.action.stashEdge, tolerance: tolerance) {
                    log.info("Trying to stash a window overlapping another one. Replacing…")
                    await unstash(stashedWindow, resetFrame: true, resetFrameAnimated: animate)
                }
            }
        }
    }

    /// Determines whether two rectangles have enough non-overlapping space between them.
    ///
    /// This function checks if windows stashed along the same edge have sufficient separation:
    /// - For horizontal edges (left/right): compares vertical ranges (y-axis)
    /// - For vertical edges (bottom): compares horizontal ranges (x-axis)
    ///
    /// - Parameters:
    ///   - rect1: The first rectangle representing a stashed window's frame.
    ///   - rect2: The second rectangle representing another window's frame.
    ///   - edge: The edge where windows are stashed (determines which axis to check).
    ///   - tolerance: The minimum number of pixels that must separate the two windows.
    ///
    /// - Returns: `true` if the two rectangles do not overlap or are separated by at least `tolerance` pixels;
    ///            `false` otherwise.
    func isThereEnoughNonOverlappingSpace(between rect1: CGRect, and rect2: CGRect, edge: StashEdge?, tolerance: CGFloat) -> Bool {
        let range1: ClosedRange<CGFloat>
        let range2: ClosedRange<CGFloat>

        // For horizontal edges (left/right), check vertical overlap
        // For vertical edges (bottom), check horizontal overlap
        if edge?.isHorizontal == true {
            range1 = rect1.minY...rect1.maxY
            range2 = rect2.minY...rect2.maxY
        } else {
            range1 = rect1.minX...rect1.maxX
            range2 = rect2.minX...rect2.maxX
        }

        return areRangesNonOverlappingByAtLeast(tolerance, range1, range2)
    }

    /// Determines if two ranges are either non-overlapping or overlap in such a way
    /// that the shorter range extends at least `tolerance` units beyond the longer range.
    /// - Parameters:
    ///   - tolerance: The minimum required extension (in units) beyond the longer range for an overlap to be acceptable.
    ///   - range1: The first closed range.
    ///   - range2: The second closed range.
    /// - Returns: `true` if the ranges do not overlap, or if the shorter range extends
    ///            at least `tolerance` units either below or above the longer range.
    func areRangesNonOverlappingByAtLeast(_ tolerance: CGFloat, _ range1: ClosedRange<CGFloat>, _ range2: ClosedRange<CGFloat>) -> Bool {
        // Check if ranges do not overlap
        if range1.upperBound < range2.lowerBound || range2.upperBound < range1.lowerBound {
            return true
        }

        // Determine longer and shorter ranges
        let length1 = range1.upperBound - range1.lowerBound
        let length2 = range2.upperBound - range2.lowerBound

        let topRange: ClosedRange<CGFloat>
        let bottomRange: ClosedRange<CGFloat>

        if length1 >= length2 {
            (topRange, bottomRange) = (range1, range2)
        } else {
            (topRange, bottomRange) = (range2, range1)
        }

        // Calculate bottom extension
        let belowExtension = bottomRange.lowerBound < topRange.lowerBound
            ? topRange.lowerBound - bottomRange.lowerBound
            : 0

        // Calculate above extension
        let aboveExtension = bottomRange.upperBound > topRange.upperBound
            ? bottomRange.upperBound - topRange.upperBound
            : 0

        return belowExtension >= tolerance || aboveExtension >= tolerance
    }
}

// MARK: - Helpers

private extension StashManager {
    func isManaged(_ windowID: CGWindowID) -> Bool {
        store.stashed[windowID] != nil
    }

    /// Cleanup references of the given window ID from the stash manager.
    func unmanage(windowID: CGWindowID) {
        store.setStashedWindow(cgWindowID: windowID, to: nil)
        store.markWindowAsRevealed(windowID)
        lastRevealTime.removeValue(forKey: windowID)
        transitionIDs.removeValue(forKey: windowID)

        if store.stashed.isEmpty {
            stopListeningToRevealTriggers()
        }
    }

    func getScreenForEdge(currentScreen: NSScreen, edge: StashEdge) -> NSScreen? {
        // Two screens are considered in the same "row" or "column" if they overlap by at least `threshold` points
        let threshold: CGFloat = 100

        return switch edge {
        case .left:
            currentScreen.leftmostScreenInSameRow(overlapThreshold: threshold)
        case .right:
            currentScreen.rightmostScreenInSameRow(overlapThreshold: threshold)
        case .bottom:
            currentScreen.bottommostScreenInSameColumn(overlapThreshold: threshold)
        }
    }

    func beginTransition(windowID: CGWindowID, revealed: Bool) -> UUID {
        let transitionID = UUID()
        transitionIDs[windowID] = transitionID

        if revealed {
            store.markWindowAsRevealed(windowID)
        } else {
            store.markWindowAsHidden(windowID)
        }

        return transitionID
    }

    @discardableResult
    func finishTransition(windowID: CGWindowID, transitionID: UUID) -> Bool {
        guard transitionIDs[windowID] == transitionID else {
            return false
        }

        transitionIDs.removeValue(forKey: windowID)
        return true
    }

    func cancelTransition(windowID: CGWindowID, transitionID: UUID, fallbackRevealed: Bool) {
        guard finishTransition(windowID: windowID, transitionID: transitionID) else {
            return
        }

        if fallbackRevealed {
            store.markWindowAsRevealed(windowID)
        } else {
            store.markWindowAsHidden(windowID)
        }
    }
}
