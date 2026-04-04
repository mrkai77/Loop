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
 - loop://list/actions/directions
 - loop://list/actions/keybinds
 - loop://direction/<name>
 - loop://keybind/<name>
 - loop://id/<uuid>

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
final class LoopCommandHandler {
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
        let source: InvocationSource
        let kind: CommandKind
        let title: String
        let jsonResponse: String
        let isSuccess: Bool
        let errorMessage: String?

        @MainActor
        func presentIfNeeded() {
            guard source == .urlScheme else {
                return
            }

            switch kind {
            case .read:
                CommandOutputWindowManager.shared.show(
                    title: title,
                    content: jsonResponse
                )
            case .write:
                guard !isSuccess else {
                    return
                }

                let alert = NSAlert()
                alert.messageText = "Loop Command Failed"
                alert.informativeText = errorMessage ?? jsonResponse
                alert.alertStyle = .warning

                let button = alert.addButton(withTitle: "OK")
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
            }
        }
    }

    private enum ListActionFilter: Equatable {
        case all
        case directionsOnly
        case keybindsOnly

        var automationFilter: LoopActionListFilter {
            switch self {
            case .all:
                .all
            case .directionsOnly:
                .directionsOnly
            case .keybindsOnly:
                .keybindsOnly
            }
        }
    }

    private enum ResponseResult<Value> {
        case success(Value)
        case failure(LoopAutomationResponse)
    }

    private enum MessageResult<Value> {
        case success(Value)
        case failure(String)
    }

    /// Parameters parsed from URL query string / CLI flags for targeting specific windows and screens.
    private struct TargetParams {
        var windowID: CGWindowID?
        var bundleID: String?
        var screenID: CGDirectDisplayID?
    }

    private struct DirectionActionDescriptor {
        let direction: WindowDirection
        let name: String
        let title: String

        var urlPath: String {
            "direction/\(name)"
        }
    }

    private struct KeybindActionDescriptor {
        let action: WindowAction
        let id: UUID
        let name: String
        let title: String

        var idString: String {
            id.uuidString.lowercased()
        }

        var urlPath: String {
            "keybind/\(name)"
        }

        var idPath: String {
            "id/\(idString)"
        }
    }

    private enum ExecutableActionDescriptor {
        case direction(DirectionActionDescriptor)
        case keybind(KeybindActionDescriptor)

        var id: UUID? {
            switch self {
            case .direction:
                nil
            case let .keybind(descriptor):
                descriptor.id
            }
        }

        var name: String {
            switch self {
            case let .direction(descriptor):
                descriptor.name
            case let .keybind(descriptor):
                descriptor.name
            }
        }

        var title: String {
            switch self {
            case let .direction(descriptor):
                descriptor.title
            case let .keybind(descriptor):
                descriptor.title
            }
        }

        var actionKind: LoopActionKind {
            switch self {
            case .direction:
                .direction
            case .keybind:
                .keybind
            }
        }

        var urlPath: String {
            switch self {
            case let .direction(descriptor):
                descriptor.urlPath
            case let .keybind(descriptor):
                descriptor.urlPath
            }
        }

        var idPath: String? {
            switch self {
            case .direction:
                nil
            case let .keybind(descriptor):
                descriptor.idPath
            }
        }

        var windowAction: WindowAction {
            switch self {
            case let .direction(descriptor):
                WindowAction(descriptor.direction)
            case let .keybind(descriptor):
                descriptor.action
            }
        }
    }

    // MARK: - Constants

    private static let directionCategories: [(String, [WindowDirection])] = [
        ("General Actions", WindowDirection.general),
        ("Halves", WindowDirection.halves),
        ("Quarters", WindowDirection.quarters),
        ("Horizontal Thirds", WindowDirection.horizontalThirds),
        ("Horizontal Fourths", WindowDirection.horizontalFourths),
        ("Vertical Thirds", WindowDirection.verticalThirds),
        ("Screen Switching", WindowDirection.screenSwitching),
        ("Size Adjustment", WindowDirection.sizeAdjustment),
        ("Shrink", WindowDirection.shrink),
        ("Grow", WindowDirection.grow),
        ("Move", WindowDirection.move),
        ("Focus", WindowDirection.focus),
        ("Other", [.initialFrame, .undo])
    ]

    // MARK: - Public Methods

    /// Handles incoming `loop://` requests and returns command metadata.
    @discardableResult
    func handle(_ url: URL) -> CommandExecutionResult {
        handle(url, source: .urlScheme)
    }

    @discardableResult
    func handle(_ url: URL, source: InvocationSource) -> CommandExecutionResult {
        log.info("Processing request: \(url.absoluteString)")

        guard url.scheme?.lowercased() == "loop" else {
            return makeExecutionResult(
                source: source,
                kind: .write,
                components: [],
                response: failureResponse(
                    message: "Invalid scheme: \(url.scheme ?? "nil"). Required: loop://"
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
        return execute(components, params: params, source: source)
    }

    @discardableResult
    func handleRequestURLString(_ request: String, source: InvocationSource) -> CommandExecutionResult {
        log.info("Processing request string: \(request)")

        guard let url = URL(string: request) else {
            return makeExecutionResult(
                source: source,
                kind: .write,
                components: [],
                response: failureResponse(message: "Invalid request URL: \(request)")
            )
        }

        return handle(url, source: source)
    }

    // MARK: - Command Execution

    private func execute(
        _ components: [String],
        params: TargetParams,
        source: InvocationSource
    ) -> CommandExecutionResult {
        if params.windowID != nil, params.bundleID != nil {
            return makeExecutionResult(
                source: source,
                kind: .write,
                components: components,
                response: failureResponse(message: "windowID and bundleID are mutually exclusive")
            )
        }

        guard let commandString = components.first?.lowercased() else {
            return makeExecutionResult(
                source: source,
                kind: .write,
                components: components,
                response: unknownCommandResponse(nil)
            )
        }

        let parameters = Array(components.dropFirst())

        switch commandString {
        case "list":
            return makeExecutionResult(
                source: source,
                kind: .read,
                components: components,
                response: handleListCommand(parameters)
            )

        case "direction":
            return makeExecutionResult(
                source: source,
                kind: .write,
                components: components,
                response: handleDirectionCommand(parameters, params: params)
            )

        case "keybind":
            return makeExecutionResult(
                source: source,
                kind: .write,
                components: components,
                response: handleKeybindCommand(parameters, params: params)
            )

        case "id":
            return makeExecutionResult(
                source: source,
                kind: .write,
                components: components,
                response: handleIDCommand(parameters, params: params)
            )

        default:
            return makeExecutionResult(
                source: source,
                kind: .write,
                components: components,
                response: unknownCommandResponse(commandString)
            )
        }
    }

    // MARK: - List Commands

    private func handleListCommand(_ parameters: [String]) -> LoopAutomationResponse {
        guard let type = parameters.first?.lowercased() else {
            return invalidListRootResponse()
        }

        switch type {
        case "windows":
            guard parameters.count == 1 else {
                return invalidListRouteResponse(parameters)
            }
            return buildWindowListResponse()

        case "screens":
            guard parameters.count == 1 else {
                return invalidListRouteResponse(parameters)
            }
            return buildScreenListResponse()

        case "actions":
            switch parseListActionFilter(parameters) {
            case let .success(filter):
                return buildActionsResponse(filter: filter)
            case let .failure(error):
                return error
            }

        default:
            return invalidListRouteResponse(parameters)
        }
    }

    private func parseListActionFilter(_ parameters: [String]) -> ResponseResult<ListActionFilter> {
        let tail = Array(parameters.dropFirst())

        guard tail.count <= 1 else {
            return .failure(invalidListRouteResponse(parameters))
        }

        guard let subtype = tail.first?.lowercased() else {
            return .success(.all)
        }

        switch subtype {
        case "directions":
            return .success(.directionsOnly)
        case "keybinds":
            return .success(.keybindsOnly)
        default:
            return .failure(invalidListRouteResponse(parameters))
        }
    }

    private func buildActionsResponse(filter: ListActionFilter) -> LoopAutomationResponse {
        let allDirectionCategories = buildDirectionActionCategories()
        let allKeybindActions = keybindActionDescriptors().map { descriptor in
            sharedActionDescriptor(.keybind(descriptor))
        }

        let result = LoopActionListResult(
            filter: filter.automationFilter,
            directionCategories: filter == .keybindsOnly ? [] : allDirectionCategories,
            keybindActions: filter == .directionsOnly ? [] : allKeybindActions
        )

        return LoopAutomationResponse(result: .actionList(result))
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

    private func handleDirectionCommand(_ parameters: [String], params: TargetParams) -> LoopAutomationResponse {
        guard parameters.count == 1 else {
            return failureResponse(
                message: "Direction execution requires exactly one name",
                replacementRoute: urlCommandString(["list", "actions", "directions"])
            )
        }

        let token = parameters[0]
        guard let descriptor = directionActionDescriptor(name: token) else {
            return failureResponse(
                message: "Unknown direction name: \(token)",
                replacementRoute: urlCommandString(["list", "actions", "directions"])
            )
        }

        return executeAction(.direction(descriptor), params: params)
    }

    private func handleKeybindCommand(_ parameters: [String], params: TargetParams) -> LoopAutomationResponse {
        guard parameters.count == 1 else {
            return failureResponse(
                message: "Keybind execution requires exactly one name",
                replacementRoute: urlCommandString(["list", "actions", "keybinds"])
            )
        }

        let token = parameters[0]
        guard let descriptor = keybindActionDescriptor(name: token) else {
            return failureResponse(
                message: "Unknown keybind name: \(token)",
                replacementRoute: urlCommandString(["list", "actions", "keybinds"])
            )
        }

        return executeAction(.keybind(descriptor), params: params)
    }

    private func handleIDCommand(_ parameters: [String], params: TargetParams) -> LoopAutomationResponse {
        guard parameters.count == 1 else {
            return failureResponse(
                message: "ID execution requires exactly one UUID",
                replacementRoute: urlCommandString(["list", "actions"])
            )
        }

        let token = parameters[0]
        guard let identifier = UUID(uuidString: token) else {
            return failureResponse(
                message: "Invalid UUID: \(token)",
                replacementRoute: urlCommandString(["list", "actions"])
            )
        }

        guard let descriptor = executableActionDescriptor(id: identifier) else {
            return failureResponse(
                message: "Unknown action ID: \(token)",
                replacementRoute: urlCommandString(["list", "actions"])
            )
        }

        return executeAction(descriptor, params: params)
    }

    private func executeAction(
        _ descriptor: ExecutableActionDescriptor,
        params: TargetParams
    ) -> LoopAutomationResponse {
        let action = descriptor.windowAction
        let resolvedWindow = resolveWindow(params: params)
        let resolvedAction = resolveActionForCommandExecution(action, window: resolvedWindow)

        if resolvedAction.direction.isNoOp || resolvedAction.direction == .cycle {
            return failureResponse(message: "Action is not executable: \(descriptor.name)")
        }

        if !resolvedAction.direction.willFocusWindow, resolvedWindow == nil {
            return failureResponse(message: windowResolveError(params))
        }

        let targetScreen: NSScreen
        switch resolveTargetScreen(for: resolvedAction, window: resolvedWindow, params: params) {
        case let .success(screen):
            targetScreen = screen
        case let .failure(error):
            return failureResponse(message: error)
        }

        dispatchAction(resolvedAction, on: resolvedWindow, screen: targetScreen)

        return LoopAutomationResponse(
            result: .execution(
                LoopExecutionResult(
                    action: sharedActionDescriptor(descriptor),
                    targetWindow: resolvedWindow.map(executionTargetWindowSummary)
                )
            )
        )
    }

    // MARK: - Action Catalog

    private func buildDirectionActionCategories() -> [LoopActionCategory] {
        Self.directionCategories.map { category, directions in
            LoopActionCategory(
                name: category,
                actions: directions.map { direction in
                    sharedActionDescriptor(.direction(directionActionDescriptor(for: direction)))
                }
            )
        }
    }

    private func allDirectionActionDescriptors() -> [DirectionActionDescriptor] {
        Self.directionCategories.flatMap { _, directions in
            directions.map { direction in
                DirectionActionDescriptor(
                    direction: direction,
                    name: canonicalDirectionName(for: direction),
                    title: direction.name
                )
            }
        }
    }

    private func directionActionDescriptor(for direction: WindowDirection) -> DirectionActionDescriptor {
        DirectionActionDescriptor(
            direction: direction,
            name: canonicalDirectionName(for: direction),
            title: direction.name
        )
    }

    private func directionActionDescriptor(name: String) -> DirectionActionDescriptor? {
        allDirectionActionDescriptors().first { $0.name == name.lowercased() }
    }

    private func keybindActionDescriptors() -> [KeybindActionDescriptor] {
        let candidates: [(WindowAction, String, String)] = Defaults[.keybinds].compactMap { action in
            guard
                !action.keybind.isEmpty,
                isExecutableKeybindAction(action)
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

            return KeybindActionDescriptor(
                action: action,
                id: action.id,
                name: finalName,
                title: displayName
            )
        }
    }

    private func keybindActionDescriptor(name: String) -> KeybindActionDescriptor? {
        keybindActionDescriptors().first { $0.name == name.lowercased() }
    }

    private func keybindActionDescriptor(id: UUID) -> KeybindActionDescriptor? {
        keybindActionDescriptors().first { $0.id == id }
    }

    private func executableActionDescriptor(id: UUID) -> ExecutableActionDescriptor? {
        if let descriptor = keybindActionDescriptor(id: id) {
            return .keybind(descriptor)
        }

        return nil
    }

    // MARK: - Response Helpers

    private func publicRoutes() -> [String] {
        publicListRoutes() + publicWriteRoutes()
    }

    private func publicListRoutes() -> [String] {
        [
            urlCommandString(["list", "windows"]),
            urlCommandString(["list", "screens"]),
            urlCommandString(["list", "actions"]),
            urlCommandString(["list", "actions", "directions"]),
            urlCommandString(["list", "actions", "keybinds"])
        ]
    }

    private func publicWriteRoutes() -> [String] {
        [
            urlCommandString(["direction", "right"]),
            urlCommandString(["direction", "maximize"]),
            urlCommandString(["direction", "next_screen"]),
            urlCommandString(["keybind", "my_layout"]),
            urlCommandString(["id", "<uuid>"])
        ]
    }

    private func urlCommandString(_ components: [String]) -> String {
        "loop://\(components.joined(separator: "/"))"
    }

    private func failureResponse(
        message: String,
        replacementRoute: String? = nil,
        availableRoutes: [String] = []
    ) -> LoopAutomationResponse {
        LoopAutomationResponse(
            error: LoopAutomationError(
                message: message,
                replacementRoute: replacementRoute,
                availableRoutes: availableRoutes.isEmpty ? nil : availableRoutes
            )
        )
    }

    private func invalidListRootResponse() -> LoopAutomationResponse {
        failureResponse(
            message: "No list type specified",
            availableRoutes: publicListRoutes()
        )
    }

    private func invalidListRouteResponse(_ parameters: [String]) -> LoopAutomationResponse {
        failureResponse(
            message: "Unknown list route: list/\(parameters.joined(separator: "/"))",
            availableRoutes: publicListRoutes()
        )
    }

    private func unknownCommandResponse(_ command: String?) -> LoopAutomationResponse {
        failureResponse(
            message: "Unknown command: \(command ?? "nil")",
            availableRoutes: publicRoutes()
        )
    }

    // MARK: - JSON Helpers

    private func jsonString(_ response: LoopAutomationResponse) -> String {
        do {
            return try LoopAutomationJSON.encodeString(response)
        } catch {
            return #"{"error":{"message":"Failed to serialize response"},"success":false}"#
        }
    }

    private func makeExecutionResult(
        source: InvocationSource,
        kind: CommandKind,
        components: [String],
        response: LoopAutomationResponse
    ) -> CommandExecutionResult {
        CommandExecutionResult(
            source: source,
            kind: kind,
            title: outputTitle(for: components),
            jsonResponse: jsonString(response),
            isSuccess: response.success,
            errorMessage: response.error?.message
        )
    }

    private func outputTitle(for components: [String]) -> String {
        let commandPath = components.joined(separator: " ")
        return commandPath.isEmpty ? "Loop Output" : "Loop Output: \(commandPath)"
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

    private func executionTargetWindowSummary(_ window: Window) -> LoopExecutionTargetWindow {
        let app = window.nsRunningApplication
        return LoopExecutionTargetWindow(
            id: window.cgWindowID,
            bundleID: app?.bundleIdentifier ?? "",
            appName: app?.localizedName ?? "",
            title: window.title ?? ""
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

    private func sharedActionDescriptor(_ descriptor: ExecutableActionDescriptor) -> LoopActionDescriptor {
        LoopActionDescriptor(
            id: descriptor.id,
            kind: descriptor.actionKind,
            title: descriptor.title,
            name: descriptor.name,
            route: urlCommandString(descriptor.urlPath.split(separator: "/").map(String.init)),
            idRoute: descriptor.idPath.map { urlCommandString($0.split(separator: "/").map(String.init)) }
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

    private func isExecutableKeybindAction(_ action: WindowAction) -> Bool {
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

    private func resolveActionForCommandExecution(_ action: WindowAction, window: Window?) -> WindowAction {
        var currentAction = action
        var depth = 0

        while currentAction.direction == .cycle {
            guard depth < 8, let cycle = currentAction.cycle, !cycle.isEmpty else {
                return currentAction
            }

            if let window,
               let latestRecord = WindowRecords.getCurrentAction(for: window),
               let currentIndex = cycle.firstIndex(of: latestRecord) {
                currentAction = cycle[(currentIndex + 1) % cycle.count]
            } else {
                currentAction = cycle[0]
            }

            depth += 1
        }

        return currentAction
    }

    private func dispatchAction(_ action: WindowAction, on window: Window?, screen: NSScreen) {
        if let app = window?.nsRunningApplication {
            log.info("Activating application: \(app.localizedName ?? "unknown")")
            app.activate(options: .activateIgnoringOtherApps)
        }

        Task {
            try? await Task.sleep(for: .seconds(0.1))

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
    }

    private func resolveTargetScreen(
        for action: WindowAction,
        window: Window?,
        params: TargetParams
    ) -> MessageResult<NSScreen> {
        if action.direction.willChangeScreen {
            guard let window else {
                return .failure(windowResolveError(params))
            }

            guard let currentScreen = ScreenUtility.screenContaining(window) ?? NSScreen.main else {
                return .failure("No current screen found")
            }

            let targetScreen: NSScreen? = switch action.direction {
            case .nextScreen:
                ScreenUtility.nextScreen(from: currentScreen)
            case .previousScreen:
                ScreenUtility.previousScreen(from: currentScreen)
            case .leftScreen:
                ScreenUtility.directionalScreen(from: currentScreen, direction: .left)
            case .rightScreen:
                ScreenUtility.directionalScreen(from: currentScreen, direction: .right)
            case .topScreen:
                ScreenUtility.directionalScreen(from: currentScreen, direction: .top)
            case .bottomScreen:
                ScreenUtility.directionalScreen(from: currentScreen, direction: .bottom)
            default:
                currentScreen
            }

            guard let targetScreen else {
                return .failure("No target screen found for \(action.direction.name)")
            }

            return .success(targetScreen)
        }

        guard let screen = resolveScreen(screenID: params.screenID) else {
            return .failure("No screen found with ID \(params.screenID!)")
        }

        return .success(screen)
    }

    // MARK: - Window/Screen Helpers

    /// Finds a window by its CGWindowID from the current window list.
    private func findWindowByID(_ windowID: CGWindowID) -> Window? {
        WindowUtility.windowList().first { $0.cgWindowID == windowID }
    }

    /// Resolves the target window from targeting parameters.
    /// Priority: windowID > bundleID > frontmost window.
    private func resolveWindow(params: TargetParams = .init()) -> Window? {
        if let windowID = params.windowID {
            return findWindowByID(windowID)
        }
        if let bundleID = params.bundleID {
            return resolveWindowByBundleID(bundleID)
        }
        return try? WindowUtility.frontmostWindow()
    }

    /// Resolves a window by bundle ID, launching the app if needed.
    private func resolveWindowByBundleID(_ bundleID: String) -> Window? {
        if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) {
            app.activate(options: .activateIgnoringOtherApps)
            Thread.sleep(forTimeInterval: 0.1)
            return try? Window(pid: app.processIdentifier)
        }

        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            log.error("No app found for bundle ID: \(bundleID)")
            return nil
        }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = true

        let semaphore = DispatchSemaphore(value: 0)
        var launchedApp: NSRunningApplication?
        NSWorkspace.shared.openApplication(at: appURL, configuration: config) { app, error in
            if let error {
                self.log.error("Failed to launch \(bundleID): \(error.localizedDescription)")
            }
            launchedApp = app
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 5)

        guard let app = launchedApp else {
            return nil
        }

        for _ in 0 ..< 30 {
            Thread.sleep(forTimeInterval: 0.1)
            if let window = try? Window(pid: app.processIdentifier) {
                return window
            }
        }

        log.error("App launched but no window appeared: \(bundleID)")
        return nil
    }

    /// Resolves a screen by display ID, falling back to the main screen.
    private func resolveScreen(screenID: CGDirectDisplayID? = nil) -> NSScreen? {
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
            return "Could not find or launch app: \(bundleID)"
        }
        return "No frontmost window found"
    }
}
