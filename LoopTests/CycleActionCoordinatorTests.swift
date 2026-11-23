//
//  CycleActionCoordinatorTests.swift
//  LoopTests
//
//  Created by Kai Azim on 2026-08-30.
//

import CoreGraphics
import Foundation
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
        let dualKeyCycle = WindowAction(cycle: children)
        let unrelatedCycle = WindowAction(cycle: [outside])
        let keysByActionID: [UUID: Set<CGKeyCode>] = [
            prefixCycle.id: [.kVK_LeftArrow],
            dualKeyCycle.id: [.kVK_LeftArrow, .kVK_RightArrow],
            unrelatedCycle.id: [.kVK_UpArrow]
        ]
        let keys: CycleActionCoordinator.KeyLookup = { keysByActionID[$0.id] ?? [] }

        #expect(CycleActionCoordinator.shouldRestartAtBeginning(
            whenEnabled: true,
            currentAction: outside,
            currentParentAction: nil,
            keybindSequenceOriginAction: nil,
            in: cycle,
            keys: keys
        ))
        #expect(CycleActionCoordinator.shouldRestartAtBeginning(
            whenEnabled: true,
            currentAction: .init(.noSelection),
            currentParentAction: nil,
            keybindSequenceOriginAction: nil,
            in: cycle,
            keys: keys
        ))
        #expect(!CycleActionCoordinator.shouldRestartAtBeginning(
            whenEnabled: true,
            currentAction: first,
            currentParentAction: cycle,
            keybindSequenceOriginAction: nil,
            in: cycle,
            keys: keys
        ))
        #expect(!CycleActionCoordinator.shouldRestartAtBeginning(
            whenEnabled: false,
            currentAction: outside,
            currentParentAction: nil,
            keybindSequenceOriginAction: nil,
            in: cycle,
            keys: keys
        ))
        #expect(CycleActionCoordinator.shouldRestartAtBeginning(
            whenEnabled: true,
            currentAction: outside,
            currentParentAction: prefixCycle,
            keybindSequenceOriginAction: nil,
            in: dualKeyCycle,
            keys: keys
        ))
        #expect(!CycleActionCoordinator.shouldRestartAtBeginning(
            whenEnabled: true,
            currentAction: outside,
            currentParentAction: prefixCycle,
            keybindSequenceOriginAction: dualKeyCycle,
            in: dualKeyCycle,
            keys: keys
        ))
        #expect(CycleActionCoordinator.shouldRestartAtBeginning(
            whenEnabled: true,
            currentAction: outside,
            currentParentAction: prefixCycle,
            keybindSequenceOriginAction: unrelatedCycle,
            in: dualKeyCycle,
            keys: keys
        ))
    }

    @Test func resumingCurrentFromOutsideResumesSessionProgress() throws {
        let first = WindowAction(.leftHalf)
        let second = WindowAction(.maximize)
        let cycle = WindowAction([first, second])
        let noSelection = WindowAction(.noSelection)
        var coordinator = CycleActionCoordinator { _ in [] }

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
            mode: .resumeCurrent
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
