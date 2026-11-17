
import Foundation
@testable import Loop
import SwiftUI
import Testing
import TOML
import Tome

struct ActionPositionMemoryTests {
    @Test func switchingPositionModesKeepsTheInactiveModesValues() {
        var memory = ActionPositionMemory()
        let coordinates = ActionPosition.coordinates(x: ScreenLength(25), y: ScreenLength(30, unit: .points))
        #expect(memory.switched(from: .anchor(.bottomRight), toCoordinates: true) == .coordinates(x: ScreenLength(0), y: ScreenLength(0)))
        #expect(memory.switched(from: coordinates, toCoordinates: false) == .anchor(.bottomRight))
        #expect(memory.switched(from: .anchor(.bottomRight), toCoordinates: true) == coordinates)
        #expect(memory.switched(from: coordinates, toCoordinates: false) == .anchor(.bottomRight))
    }

    @Test func anAnchorlessActionFallsBackToCenter() {
        var memory = ActionPositionMemory()
        #expect(memory.switched(from: .coordinates(x: ScreenLength(5), y: nil), toCoordinates: false) == .anchor(.center))
        #expect(memory.switched(from: .anchor(.center), toCoordinates: true) == .coordinates(x: ScreenLength(5), y: nil))
    }
}

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
        let resolver = BindingResolutionSnapshot(keyBindings: bindings, gestures: [], radialMenuBindings: menu)
        let direct = try #require(resolver.action(for: bindings[2].target))
        let viaAlias = try #require(resolver.action(for: menu[0].target))
        #expect(direct.id == viaAlias.id)
    }
}

extension StoreTests {
    struct ColourSettingsTests {
        @Test func coloursReadSixOrEightDigitHexAndWriteSixWhenOpaque() throws {
            let profile = try Profile("[accent-color]\ncolor = \"#11223344\"\n")
            defer { Tome.reset(\.customAccentColor) }
            Tome.refresh(\.customAccentColor)
            #expect(try Color.tomeBridge.serialize(Tome.customAccentColor) == .string("#11223344"))
            #expect(!profile.issues.contains { $0.path == "accent-color.color" })
            Tome.customAccentColor = Color(.sRGB, red: 1, green: 0, blue: 0)
            #expect(profile.value(at: ["accent-color", "color"]) == .string("#FF0000"))
            try profile.install("[accent-color]\ncolor = \"#336699\"\n")
            Tome.refresh(\.customAccentColor)
            #expect(try Color.tomeBridge.serialize(Tome.customAccentColor) == .string("#336699"))
            #expect(!profile.issues.contains { $0.path == "accent-color.color" })
        }
    }
}
