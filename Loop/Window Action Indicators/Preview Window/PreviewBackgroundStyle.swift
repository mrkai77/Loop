//
//  PreviewBackgroundStyle.swift
//  Loop
//
//  Created by Kai Azim on 2026-09-30.
//

import Foundation
import Tome

/// How the preview window's background is drawn.
enum PreviewBackgroundStyle: String, CaseIterable, Tome.Serializable {
    /// A translucent black fill, like the system's window tiling preview.
    case system

    /// A configurable blur and accent color gradient.
    case custom

    var displayName: String {
        switch self {
        case .system: String(localized: "System", comment: "Preview background style: a translucent black fill, like the system's window tiling preview")
        case .custom: String(localized: "Custom", comment: "Preview background style: a configurable blur and accent color")
        }
    }
}
