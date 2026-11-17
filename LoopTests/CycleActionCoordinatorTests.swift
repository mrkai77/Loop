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
        let prefixCycle = WindowAction(cycle: [outside])
        let prefixBinding = KeyBinding(id: prefixCycle.id, keys: [.kVK_LeftArrow], target: .windowAction(prefixCycle))
        let dualKeyCycle = WindowAction(
            cycle: children
        )
        let dualBinding = KeyBinding(id: dualKeyCycle.id, keys: [.kVK_LeftArrow, .kVK_RightArrow], target: .windowAction(dualKeyCycle))
        let unrelatedCycle = WindowAction(cycle: [outside])
        let unrelatedBinding = KeyBinding(id: unrelatedCycle.id, keys: [.kVK_UpArrow], target: .windowAction(unrelatedCycle))

        #expect(CycleActionCoordinator.shouldRestartAtBeginning(
            whenEnabled: true,
            currentAction: outside,
            currentParentAction: nil,
            keybindSequenceOrigin: nil,
            in: cycle
        ))
        #expect(CycleActionCoordinator.shouldRestartAtBeginning(
            whenEnabled: true,
            currentAction: .init(.noSelection),
            currentParentAction: nil,
            keybindSequenceOrigin: nil,
            in: cycle
        ))
        #expect(!CycleActionCoordinator.shouldRestartAtBeginning(
            whenEnabled: true,
            currentAction: first,
            currentParentAction: cycle,
            keybindSequenceOrigin: nil,
            in: cycle
        ))
        #expect(!CycleActionCoordinator.shouldRestartAtBeginning(
            whenEnabled: false,
            currentAction: outside,
            currentParentAction: nil,
            keybindSequenceOrigin: nil,
            in: cycle
        ))
        #expect(CycleActionCoordinator.shouldRestartAtBeginning(
            whenEnabled: true,
            currentAction: outside,
            currentParentAction: prefixCycle,
            keybindSequenceOrigin: nil,
            currentBinding: prefixBinding,
            cycleBinding: dualBinding,
            in: dualKeyCycle
        ))
        #expect(!CycleActionCoordinator.shouldRestartAtBeginning(
            whenEnabled: true,
            currentAction: outside,
            currentParentAction: prefixCycle,
            keybindSequenceOrigin: dualBinding,
            currentBinding: prefixBinding,
            cycleBinding: dualBinding,
            in: dualKeyCycle
        ))
        #expect(CycleActionCoordinator.shouldRestartAtBeginning(
            whenEnabled: true,
            currentAction: outside,
            currentParentAction: prefixCycle,
            keybindSequenceOrigin: unrelatedBinding,
            currentBinding: prefixBinding,
            cycleBinding: dualBinding,
            in: dualKeyCycle
        ))
    }

    @Test func resumingCurrentFromOutsideResumesSessionProgress() throws {
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
        coordinator.recordActionTransition()
        let radialSelection = try commitNext(
            with: &coordinator,
            in: cycle,
            currentAction: noSelection,
            currentParentAction: nil,
            mode: .resumeCurrent
        )
        coordinator.recordActionTransition()

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
