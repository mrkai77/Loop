//
//  LegacyRoutes.swift
//  Loop
//
//  Created by Kai Azim on 2026-11-25.
//

import Foundation

/// Routes from before the CLI, which shipped in the URL scheme's documentation
extension AutomationRequest {
    /// Which keybinds an older `action/<name>` or `keybind/<name>` URL matches by name
    enum LegacyNameScope: Equatable {
        /// `action/`, which only matched custom and stash actions by name, then built-in actions
        case customOrBuiltIn
        /// `keybind/`, which matched any keybind
        case keybinds
    }

    static func legacyCommand(from components: [String]) -> Command? {
        guard components.count == 2 else {
            return nil
        }

        let command = components[0].lowercased()
        let argument = components[1]

        // `direction/` sent names starting with "custom" or "stash" to the custom action lookup, like `action/`
        if command == "direction", ["custom", "stash"].contains(where: argument.lowercased().hasPrefix) {
            return .legacyNamedAction(argument, scope: .customOrBuiltIn)
        }

        if let route = legacyRoute(from: components) {
            return .route(route)
        }

        switch command {
        case "action":
            return .legacyNamedAction(argument, scope: .customOrBuiltIn)
        case "keybind":
            return .legacyNamedAction(argument, scope: .keybinds)
        default:
            return nil
        }
    }

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
