//
//  Develop.swift
//  LoopTests
//
//  Created by Kai Azim on 2026-11-18.
//

import CoreGraphics
import Defaults
import Foundation
@testable import Loop

/// Legacy Codable shapes, so tests can store settings as older versions did.
enum Develop {
    struct WindowAction: Encodable {
        var id = UUID()
        var direction: String
        var keybind: Set<CGKeyCode> = []
        var bypassTriggerKey: Bool?
        var name: String?
        var unit: CustomWindowActionUnit?
        var anchor: CustomWindowActionAnchor?
        var sizeMode: CustomWindowActionSizeMode?
        var width: Double?
        var height: Double?
        var positionMode: CustomWindowActionPositionMode?
        var xPoint: Double?
        var yPoint: Double?
        var cycle: [WindowAction]?

        init(_ direction: WindowDirection, keybind: Set<CGKeyCode> = [], name: String? = nil, cycle: [WindowAction]? = nil) {
            self.direction = WindowDirectionLegacyCodingTests.legacy[direction.rawValue]!
            self.keybind = keybind
            self.name = name
            self.cycle = cycle
        }

        func read() throws -> LegacyWindowAction {
            try JSONDecoder().decode(LegacyWindowAction.self, from: Data(Develop.json(self).utf8))
        }
    }

    struct RadialMenuAction: Encodable {
        var id = UUID()
        var type: ActionType

        enum ActionType: Encodable {
            case custom(WindowAction)
            case keybindReference(UUID)
        }

        static func keybindReference(_ id: UUID) -> Self { .init(type: .keybindReference(id)) }
    }

    struct GestureBinding: Encodable {
        var id = UUID()
        var fingerCount = 2
        var kind: Kind?
        var action: Action
        var activationZone = "titlebar"

        enum Kind: Encodable {
            case radialMenu, swipeUp, swipeDown, swipeLeft, swipeRight, magnifyOut, magnifyIn
        }

        enum Action: Encodable {
            case radialMenuActions
            case singleAction(RadialMenuAction.ActionType)
        }
    }

    struct KeybindsFile: Encodable {
        var version: String?
        var triggerKey: Set<CGKeyCode>?
        var actions: [WindowAction]
    }

    /// JSON with sorted keys, as Defaults stored it.
    static func json(_ value: some Encodable) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return String(decoding: try! encoder.encode(value), as: UTF8.self)
    }
}

extension LegacyDefaultsFixture {
    /// One JSON string per element, as Defaults stored it.
    func set(_ values: [some Encodable], _ key: Defaults.Key<[some Any]>) {
        suite.set(values.map(Develop.json), forKey: key.name)
    }

    func setStashRecords(_ records: [CGWindowID: Develop.WindowAction]) {
        suite.set(Dictionary(uniqueKeysWithValues: records.map { (String($0.key), Develop.json($0.value)) }), forKey: Defaults.Keys.stashManagerStashedWindows.name)
    }

    var stashRecords: [CGWindowID: Loop.WindowAction] { Defaults[ConfigMigrator.key(.stashManagerStashedWindows, in: suite)] }
}
