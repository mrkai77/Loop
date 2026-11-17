//
//  ConfigurationSpellingTests.swift
//  LoopTests
//
//  Created by Kai Azim on 2026-11-16.
//

import Foundation
@testable import Loop
import Testing
import Tome
import TOML

extension StoreTests {
    struct ConfigurationSpellingTests {
        @Test func durationsAcceptSecondsAndUnits() throws {
            // The format itself is covered by Tome's tests
            let cases: [(String, Duration?)] = [
                ("0.5", .milliseconds(500)),
                ("2", .seconds(2)),
                ("\"0.3s\"", .milliseconds(300)),
                ("\"300ms\"", .milliseconds(300)),
                ("\"2m\"", .seconds(120)),
                ("\"25h\"", .seconds(90000)),
                ("-1", .seconds(-1)),
                ("\"2562048h\"", .seconds(2_562_048 * 3600)),
                ("\"300\"", nil),
                ("\"fasts\"", nil),
                ("true", nil),
                ("1e19", nil),
                ("\"1e300s\"", nil)
            ]
            for key in ["delay", "timeout"] {
                for (literal, expected) in cases {
                    let profile = try Profile("[trigger]\n\(key) = \(literal)\n")
                    Tome.refresh(\.triggerDelay, \.triggerKeyTimeout)
                    let value = key == "delay" ? Tome.triggerDelay : Tome.triggerKeyTimeout
                    #expect(value == (expected ?? .zero), "\(key) = \(literal)")
                    #expect(profile.issues.contains { $0.path == "trigger.\(key)" } == (expected == nil), "\(key) = \(literal)")
                }
            }
        }

        @Test func timeoutAcceptsUnitsAndLoopWritesQuotedDurations() throws {
            let profile = try Profile("[trigger]\ntimeout = \"1500ms\"\n")
            defer { Tome.reset(\.triggerKeyTimeout, \.triggerDelay) }
            Tome.refresh(\.triggerKeyTimeout)
            #expect(Tome.triggerKeyTimeout == .milliseconds(1500))
            Tome.triggerKeyTimeout = .milliseconds(2500)
            #expect(profile.value(at: ["trigger", "timeout"]) == .string("2.5s"))
            Tome.triggerDelay = .milliseconds(250)
            #expect(profile.value(at: ["trigger", "delay"]) == .string("250ms"))
        }

        @Test func theTargetWindowLivesAtWindowTarget() throws {
            let profile = try Profile("[window]\ntarget = \"under-cursor\"\n")
            defer { Tome.reset(\.targetWindow) }
            Tome.refresh(\.targetWindow)
            #expect(Tome.targetWindow == .underCursor)
            Tome.targetWindow = .frontmost
            #expect(profile.value(at: ["window", "target"]) == .string("active"))
            try profile.install("[window]\ntargetWindow = \"underCursor\"\n")
            Tome.refresh(\.targetWindow)
            #expect(Tome.targetWindow == .frontmost)
            try profile.install("[window]\ntarget = \"underCursor\"\n")
            Tome.refresh(\.targetWindow)
            #expect(profile.issues.contains { $0.path == "window.target" })
        }

        @Test func screenOrderIsZShapedOrClockwise() throws {
            let profile = try Profile("screen-order = \"clockwise\"\n")
            defer { Tome.reset(\.screenOrder) }
            Tome.refresh(\.screenOrder)
            #expect(Tome.screenOrder == .clockwise)
            Tome.screenOrder = .zShaped
            #expect(profile.value(at: ["screen-order"]) == .string("z-shaped"))
            try profile.install("screen-order = \"zShaped\"\n")
            Tome.refresh(\.screenOrder)
            #expect(Tome.screenOrder == .zShaped)
            #expect(profile.issues.contains { $0.path == "screen-order" })
        }

        @Test func enumValuesInBindingsAreKebabCase() throws {
            let profile = try Profile("[[key.bindings]]\naction = \"top-two-thirds\"\nkeys = \"a\"\n[[key.bindings]]\naction = \"none\"\nkeys = \"b\"\n")
            Tome.refresh(\.keyBindings)
            #expect(profile[\.keyBindings].map(\.target.resolvedDirection) == [.topTwoThirds, .noAction])
            try profile.install("[[key.bindings]]\naction = \"topTwoThirds\"\nkeys = \"a\"\n")
            Tome.refresh(\.keyBindings)
            #expect(profile.issues.contains { $0.path == "key.bindings" })
        }
    }
}
