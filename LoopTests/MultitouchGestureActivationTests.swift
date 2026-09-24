//
//  MultitouchGestureActivationTests.swift
//  LoopTests
//
//  Created by Kai Azim on 2026-09-18.
//

import CoreGraphics
@testable import Loop
import Testing

@MainActor
struct MultitouchGestureActivationTests {
    @Test func effectiveActivationZoneForcesTwoFingerGesturesToTitlebar() {
        let twoFingerAnywhere = gesture(
            fingerCount: 2,
            kind: .swipeUp,
            activationZone: .anywhere
        )
        let threeFingerAnywhere = gesture(
            fingerCount: 3,
            kind: .swipeUp,
            activationZone: .anywhere
        )

        #expect(twoFingerAnywhere.effectiveActivationZone == .titlebar)
        #expect(threeFingerAnywhere.effectiveActivationZone == .anywhere)
    }

    @Test func outsideTitlebarContextRejectsTitlebarSwitches() {
        let session = MultitouchGestureSession()
        let maximize = gesture(kind: .swipeUp, activationZone: .anywhere)
        let leftHalf = gesture(kind: .swipeLeft, activationZone: .titlebar)
        let magnify = gesture(kind: .magnifyIn, activationZone: .titlebar)
        let context = MultitouchGestureActivationContext(
            targetWindow: nil,
            startedInTitlebar: false
        )

        #expect(session.begin(
            activationContext: context,
            gesture: maximize,
            loopWasAlreadyOpen: true
        ))
        #expect(!session.switchSwipeGesture(to: leftHalf, distance: 1))
        #expect(!session.switchMagnifyGesture(to: magnify, distance: 1))
        #expect(session.resolvedGesture?.id == maximize.id)
    }

    @Test func titlebarContextAllowsTitlebarSwitches() {
        let session = MultitouchGestureSession()
        let maximize = gesture(kind: .swipeUp, activationZone: .anywhere)
        let leftHalf = gesture(kind: .swipeLeft, activationZone: .titlebar)
        let context = MultitouchGestureActivationContext(
            targetWindow: nil,
            startedInTitlebar: true
        )

        #expect(session.begin(
            activationContext: context,
            gesture: maximize,
            loopWasAlreadyOpen: true
        ))
        #expect(session.switchSwipeGesture(to: leftHalf, distance: 1))
        #expect(session.resolvedGesture?.id == leftHalf.id)
    }

    @Test func openLoopDoesNotBypassInitialTitlebarRequirement() {
        let session = MultitouchGestureSession()
        let leftHalf = gesture(kind: .swipeLeft, activationZone: .titlebar)
        let context = MultitouchGestureActivationContext(
            targetWindow: nil,
            startedInTitlebar: false
        )

        #expect(!session.begin(
            activationContext: context,
            gesture: leftHalf,
            loopWasAlreadyOpen: true
        ))
        #expect(session.isGestureRejected)
        #expect(!session.hasGestureBegun)
    }

    @Test func rejectedDirectionalCandidateCanRetryWithAnywhereAction() {
        let session = MultitouchGestureSession()
        let titlebarOnly = gesture(kind: .swipeLeft, activationZone: .titlebar)
        let anywhere = gesture(kind: .swipeRight, activationZone: .anywhere)
        let context = MultitouchGestureActivationContext(
            targetWindow: nil,
            startedInTitlebar: false
        )

        #expect(!session.begin(
            activationContext: context,
            gesture: titlebarOnly,
            loopWasAlreadyOpen: true
        ))
        #expect(session.isGestureRejected)
        #expect(!session.shouldAttemptBegin(with: titlebarOnly))
        #expect(session.shouldAttemptBegin(with: anywhere))

        #expect(session.begin(
            activationContext: context,
            gesture: anywhere,
            loopWasAlreadyOpen: true
        ))
        #expect(!session.isGestureRejected)
        #expect(session.resolvedGesture?.id == anywhere.id)
    }

    @Test func activationContextIsOwnedAndResetPerSession() {
        let insideSession = MultitouchGestureSession()
        let outsideSession = MultitouchGestureSession()
        let anywhere = gesture(kind: .swipeUp, activationZone: .anywhere)
        let titlebar = gesture(kind: .swipeLeft, activationZone: .titlebar)

        #expect(insideSession.begin(
            activationContext: .init(targetWindow: nil, startedInTitlebar: true),
            gesture: anywhere,
            loopWasAlreadyOpen: true
        ))
        #expect(outsideSession.begin(
            activationContext: .init(targetWindow: nil, startedInTitlebar: false),
            gesture: anywhere,
            loopWasAlreadyOpen: true
        ))

        #expect(insideSession.canActivate(titlebar))
        #expect(!outsideSession.canActivate(titlebar))

        insideSession.reset()
        #expect(!insideSession.canActivate(anywhere))
        #expect(outsideSession.canActivate(anywhere))
    }

    @Test func fixedFrameActionsAreNotRapidRepeat() {
        #expect(!WindowAction(.leftHalf).allowsRapidRepeat)
        #expect(!WindowAction(.maximize).allowsRapidRepeat)
        #expect(WindowAction(.larger).allowsRapidRepeat)
    }

    @Test func swipeMoveBackZoneResetsAndSuppressesActionUntilLeavingZone() {
        let session = MultitouchGestureSession()
        var fireCount = 0
        let action = MultitouchGestureSession.ActionKey.radialSlot(0)
        session.setSwipeActivationDistance(0.08)

        session.commitSwipe(distance: 0.23, newKey: action, step: 0.15) { _ in
            fireCount += 1
        }
        #expect(fireCount == 1)
        #expect(session.resetSwipeActionIfNeeded(distance: 0.08))
        #expect(session.hasSwipeActionReset)

        session.commitSwipe(distance: 0.07, newKey: action, step: 0.15) { _ in
            fireCount += 1
        }
        #expect(fireCount == 1)
        #expect(session.shouldSuppressSwipeAction(distance: 0.07))
        #expect(!session.shouldSuppressSwipeAction(distance: 0.1))

        session.commitSwipe(distance: 0.24, newKey: action, step: 0.15) { _ in
            fireCount += 1
        }
        #expect(fireCount == 2)
        #expect(!session.hasSwipeActionReset)
    }

    @Test func swipeCycleReversesWhenTheSameStepBoundaryIsUncrossed() {
        let session = MultitouchGestureSession()
        var directions: [Bool] = []
        let action = MultitouchGestureSession.ActionKey.radialSlot(0)
        session.setSwipeActivationDistance(0.08)

        session.commitSwipe(distance: 0.08, newKey: action, step: 0.15) {
            directions.append($0)
        }
        session.commitSwipe(distance: 0.231, newKey: action, step: 0.15) {
            directions.append($0)
        }
        session.commitSwipe(distance: 0.229, newKey: action, step: 0.15) {
            directions.append($0)
        }

        #expect(directions == [false, false, true])
    }

    @Test func swipeCycleFiresOnceForEveryCrossedStepInEitherDirection() {
        let session = MultitouchGestureSession()
        var directions: [Bool] = []
        let action = MultitouchGestureSession.ActionKey.radialSlot(0)
        session.setSwipeActivationDistance(0.08)

        session.commitSwipe(distance: 0.08, newKey: action, step: 0.15) {
            directions.append($0)
        }
        session.commitSwipe(distance: 0.39, newKey: action, step: 0.15) {
            directions.append($0)
        }
        session.commitSwipe(distance: 0.22, newKey: action, step: 0.15) {
            directions.append($0)
        }

        #expect(directions == [false, false, false, true, true])
    }

    @Test func magnifyCycleReversesOuterBoundaryAndResetsInsideActivationRing() {
        let session = MultitouchGestureSession()
        var directions: [Bool] = []
        let action = gesture(kind: .magnifyOut, activationZone: .anywhere)

        session.commitMagnify(
            gesture: action,
            distance: 0.7,
            originDistance: 0.5,
            step: 0.2,
            allowsRapidRepeat: true
        ) {
            directions.append($0)
        }
        session.commitMagnify(
            gesture: action,
            distance: 0.901,
            originDistance: 0.5,
            step: 0.2,
            allowsRapidRepeat: true
        ) {
            directions.append($0)
        }
        session.commitMagnify(
            gesture: action,
            distance: 0.899,
            originDistance: 0.5,
            step: 0.2,
            allowsRapidRepeat: true
        ) {
            directions.append($0)
        }
        let didReset = session.resetMagnifyActionIfNeeded(
            distance: 0.699,
            originDistance: 0.5,
            step: 0.2
        )

        #expect(didReset)
        #expect(!session.hasCommittedMagnifyAction)
        #expect(directions == [false, false, true])
        #expect(session.resetMagnifyActionIfNeeded(distance: 0.6, originDistance: 0.5, step: 0.2))
        #expect(!session.resetMagnifyActionIfNeeded(distance: 0.701, originDistance: 0.5, step: 0.2))

        session.commitMagnify(
            gesture: action,
            distance: 0.701,
            originDistance: 0.5,
            step: 0.2,
            allowsRapidRepeat: true
        ) {
            directions.append($0)
        }
        #expect(directions == [false, false, true, false])
    }

    @Test func radialMagnifyFiresOnceForEveryCrossedStepInEitherDirection() {
        let session = MultitouchGestureSession()
        var directions: [Bool] = []

        session.commitRadialMagnify(distance: 0.7, originDistance: 0.5, step: 0.2) {
            directions.append($0)
        }
        session.commitRadialMagnify(distance: 1.101, originDistance: 0.5, step: 0.2) {
            directions.append($0)
        }
        session.commitRadialMagnify(distance: 0.899, originDistance: 0.5, step: 0.2) {
            directions.append($0)
        }
        let didReset = session.resetMagnifyActionIfNeeded(
            distance: 0.699,
            originDistance: 0.5,
            step: 0.2
        )

        #expect(didReset)
        #expect(!session.hasCommittedMagnifyAction)
        #expect(directions == [false, false, false, true, true])
    }

    private func gesture(
        fingerCount: Int = 3,
        kind: GestureBinding.Kind,
        activationZone: GestureBinding.ActivationZone
    ) -> GestureBinding {
        GestureBinding(
            fingerCount: fingerCount,
            kind: kind,
            action: .singleAction(.custom(.init(.maximize))),
            activationZone: activationZone
        )
    }
}
