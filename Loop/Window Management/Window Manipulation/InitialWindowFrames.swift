//
//  InitialWindowFrames.swift
//  Loop
//

import AppKit
import Defaults

enum InitialWindowFrames {
    static func allowsPlacement(bundleID: String, url: URL) -> Bool {
        bundleID != Bundle.main.bundleIdentifier && !Defaults[.excludedApps].contains(url)
    }

    /// Returns an app's configured initial frame action without changing any windows.
    /// Dynamic size modes depend on a window's current size or action history.
    static func action(for app: NSRunningApplication) -> WindowAction? {
        guard let id = app.bundleIdentifier,
              let url = app.bundleURL,
              allowsPlacement(bundleID: id, url: url),
              let action = Defaults[.initialWindowFrames][id],
              action.direction == .custom,
              action.sizeMode == .custom
        else {
            return nil
        }
        return action
    }

    /// Calculates the configured frame on the supplied display without resizing the window.
    /// Uses actual window properties so pixel dimensions are not scaled as an editor preview.
    static func frame(for window: Window, on screen: NSScreen) -> (frame: CGRect, bounds: CGRect)? {
        guard let app = window.nsRunningApplication, let action = action(for: app) else {
            return nil
        }
        let properties = Window.ResolvedProperties(from: window)
        let context = ResizeContext(window: window, initialFrame: properties.frame, screen: screen, action: action)
        context.resolvedWindowProperties = properties
        guard let frame = placementFrame(in: context) else {
            return nil
        }
        return (frame, context.paddedBounds)
    }

    /// Fit the requested size on the display before inner padding clips the frame to its bounds.
    static func placementFrame(in context: ResizeContext) -> CGRect? {
        let bounds = context.paddedBounds
        let rawFrame = WindowFrameResolver.getFrame(resizeContext: context).frame
        // The resolver also returns zero for invalid geometry. Only forward an explicitly requested zero.
        guard rawFrame.size.width > 0 || context.action.width == 0,
              rawFrame.size.height > 0 || context.action.height == 0,
              let fitted = constrain(rawFrame, to: bounds)
        else {
            return nil
        }

        let padded = context.padding.applyToWindow(
            frame: fitted,
            paddedBounds: bounds,
            action: context.action,
            resolvedWindowProperties: context.resolvedWindowProperties
        )
        return constrain(padded, to: bounds)
    }

    /// Keep the requested frame within the display's usable area.
    static func constrain(_ frame: CGRect, to bounds: CGRect) -> CGRect? {
        guard frame.isFinite,
              bounds.isFinite,
              frame.size.width >= 0,
              frame.size.height >= 0,
              bounds.size.width > 0,
              bounds.size.height > 0
        else {
            return nil
        }
        var result = frame
        result.size = CGSize(width: min(frame.width, bounds.width), height: min(frame.height, bounds.height))
        return result.pushInside(bounds)
    }

    enum Readiness {
        case wait
        case skip
        case ready
    }

    /// Check direct window children only; do not search through app content.
    static func hasMultipleWindowTabs(_ window: AXUIElement) throws -> Bool {
        let children: [AXUIElement] = try window.getValue(.children) ?? []
        for child in children {
            let error = AXUIElementSetMessagingTimeout(child, 0.1)
            guard error == .success else {
                throw error
            }
            let role: String? = try child.getValue(.role)
            guard role == NSAccessibility.Role.tabGroup.rawValue else {
                continue
            }
            let tabs: [AXUIElement] = try child.getValue(.tabs) ?? []
            if tabs.count > 1 {
                return true
            }
        }
        return false
    }

    /// Wait briefly for accessibility readiness; cancellation ends the wait.
    @MainActor
    static func waitUntilReady(_ check: () -> Readiness) async -> Bool {
        for delay in [Duration.zero, .milliseconds(25), .milliseconds(75), .milliseconds(250)] {
            do {
                if delay > .zero {
                    try await Task.sleep(for: delay)
                }
            } catch {
                return false
            }
            guard !Task.isCancelled else {
                return false
            }
            switch check() {
            case .wait: continue
            case .skip: return false
            case .ready: return !Task.isCancelled
            }
        }
        return false
    }
}
