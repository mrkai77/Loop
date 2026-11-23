//
//  KeybindsFileTests.swift
//  LoopTests
//
//  Created by Kai Azim on 2026-11-23.
//

import CoreGraphics
import Foundation
@testable import Loop
import Testing

struct KeybindsFileTests {
    /// What older versions require of each keybind in a file
    private struct OlderVersionAction: Decodable {
        let direction: String
        let keybind: Set<CGKeyCode>
        let cycle: [OlderVersionAction]?
    }

    private func roundTrip(_ keybind: Keybind) throws -> (json: String, keybind: Keybind) {
        let file = SavedKeybindsFormat(version: nil, triggerKey: nil, actions: [keybind])
        let data = try JSONEncoder().encode(file)
        let decoded = try JSONDecoder().decode(SavedKeybindsFormat.self, from: data)
        return try (String(decoding: data, as: UTF8.self), #require(decoded.importedKeybinds().first))
    }

    @Test func keybindsWithoutTheTriggerKeyKeepRunningWithoutIt() throws {
        let keys: Set<CGKeyCode> = [.kVK_Command, .kVK_Option, .kVK_LeftArrow]
        let (json, keybind) = try roundTrip(Keybind(keys: keys, bypassTriggerKey: true, target: .action(WindowAction(.leftHalf))))

        #expect(json.contains("\"bypassTriggerKey\":true"))
        #expect(keybind.keys == keys)
        #expect(keybind.bypassTriggerKey == true)
        #expect(keybind.target.action?.direction == .leftHalf)
    }

    @Test func keybindsWithTheTriggerKeyAreSavedAsBefore() throws {
        let (json, keybind) = try roundTrip(Keybind(keys: [.kVK_Return], bypassTriggerKey: false, target: .action(WindowAction(.maximize))))

        #expect(!json.contains("bypassTriggerKey"))
        #expect(keybind.bypassTriggerKey != true)
    }

    @Test func importedKeybindsGetNewIDs() throws {
        let original = Keybind(keys: [.kVK_Return], target: .action(WindowAction("Halves", cycle: [.init(.leftHalf)])))
        let (_, imported) = try roundTrip(original)

        #expect(imported.id != original.id)
        #expect(imported.target.action?.cycle?.first?.id != original.target.action?.cycle?.first?.id)
    }

    @Test func linksAreExportedAsTheActionsTheyRun() throws {
        let gesture = GestureBinding(kind: .swipeUp, action: .singleAction(.action(WindowAction(.topHalf))))
        let link = BindingLink(.gesture, id: gesture.id.uuidString)
        var cycle = WindowAction("Mixed", cycle: [WindowAction(.leftHalf)])
        cycle.cycle?.append(CycleStep(target: .link(link)))
        let keybinds = [
            Keybind(configID: "to-gesture", keys: [.kVK_ANSI_G], target: .link(link)),
            Keybind(keys: [.kVK_ANSI_M], target: .action(cycle))
        ]

        let file = SavedKeybindsFormat.generate(
            from: keybinds,
            triggerKey: [.kVK_Function],
            resolver: BindingLinkResolver(keybinds: keybinds, gestures: [gesture], radialMenuActions: [])
        )

        #expect(file.actions[0].target.action?.direction == .topHalf)
        #expect(file.actions[0].configID == "to-gesture")
        #expect(file.actions[1].target.action?.cycle?.allSatisfy { $0.target.link == nil } == true)
        #expect(file.actions[1].target.action?.cycleActions?.map(\.direction) == [.leftHalf, .topHalf])
    }

    @Test func importsKeepConfigIDsThatAreValidAndFree() {
        let file = SavedKeybindsFormat(version: nil, triggerKey: nil, actions: [
            Keybind(configID: "taken", target: .action(WindowAction(.maximize))),
            Keybind(configID: "free", target: .action(WindowAction(.center))),
            Keybind(configID: "free", target: .action(WindowAction(.leftHalf))),
            Keybind(configID: "My Link", target: .action(WindowAction(.bottomHalf)))
        ])
        let existing = [Keybind(configID: "taken", target: .action(WindowAction(.rightHalf)))]

        #expect(file.importedKeybinds(keepingConfigIDsNotIn: existing).map(\.configID) == [nil, "free", nil, nil])
    }

    @Test func filesFromOlderVersionsUseTheTriggerKey() throws {
        let json = #"{"actions":[{"direction":"Maximize","keybind":[36]}]}"#
        let keybind = try #require(JSONDecoder().decode(SavedKeybindsFormat.self, from: Data(json.utf8)).importedKeybinds().first)

        #expect(keybind.keys == [.kVK_Return])
        #expect(keybind.bypassTriggerKey != true)
    }

    @Test func olderVersionsReadNewFiles() throws {
        let cycle = Keybind(keys: [.kVK_UpArrow], target: .action(WindowAction("Top", cycle: [.init(.topHalf), .init(.topThird)])))
        let data = try JSONEncoder().encode(SavedKeybindsFormat(version: nil, triggerKey: nil, actions: [cycle]))

        struct OlderVersionFile: Decodable { let actions: [OlderVersionAction] }
        let action = try #require(JSONDecoder().decode(OlderVersionFile.self, from: data).actions.first)

        #expect(action.keybind == [.kVK_UpArrow])
        #expect(action.cycle?.map(\.direction) == ["TopHalf", "TopThird"])
    }

    @Test func rectangleShortcutsImportAsTheirLoopActions() throws {
        let json = #"""
        {"shortcuts": {
            "topLeft": {"keyCode": 32, "modifierFlags": 786432},
            "topRight": {"keyCode": 34, "modifierFlags": 786432},
            "bottomLeft": {"keyCode": 38, "modifierFlags": 786432},
            "bottomRight": {"keyCode": 40, "modifierFlags": 786432},
            "leftHalf": {"keyCode": 123, "modifierFlags": 786432},
            "firstThird": {"keyCode": 2, "modifierFlags": 786432}
        }}
        """#
        let keybinds = try RectangleTranslationLayer.importKeybinds(from: Data(json.utf8))
        let directions = Dictionary(uniqueKeysWithValues: keybinds.compactMap { keybind in
            keybind.target.action.map { (Array(keybind.keys)[0], $0.direction) }
        })

        #expect(directions == [
            32: .topLeftQuarter,
            34: .topRightQuarter,
            38: .bottomLeftQuarter,
            40: .bottomRightQuarter,
            123: .leftHalf
        ])
    }
}
