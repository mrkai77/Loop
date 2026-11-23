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
        let first = Keybind(keys: [.kVK_Return], target: .action(WindowAction(.maximize)))
        let second = Keybind(keys: [.kVK_Return], target: .action(WindowAction(.center)))
        let other = Keybind(keys: [.kVK_LeftArrow], target: .action(WindowAction(.leftHalf)))

        #expect(Keybind.conflictingIDs(in: [first, second, other], triggerKey: triggerKey) == [first.id, second.id])
    }

    @Test func bypassingTheTriggerKeyCountsTheTriggerKeyAsPartOfTheKeys() {
        let normal = Keybind(keys: [.kVK_Return], target: .action(WindowAction(.maximize)))
        var bypassed = Keybind(keys: [.kVK_Function, .kVK_Return], target: .action(WindowAction(.center)))
        bypassed.bypassTriggerKey = true
        var bypassedWithoutTrigger = Keybind(keys: [.kVK_Return], target: .action(WindowAction(.leftHalf)))
        bypassedWithoutTrigger.bypassTriggerKey = true

        #expect(Keybind.conflictingIDs(in: [normal, bypassed, bypassedWithoutTrigger], triggerKey: triggerKey) == [normal.id, bypassed.id])
    }

    @Test func keybindsWithoutKeysDontConflict() {
        let keybinds = [Keybind(target: .action(WindowAction(.maximize))), Keybind(target: .action(WindowAction(.center)))]

        #expect(Keybind.conflictingIDs(in: keybinds, triggerKey: triggerKey).isEmpty)
    }

    @Test func conflictingKeybindsDontRun() {
        let first = Keybind(keys: [.kVK_Return], target: .action(WindowAction(.maximize)))
        let second = Keybind(keys: [.kVK_Return], target: .action(WindowAction(.center)))
        let snapshot = WindowActionCache.snapshot(
            linkResolver: BindingLinkResolver(keybinds: [first, second], gestures: [], radialMenuActions: []),
            triggerKey: triggerKey,
            cycleBackwardsOnShiftPressed: false
        )

        #expect(snapshot.actionsByKeybind.isEmpty)
        #expect(snapshot.keysByActionID.isEmpty)
    }

    @Test @MainActor func theCLIShowsConflictingKeybindsAsInactive() {
        let first = Keybind(keys: [.kVK_Return], target: .action(WindowAction(.maximize)))
        let second = Keybind(keys: [.kVK_Return], target: .action(WindowAction(.center)))
        let catalog = LoopAutomationCatalog(keybinds: [first, second], radialMenuActions: [], gestures: [], triggerKey: triggerKey)

        #expect(catalog.keybindRows.allSatisfy { !$0.isActive && $0.note == "Conflicts with another keybind" })
    }
}
