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
    private var touchTarget: (touchID: Int, window: Window?, isInTitlebar: Bool)?

    func reset() {
        lastRepeatableWindow = nil
        touchTarget = nil
    }

    func activationContext(
        for gesture: GestureBinding,
        touchID: Int,
        allowsRapidRepeat: Bool
    ) -> MultitouchGestureActivationContext {
        let (windowAtCursor, startedInTitlebar) = windowUnderCursor(touchID: touchID)

        let targetWindow: Window? = if let windowAtCursor {
            windowAtCursor
        } else if allowsRapidRepeat, gesture.effectiveActivationZone == .anywhere {
            lastRepeatableWindow
        } else {
            nil
        }

        return MultitouchGestureActivationContext(
            targetWindow: targetWindow,
            startedInTitlebar: startedInTitlebar
        )
    }

    func isCursorInTitlebar(touchID: Int) -> Bool {
        windowUnderCursor(touchID: touchID).isInTitlebar
    }

    func rememberRepeatableWindow(_ window: Window?, allowsRapidRepeat: Bool) {
        guard let window, allowsRapidRepeat else { return }
        lastRepeatableWindow = window
    }

    private func windowUnderCursor(touchID: Int) -> (window: Window?, isInTitlebar: Bool) {
        if let touchTarget, touchTarget.touchID == touchID {
            return (touchTarget.window, touchTarget.isInTitlebar)
        }

        let cursorPosition = NSEvent.mouseLocation.flipY(screen: NSScreen.screens[0])
        let window = WindowUtility.windowAtPosition(cursorPosition)
        let isInTitlebar = window.map { isInTitlebar(cursorPosition, of: $0) } ?? false
        touchTarget = (touchID, window, isInTitlebar)
        return (window, isInTitlebar)
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
