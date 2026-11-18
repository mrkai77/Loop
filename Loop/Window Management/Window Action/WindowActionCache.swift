//
//  WindowActionCache.swift
//  Loop
//
//  Created by Kai Azim on 2025-10-11.
//

import AppKit
import Scribe
import Tome

/// Publishes key lookup and the reference graph as one atomic snapshot.
@Loggable
final class WindowActionCache: @unchecked Sendable {
    static let shared = WindowActionCache()

    struct Snapshot {
        let actionsByKeybind: [Set<CGKeyCode>: WindowAction]
        let bypassedActionsByKeybind: [Set<CGKeyCode>: WindowAction]
        /// For the cycle logic that depends on a keybind's keys.
        let bindingsByActionID: [UUID: KeyBinding]
        let resolver: BindingResolutionSnapshot
        /// Already `identified()`; runtime lookups must use these.
        let keyBindings: [KeyBinding]
        let gestureBindings: [GestureBinding]
        /// The defaults unless customization is enabled.
        let radialMenuBindings: [RadialMenuBinding]
        let graphIssue: Tome.Issue?
        let keyIssues: [Tome.Issue]

        var issues: [Tome.Issue] { (graphIssue.map { [$0] } ?? []) + keyIssues }

        /// The first of bindings sharing an id wins.
        func target(of kind: BindingKind, id: UUID) -> ActionTarget? {
            switch kind {
            case .key: keyBindings.first { $0.id == id }?.target
            case .gesture: gestureBindings.first { $0.id == id }?.target
            case .radialMenu: radialMenuBindings.first { $0.id == id }?.target
            }
        }

        static let empty = Snapshot(
            actionsByKeybind: [:],
            bypassedActionsByKeybind: [:],
            bindingsByActionID: [:],
            resolver: .init(keyBindings: [], gestureBindings: [], radialMenuBindings: []),
            keyBindings: [],
            gestureBindings: [],
            radialMenuBindings: [],
            graphIssue: nil,
            keyIssues: []
        )
    }

    private let layout: KeyboardLayout
    private let snapshotLock = NSLock()
    private var snapshot = Snapshot.empty
    private let rebuildQueue = DispatchQueue(label: "Loop.WindowActionCache.Rebuild")
    private var observations: [Tome.ObservationToken] = []
    private var layoutObserver: (any NSObjectProtocol)?

    var actionsByKeybind: [Set<CGKeyCode>: WindowAction] { read { $0.actionsByKeybind } }
    var bypassedActionsByKeybind: [Set<CGKeyCode>: WindowAction] { read { $0.bypassedActionsByKeybind } }
    func keyBinding(for action: WindowAction) -> KeyBinding? { read { $0.bindingsByActionID[action.id] } }
    var keyBindingActions: [WindowAction] {
        let current = read { $0 }
        return current.keyBindings.map { current.resolver.action(for: $0.target) }
    }

    var graphIssue: Tome.Issue? { read { $0.graphIssue } }
    var issues: [Tome.Issue] { read { $0.issues } }
    /// Posted on the main queue.
    static let issuesDidChange = Notification.Name("WindowActionCache.issuesDidChange")

    var radialMenuBindings: [RadialMenuBinding] { read { $0.radialMenuBindings } }
    var radialMenuActions: [WindowAction] {
        let current = read { $0 }
        return current.radialMenuBindings.map { current.resolver.action(for: $0.target) }
    }

    func resolve(_ kind: BindingKind, id: UUID) -> WindowAction? {
        let current = read { $0 }
        return current.target(of: kind, id: id).map(current.resolver.action(for:))
    }

    private func read<T>(_ body: (Snapshot) -> T) -> T {
        snapshotLock.lock()
        defer { snapshotLock.unlock() }
        return body(snapshot)
    }

    /// Bindings are resolved again whenever `layout` changes.
    init(layout: KeyboardLayout = .shared) {
        self.layout = layout
        self.observations = [
            Tome.observe(\.triggerKey) { [weak self] _ in self?.scheduleRegeneration() },
            Tome.observe(\.keyBindings) { [weak self] _ in self?.scheduleRegeneration() },
            Tome.observe(\.gestureBindings) { [weak self] _ in self?.scheduleRegeneration() },
            Tome.observe(\.radialMenuBindings) { [weak self] _ in self?.scheduleRegeneration() },
            Tome.observe(\.enableRadialMenuCustomization) { [weak self] _ in self?.scheduleRegeneration() },
            Tome.observe(\.cycleBackwardsOnShiftPressed) { [weak self] _ in self?.scheduleRegeneration() }
        ]
        self.layoutObserver = NotificationCenter.default.addObserver(forName: KeyboardLayout.didChange, object: layout, queue: nil) { [weak self] _ in
            self?.scheduleRegeneration()
        }
        rebuildQueue.sync { regenerateCache() }
    }

    deinit {
        layoutObserver.map(NotificationCenter.default.removeObserver)
    }

    private func regenerateCache() {
        let bindings = Tome.keyBindings.identified()
        let gestures = Tome.gestureBindings.identified()
        let configuredMenu = Tome.radialMenuBindings.identified()
        let radialMenu = Tome.enableRadialMenuCustomization ? configuredMenu : RadialMenuBinding.defaults.identified()
        let resolver = BindingResolutionSnapshot(keyBindings: bindings, gestureBindings: gestures, radialMenuBindings: configuredMenu)
        // Reported, not enforced: only bindings that reach the bad reference lose their action
        var graphIssue: Tome.Issue?
        do { try resolver.validate() }
        catch {
            log.warn("Invalid binding reference graph: \(error)")
            graphIssue = Tome.Issue(path: "references", message: error.localizedDescription)
        }
        var normal: [Set<CGKeyCode>: WindowAction] = [:]
        var bypassed: [Set<CGKeyCode>: WindowAction] = [:]
        var definingBindings: [UUID: KeyBinding] = [:]
        // A referenced action belongs to the keybind that defines it
        for binding in bindings {
            if case let .windowAction(action) = binding.target { definingBindings[action.id] = binding }
        }
        let active = KeyBinding.active(in: bindings, triggerKey: Tome.triggerKey)
        for binding in active {
            let action = resolver.action(for: binding.target)
            if definingBindings[action.id] == nil { definingBindings[action.id] = binding }
            // Inactive until the layout has the key. When two names resolve to the same codes,
            // the first binding wins.
            guard let codes = binding.keys.keyCodes(on: layout) else { continue }
            if binding.bypassTriggerKey == true {
                if bypassed[codes] == nil { bypassed[codes] = action }
            } else if normal[codes] == nil { normal[codes] = action }
        }
        if Tome.cycleBackwardsOnShiftPressed {
            for binding in active where binding.bypassTriggerKey != true && !binding.keys.containsFixedKey(.kVK_Shift) {
                guard let codes = binding.keys.keyCodes(on: layout), let action = normal[codes], action.direction == .cycle else { continue }
                let shifted = codes.union([.kVK_Shift])
                if normal[shifted] == nil { normal[shifted] = action }
            }
        }
        let next = Snapshot(
            actionsByKeybind: normal,
            bypassedActionsByKeybind: bypassed,
            bindingsByActionID: definingBindings,
            resolver: resolver,
            keyBindings: bindings,
            gestureBindings: gestures,
            radialMenuBindings: radialMenu,
            graphIssue: graphIssue,
            keyIssues: keyIssues(for: bindings)
        )
        snapshotLock.lock()
        let changed = snapshot.issues != next.issues
        snapshot = next
        snapshotLock.unlock()
        if changed {
            DispatchQueue.main.async { NotificationCenter.default.post(name: Self.issuesDidChange, object: self) }
        }
    }

    private func keyIssues(for bindings: [KeyBinding]) -> [Tome.Issue] {
        func unresolved(in chords: [KeyCombination]) -> [String] {
            var seen: Set<String> = []
            return chords.flatMap { KeyNames.components(from: $0.names) }.filter { !layout.resolves($0) && seen.insert($0).inserted }
        }
        let message = { (name: String) in "'\(name)' isn't on the current keyboard layout" }
        return unresolved(in: bindings.map(\.keys)).map { Tome.Issue(path: "key.bindings", message: message($0)) }
            + unresolved(in: [Tome.triggerKey]).map { Tome.Issue(path: "trigger.keys", message: message($0)) }
    }

    private func scheduleRegeneration() {
        rebuildQueue.async { [weak self] in self?.regenerateCache() }
    }
}
