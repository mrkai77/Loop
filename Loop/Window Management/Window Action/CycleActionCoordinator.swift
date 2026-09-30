//
//  CycleActionCoordinator.swift
//  Loop
//
//  Created by Kai Azim on 2026-08-30.
//

import CoreGraphics

struct CycleActionCoordinator {
    enum SelectionMode: Equatable {
        case advance(CycleProgressStore.Direction)
        case selectCurrent
        /// Like `selectCurrent`, but coming from outside the cycle resumes where it was left.
        /// Used by gestures, where moving back into an already visited action shouldn't restart its cycle.
        case resumeCurrent
    }

    struct Proposal {
        let action: WindowAction

        fileprivate let selection: CycleProgressStore.Selection
    }

    private var progressStore = CycleProgressStore()
    private var keybindSequenceOriginAction: WindowAction?

    mutating func proposeAction(
        for targetWindowID: CGWindowID,
        in cycleAction: WindowAction,
        currentAction: WindowAction,
        currentParentAction: WindowAction?,
        recordedAction: WindowAction?,
        restartAtBeginningWhenInterrupted: Bool,
        mode: SelectionMode
    ) -> Proposal? {
        let currentActionBelongsToCycle = cycleAction.cycle?.contains {
            $0.id == currentAction.id
        } == true
        let restartAtBeginning = Self.shouldRestartAtBeginning(
            whenEnabled: restartAtBeginningWhenInterrupted,
            currentAction: currentAction,
            currentParentAction: currentParentAction,
            keybindSequenceOriginAction: keybindSequenceOriginAction,
            in: cycleAction
        )
        let seedAction: WindowAction? = if restartAtBeginning {
            nil
        } else if currentActionBelongsToCycle {
            currentAction
        } else {
            recordedAction
        }
        let selection: CycleProgressStore.Selection? = switch mode {
        case let .advance(direction):
            progressStore.proposeSelection(
                for: targetWindowID,
                in: cycleAction,
                seededBy: seedAction,
                restartAtBeginning: restartAtBeginning,
                direction: direction
            )
        case .selectCurrent, .resumeCurrent:
            progressStore.proposeCurrentSelection(
                for: targetWindowID,
                in: cycleAction,
                seededBy: currentActionBelongsToCycle ? currentAction : nil,
                resumingProgress: mode == .resumeCurrent
            )
        }

        guard let selection else {
            return nil
        }

        return Proposal(action: selection.action, selection: selection)
    }

    mutating func commit(
        _ proposal: Proposal,
        for targetWindowID: CGWindowID,
        in cycleAction: WindowAction
    ) -> WindowAction? {
        progressStore.commit(
            proposal.selection,
            for: targetWindowID,
            in: cycleAction
        )
    }

    mutating func recordActionTransition(
        from currentAction: WindowAction,
        currentParentAction: WindowAction?,
        to newAction: WindowAction,
        newParentAction: WindowAction?
    ) {
        let currentBindingAction = currentParentAction ?? currentAction
        let nextBindingAction = newParentAction ?? newAction
        let continuesKeybindSequence = !currentBindingAction.keybind.isEmpty
            && currentBindingAction.keybind.isStrictSubset(of: nextBindingAction.keybind)

        if !continuesKeybindSequence {
            keybindSequenceOriginAction = currentBindingAction
        }
    }

    static func shouldRestartAtBeginning(
        whenEnabled isEnabled: Bool,
        currentAction: WindowAction,
        currentParentAction: WindowAction?,
        keybindSequenceOriginAction: WindowAction?,
        in cycleAction: WindowAction
    ) -> Bool {
        let currentKeybind = currentParentAction?.keybind ?? currentAction.keybind
        let isRepeatingLongerKeybind = keybindSequenceOriginAction?.id == cycleAction.id
            && !currentKeybind.isEmpty
            && currentKeybind.isStrictSubset(of: cycleAction.keybind)

        return isEnabled && (
            !isRepeatingLongerKeybind && (
                currentAction.direction == .noSelection ||
                    cycleAction.cycle?.contains { $0.id == currentAction.id } != true
            )
        )
    }
}
