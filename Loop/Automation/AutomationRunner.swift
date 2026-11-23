//
//  AutomationRunner.swift
//  Loop
//
//  Created by Kai Azim on 2026-11-22.
//

import AppKit
import Defaults
import Foundation
import Scribe

/// Runs a parsed request, picking windows, screens and cycle steps the way keybinds do
@Loggable
@MainActor
struct AutomationRunner {
    private static let launchedAppWindowTimeout: Duration = .seconds(3)
    private static let launchedAppPollInterval: Duration = .milliseconds(100)

    func response(for request: AutomationRequest) async -> LoopAutomationResponse {
        switch request.command {
        case let .route(.list(subject)):
            listResponse(subject)
        case let .route(.run(target)):
            await run(target, options: request.options)
        case let .legacyNamedAction(name, scope):
            await runKeybind(named: name, scope: scope, options: request.options)
        }
    }

    // MARK: - List

    private func listResponse(_ subject: LoopListSubject) -> LoopAutomationResponse {
        let result: LoopAutomationResult = switch subject {
        case .windows:
            .windowList(LoopWindowListResult(windows: listedWindows().map(Self.windowSummary)))
        case .screens:
            .screenList(LoopScreenListResult(screens: NSScreen.screens.map(Self.screenSummary)))
        case .actions:
            .actionList(
                LoopActionListResult(
                    actions: LoopAutomationCatalog.builtInActions().map {
                        LoopActionSummary(key: $0.direction.automationKey, name: $0.direction.name, category: $0.category)
                    }
                )
            )
        case .keybinds:
            bindingList(.keybind)
        case .gestures:
            bindingList(.gesture)
        case .radialMenu:
            bindingList(.radialMenu)
        }

        return LoopAutomationResponse(result: result)
    }

    private func bindingList(_ kind: LoopBindingKind) -> LoopAutomationResult {
        .bindingList(
            LoopBindingListResult(
                bindingKind: kind,
                bindings: LoopAutomationCatalog().bindings(of: kind).map(\.summary)
            )
        )
    }

    private func listedWindows() -> [Window] {
        WindowUtility.windowList().filter { window in
            guard let app = window.nsRunningApplication else {
                return false
            }

            return app.activationPolicy == .regular
                && !window.isApplicationHidden
                && !window.minimized
        }
    }

    // MARK: - Run

    private func run(_ target: LoopTarget, options: LoopTargetOptions) async -> LoopAutomationResponse {
        switch target {
        case let .action(key):
            guard let direction = LoopAutomationCatalog.builtInAction(named: key) else {
                return .failure(.notFound, message: "Unknown action: \(key)", suggesting: .list(.actions))
            }

            return await run(WindowAction(direction), target: .action(direction.automationKey), options: options)

        case let .binding(kind, id):
            let bindings = LoopAutomationCatalog().bindings(of: kind)
            guard let binding = bindings.first(where: { $0.id?.lowercased() == id.lowercased() }) else {
                return .failure(.notFound, message: "Unknown \(kind.noun): \(id)", suggesting: .list(kind.listSubject))
            }

            guard let action = binding.action, !action.direction.isNoOp else {
                return .failure(.failed, message: "\(target) doesn’t run an action")
            }

            return await run(action, target: target, options: options)
        }
    }

    /// Runs the first keybind with this name, like `action/<name>` and `keybind/<name>` did.
    /// `action/` only matched custom and stash actions by name, so a cycle can't take over a built-in action's name.
    private func runKeybind(named name: String, scope: AutomationRequest.LegacyNameScope, options: LoopTargetOptions) async -> LoopAutomationResponse {
        let bindings = LoopAutomationCatalog().keyBindings.filter { binding in
            scope == .keybinds || binding.action?.direction.isCustomizable == true
        }
        if let binding = bindings.first(where: { $0.action?.name?.lowercased() == name.lowercased() }),
           let target = binding.target {
            return await run(target, options: options)
        }

        if scope == .customOrBuiltIn, let direction = LoopAutomationCatalog.builtInAction(named: name) {
            return await run(.action(direction.automationKey), options: options)
        }

        return .failure(.notFound, message: "Unknown keybind: \(name)", suggesting: .list(.keybinds))
    }

    private func run(_ action: WindowAction, target: LoopTarget, options: LoopTargetOptions) async -> LoopAutomationResponse {
        // Like keybinds, which don't open Loop without it
        guard AccessibilityManager.shared.isGranted else {
            return .failure(.unavailable, message: "Loop needs Accessibility access to move windows. Grant it in System Settings, then try again.")
        }

        let window: Window?
        switch await resolveWindow(options: options) {
        case let .success(resolved):
            window = resolved
        case let .failure(error):
            return LoopAutomationResponse(error: error)
        }

        switch WindowUtility.rejection(for: window) {
        case .appExcluded:
            return .failure(.excludedApp, message: "\(window?.nsRunningApplication?.localizedName ?? "This app") is excluded in Loop’s settings")
        case .fullscreenWindow:
            return .failure(.fullscreenWindow, message: "The window is in full screen, and Loop is set to ignore those")
        case nil:
            break
        }

        guard let resolvedAction = await resolveCycle(action, for: window), !resolvedAction.direction.isNoOp else {
            return .failure(.failed, message: "\(target) has nothing to run")
        }

        if window == nil, !resolvedAction.direction.willFocusWindow {
            return .failure(.noWindow, message: "No window to act on")
        }

        let screen: NSScreen
        switch resolveScreen(for: resolvedAction, window: window, options: options) {
        case let .success(resolved):
            screen = resolved
        case let .failure(error):
            return LoopAutomationResponse(error: error)
        }

        // The engine has no frame for screen switching actions. Like keybinds, a cycle goes on to its next action on the new screen,
        // and otherwise the window keeps what it looks like now.
        var appliedAction = resolvedAction
        if resolvedAction.direction.willChangeScreen, let window {
            if let nextAction = Self.cycleAction(after: resolvedAction, in: action) {
                appliedAction = nextAction
            } else if let currentScreen = ScreenUtility.screen(for: resolvedAction, window: window) {
                appliedAction = await ScreenUtility.actionAfterScreenSwitch(for: window, from: currentScreen)
            }
        }

        log.info("Running \(target) (\(appliedAction)) on \(window?.description ?? "no window")")

        let result: WindowActionEngine.Result
        do {
            result = try await WindowActionEngine.shared.apply(appliedAction, window: window, screen: screen)
        } catch {
            return .failure(.failed, message: "Couldn’t run \(target): \(error.localizedDescription)")
        }

        guard result.success else {
            let message = if appliedAction.direction.willFocusWindow {
                "No window to focus in that direction"
            } else if appliedAction.direction.spaceDestination != nil {
                "There’s no desktop to move the window to"
            } else {
                "Couldn’t run \(target)"
            }
            return .failure(.failed, message: message)
        }

        let actedOn = result.newTargetWindow ?? window
        return LoopAutomationResponse(
            result: .run(
                LoopRunResult(
                    target: target.description,
                    action: LoopAutomationCatalog.boundAction(action),
                    window: actedOn.map(Self.windowSummary)
                )
            )
        )
    }

    /// The action after a cycle's screen switching action, unless it switches screens too, which keybinds also stop at
    static func cycleAction(after action: WindowAction, in cycle: WindowAction) -> WindowAction? {
        guard cycle.direction == .cycle,
              let actions = cycle.cycle,
              let index = actions.firstIndex(where: { $0.id == action.id })
        else {
            return nil
        }

        let next = actions[(index + 1) % actions.count]
        return next.direction.willChangeScreen || next.direction.isNoOp ? nil : next
    }

    private func resolveCycle(_ action: WindowAction, for window: Window?) async -> WindowAction? {
        guard action.direction == .cycle else {
            return action
        }

        let context = ResizeContext(window: window)
        await context.refreshResolvedState()

        // Each command is a new session, like a separate keybind press, so this follows the same setting
        guard let proposal = context.proposeCycleAction(
            in: action,
            restartAtBeginningWhenInterrupted: Defaults[.cycleModeRestartEnabled],
            mode: .advance(.forward)
        ) else {
            return nil
        }

        return context.commitCycleAction(proposal, in: action)
    }

    // MARK: - Window and Screen

    private func resolveWindow(options: LoopTargetOptions) async -> Result<Window?, LoopAutomationError> {
        if let windowID = options.windowID {
            guard let window = try? Window.fromWindowID(windowID) else {
                return .failure(LoopAutomationError(.notFound, message: "No window found with ID \(windowID)", suggesting: .list(.windows)))
            }
            return .success(window)
        }

        if let bundleID = options.bundleID {
            return await resolveWindow(bundleID: bundleID).map { $0 as Window? }
        }

        return .success(WindowUtility.userDefinedTargetWindow())
    }

    private func resolveWindow(bundleID: String) async -> Result<Window, LoopAutomationError> {
        let runningApps = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == bundleID }

        if !runningApps.isEmpty {
            let app = runningApps.first(where: \.isActive) ?? runningApps[0]
            if let window = try? Window(pid: app.processIdentifier) {
                return .success(window)
            }

            return .failure(LoopAutomationError(.noWindow, message: "\(app.localizedName ?? bundleID) has no open windows"))
        }

        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return .failure(LoopAutomationError(.notFound, message: "No app found with bundle ID \(bundleID)"))
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        let app: NSRunningApplication
        do {
            app = try await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
        } catch {
            return .failure(LoopAutomationError(.failed, message: "Couldn’t open \(bundleID): \(error.localizedDescription)"))
        }

        let clock = ContinuousClock()
        let deadline = clock.now + Self.launchedAppWindowTimeout

        while clock.now < deadline {
            if let window = try? Window(pid: app.processIdentifier) {
                return .success(window)
            }

            do {
                try await Task.sleep(for: Self.launchedAppPollInterval)
            } catch {
                break
            }
        }

        return .failure(LoopAutomationError(.noWindow, message: "\(app.localizedName ?? bundleID) opened, but didn’t show a window in time"))
    }

    private func resolveScreen(
        for action: WindowAction,
        window: Window?,
        options: LoopTargetOptions
    ) -> Result<NSScreen, LoopAutomationError> {
        if action.direction.willChangeScreen {
            guard options.screenID == nil else {
                return .failure(LoopAutomationError(.invalidRequest, message: "\(action.direction.automationKey) picks its own screen, so it can’t be combined with a screen ID"))
            }

            guard window != nil,
                  let currentScreen = ScreenUtility.screen(for: action, window: window),
                  let targetScreen = ScreenUtility.targetScreen(for: action.direction, from: currentScreen)
            else {
                return .failure(LoopAutomationError(.failed, message: "No other screen to move to"))
            }

            return .success(targetScreen)
        }

        if let screenID = options.screenID {
            guard let screen = NSScreen.screens.first(where: { $0.displayID == screenID }) else {
                return .failure(LoopAutomationError(.notFound, message: "No screen found with ID \(screenID)", suggesting: .list(.screens)))
            }
            return .success(screen)
        }

        guard let screen = ScreenUtility.screen(for: action, window: window) else {
            return .failure(LoopAutomationError(.failed, message: "No screen found"))
        }

        return .success(screen)
    }

    // MARK: - Summaries

    private static func windowSummary(_ window: Window) -> LoopWindowSummary {
        let app = window.nsRunningApplication
        return LoopWindowSummary(
            id: window.cgWindowID,
            bundleID: app?.bundleIdentifier,
            appName: app?.localizedName,
            title: window.title,
            frame: LoopRect(window.frame)
        )
    }

    private static func screenSummary(_ screen: NSScreen) -> LoopScreenSummary {
        LoopScreenSummary(
            id: screen.displayID ?? 0,
            name: screen.localizedName,
            frame: LoopRect(screen.frame),
            isMain: screen == NSScreen.main
        )
    }
}

extension LoopAutomationResponse {
    static func failure(_ code: LoopAutomationErrorCode, message: String, suggesting replacement: LoopRoute? = nil) -> Self {
        Self(error: LoopAutomationError(code, message: message, suggesting: replacement))
    }
}
