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
