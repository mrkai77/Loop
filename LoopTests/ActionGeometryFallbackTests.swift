//
//  ActionGeometryFallbackTests.swift
//  Loop
//
//  Created by Kai Azim on 2026-11-14.
//

import CoreGraphics
import Foundation
@testable import Loop
import Testing

struct ActionGeometryFallbackTests {
    @Test func editorPrecisionDependsOnEachLengthUnit() {
        let percent = ScreenLength(25.6789)
        let points = ScreenLength(250.6789, unit: .points)
        #expect(percent.roundedToDisplayPrecision() == ScreenLength(25.68))
        #expect(points.roundedToDisplayPrecision() == ScreenLength(250.7, unit: .points))
        #expect(percent.value == 25.6789)
        #expect(points.value == 250.6789)
    }

    @Test func customAndStashEditorsRetainDimensionsAcrossSizeModes() {
        for direction in [WindowDirection.custom, .stash] {
            var action = WindowAction(direction)
            let identity = action.id
            let dimensions = ActionDimensions(width: ScreenLength(25), height: ScreenLength(250, unit: .points))
            action.customDimensions = dimensions
            action.size = .preserve
            #expect(action.customDimensions == dimensions)
            action.size = .initial
            #expect(action.customDimensions == dimensions)
            action.size = .custom(width: dimensions.width, height: dimensions.height)
            #expect(action.size == .custom(width: dimensions.width, height: dimensions.height))
            #expect(action.id == identity)
            switch action.kind {
            case let .custom(payload): #expect(payload.fallbackSize == .init())
            case let .stash(payload): #expect(payload.fallbackSize == .init())
            default: Issue.record("Expected frame payload")
            }
        }
    }

    @Test func dormantDimensionsCanBeEditedAndRoundTripInNoncustomModes() throws {
        for mode in [ActionSize.preserve, .initial] {
            var action = WindowAction(kind: .custom(.init(size: mode)))
            action.customDimensions = .init(width: ScreenLength(33, unit: .points), height: nil)
            var dimensions = action.customDimensions ?? .init()
            dimensions.height = ScreenLength(60)
            action.customDimensions = dimensions
            #expect(action.customDimensions == .init(width: ScreenLength(33, unit: .points), height: ScreenLength(60)))
            let decoded = try JSONDecoder().decode(WindowAction.self, from: JSONEncoder().encode(action))
            #expect(decoded == action)
            #expect(decoded.size == mode)
            #expect(decoded.customDimensions == action.customDimensions)
        }
    }

    @Test func activeCustomPayloadsCannotAccumulateUnserializedDormantDimensions() {
        let fallback = ActionDimensions(width: ScreenLength(20), height: ScreenLength(30))
        var frame = FrameAction(fallbackSize: fallback)
        var stash = FrameAction(position: .anchor(.topLeft), fallbackSize: fallback)
        #expect(frame.fallbackSize == .init())
        #expect(stash.fallbackSize == .init())
        frame.fallbackSize = fallback
        stash.fallbackSize = fallback
        #expect(frame.fallbackSize == .init())
        #expect(stash.fallbackSize == .init())
        frame.size = .preserve
        stash.size = .preserve
        #expect(frame.fallbackSize == .init(width: ScreenLength(80), height: ScreenLength(80)))
        #expect(stash.fallbackSize == .init(width: ScreenLength(80), height: ScreenLength(80)))
    }
}
