//
//  Migrator.swift
//  Loop
//
//  Created by Kai Azim on 2024-03-22.
//

import Defaults
import Scribe
import SwiftUI

// MARK: - Saved Keybinds Format

/// Struct to represent the JSON contents of a Loop keybinds file.
struct SavedKeybindsFormat: Codable {
    let version: String?
    let triggerKey: Set<CGKeyCode>?
    let actions: [SavedWindowActionFormat]

    static func generateFromDefaults() -> SavedKeybindsFormat {
        SavedKeybindsFormat(
            version: Bundle.main.appVersion,
            triggerKey: Defaults[.triggerKey],
            actions: Defaults[.keybinds].map { SavedWindowActionFormat($0) }
        )
    }
}

// MARK: - SavedWindowActionFormat

/// Struct to define the format of saved window actions.
struct SavedWindowActionFormat: Codable {
    let direction: WindowDirection
    let keybind: Set<CGKeyCode>
    let name: String?
    let unit: CustomWindowActionUnit?
    let anchor: CustomWindowActionAnchor?
    let sizeMode: CustomWindowActionSizeMode?
    let width: Double?
    let height: Double?
    let positionMode: CustomWindowActionPositionMode?
    let xPoint: Double?
    let yPoint: Double?
    let cycle: [SavedWindowActionFormat]?

    /// Initialize from a WindowAction.
    init(_ action: WindowAction) {
        self.direction = action.direction
        self.keybind = action.keybind
        self.name = action.name
        self.unit = action.unit
        self.anchor = action.anchor
        self.sizeMode = action.sizeMode
        self.width = action.width
        self.height = action.height
        self.positionMode = action.positionMode
        self.xPoint = action.xPoint
        self.yPoint = action.yPoint
        self.cycle = action.cycle?.map { SavedWindowActionFormat($0) }
    }

    /// Converts the saved format back into a usable WindowAction object.
    func convertToWindowAction() -> WindowAction {
        WindowAction(
            direction,
            keybind: keybind,
            name: name,
            unit: unit,
            anchor: anchor,
            width: width,
            height: height,
            xPoint: xPoint,
            yPoint: yPoint,
            positionMode: positionMode,
            sizeMode: sizeMode,
            cycle: cycle?.map { $0.convertToWindowAction()
            }
        )
    }
}

// MARK: - Migrator

enum MigratorError: LocalizedError {
    case keybindsEmpty
    case failedToConvertToString
    case mainWindowNotAvailableForPanel
    case fileSelectionCancelled
    case directorySelectionCancelled
    case failedToReadFile

    var errorDescription: String? {
        switch self {
        case .keybindsEmpty:
            "Keybinds are empty."
        case .failedToConvertToString:
            "Failed to convert keybinds to string."
        case .mainWindowNotAvailableForPanel:
            "Main window not available for panel."
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

    /// Presents a prompt to export current keybinds to a JSON file.
    static func exportPrompt(onSuccess: () -> ()) async throws {
        // Check if there are any keybinds to export.
        guard !Defaults[.keybinds].isEmpty else {
            await showAlert(
                String(
                    localized: "No Keybinds Have Been Set",
                    comment: "Title for an alert shown when the user tries to export keybinds but none exist."
                ),
                informativeText: String(
                    localized: "You can't export something that doesn't exist!",
                    comment: "Description for an alert shown when the user tries to export keybinds but none exist."
                )
            )

            throw MigratorError.keybindsEmpty
        }

        let directoryURL = try await getSaveDirectoryURL()
        let keybinds = SavedKeybindsFormat.generateFromDefaults()
        try await saveKeybinds(keybinds, in: directoryURL)

        onSuccess()
    }

    /// Presents a prompt to import keybinds from a JSON file.
    static func importPrompt(onSuccess: () -> ()) async throws {
        let fileURL = try await getKeybindsFileURL()
        let jsonString = try String(contentsOf: fileURL)

        do {
            try await importKeybinds(from: jsonString, onSuccess: onSuccess)
        } catch {
            if case MigratorError.failedToReadFile = error {
                await showAlert(
                    .init(
                        localized: "Error reading keybinds alert title",
                        defaultValue: "Couldn’t Import Keybinds"
                    ),
                    informativeText: .init(
                        localized: "Error reading keybinds alert description",
                        defaultValue: "Make sure the file you selected is in the correct format."
                    )
                )
            } else {
                throw error
            }
        }
    }
}

// MARK: Migrator + Export

private extension Migrator {
    /// Presents a save panel to select a directory for exporting keybinds.
    @MainActor
    static func getSaveDirectoryURL() async throws -> URL {
        let savePanel = NSSavePanel()
        savePanel.directoryURL = Defaults[.lastMigratorURL] ?? documentsDirectory
        savePanel.title = .init(localized: "Export Keybinds")
        savePanel.nameFieldStringValue = "Loop Keybinds.json"
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

    /// Saves the keybinds in the specified directory URL.
    private static func saveKeybinds(_ keybinds: SavedKeybindsFormat, in directoryURL: URL) async throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        // Convert to a dictionary we can manipulate before final encoding
        var rootDict = try JSONSerialization.jsonObject(
            with: encoder.encode(keybinds),
            options: [.mutableContainers]
        ) as! [String: Any]

        // Process trigger key if present
        if var triggerKey = rootDict["triggerKey"] as? [CGKeyCode] {
            triggerKey.sort()
            rootDict["triggerKey"] = triggerKey
        }

        // Process actions array
        if var actions = rootDict["actions"] as? [[String: Any]] {
            // First ensure all keybind arrays are sorted
            for i in 0 ..< actions.count {
                // Sort the keybind array in each action
                if var keybind = actions[i]["keybind"] as? [CGKeyCode] {
                    keybind.sort()
                    actions[i]["keybind"] = keybind
                }

                // Handle nested cycle actions if present
                if var cycle = actions[i]["cycle"] as? [[String: Any]] {
                    // For each action in the cycle
                    for j in 0 ..< cycle.count {
                        // Sort the keybind array in each cycle action
                        if var cycleKeybind = cycle[j]["keybind"] as? [CGKeyCode] {
                            cycleKeybind.sort()
                            cycle[j]["keybind"] = cycleKeybind
                        }
                    }
                    actions[i]["cycle"] = cycle
                }
            }

            // Sort the actions array by direction and keybind for a consistent ordering
            actions.sort { first, second -> Bool in
                // First compare by direction
                let firstDir = first["direction"] as? String ?? ""
                let secondDir = second["direction"] as? String ?? ""

                if firstDir != secondDir {
                    return firstDir < secondDir
                }

                // If directions are equal, compare by name (if present)
                let firstName = first["name"] as? String ?? ""
                let secondName = second["name"] as? String ?? ""

                if firstName != secondName {
                    return firstName < secondName
                }

                // If names are equal or empty, compare by keybind
                let firstKeybind = first["keybind"] as? [CGKeyCode] ?? []
                let secondKeybind = second["keybind"] as? [CGKeyCode] ?? []

                // Convert keybinds to strings for comparison
                let firstKeyStr = firstKeybind.map { String($0) }.joined(separator: "-")
                let secondKeyStr = secondKeybind.map { String($0) }.joined(separator: "-")

                return firstKeyStr < secondKeyStr
            }

            rootDict["actions"] = actions
        }

        // Convert back to JSON data with our sorted arrays
        let sortedData = try JSONSerialization.data(
            withJSONObject: rootDict,
            options: [.prettyPrinted, .sortedKeys]
        )

        guard let json = String(data: sortedData, encoding: .utf8) else {
            throw MigratorError.failedToConvertToString
        }

        try json.write(
            to: directoryURL,
            atomically: true,
            encoding: .utf8
        )
    }
}

// MARK: Migrator + Import

private extension Migrator {
    /// Presents a file picker to select a keybinds file.
    @MainActor
    static func getKeybindsFileURL() async throws -> URL {
        let openPanel = NSOpenPanel()
        openPanel.directoryURL = Defaults[.lastMigratorURL] ?? documentsDirectory
        openPanel.title = .init(localized: "Choose a Keybinds File")
        openPanel.allowedContentTypes = [.json]
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.allowsMultipleSelection = false

        let result = await openPanel.begin()

        guard result == .OK, let selectedFileURL = openPanel.url else {
            throw MigratorError.fileSelectionCancelled
        }

        // Save the last used directory for future imports
        Defaults[.lastMigratorURL] = selectedFileURL.deletingLastPathComponent()

        return selectedFileURL
    }

    /// Imports keybinds from a JSON string.
    private static func importKeybinds(from jsonString: String, onSuccess: () -> ()) async throws {
        guard let data = jsonString.data(using: .utf8) else {
            throw MigratorError.failedToReadFile
        }

        // First, try to import the general Loop keybinds format.
        do {
            let savedData = try importLoopKeybinds(from: data)
            await updateDefaults(with: savedData, onSuccess: onSuccess)
            return
        } catch {
            log.error("Error importing Loop keybinds: \(error)")
        }

        // If that fails, try to import the old Loop (pre 1.2.0) keybinds format.
        do {
            let savedData = try importLoopLegacyKeybinds(from: data)
            await updateDefaults(with: savedData, onSuccess: onSuccess)
            return
        } catch {
            log.error("Error importing Loop (pre 1.2.0) keybinds: \(error)")
        }

        // If that fails, try to import the Rectangle keybinds format.
        do {
            let savedData = try importRectangleKeybinds(from: data)
            await updateDefaults(with: savedData, onSuccess: onSuccess)
            return
        } catch {
            log.error("Error importing Rectangle keybinds: \(error)")
        }

        // If all attempts fail, show an error alert.
        throw MigratorError.failedToReadFile
    }

    /// Tries to import Loop's keybinds format.
    static func importLoopKeybinds(from data: Data) throws -> SavedKeybindsFormat {
        let decoder = JSONDecoder()
        let keybinds = try decoder.decode(SavedKeybindsFormat.self, from: data)
        return keybinds
    }

    /// Tries to import Loop's old (pre 1.2.0) keybinds format.
    static func importLoopLegacyKeybinds(from data: Data) throws -> SavedKeybindsFormat {
        let decoder = JSONDecoder()
        let keybinds = try decoder.decode([SavedWindowActionFormat].self, from: data)
        return SavedKeybindsFormat(version: nil, triggerKey: nil, actions: keybinds)
    }

    /// Tries to import Rectangle's keybinds format.
    static func importRectangleKeybinds(from data: Data) throws -> SavedKeybindsFormat {
        let keybinds = try RectangleTranslationLayer.importKeybinds(from: data)
        return SavedKeybindsFormat(version: nil, triggerKey: nil, actions: keybinds)
    }

    // MARK: Saving Imports

    /// Updates the app's defaults with the imported keybinds.
    static func updateDefaults(with savedData: SavedKeybindsFormat, onSuccess: () -> ()) async {
        if let triggerKey = savedData.triggerKey {
            Defaults[.triggerKey] = triggerKey
        }

        if Defaults[.keybinds].isEmpty {
            Defaults[.keybinds] = savedData.actions.map { $0.convertToWindowAction() }
            onSuccess()
        } else {
            let result = await showAlertForImportDecision()

            switch result {
            case .merge:
                let newKeybinds = savedData.actions
                    .map { $0.convertToWindowAction() }
                    .filter { newKeybind in
                        !Defaults[.keybinds].contains { $0.keybind == newKeybind.keybind && $0.name == newKeybind.name }
                    }

                Defaults[.keybinds].append(contentsOf: newKeybinds)
                onSuccess()
            case .erase:
                Defaults[.keybinds] = savedData.actions.map { $0.convertToWindowAction() }
                onSuccess()
            case .cancel:
                // No action needed, no notification should be posted
                break
            }
        }
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
