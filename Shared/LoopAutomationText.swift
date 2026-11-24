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
        case heading
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
            case .bold, .heading: "\u{001B}[1m\(run.text)\u{001B}[22m"
            case .secondary: "\u{001B}[2m\(run.text)\u{001B}[22m"
            case .success: "\u{001B}[32m\(run.text)\u{001B}[39m"
            case .failure: "\u{001B}[31m\(run.text)\u{001B}[39m"
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
