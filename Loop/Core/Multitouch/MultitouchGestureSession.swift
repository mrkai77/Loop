//
//  MultitouchGestureSession.swift
//  Loop
//
//  Created by Kai Azim on 2026-01-30.
//

import SwiftUI

@MainActor
final class MultitouchGestureSession {
    enum ActionKey: Hashable {
        case radialSlot(Int)
        case radialCenter
        case gesture(UUID)
    }

    private(set) var didOpenLoopWithThisGesture = false
    private(set) var isGestureRejected = false
    private(set) var hasActivated = false
    private(set) var hasGestureBegun = false
    private(set) var ownsGestureBlocker = false
    /// The gesture currently driving this stroke. Swapped on direction reversal
    private(set) var resolvedGesture: GestureBinding?
    /// Kept so an override can hand the stroke back to the radial menu it began as
    private var radialMenuGesture: GestureBinding?
    private(set) var pendingTargetWindow: Window?
    private var activationContext: MultitouchGestureActivationContext?
    /// Set once Loop rejects or abandons the stroke, as the Dock may already be acting on it
    private var isStrokeLocked = false
    /// Bindings excluded by their activation zone, treated as unbound so another direction can still begin
    private var ineligibleGestureIDs: Set<UUID> = []

    private var lastCommittedAction: ActionKey?
    private var visitedActions: Set<ActionKey> = []
    /// Returning to an action this gesture already committed shouldn't advance its cycle
    private(set) var isRevisitingAction = false
    private var lastCommittedSwipeStepIndex: Int?
    private var swipeStepDistance: CGFloat?
    private var swipeActivationDistance: CGFloat?
    private var firstCommitSwipeDistance: CGFloat?
    private var swipeMoveBackResetActive = false
    private var swipeActionResetActive = false
    private var lastCommittedMagnifyStepIndex: Int?
    private var magnifyStepDistance: CGFloat?
    private var magnifyActivationDistance: CGFloat?
    /// Where the current magnify action was selected. Repeats step from here, like swipes do.
    private var firstCommitMagnifyDistance: CGFloat?
    private var magnifyMoveBackResetActive = false
    private var magnifyKind: GestureBinding.Kind?

    func reset(endsStroke: Bool = true) {
        didOpenLoopWithThisGesture = false
        isGestureRejected = false
        hasActivated = false
        hasGestureBegun = false
        ownsGestureBlocker = false
        resolvedGesture = nil
        radialMenuGesture = nil
        pendingTargetWindow = nil
        activationContext = nil
        if endsStroke {
            isStrokeLocked = false
            ineligibleGestureIDs.removeAll()
        }
        lastCommittedAction = nil
        visitedActions.removeAll()
        isRevisitingAction = false
        lastCommittedSwipeStepIndex = nil
        swipeStepDistance = nil
        swipeActivationDistance = nil
        firstCommitSwipeDistance = nil
        swipeMoveBackResetActive = false
        swipeActionResetActive = false
        lastCommittedMagnifyStepIndex = nil
        magnifyStepDistance = nil
        magnifyActivationDistance = nil
        firstCommitMagnifyDistance = nil
        magnifyMoveBackResetActive = false
        magnifyKind = nil
    }

    func begin(
        activationContext: MultitouchGestureActivationContext,
        gesture: GestureBinding,
        loopWasAlreadyOpen: Bool
    ) -> Bool {
        guard shouldAttemptBegin(with: gesture) else { return false }

        reset(endsStroke: false)
        self.activationContext = activationContext

        guard activationContext.allows(gesture) else {
            ineligibleGestureIDs.insert(gesture.id)
            isGestureRejected = true
            return false
        }

        guard activationContext.targetWindow != nil || loopWasAlreadyOpen else {
            reject()
            return false
        }

        pendingTargetWindow = activationContext.targetWindow
        resolvedGesture = gesture
        radialMenuGesture = gesture.kind == .radialMenu ? gesture : nil
        hasGestureBegun = true
        // Loop is already on screen, so no activation threshold to cross.
        hasActivated = loopWasAlreadyOpen
        return true
    }

    func shouldAttemptBegin(with gesture: GestureBinding) -> Bool {
        !isStrokeLocked && !ineligibleGestureIDs.contains(gesture.id)
    }

    func reject() {
        isGestureRejected = true
        isStrokeLocked = true
    }

    func abandonStroke() {
        reset(endsStroke: false)
        isStrokeLocked = true
    }

    func acquireGestureBlocker() {
        ownsGestureBlocker = true
    }

    func releaseGestureBlocker() -> Bool {
        guard ownsGestureBlocker else { return false }
        ownsGestureBlocker = false
        return true
    }

    func markActivated(openedLoop: Bool) {
        if openedLoop {
            didOpenLoopWithThisGesture = true
        }
        hasActivated = true
    }

    /// Tracks the fixed ring interval occupied by the swipe. Crossing a ring
    /// outward advances once; crossing that same ring inward reverses once.
    func commitSwipe(
        distance: CGFloat,
        newKey: ActionKey,
        step: CGFloat,
        fire: (_ reverse: Bool) -> ()
    ) {
        swipeStepDistance = step

        // `shouldSuppressSwipeAction` owns leaving the move-back zone. Until
        // the caller observes that exit, no action may recommit.
        if swipeMoveBackResetActive { return }

        if lastCommittedAction == newKey {
            guard let firstCommitSwipeDistance else { return }
            let newStepIndex = swipeStepIndex(
                for: distance,
                baseline: firstCommitSwipeDistance,
                step: step
            )
            let previousStepIndex = lastCommittedSwipeStepIndex ?? newStepIndex
            let crossedStepCount = newStepIndex - previousStepIndex
            guard crossedStepCount != 0 else { return }

            lastCommittedSwipeStepIndex = newStepIndex
            isRevisitingAction = false
            for _ in 0 ..< abs(crossedStepCount) {
                fire(crossedStepCount < 0)
            }
        } else {
            lastCommittedAction = newKey
            enterAction(newKey)
            let initialDistance = firstCommitSwipeDistance ?? swipeActivationDistance ?? distance
            if firstCommitSwipeDistance == nil {
                firstCommitSwipeDistance = initialDistance
            }
            lastCommittedSwipeStepIndex = swipeStepIndex(
                for: distance,
                baseline: initialDistance,
                step: step
            )
            swipeActionResetActive = false
            fire(false)
        }
    }

    private func enterAction(_ key: ActionKey) {
        isRevisitingAction = !visitedActions.insert(key).inserted
    }

    func setSwipeActivationDistance(_ distance: CGFloat?) {
        swipeActivationDistance = distance
    }

    func setMagnifyActivationDistance(_ distance: CGFloat?) {
        magnifyActivationDistance = distance
    }

    /// Clears the committed swipe action when the processed swipe returns to the
    /// move-back zone. The zone is the full first action's commit distance.
    func resetSwipeActionIfNeeded(distance: CGFloat) -> Bool {
        guard let firstCommitSwipeDistance,
              !swipeMoveBackResetActive,
              lastCommittedAction != nil,
              distance <= firstCommitSwipeDistance
        else {
            return false
        }

        lastCommittedAction = nil
        lastCommittedSwipeStepIndex = nil
        swipeMoveBackResetActive = true
        swipeActionResetActive = true
        return true
    }

    /// Clears the committed swipe action when the fingers move into an unbound direction.
    func clearSwipeAction() -> Bool {
        guard lastCommittedAction != nil else { return false }
        lastCommittedAction = nil
        lastCommittedSwipeStepIndex = nil
        swipeActionResetActive = true
        return true
    }

    /// Whether this swipe has been reset to no selection and should remain
    /// active while the fingers travel through an unbound direction
    var hasSwipeActionReset: Bool {
        swipeActionResetActive
    }

    var hasCommittedSwipeAction: Bool {
        lastCommittedAction != nil
    }

    var hasCommittedMagnifyAction: Bool {
        lastCommittedMagnifyStepIndex != nil
    }

    /// Drops a selected magnify action so a later spread or pinch can select one again.
    func clearMagnifyAction() -> Bool {
        guard lastCommittedMagnifyStepIndex != nil else { return false }
        lastCommittedAction = nil
        lastCommittedMagnifyStepIndex = nil
        magnifyMoveBackResetActive = true
        return true
    }

    /// Clears the committed magnify action when the gesture returns inside its
    /// activation ring
    func resetMagnifyActionIfNeeded(distance: CGFloat, originDistance: CGFloat) -> Bool {
        guard let magnifyActivationDistance,
              !magnifyMoveBackResetActive,
              lastCommittedMagnifyStepIndex != nil,
              abs(distance - originDistance) <= magnifyActivationDistance
        else {
            return false
        }

        lastCommittedAction = nil
        lastCommittedMagnifyStepIndex = nil
        magnifyMoveBackResetActive = true
        return true
    }

    func shouldSuppressMagnifyAction(distance: CGFloat, originDistance: CGFloat) -> Bool {
        guard magnifyMoveBackResetActive,
              let magnifyActivationDistance
        else {
            return false
        }

        if abs(distance - originDistance) <= magnifyActivationDistance {
            return true
        }
        magnifyMoveBackResetActive = false
        return false
    }

    func shouldSuppressSwipeAction(distance: CGFloat) -> Bool {
        guard swipeMoveBackResetActive,
              let firstCommitSwipeDistance
        else {
            return false
        }

        if distance <= firstCommitSwipeDistance {
            return true
        }
        swipeMoveBackResetActive = false
        return false
    }

    func commitRadialMagnify(
        distance: CGFloat,
        originDistance: CGFloat,
        step: CGFloat,
        fire: (_ reverse: Bool) -> ()
    ) {
        magnifyStepDistance = step

        if lastCommittedAction != .radialCenter {
            lastCommittedAction = .radialCenter
            enterAction(.radialCenter)
            firstCommitMagnifyDistance = distance
            lastCommittedMagnifyStepIndex = 0
            fire(distance < originDistance)
            return
        }

        let newStepIndex = signedMagnifyStepIndex(
            for: distance,
            baseline: firstCommitMagnifyDistance ?? distance,
            step: step
        )

        let previousStepIndex = lastCommittedMagnifyStepIndex ?? newStepIndex
        let crossedStepCount = newStepIndex - previousStepIndex
        guard crossedStepCount != 0 else { return }

        lastCommittedMagnifyStepIndex = newStepIndex
        isRevisitingAction = false
        for _ in 0 ..< abs(crossedStepCount) {
            fire(crossedStepCount < 0)
        }
    }

    func commitMagnify(
        gesture: GestureBinding,
        distance: CGFloat,
        step: CGFloat,
        allowsRapidRepeat: Bool,
        fire: (_ reverse: Bool) -> ()
    ) {
        let newKey = ActionKey.gesture(gesture.id)
        magnifyStepDistance = step

        if lastCommittedAction != newKey {
            magnifyKind = gesture.kind
            lastCommittedAction = newKey
            enterAction(newKey)
            firstCommitMagnifyDistance = distance
            lastCommittedMagnifyStepIndex = 0
            fire(false)
            return
        }

        guard allowsRapidRepeat else { return }

        let newStepIndex = directionalMagnifyStepIndex(
            for: distance,
            baseline: firstCommitMagnifyDistance ?? distance,
            kind: gesture.kind,
            step: step
        )

        let previousStepIndex = lastCommittedMagnifyStepIndex ?? newStepIndex
        let crossedStepCount = newStepIndex - previousStepIndex
        guard crossedStepCount != 0 else { return }

        lastCommittedMagnifyStepIndex = newStepIndex
        isRevisitingAction = false
        for _ in 0 ..< abs(crossedStepCount) {
            fire(crossedStepCount < 0)
        }
    }

    func canActivate(_ gesture: GestureBinding) -> Bool {
        hasGestureBegun &&
            !isGestureRejected &&
            activationContext?.allows(gesture) == true
    }

    /// Hands a radial menu stroke to a binding that overrides one of its directions
    func overrideRadialMenuGesture(with gesture: GestureBinding) -> Bool {
        guard resolvedGesture?.kind == .radialMenu, canActivate(gesture) else { return false }
        resolvedGesture = gesture
        return true
    }

    /// Hands an overridden stroke back to the radial menu it began as
    func restoreRadialMenuGesture() -> Bool {
        guard let radialMenuGesture else { return false }
        resolvedGesture = radialMenuGesture
        return true
    }

    func switchSwipeGesture(to gesture: GestureBinding, distance: CGFloat) -> Bool {
        guard canActivate(gesture) else { return false }
        resolvedGesture = gesture
        lastCommittedAction = .gesture(gesture.id)
        enterAction(.gesture(gesture.id))
        swipeActionResetActive = false
        let initialDistance = firstCommitSwipeDistance ?? swipeActivationDistance ?? distance
        if firstCommitSwipeDistance == nil {
            firstCommitSwipeDistance = initialDistance
        }
        if let swipeStepDistance {
            lastCommittedSwipeStepIndex = swipeStepIndex(
                for: distance,
                baseline: initialDistance,
                step: swipeStepDistance
            )
        } else {
            lastCommittedSwipeStepIndex = 0
        }
        return true
    }

    func switchMagnifyGesture(to gesture: GestureBinding, distance: CGFloat) -> Bool {
        guard canActivate(gesture) else { return false }
        resolvedGesture = gesture
        lastCommittedAction = .gesture(gesture.id)
        enterAction(.gesture(gesture.id))
        magnifyKind = gesture.kind
        firstCommitMagnifyDistance = distance
        lastCommittedMagnifyStepIndex = 0
        return true
    }

    func synchronizeSwipeStepIndex(distance: CGFloat) {
        guard let firstCommitSwipeDistance, let swipeStepDistance else { return }
        lastCommittedSwipeStepIndex = swipeStepIndex(
            for: distance,
            baseline: firstCommitSwipeDistance,
            step: swipeStepDistance
        )
    }

    func synchronizeMagnifyStepIndex(distance: CGFloat) {
        guard let firstCommitMagnifyDistance, let magnifyStepDistance, let magnifyKind else { return }
        lastCommittedMagnifyStepIndex = directionalMagnifyStepIndex(
            for: distance,
            baseline: firstCommitMagnifyDistance,
            kind: magnifyKind,
            step: magnifyStepDistance
        )
    }

    private func swipeStepIndex(for distance: CGFloat, baseline: CGFloat, step: CGFloat) -> Int {
        guard step > 0 else { return 0 }
        let normalizedDistance = (distance - baseline) / step
        return max(Int(floor(normalizedDistance + 0.000_001)), 0)
    }

    private func signedMagnifyStepIndex(
        for distance: CGFloat,
        baseline: CGFloat,
        step: CGFloat
    ) -> Int {
        guard step > 0 else { return 0 }
        let normalizedDistance = (distance - baseline) / step
        if normalizedDistance >= 0 {
            return Int(floor(normalizedDistance + 0.000_001))
        }
        return Int(ceil(normalizedDistance - 0.000_001))
    }

    private func directionalMagnifyStepIndex(
        for distance: CGFloat,
        baseline: CGFloat,
        kind: GestureBinding.Kind?,
        step: CGFloat
    ) -> Int {
        guard step > 0, let direction = kind?.magnifyDirection else { return 0 }
        let normalizedDistance = (distance - baseline) * direction / step
        return max(Int(floor(normalizedDistance + 0.000_001)), 0)
    }
}

private extension GestureBinding.Kind {
    var magnifyDirection: CGFloat? {
        switch self {
        case .magnifyOut:
            -1
        case .magnifyIn:
            1
        default:
            nil
        }
    }
}
