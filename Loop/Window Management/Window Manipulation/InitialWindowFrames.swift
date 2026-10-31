import AppKit
import Defaults

enum InitialWindowFrames {
    /// Returns an app's configured initial frame action without changing any windows.
    /// Dynamic size modes depend on a window's current size or action history.
    static func action(for app: NSRunningApplication) -> WindowAction? {
        guard let id = app.bundleIdentifier, id != Bundle.main.bundleIdentifier,
              let url = app.bundleURL, !Defaults[.excludedApps].contains(url),
              let action = Defaults[.initialWindowFrames][id],
              action.direction == .custom, action.sizeMode == .custom else { return nil }
        return action
    }

    /// Calculates the configured frame on the supplied display without resizing the window.
    /// Uses actual window properties so pixel dimensions are not scaled as an editor preview.
    static func frame(for window: Window, on screen: NSScreen) -> (frame: CGRect, bounds: CGRect)? {
        guard let app = window.nsRunningApplication, let action = action(for: app) else { return nil }
        let properties = Window.ResolvedProperties(from: window)
        let context = ResizeContext(window: window, initialFrame: properties.frame, screen: screen, action: action)
        context.resolvedWindowProperties = properties
        guard let frame = constrain(context.getTargetFrame().padded, to: context.paddedBounds) else { return nil }
        return (frame, context.paddedBounds)
    }

    /// Keep the requested frame within the display's usable area.
    static func constrain(_ frame: CGRect, to bounds: CGRect) -> CGRect? {
        guard frame.isFinite, bounds.isFinite, frame.size.width > 0, frame.size.height > 0,
              bounds.size.width > 0, bounds.size.height > 0 else { return nil }
        var result = frame
        result.size = CGSize(width: min(frame.width, bounds.width), height: min(frame.height, bounds.height))
        return result.pushInside(bounds)
    }

    enum Readiness { case wait, skip, ready }

    /// Wait briefly for accessibility readiness; cancellation ends the wait.
    @MainActor
    static func waitUntilReady(_ check: () -> Readiness) async -> Bool {
        for delay in [Duration.zero, .milliseconds(25), .milliseconds(75), .milliseconds(250)] {
            do {
                if delay > .zero { try await Task.sleep(for: delay) }
            } catch { return false }
            guard !Task.isCancelled else { return false }
            switch check() {
            case .wait: continue
            case .skip: return false
            case .ready: return !Task.isCancelled
            }
        }
        return false
    }
}
