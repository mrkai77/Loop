import Defaults
import SwiftUI

@MainActor
final class InitialWindowFrameManager {
    static let shared = InitialWindowFrameManager()

    private final class Observation {
        let observer: AXObserver
        var seen = Set<AXUIElement>()
        var pending: [AXUIElement: (token: UUID, task: Task<(), Never>)] = [:]

        init(observer: AXObserver) {
            self.observer = observer
        }
    }

    private var observations: [pid_t: Observation] = [:]
    private var registrations: [pid_t: (token: UUID, task: Task<(), Never>)] = [:]
    private var subscriptions: [Task<(), Never>] = []
    private var workspaceObservers: [NSObjectProtocol] = []

    private init() {}

    func start() {
        guard subscriptions.isEmpty else { return }
        let frames = Defaults.updates(.initialWindowFrames, initial: false)
        let exclusions = Defaults.updates(.excludedApps, initial: false)
        let permission = AccessibilityManager.shared.stream(initial: false)
        subscriptions = [
            Task { for await _ in frames { reset() } },
            Task { for await _ in exclusions { reset() } },
            Task { for await _ in permission { reset() } }
        ]
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            MainActor.assumeIsolated { self?.register(app, includeExisting: true) }
        })
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            MainActor.assumeIsolated { self?.remove(app.processIdentifier) }
        })
        reset()
    }

    func shutdown() {
        subscriptions.forEach { $0.cancel() }
        subscriptions.removeAll()
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceObservers.removeAll()
        for pid in Set(observations.keys).union(registrations.keys) { remove(pid) }
    }

    private func action(for app: NSRunningApplication) -> WindowAction? {
        guard !subscriptions.isEmpty, AccessibilityManager.shared.isGranted,
              !app.isTerminated, app.activationPolicy == .regular else { return nil }
        return InitialWindowFrames.action(for: app)
    }

    private func reset() {
        guard !Task.isCancelled, !subscriptions.isEmpty else { return }
        for pid in Set(observations.keys).union(registrations.keys) { remove(pid) }
        // Configuration changes establish a fresh baseline, never rearrange existing windows.
        for app in NSWorkspace.shared.runningApplications { register(app, includeExisting: false) }
    }

    private func remove(_ pid: pid_t) {
        registrations.removeValue(forKey: pid)?.task.cancel()
        guard let observation = observations.removeValue(forKey: pid) else { return }
        observation.pending.values.forEach { $0.task.cancel() }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observation.observer), .commonModes)
    }

    private func register(_ app: NSRunningApplication, includeExisting: Bool) {
        let pid = app.processIdentifier
        guard action(for: app) != nil, observations[pid] == nil, registrations[pid] == nil else { return }
        let token = UUID()
        let task = Task {
            defer { if registrations[pid]?.token == token { registrations[pid] = nil } }
            // AX may not be ready when the workspace reports an application launch.
            for delay in [Duration.zero, .milliseconds(200), .milliseconds(500), .seconds(1)] {
                do {
                    if delay > .zero { try await Task.sleep(for: delay) }
                } catch { return }
                guard !Task.isCancelled, action(for: app) != nil else { return }
                if install(app, includeExisting: includeExisting) { return }
            }
        }
        registrations[pid] = (token, task)
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
              AXObserverAddNotification(observer, application, kAXWindowCreatedNotification as CFString, nil) == .success else { return false }
        guard let windows: [AXUIElement] = try? application.getValue(.windows) else {
            AXObserverRemoveNotification(observer, application, kAXWindowCreatedNotification as CFString)
            return false
        }
        let observation = Observation(observer: observer)
        if !includeExisting { observation.seen = Set(windows) }
        observations[pid] = observation
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        for window in windows {
            AXObserverAddNotification(observer, window, kAXUIElementDestroyedNotification as CFString, nil)
            if includeExisting { created(window, app: app, observation: observation) }
        }
        return true
    }

    private func receive(_ observer: AXObserver, element: AXUIElement, notification: String) {
        guard let (pid, observation) = observations.first(where: { CFEqual($0.value.observer, observer) }) else { return }
        if notification == kAXUIElementDestroyedNotification {
            observation.pending.removeValue(forKey: element)?.task.cancel()
            observation.seen.remove(element)
        } else if notification == kAXWindowCreatedNotification, let app = NSRunningApplication(processIdentifier: pid) {
            AXObserverAddNotification(observer, element, kAXUIElementDestroyedNotification as CFString, nil)
            created(element, app: app, observation: observation)
        }
    }

    private func readableFrame(_ element: AXUIElement) -> CGRect? {
        guard let position: CGPoint = try? element.getValue(.position), let size: CGSize = try? element.getValue(.size),
              [position.x, position.y, size.width, size.height].allSatisfy(\.isFinite), size.width > 0, size.height > 0 else { return nil }
        return CGRect(origin: position, size: size)
    }

    private func created(_ element: AXUIElement, app: NSRunningApplication, observation: Observation) {
        guard observation.seen.insert(element).inserted, let configured = action(for: app) else { return }
        AXUIElementSetMessagingTimeout(element, 0.1)
        var initialFrame = readableFrame(element)
        let pid = app.processIdentifier
        let token = UUID()
        let task = Task {
            defer { if observation.pending[element]?.token == token { observation.pending[element] = nil } }
            _ = await InitialWindowFrames.waitUntilReady {
                guard observations[pid] === observation, action(for: app) == configured else { return .skip }
                guard let frame = readableFrame(element) else { return .wait }
                if let initialFrame, initialFrame != frame { return .skip }
                initialFrame = frame
                do {
                    guard let role: String = try element.getValue(.subrole),
                          let minimized: Bool = try element.getValue(.minimized) else { return .wait }
                    let fullscreen: Bool = try element.getValue(.fullScreen) ?? false
                    guard role == NSAccessibility.Subrole.standardWindow.rawValue, !minimized, !fullscreen else { return .skip }
                    // Native tabs can publish a new AX window even though the user
                    // is still in the same window. Do not reposition the tab group.
                    guard try !InitialWindowFrames.hasMultipleWindowTabs(element) else { return .skip }
                    // Window.isResizable returns true on AX errors; automatic placement must wait instead.
                    guard try element.canSetValue(.size), let candidate = try? Window(element: element, pid: pid) else { return .wait }
                    guard readableFrame(element) == frame else { return .skip }
                    return place(candidate)
                } catch { return .wait }
            }
        }
        observation.pending[element] = (token, task)
    }

    private func place(_ window: Window) -> InitialWindowFrames.Readiness {
        guard let screen = ScreenUtility.screenContaining(window),
              let (frame, bounds) = InitialWindowFrames.frame(for: window, on: screen),
              window.setFrameSynchronously(frame, sizeFirst: true) else { return .skip }
        guard let applied = readableFrame(window.axWindow) else { return .skip }
        _ = WindowEngine.handleSizeConstrainedWindow(window: window, actualFrame: applied, targetFrame: frame, bounds: bounds)
        return .ready
    }
}
