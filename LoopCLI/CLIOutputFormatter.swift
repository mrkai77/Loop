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

    init(executableName: String) {
        self.executableName = executableName
    }

    /// Tables on a terminal, and tab-separated lines when piped, like `gh`
    private static var layout: LoopAutomationFormatter.Layout {
        isatty(STDOUT_FILENO) != 0 ? .table(maxWidth: terminalWidth) : .tabSeparated
    }

    private static var terminalWidth: Int? {
        var size = winsize()
        if ioctl(STDOUT_FILENO, TIOCGWINSZ, &size) == 0, size.ws_col > 0 {
            return Int(size.ws_col)
        }

        return ProcessInfo.processInfo.environment["COLUMNS"].flatMap(Int.init)
    }

    /// Follows https://no-color.org and https://bixense.com/clicolors, and leaves dumb terminals alone
    static func usesColor(on fileDescriptor: Int32) -> Bool {
        let environment = ProcessInfo.processInfo.environment
        guard (environment["NO_COLOR"] ?? "").isEmpty, environment["TERM"]?.lowercased() != "dumb" else {
            return false
        }

        if let force = environment["CLICOLOR_FORCE"], !force.isEmpty, force != "0" {
            return true
        }

        return isatty(fileDescriptor) != 0
    }

    /// `nil` when there's nothing to print, like an empty list that's piped
    func format(_ response: CLIResponse) -> String? {
        guard let result = response.result else {
            return response.rawOutput.isEmpty ? nil : response.rawOutput
        }

        let text = LoopAutomationFormatter(layout: Self.layout).format(result)
        guard !text.isEmpty else {
            return nil
        }

        return Self.usesColor(on: STDOUT_FILENO) ? text.ansiText : text.plainText
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
