//
//  ActionTargetEditorGraphTests.swift
//  Loop
//
//  Created by Kai Azim on 2026-11-14.
//

import Foundation
@testable import Loop
import Testing

struct ActionTargetEditorGraphTests {
    @Test func renamingFollowsAGeneratedIDAndEveryReferenceToIt() {
        let unnamed = WindowAction(.custom)
        let named = WindowAction(kind: .custom(.init(name: "Daru")), id: unnamed.id)
        let cycle = WindowAction(kind: .cycle(.init(name: "Spin", steps: [.reference(.init(.key, "custom")), .windowAction(.init(.maximize))])))
        var graph = ActionTargetEditorGraph(
            keyBindings: [
                .init(configID: "custom", keys: [.kVK_Tab], target: .windowAction(unnamed)),
                .init(configID: "daru", keys: [.kVK_Return], target: .windowAction(.init(.maximize))),
                .init(keys: [.kVK_LeftArrow], target: .windowAction(cycle))
            ],
            gestureBindings: [.init(kind: .swipeUp, target: .reference(.init(.key, "custom")))],
            radialMenuBindings: [.init(target: .reference(.init(.key, "custom")))]
        )
        #expect(graph.replaceAction(in: graph.keyBindings[0].target, owner: graph.keyBindings[0].reference, with: named) == nil)
        #expect(graph.resolve(.reference(.init(.key, "daru-2"))) == named)
        // "daru" is taken by another key binding.
        #expect(graph.keyBindings[0].configID == "daru-2")
        #expect(graph.gestureBindings[0].target == .reference(.init(.key, "daru-2")))
        #expect(graph.radialMenuBindings[0].target == .reference(.init(.key, "daru-2")))
        guard case let .windowAction(spin) = graph.keyBindings[2].target, case let .cycle(steps) = spin.kind else {
            Issue.record("The cycle was lost")
            return
        }
        #expect(steps.steps.first == .reference(.init(.key, "daru-2")))
    }

    @Test func handWrittenIDsAndCycleStepsDontRename() {
        let maximize = WindowAction(.maximize)
        let renamed = WindowAction(kind: .custom(.init(name: "Big")), id: maximize.id)
        var graph = ActionTargetEditorGraph(
            keyBindings: [.init(configID: "max", keys: [.kVK_Space], target: .windowAction(maximize))],
            gestureBindings: [],
            radialMenuBindings: [.init(target: .reference(.init(.key, "max")))]
        )
        #expect(graph.replaceAction(in: .reference(.init(.key, "max")), owner: nil, with: renamed) == nil)
        #expect(graph.keyBindings[0].configID == "max")
        #expect(graph.keyBindings[0].target == .windowAction(renamed))
        #expect(graph.radialMenuBindings[0].target == .reference(.init(.key, "max")))

        let step = ActionTarget.windowAction(.init(.leftHalf))
        let holding = KeyBinding(configID: "cycle", keys: [.kVK_RightArrow], target: .windowAction(.init(kind: .cycle(.init(steps: [step])))))
        graph.keyBindings.append(holding)
        let before = graph
        let right = WindowAction(.rightHalf)
        #expect(graph.replaceAction(in: step, owner: holding.reference, with: right) == .windowAction(right))
        #expect(graph == before)
    }

    @Test func generatedIDsAreTheStemOrItsNumberedForms() {
        #expect(ConfigurationIdentity.isGenerated("custom", from: "custom"))
        #expect(ConfigurationIdentity.isGenerated("custom-3", from: "custom"))
        #expect(!ConfigurationIdentity.isGenerated("custom-1", from: "custom"))
        #expect(!ConfigurationIdentity.isGenerated("custom-x", from: "custom"))
        #expect(!ConfigurationIdentity.isGenerated("max", from: "maximize"))
    }

    @Test func sameKindChainsOnlyRewriteTheirTerminalWrapper() {
        for kind in BindingKind.allCases {
            let original = WindowAction(.custom)
            let action = WindowAction(kind: .custom(.init(name: "Edited")), id: original.id)
            let first = ActionTarget.reference(.init(kind, "a"))
            let middle = ActionTarget.reference(.init(kind, "b"))
            let last = ActionTarget.reference(.init(kind, "c"))
            var graph = ActionTargetEditorGraph(keyBindings: [], gestureBindings: [], radialMenuBindings: [])
            switch kind {
            case .key:
                graph.keyBindings = [
                    .init(configID: "a", keys: [.kVK_Space], target: middle),
                    .init(configID: "b", keys: [.kVK_Return], target: last),
                    .init(configID: "c", target: .windowAction(original))
                ]
            case .gesture:
                graph.gestureBindings = [
                    .init(configID: "a", target: middle), .init(configID: "b", target: last),
                    .init(configID: "c", target: .windowAction(original))
                ]
            case .radialMenu:
                graph.radialMenuBindings = [
                    .init(configID: "a", target: middle), .init(configID: "b", target: last),
                    .init(configID: "c", target: .windowAction(original))
                ]
            }
            let before = graph
            #expect(graph.replaceAction(in: first, owner: nil, with: action) == nil)
            #expect(graph.resolve(first) == action)
            switch kind {
            case .key:
                #expect(Array(graph.keyBindings.prefix(2)) == Array(before.keyBindings.prefix(2)))
                #expect(graph.keyBindings.map(\.id) == before.keyBindings.map(\.id))
                #expect(graph.keyBindings.map(\.keys) == before.keyBindings.map(\.keys))
            case .gesture:
                #expect(Array(graph.gestureBindings.prefix(2)) == Array(before.gestureBindings.prefix(2)))
                #expect(graph.gestureBindings.map(\.id) == before.gestureBindings.map(\.id))
            case .radialMenu:
                #expect(Array(graph.radialMenuBindings.prefix(2)) == Array(before.radialMenuBindings.prefix(2)))
                #expect(graph.radialMenuBindings.map(\.id) == before.radialMenuBindings.map(\.id))
            }
        }
    }

    @Test func mixedKindChainWithRepeatedKindChangesOnlyTerminalCollection() {
        let original = WindowAction(.custom)
        var edited = original
        edited.name = "New label"
        var graph = ActionTargetEditorGraph(
            keyBindings: [.init(configID: "a", target: .reference(.init(.gesture, "b"))), .init(configID: "c", target: .reference(.init(.radialMenu, "d")))],
            gestureBindings: [.init(configID: "b", target: .reference(.init(.key, "c")))],
            radialMenuBindings: [.init(configID: "d", target: .windowAction(original))]
        )
        let before = graph
        #expect(graph.replaceAction(in: .reference(.init(.key, "a")), owner: nil, with: edited) == nil)
        #expect(graph.resolve(.reference(.init(.key, "a"))) == edited)
        #expect(graph.keyBindings == before.keyBindings)
        #expect(graph.gestureBindings == before.gestureBindings)
        #expect(graph.radialMenuBindings.first?.id == before.radialMenuBindings.first?.id)
    }

    @Test func resolutionUsesEditedCollectionsWithoutRuntimeCacheRefresh() {
        var graph = ActionTargetEditorGraph(
            keyBindings: [.init(configID: "key", target: .reference(.init(.gesture, "gesture")))],
            gestureBindings: [.init(configID: "gesture", target: .reference(.init(.radialMenu, "radial")))],
            radialMenuBindings: [.init(configID: "radial", target: .windowAction(.init(.custom)))]
        )
        #expect(graph.resolve(.reference(.init(.key, "key")))?.name == nil)
        let edited = WindowAction(kind: .custom(.init(name: "Immediately visible")))
        graph.radialMenuBindings[0].target = .windowAction(edited)
        #expect(graph.resolve(.reference(.init(.key, "key")))?.getName() == "Immediately visible")
        graph.gestureBindings[0].target = .windowAction(.init(.maximize))
        #expect(graph.resolve(.reference(.init(.key, "key")))?.direction == .maximize)
        graph.keyBindings[0].target = .windowAction(.init(.stash))
        #expect(graph.resolve(.reference(.init(.key, "key")))?.direction == .stash)
    }

    @Test func danglingAndCyclicReferencesCannotBeEdited() {
        let graph = ActionTargetEditorGraph(
            keyBindings: [.init(configID: "a", target: .reference(.init(.gesture, "b")))],
            gestureBindings: [.init(configID: "b", target: .reference(.init(.key, "a"))), .init(kind: .radialMenu, configID: "mode")],
            radialMenuBindings: []
        )
        for target in [ActionTarget.reference(.init(.key, "a")), .reference(.init(.key, "missing")), .reference(.init(.gesture, "mode"))] {
            var edited = graph
            #expect(graph.resolve(target) == nil)
            #expect(edited.replaceAction(in: target, owner: nil, with: .init(.maximize)) == nil)
            #expect(edited == graph)
        }
    }

    @Test func pickerExcludesSelfAndDependentReferences() {
        let unnamed = KeyBinding(target: .windowAction(.init(.maximize)))
        let graph = ActionTargetEditorGraph(
            keyBindings: [
                unnamed,
                .init(configID: "a", target: .windowAction(.init(.maximize))),
                .init(configID: "b", target: .reference(.init(.key, "a")))
            ],
            gestureBindings: [.init(configID: "g", target: .windowAction(.init(.maximize)))],
            radialMenuBindings: [.init(configID: "r", target: .reference(.init(.gesture, "g")))]
        )
        #expect(!graph.canSetTarget(.reference(unnamed.reference), for: unnamed.reference))
        #expect(!graph.canSetTarget(.reference(.init(.key, "a")), for: .init(.key, "a")))
        #expect(!graph.canSetTarget(.reference(.init(.key, "b")), for: .init(.key, "a")))
        #expect(!graph.canSetTarget(.reference(.init(.radialMenu, "r")), for: .init(.gesture, "g")))
        #expect(graph.canSetTarget(.reference(.init(.gesture, "g")), for: .init(.key, "a")))
    }
}

extension StoreTests {
    struct ActionTargetEditorGraphCommitTests {
        @Test func committingWritesOnlyTheListsThatChanged() throws {
            let profile = try Profile()
            var graph = ActionTargetEditorGraph.current
            graph.gestureBindings.append(GestureBinding(kind: .swipeUp, target: .windowAction(.init(.maximize))))
            graph.commit()
            try profile.flush()
            #expect(profile.value(at: ["gestures", "bindings"]) != nil)
            #expect(profile.value(at: ["key", "bindings"]) == nil)
            #expect(profile.value(at: ["radial-menu", "bindings"]) == nil)
        }
    }
}
