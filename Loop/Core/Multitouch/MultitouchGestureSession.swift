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

    private var lastCommittedAction: ActionKey?
    private var lastCommitSwipeDistance: CGFloat = 0
    private var lastCommitMagnifyDistance: CGFloat = 0
    private var magnificationKind: GestureBinding.Kind?

    func reset() {
        didOpenLoopWithThisGesture = false
        isGestureRejected = false
        hasActivated = false
        hasGestureBegun = false
        ownsGestureBlocker = false
        resolvedGesture = nil
        pendingTargetWindow = nil
        activationContext = nil
        lastCommittedAction = nil
        lastCommitSwipeDistance = 0
        lastCommitMagnifyDistance = 0
        magnificationKind = nil
    }

    func begin(
        activationContext: MultitouchGestureActivationContext,
        gesture: GestureBinding,
        loopWasAlreadyOpen: Bool
    ) -> Bool {
        reset()
        self.activationContext = activationContext

        guard activationContext.allows(gesture),
              activationContext.targetWindow != nil || loopWasAlreadyOpen
        else {
            reject()
            return false
        }

        pendingTargetWindow = activationContext.targetWindow
        resolvedGesture = gesture
        hasGestureBegun = true
        // Loop is already on screen, so no activation threshold to cross.
        hasActivated = loopWasAlreadyOpen
        return true
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

    /// Commit distance only advances when an action fires, so sub-step
    /// jitter can't drift it past the reverse threshold. Activation is gated
    /// upstream by `activateGestureIfNeeded`, so the first commit fires
    /// immediately to seed Loop's initial active action :)
    func commitSwipe(
        distance: CGFloat,
        newKey: ActionKey,
        step: CGFloat,
        fire: (_ reverse: Bool) -> ()
    ) {
        if lastCommittedAction == newKey {
            let delta = distance - lastCommitSwipeDistance
            if delta >= step {
                lastCommitSwipeDistance = distance
                fire(false)
            } else if delta <= -step {
                lastCommitSwipeDistance = distance
                fire(true)
            }
        } else {
            lastCommittedAction = newKey
            lastCommitSwipeDistance = distance
            fire(false)
        }
    }

    func commitRadialMagnify(
        distance: CGFloat,
        originDistance: CGFloat,
        step: CGFloat,
        fire: (_ reverse: Bool) -> ()
    ) {
        if lastCommittedAction != .radialCenter {
            lastCommittedAction = .radialCenter
            lastCommitMagnifyDistance = distance
            fire(distance < originDistance)
            return
        }

        let delta = distance - lastCommitMagnifyDistance
        if delta >= step {
            lastCommitMagnifyDistance = distance
            fire(false)
        } else if delta <= -step {
            lastCommitMagnifyDistance = distance
            fire(true)
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

        if lastCommittedAction != newKey {
            magnificationKind = gesture.kind
            lastCommittedAction = newKey
            lastCommitMagnifyDistance = distance
            fire(false)
            return
        }

        guard allowsRapidRepeat,
              let magnificationDirection = magnificationKind?.magnificationDirection
        else {
            return
        }

        let delta = (distance - lastCommitMagnifyDistance) * magnificationDirection
        if delta >= step {
            lastCommitMagnifyDistance = distance
            fire(false)
        } else if delta <= -step {
            lastCommitMagnifyDistance = distance
            fire(true)
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
        lastCommitSwipeDistance = distance
        return true
    }

    func switchMagnifyGesture(to gesture: GestureBinding, distance: CGFloat) -> Bool {
        guard canActivate(gesture) else { return false }
        resolvedGesture = gesture
        lastCommittedAction = .gesture(gesture.id)
        magnificationKind = gesture.kind
        lastCommitMagnifyDistance = distance
        return true
    }

    func updateLastCommitSwipeDistance(_ distance: CGFloat) {
        lastCommitSwipeDistance = distance
    }

    func updateLastCommitMagnifyDistance(_ distance: CGFloat) {
        lastCommitMagnifyDistance = distance
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
