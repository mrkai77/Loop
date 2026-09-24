//
//  CGEventField+Extensions.swift
//  Loop
//
//  Created by Kai Azim on 2026-09-24.
//

import CoreGraphics

/// Private fields of gesture events, such as the Dock's DockSwipe
extension CGEventField {
    /// `IOHIDEventType`
    static let gestureHIDType = CGEventField(rawValue: 110)!

    static let dockSwipeMotion = CGEventField(rawValue: 123)!
    static let dockSwipeProgress = CGEventField(rawValue: 124)!
    static let dockSwipeVelocity = CGEventField(rawValue: 129)!

    static let gesturePhase = CGEventField(rawValue: 132)!

    enum GestureHIDType: Int64 {
        /// `kIOHIDEventTypeDockSwipe`
        case dockSwipe = 23
    }

    enum DockSwipeMotion: Int64 {
        case horizontal = 1
        case vertical = 2
        case pinch = 3
    }

    enum GesturePhase: Int64 {
        case began = 1
        case changed = 2
        case ended = 4
        case cancelled = 8
    }
}
