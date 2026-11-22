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
            formatActions(result.actions)
        case let .bindingList(result):
            list(result.bindings.map(bindingItem), emptyMessage: emptyMessage(for: result.bindingKind))
        case let .run(result):
            render(runItem(result))
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

    private func section(_ title: String, items: [Item]) -> LoopAutomationText {
        LoopAutomationText(title, style: .heading) + LoopAutomationText("\n") + list(items, emptyMessage: "")
    }

    // MARK: - Results

    /// Grouped by category, in the order they arrive
    private func formatActions(_ actions: [LoopActionSummary]) -> LoopAutomationText {
        guard !actions.isEmpty else {
            return LoopAutomationText("No actions", style: .secondary)
        }

        var categories: [(name: String, actions: [LoopActionSummary])] = []
        for action in actions {
            if let index = categories.firstIndex(where: { $0.name == action.category }) {
                categories[index].actions.append(action)
            } else {
                categories.append((action.category, [action]))
            }
        }

        return categories
            .map { section(sanitized($0.name), items: $0.actions.map(actionItem)) }
            .joined(separator: "\n\n")
    }

    private func emptyMessage(for kind: LoopBindingKind) -> String {
        switch kind {
        case .keybind: "No keybinds"
        case .gesture: "No gestures"
        case .radialMenu: "No radial menu actions"
        }
    }

    private func windowItem(_ window: LoopWindowSummary) -> Item {
        Item(
            name: windowName(appName: window.appName, title: window.title),
            details: ["ID \(window.id)", window.bundleID ?? "", frameString(window.frame)]
        )
    }

    private func screenItem(_ screen: LoopScreenSummary) -> Item {
        Item(
            name: nonEmpty(screen.name) ?? "Screen",
            details: ["ID \(screen.id)", screen.isMain ? "Main" : "", frameString(screen.frame)]
        )
    }

    private func actionItem(_ action: LoopActionSummary) -> Item {
        Item(name: action.key, details: [sanitized(action.name)])
    }

    private func bindingItem(_ binding: LoopBindingSummary) -> Item {
        let fallbackName = binding.kind == .gesture && binding.id == nil ? "Opens the radial menu" : "No action"
        let name = binding.action.flatMap { nonEmpty($0.name) } ?? fallbackName
        return Item(
            name: name,
            details: [
                binding.target ?? "",
                binding.linkedTarget.map { "Linked to \($0)" } ?? "",
                binding.trigger.map(sanitized) ?? "",
                binding.note ?? ""
            ]
        )
    }

    private func runItem(_ result: LoopRunResult) -> Item {
        let action = nonEmpty(result.action.name) ?? result.action.key

        guard let window = result.window else {
            return Item(name: "Ran \(action)", details: [result.target])
        }

        let target = nonEmpty(window.appName).map { " on \($0)" } ?? ""
        return Item(name: "Ran \(action)\(target)", details: [result.target, "Window \(window.id)"])
    }

    // MARK: - Text

    private func windowName(appName: String?, title: String?) -> String {
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

    /// POSIX locale so CLI output doesn't change with the user's region
    private func number(_ value: CGFloat) -> String {
        Double(value).formatted(
            .number
                .precision(.fractionLength(0...2))
                .grouping(.never)
                .locale(Locale(identifier: "en_US_POSIX"))
        )
    }

    /// Trimmed and flattened to one line, or `nil` when empty
    private func nonEmpty(_ string: String?) -> String? {
        guard let string else {
            return nil
        }

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
