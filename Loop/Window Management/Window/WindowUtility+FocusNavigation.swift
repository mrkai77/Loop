//
//  WindowUtility+FocusNavigation.swift
//  Loop
//
//  Created by cipher-shad0w on 2025-10-30.
//

import AppKit
import Scribe
import SwiftUI

extension WindowUtility {
    private static var navigationUtility = DirectionalNavigationUtility<Window>(
        minDirectionalSpan: .percentage(10),
        minStackedArea: .percentage(50),
        frameProvider: \.frame
    )

    /// Finds the next window to focus in the specified direction.
    /// - Parameters:
    ///   - currentWindow: The currently focused window to navigate from, or nil to navigate from screen center
    ///   - edge: The direction to search for the next window (leading, trailing, top, bottom)
    /// - Returns: The next window in the specified direction, or `nil` if no suitable window is found
    static func directionalWindow(
        from currentWindow: Window?,
        direction: NavigationDirection
    ) -> Window? {
        let allWindows = windowList()

        let availableWindows = allWindows
            .filter { window in
                !window.minimized &&
                    !window.isWindowHidden &&
                    !window.isAppExcluded
            }

        guard !availableWindows.isEmpty else {
            log.info("No windows available to focus")
            return nil
        }

        if let currentWindow {
            // Filter out the current window and get only visible, non-minimized, non-excluded windows
            let otherWindows = availableWindows
                .filter { $0.cgWindowID != currentWindow.cgWindowID }

            guard !otherWindows.isEmpty else {
                log.info("No other windows available to focus")
                return nil
            }

            // Use the generic directional navigation from DirectionalNavigationUtility
            if let nextWindow = navigationUtility.directionalItem(
                from: currentWindow,
                others: otherWindows,
                direction: direction,
                canWrap: true
            ) {
                log.info("Found window to focus in direction \(direction): \(nextWindow)")
                return nextWindow
            } else {
                log.info("No window found in direction \(direction)")
                return nil
            }
        } else {
            guard let screen = NSScreen.screenWithMouse ?? NSScreen.main else {
                log.error("Could not determine active screen")
                return nil
            }

            let screenCenter = screen.cgSafeScreenFrame.center
            log.info("Navigating from screen center: \(screenCenter.debugDescription)")

            // Find the closest window in the specified direction from screen center
            let nextWindow = availableWindows
                .filter { isInDirection($0.frame, from: screenCenter, direction: direction) }
                .min { screenCenter.distance(to: $0.frame.center) < screenCenter.distance(to: $1.frame.center) }

            if let nextWindow {
                log.info("Found window to focus in direction \(direction): \(nextWindow)")
            } else {
                log.info("No window found in direction \(direction) from screen center")
            }

            return nextWindow
        }
    }

    /// Finds the next window to focus in a stack cycle.
    /// - Parameters:
    ///   - currentWindow: The currently focused window to cycle from
    /// - Returns: The next window in the stack cycle, or `nil` if no suitable window is found
    static func nextStackedWindow(
        from currentWindow: Window?
    ) -> Window? {
        let allWindows = windowList()

        let availableWindows = allWindows
            .filter { window in
                !window.minimized &&
                    !window.isWindowHidden &&
                    !window.isAppExcluded
            }

        guard !availableWindows.isEmpty else {
            log.info("No windows available to focus")
            return nil
        }

        guard let currentWindow else {
            // If no current window, return the last available window
            let targetWindow = availableWindows.last
            if let targetWindow {
                log.info("No current window, selecting last window: \(targetWindow)")
            }
            return targetWindow
        }

        // Filter out the current window
        let otherWindows = availableWindows
            .filter { $0.cgWindowID != currentWindow.cgWindowID }

        guard !otherWindows.isEmpty else {
            log.info("No other windows available to focus in stack")
            return nil
        }

        // Use the generic stack cycling from DirectionalNavigationUtility
        if let nextWindow = navigationUtility.cycleInStack(
            from: currentWindow,
            others: otherWindows
        ) {
            log.info("Found window to focus in stack: \(nextWindow)")
            return nextWindow
        } else {
            log.info("No window found in stack")
            return nil
        }
    }

    /// Determines if a window frame is in the specified direction from a given point.
    /// - Parameters:
    ///   - frame: The window frame to check
    ///   - point: The reference point (screen center)
    ///   - direction: The direction to check
    /// - Returns: `true` if the window is in the specified direction
    private static func isInDirection(
        _ frame: CGRect,
        from point: CGPoint,
        direction: NavigationDirection
    ) -> Bool {
        let windowCenter = frame.center

        switch direction {
        case .left:
            return windowCenter.x < point.x
        case .right:
            return windowCenter.x > point.x
        case .top:
            return windowCenter.y > point.y
        case .bottom:
            return windowCenter.y < point.y
        }
    }
}
