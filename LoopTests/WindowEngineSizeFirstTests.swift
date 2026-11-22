//
//  WindowEngineSizeFirstTests.swift
//  LoopTests
//

import CoreGraphics
@testable import Loop
import Testing

struct WindowEngineSizeFirstTests {
    private let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    private func sizesFirst(from current: CGRect, to target: CGRect) -> Bool {
        WindowEngine.shouldSizeFirst(from: current, to: target, within: screen, willChangeScreens: false)
    }

    @Test func shrinkingTowardTheFarEdgeSizesFirst() {
        // Moving first would slide the full-width window 1280 points off the right edge
        #expect(sizesFirst(
            from: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            to: CGRect(x: 1280, y: 0, width: 640, height: 1080)
        ))
    }

    @Test func growingFromTheFarEdgeMovesFirst() {
        // Sizing first would grow the right third 1280 points off the right edge
        #expect(!sizesFirst(
            from: CGRect(x: 1280, y: 0, width: 640, height: 1080),
            to: CGRect(x: 0, y: 0, width: 1920, height: 1080)
        ))
    }

    @Test func mixedResizePicksTheOrderThatSticksOutLess() {
        // Sizing first hangs 600 points off the bottom, moving first 1080 points off the right
        #expect(sizesFirst(
            from: CGRect(x: 0, y: 600, width: 1900, height: 400),
            to: CGRect(x: 1100, y: 0, width: 800, height: 1080)
        ))
    }

    @Test func eitherOrderOnScreenSizesFirst() {
        #expect(sizesFirst(
            from: CGRect(x: 0, y: 0, width: 640, height: 1080),
            to: CGRect(x: 960, y: 0, width: 960, height: 1080)
        ))
    }

    @Test func partlyOffScreenWindowSizesFirst() {
        #expect(sizesFirst(
            from: CGRect(x: 1500, y: 0, width: 960, height: 1080),
            to: CGRect(x: 0, y: 0, width: 1920, height: 1080)
        ))
    }

    @Test func largerAcceptedSizeStaysAnchoredToTheTargetEdge() {
        // A window with an 800-point minimum width snapped to the right third keeps its right edge on the screen's
        let target = CGRect(x: 1280, y: 0, width: 640, height: 1080)
        let origin = WindowEngine.origin(afterAccepting: CGSize(width: 800, height: 1080), for: target, within: screen)
        #expect(origin == CGPoint(x: 1120, y: 0))
    }

    @Test func smallerAcceptedSizeIsPlacedAtTheTargetSize() {
        // May only be the old position clamping it, so it's corrected after the move instead
        let target = CGRect(x: 1280, y: 0, width: 640, height: 1080)
        let origin = WindowEngine.origin(afterAccepting: CGSize(width: 640, height: 500), for: target, within: screen)
        #expect(origin == target.origin)
    }
}
