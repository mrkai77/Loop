//
//  CycleActionCoordinator.swift
//  Loop
//
//  Created by Kai Azim on 2026-08-30.
//

import CoreGraphics

struct CycleActionCoordinator {
    enum SelectionMode {
        case advance(CycleProgressStore.Direction)
        case selectCurrent
        /// Like `selectCurrent`, but coming from outside the cycle resumes this session's progress.
        /// Used by gestures, where moving back into an already visited action shouldn't move on in its cycle.
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
        let isInsideCycle = currentActionBelongsToCycle || Self.isRepeatingLongerKeybind(
            currentAction: currentAction,
            currentParentAction: currentParentAction,
            keybindSequenceOriginAction: keybindSequenceOriginAction,
            in: cycleAction
        )
        let restartAtBeginning = Self.shouldRestartAtBeginning(
            whenEnabled: restartAtBeginningWhenInterrupted,
            currentAction: currentAction,
            currentParentAction: currentParentAction,
            keybindSequenceOriginAction: keybindSequenceOriginAction,
            in: cycleAction
        )

        // Inside the cycle, progress continues from this session. Entering it starts from the window's recorded
        // progress, except for gestures moving back into an action they already visited.
        let origin: CycleProgressStore.Origin = if isInsideCycle {
            .sessionProgress(fallback: currentActionBelongsToCycle ? currentAction : nil)
        } else if case .resumeCurrent = mode {
            .sessionProgress(fallback: nil)
        } else {
            .action(restartAtBeginning ? nil : recordedAction)
        }

        // Selecting a cycle from outside shows what advancing into it would select
        let direction: CycleProgressStore.Direction? = switch mode {
        case let .advance(direction): direction
        case .selectCurrent: isInsideCycle ? nil : .forward
        case .resumeCurrent: nil
        }

        let selection = progressStore.proposeSelection(
            for: targetWindowID,
            in: cycleAction,
            from: origin,
            moving: direction
        )

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
        let isRepeatingLongerKeybind = isRepeatingLongerKeybind(
            currentAction: currentAction,
            currentParentAction: currentParentAction,
            keybindSequenceOriginAction: keybindSequenceOriginAction,
            in: cycleAction
        )

        return isEnabled && (
            !isRepeatingLongerKeybind && (
                currentAction.direction == .noSelection ||
                    cycleAction.cycle?.contains { $0.id == currentAction.id } != true
            )
        )
    }

    /// Holding a shorter keybind while repeating the cycle's longer one briefly selects the shorter action first
    private static func isRepeatingLongerKeybind(
        currentAction: WindowAction,
        currentParentAction: WindowAction?,
        keybindSequenceOriginAction: WindowAction?,
        in cycleAction: WindowAction
    ) -> Bool {
        let currentKeybind = currentParentAction?.keybind ?? currentAction.keybind
        return keybindSequenceOriginAction?.id == cycleAction.id
            && !currentKeybind.isEmpty
            && currentKeybind.isStrictSubset(of: cycleAction.keybind)
    }
}
