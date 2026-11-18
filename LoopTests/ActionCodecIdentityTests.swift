//
//  ActionCodecIdentityTests.swift
//  LoopTests
//
//  Created by Kai Azim on 2026-11-14.
//

import Foundation
@testable import Loop
import Testing
import Tome
import TOML

extension StoreTests {
    struct ActionCodecIdentityTests {
        /// Excludes stash identities, which are derived from content.
        private func actionIDs(_ target: ActionTarget) -> [UUID] {
            guard case let .windowAction(action) = target else { return [] }
            if case let .cycle(cycle) = action.kind { return [action.id] + cycle.steps.flatMap(actionIDs) }
            if action.direction == .stash { return [] }
            return [action.id]
        }

        private func directAction(_ target: ActionTarget) throws -> WindowAction {
            guard case let .windowAction(action) = target else { throw TestError.expectedAction }
            return action
        }

        private enum TestError: Error { case expectedAction }

        private func cycleTarget() -> ActionTarget {
            .windowAction(WindowAction("Cycle", cycle: [WindowAction(.leftHalf), WindowAction(.rightHalf), WindowAction(.stash)]))
        }

        /// The first row must not change when an unrelated row is edited.
        private func assertUnchangedTree(
            encoded: TOMLValue,
            decode: (TOMLValue) throws -> [ActionTarget]
        ) throws {
            let initial = try decode(encoded)
            var rows = try TOMLCodecs.decodeArray(encoded)
            var other = try TOMLCodecs.decodeTable(rows[1])
            other["action"] = .string("minimize")
            rows[1] = .table(other)
            let updated = try decode(.array(rows))
            #expect(actionIDs(updated[0]) == actionIDs(initial[0]))
            #expect(!actionIDs(initial[0]).isEmpty)
            #expect(try actionIDs(decode(.array(rows))[0]) == actionIDs(initial[0]))
        }

        @Test func allCategoriesKeepDirectAndStepIDsAcrossUnrelatedRowEdits() throws {
            let target = cycleTarget()
            try assertUnchangedTree(encoded: [KeyBinding(keys: KeyCombination(names: ["a"]), target: target), KeyBinding(.maximize, keys: KeyCombination(names: ["b"]))].encodeTOML()) {
                try [KeyBinding].decodeIdentified($0).map(\.target)
            }
            try assertUnchangedTree(encoded: [RadialMenuBinding(target: target), .custom(WindowAction(.maximize))].encodeTOML()) {
                try [RadialMenuBinding].decodeIdentified($0).map(\.target)
            }
            try assertUnchangedTree(encoded: [GestureBinding(kind: .swipeLeft, target: target), GestureBinding(kind: .swipeRight, target: .windowAction(WindowAction(.maximize)))].encodeTOML()) {
                try [GestureBinding].decodeIdentified($0).map(\.target)
            }
        }

        @Test func unchangedActionKeepsIdentityWhenItsInputMetadataChanges() throws {
            let encoded = try [KeyBinding(keys: KeyCombination(names: ["a"]), target: cycleTarget())].encodeTOML()
            let before = try [KeyBinding].decodeIdentified(encoded)
            var rows = try TOMLCodecs.decodeArray(encoded)
            var table = try TOMLCodecs.decodeTable(rows[0])
            table["keys"] = .string("b")
            rows[0] = .table(table)
            let changed = try [KeyBinding].decodeIdentified(.array(rows))
            #expect(changed[0].keys == KeyCombination(names: ["b"]))
            #expect(actionIDs(changed[0].target) == actionIDs(before[0].target))
        }

        @Test func cycleReorderingPreservesCommittedProgress() throws {
            let cycle = WindowAction("Cycle", cycle: [WindowAction(.leftHalf), WindowAction(.rightHalf), WindowAction(.topHalf)])
            let encoded = try [RadialMenuBinding.custom(cycle)].encodeTOML()
            let initial = try directAction([RadialMenuBinding].decodeIdentified(encoded)[0].target)
            let stepIDs = try #require(initial.resolvedCycleSteps).map(\.id)
            let (left, right, top) = (stepIDs[0], stepIDs[1], stepIDs[2])
            var progress = CycleProgressStore()
            let initialProposal = progress.proposeSelection(for: 42, in: initial, from: .sessionProgress(fallback: nil), moving: .forward)
            let selection = try #require(initialProposal)
            let committed = progress.commit(selection, for: 42, in: initial)
            #expect(committed?.id == left)

            var rows = try TOMLCodecs.decodeArray(encoded)
            var table = try TOMLCodecs.decodeTable(rows[0])
            let steps = try TOMLCodecs.decodeArray(#require(table["cycle"]))
            table["cycle"] = .array([steps[2], steps[0], steps[1]])
            rows[0] = .table(table)
            let updated = try directAction([RadialMenuBinding].decodeIdentified(.array(rows))[0].target)
            #expect(updated.id == initial.id)
            #expect(updated.resolvedCycleSteps?.map(\.id) == [top, left, right])
            let nextProposal = progress.proposeSelection(for: 42, in: updated, from: .sessionProgress(fallback: nil), moving: .forward)
            let next = try #require(nextProposal)
            #expect(next.action.id == right)
            let nextCommitted = progress.commit(next, for: 42, in: updated)
            #expect(nextCommitted?.id == right)
        }

        @Test func duplicateCycleChildrenKeepDistinctOccurrenceIDs() throws {
            let cycle = WindowAction("Repeated", cycle: [WindowAction(.leftHalf), WindowAction(.rightHalf), WindowAction(.leftHalf)])
            let encoded = try [GestureBinding(kind: .swipeLeft, target: .windowAction(cycle))].encodeTOML()
            let initial = try #require(directAction([GestureBinding].decodeIdentified(encoded)[0].target).resolvedCycleSteps).map(\.id)
            #expect(Set(initial).count == 3)
            var rows = try TOMLCodecs.decodeArray(encoded)
            var table = try TOMLCodecs.decodeTable(rows[0])
            let steps = try TOMLCodecs.decodeArray(#require(table["cycle"]))
            table["cycle"] = .array([steps[0], steps[2], steps[1]])
            rows[0] = .table(table)
            let children = try #require(directAction([GestureBinding].decodeIdentified(.array(rows))[0].target).resolvedCycleSteps)
            #expect(children.map(\.id) == [initial[0], initial[2], initial[1]])
        }

        @Test func stashLookupIdentitySurvivesOtherCategoryAndCycleEdits() throws {
            let cycle = WindowAction("Stash cycle", cycle: [WindowAction(.leftHalf), WindowAction(.stash)])
            let keyValue = try [KeyBinding(configID: "stash-cycle", target: .windowAction(cycle))].encodeTOML()
            let initial = try [KeyBinding].decodeIdentified(keyValue)
            let snapshot = BindingResolutionSnapshot(keyBindings: initial, gestureBindings: [], radialMenuBindings: [])
            let resolved = try snapshot.resolve(.reference(.init(.key, "stash-cycle")))
            let stashedAction = try #require(resolved.resolvedCycleSteps?.last)
            // StashedWindowsStore matches this exact UUID after a restart
            let lookupID = stashedAction.id
            let restarted = try [KeyBinding].decodeIdentified(keyValue)
            let restartedCycle = try BindingResolutionSnapshot(keyBindings: restarted, gestureBindings: [], radialMenuBindings: []).resolve(.reference(.init(.key, "stash-cycle")))
            #expect(restartedCycle.resolvedCycleSteps?.last?.id == lookupID)
            _ = try [GestureBinding].decodeIdentified([GestureBinding(kind: .swipeUp, target: .windowAction(WindowAction(.maximize)))].encodeTOML())
            _ = try [RadialMenuBinding].decodeIdentified([RadialMenuBinding.custom(WindowAction(.minimize))].encodeTOML())
            let refreshed = try [KeyBinding].decodeIdentified(keyValue)
            let refreshedSnapshot = BindingResolutionSnapshot(keyBindings: refreshed, gestureBindings: [], radialMenuBindings: [])
            let refreshedCycle = try refreshedSnapshot.resolve(.reference(.init(.key, "stash-cycle")))
            #expect(refreshedCycle.resolvedCycleSteps?.last?.id == lookupID)
        }

        @Test func validatingAnotherProfileCannotChangeRunningActionIdentities() throws {
            let source = """
            [[key.bindings]]
            id = "key-cycle-a"
            keys = "a"
            action = "cycle"
            name = "Key cycle A"
            cycle = [{ action = "stash", name = "Key stash A" }, { action = "left-half" }]
            [[key.bindings]]
            action = "maximize"
            keys = "b"
            [[radial-menu.bindings]]
            id = "radial-cycle-a"
            action = "cycle"
            name = "Radial cycle A"
            cycle = [{ action = "stash", name = "Radial stash A" }, { action = "right-half" }]
            [[radial-menu.bindings]]
            action = "maximize"
            [[gestures.bindings]]
            id = "gesture-cycle-a"
            kind = "swipe-left"
            action = "cycle"
            name = "Gesture cycle A"
            cycle = [{ action = "stash", name = "Gesture stash A" }, { action = "top-half" }]
            [[gestures.bindings]]
            kind = "swipe-right"
            action = "maximize"
            """
            let settings = try Profile(source)
            let url = settings.url
            let keyTarget = try #require(settings[\.keyBindings].identified().first?.target)
            let radialTarget = try #require(settings[\.radialMenuBindings].identified().first?.target)
            let gestureTarget = try #require(settings[\.gestureBindings].identified().first?.target)
            let keyCycle = try directAction(keyTarget)
            var progress = CycleProgressStore()
            let proposed = progress.proposeSelection(for: 42, in: keyCycle, from: .sessionProgress(fallback: nil), moving: .forward)
            let selection = try #require(proposed)
            let committed = progress.commit(selection, for: 42, in: keyCycle)
            #expect(committed?.direction == .stash)
            let stashLookupID = try #require(committed?.id)

            let candidate = source.replacingOccurrences(of: "-a\"", with: "-b\"")
                .replacingOccurrences(of: " A\"", with: " B\"")
                .replacingOccurrences(of: "action = \"stash\"", with: "action = \"custom\"")
            #expect(try !Migrator.importConfiguration(candidate, confirmed: false))
            #expect(settings.serialized == source)

            try source.replacingOccurrences(of: "action = \"maximize\"", with: "action = \"minimize\"")
                .write(to: url, atomically: true, encoding: .utf8)
            try settings.reload()
            let updatedKey = try #require(settings[\.keyBindings].identified().first?.target)
            let updatedRadial = try #require(settings[\.radialMenuBindings].identified().first?.target)
            let updatedGesture = try #require(settings[\.gestureBindings].identified().first?.target)
            #expect(actionIDs(updatedKey) == actionIDs(keyTarget))
            #expect(actionIDs(updatedRadial) == actionIDs(radialTarget))
            #expect(actionIDs(updatedGesture) == actionIDs(gestureTarget))
            let updatedCycle = try directAction(updatedKey)
            #expect(updatedCycle.resolvedCycleSteps?.first?.id == stashLookupID)
            let nextProposal = progress.proposeSelection(for: 42, in: updatedCycle, from: .sessionProgress(fallback: nil), moving: .forward)
            let next = try #require(nextProposal)
            #expect(next.action.direction == .leftHalf)
        }

        @MainActor @Test func directReadsSeePendingWritesImmediately() throws {
            let source = "[[key.bindings]]\nkeys=\"a\"\naction=\"maximize\"\n"
            let settings = try Profile(source)
            let url = settings.url
            var bindings = settings[\.keyBindings]
            bindings[0].target = .windowAction(WindowAction(.leftHalf))
            settings[\.keyBindings] = bindings
            #expect(settings[\.keyBindings].first?.target.semanticKey == bindings[0].target.semanticKey)
            #expect(try String(contentsOf: url, encoding: .utf8) == source)

            bindings[0].target = .windowAction(WindowAction(.rightHalf))
            settings[\.keyBindings] = bindings
            #expect(settings[\.keyBindings].first?.target.semanticKey == bindings[0].target.semanticKey)
            #expect(try String(contentsOf: url, encoding: .utf8) == source)
            try settings.flush()
            #expect(try String(contentsOf: url, encoding: .utf8).contains("action=\"right-half\""))
        }
    }
}
