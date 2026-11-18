//
//  BindingKind.swift
//  Loop
//
//  Created by Kai Azim on 2026-11-18.
//

import Foundation

enum BindingKind: String, CaseIterable, Hashable, Sendable {
    case key
    case gesture
    case radialMenu = "radial-menu"

    /// As in `action = "key:max"`.
    var referencePrefix: String { rawValue + ":" }

    var label: String {
        switch self {
        case .key: "keybind"
        case .gesture: "gesture"
        case .radialMenu: "radial menu action"
        }
    }
}
