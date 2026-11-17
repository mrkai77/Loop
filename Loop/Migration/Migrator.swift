//
//  Migrator.swift
//  Loop
//
//  Created by Kai Azim on 2024-03-22.
//

import Defaults
import Scribe
import SwiftUI
import Tome
import UniformTypeIdentifiers

// MARK: - Migrator

enum MigratorError: LocalizedError {
    case fileSelectionCancelled
    case directorySelectionCancelled
    case failedToReadFile
    case invalidKeybinds(String)

    var errorDescription: String? {
        switch self {
        case let .invalidKeybinds(reason):
            reason
        case .fileSelectionCancelled:
            "File selection was cancelled."
        case .directorySelectionCancelled:
            "Directory selection was cancelled."
        case .failedToReadFile:
            "Failed to read file."
        }
    }
}

/// Adds functionality for saving, loading, and managing window actions.
@Loggable(style: .static)
enum Migrator {
    private static var documentsDirectory: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    }

    static func exportConfiguration() throws -> String {
        let issues = Tome.issues
        guard issues.isEmpty else { throw Tome.ValidationError(issues: issues) }
        return Tome.serializedDocument
    }

    static func exportPrompt(onSuccess: () -> ()) async throws {
        let destination = try await getSaveDirectoryURL()
        try exportConfiguration().write(to: destination, atomically: true, encoding: .utf8)
        onSuccess()
    }

    static func importPrompt(onSuccess: () -> ()) async throws {
        let fileURL = try await getKeybindsFileURL()
        let source = try String(contentsOf: fileURL, encoding: .utf8)
        do {
            if fileURL.pathExtension.lowercased() == "toml" {
                let issues = validateConfiguration(source)
                guard issues.isEmpty else { throw Tome.ValidationError(issues: issues) }
                let response = await showAlert(
                    String(localized: "Replace Configuration?"),
                    informativeText: String(localized: "This replaces all Loop configuration. Settings missing from this file return to their defaults."),
                    buttons: [String(localized: "Replace"), String(localized: "Cancel")]
                )
                if try importConfiguration(source, confirmed: response == .alertFirstButtonReturn) {
                    Defaults[.lastMigratorURL] = fileURL.deletingLastPathComponent()
                    onSuccess()
                }
            } else {
                let saved = try decodeJSON(Data(source.utf8))
                let decision = await showAlertForImportDecision()
                if try applyJSON(saved, decision: decision) {
                    Defaults[.lastMigratorURL] = fileURL.deletingLastPathComponent()
                    onSuccess()
                }
            }
        } catch {
            await showAlert(String(localized: "Couldn’t Import Configuration"), informativeText: error.localizedDescription)
            throw error
        }
    }

    static func validateConfiguration(_ source: String) -> [Tome.Issue] {
        Tome.validate(document: source)
    }

    @discardableResult
    static func importConfiguration(_ source: String, confirmed: Bool) throws -> Bool {
        guard confirmed else { return false }
        try Tome.replaceDocument(with: source)
        return true
    }
}

// MARK: Migrator + Export

@MainActor
private extension Migrator {
    static func getSaveDirectoryURL() async throws -> URL {
        let savePanel = NSSavePanel()
        savePanel.directoryURL = Defaults[.lastMigratorURL] ?? documentsDirectory
        savePanel.title = .init(localized: "Export Configuration")
        savePanel.nameFieldStringValue = "Loop Configuration.toml"
        savePanel.allowedContentTypes = [UTType(filenameExtension: "toml") ?? .plainText]
        savePanel.canCreateDirectories = true
        savePanel.showsTagField = false

        let result = await savePanel.begin()

        guard result == .OK, let selectedFileURL = savePanel.url else {
            throw MigratorError.directorySelectionCancelled
        }

        // Save the last used directory for future exports
        Defaults[.lastMigratorURL] = selectedFileURL.deletingLastPathComponent()

        return selectedFileURL
    }
}

// MARK: Migrator + Import

extension Migrator {
    /// Presents a file picker to select a keybinds file.
    @MainActor
    static func getKeybindsFileURL() async throws -> URL {
        let openPanel = NSOpenPanel()
        openPanel.directoryURL = Defaults[.lastMigratorURL] ?? documentsDirectory
        openPanel.title = .init(localized: "Choose a Configuration or Keybinds File")
        openPanel.allowedContentTypes = [UTType(filenameExtension: "toml") ?? .plainText, .json]
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.allowsMultipleSelection = false

        let result = await openPanel.begin()

        guard result == .OK, let selectedFileURL = openPanel.url else {
            throw MigratorError.fileSelectionCancelled
        }

        return selectedFileURL
    }

    static func decodeJSON(_ data: Data) throws -> LegacyKeybindsFile {
        for importer in [importLoopKeybinds, importLoopLegacyKeybinds, importRectangleKeybinds] {
            do { return try importer(data) }
            catch let error as MigratorError { throw error }
            catch {}
        }
        throw MigratorError.failedToReadFile
    }

    /// Tries to import Loop's keybinds format.
    static func importLoopKeybinds(from data: Data) throws -> LegacyKeybindsFile {
        let decoder = JSONDecoder()
        let keybinds = try decoder.decode(LegacyKeybindsFile.self, from: data)
        return try keybinds.validated()
    }

    /// Tries to import Loop's old (pre 1.2.0) keybinds format.
    static func importLoopLegacyKeybinds(from data: Data) throws -> LegacyKeybindsFile {
        let decoder = JSONDecoder()
        let keybinds = try decoder.decode([LegacyWindowAction].self, from: data)
        return try LegacyKeybindsFile(version: nil, triggerKey: nil, actions: keybinds).validated()
    }

    /// Tries to import Rectangle's keybinds format.
    static func importRectangleKeybinds(from data: Data) throws -> LegacyKeybindsFile {
        let keybinds = try RectangleTranslationLayer.importKeybinds(from: data)
        return LegacyKeybindsFile(version: nil, triggerKey: nil, actions: keybinds)
    }

    // MARK: Saving Imports

    /// The decision is resolved before any mutation, including the trigger key.
    @discardableResult
    static func applyJSON(_ saved: LegacyKeybindsFile, decision: ImportDecision) throws -> Bool {
        guard decision != .cancel else { return false }
        _ = try saved.validated()
        let imported = saved.actions.map { $0.convertToKeyBinding() }
        var actions = decision == .erase ? [] : Tome.keyBindings
        struct Identity: Hashable {
            var keys: KeyCombination
            var name: String?
        }
        func identity(of binding: KeyBinding) -> Identity? {
            guard case let .windowAction(action) = binding.target else { return nil }
            return Identity(keys: binding.keys, name: action.name)
        }
        let existing = Set(actions.compactMap(identity(of:)))
        actions.append(contentsOf: imported.filter { action in
            decision == .erase || identity(of: action).map { !existing.contains($0) } ?? true
        })
        _ = try actions.encodeTOML()
        if let trigger = saved.triggerKey { _ = try KeyCombination.tomeBridge.serialize(KeyCombination(keyCodes: trigger)) }
        try Tome.standard.set(actions, for: \.keyBindings)
        if let trigger = saved.triggerKey { try Tome.standard.set(KeyCombination(keyCodes: trigger), for: \.triggerKey) }
        return true
    }

    /// Presents a decision alert for how to handle imported keybinds.
    static func showAlertForImportDecision() async -> ImportDecision {
        let response = await showAlert(
            .init(localized: "Import Keybinds"),
            informativeText: .init(localized: "Do you want to merge or erase existing keybinds?"),
            buttons: [
                .init(localized: "Import keybinds: merge", defaultValue: "Merge"),
                .init(localized: "Import keybinds: erase", defaultValue: "Replace"),
                .init(localized: "Import keybinds: cancel", defaultValue: "Cancel")
            ]
        )

        switch response {
        case .alertFirstButtonReturn:
            return .merge
        case .alertSecondButtonReturn:
            return .erase
        default:
            return .cancel
        }
    }

    /// Utility function to show an alert with a completion handler.
    @MainActor
    @discardableResult
    static func showAlert(
        _ messageText: String,
        informativeText: String,
        buttons: [String] = []
    ) async -> NSApplication.ModalResponse {
        let alert = NSAlert()
        alert.messageText = messageText
        alert.informativeText = informativeText
        buttons.forEach { alert.addButton(withTitle: $0) }

        // Reference: https://x.com/leoshimo/status/1975642593569738755
        if #available(macOS 26.0, *) {
            alert.buttons.first?.tintProminence = .primary
        }

        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            return await alert.beginSheetModal(for: window)
        } else {
            return alert.runModal()
        }
    }

    /// Enum to represent the decision made in the import decision alert.
    enum ImportDecision {
        case merge, erase, cancel
    }
}
