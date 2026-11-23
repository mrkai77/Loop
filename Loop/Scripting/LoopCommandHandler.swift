//
//  LoopCommandHandler.swift
//  Loop
//
//  Created by Kami on 06/03/2025.
//

import AppKit
import Defaults
import Foundation
import Scribe

/// Handles Loop automation commands for both the URL scheme and `loop-cli`.
/// Routes are `loop://list/<subject>` and `loop://run/<target>`, with `?windowID=`, `?bundleID=` and `?screenID=`.
@Loggable
@MainActor
final class LoopCommandHandler {
    static let shared = LoopCommandHandler()
    private init() {}

    // MARK: - Types

    enum InvocationSource {
        case urlScheme
        case cli
    }

    struct CommandExecutionResult {
        fileprivate enum Presentation {
            case output(title: String, text: LoopAutomationText)
            case failureAlert(message: String)
        }

        let jsonResponse: String
        /// Only built for the URL scheme, since the CLI only reads `jsonResponse`
        fileprivate let presentation: Presentation?

        @MainActor
        func presentIfNeeded() {
            switch presentation {
            case let .output(title, text):
                CommandOutputWindowManager.shared.show(
                    title: title,
                    text: text,
                    json: jsonResponse
                )
            case let .failureAlert(message):
                let alert = NSAlert()
                alert.messageText = String(localized: "The command couldn’t be run.", comment: "Title of the alert shown when a loop:// URL fails. The reason is shown below it.")
                alert.informativeText = message
                alert.alertStyle = .warning

                let button = alert.addButton(withTitle: String(localized: "OK"))
                if #available(macOS 26.0, *) {
                    button.tintProminence = .primary
                }

                if #available(macOS 14.0, *) {
                    NSApp.activate()
                } else {
                    NSApp.activate(ignoringOtherApps: true)
                }

                if let window = NSApp.keyWindow ?? NSApp.mainWindow {
                    alert.beginSheetModal(for: window)
                } else {
                    alert.runModal()
                }
            case nil:
                return
            }
        }
    }

    /// Parsed from the query string, which the CLI builds from `--window-id`, `--bundle-id` and `--screen-id`
    private struct TargetParams {
        var windowID: CGWindowID?
        var bundleID: String?
        var screenID: CGDirectDisplayID?
    }

    /// A route, plus how it was asked for, so older URLs keep working without being suggested
    private enum Request {
        case route(LoopRoute)
        /// `action/<name>` and `keybind/<name>` from older versions, which matched keybinds by name
        case keybindNamed(String, orBuiltIn: Bool)
    }

    // MARK: - Constants

    private static let listRoutes: [LoopRoute] = LoopListSubject.allCases.map { .list($0) }

    private static let exampleRunRoutes: [LoopRoute] = [
        .run(.action("right-half")),
        .run(.action("next-screen")),
        .run(.binding(.keybind, id: "<id>")),
        .run(.binding(.radialMenu, id: "<id>"))
    ]

    /// How long to wait for an app launched by bundle ID to show a window
    private static let launchedAppWindowTimeout: Duration = .seconds(3)

    // MARK: - Public Methods

    /// Handles incoming `loop://` requests and returns command metadata.
    @discardableResult
    func handle(_ url: URL, source: InvocationSource = .urlScheme) async -> CommandExecutionResult {
        log.info("Processing request: \(url.absoluteString)")

        let result = await withTimeout(LoopAutomationJSON.commandTimeout) {
            await self.process(url, source: source)
        }

        return result ?? makeExecutionResult(
            source: source,
            isRead: false,
            title: nil,
            response: failureResponse(.timeout, message: "Command timed out, so the action may still complete")
        )
    }

    @discardableResult
    func handleRequestURLString(_ request: String, source: InvocationSource) async -> CommandExecutionResult {
        guard let url = URL(string: request) else {
            return makeExecutionResult(
                source: source,
                isRead: false,
                title: nil,
                response: failureResponse(.invalidRequest, message: "Invalid request URL: \(request)")
            )
        }

        return await handle(url, source: source)
    }

    private func process(_ url: URL, source: InvocationSource) async -> CommandExecutionResult {
        guard url.scheme?.lowercased() == "loop",
              let components = LoopRoute.pathComponents(of: url.absoluteString)
        else {
            return makeExecutionResult(
                source: source,
                isRead: false,
                title: nil,
                response: failureResponse(.invalidRequest, message: "URLs must start with loop://")
            )
        }

        let title = components.joined(separator: " ")

        let params: TargetParams
        switch targetParams(from: URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []) {
        case let .success(parsed):
            params = parsed
        case let .failure(error):
            return makeExecutionResult(source: source, isRead: false, title: title, response: LoopAutomationResponse(error: error))
        }

        guard let request = request(from: components) else {
            return makeExecutionResult(source: source, isRead: false, title: title, response: invalidRouteResponse(components))
        }

        let response: LoopAutomationResponse
        let isRead: Bool
        switch request {
        case let .route(.list(subject)):
            response = listResponse(subject)
            isRead = true
        case let .route(.run(target)):
            response = await run(target, params: params, source: source)
            isRead = false
        case let .keybindNamed(name, orBuiltIn):
            response = await runKeybind(named: name, orBuiltIn: orBuiltIn, params: params, source: source)
            isRead = false
        }

        return makeExecutionResult(source: source, isRead: isRead, title: title, response: response)
    }

    /// Present but malformed values are errors, so a typo can't act on some other window
    private func targetParams(from queryItems: [URLQueryItem]) -> Result<TargetParams, LoopAutomationError> {
        /// A parameter without a value, like `?windowID`, is present but empty
        func value(_ name: String) -> String? {
            queryItems.first { $0.name.lowercased() == name.lowercased() }.map { $0.value ?? "" }
        }

        var params = TargetParams()

        if let windowID = value("windowID") {
            guard let parsed = CGWindowID(windowID) else {
                return .failure(LoopAutomationError(.invalidRequest, message: "Invalid window ID: \(windowID)", replacementRoute: LoopRoute.list(.windows).displayString))
            }
            params.windowID = parsed
        }

        if let bundleID = value("bundleID") {
            guard !bundleID.isEmpty else {
                return .failure(LoopAutomationError(.invalidRequest, message: "Empty bundle ID"))
            }
            params.bundleID = bundleID
        }

        if let screenID = value("screenID") {
            guard let parsed = CGDirectDisplayID(screenID) else {
                return .failure(LoopAutomationError(.invalidRequest, message: "Invalid screen ID: \(screenID)", replacementRoute: LoopRoute.list(.screens).displayString))
            }
            params.screenID = parsed
        }

        if params.windowID != nil, params.bundleID != nil {
            return .failure(LoopAutomationError(.invalidRequest, message: "windowID and bundleID can’t be used together"))
        }

        return .success(params)
    }

    /// Returns `nil` if `operation` doesn't finish in time. It keeps running after that, since AX calls can't be cancelled
    private func withTimeout<T: Sendable>(
        _ timeout: Duration,
        _ operation: @escaping @MainActor @Sendable () async -> T
    ) async -> T? {
        await withCheckedContinuation { continuation in
            let race = TimeoutRace(continuation)

            let work = Task { @MainActor in
                await race.finish(with: operation())
            }

            let timer = Task {
                try? await Task.sleep(for: timeout)
                if race.finish(with: nil) {
                    work.cancel()
                }
            }

            Task {
                _ = await work.value
                timer.cancel()
            }
        }
    }

    // MARK: - Routing

    private func request(from components: [String]) -> Request? {
        if let route = LoopRoute(components: components) {
            return .route(route)
        }

        return legacyRequest(from: components)
    }

    /// Routes from before the CLI, which shipped in the URL scheme's documentation
    private func legacyRequest(from components: [String]) -> Request? {
        guard components.count == 2 else {
            return Self.legacyRoute(from: components).map { .route($0) }
        }

        let command = components[0].lowercased()
        let argument = components[1]

        // `direction/` sent names starting with "custom" or "stash" to the custom action lookup, like `action/`
        if command == "direction", ["custom", "stash"].contains(where: argument.lowercased().hasPrefix) {
            return .keybindNamed(argument, orBuiltIn: true)
        }

        if let route = Self.legacyRoute(from: components) {
            return .route(route)
        }

        // These matched keybinds by name, which isn't a route of its own anymore
        switch command {
        case "action":
            return .keybindNamed(argument, orBuiltIn: true)
        case "keybind":
            return .keybindNamed(argument, orBuiltIn: false)
        default:
            return nil
        }
    }

    /// The older routes that map straight onto a current one, like `direction/right`
    static func legacyRoute(from components: [String]) -> LoopRoute? {
        guard components.count == 2 else {
            return nil
        }

        let argument = components[1]

        switch components[0].lowercased() {
        case "direction":
            return WindowDirection.matchingDirectionCommand(argument)
                .map { .run(.action($0.automationKey)) }
        case "screen":
            switch argument.lowercased() {
            case "next": return .run(.action(WindowDirection.nextScreen.automationKey))
            case "previous": return .run(.action(WindowDirection.previousScreen.automationKey))
            default: return nil
            }
        case "list":
            switch argument.lowercased() {
            case "actions", "all": return .list(.actions)
            default: return nil
            }
        default:
            return nil
        }
    }

    // MARK: - List

    private func listResponse(_ subject: LoopListSubject) -> LoopAutomationResponse {
        let result: LoopAutomationResult = switch subject {
        case .windows:
            .windowList(LoopWindowListResult(windows: listedWindows().map(windowSummary)))
        case .screens:
            .screenList(LoopScreenListResult(screens: NSScreen.screens.map(screenSummary)))
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

            return app.bundleIdentifier != Bundle.main.bundleIdentifier
                && app.activationPolicy == .regular
                && !window.isApplicationHidden
                && !window.minimized
        }
    }

    // MARK: - Run

    private func run(_ target: LoopTarget, params: TargetParams, source: InvocationSource) async -> LoopAutomationResponse {
        switch target {
        case let .action(key):
            guard let direction = LoopAutomationCatalog.builtInAction(named: key) else {
                return failureResponse(.notFound, message: "Unknown action: \(key)", replacementRoute: .list(.actions))
            }

            return await run(WindowAction(direction), target: .action(direction.automationKey), params: params, source: source)

        case let .binding(kind, id):
            let bindings = LoopAutomationCatalog().bindings(of: kind)
            guard let binding = bindings.first(where: { $0.id?.lowercased() == id.lowercased() }) else {
                return failureResponse(.notFound, message: "Unknown \(Self.noun(for: kind)): \(id)", replacementRoute: .list(Self.listSubject(for: kind)))
            }

            guard let action = binding.action, !action.direction.isNoOp else {
                return failureResponse(.notFound, message: "\(target) doesn’t run an action")
            }

            return await run(action, target: target, params: params, source: source)
        }
    }

    /// Runs the first keybind with this name, like `action/<name>` and `keybind/<name>` did.
    /// `action/` only matched custom and stash actions by name, so a cycle can't take over a built-in action's name.
    private func runKeybind(named name: String, orBuiltIn: Bool, params: TargetParams, source: InvocationSource) async -> LoopAutomationResponse {
        let bindings = LoopAutomationCatalog().keyBindings.filter { binding in
            !orBuiltIn || binding.action?.direction.isCustomizable == true
        }
        if let binding = bindings.first(where: { $0.action?.name?.lowercased() == name.lowercased() }),
           let target = binding.target {
            return await run(target, params: params, source: source)
        }

        if orBuiltIn, let direction = LoopAutomationCatalog.builtInAction(named: name) {
            return await run(.action(direction.automationKey), params: params, source: source)
        }

        return failureResponse(.notFound, message: "Unknown keybind: \(name)", replacementRoute: .list(.keybinds))
    }

    /// Picks the window and screen the way keybinds do, unless the request names them
    private func run(_ action: WindowAction, target: LoopTarget, params: TargetParams, source: InvocationSource) async -> LoopAutomationResponse {
        let window: Window?
        switch await resolveWindow(params: params, canLaunchApps: source == .cli) {
        case let .success(resolved):
            window = resolved
        case let .failure(error):
            return LoopAutomationResponse(error: error)
        }

        if let window {
            guard !window.isAppExcluded else {
                return failureResponse(.excludedApp, message: "\(appName(of: window)) is excluded in Loop’s settings")
            }

            guard !(window.fullscreen && Defaults[.ignoreFullscreen]) else {
                return failureResponse(.fullscreenWindow, message: "The window is in full screen, and Loop is set to ignore those")
            }
        }

        guard let resolvedAction = await resolveCycle(action, for: window), !resolvedAction.direction.isNoOp else {
            return failureResponse(.failed, message: "\(target) has nothing to run")
        }

        if window == nil, !resolvedAction.direction.willFocusWindow {
            return failureResponse(.noWindow, message: "No window to act on")
        }

        let screen: NSScreen
        switch resolveScreen(for: resolvedAction, window: window, params: params) {
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
            } else if let currentScreen = ScreenUtility.screenContaining(window) ?? NSScreen.main {
                appliedAction = await LoopManager.actionAfterScreenSwitch(for: window, from: currentScreen)
            }
        }

        log.info("Running \(target) (\(appliedAction)) on \(window?.description ?? "no window")")

        let result: WindowActionEngine.Result
        do {
            result = try await WindowActionEngine.shared.apply(appliedAction, window: window, screen: screen)
        } catch {
            return failureResponse(.failed, message: "Couldn’t run \(target): \(error.localizedDescription)")
        }

        guard result.success else {
            let message = if appliedAction.direction.willFocusWindow {
                "No window to focus in that direction"
            } else if appliedAction.direction.spaceDestination != nil {
                "There’s no desktop to move the window to"
            } else {
                "Couldn’t run \(target)"
            }
            return failureResponse(.failed, message: message)
        }

        let actedOn = result.newTargetWindow ?? window
        return LoopAutomationResponse(
            result: .run(
                LoopRunResult(
                    target: target.description,
                    action: LoopAutomationCatalog.boundAction(action),
                    window: actedOn.map(windowSummary)
                )
            )
        )
    }

    /// The action after a cycle's screen switching action, unless it switches screens too, which keybinds also stop at
    private static func cycleAction(after action: WindowAction, in cycle: WindowAction) -> WindowAction? {
        guard cycle.direction == .cycle,
              let actions = cycle.cycle,
              let index = actions.firstIndex(where: { $0.id == action.id })
        else {
            return nil
        }

        let next = actions[(index + 1) % actions.count]
        return next.direction.willChangeScreen || next.direction.isNoOp ? nil : next
    }

    /// Picks the cycle's next action the way Loop's keybinds do, continuing from the window's current action
    private func resolveCycle(_ action: WindowAction, for window: Window?) async -> WindowAction? {
        guard action.direction == .cycle else {
            return action
        }

        let context = ResizeContext(window: window)
        await context.refreshResolvedState()

        // Each command is its own session, so restarting would always pick the first action
        guard let proposal = context.proposeCycleAction(
            in: action,
            restartAtBeginningWhenInterrupted: false,
            mode: .advance(.forward)
        ) else {
            return nil
        }

        return context.commitCycleAction(proposal, in: action)
    }

    // MARK: - Window and Screen

    /// With no window named, uses the user's "Target window" setting like keybinds do
    private func resolveWindow(params: TargetParams, canLaunchApps: Bool) async -> Result<Window?, LoopAutomationError> {
        if let windowID = params.windowID {
            guard let window = try? Window.fromWindowID(windowID) else {
                return .failure(LoopAutomationError(.notFound, message: "No window found with ID \(windowID)", replacementRoute: LoopRoute.list(.windows).displayString))
            }
            return .success(window)
        }

        if let bundleID = params.bundleID {
            return await resolveWindow(bundleID: bundleID, canLaunchApps: canLaunchApps).map { $0 as Window? }
        }

        return .success(WindowUtility.userDefinedTargetWindow())
    }

    /// Only the CLI launches apps, so a `loop://` link can't open one
    private func resolveWindow(bundleID: String, canLaunchApps: Bool) async -> Result<Window, LoopAutomationError> {
        let runningApps = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == bundleID }

        if !runningApps.isEmpty {
            // Prefer the frontmost instance when there's more than one
            let app = runningApps.first(where: \.isActive) ?? runningApps[0]
            if let window = try? Window(pid: app.processIdentifier) {
                return .success(window)
            }

            return .failure(LoopAutomationError(.noWindow, message: "\(app.localizedName ?? bundleID) has no open windows"))
        }

        guard canLaunchApps else {
            return .failure(LoopAutomationError(.notFound, message: "\(bundleID) isn’t running"))
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
                try await Task.sleep(for: .milliseconds(100))
            } catch {
                break
            }
        }

        return .failure(LoopAutomationError(.noWindow, message: "\(app.localizedName ?? bundleID) opened, but didn’t show a window in time"))
    }

    /// Like keybinds: the screen with the cursor (or the main screen), and for screen-changing actions, the one next to the window's
    private func resolveScreen(for action: WindowAction, window: Window?, params: TargetParams) -> Result<NSScreen, LoopAutomationError> {
        if action.direction.willChangeScreen {
            guard params.screenID == nil else {
                return .failure(LoopAutomationError(.invalidRequest, message: "\(action.direction.automationKey) picks its own screen, so it can’t be combined with a screen ID"))
            }

            guard let window,
                  let currentScreen = ScreenUtility.screenContaining(window) ?? NSScreen.main,
                  let targetScreen = ScreenUtility.targetScreen(for: action.direction, from: currentScreen)
            else {
                return .failure(LoopAutomationError(.failed, message: "No other screen to move to"))
            }

            return .success(targetScreen)
        }

        if let screenID = params.screenID {
            guard let screen = NSScreen.screens.first(where: { $0.displayID == screenID }) else {
                return .failure(LoopAutomationError(.notFound, message: "No screen found with ID \(screenID)", replacementRoute: LoopRoute.list(.screens).displayString))
            }
            return .success(screen)
        }

        guard let screen = Defaults[.useScreenWithCursor] ? NSScreen.screenWithMouse : NSScreen.main else {
            return .failure(LoopAutomationError(.failed, message: "No screen found"))
        }

        return .success(screen)
    }

    // MARK: - Responses

    /// Explains why `components` isn't a valid route
    private func invalidRouteResponse(_ components: [String]) -> LoopAutomationResponse {
        guard let command = components.first?.lowercased() else {
            return failureResponse(.invalidRequest, message: "No command given", availableRoutes: Self.listRoutes + Self.exampleRunRoutes)
        }

        let arguments = components.dropFirst()

        switch command {
        case "list":
            return failureResponse(
                .invalidRequest,
                message: arguments.isEmpty ? "No list type given" : "Unknown list type: \(arguments.joined(separator: "/"))",
                availableRoutes: Self.listRoutes
            )
        case "run":
            return failureResponse(
                .invalidRequest,
                message: arguments.isEmpty ? "No action given" : "Invalid action: \(arguments.joined(separator: "/"))",
                availableRoutes: Self.exampleRunRoutes
            )
        default:
            return failureResponse(.invalidRequest, message: "Unknown command: \(command)", availableRoutes: Self.listRoutes + Self.exampleRunRoutes)
        }
    }

    private func failureResponse(
        _ code: LoopAutomationErrorCode,
        message: String,
        replacementRoute: LoopRoute? = nil,
        availableRoutes: [LoopRoute] = []
    ) -> LoopAutomationResponse {
        LoopAutomationResponse(
            error: LoopAutomationError(
                code,
                message: message,
                replacementRoute: replacementRoute?.displayString,
                availableRoutes: availableRoutes.isEmpty ? nil : availableRoutes.map(\.displayString)
            )
        )
    }

    private func makeExecutionResult(
        source: InvocationSource,
        isRead: Bool,
        title: String?,
        response: LoopAutomationResponse
    ) -> CommandExecutionResult {
        let jsonResponse = LoopAutomationJSON.encodeString(response)

        guard source == .urlScheme else {
            return CommandExecutionResult(jsonResponse: jsonResponse, presentation: nil)
        }

        let presentation: CommandExecutionResult.Presentation? = if isRead {
            .output(
                title: outputTitle(for: title),
                text: response.result.map { LoopAutomationFormatter().format($0) }
                    ?? LoopAutomationText(response.error?.message ?? jsonResponse)
            )
        } else {
            response.error.map { .failureAlert(message: $0.message) }
        }

        return CommandExecutionResult(jsonResponse: jsonResponse, presentation: presentation)
    }

    private func outputTitle(for command: String?) -> String {
        guard let command, !command.isEmpty else {
            return String(localized: "Loop Output", comment: "Title of the window that shows the result of a loop:// list URL.")
        }

        return String(localized: "Loop Output: \(command)", comment: "Title of the window that shows the result of a loop:// list URL. %@ is the command that was run, such as “list windows”.")
    }

    // MARK: - Summaries

    private func windowSummary(_ window: Window) -> LoopWindowSummary {
        let app = window.nsRunningApplication
        return LoopWindowSummary(
            id: window.cgWindowID,
            bundleID: app?.bundleIdentifier,
            appName: app?.localizedName,
            title: window.title,
            frame: LoopRect(window.frame)
        )
    }

    private func screenSummary(_ screen: NSScreen) -> LoopScreenSummary {
        LoopScreenSummary(
            id: screen.displayID ?? 0,
            name: screen.localizedName,
            frame: LoopRect(screen.frame),
            isMain: screen == NSScreen.main
        )
    }

    private func appName(of window: Window) -> String {
        window.nsRunningApplication?.localizedName ?? "This app"
    }

    private static func noun(for kind: LoopBindingKind) -> String {
        switch kind {
        case .keybind: "keybind"
        case .gesture: "gesture"
        case .radialMenu: "radial menu action"
        }
    }

    private static func listSubject(for kind: LoopBindingKind) -> LoopListSubject {
        switch kind {
        case .keybind: .keybinds
        case .gesture: .gestures
        case .radialMenu: .radialMenu
        }
    }
}

extension WindowDirection {
    /// Also accepts `left`, `right`, `top` and `bottom` for the halves, like `loop://direction/` always has
    static func matchingDirectionCommand(_ name: String) -> WindowDirection? {
        if let direction = matching(name) {
            return direction
        }

        switch name.lowercased() {
        case "left": return .leftHalf
        case "right": return .rightHalf
        case "top": return .topHalf
        case "bottom": return .bottomHalf
        default: return matching(name.lowercased().replacingOccurrences(of: "half", with: ""))
        }
    }
}

/// Resumes a continuation with whichever of the operation or the timeout finishes first
private final class TimeoutRace<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T?, Never>?

    init(_ continuation: CheckedContinuation<T?, Never>) {
        self.continuation = continuation
    }

    @discardableResult
    func finish(with value: T?) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard let continuation else {
            return false
        }

        self.continuation = nil
        continuation.resume(returning: value)
        return true
    }
}
