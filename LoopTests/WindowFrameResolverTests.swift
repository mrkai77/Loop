//
//  WindowFrameResolverTests.swift
//  Loop
//
//  Created by Kai Azim on 2026-11-14.
//

import AppKit
@testable import Loop
import Testing

@MainActor
struct WindowFrameResolverTests {
    private let bounds = CGRect(x: 100, y: 200, width: 800, height: 600)
    private var previewScreenSize: CGSize {
        (NSScreen.main ?? NSScreen.screens.first)?.frame.size ?? bounds.size
    }

    @Test func mixedUnitsResolveEachDimensionAndCoordinateIndependently() {
        let action = WindowAction(kind: .custom(.init(
            size: .custom(width: ScreenLength(25), height: ScreenLength(250, unit: .points)),
            position: .coordinates(x: ScreenLength(25, unit: .points), y: ScreenLength(10))
        )))
        let frame = WindowFrameResolver.getFrame(for: action, bounds: bounds, padding: .zero)
        #expect(frame.width == 200)
        #expect(frame.height == 250 / previewScreenSize.height * bounds.height)
        #expect(frame.minX == 25 / previewScreenSize.width * bounds.width)
        #expect(frame.minY == 260)
    }

    @Test func inverseMixedUnitsKeepPercentOriginsRelativeAndPointPreviewsAbsolute() {
        let action = WindowAction(kind: .custom(.init(
            size: .custom(width: ScreenLength(250, unit: .points), height: ScreenLength(25)),
            position: .coordinates(x: ScreenLength(10), y: ScreenLength(25, unit: .points))
        )))
        let frame = WindowFrameResolver.getFrame(for: action, bounds: bounds, padding: .zero)
        #expect(frame.width == 250 / previewScreenSize.width * bounds.width)
        #expect(frame.height == 150)
        #expect(frame.minX == 180)
        #expect(frame.minY == 25 / previewScreenSize.height * bounds.height)
    }

    @Test func preserveAndInitialPreviewsUseFallbackDimensionsForCustomAndStashActions() {
        for size in [ActionSize.preserve, .initial] {
            let fallback = ActionDimensions(width: ScreenLength(20), height: ScreenLength(250, unit: .points))
            for action in [
                WindowAction(kind: .custom(.init(size: size, position: .anchor(.topLeft), fallbackSize: fallback))),
                WindowAction(kind: .stash(.init(size: size, position: .anchor(.topLeft), fallbackSize: fallback)))
            ] {
                let frame = WindowFrameResolver.getFrame(for: action, bounds: bounds, padding: .zero)
                #expect(frame.origin == bounds.origin)
                #expect(frame.width == 160)
                #expect(frame.height == 250 / previewScreenSize.height * bounds.height)
            }
        }
    }

    @Test func nonFiniteBoundsResolveToAnEmptyFrame() {
        let nonFinite = CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 100)
        #expect(WindowFrameResolver.getFrame(for: WindowAction(.maximize), bounds: nonFinite).size == .zero)
    }

    @Test func omittedDimensionsRemainZeroAndPointCoordinateZerosIgnorePreviewBoundsOrigin() {
        let action = WindowAction(kind: .custom(.init(
            size: .custom(width: nil, height: nil),
            position: .coordinates(x: ScreenLength(0, unit: .points), y: ScreenLength(0, unit: .points))
        )))
        #expect(WindowFrameResolver.getFrame(for: action, bounds: bounds, padding: .zero) == .zero)
    }
}
