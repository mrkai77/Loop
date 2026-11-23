//
//  LoopTarget.swift
//  Loop
//
//  Created by Kai Azim on 2026-11-22.
//

import Foundation

/// A kind of binding that `run` can trigger, as written before the `:` in a target
enum LoopBindingKind: String, CaseIterable, Codable {
    case keybind
    case gesture
    case radialMenu = "radial-menu"

    /// As in "Unknown keybind"
    var noun: String {
        switch self {
        case .keybind: "keybind"
        case .gesture: "gesture"
        case .radialMenu: "radial menu action"
        }
    }

    var listSubject: LoopListSubject {
        switch self {
        case .keybind: .keybinds
        case .gesture: .gestures
        case .radialMenu: .radialMenu
        }
    }
}

/// Something `run` can trigger, spelled like an action in Loop's settings file: `left-half` or `keybind:portrait`
enum LoopTarget: Hashable, CustomStringConvertible {
    /// A built-in action, by its kebab-case key
    case action(String)
    /// A keybind, gesture or radial menu action, by its id
    case binding(LoopBindingKind, id: String)

    init?(_ string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return nil
        }

        guard let separator = trimmed.firstIndex(of: ":") else {
            self = .action(trimmed)
            return
        }

        let id = String(trimmed[trimmed.index(after: separator)...])
        guard let kind = LoopBindingKind(rawValue: trimmed[..<separator].lowercased()), !id.isEmpty else {
            return nil
        }

        self = .binding(kind, id: id)
    }

    var description: String {
        switch self {
        case let .action(key):
            key
        case let .binding(kind, id):
            "\(kind.rawValue):\(id)"
        }
    }
}
