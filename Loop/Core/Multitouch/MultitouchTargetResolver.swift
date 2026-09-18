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

    func reset() {
        lastRepeatableWindow = nil
    }

    func activationContext(
        for gesture: GestureBinding,
        allowsRapidRepeat: Bool
    ) -> MultitouchGestureActivationContext {
        let cursorPosition = NSEvent.mouseLocation.flipY(screen: NSScreen.screens[0])
        let windowAtCursor = WindowUtility.windowAtPosition(cursorPosition)
        let startedInTitlebar = windowAtCursor.map {
            isInTitlebar(cursorPosition, of: $0)
        } ?? false

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

    func rememberRepeatableWindow(_ window: Window?, allowsRapidRepeat: Bool) {
        guard let window, allowsRapidRepeat else { return }
        lastRepeatableWindow = window
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
