//
//  ProcessInfo+Extensions.swift
//  Loop
//
//  Created by Kai Azim on 2026-09-24.
//

import Foundation

extension ProcessInfo {
    /// Whether an environment variable is set to `1` or `true`.
    func isEnvironmentFlagEnabled(_ name: String) -> Bool {
        guard let value = environment[name] else { return false }
        return value == "1" || value.lowercased() == "true"
    }
}
