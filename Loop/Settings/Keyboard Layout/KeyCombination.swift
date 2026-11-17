//
//  KeyCombination.swift
//  Loop
//
//  Created by Kai Azim on 2026-11-16.
//

import CoreGraphics
import Foundation
import Tome
import TOML

/// Stores key names rather than key codes, so a file means the same on every layout. See ``KeyNames``.
struct KeyCombination: Hashable, Sendable, ExpressibleByArrayLiteral, Tome.Serializable {
    var names: Set<String>

    init(names: Set<String> = []) {
        self.names = names
    }

    /// Fixed keys only. Character keys have no layout-independent name; use ``init(names:)``.
    init(arrayLiteral elements: CGKeyCode...) {
        self.init(names: Set(elements.map { code in
            guard let name = KeyNames.fixedName(for: code) else {
                preconditionFailure("Key code \(code) is a character key; use KeyCombination(names:)")
            }
            return name
        }))
    }

    /// For legacy and Rectangle key codes. Names them on the active layout.
    init(keyCodes: Set<CGKeyCode>, layout: KeyboardLayout = .shared) {
        self.names = Set(keyCodes.map(layout.name(forKeyCode:)))
    }

    var isEmpty: Bool { names.isEmpty }

    func containsFixedKey(_ code: CGKeyCode) -> Bool {
        KeyNames.fixedName(for: code).map(names.contains) ?? false
    }

    /// `nil` when a name has no key on the layout.
    func keyCodes(on layout: KeyboardLayout = .shared) -> Set<CGKeyCode>? {
        layout.keyCodes(for: names)
    }
}

/// Decoding only checks the spelling. Names are resolved against the layout at runtime.
extension KeyCombination: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let name = try? container.decode(String.self) {
            self.names = try name.isEmpty ? [] : [KeyNames.canonical(name)]
            return
        }
        let names = try container.decode([String].self)
        guard names.allSatisfy({ !$0.isEmpty }) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Key names can't be empty, found \(ConfigurationMessage.quoted("[" + names.map { "\"\($0)\"" }.joined(separator: ", ") + "]"))")
        }
        self.names = try Set(names.map(KeyNames.canonical))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        let ordered = KeyNames.components(from: names)
        if ordered.count == 1 { try container.encode(ordered[0]) } else { try container.encode(ordered) }
    }
}
