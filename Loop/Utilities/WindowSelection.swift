//
//  WindowSelection.swift
//  Loop
//
//  Created by Kai Azim on 2026-11-15.
//

import SwiftUI
import Tome

/// Which window an action is applied to.
enum WindowSelection: String, CaseIterable, Tome.Serializable {
    case frontmost = "active"
    case underCursor = "under-cursor"

    var title: String {
        switch self {
        case .frontmost: String(localized: "Active", comment: "Target window option: act on the active window")
        case .underCursor: String(localized: "Under Cursor", comment: "Window selection option: act on the window under the cursor")
        }
    }

    var icon: ImageResource {
        switch self {
        case .frontmost: .interfaceWindowOnRectangleDashed
        case .underCursor: .interfaceWindowAndPointerArrow
        }
    }
}
