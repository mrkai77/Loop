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
        let source: InvocationSource
        let kind: CommandKind
        let title: String
        let jsonResponse: String
        let readableResponse: LoopAutomationText
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
                    text: readableResponse,
                    json: jsonResponse
                )
            case .write:
                guard !isSuccess else {
                    return
                }

                let alert = NSAlert()
                alert.messageText = String(localized: "The command couldn’t be run.")
                alert.informativeText = errorMessage ?? jsonResponse
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
            }
        }
    }

    private enum ListActionFilter: Equatable {
        case all
        case presetOnly
        case customOnly

        var automationFilter: LoopActionListFilter {
            switch self {
            case .all:
                .all
            case .presetOnly:
                .presetOnly
            case .customOnly:
                .customOnly
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

    private struct PresetActionDescriptor {
        let direction: WindowDirection
        let name: String
        let title: String

        var urlPath: String {
            "exec/preset/\(name)"
        }
    }

    private struct CustomActionDescriptor {
        let action: WindowAction
        let id: UUID
        let name: String
        let title: String

        var idString: String {
            id.uuidString.lowercased()
        }

        var urlPath: String {
            "exec/custom/\(name)"
        }

        var idPath: String {
            "exec/id/\(idString)"
        }
    }

    private enum ExecutableActionDescriptor {
        case preset(PresetActionDescriptor)
        case custom(CustomActionDescriptor)

        var id: UUID? {
            switch self {
            case .preset:
                nil
            case let .custom(descriptor):
                descriptor.id
            }
        }

        var name: String {
            switch self {
            case let .preset(descriptor):
                descriptor.name
            case let .custom(descriptor):
                descriptor.name
            }
        }

        var title: String {
            switch self {
            case let .preset(descriptor):
                descriptor.title
            case let .custom(descriptor):
                descriptor.title
            }
        }

        var actionKind: LoopActionKind {
            switch self {
            case .preset:
                .preset
            case .custom:
                .custom
            }
        }

        var urlPath: String {
            switch self {
            case let .preset(descriptor):
                descriptor.urlPath
            case let .custom(descriptor):
                descriptor.urlPath
            }
        }

        var idPath: String? {
            switch self {
            case .preset:
                nil
            case let .custom(descriptor):
                descriptor.idPath
            }
        }

        var windowAction: WindowAction {
            switch self {
            case let .preset(descriptor):
                WindowAction(descriptor.direction)
            case let .custom(descriptor):
                descriptor.action
            }
        }
    }

    // MARK: - Constants

    private static let commandTimeout: Duration = .seconds(10)

    private static let presetCategories: [(String, [WindowDirection])] = [
        ("General", WindowDirection.general),
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
    func handle(_ url: URL, source: InvocationSource = .urlScheme) async -> CommandExecutionResult {
        log.info("Processing request: \(url.absoluteString)")

        let result = await withTimeout(Self.commandTimeout) {
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

            Task {
                try? await Task.sleep(for: timeout)
                if race.finish(with: nil) {
                    work.cancel()
                }
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

        case "exec":
            return await makeExecutionResult(
                source: source,
                kind: .write,
                components: components,
                response: handleExecCommand(parameters, params: params)
            )

        case "preset", "custom", "id":
            return makeExecutionResult(
                source: source,
                kind: .write,
                components: components,
                response: failureResponse(
                    message: "Unknown command: \(commandString)",
                    replacementRoute: urlCommandString(["exec"] + components)
                )
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
        case "preset":
            return .success(.presetOnly)
        case "custom":
            return .success(.customOnly)
        default:
            return .failure(invalidListRouteResponse(parameters))
        }
    }

    private func buildActionsResponse(filter: ListActionFilter) -> LoopAutomationResponse {
        let allPresetCategories = buildPresetActionCategories()
        let allCustomActions = customActionDescriptors().map { descriptor in
            sharedActionDescriptor(.custom(descriptor))
        }

        let result = LoopActionListResult(
            filter: filter.automationFilter,
            presetCategories: filter == .customOnly ? [] : allPresetCategories,
            customActions: filter == .presetOnly ? [] : allCustomActions
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

    private func handleExecCommand(_ parameters: [String], params: TargetParams) async -> LoopAutomationResponse {
        let arguments = Array(parameters.dropFirst())

        switch parameters.first?.lowercased() {
        case "preset":
            return await handlePresetCommand(arguments, params: params)
        case "custom":
            return await handleCustomCommand(arguments, params: params)
        case "id":
            return await handleIDCommand(arguments, params: params)
        case let type:
            return failureResponse(
                message: type.map { "Unknown action type: \($0)" } ?? "No action type given",
                availableRoutes: publicWriteRoutes()
            )
        }
    }

    private func handlePresetCommand(_ parameters: [String], params: TargetParams) async -> LoopAutomationResponse {
        guard parameters.count == 1 else {
            return failureResponse(
                message: "Running a preset action requires exactly one name",
                replacementRoute: urlCommandString(["list", "actions", "preset"])
            )
        }

        let token = parameters[0]
        guard let descriptor = presetActionDescriptor(name: token) else {
            return failureResponse(
                message: "Unknown preset action: \(token)",
                replacementRoute: urlCommandString(["list", "actions", "preset"])
            )
        }

        return await executeAction(.preset(descriptor), params: params)
    }

    private func handleCustomCommand(_ parameters: [String], params: TargetParams) async -> LoopAutomationResponse {
        guard parameters.count == 1 else {
            return failureResponse(
                message: "Running a custom action requires exactly one name",
                replacementRoute: urlCommandString(["list", "actions", "custom"])
            )
        }

        let token = parameters[0]
        guard let descriptor = customActionDescriptor(name: token) else {
            return failureResponse(
                message: "Unknown custom action: \(token)",
                replacementRoute: urlCommandString(["list", "actions", "custom"])
            )
        }

        return await executeAction(.custom(descriptor), params: params)
    }

    private func handleIDCommand(_ parameters: [String], params: TargetParams) async -> LoopAutomationResponse {
        guard parameters.count == 1 else {
            return failureResponse(
                message: "Running an action by ID requires exactly one UUID",
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

        return await executeAction(descriptor, params: params)
    }

    private func executeAction(
        _ descriptor: ExecutableActionDescriptor,
        params: TargetParams
    ) async -> LoopAutomationResponse {
        let action = descriptor.windowAction
        let resolvedWindow = await resolveWindow(params: params)
        let latestRecord: WindowAction? = if let resolvedWindow {
            await WindowRecords.shared.getCurrentAction(for: resolvedWindow)
        } else {
            nil
        }
        let resolvedAction = resolveActionForCommandExecution(action, latestRecord: latestRecord)

        if resolvedAction.direction.isNoOp || resolvedAction.direction == .cycle {
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
            return failureResponse(message: error)
        }

        do {
            try await performAction(resolvedAction, on: resolvedWindow, screen: targetScreen)
        } catch {
            return failureResponse(message: "Couldn’t run \(descriptor.name): \(error.localizedDescription)")
        }

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

    private func buildPresetActionCategories() -> [LoopActionCategory] {
        Self.presetCategories.map { category, directions in
            LoopActionCategory(
                name: category,
                actions: directions.map { direction in
                    sharedActionDescriptor(.preset(presetActionDescriptor(for: direction)))
                }
            )
        }
    }

    private func allPresetActionDescriptors() -> [PresetActionDescriptor] {
        Self.presetCategories.flatMap { _, directions in
            directions.map { direction in
                PresetActionDescriptor(
                    direction: direction,
                    name: canonicalDirectionName(for: direction),
                    title: direction.name
                )
            }
        }
    }

    private func presetActionDescriptor(for direction: WindowDirection) -> PresetActionDescriptor {
        PresetActionDescriptor(
            direction: direction,
            name: canonicalDirectionName(for: direction),
            title: direction.name
        )
    }

    /// Accepts the listed name or its display name, e.g. `right_half` or "Right Half"
    private func presetActionDescriptor(name: String) -> PresetActionDescriptor? {
        let slug = slugifyDisplayString(name)
        return allPresetActionDescriptors().first { $0.name == slug }
    }

    private func customActionDescriptors() -> [CustomActionDescriptor] {
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

            return CustomActionDescriptor(
                action: action,
                id: action.id,
                name: finalName,
                title: displayName
            )
        }
    }

    private func customActionDescriptor(name: String) -> CustomActionDescriptor? {
        let slug = slugifyDisplayString(name)
        return customActionDescriptors().first { $0.name == slug }
    }

    private func customActionDescriptor(id: UUID) -> CustomActionDescriptor? {
        customActionDescriptors().first { $0.id == id }
    }

    private func executableActionDescriptor(id: UUID) -> ExecutableActionDescriptor? {
        if let descriptor = customActionDescriptor(id: id) {
            return .custom(descriptor)
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
            urlCommandString(["list", "actions", "preset"]),
            urlCommandString(["list", "actions", "custom"])
        ]
    }

    private func publicWriteRoutes() -> [String] {
        [
            urlCommandString(["exec", "preset", "right_half"]),
            urlCommandString(["exec", "preset", "maximize"]),
            urlCommandString(["exec", "preset", "next_screen"]),
            urlCommandString(["exec", "custom", "my_layout"]),
            urlCommandString(["exec", "id", "<uuid>"])
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
            message: "No list type given",
            availableRoutes: publicListRoutes()
        )
    }

    private func invalidListRouteResponse(_ parameters: [String]) -> LoopAutomationResponse {
        failureResponse(
            message: "Unknown list type: \(parameters.joined(separator: "/"))",
            availableRoutes: publicListRoutes()
        )
    }

    private func unknownCommandResponse(_ command: String?) -> LoopAutomationResponse {
        failureResponse(
            message: command.map { "Unknown command: \($0)" } ?? "No command given",
            availableRoutes: publicRoutes()
        )
    }

    // MARK: - JSON Helpers

    private func jsonString(_ response: LoopAutomationResponse) -> String {
        do {
            return try LoopAutomationJSON.encodeString(response)
        } catch {
            return #"{"error":{"message":"Couldn’t encode the response"},"success":false}"#
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
            readableResponse: response.result.map { LoopAutomationFormatter().format($0) }
                ?? LoopAutomationText(response.error?.message ?? jsonString(response)),
            isSuccess: response.success,
            errorMessage: response.error?.message
        )
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

    private func resolveActionForCommandExecution(_ action: WindowAction, latestRecord: WindowAction?) -> WindowAction {
        var currentAction = action
        var depth = 0

        while currentAction.direction == .cycle {
            guard depth < 8, let cycle = currentAction.cycle, !cycle.isEmpty else {
                return currentAction
            }

            if let latestRecord,
               let currentIndex = cycle.firstIndex(of: latestRecord) {
                currentAction = cycle[(currentIndex + 1) % cycle.count]
            } else {
                currentAction = cycle[0]
            }

            depth += 1
        }

        return currentAction
    }

    private func performAction(_ action: WindowAction, on window: Window?, screen: NSScreen) async throws {
        if let app = window?.nsRunningApplication {
            log.info("Activating application: \(app.localizedName ?? "unknown")")
            app.activate(options: .activateIgnoringOtherApps)
        }

        try await Task.sleep(for: .seconds(0.1))

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
            return .failure(params.screenID.map { "No screen found with ID \($0)" } ?? "No current screen found")
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
    private func resolveWindow(params: TargetParams = .init()) async -> Window? {
        if let windowID = params.windowID {
            return findWindowByID(windowID)
        }
        if let bundleID = params.bundleID {
            return await resolveWindowByBundleID(bundleID)
        }
        return try? WindowUtility.frontmostWindow()
    }

    /// Resolves a window by bundle ID, launching the app if needed.
    private func resolveWindowByBundleID(_ bundleID: String) async -> Window? {
        if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) {
            app.activate(options: .activateIgnoringOtherApps)
            try? await Task.sleep(for: .seconds(0.1))
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

        for _ in 0 ..< 30 {
            do {
                try await Task.sleep(for: .seconds(0.1))
            } catch {
                return nil
            }

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
