//
//  TestSettings.swift
//  LoopTests
//
//  Created by Kai Azim on 2026-11-16.
//

import Defaults
import Foundation
@testable import Loop
import Testing
import Tome
import TOML

/// Tests that use Loop's real settings keys share one store, so their suites nest here and run serially.
@Suite(.serialized)
enum StoreTests {}

enum TestSettings {
    /// A long debounce keeps writes explicit; call `Tome.flush()` when the bytes matter.
    static let url: URL = {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("LoopTests-" + UUID().uuidString)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("config.toml")
        do { try Tome.configure(fileURL: url, debounceInterval: 60) }
        catch { preconditionFailure("Could not configure the test store: \(error)") }
        return url
    }()

    /// Loads `source` as if another editor saved it. Invalid content is loaded too.
    static func install(_ source: String = "") throws {
        _ = url
        try Tome.flush()
        try source.write(to: url, atomically: true, encoding: .utf8)
        try Tome.reload()
        refreshDiagnostics()
    }

    /// The store clears a key's issue only when its async state event arrives,
    /// so without this a previous test's invalid value would still be reported.
    static func refreshDiagnostics() {
        Tome.refresh(\.keyBindings, \.gestureBindings, \.radialMenuBindings, \.padding, \.triggerKey)
    }
}

struct Profile {
    init(_ source: String = "") throws {
        try TestSettings.install(source)
    }

    var url: URL { TestSettings.url }
    var serialized: String { Tome.serializedDocument }
    /// Keys decode lazily, so they are refreshed first.
    var issues: [Tome.Issue] {
        TestSettings.refreshDiagnostics()
        return Tome.issues
    }

    func value(at path: [String]) -> TOMLValue? { (try? TOMLDocument(Tome.serializedDocument))?.value(at: path) }
    func flush() throws { try Tome.flush() }
    func reload() throws { try Tome.reload() }
    func fileContents() throws -> String { try String(contentsOf: url, encoding: .utf8) }
    func install(_ source: String) throws { try TestSettings.install(source) }

    subscript<Value>(_ keyPath: WritableKeyPath<TomeValues, Value>) -> Value {
        get { Tome.standard[keyPath] }
        nonmutating set { Tome.standard[keyPath] = newValue }
    }

    func set<Value: Equatable & Sendable>(_ value: Value, for keyPath: WritableKeyPath<TomeValues, Value>) throws {
        try Tome.standard.set(value, for: keyPath)
    }
}

enum TargetCoding {
    static func decode(_ table: [String: TOMLValue]) throws -> ActionTarget {
        try TOMLDecoder().decodeFromValue(ActionTarget.self, from: .table(table))
    }

    static func decodeAction(_ table: [String: TOMLValue]) throws -> WindowAction {
        guard case let .windowAction(action) = try decode(table) else { throw TargetError.expectedAction }
        return action
    }

    static func encode(_ target: ActionTarget) throws -> [String: TOMLValue] {
        try TOMLCodecs.decodeTable(TOMLEncoder().encodeToValue(target))
    }

    enum TargetError: Error { case expectedAction }
}

extension Array where Element: ActionBinding {
    /// Decoded, then identified, as the running app reads it.
    static func decodeIdentified(_ value: TOMLValue) throws -> [Element] { try decodeTOML(value).identified() }
}

/// A throwaway legacy Defaults suite and config file location.
struct LegacyDefaultsFixture {
    let suiteName = "Loop.LegacyDefaultsFixture.\(UUID().uuidString)"
    let suite: UserDefaults
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("config.toml")
    init() { self.suite = UserDefaults(suiteName: suiteName)! }
    var persisted: [String: Any] { suite.persistentDomain(forName: suiteName) ?? [:] }
    func set<Value>(_ value: Value, _ key: Defaults.Key<Value>) {
        Defaults[Defaults.Key<Value>(key.name, default: key.defaultValue, suite: suite)] = value
    }

    func get<Value>(_ key: Defaults.Key<Value>) -> Value { ConfigMigrator.legacyValue(key, suite: suite) }
    func cleanUpFile() { try? FileManager.default.removeItem(at: url) }
    func cleanUp() {
        suite.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}

final class Recorder<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Value] = []

    func append(_ value: Value) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(value)
    }

    var values: [Value] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func contains(where predicate: (Value) -> Bool) -> Bool { values.contains(where: predicate) }
}

extension ActionTarget {
    /// `nil` for a reference.
    var resolvedDirection: WindowDirection? {
        if case let .windowAction(action) = self { action.direction } else { nil }
    }
}

extension ActionBinding {
    func withConfigurationID(_ configID: String) -> Self {
        var binding = self
        binding.configID = configID
        return binding
    }
}
