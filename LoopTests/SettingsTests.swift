//
//  SettingsTests.swift
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

extension StoreTests {
    struct SettingsTests {
        @Test func emptyFieldsAreNeverWritten() throws {
            let profile = try Profile("[[key.bindings]]\naction = \"none\"\nkeys = []\nname = \"\"\n")
            var actions = profile[\.keyBindings]
            actions[0].target = .windowAction(WindowAction(.maximize))
            actions.append(KeyBinding(.noAction))
            try profile.set(actions, for: \.keyBindings)
            let document = try TOMLDocument(profile.serialized)
            let entries = try TOMLCodecs.decodeArray(#require(document.value(at: ["key", "bindings"]))).map(TOMLCodecs.decodeTable)
            for entry in entries {
                #expect(entry["keys"] == nil)
                #expect(entry["name"] == nil)
            }
        }

        @Test func editingAChordKeepsItsComment() throws {
            let profile = try Profile("[[key.bindings]]\naction = \"maximize\"\nkeys = \"a\" # keep comment\n")
            var actions = profile[\.keyBindings]
            actions[0].keys = KeyCombination(names: ["b"])
            try profile.set(actions, for: \.keyBindings)
            #expect(profile.serialized.contains("keys = \"b\" # keep comment"))
        }

        @Test func explicitDefaultsStayInTheFileAndOnlyResetRemovesTheKey() throws {
            let profile = try Profile("")
            profile[\.showDockIcon] = true
            #expect(profile.value(at: ["icon", "show-in-dock"]) == .boolean(true))
            // An explicit write of the default stays in the file
            profile[\.showDockIcon] = false
            #expect(profile.value(at: ["icon", "show-in-dock"]) == .boolean(false))
            profile[\.showDockIcon] = true
            Tome.reset(\.showDockIcon)
            #expect(profile.value(at: ["icon", "show-in-dock"]) == nil)
            #expect(!profile.serialized.contains("show-in-dock"))
        }

        @MainActor @Test func doubleBindingRoundsWritesButPreservesHandEditedReads() throws {
            let profile = try Profile()
            let control = Binding(get: { Tome.radialMenuThickness }, set: { Tome.radialMenuThickness = $0 }).doubleBinding
            Tome.radialMenuThickness = 19.96124267578125
            #expect(control.wrappedValue == 19.96124267578125)
            control.wrappedValue = 19.96124267578125
            #expect(Tome.radialMenuThickness == 19.96)
            #expect(profile.serialized.contains("thickness = 19.96"))
        }
    }
}
