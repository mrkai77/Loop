//
//  WorkspaceManager.swift
//  Loop
//
//  Created on 2026-10-20.
//

import Defaults
import Scribe
import SwiftUI

/// Saves the current arrangement of windows as a named workspace, and recreates it on demand,
/// launching any apps that aren't running.
@Loggable
@MainActor
final class WorkspaceManager {
    static let shared = WorkspaceManager()
    private init() {}

    /// How long to wait for a freshly launched app to open its windows.
    private let launchTimeout: Duration = .seconds(10)

    private lazy var hotKeys = WorkspaceHotKeys { [weak self] id in
        self?.handleHotKey(id)
    }

    private var settingsTask: Task<(), Never>?
    private var applyTask: Task<(), Never>?

    func start() {
        settingsTask = Task { [weak self] in
            for await enabled in Defaults.updates(.workspaceHotKeysEnabled) {
                guard let self else { return }
                if enabled {
                    hotKeys.register()
                } else {
                    hotKeys.unregister()
                }
            }
        }
    }

    func shutdown() {
        settingsTask?.cancel()
        applyTask?.cancel()
        hotKeys.unregister()
    }

    private func handleHotKey(_ id: UInt32) {
        if id == WorkspaceHotKeys.restoreLayoutHotKeyID {
            Task { await DisplayMemoryManager.shared.restoreLayout() }
            return
        }

        let index = Int(id) - 1
        let workspaces = Defaults[.workspaces]
        guard workspaces.indices.contains(index) else {
            NSSound.beep()
            return
        }
        apply(workspaces[index])
    }

    // MARK: Saving

    @discardableResult
    func saveCurrentLayout(named name: String) -> Workspace? {
        let windows = WindowArranger.captureVisibleWindows()
        guard !windows.isEmpty else {
            log.warn("No windows to save")
            return nil
        }

        let workspace = Workspace(name: name, windows: windows)
        Defaults[.workspaces].append(workspace)
        return workspace
    }

    func updateWithCurrentLayout(_ workspace: Workspace) {
        guard let index = Defaults[.workspaces].firstIndex(where: { $0.id == workspace.id }) else { return }
        let windows = WindowArranger.captureVisibleWindows()
        guard !windows.isEmpty else { return }
        Defaults[.workspaces][index].windows = windows
    }

    func delete(_ workspace: Workspace) {
        Defaults[.workspaces].removeAll { $0.id == workspace.id }
    }

    /// Asks for a name, then saves the current layout.
    func promptToSaveCurrentLayout() {
        let name = promptForName(
            title: String(localized: "Save Workspace", comment: "Title of the dialog to save the current window layout"),
            message: String(
                localized: "Every visible window will be saved with its position, and missing apps will be opened when the workspace is applied.",
                comment: "Explanation in the dialog to save the current window layout"
            ),
            initialValue: String(
                localized: "Workspace \(Defaults[.workspaces].count + 1)",
                comment: "Default name for a new workspace, followed by its number"
            )
        )

        if let name {
            saveCurrentLayout(named: name)
        }
    }

    func promptToRename(_ workspace: Workspace) {
        guard let index = Defaults[.workspaces].firstIndex(where: { $0.id == workspace.id }),
              let name = promptForName(
                  title: String(localized: "Rename Workspace", comment: "Title of the dialog to rename a workspace"),
                  message: "",
                  initialValue: workspace.name
              )
        else {
            return
        }

        Defaults[.workspaces][index].name = name
    }

    private func promptForName(title: String, message: String, initialValue: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: String(localized: "Save", comment: "Button to save a workspace"))
        alert.addButton(withTitle: String(localized: "Cancel", comment: "Button to cancel saving a workspace"))

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = String(localized: "Workspace name", comment: "Placeholder for the name of a workspace")
        field.stringValue = initialValue
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }

        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? initialValue : name
    }

    // MARK: Applying

    func apply(named name: String) -> Bool {
        guard let workspace = Defaults[.workspaces].first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
            return false
        }
        apply(workspace)
        return true
    }

    func apply(_ workspace: Workspace) {
        applyTask?.cancel()
        applyTask = Task {
            await performApply(workspace)
        }
    }

    private func performApply(_ workspace: Workspace) async {
        log.info("Applying workspace \(workspace.name)")

        let bundleIDs = workspace.bundleIDs

        // Launch everything before waiting for windows, so slow apps load in parallel
        var apps: [String: NSRunningApplication] = [:]
        for bundleID in bundleIDs {
            if let app = await runningApp(bundleID: bundleID, launchIfNeeded: workspace.launchMissingApps) {
                apps[bundleID] = app
            }
        }

        var pairs: [(Window, WindowPlacement)] = []
        for bundleID in bundleIDs {
            guard !Task.isCancelled, let app = apps[bundleID] else { continue }

            if app.isHidden {
                app.unhide()
            }

            let placements = workspace.windows.filter { $0.bundleID == bundleID }
            let windows = await waitForWindows(of: app, count: placements.count)
            pairs += WindowArranger.match(placements, to: windows, allowLooseMatches: true)
        }

        guard !Task.isCancelled else { return }

        if workspace.hideOtherApps {
            for app in NSWorkspace.shared.runningApplications
                where app.activationPolicy == .regular && !bundleIDs.contains(app.bundleIdentifier ?? "") && !app.isTerminated {
                app.hide()
            }
        }

        await WindowArranger.apply(pairs, fallBackToAnyScreen: true)

        // Raise back-to-front so the window that was frontmost when saving ends up on top
        let order = workspace.windows
        for (window, _) in pairs.sorted(by: { lhs, rhs in
            (order.firstIndex(of: lhs.1) ?? 0) > (order.firstIndex(of: rhs.1) ?? 0)
        }) {
            guard !Task.isCancelled else { return }
            window.focus()
            try? await Task.sleep(for: .milliseconds(30))
        }
    }

    private func runningApp(bundleID: String, launchIfNeeded: Bool) async -> NSRunningApplication? {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            return app
        }

        guard launchIfNeeded,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else {
            return nil
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false

        do {
            return try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        } catch {
            log.error("Failed to launch \(bundleID): \(error.localizedDescription)")
            return nil
        }
    }

    /// Waits until the app has opened at least `count` windows, or until the timeout.
    /// Returns whatever windows exist at that point.
    private func waitForWindows(of app: NSRunningApplication, count: Int) async -> [Window] {
        let start = ContinuousClock.now
        var windows = WindowArranger.windows(of: app)

        while windows.count < count, ContinuousClock.now - start < launchTimeout, !Task.isCancelled {
            // An app that has been open for a while won't open more windows on its own
            if !windows.isEmpty, ContinuousClock.now - start > .seconds(2) {
                break
            }
            try? await Task.sleep(for: .milliseconds(250))
            windows = WindowArranger.windows(of: app)
        }

        return windows
    }
}
