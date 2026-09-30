//
//  MultitouchTargetResolver.swift
//  Loop
//
//  Created by Kai Azim on 2026-07-06.
//

import Defaults
import Scribe
import SwiftUI

struct MultitouchGestureActivationContext {
    let targetWindow: Window?
    let startedInTitlebar: Bool

    func allows(_ gesture: GestureBinding) -> Bool {
        gesture.effectiveActivationZone == .anywhere || startedInTitlebar
    }
}

@Loggable
@MainActor
final class MultitouchTargetResolver {
    /// Window most recently targeted by a repeatable gesture.
    /// Lets shrinking/growing continue after the cursor falls off the resized frame.
    private var lastRepeatableWindow: Window?
    /// Resolved once per touch and shared by every gesture in it, so they all agree on the window
    private var touchTarget: TouchTarget?

    private struct TouchTarget {
        let touchID: Int
        /// The window under the cursor, or the focused window without "Resize window under cursor"
        let window: Window?
        let startedInTitlebar: Bool
    }

    func reset() {
        lastRepeatableWindow = nil
        touchTarget = nil
    }

    func activationContext(
        for gesture: GestureBinding,
        touchID: Int,
        allowsRapidRepeat: Bool
    ) -> MultitouchGestureActivationContext {
        let target = touchTarget(touchID: touchID)

        let targetWindow: Window? = switch gesture.effectiveActivationZone {
        case .titlebar:
            target.startedInTitlebar ? target.window : nil
        case .anywhere:
            target.window ?? fallbackWindow(allowsRapidRepeat: allowsRapidRepeat)
        }

        return MultitouchGestureActivationContext(
            targetWindow: targetWindow,
            startedInTitlebar: target.startedInTitlebar
        )
    }

    func isCursorInTitlebar(touchID: Int) -> Bool {
        touchTarget(touchID: touchID).startedInTitlebar
    }

    func rememberRepeatableWindow(_ window: Window?, allowsRapidRepeat: Bool) {
        guard let window, allowsRapidRepeat else { return }
        lastRepeatableWindow = window
    }

    /// Used when there's no window under the cursor, matching the rest of Loop's fallback to the focused window
    private func fallbackWindow(allowsRapidRepeat: Bool) -> Window? {
        if allowsRapidRepeat, let lastRepeatableWindow {
            return lastRepeatableWindow
        }
        return try? WindowUtility.frontmostWindow()
    }

    private func touchTarget(touchID: Int) -> TouchTarget {
        if let touchTarget, touchTarget.touchID == touchID {
            return touchTarget
        }

        let cursorPosition = NSEvent.mouseLocation.flipY(screen: NSScreen.screens[0])

        let window: Window?
        let startedInTitlebar: Bool
        if Defaults[.resizeWindowUnderCursor] {
            window = WindowUtility.windowAtPosition(cursorPosition)
            startedInTitlebar = window.map { isInTitlebar(cursorPosition, of: $0) } ?? false
        } else {
            window = try? WindowUtility.frontmostWindow()
            // Only counts where the focused window is the topmost window under the cursor
            startedInTitlebar = window.map {
                SkyLightToolBelt.windowIDAtPosition(cursorPosition) == $0.cgWindowID
                    && isInTitlebar(cursorPosition, of: $0)
            } ?? false
        }

        let target = TouchTarget(touchID: touchID, window: window, startedInTitlebar: startedInTitlebar)
        touchTarget = target
        return target
    }

    private func isInTitlebar(_ cursorPosition: CGPoint, of window: Window) -> Bool {
        let minimumTitlebarHeight = Defaults[.gestureTitlebarHeight]
        let titlebarHeight: CGFloat = if #available(macOS 26, *) {
            if #unavailable(macOS 27),
               let cornerRadius = SkyLightToolBelt.getCornerRadii(windowID: window.cgWindowID)?.topLeading {
                max(2 * cornerRadius, minimumTitlebarHeight)
            } else {
                minimumTitlebarHeight
            }
        } else {
            minimumTitlebarHeight
        }

        let titlebarMinY = window.frame.minY
        let titlebarMaxY = window.frame.minY + titlebarHeight
        return cursorPosition.y >= titlebarMinY && cursorPosition.y <= titlebarMaxY
    }
}
