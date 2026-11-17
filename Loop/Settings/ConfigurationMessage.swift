//
//  ConfigurationMessage.swift
//  Loop
//
//  Created by Kai Azim on 2026-11-17.
//

import Foundation

enum ConfigurationMessage {
    private static let valueLimit = 40

    /// Single-quoted, on one line, and truncated when long.
    static func quoted(_ text: String) -> String {
        let oneLine = text
            .replacingOccurrences(of: "\r\n", with: "\\n")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
        guard oneLine.count > valueLimit else { return "'\(oneLine)'" }
        return "'\(oneLine.prefix(valueLimit))…'"
    }
}
