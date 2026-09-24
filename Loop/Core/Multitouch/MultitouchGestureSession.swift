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
    private(set) var pendingTargetWindow: Window?
    private var activationContext: MultitouchGestureActivationContext?
    private var rejectedGestureID: UUID?

    private var lastCommittedAction: ActionKey?
    private var lastCommittedSwipeStepIndex: Int?
    private var swipeStepDistance: CGFloat?
    private var swipeActivationDistance: CGFloat?
    private var firstCommitSwipeDistance: CGFloat?
    private var swipeMoveBackResetActive = false
    private var swipeActionResetActive = false
    private var lastCommittedMagnifyStepIndex: Int?
    private var magnifyOriginDistance: CGFloat?
    private var magnifyStepDistance: CGFloat?
    private var magnificationKind: GestureBinding.Kind?
    private var magnifyActionResetActive = false

    func reset(clearRejectedGesture: Bool = true) {
        didOpenLoopWithThisGesture = false
        isGestureRejected = false
        hasActivated = false
        hasGestureBegun = false
        ownsGestureBlocker = false
        resolvedGesture = nil
        pendingTargetWindow = nil
        activationContext = nil
        if clearRejectedGesture {
            rejectedGestureID = nil
        }
        lastCommittedAction = nil
        lastCommittedSwipeStepIndex = nil
        swipeStepDistance = nil
        swipeActivationDistance = nil
        firstCommitSwipeDistance = nil
        swipeMoveBackResetActive = false
        swipeActionResetActive = false
        lastCommittedMagnifyStepIndex = nil
        magnifyOriginDistance = nil
        magnifyStepDistance = nil
        magnificationKind = nil
        magnifyActionResetActive = false
    }

    func begin(
        activationContext: MultitouchGestureActivationContext,
        gesture: GestureBinding,
        loopWasAlreadyOpen: Bool
    ) -> Bool {
        // Do not retry the same rejected candidate on every changed event.
        // A different directional binding can still retry within this stroke.
        guard rejectedGestureID != gesture.id else { return false }

        reset(clearRejectedGesture: false)
        self.activationContext = activationContext

        let activationAllowed = activationContext.allows(gesture)
        let hasTarget = activationContext.targetWindow != nil || loopWasAlreadyOpen
        guard activationAllowed, hasTarget
        else {
            rejectedGestureID = gesture.id
            reject()
            return false
        }

        pendingTargetWindow = activationContext.targetWindow
        rejectedGestureID = nil
        resolvedGesture = gesture
        hasGestureBegun = true
        // Loop is already on screen, so no activation threshold to cross.
        hasActivated = loopWasAlreadyOpen
        return true
    }

    func shouldAttemptBegin(with gesture: GestureBinding) -> Bool {
        rejectedGestureID != gesture.id
    }

    func reject() {
        isGestureRejected = true
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
    /// Activation is gated upstream by `activateGestureIfNeeded`, so the first
    /// commit still fires immediately to seed Loop's initial active action :)
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
            for _ in 0..<abs(crossedStepCount) {
                fire(crossedStepCount < 0)
            }
        } else {
            lastCommittedAction = newKey
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

    func setSwipeActivationDistance(_ distance: CGFloat?) {
        swipeActivationDistance = distance
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

    /// Whether this swipe has been reset to no selection and should remain
    /// active while the fingers travel through an unbound direction
    var hasSwipeActionReset: Bool {
        swipeActionResetActive
    }

    var hasCommittedMagnifyAction: Bool {
        lastCommittedMagnifyStepIndex != nil
    }

    /// Clears the committed magnify action when the gesture returns inside its
    /// activation ring
    func resetMagnifyActionIfNeeded(
        distance: CGFloat,
        originDistance: CGFloat,
        step: CGFloat
    ) -> Bool {
        guard abs(distance - originDistance) <= step else {
            magnifyActionResetActive = false
            return false
        }

        guard !magnifyActionResetActive,
              lastCommittedMagnifyStepIndex != nil
        else {
            return magnifyActionResetActive
        }

        lastCommittedAction = nil
        lastCommittedMagnifyStepIndex = nil
        magnifyActionResetActive = true
        return true
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
        magnifyOriginDistance = originDistance
        magnifyStepDistance = step
        let newStepIndex = signedMagnifyStepIndex(
            for: distance,
            originDistance: originDistance,
            step: step
        )

        if lastCommittedAction != .radialCenter {
            lastCommittedAction = .radialCenter
            lastCommittedMagnifyStepIndex = newStepIndex
            fire(distance < originDistance)
            return
        }

        let previousStepIndex = lastCommittedMagnifyStepIndex ?? newStepIndex
        let crossedStepCount = newStepIndex - previousStepIndex
        guard crossedStepCount != 0 else { return }

        lastCommittedMagnifyStepIndex = newStepIndex
        for _ in 0..<abs(crossedStepCount) {
            fire(crossedStepCount < 0)
        }
    }

    func commitMagnify(
        gesture: GestureBinding,
        distance: CGFloat,
        originDistance: CGFloat,
        step: CGFloat,
        allowsRapidRepeat: Bool,
        fire: (_ reverse: Bool) -> ()
    ) {
        let newKey = ActionKey.gesture(gesture.id)
        magnifyOriginDistance = originDistance
        magnifyStepDistance = step
        let newStepIndex = directionalMagnifyStepIndex(
            for: distance,
            originDistance: originDistance,
            kind: gesture.kind,
            step: step
        )

        if lastCommittedAction != newKey {
            magnificationKind = gesture.kind
            lastCommittedAction = newKey
            lastCommittedMagnifyStepIndex = newStepIndex
            fire(false)
            return
        }

        guard allowsRapidRepeat else { return }

        let previousStepIndex = lastCommittedMagnifyStepIndex ?? newStepIndex
        let crossedStepCount = newStepIndex - previousStepIndex
        guard crossedStepCount != 0 else { return }

        lastCommittedMagnifyStepIndex = newStepIndex
        for _ in 0..<abs(crossedStepCount) {
            fire(crossedStepCount < 0)
        }
    }

    func canActivate(_ gesture: GestureBinding) -> Bool {
        hasGestureBegun &&
            !isGestureRejected &&
            activationContext?.allows(gesture) == true
    }

    func switchSwipeGesture(to gesture: GestureBinding, distance: CGFloat) -> Bool {
        guard canActivate(gesture) else { return false }
        resolvedGesture = gesture
        lastCommittedAction = .gesture(gesture.id)
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
        magnificationKind = gesture.kind
        if let magnifyOriginDistance, let magnifyStepDistance {
            lastCommittedMagnifyStepIndex = directionalMagnifyStepIndex(
                for: distance,
                originDistance: magnifyOriginDistance,
                kind: gesture.kind,
                step: magnifyStepDistance
            )
        } else {
            lastCommittedMagnifyStepIndex = 0
        }
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

    func synchronizeMagnifyStepIndex(distance: CGFloat, step: CGFloat) {
        guard let magnifyOriginDistance, let magnificationKind else { return }
        lastCommittedMagnifyStepIndex = directionalMagnifyStepIndex(
            for: distance,
            originDistance: magnifyOriginDistance,
            kind: magnificationKind,
            step: step
        )
    }

    private func swipeStepIndex(for distance: CGFloat, baseline: CGFloat, step: CGFloat) -> Int {
        guard step > 0 else { return 0 }
        let normalizedDistance = (distance - baseline) / step
        return max(Int(floor(normalizedDistance + 0.000_001)), 0)
    }

    private func signedMagnifyStepIndex(
        for distance: CGFloat,
        originDistance: CGFloat,
        step: CGFloat
    ) -> Int {
        guard step > 0 else { return 0 }
        let normalizedDistance = (distance - originDistance) / step
        if normalizedDistance >= 0 {
            return Int(floor(normalizedDistance + 0.000_001))
        }
        return Int(ceil(normalizedDistance - 0.000_001))
    }

    private func directionalMagnifyStepIndex(
        for distance: CGFloat,
        originDistance: CGFloat,
        kind: GestureBinding.Kind,
        step: CGFloat
    ) -> Int {
        guard step > 0, let direction = kind.magnificationDirection else { return 0 }
        let normalizedDistance = (distance - originDistance) * direction / step
        return max(Int(floor(normalizedDistance + 0.000_001)), 0)
    }
}

private extension GestureBinding.Kind {
    var magnificationDirection: CGFloat? {
        switch self {
        case .magnifyIn:
            -1
        case .magnifyOut:
            1
        default:
            nil
        }
    }
}
