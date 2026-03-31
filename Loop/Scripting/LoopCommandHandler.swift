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
 - loop://direction/<slug>
 - loop://keybind/<slug>
 - loop://id/<uuid>

 Socket / CLI transport:
 - loop-cli parses CLI arguments locally and sends canonical loop:// URLs over the socket

 Query parameters:
 - ?windowID=<id>
 - ?bundleID=<id>
 - ?screenID=<id>
 */

import AppKit
import CryptoKit
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

    private enum ListActionFilter {
        case all
        case directionsOnly
        case keybindsOnly
    }

    private enum ResponseResult<Value> {
        case success(Value)
        case failure([String: Any])
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
        let category: String
        let direction: WindowDirection
        let id: UUID
        let slug: String
        let name: String

        var idString: String {
            id.uuidString.lowercased()
        }

        var urlPath: String {
            "direction/\(slug)"
        }

        var idPath: String {
            "id/\(idString)"
        }
    }

    private struct KeybindActionDescriptor {
        let action: WindowAction
        let id: UUID
        let slug: String
        let name: String

        var idString: String {
            id.uuidString.lowercased()
        }

        var urlPath: String {
            "keybind/\(slug)"
        }

        var idPath: String {
            "id/\(idString)"
        }
    }

    private enum ExecutableActionDescriptor {
        case direction(DirectionActionDescriptor)
        case keybind(KeybindActionDescriptor)

        var idString: String {
            switch self {
            case let .direction(descriptor):
                descriptor.idString
            case let .keybind(descriptor):
                descriptor.idString
            }
        }

        var slug: String {
            switch self {
            case let .direction(descriptor):
                descriptor.slug
            case let .keybind(descriptor):
                descriptor.slug
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

        var kind: String {
            switch self {
            case .direction:
                "direction"
            case .keybind:
                "keybind"
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

        var idPath: String {
            switch self {
            case let .direction(descriptor):
                descriptor.idPath
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

    private static let directionIDNamespace = UUID(uuidString: "6c6e0e9d-2da7-4b3d-bf5b-4e868e4b6d7b")!

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
                response: [
                    "success": false,
                    "error": "Invalid scheme: \(url.scheme ?? "nil"). Required: loop://"
                ]
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
                response: [
                    "success": false,
                    "error": "Invalid request URL: \(request)"
                ]
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
                response: [
                    "success": false,
                    "error": "windowID and bundleID are mutually exclusive"
                ]
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

        if let legacy = removedLegacyCommandResponse(
            command: commandString,
            parameters: parameters
        ) {
            return makeExecutionResult(
                source: source,
                kind: legacy.kind,
                components: components,
                response: legacy.response
            )
        }

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

    private func handleListCommand(_ parameters: [String]) -> [String: Any] {
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

        case "all":
            return removedListAllResponse()

        case "keybinds":
            return removedListKeybindsResponse()

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

    private func buildActionsResponse(filter: ListActionFilter) -> [String: Any] {
        let directionActions = buildDirectionActionCategoriesJSON()
        let keybindActions = keybindActionDescriptors().map(keybindActionJSON)

        var response: [String: Any] = [
            "success": true,
            "command": "list",
            "type": "actions"
        ]

        switch filter {
        case .all:
            response["directionActions"] = directionActions
            response["keybindActions"] = keybindActions
        case .directionsOnly:
            response["subtype"] = "directions"
            response["directionActions"] = directionActions
        case .keybindsOnly:
            response["subtype"] = "keybinds"
            response["keybindActions"] = keybindActions
        }

        return response
    }

    private func buildWindowListResponse() -> [String: Any] {
        let visibleWindows = WindowUtility.windowList().filter { window in
            guard let app = window.nsRunningApplication else {
                return false
            }

            return app.bundleIdentifier != Bundle.main.bundleIdentifier
                && app.activationPolicy == .regular
                && !window.isApplicationHidden
                && !window.minimized
        }

        return [
            "success": true,
            "command": "list",
            "type": "windows",
            "windowCount": visibleWindows.count,
            "windows": visibleWindows.map(windowJSON)
        ]
    }

    private func buildScreenListResponse() -> [String: Any] {
        let screens = NSScreen.screens
        return [
            "success": true,
            "command": "list",
            "type": "screens",
            "screenCount": screens.count,
            "screens": screens.map { screen in
                [
                    "screenID": screen.displayID ?? 0,
                    "name": screen.localizedName,
                    "frame": [
                        "x": Int(screen.frame.origin.x),
                        "y": Int(screen.frame.origin.y),
                        "width": Int(screen.frame.width),
                        "height": Int(screen.frame.height)
                    ],
                    "isMain": screen == NSScreen.main
                ] as [String: Any]
            }
        ]
    }

    // MARK: - Write Commands

    private func handleDirectionCommand(_ parameters: [String], params: TargetParams) -> [String: Any] {
        guard parameters.count == 1 else {
            return [
                "success": false,
                "command": "direction",
                "error": "Direction execution requires exactly one slug",
                "replacement": urlCommandString(["list", "actions", "directions"])
            ]
        }

        let token = parameters[0]
        if let descriptor = directionActionDescriptor(slug: token) {
            return executeAction(.direction(descriptor), params: params, command: "direction")
        }

        if let descriptor = legacyDirectionDescriptor(for: token) {
            return migrationErrorResponse(
                command: "direction",
                error: "Use the canonical direction slug",
                replacement: urlCommandString(["direction", descriptor.slug])
            )
        }

        return [
            "success": false,
            "command": "direction",
            "error": "Unknown direction slug: \(token)",
            "replacement": urlCommandString(["list", "actions", "directions"])
        ]
    }

    private func handleKeybindCommand(_ parameters: [String], params: TargetParams) -> [String: Any] {
        guard parameters.count == 1 else {
            return [
                "success": false,
                "command": "keybind",
                "error": "Keybind execution requires exactly one slug",
                "replacement": urlCommandString(["list", "actions", "keybinds"])
            ]
        }

        let token = parameters[0]
        if let descriptor = keybindActionDescriptor(slug: token) {
            return executeAction(.keybind(descriptor), params: params, command: "keybind")
        }

        let legacyMatches = legacyKeybindDescriptors(for: token)
        if legacyMatches.count == 1, let descriptor = legacyMatches.first {
            return migrationErrorResponse(
                command: "keybind",
                error: "Use the canonical keybind slug",
                replacement: urlCommandString(["keybind", descriptor.slug])
            )
        }

        if legacyMatches.count > 1 {
            return [
                "success": false,
                "command": "keybind",
                "error": "Multiple keybind actions match \(token). Use list/actions/keybinds to find the canonical slug."
            ]
        }

        return [
            "success": false,
            "command": "keybind",
            "error": "Unknown keybind slug: \(token)",
            "replacement": urlCommandString(["list", "actions", "keybinds"])
        ]
    }

    private func handleIDCommand(_ parameters: [String], params: TargetParams) -> [String: Any] {
        guard parameters.count == 1 else {
            return [
                "success": false,
                "command": "id",
                "error": "ID execution requires exactly one UUID",
                "replacement": urlCommandString(["list", "actions"])
            ]
        }

        let token = parameters[0]
        guard let identifier = UUID(uuidString: token) else {
            return [
                "success": false,
                "command": "id",
                "error": "Invalid UUID: \(token)",
                "replacement": urlCommandString(["list", "actions"])
            ]
        }

        guard let descriptor = executableActionDescriptor(id: identifier) else {
            return [
                "success": false,
                "command": "id",
                "error": "Unknown action ID: \(token)",
                "replacement": urlCommandString(["list", "actions"])
            ]
        }

        return executeAction(descriptor, params: params, command: "id")
    }

    private func executeAction(
        _ descriptor: ExecutableActionDescriptor,
        params: TargetParams,
        command: String
    ) -> [String: Any] {
        let action = descriptor.windowAction
        let resolvedWindow = resolveWindow(params: params)
        let resolvedAction = resolveActionForCommandExecution(action, window: resolvedWindow)

        if resolvedAction.direction.isNoOp || resolvedAction.direction == .cycle {
            return [
                "success": false,
                "command": command,
                "id": descriptor.idString,
                "name": descriptor.name,
                "kind": descriptor.kind,
                "error": "Action is not executable: \(descriptor.name)"
            ]
        }

        if !resolvedAction.direction.willFocusWindow, resolvedWindow == nil {
            return [
                "success": false,
                "command": command,
                "id": descriptor.idString,
                "name": descriptor.name,
                "kind": descriptor.kind,
                "error": windowResolveError(params)
            ]
        }

        let targetScreen: NSScreen
        switch resolveTargetScreen(for: resolvedAction, window: resolvedWindow, params: params) {
        case let .success(screen):
            targetScreen = screen
        case let .failure(error):
            return [
                "success": false,
                "command": command,
                "id": descriptor.idString,
                "name": descriptor.name,
                "kind": descriptor.kind,
                "error": error
            ]
        }

        dispatchAction(resolvedAction, on: resolvedWindow, screen: targetScreen)

        var response: [String: Any] = [
            "success": true,
            "command": command,
            "id": descriptor.idString,
            "kind": descriptor.kind,
            "name": descriptor.name,
            "slug": descriptor.slug,
            "urlPath": descriptor.urlPath,
            "idPath": descriptor.idPath
        ]

        if let window = resolvedWindow {
            response["window"] = windowJSON(window)
        }

        return response
    }

    // MARK: - Action Catalog

    private func buildDirectionActionCategoriesJSON() -> [[String: Any]] {
        Self.directionCategories.map { category, directions in
            [
                "category": category,
                "actions": directions.map { direction in
                    directionActionJSON(directionActionDescriptor(for: direction))
                }
            ]
        }
    }

    private func directionActionJSON(_ descriptor: DirectionActionDescriptor) -> [String: Any] {
        [
            "id": descriptor.idString,
            "kind": "direction",
            "name": descriptor.name,
            "slug": descriptor.slug,
            "urlPath": descriptor.urlPath,
            "idPath": descriptor.idPath
        ]
    }

    private func keybindActionJSON(_ descriptor: KeybindActionDescriptor) -> [String: Any] {
        [
            "id": descriptor.idString,
            "kind": "keybind",
            "name": descriptor.name,
            "slug": descriptor.slug,
            "urlPath": descriptor.urlPath,
            "idPath": descriptor.idPath
        ]
    }

    private func allDirectionActionDescriptors() -> [DirectionActionDescriptor] {
        Self.directionCategories.flatMap { category, directions in
            directions.map { direction in
                DirectionActionDescriptor(
                    category: category,
                    direction: direction,
                    id: deterministicDirectionID(for: direction),
                    slug: canonicalDirectionSlug(for: direction),
                    name: direction.name
                )
            }
        }
    }

    private func directionActionDescriptor(for direction: WindowDirection) -> DirectionActionDescriptor {
        let category = Self.directionCategories.first { $0.1.contains(direction) }?.0 ?? "Actions"
        return DirectionActionDescriptor(
            category: category,
            direction: direction,
            id: deterministicDirectionID(for: direction),
            slug: canonicalDirectionSlug(for: direction),
            name: direction.name
        )
    }

    private func directionActionDescriptor(slug: String) -> DirectionActionDescriptor? {
        allDirectionActionDescriptors().first { $0.slug == slug.lowercased() }
    }

    private func directionActionDescriptor(id: UUID) -> DirectionActionDescriptor? {
        allDirectionActionDescriptors().first { $0.id == id }
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

        let groupedByBaseSlug = Dictionary(grouping: candidates, by: \.2)

        return candidates.map { action, name, baseSlug in
            let finalSlug: String = if groupedByBaseSlug[baseSlug, default: []].count > 1 {
                "\(baseSlug)_\(shortIdentifier(for: action.id))"
            } else {
                baseSlug
            }

            return KeybindActionDescriptor(
                action: action,
                id: action.id,
                slug: finalSlug,
                name: name
            )
        }
    }

    private func keybindActionDescriptor(slug: String) -> KeybindActionDescriptor? {
        keybindActionDescriptors().first { $0.slug == slug.lowercased() }
    }

    private func keybindActionDescriptor(id: UUID) -> KeybindActionDescriptor? {
        keybindActionDescriptors().first { $0.id == id }
    }

    private func executableActionDescriptor(id: UUID) -> ExecutableActionDescriptor? {
        if let descriptor = directionActionDescriptor(id: id) {
            return .direction(descriptor)
        }

        if let descriptor = keybindActionDescriptor(id: id) {
            return .keybind(descriptor)
        }

        return nil
    }

    private func legacyDirectionDescriptor(for token: String) -> DirectionActionDescriptor? {
        let lowered = token.lowercased()

        switch lowered {
        case "next":
            return directionActionDescriptor(for: .nextScreen)
        case "previous":
            return directionActionDescriptor(for: .previousScreen)
        default:
            return allDirectionActionDescriptors().first { descriptor in
                descriptor.slug == lowered
                    || slugifyDisplayString(descriptor.direction.rawValue, treatCamelCaseAsWords: true) == lowered
                    || descriptor.direction.rawValue.lowercased() == lowered
            }
        }
    }

    private func legacyKeybindDescriptors(for token: String) -> [KeybindActionDescriptor] {
        let lowered = token.lowercased()
        return keybindActionDescriptors().filter {
            $0.slug == lowered || $0.name.caseInsensitiveCompare(token) == .orderedSame
        }
    }

    // MARK: - Removed Public Commands

    private func removedLegacyCommandResponse(
        command: String,
        parameters: [String]
    ) -> (kind: CommandKind, response: [String: Any])? {
        switch command {
        case "windowlist":
            (
                .read,
                migrationErrorResponse(
                    command: "windowlist",
                    error: "windowlist has been removed",
                    replacement: listRouteReplacement(["windows"])
                )
            )

        case "screenlist":
            (
                .read,
                migrationErrorResponse(
                    command: "screenlist",
                    error: "screenlist has been removed",
                    replacement: listRouteReplacement(["screens"])
                )
            )

        case "execute":
            (
                .write,
                removedExecuteResponse(parameters: parameters)
            )

        case "screen":
            (
                .write,
                removedScreenResponse(parameters: parameters)
            )

        case "action":
            (
                parameters.first?.lowercased() == "list" ? .read : .write,
                removedActionResponse(parameters: parameters)
            )

        default:
            nil
        }
    }

    private func removedExecuteResponse(parameters: [String]) -> [String: Any] {
        if parameters.count == 1, let identifier = UUID(uuidString: parameters[0]), let descriptor = executableActionDescriptor(id: identifier) {
            return migrationErrorResponse(
                command: "execute",
                error: "execute has been removed",
                replacement: urlCommandString(["id", descriptor.idString])
            )
        }

        if parameters.count == 2, parameters[0].lowercased() == "direction", let descriptor = legacyDirectionDescriptor(for: parameters[1]) {
            return migrationErrorResponse(
                command: "execute",
                error: "execute has been removed",
                replacement: replacementCommand(for: .direction(descriptor))
            )
        }

        if parameters.count == 2, parameters[0].lowercased() == "keybind", let descriptor = keybindActionDescriptor(slug: parameters[1]) ?? legacyKeybindDescriptors(for: parameters[1]).only {
            return migrationErrorResponse(
                command: "execute",
                error: "execute has been removed",
                replacement: replacementCommand(for: .keybind(descriptor))
            )
        }

        return migrationErrorResponse(
            command: "execute",
            error: "execute has been removed",
            availableRoutes: publicWriteRoutes()
        )
    }

    private func removedScreenResponse(parameters: [String]) -> [String: Any] {
        if let parameter = parameters.first, let descriptor = legacyDirectionDescriptor(for: parameter) {
            return migrationErrorResponse(
                command: "screen",
                error: "screen has been removed",
                replacement: replacementCommand(for: .direction(descriptor))
            )
        }

        return migrationErrorResponse(
            command: "screen",
            error: "screen has been removed",
            replacement: urlCommandString(["list", "actions", "directions"])
        )
    }

    private func removedActionResponse(parameters: [String]) -> [String: Any] {
        if parameters.isEmpty || parameters.first?.lowercased() == "list" {
            return migrationErrorResponse(
                command: "action",
                error: "action has been removed",
                replacement: listRouteReplacement(["actions"])
            )
        }

        if let descriptor = legacyDirectionDescriptor(for: parameters[0]) {
            return migrationErrorResponse(
                command: "action",
                error: "action has been removed",
                replacement: replacementCommand(for: .direction(descriptor))
            )
        }

        let keybindMatches = legacyKeybindDescriptors(for: parameters[0])
        if let descriptor = keybindMatches.only {
            return migrationErrorResponse(
                command: "action",
                error: "action has been removed",
                replacement: replacementCommand(for: .keybind(descriptor))
            )
        }

        return migrationErrorResponse(
            command: "action",
            error: "action has been removed",
            replacement: listRouteReplacement(["actions"])
        )
    }

    // MARK: - Response Helpers

    private func publicCommandNames() -> [String] {
        ["list", "direction", "keybind", "id"]
    }

    private func publicListRoutes() -> [String] {
        [
            listRouteReplacement(["windows"]),
            listRouteReplacement(["screens"]),
            listRouteReplacement(["actions"]),
            listRouteReplacement(["actions", "directions"]),
            listRouteReplacement(["actions", "keybinds"])
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

    private func listRouteReplacement(_ components: [String]) -> String {
        urlCommandString(["list"] + components)
    }

    private func replacementCommand(for descriptor: ExecutableActionDescriptor) -> String {
        urlCommandString(descriptor.urlPath.split(separator: "/").map(String.init))
    }

    private func migrationErrorResponse(
        command: String,
        error: String,
        replacement: String? = nil,
        availableRoutes: [String] = []
    ) -> [String: Any] {
        var response: [String: Any] = [
            "success": false,
            "command": command,
            "error": error
        ]

        if let replacement {
            response["replacement"] = replacement
        }

        if !availableRoutes.isEmpty {
            response["availableRoutes"] = availableRoutes
        }

        return response
    }

    private func invalidListRootResponse() -> [String: Any] {
        migrationErrorResponse(
            command: "list",
            error: "No list type specified",
            availableRoutes: publicListRoutes()
        )
    }

    private func removedListAllResponse() -> [String: Any] {
        migrationErrorResponse(
            command: "list",
            error: "list/all has been removed",
            availableRoutes: publicListRoutes()
        )
    }

    private func removedListKeybindsResponse() -> [String: Any] {
        migrationErrorResponse(
            command: "list",
            error: "list/keybinds has been removed",
            replacement: listRouteReplacement(["actions", "keybinds"])
        )
    }

    private func invalidListRouteResponse(_ parameters: [String]) -> [String: Any] {
        migrationErrorResponse(
            command: "list",
            error: "Unknown list route: list/\(parameters.joined(separator: "/"))",
            availableRoutes: publicListRoutes()
        )
    }

    private func unknownCommandResponse(_ command: String?) -> [String: Any] {
        [
            "success": false,
            "error": "Unknown command: \(command ?? "nil")",
            "availableCommands": publicCommandNames()
        ]
    }

    // MARK: - JSON Helpers

    /// Serializes a response dictionary to a pretty-printed JSON string.
    private func jsonString(_ dict: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(
            withJSONObject: dict,
            options: [.prettyPrinted, .sortedKeys]
        ) else {
            return #"{"success":false,"error":"Failed to serialize response"}"#
        }
        return String(data: data, encoding: .utf8)
            ?? #"{"success":false,"error":"Failed to encode response"}"#
    }

    private func makeExecutionResult(
        source: InvocationSource,
        kind: CommandKind,
        components: [String],
        response: [String: Any]
    ) -> CommandExecutionResult {
        CommandExecutionResult(
            source: source,
            kind: kind,
            title: outputTitle(for: components),
            jsonResponse: jsonString(response),
            isSuccess: response["success"] as? Bool ?? false,
            errorMessage: response["error"] as? String
        )
    }

    private func outputTitle(for components: [String]) -> String {
        let commandPath = components.joined(separator: " ")
        return commandPath.isEmpty ? "Loop Output" : "Loop Output: \(commandPath)"
    }

    /// Builds a JSON-serializable dictionary for a window.
    private func windowJSON(_ window: Window) -> [String: Any] {
        let app = window.nsRunningApplication
        let frame = window.frame
        return [
            "windowID": window.cgWindowID,
            "bundleID": app?.bundleIdentifier ?? "",
            "appName": app?.localizedName ?? "",
            "windowTitle": window.title ?? "",
            "frame": [
                "x": Int(frame.origin.x),
                "y": Int(frame.origin.y),
                "width": Int(frame.width),
                "height": Int(frame.height)
            ]
        ]
    }

    // MARK: - Slug and ID Helpers

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

    private func canonicalDirectionSlug(for direction: WindowDirection) -> String {
        slugifyDisplayString(direction.rawValue, treatCamelCaseAsWords: true)
    }

    private func deterministicDirectionID(for direction: WindowDirection) -> UUID {
        uuidV5(namespace: Self.directionIDNamespace, name: direction.rawValue)
    }

    private func uuidV5(namespace: UUID, name: String) -> UUID {
        var namespaceUUID = namespace.uuid
        let namespaceData = withUnsafeBytes(of: &namespaceUUID) { Data($0) }
        let nameData = Data(name.utf8)
        let digest = Insecure.SHA1.hash(data: namespaceData + nameData)

        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80

        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
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

private extension Array {
    var only: Element? {
        count == 1 ? first : nil
    }
}
