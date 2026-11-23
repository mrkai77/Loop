//
//  WindowActionCache.swift
//  Loop
//
//  Created by Kai Azim on 2025-10-11.
//

import AppKit
import Defaults
import os
import Scribe

/// Caches the user's actions in a dictionary keyed by its keybind.
/// This is called from `KeybindTrigger`, to retrieve the user's actions in an efficient manner.
/// Linked keybinds are stored as the action they run, and keybinds sharing their keys are left out.
/// The event tap reads it on its own thread, so it's one locked snapshot, rebuilt on a serial queue
@Loggable
final class WindowActionCache: @unchecked Sendable {
    static let shared = WindowActionCache()

    struct Snapshot {
        /// The trigger key conflicts were found with, so keypresses match against the same one
        var triggerKey: Set<CGKeyCode> = []
        var actionsByKeybind: [Set<CGKeyCode>: WindowAction] = [:]
        var bypassedActionsByKeybind: [Set<CGKeyCode>: WindowAction] = [:]
        var keysByActionID: [UUID: Set<CGKeyCode>] = [:]
        var linkResolver = BindingLinkResolver(keybinds: [], gestures: [], radialMenuActions: [])
    }

    private let state = OSAllocatedUnfairLock(uncheckedState: Snapshot())
    private let rebuildQueue = DispatchQueue(label: "com.MrKai77.Loop.WindowActionCache.rebuild")
    private var observationTask: Task<(), Never>?

    /// Read once per event, so one event never mixes two rebuilds
    var snapshot: Snapshot {
        state.withLockUnchecked { $0 }
    }

    /// The keys of the keybind that runs `action`, without the trigger key, or none when no keybind does
    func keys(for action: WindowAction) -> Set<CGKeyCode> {
        state.withLockUnchecked { $0.keysByActionID[action.id] } ?? []
    }

    var linkResolver: BindingLinkResolver {
        state.withLockUnchecked { $0.linkResolver }
    }

    /// Builds the cache before returning, so the first keypress after launch finds its action
    private init() {
        rebuildQueue.sync { regenerateCache() }

        self.observationTask = Task { [weak self] in
            let updates = Defaults.updates(
                .keybinds,
                .triggerKey,
                .cycleBackwardsOnShiftPressed,
                .gestures,
                .radialMenuActions,
                .enableRadialMenuCustomization,
                initial: false
            )

            for await _ in updates {
                guard !Task.isCancelled, let self else {
                    break
                }

                rebuildQueue.async { [weak self] in
                    self?.regenerateCache()
                }
            }
        }
    }

    /// Rebuilds the cache and includes extra entries for cycle actions with shift keys if the user has enabled `cycleBackwardsOnShiftPressed`.
    private func regenerateCache() {
        let next = Self.snapshot(
            linkResolver: .current,
            triggerKey: Defaults[.triggerKey],
            cycleBackwardsOnShiftPressed: Defaults[.cycleBackwardsOnShiftPressed]
        )
        state.withLockUnchecked { $0 = next }

        log.info("Regenerated cache; normal: \(next.actionsByKeybind.count), bypassed: \(next.bypassedActionsByKeybind.count)")
    }

    static func snapshot(linkResolver: BindingLinkResolver, triggerKey: Set<CGKeyCode>, cycleBackwardsOnShiftPressed: Bool) -> Snapshot {
        var next = Snapshot(triggerKey: triggerKey, linkResolver: linkResolver)
        let conflictingIDs = Keybind.conflictingIDs(in: linkResolver.keybinds, triggerKey: triggerKey)
        if !conflictingIDs.isEmpty {
            log.info("Disabled \(conflictingIDs.count) keybinds that share their keys with another")
        }
        let keybinds = linkResolver.keybinds
            .filter { !$0.keys.isEmpty && !conflictingIDs.contains($0.id) }
            .map { (binding: $0, action: $0.resolvedAction(with: linkResolver) ?? WindowAction(.noAction).withID($0.id)) }

        let normalActions = keybinds.filter { !$0.binding.bypassTriggerKey }
        let bypassedActions = keybinds.filter(\.binding.bypassTriggerKey)

        // Normal actions: keybind is action-key only (without trigger key)
        next.actionsByKeybind = Dictionary(
            normalActions.map { ($0.binding.keys, $0.action) },
            uniquingKeysWith: { first, _ in first }
        )

        if cycleBackwardsOnShiftPressed {
            next.actionsByKeybind.merge(
                normalActions
                    .filter { $0.action.direction == .cycle }
                    .map { ($0.binding.keys.union([.kVK_Shift]), $0.action) },
                uniquingKeysWith: { first, _ in first }
            )
        }

        next.bypassedActionsByKeybind = Dictionary(
            bypassedActions.map { ($0.binding.keys, $0.action) },
            uniquingKeysWith: { first, _ in first }
        )

        next.keysByActionID = Dictionary(
            keybinds.map { ($0.action.id, $0.binding.keys) },
            uniquingKeysWith: { first, _ in first }
        )

        return next
    }
}
