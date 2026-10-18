//
//  FnKeyStateTests.swift
//  LoopTests
//
//  Created by root-daemon on 2026-10-18.
//

import CoreGraphics
@testable import Loop
import Testing

struct FnKeyStateTests {
    @Test func mediaKeyFnFlagDoesNotLeakIntoNextArrowKey() {
        var state = FnKeyState()

        // Volume/brightness keys carry the Fn flag without Fn being held
        state.update(type: .keyDown, keyCode: .kVK_VolumeUp, flags: .maskSecondaryFn)
        state.update(type: .keyUp, keyCode: .kVK_VolumeUp, flags: .maskSecondaryFn)

        // macOS also tags arrow keys with the Fn flag
        state.update(type: .keyDown, keyCode: .kVK_LeftArrow, flags: .maskSecondaryFn)
        let flags = state.filteredFlags(.maskSecondaryFn, keyCode: .kVK_LeftArrow)

        #expect(!state.isPressed)
        #expect(!flags.contains(.maskSecondaryFn))
    }

    @Test func physicallyHeldFnIsKeptOnArrowKey() {
        var state = FnKeyState()

        state.update(type: .flagsChanged, keyCode: .kVK_Function, flags: .maskSecondaryFn)
        state.update(type: .keyDown, keyCode: .kVK_LeftArrow, flags: .maskSecondaryFn)
        let flags = state.filteredFlags(.maskSecondaryFn, keyCode: .kVK_LeftArrow)

        #expect(state.isPressed)
        #expect(flags.contains(.maskSecondaryFn))
    }

    @Test func releasingFnClearsState() {
        var state = FnKeyState()

        state.update(type: .flagsChanged, keyCode: .kVK_Function, flags: .maskSecondaryFn)
        state.update(type: .flagsChanged, keyCode: .kVK_Function, flags: [])
        state.update(type: .keyDown, keyCode: .kVK_LeftArrow, flags: .maskSecondaryFn)

        #expect(!state.isPressed)
        #expect(!state.filteredFlags(.maskSecondaryFn, keyCode: .kVK_LeftArrow).contains(.maskSecondaryFn))
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
    }

    @Test func nonSpecialKeysKeepTheirFnFlag() {
        let state = FnKeyState()
        let flags = state.filteredFlags(.maskSecondaryFn, keyCode: .kVK_ANSI_A)

        #expect(flags.contains(.maskSecondaryFn))
    }
}
