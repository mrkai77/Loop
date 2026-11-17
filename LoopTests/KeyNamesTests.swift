//
//  KeyNamesTests.swift
//  LoopTests
//
//  Created by Kai Azim on 2026-11-16.
//

import CoreGraphics
import Foundation
@testable import Loop
import Testing
import Tome
import TOML

struct KeyNamesTests {
    // MARK: Resolution

    @Test func charactersNameTheKeyThatTypesThemOnEachLayout() {
        let (us, _) = FakeLayouts.layout(FakeLayouts.us)
        let (german, _) = FakeLayouts.layout(FakeLayouts.german)
        let (russian, _) = FakeLayouts.layout(FakeLayouts.russian)

        #expect(us.keyCode(forName: "z") == .kVK_ANSI_Z)
        #expect(us.keyCode(forName: "]") == .kVK_ANSI_RightBracket)
        #expect(us.keyCode(forName: "-") == .kVK_ANSI_Minus)
        #expect(us.keyCode(forName: "=") == .kVK_ANSI_Equal)
        #expect(german.keyCode(forName: "z") == .kVK_ANSI_Y)
        #expect(german.keyCode(forName: "y") == .kVK_ANSI_Z)
        #expect(german.keyCode(forName: "ß") == .kVK_ANSI_Minus)
        #expect(russian.keyCode(forName: "ф") == .kVK_ANSI_A)
        #expect(russian.keyCode(forName: "Ф") == .kVK_ANSI_A, "Names are lowercased before lookup")
    }

    @Test func aNameOnNoKeyIsUnresolved() {
        let (us, _) = FakeLayouts.layout(FakeLayouts.us)
        #expect(us.keyCode(forName: "ф") == nil)
        #expect(!us.resolves("ф"))
        #expect(us.keyCodes(for: ["cmd", "ф"]) == nil)
        #expect(us.keyCodes(for: ["cmd", "a"]) == [.kVK_Command, .kVK_ANSI_A])
    }

    @Test func aMissingNameFallsBackToTheUSLayout() {
        let (russian, _) = FakeLayouts.layout(FakeLayouts.russian)
        #expect(russian.keyCode(forName: "m") == .kVK_ANSI_M)
        // "z" isn't on the Russian layout, so it falls back to the US Z key
        #expect(russian.keyCode(forName: "z") == .kVK_ANSI_Z)
        #expect(russian.resolves("z"))
    }

    @Test func fixedNamesAndRawCodesIgnoreTheLayout() {
        let (russian, _) = FakeLayouts.layout(FakeLayouts.russian)
        for layout in [FakeLayouts.layout(FakeLayouts.us).0, russian] {
            #expect(layout.keyCode(forName: "left") == .kVK_LeftArrow)
            #expect(layout.keyCode(forName: "CMD") == .kVK_Command)
            #expect(layout.keyCode(forName: "right-alt") == .kVK_RightOption)
            #expect(layout.keyCode(forName: "pad5") == .kVK_ANSI_Keypad5)
            #expect(layout.keyCode(forName: "#36") == 36)
            #expect(layout.keyCode(forName: "#600") == 600)
        }
    }

    @Test func codesAreNamedByTheirCharacterOrFixedNameOrRawCode() {
        let (russian, _) = FakeLayouts.layout(FakeLayouts.russian)
        #expect(russian.name(forKeyCode: .kVK_ANSI_A) == "ф")
        #expect(russian.name(forKeyCode: .kVK_LeftArrow) == "left")
        #expect(russian.name(forKeyCode: .kVK_Option) == "alt")
        #expect(russian.name(forKeyCode: .kVK_Globe_Emoji) == "#179")
        #expect(!russian.name(forKeyCode: 0xFE).isEmpty)
    }

    @Test func fixedNamesWinAClashWithALayoutCharacter() {
        let source = FakeKeyLayoutSource(characters: [.kVK_JIS_Yen: "x", .kVK_ANSI_A: "a"])
        let layout = KeyboardLayout(source: source)
        #expect(layout.name(forKeyCode: .kVK_JIS_Yen) == "yen")
        #expect(layout.keyCode(forName: "x") == .kVK_ANSI_X, "The yen key no longer answers to its character; the US fallback does")
    }

    @Test func aLayoutWithoutDataUsesTheUSSetIncludingTheISOSection() {
        let source = FakeKeyLayoutSource(characters: [:], hasLayoutData: false)
        let layout = KeyboardLayout(source: source)
        #expect(layout.keyCode(forName: "q") == .kVK_ANSI_Q)
        #expect(layout.keyCode(forName: "§") == .kVK_ISO_Section)
        #expect(layout.name(forKeyCode: .kVK_ISO_Section) == "§")
    }

    @Test func keyCodes93And94AreSkipped() {
        let source = FakeKeyLayoutSource(characters: [93: "¥", 94: "_"])
        let layout = KeyboardLayout(source: source)
        #expect(layout.keyCode(forName: "¥") == nil)
        #expect(layout.keyCode(forName: "yen") == .kVK_JIS_Yen)
    }

    @Test func laterKeysWinARepeatedCharacter() {
        let source = FakeKeyLayoutSource(characters: [.kVK_ANSI_A: "x", .kVK_ANSI_B: "x"])
        #expect(KeyboardLayout(source: source).keyCode(forName: "x") == .kVK_ANSI_B)
    }

    @Test func theMapIsRebuiltAfterAnInputSourceChange() {
        let (layout, source) = FakeLayouts.layout(FakeLayouts.us)
        #expect(layout.keyCode(forName: "y") == .kVK_ANSI_Y)
        source.switchTo(FakeLayouts.german)
        #expect(layout.keyCode(forName: "y") == .kVK_ANSI_Y, "The map is cached until the input source changes")
        layout.invalidate()
        #expect(layout.keyCode(forName: "y") == .kVK_ANSI_Z)
    }

    // MARK: Persistence

    @Test func decodingValidatesSpellingWithoutALayout() throws {
        let bridge = KeyCombination.tomeBridge
        #expect(try bridge.deserialize(.string("a")).names == ["a"])
        #expect(try bridge.deserialize(.string("]")).names == ["]"])
        #expect(try bridge.deserialize(.string("ф")).names == ["ф"])
        #expect(try bridge.deserialize(.string("+")).names == ["+"])
        #expect(try bridge.deserialize(.string("#")).names == ["#"], "A lone # is the character, not a raw code")
        #expect(try bridge.deserialize(.string("#36")).names == ["#36"])
        #expect(try bridge.deserialize(.array([.string("CTRL"), .string("Left"), .string("A")])).names == ["ctrl", "left", "a"])
        #expect(try bridge.deserialize(.string("")).names == [])
        for invalid in ["rightbracket", "lctrl", "lopt", "minus", "key:0x10", "#x", "#-1", "#70000", "ctrl+left", "unknown"] {
            #expect(throws: (any Error).self, "\(invalid) should be invalid") { try bridge.deserialize(.string(invalid)) }
        }
        #expect(throws: (any Error).self) { try bridge.deserialize(.array([.string("left"), .string("")])) }
        #expect(throws: (any Error).self) { try bridge.deserialize(.integer(58)) }
    }

    @Test func chordsAreAnArrayOrOnePlainName() throws {
        let bridge = KeyCombination.tomeBridge
        #expect(try bridge.deserialize(bridge.serialize([])) == [])
        #expect(try bridge.serialize(KeyCombination(names: ["fn"])) == .string("fn"))
        #expect(try bridge.serialize(KeyCombination(names: ["]"])) == .string("]"))
        #expect(try bridge.serialize([.kVK_Control, .kVK_Option, .kVK_LeftArrow]) == .array([.string("alt"), .string("ctrl"), .string("left")]))
        #expect(try bridge.serialize(KeyCombination(names: ["left", "ф", "ctrl", "a"])) == .array([.string("ctrl"), .string("a"), .string("ф"), .string("left")]))
        #expect(try bridge.deserialize(bridge.serialize(KeyCombination(names: ["cmd", "["]))) == KeyCombination(names: ["cmd", "["]))
    }

    @Test func componentsPutModifiersFirstThenCharactersThenOtherKeys() {
        #expect(KeyNames.components(from: ["left", "ctrl", "a"]) == ["ctrl", "a", "left"])
        #expect(KeyNames.components(from: ["left", "ctrl", "cmd", "a"]) == ["cmd", "ctrl", "a", "left"])
    }

    @Test func modifierSidesKeepTheirMeaning() {
        #expect(KeyNames.baseModifier("right-cmd") == "cmd")
        #expect(KeyNames.baseModifier("right-alt") == "alt")
        #expect(KeyNames.baseModifier("shift") == "shift")
        #expect(KeyNames.baseModifier("a") == "a")
        #expect(KeyNames.isRightModifier("right-ctrl"))
        #expect(!KeyNames.isRightModifier("ctrl"))
        #expect(KeyCombination(names: ["shift", "left"]).containsFixedKey(.kVK_Shift))
        #expect(!KeyCombination(names: ["right-shift", "left"]).containsFixedKey(.kVK_Shift))
    }

    // MARK: Migration and recording

    @Test func migrationNamesCodesWithTheCurrentLayout() {
        let (german, _) = FakeLayouts.layout(FakeLayouts.german)
        let migrated = KeyCombination(keyCodes: [.kVK_Control, .kVK_ANSI_Y, .kVK_ANSI_Minus, .kVK_LeftArrow, .kVK_Globe_Emoji], layout: german)
        #expect(migrated.names == ["ctrl", "z", "ß", "left", "#179"])
        #expect(!migrated.names.contains(""))
    }

    @Test func aCodeMissingFromTheLayoutUsesTheUSCharacter() {
        let source = FakeKeyLayoutSource(characters: [.kVK_ANSI_A: "a"])
        #expect(KeyCombination(keyCodes: [.kVK_ANSI_Q], layout: KeyboardLayout(source: source)).names == ["q"])
    }

    @Test func legacyKeybindsConvertWithTheLayoutActiveAtMigrationTime() throws {
        let (german, _) = FakeLayouts.layout(FakeLayouts.german)
        // The Z-position key code is named "y" on QWERTZ
        let legacy = try Develop.WindowAction(.maximize, keybind: [.kVK_ANSI_Y, .kVK_Control]).read()
        let converted = KeyboardLayout.withLayout(german) { legacy.convertToKeyBinding() }
        #expect(converted.keys.names == ["z", "ctrl"])
    }

    @Test func recordingStoresTheCharacterTheKeyTypes() {
        let (russian, _) = FakeLayouts.layout(FakeLayouts.russian)
        #expect(russian.name(forKeyCode: CGKeyCode.kVK_ANSI_A.baseKey(isFnPressed: false)) == "ф")
        #expect(russian.name(forKeyCode: CGKeyCode.kVK_Home.baseKey(isFnPressed: true)) == "left")
    }
}
