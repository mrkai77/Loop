//
//  WindowUtility.swift
//  Loop
//
//  Created by Kai Azim on 2025-09-06.
//

import AppKit
import Defaults
import Scribe

/// This enum is in charge of fetching windows in the user's workspace, which will be used by Loop.
@Loggable(style: .static)
enum WindowUtility {
    /// Get the target window, depending on the user's preferences. This could be the frontmost window, or the window under the cursor.
    /// - Returns: The target window
    static func userDefinedTargetWindow() -> Window? {
        var result: Window?

        if Defaults[.resizeWindowUnderCursor] {
            log.info("Getting window at cursor...")

            if let mouseLocation = CGEvent.mouseLocation,
               let window = windowAtPosition(mouseLocation) {
                result = window
            }
        }

        if result == nil {
            do {
                result = try frontmostWindow()
            } catch {
                log.warn("Failed to get frontmost window: \(error.localizedDescription)")
            }
        }

        if let result {
            log.debug("Determined target window: \(result)")
        }

        return result
    }

    /// Get the frontmost Window
    /// - Returns: Window?
    static func frontmostWindow() throws -> Window? {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return nil
        }

        // NSRunningApplication can occasionally report a pid of -1, so fall back to
        // asking the AX API for the focused application instead.
        if app.processIdentifier <= 0 {
            log.warn("Frontmost app '\(app.localizedName ?? "<unknown>")' reported invalid pid \(app.processIdentifier), falling back to focused application")

            guard let focusedApp: AXUIElement = try AXUIElement.systemWide.getValue(NSAccessibility.Attribute(rawValue: kAXFocusedApplicationAttribute)) else {
                return nil
            }

            return try Window(pid: focusedApp.getPID())
        }

        return try Window(pid: app.processIdentifier)
    }

    /// Get the Window at a given position.
    /// - Parameter position: The position to check for
    /// - Returns: The window at the given position, if any
    static func windowAtPosition(_ position: CGPoint) -> Window? {
        do {
            // Try SkyLight first, as it is faster and doesn't deadlock on own process
            if let windowID = SkyLightToolBelt.windowIDAtPosition(position) {
                return try Window.fromWindowID(windowID)
            }
        } catch {
            if let windowError = error as? WindowError,
               case .blockedBundleID = windowError {
                // no sense in looking deeper if we find a valid-but-blocked window
                return nil
            }
        }

        do {
            // If we can find the window at a point using the Accessibility API, return it
            if let element = try AXUIElement.systemWide.getElementAtPosition(position),
               let windowElement: AXUIElement = try element.getValue(.window) {
                return try Window(element: windowElement)
            }
        } catch {
            if let windowError = error as? WindowError,
               case .blockedBundleID = windowError {
                // no sense in looking deeper if we find a valid-but-blocked window
                return nil
            }

            log.warn("Failed to determine element at position: \(error.localizedDescription)")
        }

        // If the previous method didn't work, loop through all windows on-screen and return the first one that contains the desired point
        let windowList = windowList()
        if let window = (windowList.first { $0.frame.contains(position) }) {
            return window
        }

        return nil
    }

    /// Get a list of all windows currently shown, that are likely to be resizable by Loop.
    static func windowList() -> [Window] {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as NSArray? as? [[String: AnyObject]] else {
            return []
        }

        var windowList: [Window] = []
        for windowInfo in list {
            if let window = try? Window.fromWindowInfo(windowInfo) {
                windowList.append(window)
            }
        }

        return windowList
    }
}
