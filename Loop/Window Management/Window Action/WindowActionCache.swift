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
/// Keybinds that link to another binding are stored as the action they run.
@Loggable
final class WindowActionCache {
    private(set) var actionsByKeybind: [Set<CGKeyCode>: WindowAction] = [:]
    private(set) var bypassedActionsByKeybind: [Set<CGKeyCode>: WindowAction] = [:]
    private(set) var linkResolver = BindingLinkResolver(keybinds: [], gestures: [], radialMenuActions: [])

    private var observationTask: Task<(), Never>?

    /// Initializes a new instance of `WindowActionCache`.
    /// Will automatically build cache, and update according to changes the user makes to Loop's keybinds.
    init() {
        self.observationTask = Task { [weak self] in
            // Gestures and the radial menu too, as keybinds can link to them
            let updates = Defaults.updates(
                .keybinds,
                .cycleBackwardsOnShiftPressed,
                .gestures,
                .radialMenuActions,
                .enableRadialMenuCustomization
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
        linkResolver = BindingLinkResolver()
        BindingLinkResolver.shared = linkResolver
        let keybinds = linkResolver.keybinds
            .filter { !$0.keybind.isEmpty }
            .map { $0.resolvingLink(with: linkResolver) }

        regenerateActionsByKeybind(from: keybinds)

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
}
