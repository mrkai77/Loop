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

    /// Imports the keybinds from a JSON string.
    /// - Parameter jsonString: The JSON string to import the keybinds from.
    /// - Returns: An array of WindowAction instances corresponding to the keybinds.
    static func importKeybinds(from data: Data) throws -> [LegacyWindowAction] {
        let rectangleConfig = try JSONDecoder().decode(RectangleConfig.self, from: data)

        // Converts the Rectangle shortcuts into Loop's WindowActions.
        let windowActions: [LegacyWindowAction] = rectangleConfig.shortcuts.compactMap { direction, shortcut in
            guard
                let loopDirection = directionMapping[direction],
                !direction.contains("Todo")
            else {
                return nil
            }

            return LegacyWindowAction(.init(
                loopDirection,
                keybind: Set([CGKeyCode(shortcut.keyCode)]), // Converts the integer keyCode to CGKeyCode.
                name: direction.capitalized.replacingOccurrences(of: " ", with: "") + "Cycle"
            ))
        }

        return windowActions
    }
}
