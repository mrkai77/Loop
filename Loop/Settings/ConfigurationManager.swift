//
//  ConfigurationManager.swift
//  Loop
//
//  Created by Kai Azim on 2026-11-17.
//

import AppKit
import Scribe
import Tome
import UniformTypeIdentifiers

/// Owns config.toml: migration, loading, issue reporting and saving.
@Loggable
@MainActor
final class ConfigurationManager {
    static let shared = ConfigurationManager()

    private var issueReporter: ConfigurationIssueReporter?

    private init() {}

    // MARK: Lifecycle

    /// Returns `false` when migration failed and Loop must quit.
    func start() -> Bool {
        do {
            try ConfigMigrator.run()
            try Tome.configure(fileURL: Self.fileURL(), registering: TomeValues.allEntries)
        } catch {
            log.error("Could not migrate configuration: \(error)")
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = String(localized: "Loop couldn't migrate your settings")
            alert.informativeText = error.localizedDescription + "\n\n" + Self.fileURL().path
            alert.addButton(withTitle: String(localized: "Quit"))
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
            NSApp.terminate(nil)
            return false
        }

        let reporter = ConfigurationIssueReporter()
        reporter.start()
        issueReporter = reporter
        return true
    }

    /// Flushes debounced changes before quitting.
    func stop() {
        do { try Tome.flush() }
        catch { log.error("Could not save configuration before quitting: \(error)") }
    }

    // MARK: File

    /// `$XDG_CONFIG_HOME/loop/config.toml`, or `~/.config/loop/config.toml`. A relative `XDG_CONFIG_HOME` is ignored.
    nonisolated static func fileURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        let base: URL = if let xdg = environment["XDG_CONFIG_HOME"], xdg.hasPrefix("/") {
            URL(fileURLWithPath: xdg, isDirectory: true)
        } else {
            home.appendingPathComponent(".config", isDirectory: true)
        }
        return base.appendingPathComponent("loop", isDirectory: true).appendingPathComponent("config.toml")
    }

    var backupsDirectory: URL {
        Tome.standard.url.deletingLastPathComponent().appendingPathComponent("backups", isDirectory: true)
    }

    /// Falls back to the default plain-text editor.
    func openInEditor() {
        let url = existingFileURL()
        guard let editor = NSWorkspace.shared.urlForApplication(toOpen: url)
            ?? NSWorkspace.shared.urlForApplication(toOpen: .plainText)
        else {
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return
        }
        NSWorkspace.shared.open([url], withApplicationAt: editor, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Nothing is reset if the backup fails. Returns `nil` when there was no file to back up.
    @discardableResult
    func reset() throws -> URL? {
        try Tome.flush()
        let url = Tome.standard.url
        var backup: URL?
        if FileManager.default.fileExists(atPath: url.path) {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let destination = backupsDirectory.appendingPathComponent("\(url.lastPathComponent).\(formatter.string(from: .now)).bak")
            try FileManager.default.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: url, to: destination)
            backup = destination
        }
        try Tome.replaceDocument(with: "")
        return backup
    }

    /// Creates an empty file first if there isn't one yet.
    private func existingFileURL() -> URL {
        let url = Tome.standard.url
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: url.path, contents: Data())
        }
        return url
    }
}
