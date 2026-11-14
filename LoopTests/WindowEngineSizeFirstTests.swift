//
//  WindowEngineSizeFirstTests.swift
//  LoopTests
//

import CoreGraphics
@testable import Loop
import Testing

struct WindowEngineSizeFirstTests {
    @Test func sameScreenShrinkSizesFirst() {
        #expect(
            WindowEngine.shouldSizeFirst(
                to: CGSize(width: 640, height: 900),
                from: CGSize(width: 1920, height: 900)
            )
        )
        #expect(
            WindowEngine.shouldSizeFirst(
                to: CGSize(width: 1920, height: 400),
                from: CGSize(width: 1920, height: 900)
            )
        )
    }

    @Test func shrinkingEitherAxisSizesFirst() {
        #expect(
            WindowEngine.shouldSizeFirst(
                to: CGSize(width: 800, height: 1000),
                from: CGSize(width: 1000, height: 500)
            )
        )
    }

    @Test func sameScreenGrowthMovesFirst() {
        #expect(
            !WindowEngine.shouldSizeFirst(
                to: CGSize(width: 1920, height: 900),
                from: CGSize(width: 640, height: 900)
            )
        )
        #expect(
            !WindowEngine.shouldSizeFirst(
                to: CGSize(width: 1280, height: 900),
                from: CGSize(width: 640, height: 400)
            )
        )
    }

    @Test func equalSizeMovesFirst() {
        let size = CGSize(width: 800, height: 600)
        #expect(!WindowEngine.shouldSizeFirst(to: size, from: size))
    }

    @Test func screenChangeSizesFirstEvenWhenGrowingOrUnchanged() {
        #expect(
            WindowEngine.shouldSizeFirst(
                to: CGSize(width: 1920, height: 1080),
                from: CGSize(width: 640, height: 400),
                willChangeScreens: true
            )
        )
        let size = CGSize(width: 800, height: 600)
        #expect(WindowEngine.shouldSizeFirst(to: size, from: size, willChangeScreens: true))
    }

    @Test func pureShrinkUsesTheTargetSizeBeforeMoving() {
        let size = WindowEngine.sizeBeforeMove(
            target: CGSize(width: 640, height: 400),
            current: CGSize(width: 1920, height: 900),
            sizeFirst: false
        )
        #expect(size == CGSize(width: 640, height: 400))
    }

    @Test func mixedResizeShrinksInPlaceAndDefersGrowth() {
        let size = WindowEngine.sizeBeforeMove(
            target: CGSize(width: 800, height: 1000),
            current: CGSize(width: 1000, height: 500),
            sizeFirst: false
        )
        #expect(size == CGSize(width: 800, height: 500))
    }

    @Test func screenChangeGrowthUsesTheFullTargetSize() {
        let size = WindowEngine.sizeBeforeMove(
            target: CGSize(width: 1920, height: 1080),
            current: CGSize(width: 640, height: 400),
            sizeFirst: true
        )
        #expect(size == CGSize(width: 1920, height: 1080))
    }

    @Test func sameScreenGrowthDoesNotSizeBeforeMoving() {
        let size = WindowEngine.sizeBeforeMove(
            target: CGSize(width: 1280, height: 900),
            current: CGSize(width: 640, height: 400),
            sizeFirst: false
        )
        #expect(size == nil)
    }
}
