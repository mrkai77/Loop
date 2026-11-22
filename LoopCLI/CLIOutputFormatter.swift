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
    /// Only on a terminal, and only when `NO_COLOR` isn't set to anything (https://no-color.org)
    private let usesANSIStyle = isatty(STDOUT_FILENO) != 0
        && (ProcessInfo.processInfo.environment["NO_COLOR"] ?? "").isEmpty
        && ProcessInfo.processInfo.environment["TERM"]?.lowercased() != "dumb"

    init(executableName: String) {
        self.executableName = executableName
    }

    func format(_ response: CLIResponse) -> String {
        guard let result = response.result else {
            return response.rawOutput
        }

        let text = LoopAutomationFormatter().format(result)
        return usesANSIStyle ? text.ansiText : text.plainText
    }

    /// Loop's message, plus the commands that might help, as CLI invocations
    func errorMessage(from response: CLIResponse) -> String {
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

        return lines.joined(separator: "\n")
    }

    private func displayString(for route: String) -> String {
        LoopRoute(string: route)?.commandLineInvocation(executableName: executableName) ?? route
    }
}
