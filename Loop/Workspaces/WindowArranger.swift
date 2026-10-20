//
//  WindowArranger.swift
//  Loop
//
//  Created on 2026-10-20.
//

import Defaults
import Scribe
import SwiftUI

/// Records where windows are and puts them back, shared by display memory and workspaces.
@Loggable(style: .static)
@MainActor
enum WindowArranger {
    /// Windows that Loop should never record or move.
    private static func isManageable(_ window: Window) -> Bool {
        guard !window.isOwnWindow,
              !window.isAppExcluded,
              window.nsRunningApplication?.activationPolicy == .regular,
              window.nsRunningApplication?.bundleIdentifier != nil,
              Defaults[.stashManagerStashedWindows][window.cgWindowID] == nil
        else {
            return false
        }
        return true
    }

    /// Captures every visible window, ordered front-to-back.
    static func captureVisibleWindows() -> [WindowPlacement] {
        WindowUtility.windowList()
            .filter(isManageable)
            .compactMap(placement(for:))
    }

    static func placement(for window: Window) -> WindowPlacement? {
        guard let bundleID = window.nsRunningApplication?.bundleIdentifier,
              let screen = ScreenUtility.screenContaining(window)
        else {
            return nil
        }

        let frame = window.frame
        guard frame.width > 1, frame.height > 1 else {
            return nil
        }

        let bounds = screen.displayBounds
        return WindowPlacement(
            windowID: window.cgWindowID,
            bundleID: bundleID,
            appName: window.nsRunningApplication?.localizedName ?? bundleID,
            title: window.title ?? "",
            screen: ScreenReference(screen: screen),
            frameInScreen: frame.offsetBy(dx: -bounds.minX, dy: -bounds.minY),
            screenSize: bounds.size
        )
    }

    /// All standard windows of an app, including ones that are minimized or on other screens.
    static func windows(of app: NSRunningApplication) -> [Window] {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        guard let elements: [AXUIElement] = try? element.getValue(.windows) else {
            return []
        }

        return elements
            .compactMap { try? Window(element: $0, pid: app.processIdentifier, nsRunningApplication: app) }
            .filter { $0.subrole == .standardWindow }
    }

    /// Pairs saved placements with live windows.
    ///
    /// Matching prefers the same window ID (the window never closed), then the same app with the same title,
    /// then any remaining window of the same app, in order.
    static func match(
        _ placements: [WindowPlacement],
        to windows: [Window],
        allowLooseMatches: Bool
    ) -> [(Window, WindowPlacement)] {
        var remaining = windows
        var unmatched: [WindowPlacement] = []
        var result: [(Window, WindowPlacement)] = []

        func take(where predicate: (Window) -> Bool) -> Window? {
            guard let index = remaining.firstIndex(where: predicate) else { return nil }
            return remaining.remove(at: index)
        }

        for placement in placements {
            if let window = take(where: { $0.cgWindowID == placement.windowID && $0.nsRunningApplication?.bundleIdentifier == placement.bundleID }) {
                result.append((window, placement))
            } else {
                unmatched.append(placement)
            }
        }

        var stillUnmatched: [WindowPlacement] = []
        for placement in unmatched {
            if !placement.title.isEmpty,
               let window = take(where: { $0.nsRunningApplication?.bundleIdentifier == placement.bundleID && $0.title == placement.title }) {
                result.append((window, placement))
            } else {
                stillUnmatched.append(placement)
            }
        }

        if allowLooseMatches {
            for placement in stillUnmatched {
                if let window = take(where: { $0.nsRunningApplication?.bundleIdentifier == placement.bundleID }) {
                    result.append((window, placement))
                }
            }
        }

        return result
    }

    /// Moves each window to its placement. Windows on a screen that is no longer connected are left alone
    /// unless `fallBackToAnyScreen` is set.
    static func apply(_ pairs: [(Window, WindowPlacement)], fallBackToAnyScreen: Bool) async {
        for (window, placement) in pairs {
            guard !window.fullscreen else { continue }

            let screen: NSScreen? = if fallBackToAnyScreen {
                placement.screen.resolve()
            } else {
                NSScreen.screens.first { $0.displayUUID == placement.screen.uuid && placement.screen.uuid != nil }
            }

            guard let screen else { continue }

            if window.minimized {
                window.minimized = false
            }

            let target = placement.frame(on: screen)
            if !window.frame.approximatelyEqual(to: target, tolerance: 2) {
                log.info("Restoring \(window) to \(target)")
                await window.setFrame(target, sizeFirst: !screen.displayBounds.contains(window.frame))
            }
        }
    }
}
