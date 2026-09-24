//
//  WindowActionEngine.swift
//  Loop
//
//  Created by Kai Azim on 2023-06-16.
//

import Defaults
import Scribe
import SwiftUI

/// Unified entry point for executing all window actions.
///
/// `WindowActionEngine` consolidates action execution logic previously scattered across
/// `WindowEngine`, `LoopManager`, and other files. It routes actions to appropriate handlers
/// and returns a result indicating success and any state changes.
///
/// **Note:** Screen change actions (`nextScreen`, `previousScreen`, etc.) are NOT handled here.
/// They are resolved by `LoopManager` which updates `resizeContext.screen` before calling `apply()`.
@Loggable
final class WindowActionEngine {
    static let shared = WindowActionEngine()

    @MainActor
    private var actionTasks: [CGWindowID: Task<Result, any Error>] = [:]

    /// Result of applying a window action
    struct Result {
        /// Whether the action was successfully applied
        let success: Bool
        /// For focus actions that change the target window
        let newTargetWindow: Window?

        static let noOp = Result(success: true, newTargetWindow: nil)
        static let failed = Result(success: false, newTargetWindow: nil)
        static let resized = Result(success: true, newTargetWindow: nil)

        static func focused(_ window: Window?) -> Result {
            Result(success: window != nil, newTargetWindow: window)
        }
    }

    /// Simplified apply for callers that don't need resize context tracking (URL commands, drag snap, etc.)
    ///
    /// - Parameters:
    ///   - action: The action to apply
    ///   - window: The target window
    ///   - screen: The screen to perform the action on
    /// - Returns: Result indicating success and any state changes
    func apply(
        _ action: WindowAction,
        window: Window?,
        screen: NSScreen
    ) async throws -> Result {
        let context = ResizeContext(window: window, screen: screen)
        context.setAction(to: action, parent: nil)
        await context.refreshResolvedState()
        return try await apply(context: context)
    }

    /// Apply a window action with explicit resize context tracking.
    /// The context should be updated by the caller before calling this function.
    ///
    /// - Parameters:
    ///   - action: The action to apply
    ///   - window: The target window (can be nil for some actions like focus navigation from screen center)
    ///   - resizeContext: Context containing tracking state for grow/shrink actions (passed by value, caller updates)
    /// - Returns: Result indicating success and any state changes
    /// - Throws: `CancellationError` if a new action is applied to the same window
    @concurrent
    func apply(context: ResizeContext) async throws -> Result {
        guard let windowID = context.window?.cgWindowID else {
            return try await performApply(context: context)
        }

        // Cancel any existing action on this window
        await actionTasks[windowID]?.cancel()

        // Create a task for this action
        let task = Task {
            let result = try await performApply(context: context)
            try Task.checkCancellation()
            return result
        }
        await MainActor.run {
            actionTasks[windowID] = task
        }

        // Await the task and clean up
        let result = try await task.value

        await MainActor.run {
            _ = actionTasks.removeValue(forKey: windowID)
        }

        return result
    }

    private func performApply(context: ResizeContext) async throws -> Result {
        log.info("Applying context: \(context)")

        let direction = context.action.direction

        // No-op actions: return early
        if direction.isNoOp || direction == .cycle {
            return .noOp
        }

        // Focus actions: find and focus the target window
        if direction.willFocusWindow {
            return await handleFocusAction(context.action, currentWindow: context.window)
        }

        // Cross-space throws
        if let window = context.window, let destination = direction.spaceDestination {
            await throwWindow(window, to: destination)
            return .noOp
        }

        if direction == .stash,
           let screen = context.screen,
           await StashManager.shared.toggleStashedWindow(for: context.action, on: screen) {
            return .noOp
        }

        // Quick actions that don't require resize logic
        if let result = handleQuickAction(context.action, window: context.window) {
            return result
        }

        try await WindowEngine.performResize(context: context)
        return .resized
    }

    // MARK: - Focus Actions

    @concurrent
    func resolveFocusTarget(_ action: WindowAction, currentWindow: Window?) async -> Window? {
        if action.direction == .focusNextInStack {
            WindowUtility.nextStackedWindow(from: currentWindow)
        } else if let focusDirection = action.direction.focusDirection {
            WindowUtility.directionalWindow(from: currentWindow, direction: focusDirection)
        } else {
            nil
        }
    }

    private func handleFocusAction(_ action: WindowAction, currentWindow: Window?) async -> Result {
        let newTargetWindow = await resolveFocusTarget(action, currentWindow: currentWindow)

        if let newTargetWindow {
            Task { @MainActor in
                log.info("Focusing window: \(newTargetWindow.description)")
                newTargetWindow.focus()
            }
        }

        return .focused(newTargetWindow)
    }

    // MARK: - Quick Actions

    /// Handles quick actions that don't require the full resize flow.
    /// Returns nil if the action is not a quick action.
    private func handleQuickAction(_ action: WindowAction, window: Window?) -> Result? {
        guard let window else {
            // Quick actions require a window
            if [.hide, .minimize, .fullscreen, .minimizeOthers].contains(action.direction) {
                log.info("Cannot apply quick action without a target window")
                return .failed
            }
            return nil
        }

        switch action.direction {
        case .hide:
            window.toggleHidden()
            return .noOp
        case .minimize:
            window.toggleMinimized()
            return .noOp
        case .fullscreen:
            window.toggleFullscreen()
            return .noOp
        case .minimizeOthers:
            minimizeOtherWindows(exceptWindow: window)
            return .noOp
        default:
            return nil
        }
    }

    // MARK: - Helpers

    private func minimizeOtherWindows(exceptWindow: Window) {
        let allWindows = WindowUtility.windowList()
        let windowsToMinimize = allWindows.filter {
            $0.cgWindowID != exceptWindow.cgWindowID && !$0.minimized && !$0.isWindowHidden
        }

        log.info("Minimizing \(windowsToMinimize.count) other windows")

        for window in windowsToMinimize {
            window.minimized = true
        }
    }

    // MARK: - Cross-Space Window Throw

    enum SpaceDestination {
        case previousSpace
        case nextSpace
        case desktop(UInt)

        var description: String {
            switch self {
            case .previousSpace: "previous space"
            case .nextSpace: "next space"
            case let .desktop(n): "desktop \(n)"
            }
        }

        var desktopNumber: UInt? {
            if case let .desktop(number) = self {
                return number
            }
            return nil
        }
    }

    private func throwWindow(_ window: Window, to space: SpaceDestination) async {
        guard #available(macOS 14.0, *) else {
            log.error("Cross-space window movement requires macOS 14.0 or later")
            return
        }

        let targetSpace: SkyLightToolBelt.ManagedSpace? = switch space {
        case .previousSpace:
            SkyLightToolBelt.desktopSpace(forWindow: window.cgWindowID, offset: -1)
        case .nextSpace:
            SkyLightToolBelt.desktopSpace(forWindow: window.cgWindowID, offset: 1)
        case let .desktop(number):
            SkyLightToolBelt.desktopSpace(forWindow: window.cgWindowID, desktopNumber: number)
        }

        guard let targetSpace else {
            log.error("Could not resolve target \(space.description) for window \(window.cgWindowID)")
            return
        }

        SkyLightToolBelt.moveWindow(window.cgWindowID, toSpace: targetSpace.id)
    }
}
