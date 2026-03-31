//
//  CLIErrorFormatter.swift
//  LoopCLI
//
//  Created by Kai Azim on 2026-03-29.
//

import Foundation

struct CLICommandError: LocalizedError, CustomStringConvertible {
    let message: String

    var errorDescription: String? {
        message
    }

    var description: String {
        message
    }
}

struct CLIErrorFormatter {
    private let executableName: String

    init(executableName: String) {
        self.executableName = executableName
    }

    func runtimeError(_ message: String) -> CLICommandError {
        CLICommandError(message: message)
    }

    func error(from response: CLIResponse) -> CLICommandError {
        var lines: [String] = []

        if let errorMessage = response.automationError?.message, !errorMessage.isEmpty {
            lines.append(errorMessage)
        } else if !response.rawOutput.isEmpty {
            lines.append(response.rawOutput)
        } else {
            lines.append("Command failed")
        }

        if let replacement = response.automationError?.replacementRoute, !replacement.isEmpty {
            lines.append("Try: \(displayString(for: replacement))")
        }

        let availableRoutes = response.automationError?.availableRoutes ?? []
        if !availableRoutes.isEmpty {
            let displayedRoutes = availableRoutes.map(displayString)
            lines.append("Available routes: \(displayedRoutes.joined(separator: ", "))")
        }

        return CLICommandError(message: lines.joined(separator: "\n"))
    }

    private func displayString(for route: String) -> String {
        guard
            let url = URL(string: route),
            url.scheme?.lowercased() == "loop"
        else {
            return route
        }

        let components = (url.host.map { [$0.lowercased()] } ?? [])
            + url.pathComponents.filter { $0 != "/" && !$0.isEmpty }

        switch components {
        case ["list", "windows"]:
            return "\(executableName) list windows"
        case ["list", "screens"]:
            return "\(executableName) list screens"
        case ["list", "actions"]:
            return "\(executableName) list actions"
        case ["list", "actions", "directions"]:
            return "\(executableName) list actions --directions"
        case ["list", "actions", "keybinds"]:
            return "\(executableName) list actions --keybinds"
        default:
            break
        }

        if components.count == 2, components[0] == "direction" {
            return "\(executableName) exec --direction \(components[1])"
        }

        if components.count == 2, components[0] == "id" {
            return "\(executableName) exec --id \(components[1])"
        }

        return route
    }
}
