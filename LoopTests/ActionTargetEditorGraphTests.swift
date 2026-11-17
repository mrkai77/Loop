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
    private enum Category: CaseIterable { case key, gesture, radial }

    @Test func renamingFollowsAGeneratedIDAndEveryReferenceToIt() {
        let unnamed = WindowAction(.custom)
        let named = WindowAction(kind: .custom(.init(name: "Daru")), id: unnamed.id)
        let cycle = WindowAction(kind: .cycle(.init(name: "Spin", steps: [.keyBinding("custom"), .windowAction(.init(.maximize))])))
        var graph = ActionTargetEditorGraph(
            keyBindings: [
                .init(configID: "custom", keys: [.kVK_Tab], target: .windowAction(unnamed)),
                .init(configID: "daru", keys: [.kVK_Return], target: .windowAction(.init(.maximize))),
                .init(keys: [.kVK_LeftArrow], target: .windowAction(cycle))
            ],
            gestures: [.init(kind: .swipeUp, target: .keyBinding("custom"))],
            radialMenuBindings: [.init(target: .keyBinding("custom"))]
        )
        let holder = graph.keyBindings[0].id
        let renamed = graph.renameGeneratedID(of: holder, from: unnamed, to: named)
        #expect(renamed)
        // "daru" is taken by another key binding.
        #expect(graph.keyBindings[0].configID == "daru-2")
        #expect(graph.gestures[0].target == .keyBinding("daru-2"))
        #expect(graph.radialMenuBindings[0].target == .keyBinding("daru-2"))
        guard case let .windowAction(spin) = graph.keyBindings[2].target, case let .cycle(steps) = spin.kind else {
            Issue.record("The cycle was lost")
            return
        }
        #expect(steps.steps.first == .keyBinding("daru-2"))
    }

    @Test func handWrittenIDsAndCycleStepsDontRename() {
        let maximize = WindowAction(.maximize)
        let renamed = WindowAction(kind: .custom(.init(name: "Big")), id: maximize.id)
        var graph = ActionTargetEditorGraph(
            keyBindings: [.init(configID: "max", keys: [.kVK_Space], target: .windowAction(maximize))],
            gestures: [],
            radialMenuBindings: [.init(target: .keyBinding("max"))]
        )
        let changed = graph.renameGeneratedID(of: graph.keyBindings[0].id, from: maximize, to: renamed)
        #expect(!changed)
        #expect(graph.keyBindings[0].configID == "max")
        #expect(graph.radialMenuBindings[0].target == .keyBinding("max"))

        let step = ActionTarget.windowAction(.init(.leftHalf))
        let holding = KeyBinding(configID: "cycle", keys: [.kVK_RightArrow], target: .windowAction(.init(kind: .cycle(.init(steps: [step])))))
        graph.keyBindings.append(holding)
        #expect(graph.holder(of: step, owner: holding.reference) == nil)
        #expect(graph.holder(of: holding.target, owner: holding.reference) == holding.id)
        #expect(graph.holder(of: .keyBinding("max"), owner: nil) == graph.keyBindings[0].id)
    }

    @Test func generatedIDsAreTheStemOrItsNumberedForms() {
        #expect(ConfigurationIdentity.isGenerated("custom", from: "custom"))
        #expect(ConfigurationIdentity.isGenerated("custom-3", from: "custom"))
        #expect(!ConfigurationIdentity.isGenerated("custom-1", from: "custom"))
        #expect(!ConfigurationIdentity.isGenerated("custom-x", from: "custom"))
        #expect(!ConfigurationIdentity.isGenerated("max", from: "maximize"))
    }

    @Test func sameCategoryChainsOnlyRewriteTheirTerminalWrapper() throws {
        for category in Category.allCases {
            let original = WindowAction(.custom)
            let action = WindowAction(kind: .custom(.init(name: "Edited")), id: original.id)
            let first = reference(category, "a")
            let middle = reference(category, "b")
            let last = reference(category, "c")
            var graph = ActionTargetEditorGraph(keyBindings: [], gestures: [], radialMenuBindings: [])
            switch category {
            case .key:
                graph.keyBindings = [
                    .init(configID: "a", keys: [.kVK_Space], target: middle),
                    .init(configID: "b", keys: [.kVK_Return], target: last),
                    .init(configID: "c", target: .windowAction(original))
                ]
            case .gesture:
                graph.gestures = [
                    .init(configID: "a", target: middle), .init(configID: "b", target: last),
                    .init(configID: "c", target: .windowAction(original))
                ]
            case .radial:
                graph.radialMenuBindings = [
                    .init(configID: "a", target: middle), .init(configID: "b", target: last),
                    .init(configID: "c", target: .windowAction(original))
                ]
            }
            let before = graph
            try apply(#require(graph.replacingAction(in: first, with: action)), to: &graph)
            #expect(graph.resolve(first) == action)
            switch category {
            case .key:
                #expect(Array(graph.keyBindings.prefix(2)) == Array(before.keyBindings.prefix(2)))
                #expect(graph.keyBindings.map(\.id) == before.keyBindings.map(\.id))
                #expect(graph.keyBindings.map(\.keys) == before.keyBindings.map(\.keys))
            case .gesture:
                #expect(Array(graph.gestures.prefix(2)) == Array(before.gestures.prefix(2)))
                #expect(graph.gestures.map(\.id) == before.gestures.map(\.id))
            case .radial:
                #expect(Array(graph.radialMenuBindings.prefix(2)) == Array(before.radialMenuBindings.prefix(2)))
                #expect(graph.radialMenuBindings.map(\.id) == before.radialMenuBindings.map(\.id))
            }
        }
    }

    @Test func mixedCategoryChainWithRepeatedCategoryChangesOnlyTerminalCollection() throws {
        let original = WindowAction(.custom)
        var edited = original
        edited.name = "New label"
        var graph = ActionTargetEditorGraph(
            keyBindings: [.init(configID: "a", target: .gestureBinding("b")), .init(configID: "c", target: .radialMenuBinding("d"))],
            gestures: [.init(configID: "b", target: .keyBinding("c"))],
            radialMenuBindings: [.init(configID: "d", target: .windowAction(original))]
        )
        let before = graph
        let replacement = try #require(graph.replacingAction(in: .keyBinding("a"), with: edited))
        guard case .radialMenuBindings = replacement else { Issue.record("Expected one terminal radial-menu write"); return }
        apply(replacement, to: &graph)
        #expect(graph.resolve(.keyBinding("a")) == edited)
        #expect(graph.keyBindings == before.keyBindings)
        #expect(graph.gestures == before.gestures)
        #expect(graph.radialMenuBindings.first?.id == before.radialMenuBindings.first?.id)
    }

    @Test func resolutionUsesEditedCollectionsWithoutRuntimeCacheRefresh() {
        var graph = ActionTargetEditorGraph(
            keyBindings: [.init(configID: "key", target: .gestureBinding("gesture"))],
            gestures: [.init(configID: "gesture", target: .radialMenuBinding("radial"))],
            radialMenuBindings: [.init(configID: "radial", target: .windowAction(.init(.custom)))]
        )
        #expect(graph.resolve(.keyBinding("key"))?.name == nil)
        let edited = WindowAction(kind: .custom(.init(name: "Immediately visible")))
        graph.radialMenuBindings[0].target = .windowAction(edited)
        #expect(graph.resolve(.keyBinding("key"))?.getName() == "Immediately visible")
        graph.gestures[0].target = .windowAction(.init(.maximize))
        #expect(graph.resolve(.keyBinding("key"))?.direction == .maximize)
        graph.keyBindings[0].target = .windowAction(.init(.stash))
        #expect(graph.resolve(.keyBinding("key"))?.direction == .stash)
    }

    @Test func danglingAndCyclicReferencesCannotBeEdited() {
        let graph = ActionTargetEditorGraph(
            keyBindings: [.init(configID: "a", target: .gestureBinding("b"))],
            gestures: [.init(configID: "b", target: .keyBinding("a")), .init(kind: .radialMenu, configID: "mode")],
            radialMenuBindings: []
        )
        for target in [ActionTarget.keyBinding("a"), .keyBinding("missing"), .gestureBinding("mode"), .radialMenuMode] {
            #expect(graph.resolve(target) == nil)
            #expect(graph.replacingAction(in: target, with: .init(.maximize)) == nil)
        }
    }

    @Test func pickerExcludesSelfAndDependentReferences() {
        let unnamed = KeyBinding(target: .windowAction(.init(.maximize)))
        let graph = ActionTargetEditorGraph(
            keyBindings: [
                unnamed,
                .init(configID: "a", target: .windowAction(.init(.maximize))),
                .init(configID: "b", target: .keyBinding("a"))
            ],
            gestures: [.init(configID: "g", target: .windowAction(.init(.maximize)))],
            radialMenuBindings: [.init(configID: "r", target: .gestureBinding("g"))]
        )
        #expect(!graph.canSetTarget(unnamed.reference, for: unnamed.reference))
        #expect(!graph.canSetTarget(.keyBinding("a"), for: .keyBinding("a")))
        #expect(!graph.canSetTarget(.keyBinding("b"), for: .keyBinding("a")))
        #expect(!graph.canSetTarget(.radialMenuBinding("r"), for: .gestureBinding("g")))
        #expect(graph.canSetTarget(.gestureBinding("g"), for: .keyBinding("a")))
    }

    private func reference(_ category: Category, _ id: String) -> ActionTarget {
        switch category {
        case .key: .keyBinding(id)
        case .gesture: .gestureBinding(id)
        case .radial: .radialMenuBinding(id)
        }
    }

    private func apply(_ replacement: ActionTargetEditorGraph.Replacement, to graph: inout ActionTargetEditorGraph) {
        switch replacement {
        case let .keyBindings(values): graph.keyBindings = values
        case let .gestures(values): graph.gestures = values
        case let .radialMenuBindings(values): graph.radialMenuBindings = values
        case .direct: Issue.record("Expected a referenced terminal wrapper")
        }
    }
}
