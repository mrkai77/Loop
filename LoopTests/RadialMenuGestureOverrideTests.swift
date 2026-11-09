//
//  RadialMenuGestureOverrideTests.swift
//  LoopTests
//
//  Created by Kai Azim on 2026-10-17.
//

@testable import Loop
import Testing

@MainActor
struct RadialMenuGestureOverrideTests {
    @Test func swipesAndMagnifiesOverrideRadialMenuInsteadOfConflicting() {
        let radial = gesture(kind: .radialMenu)
        let swipeUp = gesture(kind: .swipeUp)
        let pinch = gesture(kind: .magnifyOut)
        let otherFingerCount = gesture(fingerCount: 4, kind: .swipeLeft)
        let gestures = [radial, swipeUp, pinch, otherFingerCount]

        #expect(GestureBinding.conflictingIDs(in: gestures).isEmpty)
        #expect(GestureBinding.radialMenuOverrideIDs(in: gestures) == [swipeUp.id, pinch.id])
    }

    @Test func sameKindStillConflicts() {
        let radial = gesture(kind: .radialMenu)
        let firstSwipeUp = gesture(kind: .swipeUp)
        // No Action is a deliberate binding, so it conflicts like any other
        let secondSwipeUp = gesture(kind: .swipeUp, action: .noAction)
        let gestures = [radial, firstSwipeUp, secondSwipeUp]

        #expect(GestureBinding.conflictingIDs(in: gestures) == [firstSwipeUp.id, secondSwipeUp.id])
        // Disabled bindings can't override anything
        #expect(GestureBinding.radialMenuOverrideIDs(in: gestures).isEmpty)
    }

    @Test func unsetGesturesAreInactiveAndNeverConflict() {
        let radial = gesture(kind: .radialMenu)
        let firstUnset = gesture(kind: nil)
        let secondUnset = gesture(kind: nil)
        let gestures = [radial, firstUnset, secondUnset]

        #expect(GestureBinding.conflictingIDs(in: gestures).isEmpty)
        #expect(GestureBinding.activeGestures(in: gestures).map(\.id) == [radial.id])
        #expect(GestureBinding.radialMenuOverrideIDs(in: gestures).isEmpty)
    }

    @Test func sessionHandsRadialStrokeToAllowedOverride() {
        let session = MultitouchGestureSession()
        let radial = gesture(kind: .radialMenu, activationZone: .anywhere)
        let titlebarPinch = gesture(kind: .magnifyOut, activationZone: .titlebar)
        let pinch = gesture(kind: .magnifyOut, activationZone: .anywhere)
        let context = MultitouchGestureActivationContext(targetWindow: nil, startedInTitlebar: false)

        #expect(session.begin(activationContext: context, gesture: radial, loopWasAlreadyOpen: true))
        #expect(!session.overrideRadialMenuGesture(with: titlebarPinch))
        #expect(session.overrideRadialMenuGesture(with: pinch))
        #expect(session.resolvedGesture?.id == pinch.id)
    }

    @Test func nonRadialStrokeCannotBeOverridden() {
        let session = MultitouchGestureSession()
        let swipeUp = gesture(kind: .swipeUp, activationZone: .anywhere)
        let pinch = gesture(kind: .magnifyOut, activationZone: .anywhere)
        let context = MultitouchGestureActivationContext(targetWindow: nil, startedInTitlebar: true)

        #expect(session.begin(activationContext: context, gesture: swipeUp, loopWasAlreadyOpen: true))
        #expect(!session.overrideRadialMenuGesture(with: pinch))
        #expect(session.resolvedGesture?.id == swipeUp.id)
    }

    private func gesture(
        fingerCount: Int = 3,
        kind: GestureBinding.Kind?,
        action: WindowDirection = .maximize,
        activationZone: GestureBinding.ActivationZone = .anywhere
    ) -> GestureBinding {
        GestureBinding(
            fingerCount: fingerCount,
            kind: kind,
            action: kind == .radialMenu ? .radialMenuActions : .singleAction(.custom(.init(action))),
            activationZone: activationZone
        )
    }
}
