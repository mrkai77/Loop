//
//  LoopAutomationFormatter.swift
//  Loop
//
//  Created by Kai Azim on 2026-03-30.
//

import CoreGraphics
import Foundation

/// Readable text for automation results, shared by `loop-cli` and Loop's output window
struct LoopAutomationFormatter {
    enum Layout: Equatable {
        /// Aligned columns under a header, for people. Cells are cut short to fit `maxWidth`, if there is one.
        case table(maxWidth: Int?)
        /// One tab-separated line per row, without a header, so `cut` and `awk` can read it
        case tabSeparated
    }

    let layout: Layout

    init(layout: Layout = .table(maxWidth: nil)) {
        self.layout = layout
    }

    func format(_ result: LoopAutomationResult) -> LoopAutomationText {
        switch result {
        case let .windowList(result):
            render(windowTable(result.windows), emptyMessage: "No windows")
        case let .screenList(result):
            render(screenTable(result.screens), emptyMessage: "No screens")
        case let .actionList(result):
            render(actionTable(result.actions), emptyMessage: "No actions")
        case let .bindingList(result):
            render(bindingTable(result.bindings), emptyMessage: emptyMessage(for: result.bindingKind))
        case let .run(result):
            runMessage(result)
        }
    }

    // MARK: - Tables

    struct Column {
        let title: String
        /// Cut short first when the table is too wide
        var isFlexible = false
    }

    struct Row {
        /// `nil` for a missing value. It's left blank, except in the first column, where a dash shows there's nothing to type.
        let cells: [String?]
        /// For rows that don't currently do anything, like a keybind without keys
        var isDimmed = false
    }

    struct Table {
        let columns: [Column]
        let rows: [Row]
    }

    private static let columnGap = "   "
    private static let missingValue = "—"
    private static let minimumFlexibleWidth = 12

    func render(_ table: Table, emptyMessage: String) -> LoopAutomationText {
        guard !table.rows.isEmpty else {
            // Piped output stays empty, so scripts can count lines
            return layout == .tabSeparated ? LoopAutomationText() : LoopAutomationText(emptyMessage, style: .secondary)
        }

        switch layout {
        case .tabSeparated:
            let lines = table.rows.map { row in
                row.cells.map { ($0 ?? "").replacingOccurrences(of: "\t", with: " ") }.joined(separator: "\t")
            }
            return LoopAutomationText(lines.joined(separator: "\n"))
        case let .table(maxWidth):
            return renderAligned(table, maxWidth: maxWidth)
        }
    }

    private func renderAligned(_ table: Table, maxWidth: Int?) -> LoopAutomationText {
        // Columns without a single value only add noise. The first one stays, as it's what to type.
        let visible = table.columns.indices.filter { index in
            index == 0 || table.rows.contains { row in row.cells[index].map { !$0.isEmpty } ?? false }
        }
        let columns = visible.map { table.columns[$0] }
        let rows = table.rows.map { row in
            let cells = visible.enumerated().map { position, index in
                row.cells[index].flatMap { $0.isEmpty ? nil : $0 } ?? (position == 0 ? Self.missingValue : "")
            }
            return (cells: cells, isDimmed: row.isDimmed)
        }

        var widths = columns.indices.map { index in
            rows.map { Self.displayWidth(of: $0.cells[index]) }.reduce(Self.displayWidth(of: columns[index].title), max)
        }

        if let maxWidth {
            let gapsWidth = Self.columnGap.count * max(columns.count - 1, 0)
            var overflow = widths.reduce(gapsWidth, +) - maxWidth
            // Later columns hold the longer, less important text, like a window's title, so they give way first
            for index in columns.indices.reversed() where overflow > 0 && columns[index].isFlexible {
                let shrunk = min(widths[index], max(Self.minimumFlexibleWidth, widths[index] - overflow))
                overflow -= widths[index] - shrunk
                widths[index] = shrunk
            }
        }

        func line(_ cells: [String], style: (Int) -> LoopAutomationText.Style) -> LoopAutomationText {
            // Stops at the last value, so blank cells don't leave trailing spaces
            let lastIndex = cells.lastIndex { !$0.isEmpty } ?? 0
            return cells[...lastIndex].indices.map { index in
                let isLast = index == lastIndex
                let cell = Self.truncated(cells[index], toWidth: widths[index])
                let padding = isLast ? "" : String(repeating: " ", count: widths[index] - Self.displayWidth(of: cell))
                let text = LoopAutomationText(cell, style: style(index))
                return isLast ? text : text + LoopAutomationText(padding + Self.columnGap)
            }
            .reduce(LoopAutomationText(), +)
        }

        let header = line(columns.map(\.title)) { _ in .secondary }
        let body = rows.map { row in
            line(row.cells) { index in
                if row.isDimmed || row.cells[index] == Self.missingValue {
                    return .secondary
                }
                return index == 0 ? .bold : .plain
            }
        }

        return ([header] + body).joined(separator: "\n")
    }

    // MARK: - Results

    private func windowTable(_ windows: [LoopWindowSummary]) -> Table {
        Table(
            columns: [
                Column(title: "ID"),
                Column(title: "APP", isFlexible: true),
                Column(title: "BUNDLE ID", isFlexible: true),
                Column(title: "SIZE"),
                Column(title: "POSITION"),
                Column(title: "TITLE", isFlexible: true)
            ],
            rows: windows.map { window in
                Row(cells: [
                    String(window.id),
                    nonEmpty(window.appName),
                    nonEmpty(window.bundleID),
                    sizeString(window.frame),
                    positionString(window.frame),
                    nonEmpty(window.title)
                ])
            }
        )
    }

    private func screenTable(_ screens: [LoopScreenSummary]) -> Table {
        Table(
            columns: [
                Column(title: "ID"),
                Column(title: "NAME", isFlexible: true),
                Column(title: "SIZE"),
                Column(title: "POSITION"),
                Column(title: "MAIN")
            ],
            rows: screens.map { screen in
                Row(cells: [
                    String(screen.id),
                    nonEmpty(screen.name),
                    sizeString(screen.frame),
                    positionString(screen.frame),
                    screen.isMain ? "yes" : "no"
                ])
            }
        )
    }

    private func actionTable(_ actions: [LoopActionSummary]) -> Table {
        Table(
            columns: [
                Column(title: "ACTION"),
                Column(title: "NAME", isFlexible: true),
                Column(title: "CATEGORY", isFlexible: true)
            ],
            rows: actions.map { action in
                Row(cells: [action.key, nonEmpty(action.name), nonEmpty(action.category)])
            }
        )
    }

    private func bindingTable(_ bindings: [LoopBindingSummary]) -> Table {
        Table(
            columns: [
                Column(title: "TARGET"),
                Column(title: "ACTION", isFlexible: true),
                Column(title: "TRIGGER", isFlexible: true),
                Column(title: "LINKED TO"),
                Column(title: "NOTE", isFlexible: true)
            ],
            rows: bindings.map { binding in
                let fallbackName = binding.kind == .gesture && binding.id == nil ? "Opens the radial menu" : "No action"
                return Row(
                    cells: [
                        binding.target,
                        binding.action.flatMap { nonEmpty($0.name) } ?? fallbackName,
                        nonEmpty(binding.trigger),
                        binding.linkedTarget,
                        nonEmpty(binding.note)
                    ],
                    isDimmed: !binding.isActive || binding.target == nil || binding.action == nil
                )
            }
        )
    }

    private func emptyMessage(for kind: LoopBindingKind) -> String {
        switch kind {
        case .keybind: "No keybinds"
        case .gesture: "No gestures"
        case .radialMenu: "No radial menu actions"
        }
    }

    private func runMessage(_ result: LoopRunResult) -> LoopAutomationText {
        let action = nonEmpty(result.action.name) ?? result.action.key
        let app = result.window.flatMap { nonEmpty($0.appName) }.map { " on \($0)" } ?? ""
        let message = "Ran \(action)\(app)"

        guard layout != .tabSeparated else {
            return LoopAutomationText(message)
        }

        return LoopAutomationText("✓ ", style: .success) + LoopAutomationText(message)
    }

    // MARK: - Text

    private func sizeString(_ frame: LoopRect) -> String {
        "\(number(frame.width))×\(number(frame.height))"
    }

    private func positionString(_ frame: LoopRect) -> String {
        "\(number(frame.x)),\(number(frame.y))"
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

        let result = string
            .replacingOccurrences(of: "\t", with: " ")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return result.isEmpty ? nil : result
    }

    // MARK: - Width

    /// Columns a terminal uses for the string, counting wide characters like CJK and emoji as two
    static func displayWidth(of string: String) -> Int {
        string.reduce(0) { $0 + displayWidth(of: $1) }
    }

    private static func displayWidth(of character: Character) -> Int {
        guard let scalar = character.unicodeScalars.first else {
            return 0
        }

        if scalar.properties.isEmojiPresentation || character.unicodeScalars.contains("\u{FE0F}") {
            return 2
        }

        let wideRanges: [ClosedRange<UInt32>] = [
            0x1100...0x115F, 0x2E80...0x303E, 0x3041...0x33FF, 0x3400...0x4DBF, 0x4E00...0x9FFF,
            0xA000...0xA4CF, 0xAC00...0xD7A3, 0xF900...0xFAFF, 0xFE30...0xFE4F, 0xFF00...0xFF60,
            0xFFE0...0xFFE6, 0x20000...0x3FFFD
        ]
        return wideRanges.contains { $0.contains(scalar.value) } ? 2 : 1
    }

    /// Cut short with an ellipsis so it fits in `width` columns
    static func truncated(_ string: String, toWidth width: Int) -> String {
        guard displayWidth(of: string) > width else {
            return string
        }

        var result = ""
        var used = 0
        for character in string {
            let characterWidth = displayWidth(of: character)
            guard used + characterWidth <= width - 1 else {
                break
            }
            result.append(character)
            used += characterWidth
        }

        return result.trimmingCharacters(in: .whitespaces) + "…"
    }
}
