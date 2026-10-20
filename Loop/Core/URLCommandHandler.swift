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

 5. Workspace Commands:
    Format: loop://workspace/<name>
    Examples:
    - loop://workspace/Coding     (Apply the workspace named "Coding")
    - loop://workspace/restore    (Restore the remembered layout for the connected displays)

 6. List Commands:
    Format: loop://list/<type>
    Types:
    - actions    (List all window actions)
    - keybinds   (List all custom keybinds)
    - all        (List everything)

 Usage Tips:
 ----------
 1. All commands are case-insensitive
 2. Parameters with spaces must be URL encoded
 3. Window commands operate on the frontmost non-terminal window
 4. Use list commands to discover available options

 Examples:
 --------
 # Move current window to right half
 open "loop://direction/right"

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
        /// Saved workspaces and display layouts
        case workspace
        /// List available commands and options
        case list

        /// Human-readable description of each command type
        var description: String {
            switch self {
            case .direction: "Window direction command"
            case .screen: "Screen management"
            case .action: "Execute predefined window action"
            case .keybind: "Execute custom keybind action"
            case .workspace: "Apply a saved workspace"
            case .list: "List available commands"
            }
        }
    }

    // MARK: - Properties

    /// Tracks the last active window for context preservation
    private var lastActiveWindow: Window?

    /// Timestamp of last window activation
    private var lastActiveTime: Date?

    /// Current command being processed
    private var currentCommand: String?

    /// Buffer for collecting output before writing
    private var outputBuffer: [String] = []

    // MARK: - Output Handling

    /// Writes a message to either the buffer (for list commands) or stdout
    /// - Parameter message: The message to write
    private func writeToOutput(_ message: String) {
        // Remove [URLHandler] prefix and clean up the message
        let cleanMessage = message.replacingOccurrences(of: "[URLHandler] ", with: "")

        // Skip debug-only messages for regular output
        if cleanMessage.hasPrefix("Path components:") ||
            cleanMessage.hasPrefix("Found") ||
            cleanMessage.hasPrefix("Window:") ||
            (cleanMessage.hasPrefix("Processing") && !cleanMessage.contains("command:")) {
            log.info(cleanMessage)
            return
        }

        let output = cleanMessage
        if currentCommand?.contains("/list") == true {
            outputBuffer.append(output)
        } else {
            log.info("\(output)")
        }
        log.info(cleanMessage)
    }

    /// Writes a titled list of items to output
    /// - Parameters:
    ///   - title: The title for the list
    ///   - items: Array of items to list
    private func writeList(_ title: String, _ items: [String]) {
        let formattedItems = items.map { item in
            if item.hasPrefix("\n") {
                return item.replacingOccurrences(of: "\n", with: "")
            }
            return item
        }

        if currentCommand?.contains("/list") == true {
            outputBuffer.append(title)
            outputBuffer.append(contentsOf: formattedItems)
        } else {
            log.info("\n\(title)")
            formattedItems.forEach { log.info("\($0)") }
        }
    }

    /// Flushes the output buffer to a file for list commands
    /// - Note: Due to limitations with terminal output formatting and the complexity of the list output,
    ///         we use a temporary file to display the formatted list. This allows for proper spacing,
    ///         sections, and formatting that would be difficult to achieve with direct terminal output.
    ///         The file is automatically opened and then deleted after 60 seconds to keep the system clean.
    private func flushOutput() {
        guard currentCommand?.contains("/list") == true,
              !outputBuffer.isEmpty else {
            outputBuffer.removeAll()
            return
        }

        // Create a unique temporary file that will be automatically cleaned up
        let timestamp = Date().timeIntervalSince1970
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("loop_output_\(timestamp).txt")

        do {
            try outputBuffer.joined(separator: "\n").write(to: tempFile, atomically: true, encoding: .utf8)
            NSWorkspace.shared.open(tempFile)

            // Schedule file deletion after a delay
            // We use a longer delay (60s) to ensure the user has time to read the content
            Task {
                try? await Task.sleep(for: .seconds(60))

                do {
                    try FileManager.default.removeItem(at: tempFile)
                    log.info("Cleaned up temporary file: \(tempFile.lastPathComponent)")
                } catch {
                    log.error("Failed to clean up temporary file: \(error.localizedDescription)")
                }
            }
        } catch {
            log.error("Failed to write output: \(error.localizedDescription)")

            // Fallback to direct console output if file operations fail
            log.info("\(outputBuffer.joined(separator: "\n"))")
        }

        outputBuffer.removeAll()
    }

    // MARK: - Public Methods

    /// Handles incoming URL scheme requests
    /// - Parameter url: The URL to process
    /// - Throws: URLError for invalid URLs or commands
    func handle(_ url: URL) {
        currentCommand = url.absoluteString
        writeToOutput("[URLHandler] Processing URL: \(url)")

        guard url.scheme?.lowercased() == "loop" else {
            writeToOutput("[URLHandler] Invalid scheme: \(url.scheme ?? "nil")")
            writeToOutput("[URLHandler] Required format: loop://<command>/<parameters>")
            return
        }

        let components = (url.host.map { [$0] } ?? []) + url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        writeToOutput("[URLHandler] Path components: \(components)")

        guard let commandString = components.first,
              let command = Command(rawValue: commandString.lowercased()) else {
            writeToOutput("[URLHandler] Invalid command: \(components.first ?? "nil")")
            writeToOutput("[URLHandler] Available commands: \(Command.allCases.map(\.rawValue).joined(separator: ", "))")
            return
        }

        processCommand(command, Array(components.dropFirst()))
    }

    // MARK: - Command Processing

    /// Processes a command with its parameters
    /// - Parameters:
    ///   - command: The command to process
    ///   - parameters: Array of command parameters
    private func processCommand(_ command: Command, _ parameters: [String]) {
        log.info(command.rawValue)
        log.info(parameters.description)

        switch command {
        case .direction: handleDirectionCommand(parameters)
        case .screen: handleScreenCommand(parameters)
        case .action: handleActionCommand(parameters)
        case .keybind: handleKeybindCommand(parameters)
        case .workspace: handleWorkspaceCommand(parameters)
        case .list: handleListCommand(parameters)
        }

        flushOutput()
    }

    /// Handles window direction commands
    /// - Parameter parameters: Direction parameters
    private func handleDirectionCommand(_ parameters: [String]) {
        guard let directionStr = parameters.first?.lowercased() else {
            writeToOutput("No direction specified")
            writeToOutput("Available directions:")
            writeToOutput("  Basic: left, right, top, bottom")
            writeToOutput("  Full names: \(WindowDirection.allCases.map { $0.rawValue.lowercased() }.joined(separator: ", "))")
            return
        }

        // If this is a list command, redirect to the action handler
        if directionStr == "list" {
            handleListCommand(["actions"])
            return
        }

        writeToOutput("Processing direction: \(directionStr)")

        // First check if this is a custom action being called via direction
        if directionStr.hasPrefix("custom") || directionStr.hasPrefix("stash") {
            handleActionCommand(parameters)
            return
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
            executeWindowAction(direction)
        } else {
            writeToOutput("Invalid direction: \(directionStr)")
            writeToOutput("Available directions:")
            writeToOutput("  Basic: left, right, top, bottom")
            writeToOutput("  Full names: \(WindowDirection.allCases.map { $0.rawValue.lowercased() }.joined(separator: ", "))")
        }
    }

    /// Handles workspace commands
    /// - Parameter parameters: The workspace name, or `restore` for the display layout
    private func handleWorkspaceCommand(_ parameters: [String]) {
        guard let name = parameters.first else {
            writeToOutput("No workspace specified")
            writeToOutput("Available workspaces: \(Defaults[.workspaces].map(\.name).joined(separator: ", "))")
            return
        }

        Task { @MainActor in
            if name.lowercased() == "restore" {
                await DisplayMemoryManager.shared.restoreLayout()
            } else if !WorkspaceManager.shared.apply(named: name) {
                writeToOutput("Workspace not found: \(name)")
                writeToOutput("Available workspaces: \(Defaults[.workspaces].map(\.name).joined(separator: ", "))")
            }
        }
    }

    /// Executes a window action for a given direction
    /// - Parameter direction: The direction to move/resize the window
    private func executeWindowAction(_ direction: WindowDirection) {
        writeToOutput("[URLHandler] Executing direction: \(direction.rawValue)")

        let allWindows = WindowUtility.windowList()
        writeToOutput("[URLHandler] Found \(allWindows.count) total windows")

        let visibleWindows = allWindows.filter { win in
            guard let app = win.nsRunningApplication else {
                writeToOutput("[URLHandler] Window has no application: \(win.title ?? "unknown")")
                return false
            }

            let isLoop = app.bundleIdentifier == Bundle.main.bundleIdentifier
            let isRegular = app.activationPolicy == .regular
            let isVisible = !win.isApplicationHidden && !win.minimized

            logWindowDetails(win, app, isLoop, isRegular, isVisible)

            return !isLoop && isRegular && isVisible
        }

        writeToOutput("[URLHandler] Found \(visibleWindows.count) eligible windows")

        guard let window = findTargetWindow(from: visibleWindows),
              let screen = NSScreen.main else {
            writeToOutput("[URLHandler] No suitable windows or screen found")
            return
        }

        logSelectedWindow(window, screen)

        let action = WindowAction(direction)
        writeToOutput("[URLHandler] Resizing window with action: \(direction.rawValue)")

        activateAndResizeWindow(window, action, screen)
    }

    /// Handles screen management commands
    /// - Parameter parameters: Screen command parameters
    private func handleScreenCommand(_ parameters: [String]) {
        guard let command = parameters.first?.lowercased(),
              let window = try? WindowUtility.frontmostWindow() else {
            writeToOutput("[URLHandler] No screen command or window")
            return
        }

        writeToOutput("[URLHandler] Processing screen command: \(command)")

        let direction: WindowDirection = command == "next" ? .nextScreen : .previousScreen
        moveWindowToScreen(window, direction)
    }

    /// Handles predefined window actions
    /// - Parameter parameters: Action parameters
    private func handleActionCommand(_ parameters: [String]) {
        guard let actionStr = parameters.first?.lowercased() else {
            printAvailableActions()
            return
        }

        // First check for custom actions by name
        let customKeybinds = Defaults[.keybinds].filter { $0.direction.isCustomizable && $0.name != nil }
        if let customAction = customKeybinds.first(where: { ($0.name?.lowercased() ?? "") == actionStr }) {
            writeToOutput("Executing custom action: \(customAction.name ?? "unnamed")")

            // Try multiple methods to get the target window
            let targetWindow = findTargetWindow(from: WindowUtility.windowList().filter { win in
                guard let app = win.nsRunningApplication else { return false }
                return app.activationPolicy == .regular && !win.isApplicationHidden && !win.minimized
            })

            if let window = targetWindow,
               let screen = NSScreen.main {
                writeToOutput("Found target window: \(window.title ?? "unknown")")
                activateAndResizeWindow(window, customAction, screen)
            } else {
                writeToOutput("Error: Could not find a suitable window to apply the custom action")
            }
        } else if actionStr == "list" {
            // For list command, just show the actions without the invalid message
            printAvailableActions()
        } else if let direction = WindowDirection.allCases.first(where: { $0.rawValue.lowercased() == actionStr }),
                  let window = findTargetWindow(from: WindowUtility.windowList()),
                  let screen = NSScreen.main {
            writeToOutput("Executing action: \(direction.rawValue)")
            activateAndResizeWindow(window, .init(direction), screen)
        } else {
            writeToOutput("Invalid action: \(actionStr)")
            printAvailableActions()
        }
    }

    /// Prints all available window actions in categories
    private func printAvailableActions() {
        var items: [String] = []

        // Get any custom keybinds with names and custom direction
        let customKeybinds = Defaults[.keybinds].filter { $0.direction == .custom && $0.name?.isEmpty == false }
        if !customKeybinds.isEmpty {
            items.append("Custom Actions:")
            items.append(contentsOf: customKeybinds.compactMap { keybind in
                guard let name = keybind.name else { return nil }
                return "  • loop://action/\(name.lowercased())"
            })
            items.append("")
        }

        // Get any stash keybinds with names and custom direction
        let stashKeybinds = Defaults[.keybinds].filter { $0.direction == .stash && $0.name?.isEmpty == false }
        if !stashKeybinds.isEmpty {
            items.append("Stash Actions:")
            items.append(contentsOf: stashKeybinds.compactMap { keybind in
                guard let name = keybind.name else { return nil }
                return "  • loop://action/\(name.lowercased())"
            })
            items.append("")
        }

        let categories: [(String, [WindowDirection])] = [
            ("General Actions", Array(WindowDirection.general.dropFirst(3))), // Drop first 3 actions
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

        for (title, actions) in categories {
            if !actions.isEmpty {
                items.append("\(title):")
                items.append(contentsOf: actions.map { "  • loop://action/\($0.rawValue.lowercased())" })
                items.append("")
            }
        }

        // Remove the last empty line if it exists
        if items.last?.isEmpty == true {
            items.removeLast()
        }

        writeList("", items)
    }

    /// Handles custom keybind execution
    /// - Parameter parameters: Keybind parameters
    private func handleKeybindCommand(_ parameters: [String]) {
        guard let keybindName = parameters.first else {
            writeToOutput("[URLHandler] No keybind specified")
            return
        }

        let keybinds = Defaults[.keybinds]

        if keybindName.lowercased() == "list" {
            writeToOutput("[URLHandler] Available keybinds:")
            keybinds.compactMap(\.name).forEach { writeToOutput("  - \($0)") }
            return
        }

        if let keybind = keybinds.first(where: { $0.name?.lowercased() == keybindName.lowercased() }) {
            writeToOutput("[URLHandler] Executing keybind: \(keybind.name ?? "unnamed")")
            if let window = WindowUtility.userDefinedTargetWindow(),
               let screen = NSScreen.main {
                Task {
                    _ = try? await WindowActionEngine.shared.apply(
                        keybind,
                        window: window,
                        screen: screen
                    )
                }
            }
        } else {
            writeToOutput("[URLHandler] Keybind not found: \(keybindName)")
            writeToOutput("[URLHandler] Available keybinds:")
            keybinds.compactMap(\.name).forEach { writeToOutput("  - \($0)") }
        }
    }

    /// Handles list commands for viewing available options
    /// - Parameter parameters: List parameters
    private func handleListCommand(_ parameters: [String]) {
        let type = parameters.first?.lowercased() ?? "all"
        var items: [String] = []

        switch type {
        case "actions":
            items.append("Available Actions:")
            // Get any custom keybinds with names and custom direction
            let customKeybinds = Defaults[.keybinds].filter { $0.direction == .custom && $0.name?.isEmpty == false }
            if !customKeybinds.isEmpty {
                items.append("\nCustom Actions:")
                items.append(contentsOf: customKeybinds.compactMap { keybind in
                    guard let name = keybind.name else { return nil }
                    return "  • loop://action/\(name.lowercased())"
                })
            }

            // Get any stash keybinds with names and custom direction
            let stashKeybinds = Defaults[.keybinds].filter { $0.direction == .stash && $0.name?.isEmpty == false }
            if !stashKeybinds.isEmpty {
                items.append("\nStash Actions:")
                items.append(contentsOf: stashKeybinds.compactMap { keybind in
                    guard let name = keybind.name else { return nil }
                    return "  • loop://action/\(name.lowercased())"
                })
            }

            let categories: [(String, [WindowDirection])] = [
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

            for (title, actions) in categories {
                if !actions.isEmpty {
                    items.append("\n\(title):")
                    items.append(contentsOf: actions.map { "  • loop://action/\($0.rawValue.lowercased())" })
                }
            }

        case "keybinds":
            items.append("Available Keybinds:")
            items.append(contentsOf: Defaults[.keybinds].compactMap { keybind in
                guard let name = keybind.name else { return nil }
                return "  • loop://keybind/\(name)"
            })

        default:
            items.append("Available Commands:")

            items.append("\nDirection Commands:")
            items.append(contentsOf: WindowDirection.allCases.map { "  • loop://direction/\($0.rawValue.lowercased())" })

            items.append("\nScreen Commands:")
            items.append("  • loop://screen/next")
            items.append("  • loop://screen/previous")

            items.append("\nActions:")
            // Get any custom keybinds with names and custom direction
            let customKeybinds = Defaults[.keybinds].filter { $0.direction == .custom && $0.name?.isEmpty == false }
            if !customKeybinds.isEmpty {
                items.append("\nCustom Actions:")
                items.append(contentsOf: customKeybinds.compactMap { keybind in
                    guard let name = keybind.name else { return nil }
                    return "  • loop://action/\(name.lowercased())"
                })
            }

            // Get any stash keybinds with names and custom direction
            let stashKeybinds = Defaults[.keybinds].filter { $0.direction == .stash && $0.name?.isEmpty == false }
            if !stashKeybinds.isEmpty {
                items.append("\nStash Actions:")
                items.append(contentsOf: stashKeybinds.compactMap { keybind in
                    guard let name = keybind.name else { return nil }
                    return "  • loop://action/\(name.lowercased())"
                })
            }

            items.append("\nKeybind Commands:")
            items.append(contentsOf: Defaults[.keybinds].compactMap { keybind in
                guard let name = keybind.name else { return nil }
                return "  • loop://keybind/\(name)"
            })

            items.append("\nList Commands:")
            items.append("  • loop://list/actions")
            items.append("  • loop://list/keybinds")
            items.append("  • loop://list/all")
        }

        writeList(type == "all" ? "All Commands" : items.removeFirst(), Array(items))
    }

    // MARK: - Helper Methods

    /// Finds the most appropriate target window for an action
    /// - Parameter visibleWindows: Array of visible windows to choose from
    /// - Returns: The most appropriate window or nil if none found
    private func findTargetWindow(from visibleWindows: [Window]) -> Window? {
        if let targetWindow = WindowUtility.userDefinedTargetWindow() {
            writeToOutput("[URLHandler] Using WindowEngine.getTargetWindow(): \(targetWindow.title ?? "unknown")")
            return targetWindow
        }

        if let lastWindow = lastActiveWindow,
           let app = lastWindow.nsRunningApplication,
           app.bundleIdentifier != Bundle.main.bundleIdentifier,
           !lastWindow.isApplicationHidden, !lastWindow.minimized,
           let lastTime = lastActiveTime,
           lastTime.timeIntervalSinceNow > -5 {
            writeToOutput("[URLHandler] Using last active window: \(lastWindow.title ?? "unknown")")
            return lastWindow
        }

        return visibleWindows.first
    }

    /// Logs window details for debugging
    private func logWindowDetails(_ window: Window, _ app: NSRunningApplication, _ isLoop: Bool, _ isRegular: Bool, _ isVisible: Bool) {
        writeToOutput("[URLHandler] Window: \(window.title ?? "unknown")")
        writeToOutput("  - App: \(app.localizedName ?? "unknown")")
        writeToOutput("  - Bundle ID: \(app.bundleIdentifier ?? "unknown")")
        writeToOutput("  - Is Loop: \(isLoop)")
        writeToOutput("  - Is Regular: \(isRegular)")
        writeToOutput("  - Is Visible: \(isVisible)")
    }

    /// Logs selected window details
    private func logSelectedWindow(_ window: Window, _ screen: NSScreen) {
        writeToOutput("[URLHandler] Selected window for action:")
        writeToOutput("  - Title: \(window.title ?? "unknown")")
        writeToOutput("  - App: \(window.nsRunningApplication?.localizedName ?? "unknown")")
        writeToOutput("  - Screen: \(screen.localizedName)")
        writeToOutput("  - Current Frame: \(window.frame)")
    }

    /// Activates and resizes a window
    private func activateAndResizeWindow(_ window: Window, _ action: WindowAction, _ screen: NSScreen) {
        lastActiveWindow = window
        lastActiveTime = Date()

        if let app = window.nsRunningApplication {
            writeToOutput("[URLHandler] Activating application: \(app.localizedName ?? "unknown")")
            app.activate(options: .activateIgnoringOtherApps)
        }

        Task {
            try? await Task.sleep(for: .seconds(0.1))

            writeToOutput("[URLHandler] Executing resize operation")
            _ = try? await WindowActionEngine.shared.apply(
                action,
                window: window,
                screen: screen
            )
            writeToOutput("[URLHandler] New window frame: \(window.frame)")
        }
    }

    /// Moves a window to another screen
    private func moveWindowToScreen(_ window: Window, _ direction: WindowDirection) {
        if let currentScreen = ScreenUtility.screenContaining(window),
           let targetScreen = direction == .nextScreen ?
           ScreenUtility.nextScreen(from: currentScreen) :
           ScreenUtility.previousScreen(from: currentScreen) {
            writeToOutput("[URLHandler] Moving window to screen: \(targetScreen.localizedName)")
            Task {
                _ = try? await WindowActionEngine.shared.apply(
                    .init(direction),
                    window: window,
                    screen: targetScreen
                )
            }
        } else {
            writeToOutput("[URLHandler] Failed to find target screen")
        }
    }
}
