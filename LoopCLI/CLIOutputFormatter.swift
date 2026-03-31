//
//  CLIOutputFormatter.swift
//  LoopCLI
//
//  Created by Kai Azim on 2026-03-30.
//

import Darwin
import Foundation
import CoreGraphics

struct CLIOutputFormatter {
    private let supportsANSIStyle = isatty(STDOUT_FILENO) != 0
        && ProcessInfo.processInfo.environment["NO_COLOR"] == nil
        && ProcessInfo.processInfo.environment["TERM"]?.lowercased() != "dumb"

    func format(_ response: CLIResponse, configuration: CLIOutputConfiguration) -> String {
        switch configuration.mode {
        case .json:
            return response.rawOutput
        case .human:
            guard let result = response.result else {
                return response.rawOutput
            }

            switch result {
            case let .windowList(result):
                return formatWindows(result.windows)
            case let .screenList(result):
                return formatScreens(result.screens)
            case let .actionList(result):
                return formatActions(result, showIDs: configuration.showIDs)
            case let .execution(result):
                return formatExecution(result)
            }
        }
    }

    private func formatWindows(_ windows: [LoopWindowSummary]) -> String {
        guard !windows.isEmpty else {
            return "No windows"
        }

        return windows.enumerated().map { index, window in
            var lines = [windowPrimaryLine(appName: window.appName, title: window.title, fallback: "Window \(index + 1)")]

            if let metadata = windowMetadataLine(
                bundleID: window.bundleID,
                idLabel: "Window ID",
                id: window.id,
                frame: window.frame
            ) {
                lines.append(dim(metadata))
            }

            return lines.joined(separator: "\n")
        }.joined(separator: "\n\n")
    }

    private func formatScreens(_ screens: [LoopScreenSummary]) -> String {
        guard !screens.isEmpty else {
            return "No screens"
        }

        return screens.enumerated().map { index, screen in
            var lines = [screenPrimaryLine(screen, fallback: "Screen \(index + 1)")]

            if let metadata = screenMetadataLine(screen) {
                lines.append(dim(metadata))
            }

            return lines.joined(separator: "\n")
        }.joined(separator: "\n\n")
    }

    private func formatActions(_ result: LoopActionListResult, showIDs: Bool) -> String {
        var sections: [String] = []

        if !result.directionCategories.isEmpty {
            sections.append(formatDirectionSections(result.directionCategories, showIDs: showIDs))
        }

        if !result.keybindActions.isEmpty || result.filter == .keybindsOnly || result.filter == .all {
            sections.append(formatKeybindSection(result.keybindActions, showIDs: showIDs))
        }

        let nonEmptySections = sections.filter { !$0.isEmpty }
        if nonEmptySections.isEmpty {
            return "No actions"
        }

        return nonEmptySections.joined(separator: "\n\n")
    }

    private func formatDirectionSections(_ categories: [LoopActionCategory], showIDs: Bool) -> String {
        guard !categories.isEmpty else {
            return "\(bold("- Direction Actions (Built-in) -"))\n\n\(dim("None"))"
        }

        var lines = [bold("- Direction Actions (Built-in) -")]

        for category in categories where !category.actions.isEmpty {
            lines.append("")
            lines.append(bold(sanitizeInline(category.name)))
            lines.append(contentsOf: formatActionRows(category.actions, showIDs: showIDs))
        }

        return lines.joined(separator: "\n")
    }

    private func formatKeybindSection(_ keybinds: [LoopActionDescriptor], showIDs: Bool) -> String {
        var lines = [bold("- User-Configured Keybind Actions -")]

        guard !keybinds.isEmpty else {
            lines.append("")
            lines.append(dim("None"))
            return lines.joined(separator: "\n")
        }

        lines.append("")
        lines.append(contentsOf: formatActionRows(keybinds, showIDs: showIDs))

        return lines.joined(separator: "\n")
    }

    private func formatExecution(_ result: LoopExecutionResult) -> String {
        let slug = sanitizeInline(result.action.slug)

        guard let window = result.targetWindow else {
            return "Successfully executed \(slug)"
        }

        if let appName = nonEmptyString(window.appName).map(sanitizeInline) {
            return "Successfully executed \(slug) on \(appName) (Window ID: \(window.id))"
        }

        return "Successfully executed \(slug) (Window ID: \(window.id))"
    }

    private func formatActionRows(_ actions: [LoopActionDescriptor], showIDs: Bool) -> [String] {
        let rows = actions.map { action in
            (slug: sanitizeInline(action.slug), id: action.idString)
        }

        guard showIDs else {
            return rows.map { blue($0.slug) }
        }

        let slugColumnWidth = rows.map(\.slug.count).max() ?? 0

        return rows.map { row in
            let paddedSlug = row.slug.padding(toLength: slugColumnWidth, withPad: " ", startingAt: 0)
            return "\(blue(paddedSlug))  \(dim(row.id))"
        }
    }

    private func windowPrimaryLine(appName: String, title: String, fallback: String) -> String {
        let sanitizedAppName = nonEmptyString(appName).map(sanitizeInline)
        let sanitizedTitle = nonEmptyString(title).map(quotedTitle)

        switch (sanitizedAppName, sanitizedTitle) {
        case let (appName?, title?):
            return "\(bold(appName)) \(title)"
        case let (appName?, nil):
            return bold(appName)
        case let (nil, title?):
            return title
        case (nil, nil):
            return fallback
        }
    }

    private func windowMetadataLine(
        bundleID: String,
        idLabel: String,
        id: UInt32,
        frame: LoopRect?
    ) -> String? {
        var parts: [String] = []

        if let bundleID = nonEmptyString(bundleID) {
            parts.append("Bundle ID: \(bundleID)")
        }

        parts.append("\(idLabel): \(id)")

        if let frame {
            parts.append("Frame: \(formatLength(frame.width))x\(formatLength(frame.height)) @ \(formatCoordinate(frame.x)),\(formatCoordinate(frame.y))")
        }

        return parts.isEmpty ? nil : parts.joined(separator: " | ")
    }

    private func screenPrimaryLine(_ screen: LoopScreenSummary, fallback: String) -> String {
        let name = nonEmptyString(screen.name).map(sanitizeInline) ?? fallback
        return screen.isMain ? "\(bold(name)) [main]" : bold(name)
    }

    private func screenMetadataLine(_ screen: LoopScreenSummary) -> String? {
        "Screen ID: \(screen.id) | Frame: \(formatLength(screen.frame.width))x\(formatLength(screen.frame.height)) @ \(formatCoordinate(screen.frame.x)),\(formatCoordinate(screen.frame.y))"
    }

    private func formatLength(_ value: CGFloat) -> String {
        formatCGFloat(value)
    }

    private func formatCoordinate(_ value: CGFloat) -> String {
        formatCGFloat(value)
    }

    private func formatCGFloat(_ value: CGFloat) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }

        let formatted = String(format: "%.2f", Double(value))
        return formatted
            .replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
    }

    private func nonEmptyString(_ string: String) -> String? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func sanitizeInline(_ string: String) -> String {
        string
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func quotedTitle(_ string: String) -> String {
        let sanitized = sanitizeInline(string).replacingOccurrences(of: "'", with: "\\'")
        return "'\(sanitized)'"
    }

    private func bold(_ string: String) -> String {
        guard supportsANSIStyle else {
            return string
        }

        return "\u{001B}[1m\(string)\u{001B}[22m"
    }

    private func dim(_ string: String) -> String {
        guard supportsANSIStyle else {
            return string
        }

        return "\u{001B}[2m\(string)\u{001B}[22m"
    }

    private func blue(_ string: String) -> String {
        guard supportsANSIStyle else {
            return string
        }

        return "\u{001B}[34m\(string)\u{001B}[39m"
    }
}
