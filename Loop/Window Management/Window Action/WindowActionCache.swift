//
//  WindowActionCache.swift
//  Loop
//
//  Created by Kai Azim on 2025-10-11.
//

import AppKit
import Defaults
import Scribe

/// Caches the user's actions in a dictionary keyed by its keybind.
/// This is called from `KeybindObserver`, to retrieve the user's actions in an efficient manner.
@Loggable
final class WindowActionCache {
    private(set) var actionsByKeybind: [Set<CGKeyCode>: WindowAction] = [:]
    private(set) var bypassedActionsByKeybind: [Set<CGKeyCode>: WindowAction] = [:]
    private(set) var actionsByIdentifier: [UUID: WindowAction] = [:]

    private var observationTask: Task<(), Never>?

    /// Initializes a new instance of `WindowActionCache`.
    /// Will automatically build cache, and update according to changes the user makes to Loop's keybinds.
    init() {
        self.observationTask = Task { [weak self] in
            let updates = Defaults.updates(
                .keybinds,
                .cycleBackwardsOnShiftPressed
            )

            for await _ in updates {
                guard
                    !Task.isCancelled,
                    let self
                else {
                    break
                }

                regenerateCache()
            }
        }
    }

    /// Rebuilds the cache and includes extra entries for cycle actions with shift keys if the user has enabled `cycleBackwardsOnShiftPressed`.
    private func regenerateCache() {
        let keybinds: [WindowAction] = Defaults[.keybinds]

        regenerateActionsByKeybind(from: keybinds.filter { !$0.keybind.isEmpty })
        regenerateActionsByIdentifier(from: keybinds)

        log.info("Regenerated cache; normal: \(actionsByKeybind.count), bypassed: \(bypassedActionsByKeybind.count)")
    }

    private func regenerateActionsByKeybind(from keybinds: [WindowAction]) {
        let cycleBackwardsOnShiftPressed: Bool = Defaults[.cycleBackwardsOnShiftPressed]

        let normalActions = keybinds.filter { $0.bypassTriggerKey != true }
        let bypassedActions = keybinds.filter { $0.bypassTriggerKey == true }

        // Normal actions: keybind is action-key only (without trigger key)
        actionsByKeybind = Dictionary(
            normalActions.map { ($0.keybind, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        if cycleBackwardsOnShiftPressed {
            actionsByKeybind.merge(
                normalActions
                    .filter { $0.direction == .cycle }
                    .map { ($0.keybind.union([.kVK_Shift]), $0) },
                uniquingKeysWith: { first, _ in first }
            )
        }

        bypassedActionsByKeybind = Dictionary(
            bypassedActions.map { ($0.keybind, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private func regenerateActionsByIdentifier(from keybinds: [WindowAction]) {
        actionsByIdentifier = Dictionary(
            keybinds.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }
}
