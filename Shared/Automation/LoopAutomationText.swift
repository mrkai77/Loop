//
//  LoopAutomationText.swift
//  Loop
//
//  Created by Kai Azim on 2026-03-30.
//

import Foundation

/// Styled text that `loop-cli` renders with ANSI codes and Loop's output window renders with colors
struct LoopAutomationText {
    enum Style {
        case plain
        case bold
        case secondary
        case success
        case failure
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

    var isEmpty: Bool {
        runs.isEmpty
    }

    var plainText: String {
        runs.map(\.text).joined()
    }

    var ansiText: String {
        runs.map { run in
            switch run.style {
            case .plain: run.text
            case .bold: ANSI.bold + run.text + ANSI.normalIntensity
            case .secondary: ANSI.faint + run.text + ANSI.normalIntensity
            case .success: ANSI.green + run.text + ANSI.defaultColor
            case .failure: ANSI.red + run.text + ANSI.defaultColor
            }
        }
        .joined()
    }

    /// SGR escape codes. Each style resets only what it set, so styles can sit next to each other.
    private enum ANSI {
        static let bold = "\u{001B}[1m"
        static let faint = "\u{001B}[2m"
        static let normalIntensity = "\u{001B}[22m"
        static let green = "\u{001B}[32m"
        static let red = "\u{001B}[31m"
        static let defaultColor = "\u{001B}[39m"
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
