//
//  ConfigMigratorTests.swift
//  LoopTests
//
//  Created by Kai Azim on 2026-11-16.
//

import Defaults
import Foundation
@testable import Loop
import SwiftUI
import Testing
import TOML
import Tome

extension StoreTests {
    struct ConfigMigratorTests {
        @Test func legacyEnumAndPaddingChoicesBecomeNamedValuesOnlyAtCutover() throws {
            let fixture = LegacyDefaultsFixture()
            defer { fixture.cleanUp() }
            fixture.set(.custom, LegacyDefaults.accentColorMode)
            fixture.set(.brisk, LegacyDefaults.animationConfiguration)
            fixture.set(.clockwise, LegacyDefaults.screenOrder)
            fixture.set(LegacyPaddingConfiguration(
                window: 10,
                externalBar: 0,
                top: 20,
                bottom: 30,
                right: 40,
                left: 50,
                configureScreenPadding: true
            ), LegacyDefaults.padding)
            let before = fixture.persisted
            try ConfigMigrator.run(url: fixture.url, suite: fixture.suite, domainName: fixture.suiteName)
            let document = try TOMLDocument(String(contentsOf: fixture.url, encoding: .utf8))
            #expect(document.value(at: ["accent-color", "mode"]) == .string("custom"))
            #expect(document.value(at: ["animation-speed"]) == .string("brisk"))
            #expect(document.value(at: ["screen-order"]) == .string("clockwise"))
            #expect(document.value(at: ["padding", "mode"]) == .string("custom"))
            #expect(document.value(at: ["padding", "gap"]) == .float(10))
            #expect(document.value(at: ["padding", "edges"]) == .table(["top": .float(20), "bottom": .float(30), "left": .float(50), "right": .float(40)]))
            #expect(document.value(at: ["padding", "windowGaps"]) == nil)
            var after = fixture.persisted
            after.removeValue(forKey: "configMigrationVersion")
            #expect(NSDictionary(dictionary: before).isEqual(to: after))
        }

        @Test func triggerPrecedesBindingsAndExplicitDefaultsAreMigrated() throws {
            let fixture = LegacyDefaultsFixture()
            defer { fixture.cleanUp() }
            fixture.set(LegacyDefaults.enablePadding.defaultValue, LegacyDefaults.enablePadding)
            fixture.set(LegacyDefaults.startHidden.defaultValue, LegacyDefaults.startHidden)
            fixture.set(LegacyDefaults.sizeIncrement.defaultValue, LegacyDefaults.sizeIncrement)
            fixture.set([.kVK_Option], LegacyDefaults.triggerKey)
            fixture.set([LegacyWindowAction(KeyBinding(.maximize, keybind: KeyCombination(names: ["a"])))], LegacyDefaults.keybinds)
            #expect(fixture.persisted.keys.contains(LegacyDefaults.enablePadding.name))
            #expect(fixture.persisted.keys.contains(LegacyDefaults.triggerKey.name))
            #expect(fixture.persisted.keys.contains(LegacyDefaults.keybinds.name))

            try ConfigMigrator.run(url: fixture.url, suite: fixture.suite, domainName: fixture.suiteName)
            let source = try String(contentsOf: fixture.url, encoding: .utf8)
            let document = try TOMLDocument(source)
            #expect(document.value(at: ["padding", "enabled"]) == .boolean(false))
            #expect(document.value(at: ["start-hidden"]) == .boolean(false))
            #expect(document.value(at: ["window", "size-increment"]) != nil)
            #expect(document.value(at: ["icon", "show-in-dock"]) == nil)
            #expect(document.value(at: ["trigger", "keys"]) != nil)
            #expect(document.value(at: ["key", "bindings"]) != nil)
            let trigger = try #require(source.range(of: "[trigger]"))
            let bindings = try #require(source.range(of: "[[key.bindings]]"))
            #expect(trigger.lowerBound < bindings.lowerBound)
        }

        @Test func firstConversionRoundsLengthsWithoutChangingUserDefaults() throws {
            let fixture = LegacyDefaultsFixture()
            defer { fixture.cleanUp() }
            fixture.set(40.2978515625, LegacyDefaults.radialMenuCornerRadius)
            fixture.set(19.96124267578125, LegacyDefaults.radialMenuThickness)
            fixture.set(3.139404296875, LegacyDefaults.previewBorderThickness)
            fixture.set(LegacyPaddingConfiguration(
                window: 12.345,
                externalBar: 0,
                top: 12.345,
                bottom: 12.345,
                right: 12.345,
                left: 12.345,
                configureScreenPadding: true
            ), LegacyDefaults.padding)
            let action = WindowAction(kind: .custom(.init(
                size: .custom(width: ScreenLength(52.306), height: ScreenLength(80.006)),
                position: .coordinates(x: ScreenLength(10.234), y: ScreenLength(5.678))
            )))
            let binding = KeyBinding(target: .windowAction(action))
            fixture.set([LegacyWindowAction(binding)], LegacyDefaults.keybinds)
            fixture.set([.keybindReference(binding.id)], LegacyDefaults.radialMenuActions)
            fixture.set(true, LegacyDefaults.enableGestures)
            fixture.set([LegacyGestureBinding(
                fingerCount: 3,
                kind: .magnifyOut,
                action: .singleAction(.keybindReference(binding.id)),
                activationZone: .anywhere
            )], LegacyDefaults.gestures)
            let before = fixture.persisted

            #expect(try ConfigMigrator.run(url: fixture.url, suite: fixture.suite, domainName: fixture.suiteName) == .migrated)
            var after = fixture.persisted
            #expect(after.removeValue(forKey: "configMigrationVersion") as? Int == 1)
            #expect(NSDictionary(dictionary: before).isEqual(to: after))
            let source = try String(contentsOf: fixture.url, encoding: .utf8)
            let document = try TOMLDocument(source)
            #expect(document.value(at: ["radial-menu", "corner-radius"]) == .float(40.3))
            #expect(document.value(at: ["radial-menu", "thickness"]) == .float(20.0))
            #expect(document.value(at: ["preview", "border-thickness"]) == .float(3.1))
            #expect(document.value(at: ["padding", "gap"]) == .float(12.3))
            let keybinds = try TOMLCodecs.decodeArray(#require(document.value(at: ["key", "bindings"])))
            let custom = try TOMLCodecs.decodeTable(keybinds[0])
            #expect(custom["size"] == .table(["width": .string("52.31%"), "height": .string("80.01%")]))
            #expect(custom["position"] == .table(["x": .string("10.23%"), "y": .string("5.68%")]))
            let gesture = try TOMLCodecs.decodeTable(TOMLCodecs.decodeArray(#require(document.value(at: ["gestures", "bindings"])))[0])
            #expect(gesture["kind"] == .string("pinch"))
            #expect(gesture["zone"] == .string("anywhere"))
            let headers = source.split(separator: "\n").map(String.init).filter { $0.hasPrefix("[") }
            let radialIndex = try #require(headers.firstIndex(of: "[radial-menu]"))
            let previewIndex = try #require(headers.firstIndex(of: "[preview]"))
            let paddingIndex = try #require(headers.firstIndex(of: "[padding]"))
            let keyBindingIndex = try #require(headers.firstIndex(of: "[[key.bindings]]"))
            let gestureIndex = try #require(headers.firstIndex(of: "[gestures]"))
            #expect(headers[radialIndex + 1] == "[[radial-menu.bindings]]")
            #expect(radialIndex < previewIndex && previewIndex < paddingIndex && paddingIndex < keyBindingIndex && keyBindingIndex < gestureIndex)
            #expect(headers[gestureIndex + 1] == "[[gestures.bindings]]")
        }

        @Test func customizedProfilePreservesEffectiveValuesAndLegacyStorage() throws {
            let fixture = LegacyDefaultsFixture()
            defer { fixture.cleanUp() }
            let custom = KeyBinding(keys: KeyCombination(names: ["ctrl", "a"]), bypassTriggerKey: true, target: .windowAction(WindowAction(kind: .custom(.init(name: "Wide", size: .custom(width: ScreenLength(0.75), height: ScreenLength(0.8)), position: .coordinates(x: ScreenLength(12), y: ScreenLength(24)))))))
            fixture.set([LegacyWindowAction(custom)], LegacyDefaults.keybinds)
            fixture.set([.keybindReference(custom.id)], LegacyDefaults.radialMenuActions)
            fixture.set([LegacyGestureBinding(fingerCount: 3, kind: .magnifyOut, action: .singleAction(.keybindReference(custom.id)), activationZone: .anywhere)], LegacyDefaults.gestures)
            fixture.set(Color(.sRGB, red: 0x12 / 255.0, green: 0x34 / 255.0, blue: 0x56 / 255.0, opacity: 1), LegacyDefaults.customAccentColor)
            fixture.set(LegacyPaddingConfiguration(window: 8, externalBar: 9, top: 10, bottom: 11, right: 12, left: 13, configureScreenPadding: true), LegacyDefaults.padding)
            fixture.set(42, Defaults.Keys.timesLooped)
            fixture.set("AppIcon-Test", Defaults.Keys.currentIcon)
            fixture.set(true, Defaults.Keys.launchAtLogin)
            fixture.set(true, LegacyDefaults.enablePadding)
            fixture.set(true, LegacyDefaults.disableCursorInteraction)
            fixture.set(true, LegacyDefaults.resizeWindowUnderCursor)
            fixture.set(true, LegacyDefaults.startHidden)
            fixture.set(true, LegacyDefaults.hideMenuBarIcon)
            fixture.set(false, LegacyDefaults.hideOnNoSelectionForGestures)
            fixture.set(2.5, LegacyDefaults.triggerKeyTimeout)
            fixture.set(0.3, LegacyDefaults.triggerDelay)
            let before = fixture.persisted
            #expect(try ConfigMigrator.run(url: fixture.url, suite: fixture.suite, domainName: fixture.suiteName) == .migrated)
            var after = fixture.persisted
            #expect(after.removeValue(forKey: "configMigrationVersion") as? Int == 1)
            #expect(NSDictionary(dictionary: before).isEqual(to: after))

            let document = try TOMLDocument(String(contentsOf: fixture.url, encoding: .utf8))
            #expect(document.value(at: ["version"]) == nil)
            let tables = try TOMLCodecs.decodeArray(#require(document.value(at: ["key", "bindings"])))
            let customTable = try TOMLCodecs.decodeTable(tables[0])
            #expect(customTable["size"] == .table(["width": .string("0.75%"), "height": .string("0.8%")]))
            #expect(customTable["position"] == .table(["x": .string("12%"), "y": .string("24%")]))
            let settings = try Profile(String(contentsOf: fixture.url, encoding: .utf8))
            #expect(settings[\.keyBindings].map(\.target.semanticKey) == [custom.target.semanticKey])
            #expect(settings[\.keyBindings][0].bypassTriggerKey == true)
            #expect(try settings[\.radialMenuActions][0].target == .keyBinding(#require(settings[\.keyBindings][0].configID)))
            let gesture = settings[\.gestures][0]
            #expect(try gesture.target == .keyBinding(#require(settings[\.keyBindings][0].configID)))
            #expect(gesture.kind == .magnifyOut)
            #expect(gesture.activationZone == .anywhere)
            #expect(settings[\.padding] == fixture.get(LegacyDefaults.padding).current)
            #expect(settings[\.selectActionsWithCursor] == !fixture.get(LegacyDefaults.disableCursorInteraction))
            #expect((settings[\.targetWindow] == .underCursor) == fixture.get(LegacyDefaults.resizeWindowUnderCursor))
            #expect(settings[\.startHidden] && settings[\.hideMenuBarIcon])
            #expect(settings[\.triggerKeyTimeout] == .milliseconds(2500))
            #expect(settings[\.triggerDelay] == .milliseconds(300))
            #expect(settings.value(at: ["trigger", "delay"]) == .string("300ms"))
            #expect(try Color.tomeBridge.serialize(settings[\.customAccentColor]) == .string("#123456"))
            #expect(settings.issues.isEmpty)
        }

        @Test func existingFileAlwaysWinsEvenWhenMalformed() throws {
            for text in ["startHidden = false\n", "invalid = ["] {
                let fixture = LegacyDefaultsFixture()
                defer { fixture.cleanUp() }
                fixture.set(true, LegacyDefaults.startHidden)
                try FileManager.default.createDirectory(at: fixture.url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try text.write(to: fixture.url, atomically: true, encoding: .utf8)
                let before = fixture.persisted
                #expect(try ConfigMigrator.run(url: fixture.url, suite: fixture.suite, domainName: fixture.suiteName) == .existingFile)
                #expect(try String(contentsOf: fixture.url, encoding: .utf8) == text)
                var after = fixture.persisted
                #expect(after.removeValue(forKey: "configMigrationVersion") as? Int == 1)
                #expect(NSDictionary(dictionary: before).isEqual(to: after))
            }
        }

        @Test func failedMigrationLeavesDefaultsUntouchedAndRunsAgainNextLaunch() throws {
            let fixture = LegacyDefaultsFixture()
            defer { fixture.cleanUp() }
            fixture.set(true, LegacyDefaults.startHidden)
            let before = fixture.persisted
            enum Interrupted: Error { case write }
            #expect(throws: Interrupted.self) {
                try ConfigMigrator.run(url: fixture.url, suite: fixture.suite, domainName: fixture.suiteName) { _, _ in throw Interrupted.write }
            }
            #expect(!FileManager.default.fileExists(atPath: fixture.url.path))
            #expect(fixture.suite.integer(forKey: "configMigrationVersion") == 0)
            #expect(NSDictionary(dictionary: before).isEqual(to: fixture.persisted))

            #expect(try ConfigMigrator.run(url: fixture.url, suite: fixture.suite, domainName: fixture.suiteName) == .migrated)
            #expect(try TOMLDocument(String(contentsOf: fixture.url, encoding: .utf8)).value(at: ["start-hidden"]) == .boolean(true))
            var after = fixture.persisted
            #expect(after.removeValue(forKey: "configMigrationVersion") as? Int == 1)
            #expect(NSDictionary(dictionary: before).isEqual(to: after))
        }

        @Test func failedReparseDoesNotRecordCompletion() throws {
            let fixture = LegacyDefaultsFixture()
            defer { fixture.cleanUp() }
            fixture.set(true, LegacyDefaults.startHidden)
            #expect(throws: (any Error).self) {
                try ConfigMigrator.run(url: fixture.url, suite: fixture.suite, domainName: fixture.suiteName) { _, url in
                    try ConfigMigrator.writeFile(Data("broken = [".utf8), to: url)
                }
            }
            #expect(fixture.suite.integer(forKey: "configMigrationVersion") == 0)
        }

        @Test func freshProfileStaysSparseAndCompletedMigrationDoesNotRepeat() throws {
            let fixture = LegacyDefaultsFixture()
            defer { fixture.cleanUp() }
            #expect(try ConfigMigrator.migratedSource(suite: fixture.suite, domainName: fixture.suiteName) == nil)
            #expect(try ConfigMigrator.run(url: fixture.url, suite: fixture.suite, domainName: fixture.suiteName) == .migrated)
            #expect(!FileManager.default.fileExists(atPath: fixture.url.path))
            fixture.set(true, LegacyDefaults.startHidden)
            #expect(try ConfigMigrator.run(url: fixture.url, suite: fixture.suite, domainName: fixture.suiteName) == .alreadyMigrated)
            #expect(!FileManager.default.fileExists(atPath: fixture.url.path))
        }

        @Test func deletedLegacyKeybindReferencesRemainUnresolved() throws {
            let fixture = LegacyDefaultsFixture()
            defer { fixture.cleanUp() }
            let missing = try #require(UUID(uuidString: "B3C83D94-C249-47CD-8517-C887B0DDEB07"))
            fixture.set([.keybindReference(missing)], LegacyDefaults.radialMenuActions)
            fixture.set([LegacyGestureBinding(kind: .swipeUp, action: .singleAction(.keybindReference(missing)))], LegacyDefaults.gestures)
            try ConfigMigrator.run(url: fixture.url, suite: fixture.suite, domainName: fixture.suiteName)
            let settings = try Profile(String(contentsOf: fixture.url, encoding: .utf8))
            let target = settings[\.radialMenuActions][0].target
            #expect(target == .keyBinding("missing-" + missing.uuidString.lowercased()))
            #expect(settings[\.gestures][0].target == target)
            #expect(settings.issues.isEmpty)
        }

        @Test func sparseDefaultTopCycleReferenceResolvesAfterMigration() throws {
            let fixture = LegacyDefaultsFixture()
            defer { fixture.cleanUp() }
            let top = try #require(LegacyDefaults.keybinds.defaultValue.first { $0.keybind == [.kVK_UpArrow] })
            let topID = try #require(top.id)
            fixture.set([.keybindReference(topID)], LegacyDefaults.radialMenuActions)
            fixture.set([LegacyGestureBinding(kind: .swipeUp, action: .singleAction(.keybindReference(topID)))], LegacyDefaults.gestures)
            try ConfigMigrator.run(url: fixture.url, suite: fixture.suite, domainName: fixture.suiteName)
            let settings = try Profile(String(contentsOf: fixture.url, encoding: .utf8))
            #expect(settings.value(at: ["key", "bindings"]) != nil)
            let source = try String(contentsOf: fixture.url, encoding: .utf8)
            #expect(source.contains("cycle = [\n    { action ="))
            #expect(!source.contains("[[key.bindings.cycle]]"))
            let linked = try #require(settings[\.keyBindings].first { $0.configID != nil })
            let name = try #require(linked.configID)
            #expect(name == ConfigurationIdentity.kebabCase(String(localized: "Top Cycle")))
            #expect(settings[\.keyBindings].filter { $0.configID != nil }.count == 1)
            #expect(settings[\.radialMenuActions][0].target == .keyBinding(name))
            #expect(settings[\.gestures][0].target == .keyBinding(name))
        }

        @Test func legacyNoSelectionBeforeLinkedKeybindDoesNotShiftReference() throws {
            let fixture = LegacyDefaultsFixture()
            defer { fixture.cleanUp() }
            let linked = KeyBinding(.leftHalf, keybind: KeyCombination(names: ["a"]))
            fixture.set([LegacyWindowAction(KeyBinding(.noSelection)), LegacyWindowAction(linked)], LegacyDefaults.keybinds)
            fixture.set([.keybindReference(linked.id)], LegacyDefaults.radialMenuActions)
            try ConfigMigrator.run(url: fixture.url, suite: fixture.suite, domainName: fixture.suiteName)
            let settings = try Profile(String(contentsOf: fixture.url, encoding: .utf8))
            #expect(settings[\.keyBindings].count == 1)
            #expect(settings[\.keyBindings][0].target.semanticKey == ActionTarget.windowAction(WindowAction(.leftHalf)).semanticKey)
            #expect(try settings[\.radialMenuActions][0].target == .keyBinding(#require(settings[\.keyBindings][0].configID)))
        }

        @Test func interruptedMigrationThatAlreadyWroteTheFileFinishesOnTheNextLaunch() throws {
            let fixture = LegacyDefaultsFixture()
            defer { fixture.cleanUp() }
            fixture.set(true, LegacyDefaults.startHidden)
            enum Interrupted: Error { case afterWrite }
            #expect(throws: Interrupted.self) {
                try ConfigMigrator.run(url: fixture.url, suite: fixture.suite, domainName: fixture.suiteName) { data, url in
                    try ConfigMigrator.writeFile(data, to: url)
                    throw Interrupted.afterWrite
                }
            }
            let written = try Data(contentsOf: fixture.url)
            #expect(fixture.suite.integer(forKey: "configMigrationVersion") == 0)

            #expect(try ConfigMigrator.run(url: fixture.url, suite: fixture.suite, domainName: fixture.suiteName) == .migrated)
            #expect(fixture.suite.integer(forKey: "configMigrationVersion") == 1)
            #expect(fixture.suite.string(forKey: "configMigrationPendingDigest") == nil)
            #expect(try Data(contentsOf: fixture.url) == written)
            #expect(try ConfigMigrator.run(url: fixture.url, suite: fixture.suite, domainName: fixture.suiteName) == .existingFile)
        }

        @Test func aFileEditedAfterAnInterruptedMigrationIsNeverTreatedAsMigrated() throws {
            let fixture = LegacyDefaultsFixture()
            defer { fixture.cleanUp() }
            fixture.set(true, LegacyDefaults.startHidden)
            enum Interrupted: Error { case afterWrite }
            _ = try? ConfigMigrator.run(url: fixture.url, suite: fixture.suite, domainName: fixture.suiteName) { data, url in
                try ConfigMigrator.writeFile(data, to: url)
                throw Interrupted.afterWrite
            }
            try "# edited elsewhere\n".write(to: fixture.url, atomically: true, encoding: .utf8)
            #expect(try ConfigMigrator.run(url: fixture.url, suite: fixture.suite, domainName: fixture.suiteName) == .existingFile)
            #expect(fixture.suite.string(forKey: "configMigrationPendingDigest") == nil)
        }

        @Test func coloursMigrateWithAlphaAndColorSpace() throws {
            let fixture = LegacyDefaultsFixture()
            defer { fixture.cleanUp() }
            fixture.set(Color(.sRGB, red: 0x12 / 255, green: 0x34 / 255, blue: 0x56 / 255, opacity: 0.5), LegacyDefaults.customAccentColor)
            fixture.set(Color(.displayP3, red: 1, green: 0, blue: 0), LegacyDefaults.gradientColor)
            try ConfigMigrator.run(url: fixture.url, suite: fixture.suite, domainName: fixture.suiteName)
            let document = try TOMLDocument(String(contentsOf: fixture.url, encoding: .utf8))
            #expect(document.value(at: ["accent-color", "color"]) == .string("#12345680"))
            #expect(document.value(at: ["accent-color", "gradient-color"]) == .string("#FF0000"))
        }

        @Test func deletingAnExistingFileDoesNotReimportStaleDefaults() throws {
            let fixture = LegacyDefaultsFixture()
            defer { fixture.cleanUp() }
            fixture.set(true, LegacyDefaults.startHidden)
            try FileManager.default.createDirectory(at: fixture.url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try "".write(to: fixture.url, atomically: true, encoding: .utf8)
            #expect(try ConfigMigrator.run(url: fixture.url, suite: fixture.suite, domainName: fixture.suiteName) == .existingFile)
            fixture.cleanUpFile()
            #expect(try ConfigMigrator.run(url: fixture.url, suite: fixture.suite, domainName: fixture.suiteName) == .alreadyMigrated)
            #expect(!FileManager.default.fileExists(atPath: fixture.url.path))
        }

        @Test func resumingAnInterruptedMigrationRemapsStashRecords() throws {
            let fixture = LegacyDefaultsFixture()
            defer { fixture.cleanUp() }
            let legacyStash = KeyBinding(.stash, keybind: KeyCombination(names: ["s"]))
            fixture.set([LegacyWindowAction(legacyStash)], LegacyDefaults.keybinds)
            let stashKey = Defaults.Key<[CGWindowID: WindowAction]>("stashManagerStashed", default: [:], suite: fixture.suite)
            let legacy = try #require(legacyStash.target.legacyWindowAction).withRuntimeID(legacyStash.id)
            Defaults[stashKey] = [314: legacy]
            enum Interrupted: Error { case afterWrite }
            #expect(throws: Interrupted.self) {
                try ConfigMigrator.run(url: fixture.url, suite: fixture.suite, domainName: fixture.suiteName) { data, url in
                    try ConfigMigrator.writeFile(data, to: url)
                    throw Interrupted.afterWrite
                }
            }
            #expect(Defaults[stashKey][314]?.id == legacy.id)
            #expect(try ConfigMigrator.run(url: fixture.url, suite: fixture.suite, domainName: fixture.suiteName) == .migrated)
            let document = try TOMLDocument(String(contentsOf: fixture.url, encoding: .utf8))
            let migrated = try [KeyBinding].decodeIdentified(#require(document.value(at: ["key", "bindings"])))
            #expect(Defaults[stashKey][314]?.id == migrated[0].target.legacyWindowAction?.id)
            #expect(Defaults[stashKey][314]?.id != legacy.id)
        }

        @Test func recoveredStashRecordsFollowTheirActionToItsMigratedIdentity() throws {
            let fixture = LegacyDefaultsFixture()
            defer { fixture.cleanUp() }
            let legacyStash = KeyBinding(.stash, keybind: KeyCombination(names: ["s"]))
            let cycleChild = WindowAction(.stash)
            let legacyCycle = KeyBinding("Cycle", cycle: [WindowAction(.leftHalf), cycleChild], keybind: KeyCombination(names: ["c"]))
            fixture.set([LegacyWindowAction(legacyStash), LegacyWindowAction(legacyCycle)], LegacyDefaults.keybinds)
            let stashKey = Defaults.Key<[CGWindowID: WindowAction]>("stashManagerStashed", default: [:], suite: fixture.suite)
            let topLevel = try #require(legacyStash.target.legacyWindowAction).withRuntimeID(legacyStash.id)
            Defaults[stashKey] = [314: topLevel, 315: cycleChild]

            try ConfigMigrator.run(url: fixture.url, suite: fixture.suite, domainName: fixture.suiteName)
            let document = try TOMLDocument(String(contentsOf: fixture.url, encoding: .utf8))
            let migrated = try [KeyBinding].decodeIdentified(#require(document.value(at: ["key", "bindings"])))
            let migratedStash = try #require(migrated[0].target.legacyWindowAction)
            guard case let .cycle(cycle)? = migrated[1].target.legacyWindowAction?.kind,
                  case let .windowAction(migratedChild) = cycle.steps[1] else {
                Issue.record("Expected a migrated cycle with a stash step")
                return
            }
            #expect(migratedStash.id != topLevel.id)
            #expect(Defaults[stashKey][314]?.id == migratedStash.id)
            #expect(Defaults[stashKey][315]?.id == migratedChild.id)
            let restarted = try [KeyBinding].decodeIdentified(#require(document.value(at: ["key", "bindings"])))
            #expect(restarted[0].target.legacyWindowAction?.id == migratedStash.id)
        }

        @Test func duplicateLegacyIDsAndAnUnconvertibleDelayDoNotStopTheRestOfTheMigration() throws {
            let fixture = LegacyDefaultsFixture()
            defer { fixture.cleanUp() }
            let id = UUID()
            let twin = LegacyWindowAction(action: WindowAction(.maximize), id: id, configID: "same")
            let other = LegacyWindowAction(action: WindowAction(.maximize), id: UUID())
            fixture.set([twin, twin, other], LegacyDefaults.keybinds)
            fixture.set([.keybindReference(id)], LegacyDefaults.radialMenuActions)
            fixture.set(7, LegacyDefaults.radialMenuThickness)
            fixture.set(1e19, LegacyDefaults.triggerDelay)

            let source = try #require(try ConfigMigrator.migratedSource(suite: fixture.suite, domainName: fixture.suiteName))
            let document = try TOMLDocument(source)
            #expect(document.value(at: ["radial-menu", "thickness"]) == .float(7))
            #expect(document.value(at: ["trigger", "delay"]) == nil)
            #expect(try TOMLCodecs.decodeArray(#require(document.value(at: ["key", "bindings"]))).count == 3)
        }

        @Test func legacyCyclesNestedInsideCyclesLoseOnlyTheInnerCycle() throws {
            let fixture = LegacyDefaultsFixture()
            defer { fixture.cleanUp() }
            let inner = WindowAction("Inner", cycle: [WindowAction(.leftHalf)])
            let outer = WindowAction("Outer", cycle: [WindowAction(.rightHalf), inner, WindowAction(.maximize)])
            fixture.set([LegacyWindowAction(action: outer, id: UUID(), keybind: [.kVK_ANSI_A]), LegacyWindowAction(action: WindowAction(.maximize), id: UUID())], LegacyDefaults.keybinds)
            fixture.set(7, LegacyDefaults.radialMenuThickness)
            let source = try #require(try ConfigMigrator.migratedSource(suite: fixture.suite, domainName: fixture.suiteName))
            let document = try TOMLDocument(source)
            let bindings = try [KeyBinding].decodeTOML(#require(document.value(at: ["key", "bindings"])))
            #expect(bindings.count == 2)
            guard case let .windowAction(action) = bindings[0].target, case let .cycle(cycle) = action.kind else {
                Issue.record("Expected a cycle")
                return
            }
            #expect(cycle.steps.compactMap(\.resolvedDirection) == [.rightHalf, .maximize])
            #expect(document.value(at: ["radial-menu", "thickness"]) == .float(7))
        }
    }
}

private extension ActionTarget {
    var legacyWindowAction: WindowAction? {
        if case let .windowAction(action) = self { action } else { nil }
    }
}
