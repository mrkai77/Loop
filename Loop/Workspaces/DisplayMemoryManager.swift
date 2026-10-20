//
//  DisplayMemoryManager.swift
//  Loop
//
//  Created on 2026-10-20.
//

import Defaults
import Scribe
import SwiftUI

/// Remembers where windows were for each combination of connected displays, and puts them back
/// when that combination is connected again (e.g. plugging a MacBook back into its monitors).
///
/// macOS moves windows around as soon as a display disappears, so by the time we are notified it is
/// too late to record anything. Instead, the layout of the current configuration is recorded periodically,
/// and recording is paused while displays are changing so the shuffled state never overwrites it.
@Loggable
@MainActor
final class DisplayMemoryManager: ObservableObject {
    static let shared = DisplayMemoryManager()
    private init() {}

    @Published private(set) var currentConfigurationName: String = ""

    private let snapshotInterval: Duration = .seconds(5)
    /// macOS sends several notifications and keeps moving windows for a moment after a display change.
    private let settleDelay: Duration = .seconds(2)

    private var lastConfigurationKey: String = ""
    private var isPaused = false

    private var snapshotTask: Task<(), Never>?
    private var transitionTask: Task<(), Never>?
    private var observers: [NSObjectProtocol] = []
    private var settingsTask: Task<(), Never>?

    func start() {
        lastConfigurationKey = NSScreen.configurationKey
        currentConfigurationName = NSScreen.configurationName

        settingsTask = Task { [weak self] in
            for await enabled in Defaults.updates(.displayMemoryEnabled) {
                guard let self else { return }
                if enabled {
                    startMonitoring()
                } else {
                    stopMonitoring()
                }
            }
        }
    }

    func shutdown() {
        settingsTask?.cancel()
        stopMonitoring()
    }

    private func startMonitoring() {
        guard snapshotTask == nil else { return }
        log.info("Starting display memory")

        lastConfigurationKey = NSScreen.configurationKey
        currentConfigurationName = NSScreen.configurationName

        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.displaysChanged() }
        })

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.screensDidSleepNotification, NSWorkspace.willSleepNotification] {
            observers.append(workspaceCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.pause() }
            })
        }
        for name in [NSWorkspace.screensDidWakeNotification, NSWorkspace.didWakeNotification] {
            observers.append(workspaceCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.displaysChanged() }
            })
        }

        snapshotTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.recordCurrentLayout()
                try? await Task.sleep(for: self?.snapshotInterval ?? .seconds(5))
            }
        }
    }

    private func stopMonitoring() {
        snapshotTask?.cancel()
        snapshotTask = nil
        transitionTask?.cancel()
        transitionTask = nil
        observers.forEach {
            NotificationCenter.default.removeObserver($0)
            NSWorkspace.shared.notificationCenter.removeObserver($0)
        }
        observers.removeAll()
    }

    private func pause() {
        isPaused = true
    }

    private func displaysChanged() {
        isPaused = true
        transitionTask?.cancel()
        transitionTask = Task { [weak self] in
            try? await Task.sleep(for: self?.settleDelay ?? .seconds(2))
            guard let self, !Task.isCancelled else { return }

            let key = NSScreen.configurationKey
            currentConfigurationName = NSScreen.configurationName

            if key != lastConfigurationKey {
                log.info("Display configuration changed to \(currentConfigurationName)")
                lastConfigurationKey = key
                await restoreLayout(fallBackToAnyScreen: false)

                // Some apps move their windows again once they notice the new screens
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                await restoreLayout(fallBackToAnyScreen: false)
            }

            isPaused = false
            recordCurrentLayout()
        }
    }

    /// Puts windows back where they were the last time the current displays were connected.
    func restoreLayout(fallBackToAnyScreen: Bool = true) async {
        guard let layout = Defaults[.displayLayouts][NSScreen.configurationKey] else {
            log.info("No saved layout for \(NSScreen.configurationName)")
            return
        }

        let windows = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .flatMap(WindowArranger.windows(of:))

        let pairs = WindowArranger.match(layout.windows, to: windows, allowLooseMatches: false)
        log.info("Restoring \(pairs.count) window(s) for \(layout.name)")
        await WindowArranger.apply(pairs, fallBackToAnyScreen: fallBackToAnyScreen)
    }

    private func recordCurrentLayout() {
        guard !isPaused, AccessibilityManager.shared.isGranted else { return }

        let key = NSScreen.configurationKey
        // A display change that hasn't been handled yet; don't record windows mid-shuffle
        guard key == lastConfigurationKey else { return }

        let visible = WindowArranger.captureVisibleWindows()
        let visibleIDs = Set(visible.map(\.windowID))
        let runningBundleIDs = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))

        // Windows that are minimized or on another Space aren't visible right now, but should keep their spot
        let kept = (Defaults[.displayLayouts][key]?.windows ?? []).filter {
            !visibleIDs.contains($0.windowID) && runningBundleIDs.contains($0.bundleID)
        }

        let windows = Array((visible + kept).prefix(200))
        let existing = Defaults[.displayLayouts][key]
        guard existing?.windows != windows else { return }

        Defaults[.displayLayouts][key] = DisplayLayout(
            name: NSScreen.configurationName,
            windows: windows,
            updatedAt: .now
        )
    }

    func forgetLayout(_ key: String) {
        Defaults[.displayLayouts][key] = nil
    }
}
