//
//  ActionBindingModelTests.swift
//  Loop
//
//  Created by Kai Azim on 2026-11-14.
//

import Foundation
@testable import Loop
import SwiftUI
import Testing

struct ActionBindingModelTests {
    @Test func bindingRoundTripKeepsInputSeparateFromTypedAction() throws {
        let frame = FrameAction(
            name: "Wide", size: .custom(width: ScreenLength(25), height: ScreenLength(250, unit: .points)),
            position: .coordinates(x: ScreenLength(25, unit: .points), y: ScreenLength(10))
        )
        let binding = KeyBinding(
            configID: "wide", keys: [.kVK_Space], bypassTriggerKey: true,
            target: .windowAction(.init(kind: .custom(frame)))
        )
        let data = try JSONEncoder().encode(binding)
        let decoded = try JSONDecoder().decode(KeyBinding.self, from: data)
        #expect(decoded.configID == binding.configID)
        #expect(decoded.keys == binding.keys)
        #expect(decoded.bypassTriggerKey == binding.bypassTriggerKey)
        #expect(decoded.target.semanticKey == binding.target.semanticKey)
        #expect(decoded.id == ConfigurationIdentity.uuid("key/id:wide"))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["keys"] as? String == "space")
        #expect(object["id"] as? String == "wide")
        #expect(object["link-trigger-key"] as? Bool == false)
        #expect(object["action"] as? String == "custom")
        #expect(object["configID"] == nil)
        #expect(object["bypassTriggerKey"] == nil)
        if case let .windowAction(action) = decoded.target {
            #expect(action.direction == .custom)
        } else { Issue.record("Expected direct custom frame") }
    }

    @Test func actionKindChangeRetainsIdentityAndConstructsDefaults() {
        var action = WindowAction(kind: .custom(.init(name: "Custom", size: .preserve, position: .anchor(.bottomLeft))))
        let identity = action.id
        action.direction = .maximize
        action.name = "Not applicable"
        action.customDimensions = .init(width: ScreenLength(50), height: nil)
        #expect(action.id == identity)
        #expect(action.name == nil)
        #expect(action.size == nil)
        #expect(action.position == nil)
        action.direction = .stash
        #expect(action.id == identity)
        #expect(action.name == nil)
        #expect(action.size == .defaultCustom)
        #expect(action.position == .anchor(.topLeft))
        action.direction = .custom
        #expect(action.position == .anchor(.center))
        action.direction = .cycle
        #expect(action.kind == .cycle(.init()))
    }

    @Test func promotingReferenceIDRetainsBindingAndActionIdentity() {
        var rows = [KeyBinding(.maximize, keys: [.kVK_Space])]
        let identity = rows[0].id
        let actionIdentity = rows[0].target.id
        let pending = rows[0].reference
        let reference = rows.ensureConfigurationID(at: 0)
        #expect(reference == "maximize")
        #expect(rows.ensureConfigurationID(at: 0) == reference)
        // Only a later decode derives the identity from the id
        #expect(rows[0].id == identity)
        #expect(rows[0].target.id == actionIdentity)
        #expect(rows[0].keys == [.kVK_Space])
        #expect(rows[0].reference == .init(.key, reference))
        #expect(rows[0].reference != pending)
        var graph = ActionTargetEditorGraph(keyBindings: rows, gestureBindings: [], radialMenuBindings: [])
        #expect(graph.resolve(.reference(.init(.key, reference)))?.direction == .maximize)
        let promoted = graph.promoted(.reference(rows[0].reference))
        #expect(promoted == .reference(.init(.key, reference)))
    }

    @Test func generatedIDsAreReadableAndUnique() {
        func id(_ binding: some ActionBinding) -> String {
            var binding = binding
            return binding.ensureConfigurationID(avoiding: [])
        }
        func named(_ name: String) -> KeyBinding {
            KeyBinding(target: .windowAction(.init(kind: .custom(.init(name: name, size: .preserve, position: .anchor(.center))))))
        }
        #expect(id(named("Left Half")) == "left-half")
        #expect(id(KeyBinding(.leftHalf)) == "left-half")
        #expect(id(KeyBinding(.topLeftQuarter)) == "top-left-quarter")
        #expect(id(KeyBinding(.custom)) == "custom")
        #expect(id(named("  Fancy -- Name!! \u{1F680} Caf\u{E9} \u{65E5}\u{672C}")) == "fancy-name-cafe")
        #expect(id(named("\u{1F680}!!")) == "custom")
        #expect(id(named("myCoolAction2Go")) == "my-cool-action-2-go")
        for name in ["Left Half", "\u{1F680}", "a/b\\c", "UPPER", ""] {
            #expect(ConfigurationIdentity.isValid(id(named(name))))
        }
        #expect(id(GestureBinding(kind: .swipeUp, target: .windowAction(.init(.maximize)))) == "maximize")
        #expect(id(RadialMenuBinding(target: .windowAction(.init(.maximize)))) == "maximize")

        var rows = [KeyBinding(.leftHalf), named("Left Half"), KeyBinding(.leftHalf), KeyBinding(.rightHalf)]
        for index in rows.indices { rows.ensureConfigurationID(at: index) }
        #expect(rows.map(\.configID) == ["left-half", "left-half-2", "left-half-3", "right-half"])
        rows[0].target = named("Something Else").target
        #expect(rows.ensureConfigurationID(at: 0) == "left-half")
    }

    @Test func theConflictCounterGoesAfterTheWholeID() {
        #expect(ConfigurationIdentity.nextFreeID("same-2", taken: ["same-2"]) == "same-2-2")
        #expect(ConfigurationIdentity.nextFreeID("same-2", taken: ["same-2", "same-2-2"]) == "same-2-3")
        #expect(ConfigurationIdentity.nextFreeID("same", taken: ["same", "same-2"]) == "same-3")
        #expect(ConfigurationIdentity.nextFreeID("free", taken: ["same"]) == "free")
        #expect(ConfigurationIdentity.nextFreeID("-2", taken: ["-2"]) == "-2-2")
        #expect(ConfigurationIdentity.nextFreeID("v2", taken: ["v2"]) == "v2-2")
        #expect(ConfigurationIdentity.nextFreeID("move-to-space-1", taken: ["move-to-space-1"]) == "move-to-space-1-2")
        #expect(ConfigurationIdentity.nextFreeID("left-half", taken: ["left-half"]) == "left-half-2")
        let rows = ConfigurationIdentity.deduplicatingIDs(["same-2", "same-2", "same", "same-2"].map { KeyBinding(.leftHalf).withConfigurationID($0) })
        #expect(rows.map(\.configID) == ["same-2", "same-2-2", "same", "same-2-3"])
        let spaces = ConfigurationIdentity.deduplicatingIDs(["move-to-space-1", "move-to-space-1", "move-to-space-1", "move-to-space-2"].map { KeyBinding(.moveToSpace1).withConfigurationID($0) })
        #expect(spaces.map(\.configID) == ["move-to-space-1", "move-to-space-1-2", "move-to-space-1-3", "move-to-space-2"])
        let halves = ConfigurationIdentity.deduplicatingIDs(["left-half", "left-half", "left-half-2"].map { KeyBinding(.leftHalf).withConfigurationID($0) })
        #expect(halves.map(\.configID) == ["left-half", "left-half-3", "left-half-2"])
    }

    @Test func writingIDsDoesNotChangeStashIdentity() {
        func stashIDs(_ rows: [KeyBinding]) -> [UUID] {
            rows.identified().flatMap { row -> [UUID] in
                guard case let .windowAction(action) = row.target else { return [] }
                if case let .cycle(cycle) = action.kind {
                    return cycle.steps.compactMap { if case let .windowAction(step) = $0 { step.id } else { nil } } + [action.id]
                }
                return [action.id]
            }
        }
        var rows = [
            KeyBinding(.stash, keys: KeyCombination(names: ["s"])),
            KeyBinding("Cycle", cycle: [WindowAction(.leftHalf), WindowAction(.stash)], keys: KeyCombination(names: ["c"]))
        ]
        let before = stashIDs(rows)
        for index in rows.indices { rows.ensureConfigurationID(at: index) }
        #expect(stashIDs(rows) == before)
        #expect(stashIDs([rows[0].withConfigurationID("mine")]) == [before[0]])
        #expect(stashIDs([rows[0].withConfigurationID("kb_work")]) == [before[0]])
        let hand = [rows[0].withConfigurationID("kb_work"), rows[0].withConfigurationID("kb_home")]
        #expect(stashIDs(hand)[0] != stashIDs(hand)[1])
        #expect(stashIDs(hand) == stashIDs(hand.map { $0.withConfigurationID("other") }))
    }

    @MainActor @Test func swiftUIBindingEditsKeepPayloadAndWrapperIdentity() {
        var stored = KeyBinding(.custom, keys: [.kVK_Space]).withConfigurationID("custom")
        let identity = stored.id
        let binding = Binding(get: { stored }, set: { stored = $0 })
        let action = Binding<WindowAction>(get: {
            if case let .windowAction(value) = binding.wrappedValue.target { value } else { .init(.noAction) }
        }, set: { binding.wrappedValue.target = .windowAction($0) })
        action.name.wrappedValue = "Edited"
        action.size.wrappedValue = .custom(width: ScreenLength(25), height: ScreenLength(250, unit: .points))
        action.position.wrappedValue = .coordinates(x: ScreenLength(25, unit: .points), y: ScreenLength(10))
        #expect(stored.id == identity)
        #expect(stored.configID == "custom")
        #expect(stored.keys == [.kVK_Space])
        #expect(action.wrappedValue.name == "Edited")
        #expect(action.wrappedValue.size == .custom(width: ScreenLength(25), height: ScreenLength(250, unit: .points)))
        #expect(action.wrappedValue.position == .coordinates(x: ScreenLength(25, unit: .points), y: ScreenLength(10)))
        action.direction.wrappedValue = .stash
        #expect(action.wrappedValue.position == .anchor(.topLeft))
        #expect(stored.id == identity)
    }

    @Test func payloadDirectionsCannotBeStoredAsBuiltins() {
        for direction in [WindowDirection.custom, .cycle, .stash] {
            let action = WindowAction(kind: .builtin(direction))
            #expect(action.kind == WindowAction(direction).kind)
            var edited = WindowAction(.maximize)
            edited.kind = .builtin(direction)
            #expect(edited.kind == WindowAction(direction).kind)
        }
    }
}
