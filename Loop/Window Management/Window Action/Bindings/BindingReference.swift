//
//  BindingReference.swift
//  Loop
//
//  Created by Kai Azim on 2026-11-18.
//

import Foundation

/// Written as `key:max` in config.toml.
struct BindingReference: Hashable, Sendable, CustomStringConvertible {
    let kind: BindingKind
    let id: String

    init(_ kind: BindingKind, _ id: String) {
        self.kind = kind
        self.id = id
    }

    var configurationString: String { kind.referencePrefix + id }

    var description: String { "\(kind.label) '\(id)'" }
}
