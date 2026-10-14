//
//  LoopCommandHandler.swift
//  Loop
//
//  Created by Kami on 06/03/2025.
//

/*
 Loop Automation API
 ===================

 Public URL commands:
 - loop://list/windows
 - loop://list/screens
 - loop://list/actions
 - loop://list/actions/preset
 - loop://list/actions/custom
 - loop://exec/preset/<name>
 - loop://exec/custom/<name>
 - loop://exec/id/<uuid>

 Socket / CLI transport:
 - loop-cli parses CLI arguments locally and sends canonical loop:// URLs over the socket

 Response JSON:
 - success responses use `{ "success": true, "result": { ... } }`
 - failures use `{ "success": false, "error": { "message": "...", ... } }`

 Query parameters:
 - ?windowID=<id>
 - ?bundleID=<id>
 - ?screenID=<id>
 */

import AppKit
import Defaults
import Foundation
import Scribe

/// Handles Loop automation commands for both the URL scheme and `loop-cli`.
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

    enum CommandKind {
        case read
        case write
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
                alert.messageText = String(localized: "The command couldn’t be run.")
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

    /// Parameters parsed from URL query string / CLI flags for targeting specific windows and screens.
    private struct TargetParams {
        var windowID: CGWindowID?
        var bundleID: String?
        var screenID: CGDirectDisplayID?
    }

    private struct ActionDescriptor {
        let action: WindowAction
        let kind: LoopActionKind
        let name: String
        let title: String

        var publicDescriptor: LoopActionDescriptor {
            // Preset actions are rebuilt for every request, so only custom actions have stable IDs
            let id = kind == .custom ? action.id : nil

            return LoopActionDescriptor(
                id: id,
                kind: kind,
                title: title,
                name: name,
                route: LoopRoute.exec(kind, name: name).displayString,
                idRoute: id.map { LoopRoute.execID($0.uuidString.lowercased()).displayString }
            )
        }
    }

    // MARK: - Constants

    private static let listRoutes: [LoopRoute] = [
        .listWindows,
        .listScreens,
        .listActions(.all),
        .listActions(.presetOnly),
        .listActions(.customOnly)
    ]

    private static let exampleExecRoutes: [LoopRoute] = [
        .exec(.preset, name: "right_half"),
        .exec(.preset, name: "maximize"),
        .exec(.preset, name: "next_screen"),
        .exec(.custom, name: "my_layout"),
        .execID("<uuid>")
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
            kind: .write,
            components: [],
            response: failureResponse(message: "Command timed out")
        )
    }

    @discardableResult
    func handleRequestURLString(_ request: String, source: InvocationSource) async -> CommandExecutionResult {
        log.info("Processing request string: \(request)")

        guard let url = URL(string: request) else {
            return makeExecutionResult(
                source: source,
                kind: .write,
                components: [],
                response: failureResponse(message: "Invalid request URL: \(request)")
            )
        }

        return await handle(url, source: source)
    }

    private func process(_ url: URL, source: InvocationSource) async -> CommandExecutionResult {
        guard url.scheme?.lowercased() == "loop" else {
            return makeExecutionResult(
                source: source,
                kind: .write,
                components: [],
                response: failureResponse(
                    message: "URLs must start with loop://"
                )
            )
        }

        let urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = urlComponents?.queryItems

        let params = TargetParams(
            windowID: queryItems?.first(where: { $0.name == "windowID" })?.value.flatMap(UInt32.init),
            bundleID: queryItems?.first(where: { $0.name == "bundleID" })?.value,
            screenID: queryItems?.first(where: { $0.name == "screenID" })?.value.flatMap(UInt32.init)
        )

        let components = (url.host.map { [$0] } ?? []) + url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        return await execute(components, params: params, source: source)
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

    // MARK: - Command Execution

    private func execute(
        _ components: [String],
        params: TargetParams,
        source: InvocationSource
    ) async -> CommandExecutionResult {
        if params.windowID != nil, params.bundleID != nil {
            return makeExecutionResult(
                source: source,
                kind: .write,
                components: components,
                response: failureResponse(message: "windowID and bundleID are mutually exclusive")
            )
        }

        let response: LoopAutomationResponse = if let route = LoopRoute(components: components) {
            await self.response(for: route, params: params)
        } else {
            invalidRouteResponse(components)
        }

        return makeExecutionResult(
            source: source,
            kind: components.first?.lowercased() == "list" ? .read : .write,
            components: components,
            response: response
        )
    }

    private func response(for route: LoopRoute, params: TargetParams) async -> LoopAutomationResponse {
        switch route {
        case .listWindows:
            return buildWindowListResponse()

        case .listScreens:
            return buildScreenListResponse()

        case let .listActions(filter):
            return buildActionsResponse(filter: filter)

        case let .exec(.preset, name):
            guard let descriptor = presetActionDescriptor(name: name) else {
                return failureResponse(
                    message: "Unknown preset action: \(name)",
                    replacementRoute: .listActions(.presetOnly)
                )
            }

            return await executeAction(descriptor, params: params)

        case let .exec(.custom, name):
            let slug = slugifyDisplayString(name)
            guard let descriptor = customActionDescriptors().first(where: { $0.name == slug }) else {
                return failureResponse(
                    message: "Unknown custom action: \(name)",
                    replacementRoute: .listActions(.customOnly)
                )
            }

            return await executeAction(descriptor, params: params)

        case let .execID(token):
            guard let identifier = UUID(uuidString: token) else {
                return failureResponse(
                    message: "Invalid UUID: \(token)",
                    replacementRoute: .listActions(.all)
                )
            }

            guard let descriptor = customActionDescriptors().first(where: { $0.action.id == identifier }) else {
                return failureResponse(
                    message: "Unknown action ID: \(token)",
                    replacementRoute: .listActions(.all)
                )
            }

            return await executeAction(descriptor, params: params)
        }
    }

    // MARK: - List Commands

    private func buildActionsResponse(filter: LoopActionListFilter) -> LoopAutomationResponse {
        let presetCategories: [LoopActionCategory] = filter == .customOnly ? [] : presetSections().map { section in
            LoopActionCategory(
                name: section.title,
                actions: section.items.map { presetActionDescriptor(for: $0).publicDescriptor }
            )
        }

        let customActions: [LoopActionDescriptor] = filter == .presetOnly ? [] : customActionDescriptors().map(\.publicDescriptor)

        return LoopAutomationResponse(
            result: .actionList(
                LoopActionListResult(
                    filter: filter,
                    presetCategories: presetCategories,
                    customActions: customActions
                )
            )
        )
    }

    private func buildWindowListResponse() -> LoopAutomationResponse {
        let visibleWindows = WindowUtility.windowList().filter { window in
            guard let app = window.nsRunningApplication else {
                return false
            }

            return app.bundleIdentifier != Bundle.main.bundleIdentifier
                && app.activationPolicy == .regular
                && !window.isApplicationHidden
                && !window.minimized
        }

        return LoopAutomationResponse(
            result: .windowList(
                LoopWindowListResult(
                    windows: visibleWindows.map(windowSummary)
                )
            )
        )
    }

    private func buildScreenListResponse() -> LoopAutomationResponse {
        let screens = NSScreen.screens
        return LoopAutomationResponse(
            result: .screenList(
                LoopScreenListResult(
                    screens: screens.map(screenSummary)
                )
            )
        )
    }

    // MARK: - Write Commands

    private func executeAction(
        _ descriptor: ActionDescriptor,
        params: TargetParams
    ) async -> LoopAutomationResponse {
        let resolvedWindow = await resolveWindow(params: params)

        guard let resolvedAction = await resolveCycle(descriptor.action, for: resolvedWindow),
              !resolvedAction.direction.isNoOp
        else {
            return failureResponse(message: "Can’t run this action: \(descriptor.name)")
        }

        if !resolvedAction.direction.willFocusWindow, resolvedWindow == nil {
            return failureResponse(message: windowResolveError(params))
        }

        let targetScreen: NSScreen
        switch resolveTargetScreen(for: resolvedAction, window: resolvedWindow, params: params) {
        case let .success(screen):
            targetScreen = screen
        case let .failure(error):
            return LoopAutomationResponse(error: error)
        }

        do {
            try await performAction(resolvedAction, on: resolvedWindow, screen: targetScreen)
        } catch {
            return failureResponse(message: "Couldn’t run \(descriptor.name): \(error.localizedDescription)")
        }

        return LoopAutomationResponse(
            result: .execution(
                LoopExecutionResult(
                    action: descriptor.publicDescriptor,
                    targetWindow: resolvedWindow.map(windowSummary)
                )
            )
        )
    }

    // MARK: - Action Catalog

    /// The Keybinds tab's action picker, minus actions that have to be configured first, like stash
    private func presetSections() -> [PickerSection<WindowDirection>] {
        PickerSection.windowDirections.compactMap { section in
            let items = section.items.filter { !$0.isCustomizable }
            return items.isEmpty ? nil : PickerSection(section.title, items)
        }
    }

    private func presetActionDescriptor(for direction: WindowDirection) -> ActionDescriptor {
        ActionDescriptor(
            action: WindowAction(direction),
            kind: .preset,
            name: canonicalDirectionName(for: direction),
            title: direction.name
        )
    }

    /// Accepts the listed name or its display name, e.g. `right_half` or "Right Half"
    private func presetActionDescriptor(name: String) -> ActionDescriptor? {
        let slug = slugifyDisplayString(name)
        return presetSections()
            .flatMap(\.items)
            .first { canonicalDirectionName(for: $0) == slug }
            .map(presetActionDescriptor(for:))
    }

    private func customActionDescriptors() -> [ActionDescriptor] {
        let candidates: [(WindowAction, String, String)] = Defaults[.keybinds].compactMap { action in
            guard
                !action.keybind.isEmpty,
                isExecutableCustomAction(action)
            else {
                return nil
            }

            let displayName = action.getName().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !displayName.isEmpty else {
                return nil
            }

            return (action, displayName, slugifyDisplayString(displayName))
        }

        let groupedByBaseName = Dictionary(grouping: candidates, by: \.2)

        return candidates.map { action, displayName, baseName in
            let finalName: String = if groupedByBaseName[baseName, default: []].count > 1 {
                "\(baseName)_\(shortIdentifier(for: action.id))"
            } else {
                baseName
            }

            return ActionDescriptor(
                action: action,
                kind: .custom,
                name: finalName,
                title: displayName
            )
        }
    }

    // MARK: - Response Helpers

    /// Explains why `components` isn't a valid route
    private func invalidRouteResponse(_ components: [String]) -> LoopAutomationResponse {
        guard let command = components.first?.lowercased() else {
            return failureResponse(
                message: "No command given",
                availableRoutes: Self.listRoutes + Self.exampleExecRoutes
            )
        }

        let arguments = Array(components.dropFirst())

        switch command {
        case "list":
            return failureResponse(
                message: arguments.isEmpty ? "No list type given" : "Unknown list type: \(arguments.joined(separator: "/"))",
                availableRoutes: Self.listRoutes
            )

        case "exec":
            return invalidExecRouteResponse(arguments)

        case "preset", "custom", "id":
            return failureResponse(
                message: "Unknown command: \(command)",
                replacementRoute: LoopRoute(components: ["exec"] + components)
            )

        default:
            return failureResponse(
                message: "Unknown command: \(command)",
                availableRoutes: Self.listRoutes + Self.exampleExecRoutes
            )
        }
    }

    private func invalidExecRouteResponse(_ arguments: [String]) -> LoopAutomationResponse {
        switch arguments.first?.lowercased() {
        case "preset":
            failureResponse(
                message: "Running a preset action requires exactly one name",
                replacementRoute: .listActions(.presetOnly)
            )
        case "custom":
            failureResponse(
                message: "Running a custom action requires exactly one name",
                replacementRoute: .listActions(.customOnly)
            )
        case "id":
            failureResponse(
                message: "Running an action by ID requires exactly one UUID",
                replacementRoute: .listActions(.all)
            )
        case let type:
            failureResponse(
                message: type.map { "Unknown action type: \($0)" } ?? "No action type given",
                availableRoutes: Self.exampleExecRoutes
            )
        }
    }

    private func failureResponse(
        message: String,
        replacementRoute: LoopRoute? = nil,
        availableRoutes: [LoopRoute] = []
    ) -> LoopAutomationResponse {
        LoopAutomationResponse(
            error: LoopAutomationError(
                message: message,
                replacementRoute: replacementRoute?.displayString,
                availableRoutes: availableRoutes.isEmpty ? nil : availableRoutes.map(\.displayString)
            )
        )
    }

    private func makeExecutionResult(
        source: InvocationSource,
        kind: CommandKind,
        components: [String],
        response: LoopAutomationResponse
    ) -> CommandExecutionResult {
        let jsonResponse = LoopAutomationJSON.encodeString(response)

        guard source == .urlScheme else {
            return CommandExecutionResult(jsonResponse: jsonResponse, presentation: nil)
        }

        let presentation: CommandExecutionResult.Presentation? = switch kind {
        case .read:
            .output(
                title: outputTitle(for: components),
                text: response.result.map { LoopAutomationFormatter().format($0) }
                    ?? LoopAutomationText(response.error?.message ?? jsonResponse)
            )
        case .write:
            response.error.map { .failureAlert(message: $0.message) }
        }

        return CommandExecutionResult(jsonResponse: jsonResponse, presentation: presentation)
    }

    private func outputTitle(for components: [String]) -> String {
        let commandPath = components.joined(separator: " ")
        return commandPath.isEmpty
            ? String(localized: "Loop Output")
            : String(localized: "Loop Output: \(commandPath)", comment: "Output window title; the value is the command that was run, such as “list windows”")
    }

    private func windowSummary(_ window: Window) -> LoopWindowSummary {
        let app = window.nsRunningApplication
        return LoopWindowSummary(
            id: window.cgWindowID,
            bundleID: app?.bundleIdentifier ?? "",
            appName: app?.localizedName ?? "",
            title: window.title ?? "",
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

    // MARK: - Name and ID Helpers

    private func slugifyDisplayString(_ string: String, treatCamelCaseAsWords: Bool = false) -> String {
        let source = if treatCamelCaseAsWords {
            string
                .replacingOccurrences(
                    of: "([A-Z]+)([A-Z][a-z])",
                    with: "$1_$2",
                    options: .regularExpression
                )
                .replacingOccurrences(
                    of: "([a-z0-9])([A-Z])",
                    with: "$1_$2",
                    options: .regularExpression
                )
        } else {
            string
        }

        let slug = source
            .replacingOccurrences(of: "[^A-Za-z0-9]+", with: "_", options: .regularExpression)
            .replacingOccurrences(of: "_{2,}", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
            .lowercased()

        return slug.isEmpty ? "unnamed" : slug
    }

    private func canonicalDirectionName(for direction: WindowDirection) -> String {
        slugifyDisplayString(direction.rawValue, treatCamelCaseAsWords: true)
    }

    private func shortIdentifier(for uuid: UUID) -> String {
        String(uuid.uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(8))
    }

    // MARK: - Execution Helpers

    private func isExecutableCustomAction(_ action: WindowAction) -> Bool {
        switch action.direction {
        case .noAction, .noSelection:
            false
        case .cycle:
            !(action.cycle?.isEmpty ?? true)
        case .stash:
            action.stashEdge != nil
        default:
            true
        }
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

    private func performAction(_ action: WindowAction, on window: Window?, screen: NSScreen) async throws {
        if let window {
            log.info("Focusing window: \(window.description)")
            window.focus()
        }

        log.info("Executing action: \(action) on \(window?.title ?? "unknown")")
        _ = try await WindowActionEngine.shared.apply(
            action,
            window: window,
            screen: screen
        )

        if let window {
            log.info("New window frame: \(window.frame)")
        }
    }

    private func resolveTargetScreen(
        for action: WindowAction,
        window: Window?,
        params: TargetParams
    ) -> Result<NSScreen, LoopAutomationError> {
        if action.direction.willChangeScreen {
            guard let window else {
                return .failure(LoopAutomationError(message: windowResolveError(params)))
            }

            guard let currentScreen = ScreenUtility.screenContaining(window) ?? NSScreen.main else {
                return .failure(LoopAutomationError(message: "No current screen found"))
            }

            guard let targetScreen = ScreenUtility.targetScreen(for: action.direction, from: currentScreen) else {
                return .failure(LoopAutomationError(message: "No target screen found for \(action.direction.name)"))
            }

            return .success(targetScreen)
        }

        guard let screen = resolveScreen(screenID: params.screenID) else {
            return .failure(LoopAutomationError(message: params.screenID.map { "No screen found with ID \($0)" } ?? "No current screen found"))
        }

        return .success(screen)
    }

    // MARK: - Window/Screen Helpers

    /// Resolves the target window from targeting parameters.
    /// Priority: windowID > bundleID > frontmost window.
    private func resolveWindow(params: TargetParams) async -> Window? {
        if let windowID = params.windowID {
            return try? Window.fromWindowID(windowID)
        }
        if let bundleID = params.bundleID {
            return await resolveWindowByBundleID(bundleID)
        }
        return try? WindowUtility.frontmostWindow()
    }

    /// Resolves a window by bundle ID, launching the app if needed.
    private func resolveWindowByBundleID(_ bundleID: String) async -> Window? {
        if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) {
            return try? Window(pid: app.processIdentifier)
        }

        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            log.error("No app found for bundle ID: \(bundleID)")
            return nil
        }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = true

        let app: NSRunningApplication
        do {
            app = try await NSWorkspace.shared.openApplication(at: appURL, configuration: config)
        } catch {
            log.error("Failed to launch \(bundleID): \(error.localizedDescription)")
            return nil
        }

        let clock = ContinuousClock()
        let deadline = clock.now + Self.launchedAppWindowTimeout

        while clock.now < deadline {
            if let window = try? Window(pid: app.processIdentifier) {
                return window
            }

            do {
                try await Task.sleep(for: .milliseconds(100))
            } catch {
                return nil
            }
        }

        log.error("App launched but no window appeared: \(bundleID)")
        return nil
    }

    /// Resolves a screen by display ID, falling back to the main screen.
    private func resolveScreen(screenID: CGDirectDisplayID?) -> NSScreen? {
        if let screenID {
            return NSScreen.screens.first { $0.displayID == screenID }
        }
        return NSScreen.main
    }

    /// Builds a human-readable error message for window resolution failure.
    private func windowResolveError(_ params: TargetParams) -> String {
        if let windowID = params.windowID {
            return "No window found with ID \(windowID)"
        }
        if let bundleID = params.bundleID {
            return "Couldn’t find or open app: \(bundleID)"
        }
        return "No frontmost window found"
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
