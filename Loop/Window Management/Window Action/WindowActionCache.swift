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
/// This is called from `KeybindObserver`, to retrieve the user's actions in an efficient manner.
/// Keybinds that link to another binding are stored as the action they run, and keybinds that share their keys with another are left out.
///
/// The event tap reads it on its own thread, so everything is published as one snapshot behind a lock,
/// and rebuilt on a serial queue.
@Loggable
final class WindowActionCache: @unchecked Sendable {
    static let shared = WindowActionCache()

    private struct Snapshot {
        var actionsByKeybind: [Set<CGKeyCode>: WindowAction] = [:]
        var bypassedActionsByKeybind: [Set<CGKeyCode>: WindowAction] = [:]
        var linkResolver = BindingLinkResolver(keybinds: [], gestures: [], radialMenuActions: [])
    }

    private let snapshot = OSAllocatedUnfairLock(uncheckedState: Snapshot())
    private let rebuildQueue = DispatchQueue(label: "com.MrKai77.Loop.WindowActionCache.rebuild")
    private var observationTask: Task<(), Never>?

    var actionsByKeybind: [Set<CGKeyCode>: WindowAction] { read(\.actionsByKeybind) }
    var bypassedActionsByKeybind: [Set<CGKeyCode>: WindowAction] { read(\.bypassedActionsByKeybind) }
    var linkResolver: BindingLinkResolver { read(\.linkResolver) }

    /// Builds the cache before returning, so the first keypress after launch already finds its action
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

    private func read<T>(_ keyPath: KeyPath<Snapshot, T>) -> T {
        snapshot.withLockUnchecked { $0[keyPath: keyPath] }
    }

    /// Rebuilds the cache and includes extra entries for cycle actions with shift keys if the user has enabled `cycleBackwardsOnShiftPressed`.
    private func regenerateCache() {
        var next = Snapshot(linkResolver: BindingLinkResolver())
        let conflictingIDs = WindowAction.conflictingIDs(in: next.linkResolver.keybinds, triggerKey: Defaults[.triggerKey])
        let keybinds = next.linkResolver.keybinds
            .filter { !$0.keybind.isEmpty && !conflictingIDs.contains($0.id) }
            .map { $0.resolvingLink(with: next.linkResolver) }

        let cycleBackwardsOnShiftPressed: Bool = Defaults[.cycleBackwardsOnShiftPressed]

        let normalActions = keybinds.filter { $0.bypassTriggerKey != true }
        let bypassedActions = keybinds.filter { $0.bypassTriggerKey == true }

        // Normal actions: keybind is action-key only (without trigger key)
        next.actionsByKeybind = Dictionary(
            normalActions.map { ($0.keybind, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        if cycleBackwardsOnShiftPressed {
            next.actionsByKeybind.merge(
                normalActions
                    .filter { $0.direction == .cycle }
                    .map { ($0.keybind.union([.kVK_Shift]), $0) },
                uniquingKeysWith: { first, _ in first }
            )
        }

        next.bypassedActionsByKeybind = Dictionary(
            bypassedActions.map { ($0.keybind, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        snapshot.withLockUnchecked { $0 = next }

        log.info("Regenerated cache; normal: \(next.actionsByKeybind.count), bypassed: \(next.bypassedActionsByKeybind.count), disabled by conflicts: \(conflictingIDs.count)")
    }
}
