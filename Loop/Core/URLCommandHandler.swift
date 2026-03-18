//
//  URLCommandHandler.swift
//  Loop
//
//  Created by Kami on 06/03/2025.
//

/*
 Loop URL Scheme Documentation
 ===========================

 The Loop app supports URL scheme commands for window management and automation.
 Base URL format: loop://<command>/<parameters>

 Available Commands:
 -----------------

 1. Window Direction Commands:
    Format: loop://direction/<direction>
    Examples:
    - loop://direction/left       (Move window to left half)
    - loop://direction/right      (Move window to right half)
    - loop://direction/top        (Move window to top half)
    - loop://direction/bottom     (Move window to bottom half)
    - loop://direction/maximize   (Maximize window)
    - loop://direction/center     (Center window)

 2. Screen Management:
    Format: loop://screen/<command>
    Examples:
    - loop://screen/next          (Move window to next screen)
    - loop://screen/previous      (Move window to previous screen)

 3. Action Commands:
    Format: loop://action/<action>
    Examples:
    - loop://action/maximize      (Maximize window)
    - loop://action/leftHalf      (Move to left half)
    Note: See 'loop://list/actions' for all available actions

 4. Keybind Commands:
    Format: loop://keybind/<name>
    Examples:
    - loop://keybind/myCustomLayout
    Note: See 'loop://list/keybinds' for available keybinds

 5. List Commands:
    Format: loop://list/<type>
    Types:
    - actions    (List all window actions)
    - keybinds   (List all custom keybinds)
    - all        (List everything)

 6. Window List Command:
    Format: loop://windowlist
    Returns JSON listing all visible windows with:
    - windowID, bundleID, appName, windowTitle, frame

 7. Screen List Command:
    Format: loop://screenlist
    Returns JSON listing all connected screens with:
    - screenID, name, frame, isMain

 Query Parameters:
 ----------------
 All action commands support optional query parameters for targeting:

 ?windowID=<id>    Target a specific window by CGWindowID
 ?bundleID=<id>    Target an app by bundle ID (launches if needed)
 ?screenID=<id>    Target a specific screen by display ID

 Notes:
 - windowID and bundleID are mutually exclusive (error if both specified)
 - screenID can be combined with either windowID or bundleID
 - Use loop://windowlist and loop://screenlist to discover IDs

 Examples:
 - loop://direction/right?windowID=1234
 - loop://action/maximize?bundleID=com.apple.Safari
 - loop://direction/left?screenID=12345
 - loop://action/maximize?bundleID=com.apple.Safari&screenID=12345

 Usage Tips:
 ----------
 1. All commands are case-insensitive
 2. All commands return JSON responses
 3. Window commands operate on the frontmost window by default
 4. Use loop://windowlist and loop://screenlist to discover IDs
 5. Use loop://list/all to discover all available commands

 Examples:
 --------
 # Move current window to right half
 open "loop://direction/right"

 # List all windows and screens
 open "loop://windowlist"
 open "loop://screenlist"

 # Move a specific window to the right half
 open "loop://direction/right?windowID=1234"

 # Launch/focus Safari and maximize it on a specific screen
 open "loop://action/maximize?bundleID=com.apple.Safari&screenID=12345"

 # List all available actions
 open "loop://list/actions"

 Error Examples:
 -------------
 # Invalid command
 open "loop://invalid" -> {"success": false, "error": "Unknown command: invalid"}

 # Both windowID and bundleID
 open "loop://direction/right?windowID=1&bundleID=com.x" -> error: mutually exclusive

 # Invalid window/screen ID
 open "loop://direction/right?windowID=9999" -> error: No window found with ID 9999
 */

import Defaults
import Foundation
import Scribe
import SwiftUI

/// Handles URL scheme commands for the Loop application
@Loggable
final class URLCommandHandler {
    // MARK: - Types

    /// Available URL scheme commands with their descriptions
    enum Command: String, CaseIterable {
        /// Window positioning commands (left, right, top, bottom, etc.)
        case direction
        /// Multi-screen management commands (next, previous)
        case screen
        /// Predefined window actions
        case action
        /// Custom keybind actions
        case keybind
        /// List available commands and options
        case list
        /// List all visible windows as JSON
        case windowlist
        /// List all screens as JSON
        case screenlist

        /// Human-readable description of each command type
        var description: String {
            switch self {
            case .direction: "Window direction command"
            case .screen: "Screen management"
            case .action: "Execute predefined window action"
            case .keybind: "Execute custom keybind action"
            case .list: "List available commands"
            case .windowlist: "List all visible windows as JSON"
            case .screenlist: "List all screens as JSON"
            }
        }
    }

    /// Parameters parsed from URL query string for targeting specific windows and screens
    private struct TargetParams {
        var windowID: CGWindowID?
        var bundleID: String?
        var screenID: CGDirectDisplayID?
    }

    // MARK: - Properties

    // MARK: - JSON Helpers

    /// Serializes a response dictionary to a pretty-printed JSON string
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

    /// Builds a JSON-serializable dictionary for a window
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

    // MARK: - Public Methods

    /// Handles incoming URL scheme requests and returns a JSON response string.
    /// This is the entry point for `loop://` URL scheme events.
    /// - Parameter url: The URL to process (e.g., `loop://direction/right?bundleID=com.apple.Safari`)
    /// - Returns: A JSON string containing the response
    @discardableResult
    func handle(_ url: URL) -> String {
        log.info("Processing URL: \(url)")

        guard url.scheme?.lowercased() == "loop" else {
            return jsonString([
                "success": false,
                "error": "Invalid scheme: \(url.scheme ?? "nil"). Required: loop://"
            ])
        }

        // Parse query parameters for targeting specific windows and screens
        let urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = urlComponents?.queryItems

        let params = TargetParams(
            windowID: queryItems?.first(where: { $0.name == "windowID" })?.value.flatMap { UInt32($0) },
            bundleID: queryItems?.first(where: { $0.name == "bundleID" })?.value,
            screenID: queryItems?.first(where: { $0.name == "screenID" })?.value.flatMap { UInt32($0) }
        )

        let components = (url.host.map { [$0] } ?? []) + url.pathComponents.filter { $0 != "/" && !$0.isEmpty }

        return execute(components, params: params)
    }

    /// Executes a raw command string and returns a JSON response.
    /// This is the entry point for the Unix socket (loop-cli).
    ///
    /// Format: `<command> [args...] [--window-id <id>] [--bundle-id <id>] [--screen-id <id>]`
    ///
    /// Examples:
    /// - `windowlist`
    /// - `direction right`
    /// - `direction right --bundle-id com.apple.Safari --screen-id 123`
    /// - `action maximize --window-id 1234`
    ///
    /// - Parameter input: The raw command string
    /// - Returns: A JSON string containing the response
    func executeRaw(_ input: String) -> String {
        log.info("Processing command: \(input)")

        var components: [String] = []
        var params = TargetParams()

        let tokens = input.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        var i = 0

        while i < tokens.count {
            switch tokens[i] {
            case "--window-id":
                i += 1
                if i < tokens.count { params.windowID = UInt32(tokens[i]) }
            case "--bundle-id":
                i += 1
                if i < tokens.count { params.bundleID = tokens[i] }
            case "--screen-id":
                i += 1
                if i < tokens.count { params.screenID = UInt32(tokens[i]) }
            default:
                components.append(tokens[i])
            }
            i += 1
        }

        return execute(components, params: params)
    }

    // MARK: - Command Execution

    /// Core command execution. Both `handle()` (URL scheme) and `executeRaw()` (socket) converge here.
    /// - Parameters:
    ///   - components: Path components (e.g., `["direction", "right"]`)
    ///   - params: Targeting parameters (windowID/bundleID/screenID)
    /// - Returns: A JSON string containing the response
    private func execute(_ components: [String], params: TargetParams) -> String {
        // windowID and bundleID are mutually exclusive
        if params.windowID != nil, params.bundleID != nil {
            return jsonString([
                "success": false,
                "error": "windowID and bundleID are mutually exclusive"
            ])
        }

        guard let commandString = components.first,
              let command = Command(rawValue: commandString.lowercased()) else {
            return jsonString([
                "success": false,
                "error": "Unknown command: \(components.first ?? "nil")",
                "availableCommands": Command.allCases.map(\.rawValue)
            ])
        }

        let parameters = Array(components.dropFirst())
        log.info("\(command.rawValue) \(parameters)")

        let response: [String: Any]
        switch command {
        case .direction: response = handleDirectionCommand(parameters, params: params)
        case .screen: response = handleScreenCommand(parameters, params: params)
        case .action: response = handleActionCommand(parameters, params: params)
        case .keybind: response = handleKeybindCommand(parameters, params: params)
        case .list: response = handleListCommand(parameters)
        case .windowlist: response = handleWindowListCommand()
        case .screenlist: response = handleScreenListCommand()
        }

        return jsonString(response)
    }

    /// Handles window direction commands
    /// - Parameters:
    ///   - parameters: Direction parameters
    ///   - windowID: Optional CGWindowID to target a specific window
    /// - Returns: JSON response dictionary
    private func handleDirectionCommand(_ parameters: [String], params: TargetParams = .init()) -> [String: Any] {
        guard let directionStr = parameters.first?.lowercased() else {
            return [
                "success": false,
                "command": "direction",
                "error": "No direction specified"
            ]
        }

        // If this is a list command, redirect to the list handler
        if directionStr == "list" {
            return handleListCommand(["actions"])
        }

        // First check if this is a custom action being called via direction
        if directionStr.hasPrefix("custom") || directionStr.hasPrefix("stash") {
            return handleActionCommand(parameters, params: params)
        }

        let direction: WindowDirection? = WindowDirection.allCases.first { $0.rawValue.lowercased() == directionStr } ?? {
            switch directionStr {
            case "left": return WindowDirection.leftHalf
            case "right": return WindowDirection.rightHalf
            case "top": return WindowDirection.topHalf
            case "bottom": return WindowDirection.bottomHalf
            default:
                let withoutHalf = directionStr.replacingOccurrences(of: "half", with: "")
                return WindowDirection.allCases.first { $0.rawValue.lowercased() == withoutHalf }
            }
        }()

        if let direction {
            return executeWindowAction(direction, params: params)
        } else {
            return [
                "success": false,
                "command": "direction",
                "parameter": directionStr,
                "error": "Invalid direction: \(directionStr)"
            ]
        }
    }

    /// Executes a window action for a given direction
    /// - Parameters:
    ///   - direction: The direction to move/resize the window
    ///   - windowID: Optional CGWindowID to target a specific window
    /// - Returns: JSON response dictionary
    private func executeWindowAction(_ direction: WindowDirection, params: TargetParams = .init()) -> [String: Any] {
        log.info("Executing direction: \(direction.rawValue)")

        guard let window = resolveWindow(params: params) else {
            return [
                "success": false,
                "command": "direction",
                "parameter": direction.rawValue.lowercased(),
                "error": windowResolveError(params)
            ]
        }

        guard let screen = resolveScreen(screenID: params.screenID) else {
            return [
                "success": false,
                "command": "direction",
                "error": "No screen found with ID \(params.screenID!)"
            ]
        }

        let action = WindowAction(direction)
        activateAndResizeWindow(window, action, screen)
        return [
            "success": true,
            "command": "direction",
            "action": direction.rawValue,
            "window": windowJSON(window)
        ]
    }

    /// Handles screen management commands
    /// - Parameters:
    ///   - parameters: Screen command parameters
    ///   - windowID: Optional CGWindowID to target a specific window
    /// - Returns: JSON response dictionary
    private func handleScreenCommand(_ parameters: [String], params: TargetParams = .init()) -> [String: Any] {
        guard let command = parameters.first?.lowercased() else {
            return ["success": false, "command": "screen", "error": "No screen command specified"]
        }

        guard let window = resolveWindow(params: params) else {
            return [
                "success": false,
                "command": "screen",
                "parameter": command,
                "error": windowResolveError(params)
            ]
        }

        let direction: WindowDirection = command == "next" ? .nextScreen : .previousScreen
        moveWindowToScreen(window, direction)
        return [
            "success": true,
            "command": "screen",
            "action": command,
            "window": windowJSON(window)
        ]
    }

    /// Handles predefined window actions
    /// - Parameters:
    ///   - parameters: Action parameters
    ///   - windowID: Optional CGWindowID to target a specific window
    /// - Returns: JSON response dictionary
    private func handleActionCommand(_ parameters: [String], params: TargetParams = .init()) -> [String: Any] {
        guard let actionStr = parameters.first?.lowercased() else {
            return buildActionsResponse()
        }

        // First check for custom actions by name
        let customKeybinds = Defaults[.keybinds].filter { $0.direction.isCustomizable && $0.name != nil }
        if let customAction = customKeybinds.first(where: { ($0.name?.lowercased() ?? "") == actionStr }) {
            guard let window = resolveWindow(params: params) else {
                return ["success": false, "command": "action", "parameter": actionStr, "error": windowResolveError(params)]
            }
            guard let screen = resolveScreen(screenID: params.screenID) else {
                return ["success": false, "command": "action", "error": "No screen found with ID \(params.screenID!)"]
            }
            activateAndResizeWindow(window, customAction, screen)
            return [
                "success": true,
                "command": "action",
                "action": customAction.name ?? actionStr,
                "window": windowJSON(window)
            ]
        }

        if actionStr == "list" {
            return buildActionsResponse()
        }

        if let direction = WindowDirection.allCases.first(where: { $0.rawValue.lowercased() == actionStr }) {
            guard let window = resolveWindow(params: params) else {
                return ["success": false, "command": "action", "parameter": actionStr, "error": windowResolveError(params)]
            }
            guard let screen = resolveScreen(screenID: params.screenID) else {
                return ["success": false, "command": "action", "error": "No screen found with ID \(params.screenID!)"]
            }
            activateAndResizeWindow(window, .init(direction), screen)
            return [
                "success": true,
                "command": "action",
                "action": direction.rawValue,
                "window": windowJSON(window)
            ]
        }

        return [
            "success": false,
            "command": "action",
            "parameter": actionStr,
            "error": "Invalid action: \(actionStr)"
        ]
    }

    /// Builds a structured response of all available actions grouped by category
    /// - Returns: JSON response dictionary with categorized actions
    private func buildActionsResponse() -> [String: Any] {
        var categories: [[String: Any]] = []

        let customKeybinds = Defaults[.keybinds].filter { $0.direction == .custom && $0.name?.isEmpty == false }
        if !customKeybinds.isEmpty {
            categories.append([
                "category": "Custom Actions",
                "actions": customKeybinds.compactMap { $0.name?.lowercased() }
            ])
        }

        let stashKeybinds = Defaults[.keybinds].filter { $0.direction == .stash && $0.name?.isEmpty == false }
        if !stashKeybinds.isEmpty {
            categories.append([
                "category": "Stash Actions",
                "actions": stashKeybinds.compactMap { $0.name?.lowercased() }
            ])
        }

        let builtinCategories: [(String, [WindowDirection])] = [
            ("General Actions", Array(WindowDirection.general.dropFirst(3))),
            ("Halves", WindowDirection.halves),
            ("Quarters", WindowDirection.quarters),
            ("Horizontal Thirds", WindowDirection.horizontalThirds),
            ("Vertical Thirds", WindowDirection.verticalThirds),
            ("Screen Switching", WindowDirection.screenSwitching),
            ("Size Adjustment", WindowDirection.sizeAdjustment),
            ("Shrink", WindowDirection.shrink),
            ("Grow", WindowDirection.grow),
            ("Move", WindowDirection.move),
            ("Other", WindowDirection.more)
        ]

        for (title, actions) in builtinCategories where !actions.isEmpty {
            categories.append([
                "category": title,
                "actions": actions.map { $0.rawValue.lowercased() }
            ])
        }

        return [
            "success": true,
            "command": "list",
            "type": "actions",
            "categories": categories
        ]
    }

    /// Handles custom keybind execution
    /// - Parameters:
    ///   - parameters: Keybind parameters
    ///   - windowID: Optional CGWindowID to target a specific window
    /// - Returns: JSON response dictionary
    private func handleKeybindCommand(_ parameters: [String], params: TargetParams = .init()) -> [String: Any] {
        let keybinds = Defaults[.keybinds]

        guard let keybindName = parameters.first else {
            return ["success": false, "command": "keybind", "error": "No keybind specified"]
        }

        if keybindName.lowercased() == "list" {
            return [
                "success": true,
                "command": "list",
                "type": "keybinds",
                "keybinds": keybinds.compactMap(\.name)
            ]
        }

        guard let keybind = keybinds.first(where: { $0.name?.lowercased() == keybindName.lowercased() }) else {
            return [
                "success": false,
                "command": "keybind",
                "parameter": keybindName,
                "error": "Keybind not found: \(keybindName)",
                "availableKeybinds": keybinds.compactMap(\.name)
            ]
        }

        guard let window = resolveWindow(params: params) else {
            return [
                "success": false,
                "command": "keybind",
                "parameter": keybindName,
                "error": windowResolveError(params)
            ]
        }

        guard let screen = resolveScreen(screenID: params.screenID) else {
            return [
                "success": false,
                "command": "keybind",
                "error": "No screen found with ID \(params.screenID!)"
            ]
        }

        Task {
            _ = try await WindowActionEngine.shared.apply(
                keybind, window: window, screen: screen
            )
        }
        return [
            "success": true,
            "command": "keybind",
            "keybind": keybind.name ?? keybindName,
            "window": windowJSON(window)
        ]
    }

    /// Handles list commands for viewing available options
    /// - Parameter parameters: List parameters
    /// - Returns: JSON response dictionary
    private func handleListCommand(_ parameters: [String]) -> [String: Any] {
        let type = parameters.first?.lowercased() ?? "all"

        switch type {
        case "actions":
            return buildActionsResponse()

        case "keybinds":
            return [
                "success": true,
                "command": "list",
                "type": "keybinds",
                "keybinds": Defaults[.keybinds].compactMap(\.name)
            ]

        default:
            let actionsResponse = buildActionsResponse()

            return [
                "success": true,
                "command": "list",
                "type": "all",
                "directions": WindowDirection.allCases.map { $0.rawValue.lowercased() },
                "screenCommands": ["next", "previous"],
                "actionCategories": actionsResponse["categories"] ?? [],
                "keybinds": Defaults[.keybinds].compactMap(\.name),
                "commands": Command.allCases.map { [
                    "command": $0.rawValue,
                    "description": $0.description
                ] as [String: String] }
            ]
        }
    }

    // MARK: - Window List

    /// Lists all visible windows with their details
    /// - Returns: JSON response dictionary
    private func handleWindowListCommand() -> [String: Any] {
        let visibleWindows = WindowUtility.windowList().filter { win in
            guard let app = win.nsRunningApplication else { return false }
            return app.bundleIdentifier != Bundle.main.bundleIdentifier
                && app.activationPolicy == .regular
                && !win.isApplicationHidden
                && !win.minimized
        }

        return [
            "success": true,
            "command": "windowlist",
            "windowCount": visibleWindows.count,
            "windows": visibleWindows.map { windowJSON($0) }
        ]
    }

    // MARK: - Screen List

    /// Lists all connected screens with their details
    /// - Returns: JSON response dictionary
    private func handleScreenListCommand() -> [String: Any] {
        let screens = NSScreen.screens
        return [
            "success": true,
            "command": "screenlist",
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

    // MARK: - Helper Methods

    /// Finds a window by its CGWindowID from the current window list
    /// - Parameter windowID: The CGWindowID to search for
    /// - Returns: The matching window, or nil if not found
    private func findWindowByID(_ windowID: CGWindowID) -> Window? {
        WindowUtility.windowList().first { $0.cgWindowID == windowID }
    }

    /// Resolves the target window from targeting parameters
    /// Priority: windowID > bundleID > frontmost window
    /// - Parameter params: Targeting parameters
    /// - Returns: The resolved window, or nil if not found
    private func resolveWindow(params: TargetParams = .init()) -> Window? {
        if let windowID = params.windowID {
            return findWindowByID(windowID)
        }
        if let bundleID = params.bundleID {
            return resolveWindowByBundleID(bundleID)
        }
        return try? WindowUtility.frontmostWindow()
    }

    /// Resolves a window by bundle ID, launching the app if needed
    /// - Parameter bundleID: The bundle identifier of the app
    /// - Returns: The app's frontmost window, or nil if not found
    private func resolveWindowByBundleID(_ bundleID: String) -> Window? {
        // Check if already running
        if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) {
            app.activate(options: .activateIgnoringOtherApps)
            // Brief pause to let activation settle
            Thread.sleep(forTimeInterval: 0.1)
            return try? Window(pid: app.processIdentifier)
        }

        // Not running — try to launch it
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

        guard let app = launchedApp else { return nil }

        // Wait for the app to create a window (up to 3 seconds)
        for _ in 0..<30 {
            Thread.sleep(forTimeInterval: 0.1)
            if let window = try? Window(pid: app.processIdentifier) {
                return window
            }
        }

        log.error("App launched but no window appeared: \(bundleID)")
        return nil
    }

    /// Resolves a screen by display ID, falling back to the main screen
    /// - Parameter screenID: Optional display ID to target a specific screen
    /// - Returns: The resolved screen, or nil if the specified ID was not found
    private func resolveScreen(screenID: CGDirectDisplayID? = nil) -> NSScreen? {
        if let screenID {
            return NSScreen.screens.first { $0.displayID == screenID }
        }
        return NSScreen.main
    }

    /// Builds a human-readable error message for window resolution failure
    /// - Parameter params: The targeting parameters that were used
    /// - Returns: Error message string
    private func windowResolveError(_ params: TargetParams) -> String {
        if let windowID = params.windowID {
            return "No window found with ID \(windowID)"
        }
        if let bundleID = params.bundleID {
            return "Could not find or launch app: \(bundleID)"
        }
        return "No frontmost window found"
    }

    /// Activates and resizes a window
    private func activateAndResizeWindow(_ window: Window, _ action: WindowAction, _ screen: NSScreen) {
        if let app = window.nsRunningApplication {
            log.info("Activating application: \(app.localizedName ?? "unknown")")
            app.activate(options: .activateIgnoringOtherApps)
        }

        Task {
            try? await Task.sleep(for: .seconds(0.1))

            log.info("Executing resize: \(action) on \(window.title ?? "unknown")")
            _ = try? await WindowActionEngine.shared.apply(
                action,
                window: window,
                screen: screen
            )
            log.info("New window frame: \(window.frame)")
        }
    }

    /// Moves a window to another screen
    private func moveWindowToScreen(_ window: Window, _ direction: WindowDirection) {
        if let currentScreen = ScreenUtility.screenContaining(window),
           let targetScreen = direction == .nextScreen ?
           ScreenUtility.nextScreen(from: currentScreen) :
           ScreenUtility.previousScreen(from: currentScreen) {
            log.info("Moving window to screen: \(targetScreen.localizedName)")
            Task {
                _ = try? await WindowActionEngine.shared.apply(
                    .init(direction),
                    window: window,
                    screen: targetScreen
                )
            }
        } else {
            log.error("Failed to find target screen")
        }
    }
}
