//
//  PreviewStartingPosition.swift
//  Loop
//
//  Created by Kai Azim on 2025-05-30.
//

import Foundation
import Tome

/// An enum to represent the starting position of the preview window when it is initially opened.
enum PreviewStartingPosition: String, CaseIterable, Tome.Serializable {
    /// The preview window will open at the center of the screen.
    case screenCenter = "screen-center"

    /// The preview window will open at the radial menu position.
    case radialMenu = "radial-menu"

    /// The preview window will open at the center of the first action.
    case actionCenter = "action-center"
}
