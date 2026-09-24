//
//  SystemGestureFilterTests.swift
//  LoopTests
//
//  Created by Kai Azim on 2026-09-24.
//

@testable import Loop
import Testing

struct SystemGestureFilterTests {
    @Test func claimsFollowEachBindingsFingerCountAndActivationZone() {
        let claims = SystemGestureFilter.claims(for: [
            gesture(fingerCount: 3, kind: .swipeRight, activationZone: .anywhere),
            gesture(fingerCount: 3, kind: .swipeLeft, activationZone: .titlebar),
            gesture(fingerCount: 4, kind: .radialMenu, activationZone: .anywhere),
            // Two-finger gestures are always titlebar-only
            gesture(fingerCount: 2, kind: .magnifyOut, activationZone: .anywhere),
            // Conflicting bindings are inactive, so they claim nothing
            gesture(fingerCount: 3, kind: .magnifyIn, activationZone: .anywhere),
            gesture(fingerCount: 3, kind: .magnifyIn, activationZone: .anywhere)
        ])

        #expect(claims[3]?.anywhere == [.swipeRight])
        #expect(claims[3]?.titlebarOnly == [.swipeLeft])
        #expect(claims[4]?.anywhere == Set(SystemGestureFilter.DockGesture.allCases))
        #expect(claims[2]?.anywhere == [])
        #expect(claims[2]?.titlebarOnly == [.pinch])
    }

    private func gesture(
        fingerCount: Int,
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
