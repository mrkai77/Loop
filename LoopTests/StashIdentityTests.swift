//
//  StashIdentityTests.swift
//  LoopTests
//
//  Created by Kai Azim on 2026-11-16.
//

import Foundation
@testable import Loop
import SwiftUI
import Testing
import Tome
import TOML

struct StashIdentityTests {
    private let source = """
    [[key.bindings]]
    action = "stash"
    name = "Left"
    keys = "a"
    position = "top-left"
    [[key.bindings]]
    action = "cycle"
    cycle = [{ action = "left-half" }, { action = "stash", position = "top-right" }]
    [[key.bindings]]
    id = "named"
    action = "stash"
    position = "bottom-left"
    """

    private func stashIDs(_ source: String) throws -> [UUID] {
        let rows = try #require(TOMLDocument(source).value(at: ["key", "bindings"]))
        // Every call is a fresh launch
        return try [KeyBinding].decodeIdentified(rows).flatMap { binding -> [UUID] in
            guard case let .windowAction(action) = binding.target else { return [] }
            if case let .cycle(cycle) = action.kind {
                return cycle.steps.compactMap { if case let .windowAction(step) = $0, step.direction == .stash { step.id } else { nil } }
            }
            return action.direction == .stash ? [action.id] : []
        }
    }

    @Test func stashIdentitySurvivesARestart() throws {
        let first = try stashIDs(source)
        #expect(first.count == 3)
        #expect(Set(first).count == 3)
        #expect(try stashIDs(source) == first)
    }

    @Test func renamesAndShortcutChangesKeepTheIdentity() throws {
        let first = try stashIDs(source)
        let edited = source.replacingOccurrences(of: "name = \"Left\"", with: "name = \"Renamed\"")
            .replacingOccurrences(of: "keys = \"a\"", with: "keys = [\"ctrl\", \"b\"]")
        #expect(try stashIDs(edited) == first)
    }

    @Test func aBindingsIdentityIgnoresItsConfigurationID() throws {
        let first = try stashIDs(source)
        #expect(try stashIDs(source.replacingOccurrences(of: "id = \"named\"", with: "id = \"other\"")) == first)
        #expect(try stashIDs(source.replacingOccurrences(of: "id = \"named\"", with: "id = \"kb_named\"")) == first)
        #expect(try stashIDs(source.replacingOccurrences(of: "id = \"named\"\n", with: "")) == first)
        let moved = source.replacingOccurrences(of: "id = \"named\"\naction = \"stash\"\nposition = \"bottom-left\"", with: "id = \"named\"\naction = \"stash\"\nposition = \"bottom-right\"")
        #expect(try stashIDs(moved)[2] != first[2])
    }

    @Test func identicalStashesAreToldApartByTheirPosition() throws {
        let twice = "[[key.bindings]]\naction = \"stash\"\nposition = \"top-left\"\n[[key.bindings]]\naction = \"stash\"\nposition = \"top-left\"\n"
        let ids = try stashIDs(twice)
        #expect(ids.count == 2 && ids[0] != ids[1])
        #expect(try stashIDs(twice) == ids)
    }

    /// `prefix` rows come before the unidentified stash keybind.
    private func unidentifiedStashID(after prefix: String = "") throws -> UUID {
        let source = "\(prefix)[[key.bindings]]\naction = \"stash\"\nposition = \"top-left\"\nkeys = \"s\"\n"
        return try #require(stashIDs(source).last)
    }

    @Test func insertingAnUnrelatedBindingBeforeAStashKeepsItsIdentity() throws {
        let unrelated = "[[key.bindings]]\naction = \"maximize\"\nkeys = \"m\"\n[[key.bindings]]\naction = \"stash\"\nposition = \"bottom-right\"\n"
        #expect(try unidentifiedStashID(after: unrelated) == unidentifiedStashID())
    }

    @Test func aliasesResolveToTheDestinationsIdentity() throws {
        let rows = try #require(TOMLDocument(source + "\n[[radial-menu.bindings]]\naction = \"key:named\"\n").value(at: ["key", "bindings"]))
        let radial = try #require(TOMLDocument(source + "\n[[radial-menu.bindings]]\naction = \"key:named\"\n").value(at: ["radial-menu", "bindings"]))
        let bindings = try [KeyBinding].decodeIdentified(rows)
        let menu = try [RadialMenuBinding].decodeIdentified(radial)
        let resolver = BindingResolutionSnapshot(keyBindings: bindings, gestureBindings: [], radialMenuBindings: menu)
        let direct = try #require(resolver.action(for: bindings[2].target))
        let viaAlias = try #require(resolver.action(for: menu[0].target))
        #expect(direct.id == viaAlias.id)
    }
}
