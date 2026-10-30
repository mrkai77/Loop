import Defaults
import SwiftUI

/// Observes only opted-in applications. Initial placement never enters the interactive
/// action engine: it does not focus, raise, move the cursor, exit fullscreen or record Undo.
@MainActor
final class InitialWindowFrameManager {
    static let shared = InitialWindowFrameManager()

    private final class Observation {
        let observer: AXObserver
        let application: AXUIElement
        var windows = InitialWindowTracker<AXUIElement>()
        var pending: [AXUIElement: (token: UUID, task: Task<(), Never>)] = [:]

        init(observer: AXObserver, application: AXUIElement) {
            self.observer = observer
            self.application = application
        }
    }

    private var observations: [pid_t: Observation] = [:]
    private var registrations: [pid_t: Task<(), Never>] = [:]
    private var subscriptions: [Task<(), Never>] = []
    private var workspaceObservers: [NSObjectProtocol] = []

    private init() {}

    func start() {
        guard subscriptions.isEmpty else { return }
        subscriptions = [
            Task { for await _ in Defaults.updates(.initialWindowFramesEnabled, initial: false) { resetObservations() } },
            Task { for await _ in Defaults.updates(.initialWindowFrames, initial: false) { resetObservations() } },
            Task { for await _ in Defaults.updates(.excludedApps, initial: false) { resetObservations() } },
            Task { for await _ in AccessibilityManager.shared.stream(initial: false) { resetObservations() } }
        ]
        resetObservations()
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            MainActor.assumeIsolated { self?.register(app, includeExisting: true) }
        })
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            MainActor.assumeIsolated { self?.remove(app.processIdentifier) }
        })
    }

    func shutdown() {
        subscriptions.forEach { $0.cancel() }
        subscriptions.removeAll()
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceObservers.removeAll()
        for pid in Set(observations.keys).union(registrations.keys) { remove(pid) }
    }

    private func action(for app: NSRunningApplication) -> WindowAction? {
        guard !subscriptions.isEmpty, Defaults[.initialWindowFramesEnabled], AccessibilityManager.shared.isGranted,
              !app.isTerminated, app.activationPolicy == .regular,
              let id = app.bundleIdentifier, id != Bundle.main.bundleIdentifier,
              let url = app.bundleURL, !Defaults[.excludedApps].contains(url) else { return nil }
        return Defaults[.initialWindowFrames][id]
    }

    private func resetObservations() {
        guard !Task.isCancelled, !subscriptions.isEmpty else { return }
        for pid in Set(observations.keys).union(registrations.keys) { remove(pid) }
        // Enabling, editing or regaining permission seeds existing windows as a baseline.
        for app in NSWorkspace.shared.runningApplications { register(app, includeExisting: false) }
    }

    private func remove(_ pid: pid_t) {
        registrations.removeValue(forKey: pid)?.cancel()
        guard let observation = observations.removeValue(forKey: pid) else { return }
        observation.pending.values.forEach { $0.task.cancel() }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observation.observer), .commonModes)
    }

    private func register(_ app: NSRunningApplication, includeExisting: Bool) {
        let pid = app.processIdentifier
        guard action(for: app) != nil, observations[pid] == nil, registrations[pid] == nil else { return }
        registrations[pid] = Task {
            // Apps may announce launch before their AX server is ready. This is bounded,
            // and cancellation prevents a pending registration surviving a settings change.
            for attempt in 0 ..< 4 {
                if attempt > 0 { try? await Task.sleep(for: .milliseconds(200)) }
                guard !Task.isCancelled, action(for: app) != nil else { return }
                if install(app, includeExisting: includeExisting) { break }
            }
            registrations[pid] = nil
        }
    }

    private func install(_ app: NSRunningApplication, includeExisting: Bool) -> Bool {
        let pid = app.processIdentifier
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.1)
        var observer: AXObserver?
        guard AXObserverCreate(pid, { observer, element, notification, _ in
                  MainActor.assumeIsolated {
                      InitialWindowFrameManager.shared.receive(observer, element: element, notification: notification as String)
                  }
              }, &observer) == .success, let observer,
              AXObserverAddNotification(observer, application, kAXWindowCreatedNotification as CFString, nil) == .success,
              let windows: [AXUIElement] = try? application.getValue(.windows) else { return false }

        let observation = Observation(observer: observer, application: application)
        observations[pid] = observation
        if !includeExisting { observation.windows = InitialWindowTracker(existing: windows) }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        for window in windows {
            AXObserverAddNotification(observer, window, kAXUIElementDestroyedNotification as CFString, nil)
            if includeExisting { created(window, pid: pid, observation: observation) }
        }
        return true
    }

    private func receive(_ observer: AXObserver, element: AXUIElement, notification: String) {
        guard let (pid, observation) = observations.first(where: { CFEqual($0.value.observer, observer) }) else { return }
        if notification == kAXUIElementDestroyedNotification {
            observation.pending.removeValue(forKey: element)?.task.cancel()
            observation.windows.remove(element)
        } else if notification == kAXWindowCreatedNotification {
            AXObserverAddNotification(observer, element, kAXUIElementDestroyedNotification as CFString, nil)
            created(element, pid: pid, observation: observation)
        }
    }

    private func created(_ element: AXUIElement, pid: pid_t, observation: Observation) {
        guard observation.windows.insert(element),
              let app = NSRunningApplication(processIdentifier: pid), let configuredAction = action(for: app) else { return }
        AXUIElementSetMessagingTimeout(element, 0.1)
        guard let position: CGPoint = try? element.getValue(.position),
              let size: CGSize = try? element.getValue(.size),
              size.width > 0, size.height > 0 else { return }
        let initialFrame = CGRect(origin: position, size: size)
        let token = UUID()
        let task = Task {
            defer {
                if observation.pending[element]?.token == token { observation.pending[element] = nil }
            }
            // Give newly created windows time to publish their resizability (notably Finder).
            for delay in [0, 350] {
                if delay > 0 { try? await Task.sleep(for: .milliseconds(delay)) }
                guard !Task.isCancelled, observations[pid] === observation,
                      action(for: app) == configuredAction,
                      let window = try? Window(element: element, pid: pid),
                      window.subrole == .standardWindow, !window.minimized, !window.fullscreen,
                      window.frame == initialFrame else { return }
                guard window.isResizable else { continue }
                place(window, action: configuredAction, application: observation.application)
                return
            }
        }
        observation.pending[element] = (token, task)
    }

    private func place(_ window: Window, action: WindowAction, application: AXUIElement) {
        let current = window.frame
        guard let screen = ScreenUtility.screenContaining(window),
              let frame = InitialWindowFrames.frame(for: action, bounds: screen.cgSafeScreenFrame, currentSize: current.size) else { return }
        let enhanced: Bool = (try? application.getValue(.enhancedUserInterface)) ?? false
        if enhanced { try? application.setValue(.enhancedUserInterface, value: false) }
        defer { if enhanced { try? application.setValue(.enhancedUserInterface, value: true) } }
        window.setSize(frame.size)
        // Re-anchor using the app's accepted minimum size, then use the existing AX setters.
        if let accepted = InitialWindowFrames.frame(for: action, bounds: screen.cgSafeScreenFrame, currentSize: current.size, resizedSize: window.size) {
            window.setPosition(accepted.origin)
            window.setSize(accepted.size)
        }
    }
}
