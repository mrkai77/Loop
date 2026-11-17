//
//  ConfigMigrator.swift
//  Loop
//
//  Created by Kai Azim on 2026-11-16.
//

import CryptoKit
import Defaults
import Foundation
import Tome
import TOML

/// One-time migration from Defaults to config.toml. Legacy values are left in place.
/// Call after DataPatcher and before TOML is configured.
enum ConfigMigrator {
    enum Outcome: Equatable { case migrated, existingFile, alreadyMigrated }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    @discardableResult
    static func run(
        url: URL = ConfigurationManager.fileURL(),
        suite: UserDefaults = .standard,
        domainName: String = Bundle.main.bundleIdentifier ?? "com.MrKai77.Loop",
        write: (Data, URL) throws -> () = writeFile
    ) throws -> Outcome {
        let done = key(.migratedToConfigFile, in: suite)
        let pending = key(.configMigrationPendingDigest, in: suite)
        // An existing file wins, even a malformed one, unless an interrupted migration wrote it
        if FileManager.default.fileExists(atPath: url.path) {
            // Deleting the file later must not re-import stale Defaults
            defer { Defaults[done] = true }
            guard let expected = Defaults[pending] else { return .existingFile }
            Defaults[pending] = nil
            guard let saved = try? Data(contentsOf: url), digest(saved) == expected else { return .existingFile }
            if let document = try? TOMLDocument(String(decoding: saved, as: UTF8.self)) {
                migrateStashRecords(document: document, suite: suite)
            }
            return .migrated
        }
        guard !Defaults[done] else { return .alreadyMigrated }
        if let source = try migratedSource(suite: suite, domainName: domainName) {
            let data = Data(source.utf8)
            // Recorded first, so an interrupted run can be finished later
            Defaults[pending] = digest(data)
            do { try write(data, url) }
            catch {
                // Only a file that was written can be resumed
                if !FileManager.default.fileExists(atPath: url.path) { Defaults[pending] = nil }
                throw error
            }
            let saved = try TOMLDocument(String(contentsOf: url, encoding: .utf8))
            guard try saved.value == TOMLDocument(source).value else {
                throw TOMLValueError.invalidValue("Configuration changed while migrating")
            }
            migrateStashRecords(document: saved, suite: suite)
        }
        Defaults[done] = true
        Defaults[pending] = nil
        return .migrated
    }

    static func writeFile(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    static func key<Value>(_ key: Defaults.Key<Value>, in suite: UserDefaults) -> Defaults.Key<Value> {
        Defaults.Key<Value>(key.name, default: key.defaultValue, suite: suite)
    }

    static func legacyValue<Value>(_ key: Defaults.Key<Value>, suite: UserDefaults) -> Value {
        Defaults[self.key(key, in: suite)]
    }

    /// `nil` when no legacy key was set. Rendered through the settings API, so it matches the real file.
    static func migratedSource(suite: UserDefaults, domainName: String) throws -> String? {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("LoopMigration-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let settings = try Tome.Settings(url: scratch.appendingPathComponent("config.toml"))
        try LegacyMigration(suite: suite, persisted: Set((suite.persistentDomain(forName: domainName) ?? [:]).keys), settings: settings).writeAll()
        try settings.flush()
        let source = settings.serializedDocument
        guard try TOMLDocument(source).value != .table([:]) else { return nil }
        return source
    }
}
