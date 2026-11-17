//
//  RectangleTranslationLayer.swift
//  Loop
//
//  Created by Kami on 8/7/2024.
//

import AppKit
import Defaults
import Foundation

/// Represents a keyboard shortcut configuration for a Rectangle action.
struct RectangleShortcut: Codable {
    let keyCode: Int
    let modifierFlags: Int
}

/// Represents the configuration of Rectangle app shortcuts.
struct RectangleConfig: Codable {
    let shortcuts: [String: RectangleShortcut]
}

/// Encapsulate the functions within an enum to provide a namespace
enum RectangleTranslationLayer {
    /// Maps Rectangle direction keys to Loop's WindowDirection enum.
    private static let directionMapping: [String: WindowDirection] = [
        "bottomHalf": .bottomHalf,
        "bottomRight": .bottomRightQuarter,
        "center": .center,
        "centerHalf": .horizontalCenterHalf,
        "larger": .larger,
        "leftHalf": .leftHalf,
        "maximize": .maximize,
        "maximizeHeight": .maximizeHeight,
        "nextDisplay": .nextScreen,
        "previousDisplay": .previousScreen,
        "restore": .undo,
        "rightHalf": .rightHalf,
        "smaller": .smaller,
        "topHalf": .topHalf,
        "topLeft": .topLeftQuarter,
        "topRight": .topRightQuarter
    ]

    /// Imports the keybinds from Rectangle's exported JSON.
    /// Shortcuts without a matching Loop action are skipped. The rest bypass the trigger key, as in Rectangle.
    static func importKeybinds(from data: Data) throws -> [KeyBinding] {
        let rectangleConfig = try JSONDecoder().decode(RectangleConfig.self, from: data)

        return rectangleConfig.shortcuts.compactMap { direction, shortcut -> KeyBinding? in
            guard
                let loopDirection = directionMapping[direction],
                !direction.contains("Todo"),
                let keyCode = CGKeyCode(exactly: shortcut.keyCode)
            else {
                return nil
            }

            var keys: Set<CGKeyCode> = [keyCode]
            let flags = NSEvent.ModifierFlags(rawValue: UInt(bitPattern: shortcut.modifierFlags))
            if flags.contains(.command) { keys.insert(.kVK_Command) }
            if flags.contains(.option) { keys.insert(.kVK_Option) }
            if flags.contains(.control) { keys.insert(.kVK_Control) }
            if flags.contains(.shift) { keys.insert(.kVK_Shift) }

            return KeyBinding(keys: KeyCombination(keyCodes: keys), bypassTriggerKey: true, target: .windowAction(WindowAction(loopDirection)))
        }
    }
}
