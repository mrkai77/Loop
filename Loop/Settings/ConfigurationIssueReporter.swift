//
//  ConfigurationIssueReporter.swift
//  Loop
//
//  Created by Kai Azim on 2026-11-16.
//

import AppKit
import Combine
import Scribe
import Tome
import UserNotifications

/// Reports config.toml problems as a notification, or an alert when notifications aren't allowed.
@Loggable
@MainActor
final class ConfigurationIssueReporter: NSObject {
    static let notificationCategory = "configuration_issues"

    private let fileIssues = Tome.IssuesObject()
    private var bindingIssues = WindowActionCache.shared.issues
    private var reported: [Tome.Issue] = []
    private var reportedRevision: Int?
    private var notificationIdentifier: String?
    /// One save publishes a burst of snapshots, some stale, so updates are debounced.
    private var pendingUpdate: Task<(), Never>?
    /// Waits on the permission prompt, which may still be up.
    private var pendingReport: (issues: [Tome.Issue], changesNotSaved: Bool)?
    private var isCheckingPermission = false
    private var alert: NSAlert?
    private var observations: Set<AnyCancellable> = []

    func start() {
        fileIssues.$snapshot
            .sink { [weak self] _ in self?.scheduleUpdate() }
            .store(in: &observations)
        NotificationCenter.default.publisher(for: WindowActionCache.issuesDidChange)
            .sink { [weak self] _ in
                guard let self else { return }
                bindingIssues = WindowActionCache.shared.issues
                scheduleUpdate()
            }
            .store(in: &observations)
    }

    private func scheduleUpdate() {
        pendingUpdate?.cancel()
        pendingUpdate = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self else { return }
            update(fileIssues: fileIssues.snapshot)
        }
    }

    private func update(fileIssues snapshot: Tome.Snapshot) {
        let issues = snapshot.issues + bindingIssues
        // Every save is reported, even with the same problems
        guard issues != reported || snapshot.fileRevision != reportedRevision else { return }
        reported = issues
        reportedRevision = snapshot.fileRevision

        guard !issues.isEmpty else {
            pendingReport = nil
            withdrawNotification()
            alert?.window.orderOut(nil)
            alert = nil
            return
        }

        log.warn("Configuration has \(issues.count) issue(s)")
        if let alert {
            configure(alert, issues: issues, changesNotSaved: snapshot.changesNotSaved)
            alert.window.makeKeyAndOrderFront(nil)
            return
        }
        pendingReport = (issues, snapshot.changesNotSaved)
        guard !isCheckingPermission else { return }
        isCheckingPermission = true
        Task {
            let canNotify = await Self.canNotify()
            isCheckingPermission = false
            guard let report = pendingReport else { return }
            pendingReport = nil
            if canNotify {
                notify(issues: report.issues, changesNotSaved: report.changesNotSaved)
            } else {
                showAlert(issues: report.issues, changesNotSaved: report.changesNotSaved)
            }
        }
    }

    private static func lines(for issues: some Collection<Tome.Issue>) -> [String] {
        issues.map { issue in
            if let line = issue.line {
                String(localized: "Line \(line): \(issue.message)", comment: "A problem in config.toml, with its line number")
            } else {
                "\(issue.path): \(issue.message)"
            }
        }
    }

    private static var unsavedNote: String {
        String(localized: "Changes made in Settings can't be saved while the file has errors, and fixing the file replaces them.", comment: "Shown with config.toml problems")
    }

    private static var title: String {
        String(localized: "Configuration error", comment: "Title of the notification or alert about config.toml problems")
    }

    private static func canNotify() async -> Bool {
        let center = UNUserNotificationCenter.current()
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional:
            return true
        case .notDetermined:
            return await (try? center.requestAuthorization(options: [.alert])) ?? false
        default:
            return false
        }
    }

    /// Lists the first three problems; the banner has little room.
    private func notify(issues: [Tome.Issue], changesNotSaved: Bool) {
        var lines = Self.lines(for: issues.prefix(3))
        if issues.count > 3 {
            lines.append(String(localized: "and \(issues.count - 3) more", comment: "Follows a list of config.toml problems"))
        }
        if changesNotSaved {
            lines.append(Self.unsavedNote)
        }
        let message = lines.joined(separator: "\n")
        let center = UNUserNotificationCenter.current()
        let category = UNNotificationCategory(identifier: Self.notificationCategory, actions: [], intentIdentifiers: [])
        center.getNotificationCategories { categories in
            center.setNotificationCategories(categories.union([category]))
        }
        let content = UNMutableNotificationContent()
        content.title = Self.title
        content.body = message
        content.categoryIdentifier = Self.notificationCategory
        // Reusing an identifier would update the old notification silently
        withdrawNotification()
        let identifier = UUID().uuidString
        notificationIdentifier = identifier
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
    }

    private func withdrawNotification() {
        guard let notificationIdentifier else { return }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [notificationIdentifier])
        self.notificationIdentifier = nil
    }

    /// Non-modal, so Loop keeps working while it's open.
    private func showAlert(issues: [Tome.Issue], changesNotSaved: Bool) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = Self.title
        alert.showsHelp = false
        alert.showsSuppressionButton = false
        let open = alert.addButton(withTitle: String(localized: "Open Configuration File", comment: "Alert button that opens config.toml"))
        open.target = self
        open.action = #selector(openFile)
        let dismiss = alert.addButton(withTitle: String(localized: "OK", comment: "Dismisses an alert"))
        dismiss.target = self
        dismiss.action = #selector(dismissAlert)
        configure(alert, issues: issues, changesNotSaved: changesNotSaved)
        alert.window.center()
        alert.window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.alert = alert
    }

    /// Without `runModal()`, the alert must be laid out explicitly or its unused controls appear.
    private func configure(_ alert: NSAlert, issues: [Tome.Issue], changesNotSaved: Bool) {
        alert.informativeText = changesNotSaved ? Self.unsavedNote : ""
        let list = NSTextField(wrappingLabelWithString: Self.lines(for: issues).joined(separator: "\n"))
        list.isSelectable = true
        list.alignment = .left
        list.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        list.preferredMaxLayoutWidth = 260
        list.frame.size = list.fittingSize
        alert.accessoryView = list
        alert.layout()
    }

    @objc private func openFile() {
        dismissAlert()
        ConfigurationManager.shared.openInEditor()
    }

    @objc private func dismissAlert() {
        alert?.window.orderOut(nil)
        alert = nil
    }
}
