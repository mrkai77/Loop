//
//  AppDelegate.swift
//  Loop
//
//  Created by Kai Azim on 2023-10-05.
//

import Darwin
import Defaults
import Scribe
import SwiftUI
import UserNotifications

@Loggable
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let terminateNotificationName = Notification.Name("com.MrKai77.Loop.terminate")
    private var terminateObserver: Any?

    /// Launched from Finder, the Dock or `open`, rather than at login or to open a `loop://` URL, which has no open-application event
    private var launchedByUser: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent, event.eventID == kAEOpenApplication else {
            return false
        }

        return event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue != keyAELaunchedAsLogInItem
    }

    func applicationDidFinishLaunching(_: Notification) {
        configureLogging()
        DefaultsiCloudSyncRegistrar.register()

        // Register before broadcasting so other instances can receive the signal
        registerTerminateObserver()

        let dataPatcherTask = Task { @MainActor in
            await Defaults.iCloud.waitForSyncCompletion()
            DataPatcher.run()
        }

        // Show settings window only if launched by the user AND startHidden is disabled
        if launchedByUser, !Defaults[.startHidden] {
            SettingsWindowManager.shared.show()
        } else {
            // Closing also hides the dock icon if needed.
            SettingsWindowManager.shared.close()
        }

        IconManager.refreshCurrentAppIcon()
        LaunchAtLoginManager.shared.start()

        UNUserNotificationCenter.current().delegate = self
        AppDelegate.requestNotificationAuthorization()

        // Register for URL handling
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )

        // Wait for other instances to fully exit before installing event taps to prevent conflicts
        Task { @MainActor in
            await dataPatcherTask.value

            let stalePIDs = broadcastTerminateToOtherInstances()
            await waitForInstancesToExit(pids: stalePIDs, timeout: .seconds(3))
            LoopManager.shared.start()
            // After older instances exit, as they remove their socket file while quitting
            LoopSocketManager.shared.start()
            WindowDragManager.shared.addObservers()
            StashManager.shared.start()
            AccessibilityManager.requestAccess()

            // Wait for the app to settle before showing the update window
            try? await Task.sleep(for: .seconds(5))
            await Updater.shared.fetchLatestInfo()
            await Updater.shared.showUpdateWindowIfEligible()
        }
    }

    /// Subscribes to the terminate notification so this instance shuts down when a newer Loop instance launches.
    private func registerTerminateObserver() {
        terminateObserver = DistributedNotificationCenter.default().addObserver(
            forName: Self.terminateNotificationName,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }

            // Ignore our own broadcast (for obvious reasons)
            if let senderPID = notification.userInfo?["pid"] as? Int,
               senderPID == Int(ProcessInfo.processInfo.processIdentifier) {
                return
            }

            log.info("Received terminate broadcast from newer Loop instance, shutting down")
            NSApp.terminate(nil)
        }
    }

    /// Sends the terminate notification to any other running Loop instances, and returns their PIDs.
    @discardableResult
    private func broadcastTerminateToOtherInstances() -> [pid_t] {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let bundleId = Bundle.main.bundleIdentifier ?? "com.MrKai77.Loop"

        let otherInstances = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == bundleId && $0.processIdentifier != currentPID
        }

        guard !otherInstances.isEmpty else {
            log.info("No other Loop instances found")
            return []
        }

        log.info("Found \(otherInstances.count) other Loop instance(s), broadcasting terminate notification")

        DistributedNotificationCenter.default().post(
            name: Self.terminateNotificationName,
            object: nil,
            userInfo: ["pid": Int(currentPID)]
        )

        return otherInstances.map(\.processIdentifier)
    }

    /// Waits until all provided PIDs have exited, or until the timeout is reached.
    private func waitForInstancesToExit(pids: [pid_t], timeout: Duration) async {
        guard !pids.isEmpty else { return }

        let deadline = ContinuousClock.now + timeout

        while ContinuousClock.now < deadline {
            let allGone = pids.allSatisfy { NSRunningApplication(processIdentifier: $0) == nil }
            if allGone {
                log.info("All prior Loop instances have exited")
                return
            }
            try? await Task.sleep(for: .milliseconds(100))
        }

        let surviving = pids.filter { NSRunningApplication(processIdentifier: $0) != nil }
        if !surviving.isEmpty {
            log.warn("Timed out waiting for prior Loop instances to exit, force killing \(surviving.count) instance(s)")
            for pid in surviving {
                kill(pid, SIGKILL)
            }
        }
    }

    /// Applies baseline logging configuration for Scribe.
    private func configureLogging() {
        LogManager.shared.configuration.includeFileAndLineNumber = false
    }

    @objc func handleGetURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent _: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: urlString) else {
            log.info("Failed to get URL from event")
            return
        }

        processIncomingURL(url)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        SettingsWindowManager.shared.close()
        return false
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        SettingsWindowManager.shared.show()
        return true
    }

    func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
        // LoopManager and WindowDragManager are explicitly shut down so that their
        // event monitors are stopped immediately (in case they are active)
        LoopManager.shared.shutdown()
        WindowDragManager.shared.shutdown()
        StashManager.shared.shutdown()
        LoopSocketManager.shared.shutdown()
        return .terminateNow
    }

    func application(_: NSApplication, open urls: [URL]) {
        for url in urls {
            processIncomingURL(url)
        }
    }

    private func processIncomingURL(_ url: URL) {
        log.info("Received URL: \(url)")

        Task { @MainActor in
            // macOS gives Loop a Dock icon before handing it a URL, as Loop isn't an `LSUIElement` app
            SettingsWindowManager.shared.hideDockIconIfUnused()

            let result = await LoopCommandHandler.shared.handle(url)
            log.debug("Response: \(result.jsonResponse)")
            result.presentIfNeeded()
        }
    }
}
