//
//  CLIOutputFormatter.swift
//  LoopCLI
//
//  Created by Kai Azim on 2026-03-30.
//

import CoreGraphics
import Darwin
import Foundation

struct CLIOutputFormatter {
    private let executableName: String
    private let supportsANSIStyle = isatty(STDOUT_FILENO) != 0
        && ProcessInfo.processInfo.environment["NO_COLOR"] == nil
        && ProcessInfo.processInfo.environment["TERM"]?.lowercased() != "dumb"

    init(executableName: String) {
        self.executableName = executableName
    }

    func format(_ response: CLIResponse, mode: OutputOptions.Mode) -> String {
        guard mode == .human, let result = response.result else {
            return response.rawOutput
        }

        switch result {
        case let .windowList(result):
            return list(result.windows.map(windowItem), emptyMessage: "No windows")
        case let .screenList(result):
            return list(result.screens.map(screenItem), emptyMessage: "No screens")
        case let .actionList(result):
            return formatActions(result)
        case let .execution(result):
            return render(executionItem(result))
        }
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

        if components.count == 2, components[0] == "preset" {
            return "\(executableName) exec --preset \(components[1])"
        }

        if components.count == 2, components[0] == "custom" {
            return "\(executableName) exec --custom \(components[1])"
        }

        if components.count == 2, components[0] == "id" {
            return "\(executableName) exec --id \(components[1])"
        }

        return route
    }

    // MARK: - Layout

    /// Every entry is a bold name followed by an indented, dimmed line of details
    private struct Item {
        let name: String
        let details: [String]
    }

    private func render(_ item: Item) -> String {
        let details = item.details.filter { !$0.isEmpty }
        guard !details.isEmpty else {
            return bold(item.name)
        }

        return bold(item.name) + "\n" + dim("  " + details.joined(separator: " · "))
    }

    private func list(_ items: [Item], emptyMessage: String) -> String {
        guard !items.isEmpty else {
            return dim(emptyMessage)
        }

        return items.map(render).joined(separator: "\n")
    }

    private func section(_ title: String, items: [Item], emptyMessage: String) -> String {
        underline(title) + "\n" + list(items, emptyMessage: emptyMessage)
    }

    // MARK: - Results

    private func formatActions(_ result: LoopActionListResult) -> String {
        var sections: [String] = []

        if result.filter != .customOnly {
            for category in result.presetCategories where !category.actions.isEmpty {
                sections.append(section(category.name, items: category.actions.map(actionItem), emptyMessage: ""))
            }
        }

        if result.filter != .presetOnly {
            sections.append(section("Custom", items: result.customActions.map(actionItem), emptyMessage: "No custom actions"))
        }

        return sections.joined(separator: "\n\n")
    }

    private func windowItem(_ window: LoopWindowSummary) -> Item {
        Item(
            name: windowName(appName: window.appName, title: window.title),
            details: ["ID \(window.id)", window.bundleID, frameString(window.frame)]
        )
    }

    private func screenItem(_ screen: LoopScreenSummary) -> Item {
        Item(
            name: nonEmpty(screen.name) ?? "Screen",
            details: ["ID \(screen.id)", screen.isMain ? "main" : "", frameString(screen.frame)]
        )
    }

    private func actionItem(_ action: LoopActionDescriptor) -> Item {
        Item(
            name: sanitized(action.name),
            details: [sanitized(action.title), action.idString.map { "ID \($0)" } ?? ""]
        )
    }

    private func executionItem(_ result: LoopExecutionResult) -> Item {
        let action = sanitized(result.action.name)

        guard let window = result.targetWindow else {
            return Item(name: "Ran \(action)", details: [])
        }

        let target = nonEmpty(window.appName).map { " on \($0)" } ?? ""
        return Item(name: "Ran \(action)\(target)", details: ["ID \(window.id)", window.bundleID])
    }

    // MARK: - Text

    private func windowName(appName: String, title: String) -> String {
        switch (nonEmpty(appName), nonEmpty(title)) {
        case let (appName?, title?):
            "\(appName) — \(title)"
        case let (appName?, nil):
            appName
        case let (nil, title?):
            title
        case (nil, nil):
            "Untitled window"
        }
    }

    private func frameString(_ frame: LoopRect) -> String {
        "\(number(frame.width))×\(number(frame.height)) at \(number(frame.x)),\(number(frame.y))"
    }

    private func number(_ value: CGFloat) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }

        return String(format: "%.2f", Double(value))
            .replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
    }

    /// Trimmed and flattened to one line, or `nil` when empty
    private func nonEmpty(_ string: String) -> String? {
        let result = sanitized(string)
        return result.isEmpty ? nil : result
    }

    private func sanitized(_ string: String) -> String {
        string
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    // MARK: - Styling

    private func bold(_ string: String) -> String {
        styled(string, "1", "22")
    }

    private func dim(_ string: String) -> String {
        styled(string, "2", "22")
    }

    private func underline(_ string: String) -> String {
        styled(string, "1;4", "22;24")
    }

    private func styled(_ string: String, _ on: String, _ off: String) -> String {
        guard supportsANSIStyle else {
            return string
        }

        return "\u{001B}[\(on)m\(string)\u{001B}[\(off)m"
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
