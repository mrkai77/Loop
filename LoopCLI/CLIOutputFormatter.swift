//
//  CLIOutputFormatter.swift
//  LoopCLI
//
//  Created by Kai Azim on 2026-03-30.
//

import Darwin
import Foundation

struct CLIOutputFormatter {
    private let executableName: String
    private let usesANSIStyle = isatty(STDOUT_FILENO) != 0
        && ProcessInfo.processInfo.environment["NO_COLOR"] == nil
        && ProcessInfo.processInfo.environment["TERM"]?.lowercased() != "dumb"

    init(executableName: String) {
        self.executableName = executableName
    }

    func format(_ response: CLIResponse, mode: OutputOptions.Mode) -> String {
        guard mode == .human, let result = response.result else {
            return response.rawOutput
        }

        let text = LoopAutomationFormatter().format(result)
        return usesANSIStyle ? text.ansiText : text.plainText
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
            lines.append("Available commands: \(displayedRoutes.joined(separator: ", "))")
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
        case ["list", "actions", "preset"]:
            return "\(executableName) list actions --preset"
        case ["list", "actions", "custom"]:
            return "\(executableName) list actions --custom"
        default:
            break
        }

        if components.count == 3, components[0] == "exec", ["preset", "custom", "id"].contains(components[1]) {
            return "\(executableName) exec --\(components[1]) \(components[2])"
        }

        return route
    }
}

struct CLICommandError: LocalizedError, CustomStringConvertible {
    let message: String

    var errorDescription: String? {
        message
    }

    var description: String {
        message
    }
}
