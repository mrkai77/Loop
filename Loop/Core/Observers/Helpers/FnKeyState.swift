//
//  FnKeyState.swift
//  Loop
//
//  Created by root-daemon on 2026-10-18.
//

import AppKit
import CoreGraphics

/// Tracks whether the Fn/Globe key is physically held.
///
/// macOS adds `maskSecondaryFn` to many keys (arrows, F-keys, Apple's top-row keys, etc.) even when Fn isn't held,
/// so an event's flags alone can't tell whether Fn is actually down. Only a `flagsChanged` event for the
/// Fn key itself can press it, and any event without the Fn flag releases it.
struct FnKeyState {
    private(set) var isPressed = false

    mutating func update(type: CGEventType, keyCode: CGKeyCode, flags: CGEventFlags) {
        if type == .flagsChanged, keyCode == .kVK_Function {
            isPressed = flags.contains(.maskSecondaryFn)
        } else if !flags.contains(.maskSecondaryFn) {
            isPressed = false
        }
    }

    mutating func update(with event: NSEvent) {
        guard let type = CGEventType(rawValue: UInt32(event.type.rawValue)) else { return }
        update(type: type, keyCode: event.keyCode, flags: CGEventFlags(cocoaFlags: event.modifierFlags))
    }

    /// Removes the Fn flag unless Fn is physically held.
    func filteredFlags(_ flags: CGEventFlags) -> CGEventFlags {
        isPressed ? flags : flags.subtracting(.maskSecondaryFn)
    }

    /// - Parameter isPressed: the Fn state to start from, for when Fn may already be held (its press event was missed).
    mutating func reset(isPressed: Bool = false) {
        self.isPressed = isPressed
    }
}
