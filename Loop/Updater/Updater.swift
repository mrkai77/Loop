//
//  Updater.swift
//  Loop
//
//  Created by Kami on 11/5/2024.
//

import Defaults
import Luminare
import Scribe
import SwiftUI

@Loggable
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()

    @Published private(set) var updateState: UpdateAvailability = .unavailable {
        didSet { updateStateChanged() }
    }

    @Published private(set) var installState: InstallState = .ready
    @Published private(set) var progressBar: Double = 0
    @Published private(set) var updatesEnabled: Bool = Updater.checkIfUpdatesEnabled()
    @Published private(set) var changelog: [ChangelogSection] = []
    @Published var expandedChangelogSections: Set<String> = [] // By ID
    @Published private(set) var updateManifest: UpdateManifest?

    private(set) var shouldAutoPresentUpdateWindow: Bool = false
    private var windowController: NSWindowController?
    private var includeDevelopmentVersions: Bool { Defaults[.includeDevelopmentVersions] }
    private var automaticallyUpdate: Bool { Defaults[.automaticallyUpdate] }

    private var updateFetcherTask: Task<(), Never>?
    private var updateCheckerTask: Task<(), Never>?
    private var autoPresentUpdateWindowTask: Task<(), Never>?
    private var includeDevelopmentVersionsObserver: Task<(), Never>?
    private var updatesEnabledObserver: Task<(), Never>?

    private let updateChecker: UpdateChecker
    private let downloader: UpdateDownloader
    private let installer: UpdateInstaller

    private init() {
        // Initialize new updater system components
        self.updateChecker = UpdateChecker()
        self.downloader = UpdateDownloader()
        self.installer = UpdateInstaller()

        // Initialize optional properties to nil - will be set up after init
        self.updateCheckerTask = nil
        self.includeDevelopmentVersionsObserver = nil
        self.updatesEnabledObserver = nil

        // Set up observers and tasks after initialization is complete
        Task {
            setupObserversAndTasks()
        }
    }

    private func setupObserversAndTasks() {
        // Set up observers and tasks now that self is fully initialized
        let updatesEnabled = Self.checkIfUpdatesEnabled()
        if updatesEnabled {
            updateCheckerTask = makeUpdateCheckerTask()
            includeDevelopmentVersionsObserver = makeIncludeDevelopmentVersionsObserver()
        }

        updatesEnabledObserver = makeUpdatesEnabledObserver()
    }

    private static func checkIfUpdatesEnabled() -> Bool {
        if ProcessInfo.processInfo.isEnvironmentFlagEnabled("LOOP_SKIP_UPDATE_CHECK") {
            return false
        }
        return Defaults[.updatesEnabled]
    }

    private func updateStateChanged() {
        autoPresentUpdateWindowTask?.cancel()
        autoPresentUpdateWindowTask = nil

        if updateState == .available {
            // If automatic updates are enabled, never auto-present the update window
            if automaticallyUpdate {
                // Only install if Loop is not in use
                if !NSApp.isActive, NSApp.windows.allSatisfy({ !$0.isVisible }) {
                    log.info("Automatic updates enabled, installing update...")
                    Task {
                        try await downloadAndInstallUpdate()
                        await relaunchAfterUpdate()
                    }
                } else {
                    log.info("Automatic updates enabled, but Loop is active. Skipping installation.")
                }

                return
            }

            shouldAutoPresentUpdateWindow = true

            // If the updater has requested that the update window be presented for over 6 hours, automatically present it.
            autoPresentUpdateWindowTask = Task {
                log.info("Will automatically present update window in 6 hours if there is no activity")

                try? await Task.sleep(for: .seconds(21600))

                if !Task.isCancelled, shouldAutoPresentUpdateWindow {
                    await showUpdateWindowIfEligible()
                }

                autoPresentUpdateWindowTask = nil
            }
        } else {
            shouldAutoPresentUpdateWindow = false
        }
    }

    private func makeUpdateCheckerTask() -> Task<(), Never>? {
        Task {
            while !Task.isCancelled {
                // 6 hours
                try? await Task.sleep(for: .seconds(21600))

                await self.fetchLatestInfo()
            }
        }
    }

    private func makeIncludeDevelopmentVersionsObserver() -> Task<(), Never>? {
        Task {
            for await _ in Defaults.updates(.includeDevelopmentVersions, initial: false) {
                guard !Task.isCancelled else { break }
                await fetchLatestInfo()
            }
        }
    }

    private func makeUpdatesEnabledObserver() -> Task<(), Never>? {
        Task {
            for await _ in Defaults.updates(.updatesEnabled) {
                guard !Task.isCancelled else { break }

                updatesEnabled = Updater.checkIfUpdatesEnabled()

                log.info("Updates enabled status changed to: \(updatesEnabled)")

                if updatesEnabled {
                    self.updateCheckerTask = makeUpdateCheckerTask()
                    self.includeDevelopmentVersionsObserver = makeIncludeDevelopmentVersionsObserver()
                } else {
                    self.updateCheckerTask?.cancel()
                    self.includeDevelopmentVersionsObserver?.cancel()
                    self.updateCheckerTask = nil
                    self.includeDevelopmentVersionsObserver = nil

                    updateManifest = nil
                    updateState = .unavailable
                    progressBar = 0
                }
            }
        }
    }

    func dismissWindow() {
        windowController?.close()
        windowController = nil

        // Clear update state when window is dismissed
        updateManifest = nil
        progressBar = 0
        installState = .ready
        shouldAutoPresentUpdateWindow = false
    }

    /// Pulls the latest release information from GitHub and updates the app state accordingly.
    func fetchLatestInfo(bypassUpdatesEnabled: Bool = false) async {
        // Don't run update checks while actively downloading
        if downloader.isDownloading == true {
            return
        }

        if let updateFetcherTask {
            await updateFetcherTask.value // If already fetching, wait for it to finish
            return
        }

        updateFetcherTask = Task {
            defer { updateFetcherTask = nil }

            // Don't clear update state if window is currently showing (user is interacting)
            if windowController?.window?.isVisible != true {
                updateManifest = nil
                progressBar = 0
            }

            // Early return if updates are disabled and not forcing
            guard updatesEnabled || bypassUpdatesEnabled else {
                updateState = .unavailable
                log.warn("Updates are disabled. Not fetching latest info.")
                return
            }

            log.info("Fetching latest release info...")

            do {
                // Use GitHub releases API
                let channel: UpdateChannel = includeDevelopmentVersions ? .development : .stable

                let currentVersion = Bundle.main.appVersion?.filter(\.isASCII)
                    .trimmingCharacters(in: .whitespaces) ?? "0.0.0"
                let currentBuild = Bundle.main.appBuild ?? 0

                if let manifest = try await updateChecker.checkForUpdate(
                    currentVersion: currentVersion,
                    currentBuild: currentBuild,
                    channel: channel
                ) {
                    changelog = ChangelogParser.parse(manifest.releaseNotes.body)
                    if let firstSection = changelog.first {
                        expandedChangelogSections = [firstSection.id]
                    }

                    updateManifest = manifest
                    updateState = .available

                    log.notice("Update available: \(manifest.version) build \(manifest.buildNumber)")
                } else {
                    updateState = .unavailable

                    log.info("No updates available")
                }
            } catch {
                if case .incompatibleSystem? = error as? UpdateError {
                    updateState = .osNotSupported
                } else {
                    updateState = .unavailable
                }

                log.error("Error fetching release info: \(error.localizedDescription)")
            }
        }

        await updateFetcherTask?.value
    }

    func showUpdateWindowIfEligible() async {
        shouldAutoPresentUpdateWindow = false
        guard updateState == .available else { return }

        if windowController?.window == nil {
            windowController = .init(window: LuminareWindow(cornerRadius: 20) { UpdateView() })
        }
        windowController?.window?.makeKeyAndOrderFront(self)
        windowController?.window?.orderFrontRegardless()

        log.ui("Update window shown")
    }

    /// Downloads the update from GitHub and installs it
    func downloadAndInstallUpdate() async throws {
        guard let manifest = updateManifest else {
            let error = UpdateError.installationFailed(
                "No update information is available. Please check for updates again and retry."
            )
            log.error("Cannot start installation: update manifest is missing")
            progressBar = 0
            installState = .failed(error)
            throw error
        }

        installState = .installing

        log.info("Installing update: \(manifest.version)")

        do {
            let downloadedFileURL = try await downloader.downloadUpdate(manifest: manifest) { [weak self] progress in
                self?.progressBar = progress.percentage * 0.75
            }

            try await installer.installUpdate(from: downloadedFileURL, manifest: manifest) { [weak self] progress in
                self?.progressBar = 0.75 + (progress.percentage * 0.25)
            }

            progressBar = 1.0
            updateState = .unavailable

            // Brief delay before showing restart button
            try? await Task.sleep(for: .seconds(1))

            installState = .readyToRestart

            log.success("Update installed successfully")
        } catch {
            log.error("Update installation failed: \(error)")
            progressBar = 0
            installState = .failed(error)
            throw error
        }
    }

    func relaunchAfterUpdate() async {
        guard installState == .readyToRestart else {
            log.error("Cannot restart as the install state is \(installState)")
            return
        }

        await installer.restartApplication()
    }
}
