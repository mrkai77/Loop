//
//  WindowAction+Defaults.swift
//  Loop
//
//  Created by Kai Azim on 2025-11-11.
//

import Defaults
import Foundation

// MARK: Keybinds

extension KeyBinding {
    static let defaultKeybinds: [KeyBinding] = [
        KeyBinding(.maximize, keybind: [.kVK_Space]),
        KeyBinding(.center, keybind: [.kVK_Return]),
        KeyBinding(
            .init(localized: "Top Cycle"),
            cycle: [.init(.topHalf), .init(.topThird), .init(.topTwoThirds)],
            keybind: [.kVK_UpArrow]
        ),
        KeyBinding(
            .init(localized: "Bottom Cycle"),
            cycle: [.init(.bottomHalf), .init(.bottomThird), .init(.bottomTwoThirds)],
            keybind: [.kVK_DownArrow]
        ),
        KeyBinding(
            .init(localized: "Right Cycle"),
            cycle: [.init(.rightHalf), .init(.rightThird), .init(.rightTwoThirds)],
            keybind: [.kVK_RightArrow]
        ),
        KeyBinding(
            .init(localized: "Left Cycle"),
            cycle: [.init(.leftHalf), .init(.leftThird), .init(.leftTwoThirds)],
            keybind: [.kVK_LeftArrow]
        ),
        KeyBinding(.topLeftQuarter, keybind: [.kVK_UpArrow, .kVK_LeftArrow]),
        KeyBinding(.topRightQuarter, keybind: [.kVK_UpArrow, .kVK_RightArrow]),
        KeyBinding(.bottomRightQuarter, keybind: [.kVK_DownArrow, .kVK_RightArrow]),
        KeyBinding(.bottomLeftQuarter, keybind: [.kVK_DownArrow, .kVK_LeftArrow])
    ]
}
