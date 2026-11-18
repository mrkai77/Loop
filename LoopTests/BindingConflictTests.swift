//
//  BindingConflictTests.swift
//  LoopTests
//
//  Created by Kai Azim on 2026-11-18.
//

@testable import Loop
import Testing

struct BindingConflictTests {
    private let triggerKey: KeyCombination = [.kVK_Function]

    @Test func keybindsConflictOnTheirEffectiveKeys() {
        let first = KeyBinding(.leftHalf, keys: [.kVK_Space])
        let second = KeyBinding(.rightHalf, keys: [.kVK_Space])
        let other = KeyBinding(.maximize, keys: [.kVK_Return])
        let unset = KeyBinding(.center)
        let bindings = [first, second, other, unset]

        #expect(KeyBinding.conflictingIDs(in: bindings, triggerKey: triggerKey) == [first.id, second.id])
        #expect(KeyBinding.active(in: bindings, triggerKey: triggerKey).map(\.id) == [other.id])
    }

    @Test func theTriggerKeyOnlyCountsForKeybindsThatDoNotBypassIt() {
        let linked = KeyBinding(.leftHalf, keys: [.kVK_Space])
        var bypassing = KeyBinding(.rightHalf, keys: [.kVK_Function, .kVK_Space])
        bypassing.bypassTriggerKey = true
        let bindings = [linked, bypassing]

        #expect(linked.trigger(triggerKey: triggerKey) == bypassing.trigger(triggerKey: triggerKey))
        #expect(KeyBinding.conflictingIDs(in: bindings, triggerKey: triggerKey) == [linked.id, bypassing.id])

        bypassing.keys = [.kVK_Space]
        #expect(KeyBinding.conflictingIDs(in: [linked, bypassing], triggerKey: triggerKey).isEmpty)
        #expect(KeyBinding.active(in: [linked, bypassing], triggerKey: triggerKey).count == 2)
        #expect(KeyBinding.conflictingIDs(in: [linked, bypassing], triggerKey: []) == [linked.id, bypassing.id])
    }

    @Test func gesturesConflictOnFingerCountAndKind() {
        let first = GestureBinding(fingerCount: 3, kind: .swipeUp)
        let second = GestureBinding(fingerCount: 3, kind: .swipeUp)
        let otherFingers = GestureBinding(fingerCount: 4, kind: .swipeUp)
        let otherKind = GestureBinding(fingerCount: 3, kind: .swipeDown)
        let unset = GestureBinding(fingerCount: 3, kind: nil)
        let gestures = [first, second, otherFingers, otherKind, unset]

        #expect(GestureBinding.conflictingIDs(in: gestures) == [first.id, second.id])
        #expect(GestureBinding.active(in: gestures).map(\.id) == [otherFingers.id, otherKind.id])
    }

    @Test func aSwipeSharingTheRadialMenusFingerCountOverridesInsteadOfConflicting() {
        let radial = GestureBinding(fingerCount: 3, kind: .radialMenu)
        let swipe = GestureBinding(fingerCount: 3, kind: .swipeLeft)
        let gestures = [radial, swipe]

        #expect(GestureBinding.conflictingIDs(in: gestures).isEmpty)
        #expect(GestureBinding.radialMenuOverrideIDs(in: gestures) == [swipe.id])
    }
}
