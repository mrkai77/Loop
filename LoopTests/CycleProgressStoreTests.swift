//
//  CycleProgressStoreTests.swift
//  LoopTests
//
//  Created by Kai Azim on 2026-08-29.
//

import CoreGraphics
@testable import Loop
import Testing

struct CycleProgressStoreTests {
    private let targetA: CGWindowID = 1
    private let targetB: CGWindowID = 2

    @Test func restartBeginsAtTheFirstChildEvenWithStoredProgress() throws {
        let first = WindowAction(.leftHalf)
        let second = WindowAction(.rightHalf)
        let cycle = WindowAction([first, second])
        var store = CycleProgressStore()

        _ = try commitNext(
            in: &store,
            target: targetA,
            cycle: cycle,
            restartAtBeginning: true
        )
        let secondSelection = try commitNext(
            in: &store,
            target: targetA,
            cycle: cycle
        )
        let restarted = try selection(
            from: &store,
            target: targetA,
            cycle: cycle,
            restartAtBeginning: true
        )

        #expect(secondSelection.action.id == second.id)
        #expect(restarted.action.id == first.id)
        #expect(restarted.index == 0)
    }

    @Test func storedProgressAdvancesAndWrapsForward() throws {
        let first = WindowAction(.leftHalf)
        let second = WindowAction(.maximize)
        let third = WindowAction(.rightHalf)
        let cycle = WindowAction([first, second, third])
        var store = CycleProgressStore()

        let selections = try (0 ..< 4).map { index in
            try commitNext(
                in: &store,
                target: targetA,
                cycle: cycle,
                restartAtBeginning: index == 0
            )
        }

        #expect(selections.map(\.action.id) == [first.id, second.id, third.id, first.id])
        #expect(selections.map(\.index) == [0, 1, 2, 0])
    }

    @Test func storedProgressAdvancesAndWrapsBackward() throws {
        let first = WindowAction(.leftHalf)
        let second = WindowAction(.maximize)
        let third = WindowAction(.rightHalf)
        let cycle = WindowAction([first, second, third])
        var store = CycleProgressStore()

        let initial = try commitNext(
            in: &store,
            target: targetA,
            cycle: cycle,
            restartAtBeginning: true
        )
        let wrapped = try commitNext(
            in: &store,
            target: targetA,
            cycle: cycle,
            direction: .backward
        )
        let previous = try commitNext(
            in: &store,
            target: targetA,
            cycle: cycle,
            direction: .backward
        )

        #expect(initial.action.id == first.id)
        #expect(wrapped.action.id == third.id)
        #expect(previous.action.id == second.id)
    }

    @Test func parentCyclesKeepIndependentCursors() throws {
        let firstA = WindowAction(.leftHalf)
        let secondA = WindowAction(.rightHalf)
        let firstB = WindowAction(.topHalf)
        let secondB = WindowAction(.bottomHalf)
        let cycleA = WindowAction([firstA, secondA])
        let cycleB = WindowAction([firstB, secondB])
        var store = CycleProgressStore()

        _ = try commitNext(
            in: &store,
            target: targetA,
            cycle: cycleA,
            restartAtBeginning: true
        )
        let seededB = try commitNext(
            in: &store,
            target: targetA,
            cycle: cycleB,
            restartAtBeginning: true
        )
        let resumedA = try selection(
            from: &store,
            target: targetA,
            cycle: cycleA
        )

        #expect(seededB.action.id == firstB.id)
        #expect(resumedA.action.id == secondA.id)
    }

    @Test func reorderedChildrenFollowTheSelectedChildID() throws {
        let first = WindowAction(.leftHalf)
        let second = WindowAction(.maximize)
        let third = WindowAction(.rightHalf)
        var cycle = WindowAction([first, second, third])
        var store = CycleProgressStore()

        _ = try commitNext(
            in: &store,
            target: targetA,
            cycle: cycle,
            restartAtBeginning: true
        )
        cycle.cycle = [second, first, third]
        let selection = try selection(from: &store, target: targetA, cycle: cycle)

        #expect(selection.action.id == third.id)
        #expect(selection.index == 2)
    }

    @Test func removedSelectedChildReseedsFromTheUpdatedCycle() throws {
        let first = WindowAction(.leftHalf)
        let removed = WindowAction(.maximize)
        let third = WindowAction(.rightHalf)
        var cycle = WindowAction([first, removed, third])
        var store = CycleProgressStore()

        _ = try commitNext(
            in: &store,
            target: targetA,
            cycle: cycle,
            restartAtBeginning: true
        )
        _ = try commitNext(in: &store, target: targetA, cycle: cycle)
        cycle.cycle = [first, third]
        let selection = try selection(
            from: &store,
            target: targetA,
            cycle: cycle,
            seededBy: third
        )

        #expect(selection.action.id == first.id)
        #expect(selection.index == 0)
    }

    @Test func targetWindowsKeepIndependentCursors() throws {
        let first = WindowAction(.leftHalf)
        let second = WindowAction(.maximize)
        let third = WindowAction(.rightHalf)
        let cycle = WindowAction([first, second, third])
        var store = CycleProgressStore()

        _ = try commitNext(
            in: &store,
            target: targetA,
            cycle: cycle,
            restartAtBeginning: true
        )
        _ = try commitNext(in: &store, target: targetA, cycle: cycle)
        _ = try commitNext(
            in: &store,
            target: targetB,
            cycle: cycle,
            restartAtBeginning: true
        )
        let nextA = try selection(from: &store, target: targetA, cycle: cycle)
        let nextB = try selection(from: &store, target: targetB, cycle: cycle)

        #expect(nextA.action.id == third.id)
        #expect(nextB.action.id == second.id)
    }

    @Test func singleChildCycleRemainsOnItsOnlyChild() throws {
        let only = WindowAction(.leftHalf)
        let cycle = WindowAction([only])
        var store = CycleProgressStore()

        let first = try commitNext(
            in: &store,
            target: targetA,
            cycle: cycle,
            restartAtBeginning: true
        )
        let forward = try commitNext(in: &store, target: targetA, cycle: cycle)
        let backward = try selection(
            from: &store,
            target: targetA,
            cycle: cycle,
            direction: .backward
        )

        #expect(first.action.id == only.id)
        #expect(forward.action.id == only.id)
        #expect(backward.action.id == only.id)
        #expect([first.index, forward.index, backward.index] == [0, 0, 0])
    }

    @Test func selectingDuplicateChildPreservesSelectedOccurrence() throws {
        let repeated = WindowAction(.leftHalf)
        let middle = WindowAction(.maximize)
        let cycle = WindowAction([repeated, middle, repeated])
        var store = CycleProgressStore()

        _ = try commitNext(
            in: &store,
            target: targetA,
            cycle: cycle,
            restartAtBeginning: true
        )
        _ = try commitNext(in: &store, target: targetA, cycle: cycle)
        _ = try commitNext(in: &store, target: targetA, cycle: cycle)
        let currentSelection = store.proposeCurrentSelection(
            for: targetA,
            in: cycle,
            seededBy: repeated,
            resumingProgress: false
        )
        let selected = try #require(currentSelection)
        _ = store.commit(selected, for: targetA, in: cycle)

        let next = try selection(from: &store, target: targetA, cycle: cycle)

        #expect(selected.index == 2)
        #expect(next.index == 0)
    }

    private func selection(
        from store: inout CycleProgressStore,
        target: CGWindowID,
        cycle: WindowAction,
        seededBy seedAction: WindowAction? = nil,
        restartAtBeginning: Bool = false,
        direction: CycleProgressStore.Direction = .forward
    ) throws -> CycleProgressStore.Selection {
        let selection = store.proposeSelection(
            for: target,
            in: cycle,
            seededBy: seedAction,
            restartAtBeginning: restartAtBeginning,
            direction: direction
        )
        return try #require(selection)
    }

    private func commitNext(
        in store: inout CycleProgressStore,
        target: CGWindowID,
        cycle: WindowAction,
        seededBy seedAction: WindowAction? = nil,
        restartAtBeginning: Bool = false,
        direction: CycleProgressStore.Direction = .forward
    ) throws -> CycleProgressStore.Selection {
        let selection = try selection(
            from: &store,
            target: target,
            cycle: cycle,
            seededBy: seedAction,
            restartAtBeginning: restartAtBeginning,
            direction: direction
        )
        let committedAction = store.commit(selection, for: target, in: cycle)
        #expect(committedAction?.id == selection.action.id)
        return selection
    }
}
