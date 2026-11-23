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
        "bottomLeft": .bottomLeftQuarter,
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
    static func importKeybinds(from data: Data) throws -> [Keybind] {
        let rectangleConfig = try JSONDecoder().decode(RectangleConfig.self, from: data)

        // Converts the Rectangle shortcuts into Loop's WindowActions.
        let windowActions: [Keybind] = rectangleConfig.shortcuts.compactMap { direction, shortcut in
            guard
                let loopDirection = directionMapping[direction],
                !direction.contains("Todo")
            else {
                return nil
            }

            return Keybind(
                keys: [CGKeyCode(shortcut.keyCode)], // Converts the integer keyCode to CGKeyCode.
                target: .action(WindowAction(loopDirection, name: direction.capitalized.replacingOccurrences(of: " ", with: "") + "Cycle"))
            )
        }

        return windowActions
    }
}
