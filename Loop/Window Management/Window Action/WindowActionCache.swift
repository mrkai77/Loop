//
//  WindowActionCache.swift
//  Loop
//
//  Created by Kai Azim on 2025-10-11.
//

import AppKit
import Scribe
import Tome

@Loggable
final class WindowActionCache: @unchecked Sendable {
    static let shared = WindowActionCache()

    struct Snapshot {
        let actionsByKeybind: [Set<CGKeyCode>: WindowAction]
        let bypassedActionsByKeybind: [Set<CGKeyCode>: WindowAction]
        let bindingsByActionID: [UUID: KeyBinding]
        let resolver: BindingResolutionSnapshot
        let keyBindings: [KeyBinding]
        let gesturesByID: [UUID: GestureBinding]
        let radialMenuBindings: [RadialMenuBinding]
        let radialMenuBindingsByID: [UUID: RadialMenuBinding]
        let graphIssue: Tome.Issue?
        let keyIssues: [Tome.Issue]

        var issues: [Tome.Issue] { (graphIssue.map { [$0] } ?? []) + keyIssues }

        static let empty = Snapshot(
            actionsByKeybind: [:],
            bypassedActionsByKeybind: [:],
            bindingsByActionID: [:],
            resolver: .init(keyBindings: [], gestures: [], radialMenuBindings: []),
            keyBindings: [],
            gesturesByID: [:],
            radialMenuBindings: [],
            radialMenuBindingsByID: [:],
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
        return current.keyBindings.compactMap { current.resolver.action(for: $0.target) }
    }

    var graphIssue: Tome.Issue? { read { $0.graphIssue } }
    var issues: [Tome.Issue] { read { $0.issues } }
    static let issuesDidChange = Notification.Name("WindowActionCache.issuesDidChange")

    var radialMenuBindings: [RadialMenuBinding] { read { $0.radialMenuBindings } }
    func resolve(gestureID: UUID) -> WindowAction? {
        let current = read { $0 }
        return current.gesturesByID[gestureID].flatMap { current.resolver.action(for: $0.target) }
    }

    func resolve(radialMenuBindingID: UUID) -> WindowAction? {
        let current = read { $0 }
        return current.radialMenuBindingsByID[radialMenuBindingID].flatMap { current.resolver.action(for: $0.target) }
    }

    func resolve(_ target: ActionTarget) -> WindowAction? { read { $0.resolver }.action(for: target) }

    private func read<T>(_ body: (Snapshot) -> T) -> T {
        snapshotLock.lock()
        defer { snapshotLock.unlock() }
        return body(snapshot)
    }

    init(layout: KeyboardLayout = .shared) {
        self.layout = layout
        self.observations = [
            Tome.observe(\.triggerKey) { [weak self] _ in self?.scheduleRegeneration() },
            Tome.observe(\.keyBindings) { [weak self] _ in self?.scheduleRegeneration() },
            Tome.observe(\.gestures) { [weak self] _ in self?.scheduleRegeneration() },
            Tome.observe(\.radialMenuActions) { [weak self] _ in self?.scheduleRegeneration() },
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
        let resolver = BindingResolutionSnapshot(keyBindings: Tome.keyBindings, gestures: Tome.gestures, radialMenuBindings: Tome.radialMenuActions)
        let bindings = resolver.keyBindings
        let gestures = resolver.gestures
        let configuredMenu = resolver.radialMenuBindings
        let radialMenu = Tome.enableRadialMenuCustomization ? configuredMenu : RadialMenuBinding.defaultRadialMenuActions
        var graphIssue: Tome.Issue?
        do { try resolver.validate() }
        catch {
            log.warn("Invalid binding reference graph: \(error)")
            graphIssue = Tome.Issue(path: "references", message: Self.message(for: error))
        }
        var normal: [Set<CGKeyCode>: WindowAction] = [:]
        var bypassed: [Set<CGKeyCode>: WindowAction] = [:]
        var definingBindings: [UUID: KeyBinding] = [:]
        for binding in bindings {
            if case let .windowAction(action) = binding.target { definingBindings[action.id] = binding }
        }
        for binding in bindings {
            guard !binding.keys.isEmpty, let action = resolver.action(for: binding.target) else { continue }
            if definingBindings[action.id] == nil { definingBindings[action.id] = binding }
            guard let codes = binding.keys.keyCodes(on: layout) else { continue }
            if binding.bypassTriggerKey == true {
                if bypassed[codes] == nil { bypassed[codes] = action }
            } else if normal[codes] == nil { normal[codes] = action }
        }
        if Tome.cycleBackwardsOnShiftPressed {
            for binding in bindings where binding.bypassTriggerKey != true && !binding.keys.isEmpty && !binding.keys.containsFixedKey(.kVK_Shift) {
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
            gesturesByID: Dictionary(gestures.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }),
            radialMenuBindings: radialMenu,
            radialMenuBindingsByID: Dictionary((configuredMenu + radialMenu).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }),
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

    private static func message(for error: any Error) -> String {
        switch error as? BindingResolutionSnapshot.ResolutionError {
        case let .cycle(path): "References form a cycle: " + path.map(\.description).joined(separator: " \u{2192} ")
        case let .radialMenuModeReference(reference): "The whole radial menu can't be referenced by \(reference)"
        case let .duplicateIdentifier(reference): "Duplicate \(reference)"
        case let .nestedCycle(reference): reference.map { "A cycle step references a cycle: \($0)" } ?? "A cycle step can't be a cycle"
        case nil: error.localizedDescription
        }
    }

    private func scheduleRegeneration() {
        rebuildQueue.async { [weak self] in self?.regenerateCache() }
    }
}
