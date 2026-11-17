//
//  WindowActionLegacyDecodingTests.swift
//  Loop
//
//  Created by Kai Azim on 2026-11-14.
//

import CoreGraphics
import Defaults
import Foundation
@testable import Loop
import Testing
import TOML

struct WindowActionLegacyDecodingTests {
    /// Stored by Defaults.DictionaryBridge as one JSON string per window ID.
    private let legacyStash = """
    {"id":"A1442C2E-5A10-4CCA-B36E-CA37EE503C8C","direction":"Stash","keybind":[],"name":"Recovered stash","unit":0,"anchor":0,"sizeMode":1,"width":640,"height":480,"positionMode":1,"xPoint":40,"yPoint":60}
    """

    @Test func migrationRewritesDevelopsStashRecordsKeepingTheirIdentityAndGeometry() throws {
        let fixture = LegacyDefaultsFixture()
        defer { fixture.cleanUp() }
        fixture.suite.set(["314": legacyStash], forKey: Defaults.Keys.stashManagerStashedWindows.name)
        #expect(fixture.stashRecords.isEmpty)

        try ConfigMigrator.migrateStashRecords(document: TOMLDocument(""), suite: fixture.suite)
        let recovered = try #require(fixture.stashRecords[314])
        #expect(recovered.id == UUID(uuidString: "A1442C2E-5A10-4CCA-B36E-CA37EE503C8C"))
        #expect(recovered.direction == .stash)
        #expect(recovered.name == "Recovered stash")
        #expect(recovered.size == .preserve)
        #expect(recovered.customDimensions == .init(width: ScreenLength(640, unit: .points), height: ScreenLength(480, unit: .points)))
        #expect(recovered.position == .coordinates(x: ScreenLength(40, unit: .points), y: ScreenLength(60, unit: .points)))

        let rewritten = try #require((fixture.suite.dictionary(forKey: Defaults.Keys.stashManagerStashedWindows.name)?["314"] as? String)?.data(using: .utf8))
        let object = try #require(JSONSerialization.jsonObject(with: rewritten) as? [String: Any])
        #expect(object["direction"] == nil)
        #expect(object["kind"] != nil)
        try ConfigMigrator.migrateStashRecords(document: TOMLDocument(""), suite: fixture.suite)
        #expect(fixture.stashRecords[314] == recovered)
    }

    @Test func legacyInitialSizeAndOmittedGeometryRetainTheirMeaning() throws {
        let source = """
        {"id":"0BFCEEA7-7FE7-46BB-BDF3-E7CA23740C51","direction":"Custom","keybind":[],"unit":1,"sizeMode":2,"width":25,"height":50,"anchor":6}
        """
        let action = try JSONDecoder().decode(LegacyWindowAction.self, from: Data(source.utf8)).convertToWindowAction()
        #expect(action.id == UUID(uuidString: "0BFCEEA7-7FE7-46BB-BDF3-E7CA23740C51"))
        #expect(action.size == .initial)
        #expect(action.customDimensions == .init(width: ScreenLength(25), height: ScreenLength(50)))
        #expect(action.position == .anchor(.bottomLeft))
        let omitted = try JSONDecoder().decode(LegacyWindowAction.self, from: Data("{\"id\":\"0BFCEEA7-7FE7-46BB-BDF3-E7CA23740C51\",\"direction\":\"Stash\",\"keybind\":[]}".utf8)).convertToWindowAction()
        #expect(omitted.size == .custom(width: nil, height: nil))
        #expect(omitted.position == .anchor(.none))
    }

    @Test func legacyCyclePreservesEveryStoredActionUUID() throws {
        let source = """
        {"id":"36974649-0488-4773-9EA4-ED4424F748A3","direction":"Cycle","keybind":[],"name":"Recovery cycle","cycle":[{"id":"9BCDEDAB-1233-4B2D-A2F8-CB0E5ED0C928","direction":"Maximize","keybind":[]},{"id":"E57FB481-EE2B-4F9C-BBE8-90CB32358D8D","direction":"Stash","keybind":[],"unit":1,"width":80,"height":70,"anchor":0}]}
        """
        let action = try JSONDecoder().decode(LegacyWindowAction.self, from: Data(source.utf8)).convertToWindowAction()
        #expect(action.id == UUID(uuidString: "36974649-0488-4773-9EA4-ED4424F748A3"))
        guard case let .cycle(payload) = action.kind else { Issue.record("Expected recovery cycle"); return }
        #expect(payload.name == "Recovery cycle")
        let children = payload.steps.compactMap { target -> WindowAction? in
            if case let .windowAction(action) = target { action } else { nil }
        }
        #expect(try children.map(\.id) == [#require(UUID(uuidString: "9BCDEDAB-1233-4B2D-A2F8-CB0E5ED0C928")), #require(UUID(uuidString: "E57FB481-EE2B-4F9C-BBE8-90CB32358D8D"))])
        #expect(children.last?.customDimensions == .init(width: ScreenLength(80), height: ScreenLength(70)))
    }

    @Test func stashRecordsRoundTripThroughDefaults() throws {
        var stash = WindowAction(.stash)
        stash.name = "Stashed"
        stash.size = .preserve
        stash.customDimensions = .init(width: ScreenLength(300, unit: .points), height: ScreenLength(40))
        stash.position = .coordinates(x: ScreenLength(10, unit: .points), y: ScreenLength(20, unit: .points))
        var corner = WindowAction(.stash)
        corner.position = .anchor(.bottomRight)
        let key = try Defaults.Key<[CGWindowID: WindowAction]>("stashRoundTrip.\(UUID().uuidString)", default: [:], suite: #require(UserDefaults(suiteName: UUID().uuidString)))
        Defaults[key] = [1: stash, 2: corner]
        #expect(Defaults[key][1] == stash)
        #expect(Defaults[key][2] == corner)
    }

    @Test func stashRecordsAreSavedWithRawValues() throws {
        var action = WindowAction(.stash)
        let width = ScreenLength(50, unit: .percent)
        let height = ScreenLength(480, unit: .points)
        action.size = .custom(width: width, height: height)
        action.position = .anchor(.bottomRight)
        let json = try #require(WindowAction.bridge.serialize(action))
        #expect(WindowAction.bridge.deserialize(json) == action)
        #expect(json.contains("\"bottom-right\""))
        #expect(json.contains("\"50%\"") && json.contains("\"480pt\""))
    }
}
