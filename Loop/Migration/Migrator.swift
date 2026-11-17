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
    case failedToReadFile
    case invalidKeybinds(String)

    var errorDescription: String? {
        switch self {
        case let .invalidKeybinds(reason):
            reason
        case .fileSelectionCancelled:
            "File selection was cancelled."
        case .failedToReadFile:
            "Failed to read file."
        }
    }
}

struct ImportedKeybinds {
    var triggerKey: KeyCombination?
    var bindings: [KeyBinding]
}

extension ImportedKeybinds {
    init(_ file: LegacyKeybindsFile) {
        self.init(triggerKey: file.triggerKey.map { KeyCombination(keyCodes: $0) }, bindings: file.actions.map { $0.convertToKeyBinding() })
    }
}

/// Imports config.toml, legacy Loop keybinds files, or Rectangle's.
@Loggable(style: .static)
enum Migrator {
    private static var documentsDirectory: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
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

    /// An invalid document leaves the running profile untouched.
    @discardableResult
    static func importConfiguration(_ source: String, confirmed: Bool) throws -> Bool {
        guard confirmed else { return false }
        try Tome.replaceDocument(with: source)
        return true
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

    static func decodeJSON(_ data: Data) throws -> ImportedKeybinds {
        // Report unrunnable content in a Loop file as such, not as an unreadable file
        for importer in [importLoopKeybinds, importLoopLegacyKeybinds, importRectangleKeybinds] {
            do { return try importer(data) }
            catch let error as MigratorError { throw error }
            catch {}
        }
        throw MigratorError.failedToReadFile
    }

    /// Tries to import Loop's keybinds format.
    static func importLoopKeybinds(from data: Data) throws -> ImportedKeybinds {
        try ImportedKeybinds(JSONDecoder().decode(LegacyKeybindsFile.self, from: data).validated())
    }

    /// Tries to import Loop's old (pre 1.2.0) keybinds format.
    static func importLoopLegacyKeybinds(from data: Data) throws -> ImportedKeybinds {
        let actions = try JSONDecoder().decode([LegacyWindowAction].self, from: data)
        return try ImportedKeybinds(LegacyKeybindsFile(version: nil, triggerKey: nil, actions: actions).validated())
    }

    /// Tries to import Rectangle's keybinds format.
    static func importRectangleKeybinds(from data: Data) throws -> ImportedKeybinds {
        try ImportedKeybinds(triggerKey: nil, bindings: RectangleTranslationLayer.importKeybinds(from: data))
    }

    // MARK: Saving Imports

    /// The decision is resolved before any mutation, including the trigger key.
    @discardableResult
    static func applyJSON(_ imported: ImportedKeybinds, decision: ImportDecision) throws -> Bool {
        guard decision != .cancel else { return false }
        var actions = decision == .erase ? [] : Tome.keyBindings
        // Keys and name identify a binding; on a match the existing one is kept
        struct Identity: Hashable {
            var keys: KeyCombination
            var name: String?
        }
        func identity(of binding: KeyBinding) -> Identity? {
            guard case let .windowAction(action) = binding.target else { return nil }
            return Identity(keys: binding.keys, name: action.name)
        }
        let existing = Set(actions.compactMap(identity(of:)))
        actions.append(contentsOf: imported.bindings.filter { action in
            decision == .erase || identity(of: action).map { !existing.contains($0) } ?? true
        })
        // Encode first, so a failure changes neither key
        _ = try actions.encodeTOML()
        if let trigger = imported.triggerKey { _ = try KeyCombination.tomeBridge.serialize(trigger) }
        try Tome.standard.set(actions, for: \.keyBindings)
        if let trigger = imported.triggerKey { try Tome.standard.set(trigger, for: \.triggerKey) }
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
