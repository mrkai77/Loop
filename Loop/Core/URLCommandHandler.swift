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
    Returns a JSON file listing all visible windows with:
    - windowID   (CGWindowID, use with ?windowID parameter)
    - bundleID   (App bundle identifier)
    - appName    (App display name)
    - windowTitle (Window title)
    - frame      (x, y, width, height)

 Targeting a Specific Window:
 ---------------------------
 Any action command can optionally include a ?windowID=<id> query parameter
 to target a specific window instead of the frontmost one.

 Examples:
 - loop://direction/right?windowID=1234
 - loop://action/maximize?windowID=1234
 - loop://keybind/myLayout?windowID=1234
 - loop://screen/next?windowID=1234

 Usage Tips:
 ----------
 1. All commands are case-insensitive
 2. Parameters with spaces must be URL encoded
 3. Window commands operate on the frontmost non-terminal window (unless ?windowID is specified)
 4. Use list commands to discover available options
 5. Use loop://windowlist to discover window IDs for targeted actions

 Examples:
 --------
 # Move current window to right half
 open "loop://direction/right"

 # List all windows to find window IDs
 open "loop://windowlist"

 # Move a specific window to the right half
 open "loop://direction/right?windowID=1234"

 # List all available actions
 open "loop://list/actions"

 # Execute custom keybind
 open "loop://keybind/myLayout"

 Error Examples:
 -------------
 # Invalid command
 open "loop://invalid" -> Returns available commands

 # Missing parameter
 open "loop://direction" -> Returns available directions

 # Invalid keybind
 open "loop://keybind/nonexistent" -> Returns available keybinds

 # Invalid window ID
 open "loop://direction/right?windowID=9999" -> Returns error with available windows
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

        /// Human-readable description of each command type
        var description: String {
            switch self {
            case .direction: "Window direction command"
            case .screen: "Screen management"
            case .action: "Execute predefined window action"
            case .keybind: "Execute custom keybind action"
            case .list: "List available commands"
            case .windowlist: "List all visible windows as JSON"
            }
        }
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

    /// Handles incoming URL scheme requests and returns a JSON response string
    /// - Parameter url: The URL to process
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

        // Parse optional windowID query parameter for targeting a specific window
        let urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let windowID: CGWindowID? = urlComponents?
            .queryItems?
            .first(where: { $0.name == "windowID" })?
            .value
            .flatMap { UInt32($0) }

        let components = (url.host.map { [$0] } ?? []) + url.pathComponents.filter { $0 != "/" && !$0.isEmpty }

        guard let commandString = components.first,
              let command = Command(rawValue: commandString.lowercased()) else {
            return jsonString([
                "success": false,
                "error": "Unknown command: \(components.first ?? "nil")",
                "availableCommands": Command.allCases.map(\.rawValue)
            ])
        }

        return processCommand(command, Array(components.dropFirst()), windowID: windowID)
    }

    // MARK: - Command Processing

    /// Processes a command with its parameters and returns a JSON response string
    /// - Parameters:
    ///   - command: The command to process
    ///   - parameters: Array of command parameters
    ///   - windowID: Optional CGWindowID to target a specific window
    /// - Returns: A JSON string containing the response
    private func processCommand(_ command: Command, _ parameters: [String], windowID: CGWindowID? = nil) -> String {
        log.info("\(command.rawValue) \(parameters)")

        let response: [String: Any]
        switch command {
        case .direction: response = handleDirectionCommand(parameters, windowID: windowID)
        case .screen: response = handleScreenCommand(parameters, windowID: windowID)
        case .action: response = handleActionCommand(parameters, windowID: windowID)
        case .keybind: response = handleKeybindCommand(parameters, windowID: windowID)
        case .list: response = handleListCommand(parameters)
        case .windowlist: response = handleWindowListCommand()
        }

        return jsonString(response)
    }

    /// Handles window direction commands
    /// - Parameters:
    ///   - parameters: Direction parameters
    ///   - windowID: Optional CGWindowID to target a specific window
    /// - Returns: JSON response dictionary
    private func handleDirectionCommand(_ parameters: [String], windowID: CGWindowID? = nil) -> [String: Any] {
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
            return handleActionCommand(parameters, windowID: windowID)
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
            return executeWindowAction(direction, windowID: windowID)
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
    private func executeWindowAction(_ direction: WindowDirection, windowID: CGWindowID? = nil) -> [String: Any] {
        log.info("Executing direction: \(direction.rawValue)")

        guard let window = resolveWindow(windowID: windowID) else {
            return [
                "success": false,
                "command": "direction",
                "parameter": direction.rawValue.lowercased(),
                "error": windowID != nil
                    ? "No window found with ID \(windowID!)"
                    : "No frontmost window found"
            ]
        }

        guard let screen = NSScreen.main else {
            return ["success": false, "command": "direction", "error": "No screen found"]
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
    private func handleScreenCommand(_ parameters: [String], windowID: CGWindowID? = nil) -> [String: Any] {
        guard let command = parameters.first?.lowercased() else {
            return ["success": false, "command": "screen", "error": "No screen command specified"]
        }

        guard let window = resolveWindow(windowID: windowID) else {
            return [
                "success": false,
                "command": "screen",
                "parameter": command,
                "error": windowID != nil
                    ? "No window found with ID \(windowID!)"
                    : "No frontmost window found"
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
    private func handleActionCommand(_ parameters: [String], windowID: CGWindowID? = nil) -> [String: Any] {
        guard let actionStr = parameters.first?.lowercased() else {
            return buildActionsResponse()
        }

        // First check for custom actions by name
        let customKeybinds = Defaults[.keybinds].filter { $0.direction.isCustomizable && $0.name != nil }
        if let customAction = customKeybinds.first(where: { ($0.name?.lowercased() ?? "") == actionStr }) {
            if let window = resolveWindow(windowID: windowID), let screen = NSScreen.main {
                activateAndResizeWindow(window, customAction, screen)
                return [
                    "success": true,
                    "command": "action",
                    "action": customAction.name ?? actionStr,
                    "window": windowJSON(window)
                ]
            } else {
                return [
                    "success": false,
                    "command": "action",
                    "parameter": actionStr,
                    "error": windowID != nil
                        ? "No window found with ID \(windowID!)"
                        : "No suitable window found"
                ]
            }
        }

        if actionStr == "list" {
            return buildActionsResponse()
        }

        if let direction = WindowDirection.allCases.first(where: { $0.rawValue.lowercased() == actionStr }) {
            if let window = resolveWindow(windowID: windowID), let screen = NSScreen.main {
                activateAndResizeWindow(window, .init(direction), screen)
                return [
                    "success": true,
                    "command": "action",
                    "action": direction.rawValue,
                    "window": windowJSON(window)
                ]
            } else {
                return [
                    "success": false,
                    "command": "action",
                    "parameter": actionStr,
                    "error": windowID != nil
                        ? "No window found with ID \(windowID!)"
                        : "No suitable window found"
                ]
            }
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
    private func handleKeybindCommand(_ parameters: [String], windowID: CGWindowID? = nil) -> [String: Any] {
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

        guard let window = resolveWindow(windowID: windowID) else {
            return [
                "success": false,
                "command": "keybind",
                "parameter": keybindName,
                "error": windowID != nil
                    ? "No window found with ID \(windowID!)"
                    : "No frontmost window found"
            ]
        }

        if let screen = NSScreen.main {
            Task {
                _ = try? await WindowActionEngine.shared.apply(
                    keybind, window: window, screen: screen
                )
            }
            return [
                "success": true,
                "command": "keybind",
                "keybind": keybind.name ?? keybindName,
                "window": windowJSON(window)
            ]
        } else {
            return [
                "success": false,
                "command": "keybind",
                "parameter": keybindName,
                "error": "No suitable window found"
            ]
        }
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

    // MARK: - Helper Methods

    /// Finds a window by its CGWindowID from the current window list
    /// - Parameter windowID: The CGWindowID to search for
    /// - Returns: The matching window, or nil if not found
    private func findWindowByID(_ windowID: CGWindowID) -> Window? {
        WindowUtility.windowList().first { $0.cgWindowID == windowID }
    }

    /// Resolves the target window — by ID if specified, otherwise the frontmost window
    /// - Parameter windowID: Optional CGWindowID to target a specific window
    /// - Returns: The resolved window, or nil if not found
    private func resolveWindow(windowID: CGWindowID? = nil) -> Window? {
        if let windowID {
            return findWindowByID(windowID)
        }
        return try? WindowUtility.frontmostWindow()
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
