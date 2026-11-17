//
//  ConfigMigrator+StashRecords.swift
//  Loop
//
//  Created by Kai Azim on 2026-11-16.
//

import CoreGraphics
import Defaults
import Foundation
import TOML
import Tome

extension ConfigMigrator {
    static func reconnectStashRecords(document: TOMLDocument, suite: UserDefaults) {
        let stashKey = Defaults.Key<[CGWindowID: WindowAction]>("stashManagerStashed", default: [:], suite: suite)
        let records = Defaults[stashKey]
        guard !records.isEmpty else { return }
        var mapping: [UUID: UUID] = [:]
        func pair(_ old: ActionTarget, _ new: ActionTarget) {
            guard case let .windowAction(oldAction) = old, case let .windowAction(newAction) = new else { return }
            mapping[oldAction.id] = newAction.id
            guard case let .cycle(oldCycle) = oldAction.kind, case let .cycle(newCycle) = newAction.kind,
                  oldCycle.steps.count == newCycle.steps.count else { return }
            zip(oldCycle.steps, newCycle.steps).forEach(pair)
        }
        func pairAll<Binding: ConfigurationIdentifiable>(_ legacy: [ActionTarget], as _: Binding.Type, at path: [String]) {
            guard let value = document.value(at: path), let migrated = try? [Binding].decodeTOML(value).identified(), migrated.count == legacy.count else { return }
            zip(legacy, migrated.map(\.target)).forEach(pair)
        }
        let direct: (LegacyRadialMenuAction.ActionType) -> ActionTarget = {
            if case let .custom(saved) = $0 { .windowAction(saved.convertToWindowAction()) } else { .keyBinding("") }
        }
        pairAll(legacyValue(LegacyDefaults.keybinds, suite: suite).filter { $0.direction != .noSelection }.map { $0.convertToKeyBinding().target }, as: KeyBinding.self, at: ["key", "bindings"])
        pairAll(legacyValue(LegacyDefaults.radialMenuActions, suite: suite).map { direct($0.type) }, as: RadialMenuBinding.self, at: ["radial-menu", "bindings"])
        pairAll(legacyValue(LegacyDefaults.gestures, suite: suite).map { gesture in
            if case let .singleAction(type) = gesture.action { direct(type) } else { .radialMenuMode }
        }, as: GestureBinding.self, at: ["gestures", "bindings"])
        let reconnected = records.mapValues { action in mapping[action.id].map(action.withRuntimeID) ?? action }
        if reconnected != records { Defaults[stashKey] = reconnected }
    }
}
