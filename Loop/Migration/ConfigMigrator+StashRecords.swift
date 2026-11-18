//
//  ConfigMigrator+StashRecords.swift
//  Loop
//
//  Created by Kai Azim on 2026-11-16.
//

import CoreGraphics
import Defaults
import Foundation
import Tome
import TOML

extension ConfigMigrator {
    /// Rewrites legacy stash records to use the identities from `identified()`.
    /// Rewritten records no longer decode as legacy ones, so running this again is safe.
    static func migrateStashRecords(document: TOMLDocument, suite: UserDefaults) {
        let stashKey = key(.stashManagerStashedWindows, in: suite)
        let records = Defaults[Defaults.Key<[CGWindowID: LegacyWindowAction]>(stashKey.name, default: [:], suite: suite)]
        guard !records.isEmpty else { return }
        var mapping: [UUID: UUID] = [:]
        func pair(_ old: ActionTarget, _ new: ActionTarget) {
            guard case let .windowAction(oldAction) = old, case let .windowAction(newAction) = new else { return }
            mapping[oldAction.id] = newAction.id
            guard case let .cycle(oldCycle) = oldAction.kind, case let .cycle(newCycle) = newAction.kind,
                  oldCycle.steps.count == newCycle.steps.count else { return }
            zip(oldCycle.steps, newCycle.steps).forEach(pair)
        }
        func pairAll<Legacy: LegacyBinding>(_: Legacy.Type) {
            let legacy = legacyValue(Legacy.defaultsKey, suite: suite).compactMap { $0.migrated(names: [:]) }
            guard let value = document.value(at: Tome.path(of: Legacy.settingsKeyPath)),
                  let migrated = try? [Legacy.Binding].decodeTOML(value).identified(),
                  migrated.count == legacy.count else { return }
            zip(legacy.map(\.target), migrated.map(\.target)).forEach(pair)
        }
        pairAll(LegacyWindowAction.self)
        pairAll(LegacyRadialMenuAction.self)
        pairAll(LegacyGestureBinding.self)
        Defaults[stashKey] = records.mapValues { record in
            let action = record.convertToWindowAction()
            return mapping[action.id].map(action.withRuntimeID) ?? action
        }
    }
}
