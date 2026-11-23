//
//  KeybindConflictTests.swift
//  LoopTests
//
//  Created by Kai Azim on 2026-11-22.
//

import CoreGraphics
@testable import Loop
import Testing

struct KeybindConflictTests {
    private let triggerKey: Set<CGKeyCode> = [.kVK_Function]

    @Test func keybindsWithTheSameKeysAllConflict() {
        let first = WindowAction(.maximize, keybind: [.kVK_Return])
        let second = WindowAction(.center, keybind: [.kVK_Return])
        let other = WindowAction(.leftHalf, keybind: [.kVK_LeftArrow])

        #expect(WindowAction.conflictingIDs(in: [first, second, other], triggerKey: triggerKey) == [first.id, second.id])
    }

    @Test func bypassingTheTriggerKeyCountsTheTriggerKeyAsPartOfTheKeys() {
        let normal = WindowAction(.maximize, keybind: [.kVK_Return])
        var bypassed = WindowAction(.center, keybind: [.kVK_Function, .kVK_Return])
        bypassed.bypassTriggerKey = true
        var bypassedWithoutTrigger = WindowAction(.leftHalf, keybind: [.kVK_Return])
        bypassedWithoutTrigger.bypassTriggerKey = true

        #expect(WindowAction.conflictingIDs(in: [normal, bypassed, bypassedWithoutTrigger], triggerKey: triggerKey) == [normal.id, bypassed.id])
    }

    @Test func keybindsWithoutKeysDontConflict() {
        let keybinds = [WindowAction(.maximize), WindowAction(.center)]

        #expect(WindowAction.conflictingIDs(in: keybinds, triggerKey: triggerKey).isEmpty)
    }

    @Test @MainActor func theCLIShowsConflictingKeybindsAsInactive() {
        let first = WindowAction(.maximize, keybind: [.kVK_Return])
        let second = WindowAction(.center, keybind: [.kVK_Return])
        let catalog = LoopAutomationCatalog(keybinds: [first, second], radialMenuActions: [], gestures: [], triggerKey: triggerKey)

        #expect(catalog.keyBindings.allSatisfy { !$0.isActive && $0.note == "Conflicts with another keybind" })
    }
}
