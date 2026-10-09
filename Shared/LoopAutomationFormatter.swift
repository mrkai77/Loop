//
//  LoopAutomationFormatter.swift
//  Loop
//
//  Created by Kai Azim on 2026-03-30.
//

import CoreGraphics
import Foundation

/// Styled text that `loop-cli` renders with ANSI codes and Loop's output window renders with colors
struct LoopAutomationText {
    enum Style {
        case plain
        case bold
        case secondary
        case heading
    }

    struct Run {
        let text: String
        let style: Style
    }

    private(set) var runs: [Run] = []

    init(_ text: String = "", style: Style = .plain) {
        if !text.isEmpty {
            self.runs = [Run(text: text, style: style)]
        }
    }

    static func + (lhs: Self, rhs: Self) -> Self {
        var result = lhs
        result.runs += rhs.runs
        return result
    }

    var plainText: String {
        runs.map(\.text).joined()
    }

    var ansiText: String {
        runs.map { run in
            switch run.style {
            case .plain: run.text
            case .bold: "\u{001B}[1m\(run.text)\u{001B}[22m"
            case .secondary: "\u{001B}[2m\(run.text)\u{001B}[22m"
            case .heading: "\u{001B}[1;4m\(run.text)\u{001B}[22;24m"
            }
        }
        .joined()
    }
}

extension [LoopAutomationText] {
    func joined(separator: String) -> LoopAutomationText {
        reduce(into: LoopAutomationText()) { result, text in
            if !result.runs.isEmpty {
                result = result + LoopAutomationText(separator)
            }
            result = result + text
        }
    }
}

/// Readable text for automation results, shared by `loop-cli` and Loop's output window
struct LoopAutomationFormatter {
    func format(_ result: LoopAutomationResult) -> LoopAutomationText {
        switch result {
        case let .windowList(result):
            list(result.windows.map(windowItem), emptyMessage: "No windows")
        case let .screenList(result):
            list(result.screens.map(screenItem), emptyMessage: "No screens")
        case let .actionList(result):
            formatActions(result)
        case let .execution(result):
            render(executionItem(result))
        }
    }

    // MARK: - Layout

    /// Every entry is a bold name followed by an indented, dimmed line of details
    private struct Item {
        let name: String
        let details: [String]
    }

    private func render(_ item: Item) -> LoopAutomationText {
        let name = LoopAutomationText(item.name, style: .bold)
        let details = item.details.filter { !$0.isEmpty }
        guard !details.isEmpty else {
            return name
        }

        return name + LoopAutomationText("\n") + LoopAutomationText("  " + details.joined(separator: " · "), style: .secondary)
    }

    private func list(_ items: [Item], emptyMessage: String) -> LoopAutomationText {
        guard !items.isEmpty else {
            return LoopAutomationText(emptyMessage, style: .secondary)
        }

        return items.map(render).joined(separator: "\n")
    }

    private func section(_ title: String, items: [Item], emptyMessage: String) -> LoopAutomationText {
        LoopAutomationText(title, style: .heading) + LoopAutomationText("\n") + list(items, emptyMessage: emptyMessage)
    }

    // MARK: - Results

    private func formatActions(_ result: LoopActionListResult) -> LoopAutomationText {
        var sections: [LoopAutomationText] = []

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
            "\(appName) - \(title)"
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
}
