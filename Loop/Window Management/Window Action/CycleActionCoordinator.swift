//
//  CycleActionCoordinator.swift
//  Loop
//
//  Created by Kai Azim on 2026-08-30.
//

import CoreGraphics
import Foundation

struct CycleActionCoordinator {
    /// `false` when the trigger keys or the action's own keybind already contain Shift.
    static func allowsShiftReverseCycle(sourceBinding: KeyBinding?, triggerKeys: KeyCombination, enabled: Bool) -> Bool {
        enabled && !triggerKeys.containsFixedKey(.kVK_Shift) && (sourceBinding.map { !$0.keys.containsFixedKey(.kVK_Shift) } ?? true)
    }

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
    private var keybindSequenceOrigin: KeyBinding?

    mutating func proposeAction(
        for targetWindowID: CGWindowID,
        in cycleAction: WindowAction,
        currentAction: WindowAction,
        currentParentAction: WindowAction?,
        recordedAction: WindowAction?,
        restartAtBeginningWhenInterrupted: Bool,
        mode: SelectionMode,
        currentBinding: KeyBinding? = nil,
        cycleBinding: KeyBinding? = nil
    ) -> Proposal? {
        let currentActionBelongsToCycle = cycleAction.resolvedCycleSteps?.contains {
            $0.id == currentAction.id
        } == true
        let isInsideCycle = currentActionBelongsToCycle || currentParentAction?.id == cycleAction.id || Self.isRepeatingLongerKeybind(
            keybindSequenceOrigin: keybindSequenceOrigin,
            currentBinding: currentBinding,
            cycleBinding: cycleBinding
        )
        let restartAtBeginning = Self.shouldRestartAtBeginning(
            whenEnabled: restartAtBeginningWhenInterrupted,
            currentAction: currentAction,
            currentParentAction: currentParentAction,
            keybindSequenceOrigin: keybindSequenceOrigin,
            currentBinding: currentBinding,
            cycleBinding: cycleBinding,
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
        currentBinding: KeyBinding? = nil,
        newBinding: KeyBinding? = nil
    ) {
        let continuesKeybindSequence = currentBinding.map { current in
            !current.keys.isEmpty && newBinding.map { current.keys.names.isStrictSubset(of: $0.keys.names) } == true
        } == true
        if !continuesKeybindSequence { keybindSequenceOrigin = currentBinding }
    }

    static func shouldRestartAtBeginning(
        whenEnabled isEnabled: Bool,
        currentAction: WindowAction,
        currentParentAction: WindowAction?,
        keybindSequenceOrigin: KeyBinding?,
        currentBinding: KeyBinding? = nil,
        cycleBinding: KeyBinding? = nil,
        in cycleAction: WindowAction
    ) -> Bool {
        let isRepeatingLongerKeybind = isRepeatingLongerKeybind(
            keybindSequenceOrigin: keybindSequenceOrigin,
            currentBinding: currentBinding,
            cycleBinding: cycleBinding
        )

        return isEnabled && (
            !isRepeatingLongerKeybind && (
                currentAction.direction == .noSelection ||
                    (currentParentAction?.id != cycleAction.id &&
                        cycleAction.resolvedCycleSteps?.contains { $0.id == currentAction.id } != true)
            )
        )
    }

    /// Holding a shorter keybind while repeating the cycle's longer one briefly selects the shorter action first
    private static func isRepeatingLongerKeybind(
        keybindSequenceOrigin: KeyBinding?,
        currentBinding: KeyBinding? = nil,
        cycleBinding: KeyBinding? = nil
    ) -> Bool {
        guard let currentBinding, let cycleBinding else { return false }
        return keybindSequenceOrigin?.id == cycleBinding.id
            && !currentBinding.keys.isEmpty
            && currentBinding.keys.names.isStrictSubset(of: cycleBinding.keys.names)
    }
}
