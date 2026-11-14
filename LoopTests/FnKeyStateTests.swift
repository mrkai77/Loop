//
//  FnKeyStateTests.swift
//  LoopTests
//
//  Created by root-daemon on 2026-10-18.
//

import CoreGraphics
@testable import Loop
import Testing

/// Event sequences below mirror what a CGEventTap receives from a built-in MacBook keyboard.
struct FnKeyStateTests {
    /// macOS tags arrow keys with both the Fn and numeric pad flags, whether or not Fn is held.
    private let arrowFlags: CGEventFlags = [.maskSecondaryFn, .maskNumericPad]

    @Test(arguments: [
        CGKeyCode.kVK_MissionControl,
        .kVK_Spotlight,
        .kVK_Dictation,
        .kVK_DoNotDisturb
    ])
    func topRowKeyFnFlagDoesNotLeakIntoNextArrowKey(_ topRowKey: CGKeyCode) {
        var state = FnKeyState()

        // These keys carry the Fn flag without Fn being held
        state.update(type: .keyDown, keyCode: topRowKey, flags: .maskSecondaryFn)
        #expect(!state.filteredFlags(.maskSecondaryFn).contains(.maskSecondaryFn))

        state.update(type: .keyUp, keyCode: topRowKey, flags: .maskSecondaryFn)
        state.update(type: .keyDown, keyCode: .kVK_LeftArrow, flags: arrowFlags)

        #expect(!state.isPressed)
        #expect(!state.filteredFlags(arrowFlags).contains(.maskSecondaryFn))
    }

    /// Holding Globe and pressing the left arrow arrives as `kVK_Home` with only the Fn flag.
    @Test func physicallyHeldFnIsKeptOnArrowKey() {
        var state = FnKeyState()

        state.update(type: .flagsChanged, keyCode: .kVK_Function, flags: .maskSecondaryFn)
        state.update(type: .keyDown, keyCode: .kVK_Home, flags: .maskSecondaryFn)

        #expect(state.isPressed)
        #expect(CGKeyCode.kVK_Home.baseKey(isFnPressed: state.isPressed) == .kVK_LeftArrow)
        #expect(state.filteredFlags(.maskSecondaryFn).contains(.maskSecondaryFn))
    }

    @Test func releasingFnClearsState() {
        var state = FnKeyState()

        state.update(type: .flagsChanged, keyCode: .kVK_Function, flags: .maskSecondaryFn)
        state.update(type: .flagsChanged, keyCode: .kVK_Function, flags: [])
        state.update(type: .keyDown, keyCode: .kVK_LeftArrow, flags: arrowFlags)

        #expect(!state.isPressed)
        #expect(!state.filteredFlags(arrowFlags).contains(.maskSecondaryFn))
    }

    @Test func eventWithoutFnFlagClearsMissedRelease() {
        var state = FnKeyState()

        state.update(type: .flagsChanged, keyCode: .kVK_Function, flags: .maskSecondaryFn)
        state.update(type: .keyDown, keyCode: .kVK_ANSI_A, flags: [])

        #expect(!state.isPressed)
    }

    @Test func otherModifiersWhileHoldingFnKeepItPressed() {
        var state = FnKeyState()

        state.update(type: .flagsChanged, keyCode: .kVK_Function, flags: .maskSecondaryFn)
        state.update(type: .flagsChanged, keyCode: .kVK_Shift, flags: [.maskSecondaryFn, .maskShift])

        #expect(state.isPressed)
        #expect(state.filteredFlags([.maskSecondaryFn, .maskShift]) == [.maskSecondaryFn, .maskShift])
    }

    @Test func fnFlagIsRemovedFromAnyKeyUnlessFnIsHeld() {
        let state = FnKeyState()

        #expect(state.filteredFlags([.maskSecondaryFn, .maskShift]) == .maskShift)
    }
}
