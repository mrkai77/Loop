//
//  FnKeyState.swift
//  Loop
//
//  Created by root-daemon on 2026-10-18.
//

import CoreGraphics

/// Tracks whether the Fn/Globe key is physically held.
///
/// macOS adds `maskSecondaryFn` to some keys (arrows, F-keys, media keys, etc.) even when Fn isn't held,
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

    /// Removes the Fn flag from keys that macOS tags with it automatically, unless Fn is physically held.
    func filteredFlags(_ flags: CGEventFlags, keyCode: CGKeyCode) -> CGEventFlags {
        guard keyCode.isFnSpecialKey, !isPressed else { return flags }

        var result = flags
        result.remove(.maskSecondaryFn)
        return result
    }

    mutating func reset() {
        isPressed = false
    }
}
