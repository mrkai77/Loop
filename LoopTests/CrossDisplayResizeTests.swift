//
//  CrossDisplayResizeTests.swift
//  LoopTests
//

import CoreGraphics
@testable import Loop
import Testing

struct CrossDisplayResizeTests {
    /// A 13-inch display, the source in the cross-display maximize report.
    private let laptopDisplay = CGRect(x: 0, y: 0, width: 1470, height: 956)

    /// The frame Maximize requested on the vertical display.
    private let verticalTarget = CGRect(x: -1074, y: -370, width: 1068, height: 1878)

    /// What Accessibility read back after the first, clamped Maximize.
    private let clampedReadBack = CGRect(x: -1074, y: -156, width: 1068, height: 1450)

    // MARK: Move before sizing

    @Test func aTallerTargetOnAnotherDisplayMovesBeforeSizing() {
        #expect(WindowEngine.shouldMoveBeforeSizing(
            willChangeScreens: true,
            targetSize: verticalTarget.size,
            sourceDisplayBounds: laptopDisplay
        ))
    }

    @Test func aTargetThatFitsTheSourceDisplaySizesFirst() {
        #expect(!WindowEngine.shouldMoveBeforeSizing(
            willChangeScreens: true,
            targetSize: CGSize(width: 1068, height: 900),
            sourceDisplayBounds: laptopDisplay
        ))

        // Maximizing onto a display of the same resolution does not exceed it.
        #expect(!WindowEngine.shouldMoveBeforeSizing(
            willChangeScreens: true,
            targetSize: laptopDisplay.size,
            sourceDisplayBounds: laptopDisplay
        ))
    }

    @Test func stayingOnOneScreenSizesFirstEvenWhenTheTargetIsLarger() {
        #expect(!WindowEngine.shouldMoveBeforeSizing(
            willChangeScreens: false,
            targetSize: verticalTarget.size,
            sourceDisplayBounds: laptopDisplay
        ))
    }

    @Test func aMissingSourceDisplaySizesFirst() {
        #expect(!WindowEngine.shouldMoveBeforeSizing(
            willChangeScreens: true,
            targetSize: verticalTarget.size,
            sourceDisplayBounds: nil
        ))
    }

    // MARK: Reapply

    @Test func aClampedCrossDisplayReadBackIsReapplied() {
        #expect(WindowEngine.shouldReapplyFrame(
            actual: clampedReadBack,
            target: verticalTarget,
            appliesSoFar: 1,
            maxApplies: 20
        ))
    }

    @Test func aFrameWithinToleranceIsNotReapplied() {
        let withinTolerance = CGRect(
            x: verticalTarget.origin.x,
            y: verticalTarget.origin.y + 9,
            width: verticalTarget.width,
            height: verticalTarget.height
        )

        #expect(!WindowEngine.shouldReapplyFrame(
            actual: withinTolerance,
            target: verticalTarget,
            appliesSoFar: 1,
            maxApplies: 20
        ))
    }

    @Test func aSpentApplyBudgetIsNotReapplied() {
        #expect(!WindowEngine.shouldReapplyFrame(
            actual: clampedReadBack,
            target: verticalTarget,
            appliesSoFar: 20,
            maxApplies: 20
        ))

        // Same-screen resizes keep the one-shot retry: the apply just made, plus one more.
        #expect(WindowEngine.shouldReapplyFrame(
            actual: clampedReadBack,
            target: verticalTarget,
            appliesSoFar: 1,
            maxApplies: 2
        ))
        #expect(!WindowEngine.shouldReapplyFrame(
            actual: clampedReadBack,
            target: verticalTarget,
            appliesSoFar: 2,
            maxApplies: 2
        ))
    }
}
