//
//  SettingsSchemaTests.swift
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
    struct TOMLSchemaTests {
        @Test func paddingRoundTrips() throws {
            let padding = PaddingConfiguration(window: 7, externalBar: 9, top: 11, bottom: 13, right: 15, left: 17, mode: .custom)
            #expect(try PaddingConfiguration.decodeTOML(padding.encodeTOML()) == padding)
            #expect(try PaddingConfiguration.zero.encodeTOML() == .table([:]))
            #expect(try PaddingConfiguration.decodeTOML(.table(["gap": .float(8)])).window == 8)
            let encoded = try TOMLCodecs.decodeTable(padding.encodeTOML())
            #expect(encoded["mode"] == .string("custom"))
            #expect(encoded["gap"] == .float(7))
            #expect(encoded["custom-menu-bar"] == .float(9))
            #expect(encoded["edges"] == .table(["top": .float(11), "bottom": .float(13), "left": .float(17), "right": .float(15)]))
            let decoded = try PaddingConfiguration.decodeTOML(.table(["edges": .table(["top": .integer(5)]), "custom-menu-bar": .integer(2)]))
            #expect(decoded.top == 5 && decoded.bottom == 0 && decoded.externalBar == 2)
            for old in ["windowGaps", "externalBar", "top", "left"] {
                #expect(try PaddingConfiguration.decodeTOML(.table([old: .float(8)])) == .zero)
            }
            #expect(throws: (any Error).self) { try PaddingConfiguration.decodeTOML(.table(["edges": .float(1)])) }
            #expect(throws: (any Error).self) { try PaddingConfiguration.decodeTOML(.table(["mode": .string("customMode")])) }
        }

        @Test func geometryRetainsOmittedDefaultsAndAcceptsLengthSpellings() throws {
            let minimal = try TargetCoding.decodeAction(["action": .string("custom")])
            #expect(minimal.size == .custom(width: nil, height: nil))
            #expect(minimal.position == .anchor(.none))
            let new = try TargetCoding.decodeAction(["action": .string("custom"), "size": .table(["width": .string("250px"), "height": .string("100pt")]), "position": .table(["x": .string("25pt"), "y": .string("50pt")])])
            #expect(try TargetCoding.encode(.windowAction(new))["size"] == .table(["width": .string("250pt"), "height": .string("100pt")]))
            let numbers = try TargetCoding.decodeAction(["action": .string("custom"), "size": .table(["width": .integer(250), "height": .float(100.5)]), "position": .table(["x": .integer(-25), "y": .float(50)])])
            #expect(numbers.size == .custom(width: ScreenLength(250, unit: .points), height: ScreenLength(100.5, unit: .points)))
            #expect(numbers.position == .coordinates(x: ScreenLength(-25, unit: .points), y: ScreenLength(50, unit: .points)))
            let quoted = try TargetCoding.decodeAction(["action": .string("custom"), "size": .table(["width": .string("250pt"), "height": .string("100.5pt")]), "position": .table(["x": .string("-25pt"), "y": .string("50pt")])])
            #expect(numbers.semanticKey == quoted.semanticKey)
            #expect(try TargetCoding.encode(.windowAction(numbers))["size"] == .table(["width": .string("250pt"), "height": .string("100.5pt")]))
        }

        @Test func preserveAndInitialAreStringsAndDropFallbackDimensions() throws {
            for (kind, mode) in [("custom", "preserve"), ("custom", "initial"), ("stash", "preserve"), ("stash", "initial")] {
                let action = try TargetCoding.decodeAction(["action": .string(kind), "size": .string(mode)])
                #expect(action.size == (mode == "preserve" ? .preserve : .initial))
                #expect(action.customDimensions == .init())
                #expect(try TargetCoding.encode(.windowAction(action))["size"] == .string(mode))
                var withFallback = action
                withFallback.customDimensions = .init(width: ScreenLength(250, unit: .points), height: ScreenLength(100, unit: .points))
                #expect(try TargetCoding.encode(.windowAction(withFallback)) == TargetCoding.encode(.windowAction(action)))
            }
        }

        @Test func sizeIsAStringOrATableAndModeIsGone() throws {
            let table = try TargetCoding.decodeAction(["action": .string("custom"), "size": .table(["width": .string("50%")])])
            #expect(table.size == .custom(width: ScreenLength(50), height: nil))
            for size: TOMLValue in [
                .string("custom"), .string("Preserve"), .integer(3),
                .table(["mode": .string("preserve")]),
                .table(["mode": .string("custom"), "width": .string("50%")]),
                .table(["depth": .string("50%")])
            ] {
                #expect(throws: (any Error).self) { try TargetCoding.decode(["action": .string("custom"), "size": size]) }
            }
        }

        @Test func positionIsAnAnchorOrATable() throws {
            let anchor = try TargetCoding.decodeAction(["action": .string("custom"), "position": .string("bottom-left")])
            #expect(anchor.position == .anchor(.bottomLeft))
            #expect(try TargetCoding.encode(.windowAction(anchor))["position"] == .string("bottom-left"))
            let center = try TargetCoding.decodeAction(["action": .string("custom"), "position": .string("center")])
            #expect(center.position == .anchor(.center))
            let table = try TargetCoding.decodeAction(["action": .string("custom"), "position": .table(["x": .string("10%")])])
            #expect(table.position == .coordinates(x: ScreenLength(10), y: nil))
            #expect(try TargetCoding.encode(.windowAction(table))["position"] == .table(["x": .string("10%")]))
            for position: TOMLValue in [.string("middle"), .table(["z": .string("10%")]), .table(["x": .string("left")]), .table(["x": .string("10%"), "anchor": .string("center")])] {
                #expect(throws: (any Error).self) { try TargetCoding.decode(["action": .string("custom"), "position": position]) }
            }
        }

        @Test func screenLengthSpellings() throws {
            func decode(_ value: TOMLValue) throws -> ScreenLength {
                try TOMLDecoder().decodeFromValue(ScreenLength.self, from: value)
            }
            #expect(try decode(.string("25%")) == ScreenLength(25))
            #expect(try decode(.string("250pt")) == ScreenLength(250, unit: .points))
            #expect(try decode(.string("250px")) == ScreenLength(250, unit: .points))
            #expect(try decode(.string("-12.5pt")) == ScreenLength(-12.5, unit: .points))
            #expect(try decode(.integer(250)) == ScreenLength(250, unit: .points))
            #expect(try decode(.float(100.5)) == ScreenLength(100.5, unit: .points))
            for invalid: TOMLValue in [.string("25"), .string("wide"), .string("%"), .boolean(true)] {
                #expect(throws: (any Error).self) { try decode(invalid) }
            }
            #expect(try TOMLCodecs.decodeTable(TOMLEncoder().encodeToValue(["w": ScreenLength(25), "h": ScreenLength(250.5, unit: .points)])) == ["w": .string("25%"), "h": .string("250.5pt")])
            #expect(ScreenLength(250, unit: .points).configurationString() == "250pt")
        }

        @Test func aReferenceIsAnActionNamingAnotherBinding() throws {
            #expect(try TargetCoding.decode(["action": .string("key:wide")]) == .reference(.init(.key, "wide")))
            #expect(try TargetCoding.decode(["action": .string("gesture:swipe")]) == .reference(.init(.gesture, "swipe")))
            #expect(try TargetCoding.decode(["action": .string("radial-menu:top")]) == .reference(.init(.radialMenu, "top")))
            #expect(throws: (any Error).self) { try TargetCoding.decode(["action": .string("radial-menu")]) }
            #expect(try TargetCoding.encode(.reference(.init(.key, "wide"))) == ["action": .string("key:wide")])
            #expect(try TargetCoding.encode(.reference(.init(.radialMenu, "top"))) == ["action": .string("radial-menu:top")])
            #expect(throws: (any Error).self) { try TargetCoding.decode([:]) }
            #expect(throws: (any Error).self) { try TargetCoding.decode(["action": .string("key:Not Valid!")]) }
            #expect(throws: (any Error).self) { try TargetCoding.decode(["action": .string("window:wide")]) }
        }

        @Test func anInlineCycleStepCannotBeACycle() throws {
            let nested: [String: TOMLValue] = [
                "action": .string("cycle"),
                "cycle": .array([.table(["action": .string("left-half")]), .table(["action": .string("cycle"), "cycle": .array([.table(["action": .string("maximize")])])])])
            ]
            #expect(throws: (any Error).self) { try TargetCoding.decode(nested) }
            let cycle = WindowAction(kind: .cycle(.init(steps: [.windowAction(WindowAction(kind: .cycle(.init())))])))
            #expect(throws: (any Error).self) { try TargetCoding.encode(.windowAction(cycle)) }
            let flat: [String: TOMLValue] = ["action": .string("cycle"), "cycle": .array([.table(["action": .string("left-half")]), .table(["action": .string("stash")]), .table(["action": .string("key:other")])])]
            #expect(try TargetCoding.decodeAction(flat).direction == .cycle)

            let profile = try Profile("""
            [[key.bindings]]
            keys = "a"
            action = "cycle"
            cycle = [{ action = "cycle", cycle = [{ action = "maximize" }] }]
            """)
            Tome.refresh(\.keyBindings)
            #expect(profile.issues.contains { $0.path == "key.bindings" })
        }

        @Test func everyBindingKindRoundTripsThroughTheFile() throws {
            let custom = WindowAction(kind: .custom(.init(name: "Custom", size: .custom(width: ScreenLength(40), height: nil), position: .coordinates(x: nil, y: ScreenLength(5, unit: .points)))))
            let stash = WindowAction(kind: .stash(.init(name: "Stash", size: .preserve, position: .anchor(.topRight))))
            let cycle = WindowAction(kind: .cycle(.init(name: "Cycle", steps: [.windowAction(custom), .windowAction(WindowAction(.leftHalf)), .reference(.init(.key, "wide"))])))
            let keys = [
                KeyBinding(configID: "wide", keys: KeyCombination(names: ["a"]), bypassTriggerKey: true, target: .windowAction(custom)),
                KeyBinding(keys: KeyCombination(names: ["b"]), target: .windowAction(cycle)),
                KeyBinding(keys: KeyCombination(names: ["c"]), target: .reference(.init(.gesture, "swipe"))),
                KeyBinding(target: .windowAction(WindowAction(.noAction)))
            ]
            let decodedKeys = try [KeyBinding].decodeTOML(keys.encodeTOML())
            #expect(decodedKeys.map(\.target.semanticKey) == keys.map(\.target.semanticKey))
            #expect(decodedKeys.map(\.keys) == keys.map(\.keys))
            #expect(decodedKeys.map(\.configID) == keys.map(\.configID))
            #expect(decodedKeys.map(\.bypassTriggerKey) == keys.map(\.bypassTriggerKey))

            let radial = [RadialMenuBinding(configID: "top", target: .windowAction(stash)), RadialMenuBinding(target: .windowAction(cycle)), RadialMenuBinding(target: .reference(.init(.key, "wide")))]
            let decodedRadial = try [RadialMenuBinding].decodeTOML(radial.encodeTOML())
            #expect(decodedRadial.map(\.target.semanticKey) == radial.map(\.target.semanticKey))
            #expect(decodedRadial.map(\.configID) == radial.map(\.configID))

            let gestures = [
                GestureBinding(kind: .radialMenu, configID: "menu"),
                GestureBinding(fingerCount: 3, kind: .swipeLeft, configID: "swipe", target: .windowAction(custom), activationZone: .anywhere),
                GestureBinding(fingerCount: 4, kind: .magnifyIn, target: .reference(.init(.radialMenu, "top"))),
                GestureBinding(fingerCount: 2, kind: .swipeUp, target: .windowAction(cycle))
            ]
            let decodedGestures = try [GestureBinding].decodeTOML(gestures.encodeTOML())
            #expect(decodedGestures.map(\.target.semanticKey) == gestures.map(\.target.semanticKey))
            #expect(decodedGestures.map(\.kind) == gestures.map(\.kind))
            #expect(decodedGestures.map(\.fingerCount) == gestures.map(\.fingerCount))
            #expect(decodedGestures.map(\.activationZone) == gestures.map(\.activationZone))
            #expect(decodedGestures.map(\.configID) == gestures.map(\.configID))
        }

        @Test func aRowWritesItsOwnFieldsBeforeTheTarget() throws {
            let custom = WindowAction(kind: .custom(.init(name: "Portrait", size: .custom(width: ScreenLength(40), height: nil), position: .anchor(.bottomLeft))))
            let cycle = WindowAction(kind: .cycle(.init(name: "Halves", steps: [.windowAction(WindowAction(.leftHalf)), .windowAction(WindowAction(.rightHalf))])))
            let rows = [
                KeyBinding(configID: "portrait", keys: KeyCombination(names: ["a"]), bypassTriggerKey: true, target: .windowAction(custom)),
                KeyBinding(configID: "halves", keys: KeyCombination(names: ["b"]), target: .windowAction(cycle)),
                KeyBinding(keys: KeyCombination(names: ["c"]), target: .reference(.init(.key, "portrait")))
            ]
            var document = try TOMLDocument("")
            try document.set(TOMLEncoder().encodeToDocumentValue(rows), at: ["key", "bindings"])
            #expect(document.serialize() == """
            [[key.bindings]]
            id = "portrait"
            keys = "a"
            link-trigger-key = false
            action = "custom"
            name = "Portrait"
            size = {
                width = "40%",
            }
            position = "bottom-left"

            [[key.bindings]]
            id = "halves"
            keys = "b"
            action = "cycle"
            name = "Halves"
            cycle = [
                { action = "left-half" },
                { action = "right-half" },
            ]

            [[key.bindings]]
            keys = "c"
            action = "key:portrait"

            """)
        }

        @Test func fullReferenceMatrixPreservesDanglingIDs() throws {
            let targets: [ActionTarget] = [.reference(.init(.key, "wide")), .reference(.init(.gesture, "gs_example")), .reference(.init(.radialMenu, "rm_example"))]
            for target in targets {
                let keys = [KeyBinding(target: target)]
                #expect(try [KeyBinding].decodeTOML(keys.encodeTOML()).map(\.target) == [target])
                let radial = [RadialMenuBinding(configID: "menu", target: target)]
                #expect(try [RadialMenuBinding].decodeTOML(radial.encodeTOML()).map(\.target) == [target])
                let gestures = [GestureBinding(kind: .swipeLeft, configID: "swipe", target: target)]
                #expect(try [GestureBinding].decodeTOML(gestures.encodeTOML()).map(\.target) == [target])
            }
        }

        @Test func rowsWithoutAWrittenIDAreRandomAndPromotionKeepsIdentity() throws {
            let encoded = try [KeyBinding(.leftHalf, keys: KeyCombination(names: ["a"])), KeyBinding(.rightHalf, keys: KeyCombination(names: ["b"]))].encodeTOML()
            var rows = try [KeyBinding].decodeTOML(encoded)
            #expect(Set(rows.map(\.id)).count == 2)
            #expect(rows.allSatisfy { $0.configID == nil })
            #expect(try TOMLCodecs.decodeArray(rows.encodeTOML()).allSatisfy { try TOMLCodecs.decodeTable($0)["id"] == nil })
            let identity = rows[0].id
            #expect(rows.ensureConfigurationID(at: 0) == "left-half")
            #expect(rows[0].id == identity)
            let promoted = try [KeyBinding].decodeTOML(rows.encodeTOML())
            #expect(promoted[0].id == ConfigurationIdentity.uuid("key/id:left-half"))
            #expect(promoted[0].configID == rows[0].configID)
            #expect(promoted[1].configID == nil)
            let named = [rows[1].withConfigurationID("moved"), rows[0]]
            #expect(try [KeyBinding].decodeTOML(named.encodeTOML()).first?.id == [KeyBinding].decodeTOML([rows[1].withConfigurationID("moved")].encodeTOML()).first?.id)
        }

        @Test func duplicateIDsAreRenamedInsteadOfRejected() throws {
            let settings = try Profile()
            let source = "[[key.bindings]]\nid = \"same\"\naction = \"left-half\"\n[[key.bindings]]\nid = \"same\"\naction = \"right-half\"\n[[key.bindings]]\nid = \"same-2\"\naction = \"maximize\"\n"
            #expect(Tome.validate(document: source).isEmpty)
            try settings.install(source)
            #expect(settings[\.keyBindings].map(\.configID) == ["same", "same-3", "same-2"])
            #expect(settings[\.keyBindings].map(\.target.semanticKey) == [.leftHalf, .rightHalf, .maximize].map { ActionTarget.windowAction(.init($0)).semanticKey })
            #expect(settings.issues.isEmpty)
            let ids = settings[\.keyBindings].map(\.id)
            try settings.install(source + "# touched\n")
            #expect(settings[\.keyBindings].map(\.id) == ids)
            try settings.install(source)

            // Reading never rewrites the file.
            try settings.flush()
            #expect(try settings.fileContents() == source)

            let snapshot = BindingResolutionSnapshot(
                keyBindings: settings[\.keyBindings] + [KeyBinding(configID: "ref", target: .reference(.init(.key, "same")))],
                gestureBindings: [], radialMenuBindings: []
            )
            #expect(snapshot.action(for: .reference(.init(.key, "same"))).direction == .leftHalf)

            var rows = settings[\.keyBindings]
            rows[0].keys = KeyCombination(names: ["a"])
            settings[\.keyBindings] = rows
            try settings.flush()
            let written = try TOMLDocument(settings.fileContents())
            guard case let .array(items)? = written.value(at: ["key", "bindings"]) else {
                Issue.record("Expected keyBindings")
                return
            }
            var writtenIDs: [String] = []
            for case let .table(table) in items {
                if case let .string(id)? = table["id"] { writtenIDs.append(id) }
            }
            #expect(writtenIDs == ["same", "same-3", "same-2"])
        }

        @Test func writingDuplicateIDsFromTheUIRenamesThem() throws {
            let settings = try Profile()
            try settings.set([KeyBinding(.leftHalf).withConfigurationID("same"), KeyBinding(.rightHalf).withConfigurationID("same")], for: \.keyBindings)
            #expect(settings[\.keyBindings].map(\.configID) == ["same", "same-2"])
            #expect(settings.issues.isEmpty)
            try settings.flush()
            try settings.reload()
            #expect(settings[\.keyBindings].map(\.configID) == ["same", "same-2"])
            try settings.install("[[gestures.bindings]]\nid = \"g\"\nfingers = 3\nkind = \"pinch\"\naction = \"maximize\"\n[[gestures.bindings]]\nid = \"g\"\nfingers = 4\nkind = \"pinch\"\naction = \"maximize\"\n[[radial-menu.bindings]]\nid = \"r\"\naction = \"maximize\"\n[[radial-menu.bindings]]\nid = \"r\"\naction = \"maximize\"\n")
            #expect(settings[\.gestureBindings].map(\.configID) == ["g", "g-2"])
            #expect(settings[\.radialMenuBindings].map(\.configID) == ["r", "r-2"])
            #expect(settings.issues.isEmpty)
        }

        @Test func theRadialMenuIsAGestureKindNotAnAction() throws {
            let rows = try [GestureBinding].decodeTOML(.array([.table(["kind": .string("radial-menu")])]))
            #expect(rows.first?.target.resolvedDirection == .noAction)
            #expect(try TOMLCodecs.decodeTable(TOMLCodecs.decodeArray(rows.encodeTOML())[0])["action"] == nil)
            #expect(try [GestureBinding].decodeTOML(rows.encodeTOML()).map(\.kind) == [.radialMenu])
            #expect(throws: (any Error).self) { try [GestureBinding].decodeTOML(.array([.table(["action": .string("radial-menu")])])) }
            #expect(throws: (any Error).self) {
                try [GestureBinding].decodeTOML(.array([.table(["kind": .string("radial-menu"), "action": .string("maximize")])]))
            }
        }

        @Test func aGestureRowWithAnActionTableIsInvalid() throws {
            let nested: TOMLValue = .array([.table(["fingers": .integer(4), "kind": .string("spread"), "action": .table(["action": .string("maximize")])])])
            #expect(throws: (any Error).self) { try [GestureBinding].decodeTOML(nested) }
        }

        @Test func newCoordinateGeometryIsWrittenWithUnitSuffixes() throws {
            let settings = try Profile()
            let action = WindowAction(kind: .custom(.init(size: .custom(width: ScreenLength(25), height: ScreenLength(250, unit: .points)), position: .coordinates(x: ScreenLength(25, unit: .points), y: ScreenLength(10)))))
            try settings.set([KeyBinding(target: .windowAction(action))], for: \.keyBindings)
            let document = try TOMLDocument(settings.serialized)
            #expect(document.value(at: ["key", "bindings"]) != nil)
            let row = try TOMLCodecs.decodeTable(TOMLCodecs.decodeArray(#require(document.value(at: ["key", "bindings"])))[0])
            #expect(row["position"] == .table(["x": .string("25pt"), "y": .string("10%")]))
            #expect(row["size"] == .table(["width": .string("25%"), "height": .string("250pt")]))
            #expect(row["unit"] == nil)
        }

        @Test func invalidGestureDoesNotDisableValidKeyBindings() throws {
            let settings = try Profile("""
            [[key.bindings]]
            id = "mine"
            keys = ["ctrl", "a"]
            action = "maximize"
            [[gestures.bindings]]
            fingers = 9
            kind = "swipe-left"
            action = "maximize"
            """)
            #expect(settings[\.keyBindings].first?.configID == "mine")
            #expect(settings[\.keyBindings].first?.keys == KeyCombination(names: ["ctrl", "a"]))
            #expect(settings[\.gestureBindings].map(\.fingerCount) == GestureBinding.defaults.map(\.fingerCount))
            #expect(settings.issues.contains { $0.path == "gestures.bindings" })
            #expect(!settings.issues.contains { $0.path == "key.bindings" })
            try settings.set([GestureBinding(fingerCount: 3, kind: .swipeLeft)], for: \.gestureBindings)
            #expect(settings[\.gestureBindings].first?.fingerCount == 3)
            #expect(settings.serialized.contains("fingers = 9") == false)
            #expect(settings[\.keyBindings].first?.configID == "mine")
            #expect(settings.issues.isEmpty)
        }

        @Test func danglingReferencesResolveToNoAction() throws {
            let settings = try Profile("""
            [[key.bindings]]
            action = "maximize"
            keys = "a"
            [[radial-menu.bindings]]
            action = "key:missing"
            [[gestures.bindings]]
            kind = "swipe-left"
            action = "gesture:also-missing"
            """)
            #expect(settings.issues.isEmpty)
            let resolver = BindingResolutionSnapshot(keyBindings: settings[\.keyBindings], gestureBindings: settings[\.gestureBindings], radialMenuBindings: settings[\.radialMenuBindings])
            #expect(resolver.action(for: settings[\.radialMenuBindings][0].target).direction == .noAction)
            #expect(resolver.action(for: settings[\.gestureBindings][0].target).direction == .noAction)
        }

        @Test func canonicalAPIReadsAndObservesTheSection() async throws {
            let source = "# keep profile\n[[key.bindings]]\nid=\"observed\"\naction=\"maximize\" # keep action\n"
            let settings = try Profile(source)
            #expect(settings[\.keyBindings].first?.target.semanticKey == ActionTarget.windowAction(WindowAction(.maximize)).semanticKey)
            try settings.flush()
            #expect(try settings.fileContents() == source)
            let changes = Recorder<[KeyBinding]>()
            let observation = Tome.observe(\.keyBindings) { changes.append($0.newValue) }
            defer { observation.cancel() }
            try settings.install(source.replacingOccurrences(of: "maximize", with: "left-half"))
            for _ in 0 ..< 100 {
                if changes.contains(where: { $0.first?.target.resolvedDirection == .leftHalf }) { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            #expect(changes.contains { $0.first?.target.resolvedDirection == .leftHalf })
            #expect(settings[\.keyBindings].first?.target.semanticKey == ActionTarget.windowAction(WindowAction(.leftHalf)).semanticKey)
        }

        @Test func aggregatePaddingPreservesSiblingSettingsAndUnknownBytes() async throws {
            let source = """
            # My custom screen profile
            [padding]
            enabled   = true # keep this spacing
            minimum-screen-size = 19
            ignore-notch = false
            unknown = "keep me"
            gap = 8.0
            """ + "\n"
            let settings = try Profile(source)
            let changes = Recorder<PaddingConfiguration>()
            let observation = Tome.observe(\.padding) { changes.append($0.newValue) }
            defer { observation.cancel() }
            var padding = settings[\.padding]
            padding.window = 4
            padding.top = 3
            try settings.set(padding, for: \.padding)
            let changed = settings.serialized
            #expect(changed.contains("enabled   = true # keep this spacing"))
            #expect(changed.contains("unknown = \"keep me\""))
            #expect(changed.contains("minimum-screen-size = 19"))
            #expect(changed.contains("gap = 4"))
            #expect(settings[\.padding] == padding)
            for _ in 0 ..< 100 {
                if changes.values.count >= 1 { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            #expect(changes.values == [padding])
            try settings.set(.zero, for: \.padding)
            let reset = try TOMLDocument(settings.serialized)
            #expect(reset.value(at: ["padding", "gap"]) == nil)
            #expect(reset.value(at: ["padding", "edges"]) == nil)
            #expect(reset.value(at: ["padding", "enabled"]) == .boolean(true))
            #expect(reset.value(at: ["padding", "unknown"]) == .string("keep me"))
            #expect(reset.value(at: ["padding", "minimum-screen-size"]) == .integer(19))
            #expect(reset.serialize().contains("# My custom screen profile"))
            #expect(reset.serialize().contains("enabled   = true # keep this spacing"))
            for _ in 0 ..< 100 {
                if changes.values.count >= 2 { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            #expect(changes.values == [padding, .zero])
        }

        @Test func gestureRowsKeepTheirIdentityAsTheyAreEdited() throws {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let settings = try Tome.Settings(url: directory.appendingPathComponent("config.toml"), debounceInterval: 60)
            try settings.set([GestureBinding(fingerCount: 3, kind: .swipeLeft), GestureBinding(fingerCount: 4, kind: .swipeRight)], for: \.gestureBindings)
            let ids = settings[\.gestureBindings].map(\.id)
            #expect(Set(ids).count == 2)
            var edited = settings[\.gestureBindings]
            edited[1].kind = .swipeUp
            try settings.set(edited, for: \.gestureBindings)
            #expect(settings[\.gestureBindings].map(\.id) == ids)
            #expect(settings[\.gestureBindings][1].kind == .swipeUp)
            edited[1] = edited[1].withConfigurationID("selected")
            try settings.set(edited, for: \.gestureBindings)
            let selected = try #require(settings[\.gestureBindings].first { $0.configID == "selected" }).id
            try settings.set([GestureBinding(fingerCount: 2, kind: .magnifyIn)] + edited, for: \.gestureBindings)
            #expect(settings[\.gestureBindings].first { $0.configID == "selected" }?.id == selected)
        }
    }
}
