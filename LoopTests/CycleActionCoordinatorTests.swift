//
//  CycleActionCoordinatorTests.swift
//  LoopTests
//
//  Created by Kai Azim on 2026-08-30.
//

import CoreGraphics
@testable import Loop
import Testing

struct CycleActionCoordinatorTests {
    private let targetWindowID: CGWindowID = 1

    @Test func restartPolicyOnlyRestartsInterruptedCyclesWhenEnabled() {
        let first = WindowAction(.leftHalf)
        let second = WindowAction(.rightHalf)
        let outside = WindowAction(.maximize)
        let children = [first, second]
        let cycle = WindowAction(children)
        let prefixCycle = WindowAction(cycle: [outside], keybind: [.kVK_LeftArrow])
        let dualKeyCycle = WindowAction(
            cycle: children,
            keybind: [.kVK_LeftArrow, .kVK_RightArrow]
        )
        let unrelatedCycle = WindowAction(cycle: [outside], keybind: [.kVK_UpArrow])

        #expect(CycleActionCoordinator.shouldRestartAtBeginning(
            whenEnabled: true,
            currentAction: outside,
            currentParentAction: nil,
            keybindSequenceOriginAction: nil,
            in: cycle
        ))
        #expect(CycleActionCoordinator.shouldRestartAtBeginning(
            whenEnabled: true,
            currentAction: .init(.noSelection),
            currentParentAction: nil,
            keybindSequenceOriginAction: nil,
            in: cycle
        ))
        #expect(!CycleActionCoordinator.shouldRestartAtBeginning(
            whenEnabled: true,
            currentAction: first,
            currentParentAction: cycle,
            keybindSequenceOriginAction: nil,
            in: cycle
        ))
        #expect(!CycleActionCoordinator.shouldRestartAtBeginning(
            whenEnabled: false,
            currentAction: outside,
            currentParentAction: nil,
            keybindSequenceOriginAction: nil,
            in: cycle
        ))
        #expect(CycleActionCoordinator.shouldRestartAtBeginning(
            whenEnabled: true,
            currentAction: outside,
            currentParentAction: prefixCycle,
            keybindSequenceOriginAction: nil,
            in: dualKeyCycle
        ))
        #expect(!CycleActionCoordinator.shouldRestartAtBeginning(
            whenEnabled: true,
            currentAction: outside,
            currentParentAction: prefixCycle,
            keybindSequenceOriginAction: dualKeyCycle,
            in: dualKeyCycle
        ))
        #expect(CycleActionCoordinator.shouldRestartAtBeginning(
            whenEnabled: true,
            currentAction: outside,
            currentParentAction: prefixCycle,
            keybindSequenceOriginAction: unrelatedCycle,
            in: dualKeyCycle
        ))
    }

    @Test func selectingCurrentChildUpdatesStoredProgress() throws {
        let first = WindowAction(.leftHalf)
        let second = WindowAction(.maximize)
        let cycle = WindowAction([first, second])
        let noSelection = WindowAction(.noSelection)
        var coordinator = CycleActionCoordinator()

        _ = try commitNext(
            with: &coordinator,
            in: cycle,
            currentAction: noSelection,
            currentParentAction: nil,
            restartAtBeginning: true
        )
        let secondSelection = try commitNext(
            with: &coordinator,
            in: cycle,
            currentAction: first,
            currentParentAction: cycle
        )
        coordinator.recordActionTransition(
            from: secondSelection,
            currentParentAction: cycle,
            to: noSelection,
            newParentAction: nil
        )
        let radialSelection = try commitNext(
            with: &coordinator,
            in: cycle,
            currentAction: noSelection,
            currentParentAction: nil,
            mode: .selectCurrent
        )
        coordinator.recordActionTransition(
            from: noSelection,
            currentParentAction: nil,
            to: radialSelection,
            newParentAction: cycle
        )

        let nextProposal = coordinator.proposeAction(
            for: targetWindowID,
            in: cycle,
            currentAction: radialSelection,
            currentParentAction: cycle,
            recordedAction: nil,
            restartAtBeginningWhenInterrupted: true,
            mode: .advance(.forward)
        )
        let next = try #require(nextProposal)

        #expect(radialSelection.id == second.id)
        #expect(next.action.id == first.id)
    }

    private func commitNext(
        with coordinator: inout CycleActionCoordinator,
        in cycle: WindowAction,
        currentAction: WindowAction,
        currentParentAction: WindowAction?,
        restartAtBeginning: Bool = false,
        mode: CycleActionCoordinator.SelectionMode = .advance(.forward)
    ) throws -> WindowAction {
        let nextProposal = coordinator.proposeAction(
            for: targetWindowID,
            in: cycle,
            currentAction: currentAction,
            currentParentAction: currentParentAction,
            recordedAction: nil,
            restartAtBeginningWhenInterrupted: restartAtBeginning,
            mode: mode
        )
        let proposal = try #require(nextProposal)
        let committedAction = coordinator.commit(
            proposal,
            for: targetWindowID,
            in: cycle
        )
        return try #require(committedAction)
    }
}
