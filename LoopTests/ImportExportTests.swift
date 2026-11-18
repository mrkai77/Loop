//
//  ImportExportTests.swift
//  LoopTests
//
//  Created by Kai Azim on 2026-11-16.
//

import AppKit
import Foundation
@testable import Loop
import Testing
import Tome
import TOML

extension StoreTests {
    struct ImportExportTests {
        @Test func losslessFullConfigurationRoundTripKeepsLinksAndReferences() throws {
            let source = """
            # My window profile
            unknown = "preserved"
            [[key.bindings]]
            id = "portrait"
            keys = ["ctrl", "a"]
            link-trigger-key = false
            action = "custom"
            name = "Portrait"
            size = "preserve"
            position = {
                x = "14pt",
                y = "-23pt",
            }
            [[key.bindings.cycle]]
            action = "left-half"
            [trigger]
            keys = "alt"
            [[radial-menu.bindings]]
            action = "key:portrait"
            [[gestures.bindings]]
            fingers = 3
            kind = "pinch"
            zone = "title-bar"
            action = "key:portrait"
            [preview]
            corner-radius   = 17 # Keep this comment and spacing
            """ + "\n"
            let original = try Profile(source)
            let exported = Tome.serializedDocument
            #expect(exported == source)
            let originalBinding = try #require(original[\.keyBindings].first)
            let destination = try Profile("[icon]\nshow-in-dock = true\n[obsolete]\nvalue = 1\n")
            #expect(try Migrator.importConfiguration(exported, confirmed: true))
            #expect(Tome.serializedDocument == source)
            #expect(destination[\.showDockIcon] == false)
            #expect(destination.value(at: ["obsolete"]) == nil)
            let action = try #require(destination[\.keyBindings].first)
            #expect(action.bypassTriggerKey == true)
            #expect(action.configID == "portrait")
            #expect(action.id == originalBinding.id)
            #expect(action.target.semanticKey == originalBinding.target.semanticKey)
            #expect(destination[\.radialMenuBindings].first?.target == .reference(.init(.key, "portrait")))
            #expect(destination[\.gestureBindings].first?.target == .reference(.init(.key, "portrait")))
            #expect(try destination.fileContents() == source)
        }

        @Test func validationListsEveryProblemBeforeAnythingIsConfirmed() throws {
            let settings = try Profile("")
            // Keys join validation once they are read
            _ = (settings[\.showDockIcon], settings[\.previewCornerRadius])
            let invalid = "[icon]\nshow-in-dock = \"yes\"\n[preview]\ncorner-radius = \"bad\"\n"
            let paths = Set(Migrator.validateConfiguration(invalid).map(\.path))
            #expect(paths == ["icon.show-in-dock", "preview.corner-radius"])
            #expect(Migrator.validateConfiguration("[icon]\nshow-in-dock = true\n").isEmpty)
            #expect(settings.serialized == "")
        }

        @Test func invalidKeysAreRejectedAndImportChangesNothing() throws {
            let source = "[icon]\nshow-in-dock = true\n"
            let settings = try Profile(source)
            _ = (settings[\.previewCornerRadius], settings[\.triggerKey])
            let invalid = "[icon]\nshow-in-dock = \"yes\"\n[preview]\ncorner-radius = \"bad\"\n"
            #expect(throws: (any Error).self) { try Migrator.importConfiguration(invalid, confirmed: true) }
            #expect(settings[\.showDockIcon])
            #expect(settings.serialized == source)
            #expect(try settings.fileContents() == source)
            #expect(throws: (any Error).self) { try Migrator.importConfiguration("[preview\n", confirmed: true) }
            #expect(throws: (any Error).self) { try Migrator.importConfiguration("trigger = false\n", confirmed: true) }
            #expect(throws: (any Error).self) { try Migrator.importConfiguration("[trigger]\nkeys = \"ctrl+a\"\n", confirmed: true) }
            #expect(settings.serialized == source)
        }

        @Test func cancelDoesNotChangeTriggerOrAnyBytes() throws {
            let source = "[trigger]\nkeys = \"alt\"\n"
            let settings = try Profile(source)
            let saved = try Migrator.decodeJSON(Data(Self.issue1080.utf8))
            #expect(try !Migrator.applyJSON(saved, decision: .cancel))
            #expect(try !Migrator.importConfiguration("", confirmed: false))
            #expect(settings[\.triggerKey] == [.kVK_Option])
            #expect(settings.serialized == source)
            #expect(try String(contentsOf: settings.url, encoding: .utf8) == source)
        }

        @Test func currentAndPre12JSONSupportMergeReplaceAndExplicitUnlinkedActions() throws {
            let expected = ActionTarget.windowAction(WindowAction(kind: .custom(.init(name: "Test", size: .preserve, position: .coordinates(x: ScreenLength(5), y: ScreenLength(7))))))
            var custom = Develop.WindowAction(.custom, keybind: [.kVK_ANSI_A], name: "Test")
            custom.bypassTriggerKey = true
            custom.unit = .percentage
            custom.sizeMode = .preserve
            custom.positionMode = .coordinates
            custom.xPoint = 5
            custom.yPoint = 7
            let saved = Develop.KeybindsFile(version: "1.4.2", triggerKey: [.kVK_Function], actions: [custom])
            let current = try Migrator.decodeJSON(Data(Develop.json(saved).utf8))
            let legacy = try Migrator.decodeJSON(Data(Develop.json(saved.actions).utf8))
            #expect(legacy.triggerKey == nil)
            #expect(current.bindings.first?.target.semanticKey == expected.semanticKey)
            #expect(current.bindings.first?.keys == KeyCombination(names: ["a"]))
            let settings = try Profile()
            try settings.set([KeyBinding(.rightHalf, keys: KeyCombination(names: ["b"]))], for: \.keyBindings)
            #expect(try Migrator.applyJSON(current, decision: .merge))
            #expect(settings[\.keyBindings].count == 2)
            #expect(settings[\.triggerKey] == [.kVK_Function])
            #expect(try Migrator.applyJSON(legacy, decision: .erase))
            #expect(settings[\.keyBindings].count == 1)
            #expect(settings[\.keyBindings][0].bypassTriggerKey == true)
            try settings.flush()
        }

        @Test func mergeKeepsAnExistingBindingOnTheSameKeysUnlessItIsADifferentKindOfTarget() throws {
            func custom(_ width: Double, _ height: Double, _ anchor: CustomWindowActionAnchor) -> ActionTarget {
                .windowAction(WindowAction(kind: .custom(.init(name: "Wide", size: .custom(width: ScreenLength(width), height: ScreenLength(height)), position: .anchor(anchor)))))
            }
            let a = KeyCombination(names: ["a"])
            // (existing, imported, bindings left after the merge)
            let cases: [(KeyBinding, KeyBinding, Int)] = [
                (KeyBinding(.leftHalf, keys: a), KeyBinding(.rightHalf, keys: a), 1),
                (KeyBinding(keys: a, target: custom(75, 80, .center)), KeyBinding(keys: a, target: custom(25, 50, .bottomLeft)), 1),
                (KeyBinding(keys: a, target: .reference(.init(.key, "missing"))), KeyBinding(.rightHalf, keys: a), 2)
            ]
            for (existing, imported, count) in cases {
                let settings = try Profile()
                try settings.set([existing], for: \.keyBindings)
                #expect(try Migrator.applyJSON(ImportedKeybinds(triggerKey: nil, bindings: [imported]), decision: .merge))
                #expect(settings[\.keyBindings].count == count)
                #expect(settings[\.keyBindings][0].target.semanticKey == existing.target.semanticKey)
                if count == 2 { #expect(settings[\.keyBindings][1].target.semanticKey == imported.target.semanticKey) }
            }
        }

        @Test func rectangleRetainsCompleteStandaloneShortcut() throws {
            let json = #"{"shortcuts":{"leftHalf":{"keyCode":123,"modifierFlags":786432},"unknown":{"keyCode":-1,"modifierFlags":0}}}"#
            let imported = try Migrator.decodeJSON(Data(json.utf8))
            let action = try #require(imported.bindings.first)
            #expect(imported.bindings.count == 1)
            #expect(action.target.semanticKey == ActionTarget.windowAction(WindowAction(.leftHalf)).semanticKey)
            #expect(action.keys == [.kVK_Control, .kVK_Option, .kVK_LeftArrow])
            #expect(action.bypassTriggerKey == true)
            let settings = try Profile()
            #expect(try Migrator.applyJSON(imported, decision: .erase))
            #expect(settings[\.keyBindings].first?.keys == action.keys)
            try settings.flush()
        }

        @Test func issue1080OriginalJSONImportsAllActionsWithoutInventingMissingLinkData() throws {
            // The issue's file has no bypassTriggerKey field, so its link state can't be recovered
            let saved = try Migrator.decodeJSON(Data(Self.issue1080.utf8))
            #expect(saved.bindings.count == 9)
            #expect(saved.triggerKey == [.kVK_Function])
            let settings = try Profile()
            #expect(try Migrator.applyJSON(saved, decision: .erase))
            #expect(settings[\.keyBindings].count == 9)
            #expect(settings[\.keyBindings].first?.keys == KeyCombination(names: ["c", "alt", "ctrl"]))
            let resolver = BindingResolutionSnapshot(keyBindings: settings[\.keyBindings], gestureBindings: [], radialMenuBindings: [])
            #expect(resolver.action(for: settings[\.keyBindings][1].target).customDimensions?.width?.value == 50)
            #expect(resolver.action(for: settings[\.keyBindings][2].target).resolvedCycleSteps?.count == 3)
            let exported = Tome.serializedDocument
            #expect(try Migrator.importConfiguration(exported, confirmed: true))
            #expect(Tome.serializedDocument == exported)
        }

        @Test func cyclicAndWholeMenuReferencesImportAndResolveToNoAction() throws {
            for source in [
                "[[key.bindings]]\nid=\"a\"\naction=\"key:a\"\n",
                "[[key.bindings]]\nid=\"a\"\naction=\"gesture:g\"\n[[gestures.bindings]]\nid=\"g\"\nkind=\"swipe-left\"\naction=\"radial-menu:r\"\n[[radial-menu.bindings]]\nid=\"r\"\naction=\"key:a\"\n",
                "[[key.bindings]]\naction=\"gesture:g\"\n[[gestures.bindings]]\nid=\"g\"\nkind=\"radial-menu\"\n"
            ] {
                let settings = try Profile()
                #expect(try Migrator.importConfiguration(source, confirmed: true))
                let resolver = BindingResolutionSnapshot(keyBindings: settings[\.keyBindings], gestureBindings: settings[\.gestureBindings], radialMenuBindings: settings[\.radialMenuBindings])
                #expect(settings[\.keyBindings].allSatisfy { resolver.action(for: $0.target).direction == .noAction })
            }
        }

        @Test func nestedCyclesAreRejectedOnJSONImport() throws {
            func json(depth: Int) -> Data {
                let entry = "{\"direction\":\"Maximize\",\"keybind\":[0]}"
                let text = "[" + String(repeating: "{\"direction\":\"Cycle\",\"keybind\":[0],\"cycle\":[", count: depth) + entry + String(repeating: "]}", count: depth) + "]"
                return Data(text.utf8)
            }
            let flat = try Migrator.decodeJSON(json(depth: 1))
            #expect(flat.bindings.count == 1)
            _ = try flat.bindings.encodeTOML()
            #expect(throws: MigratorError.self) { try Migrator.decodeJSON(json(depth: 2)) }
            #expect(throws: MigratorError.self) { try Migrator.importLoopLegacyKeybinds(from: json(depth: 2)) }
            #expect(throws: (any Error).self) { try Migrator.decodeJSON(json(depth: 20)) }
            let wrapped = Data("{\"version\":\"1\",\"actions\":\(String(decoding: json(depth: 2), as: UTF8.self))}".utf8)
            #expect(throws: MigratorError.self) { try Migrator.decodeJSON(wrapped) }
        }

        /// Verbatim JSON fixture from https://github.com/mrkai77/Loop/issues/1080
        private static let issue1080 = #"{"actions":[{"direction":"Center","keybind":[8,58,59]},{"anchor":8,"direction":"Custom","height":50,"keybind":[51,58,59],"name":"Reasonable Size","positionMode":0,"sizeMode":0,"unit":1,"width":50},{"cycle":[{"direction":"BottomHalf","keybind":[]},{"direction":"BottomThird","keybind":[]},{"direction":"BottomTwoThirds","keybind":[]}],"direction":"Cycle","keybind":[58,59,125],"name":"Bottom Cycle"},{"cycle":[{"direction":"LeftHalf","keybind":[]},{"direction":"LeftThird","keybind":[]},{"direction":"LeftThreeFourths","keybind":[]},{"direction":"LeftTwoThirds","keybind":[]}],"direction":"Cycle","keybind":[58,59,123],"name":"Left Cycle"},{"cycle":[{"direction":"RightHalf","keybind":[]},{"direction":"RightThird","keybind":[]},{"direction":"RightThreeFourths","keybind":[]},{"direction":"RightTwoThirds","keybind":[]}],"direction":"Cycle","keybind":[58,59,124],"name":"Right Cycle"},{"cycle":[{"direction":"TopHalf","keybind":[]},{"direction":"TopThird","keybind":[]},{"direction":"TopTwoThirds","keybind":[]}],"direction":"Cycle","keybind":[58,59,126],"name":"Top Cycle"},{"direction":"Maximize","keybind":[36,58,59]},{"direction":"NextScreen","keybind":[56,58,59,124]},{"direction":"PreviousScreen","keybind":[56,58,59,123]}],"triggerKey":[63],"version":"1.4.2"}"#
    }
}
