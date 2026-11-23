//
//  ScreenUtility.swift
//  Loop
//
//  Created by Kai Azim on 2024-01-11.
//

import Defaults
import SwiftUI

enum ScreenUtility {
    private static var navigationUtility = DirectionalNavigationUtility<NSScreen>(
        minDirectionalSpan: .points(1),
        minStackedArea: .percentage(100), // Won't be used since screens cannot be stacked
        frameProvider: \.frame
    )

    /// Returns a screen containing a window, if found.
    /// - Parameter window: the window whose screen we want to find.
    /// - Returns: the screen containing the window.
    static func screenContaining(_ window: Window) -> NSScreen? {
        let screens = NSScreen.screens

        if screens.count == 1, let firstScreen = screens.first {
            return firstScreen
        }

        guard let currentScreen = findScreen(with: window, screens) else {
            return screens.first
        }

        return currentScreen
    }

    /// Finds a screen contianing a window, within an array of screens.
    /// - Parameters:
    ///   - window: the window whose screen we want to find.
    ///   - screens: an array of screens to search within
    /// - Returns: the screen containing the window.
    private static func findScreen(with window: Window, _ screens: [NSScreen]) -> NSScreen? {
        var result: NSScreen?

        let windowFrame = window.frame
        var largestRecordedArea: CGFloat = .zero

        for screen in screens {
            let screenFrame = screen.displayBounds

            if screenFrame.contains(windowFrame) {
                result = screen
                break
            }

            let intersectSize = screenFrame.intersection(windowFrame).size
            let intersectArea = intersectSize.area

            if intersectArea > largestRecordedArea {
                largestRecordedArea = intersectArea
                result = screen
            }
        }

        return result
    }

    // MARK: Next/Previous Screen

    /// Determines the next screen from a screen of reference.
    /// - Parameters:
    ///   - screen: the current screen
    ///   - canRestartCycle: whether this should continuously loop through all screens, rather than stopping at the end.
    /// - Returns: the next screen, or the first screen in the cycle if `canRestartCycle` is enabled. Otherwise, it will return `nil`.
    static func nextScreen(from screen: NSScreen, canRestartCycle: Bool = true) -> NSScreen? {
        let screens = getOrderedScreens()

        if let nextScreen = screens.next(from: screen) {
            return nextScreen
        }
        return canRestartCycle ? screens.first : nil
    }

    /// Determines the previous screen from a screen of reference.
    /// - Parameters:
    ///   - screen: the current screen
    ///   - canRestartCycle: whether this should continuously loop through all screens, rather than stopping at the end.
    /// - Returns: the previous screen, or the last screen in the cycle if `canRestartCycle` is enabled. Otherwise, it will return `nil`.
    static func previousScreen(from screen: NSScreen, canRestartCycle: Bool = true) -> NSScreen? {
        let screens = getOrderedScreens()

        if let previousScreen = screens.previous(from: screen) {
            return previousScreen
        }
        return canRestartCycle ? screens.last : nil
    }

    /// Sorts all NSScreens in an order such that the next/previous screen are in positional order.
    private static func getOrderedScreens() -> [NSScreen] {
        Defaults[.screenOrder].sorted(NSScreen.screens) { $0.frame }
    }

    /// The screen a screen switching direction moves to, or `nil` for other directions or when there isn't one
    static func targetScreen(for direction: WindowDirection, from screen: NSScreen) -> NSScreen? {
        switch direction {
        case .nextScreen:
            nextScreen(from: screen)
        case .previousScreen:
            previousScreen(from: screen)
        case .leftScreen:
            directionalScreen(from: screen, direction: .left)
        case .rightScreen:
            directionalScreen(from: screen, direction: .right)
        case .topScreen:
            directionalScreen(from: screen, direction: .top)
        case .bottomScreen:
            directionalScreen(from: screen, direction: .bottom)
        default:
            nil
        }
    }

    /// Screen switching actions start from the window's own screen, so where they go doesn't depend on the cursor.
    @MainActor
    static func screen(for action: WindowAction, window: Window?) -> NSScreen? {
        if action.direction.willChangeScreen, let window, let screen = ScreenUtility.screenContaining(window) {
            return screen
        }

        return Defaults[.useScreenWithCursor] ? NSScreen.screenWithMouse : NSScreen.main
    }

    /// What a screen switching action applies on the new screen: the window's last action, or its frame in proportion
    @MainActor
    static func actionAfterScreenSwitch(for window: Window, from currentScreen: NSScreen) async -> WindowAction {
        let screenSwitchingCustomActionName = "autogenerated_screen_switching_action"

        if let lastAction = await WindowRecords.shared.getCurrentAction(for: window),
           lastAction.getName() != screenSwitchingCustomActionName,
           !lastAction.forceProportionalFrameOnScreenChange {
            return lastAction
        }

        let currentFrame = window.frame

        // Measured on the screen the window is actually on. The screen Loop started from can be another one,
        // and measuring against it gives proportions outside the screen.
        let windowScreen = ScreenUtility.screenContaining(window) ?? currentScreen
        let adjustedBounds = PaddingConfiguration
            .getConfiguredPadding(for: windowScreen)
            .applyToBounds(windowScreen.cgSafeScreenFrame, screen: windowScreen)

        let proportionalSize = CGRect(
            x: (currentFrame.minX - adjustedBounds.minX) / adjustedBounds.width,
            y: (currentFrame.minY - adjustedBounds.minY) / adjustedBounds.height,
            width: currentFrame.width / adjustedBounds.width,
            height: currentFrame.height / adjustedBounds.height
        )

        return .init(
            .custom,
            name: screenSwitchingCustomActionName,
            unit: .percentage,
            width: proportionalSize.width * 100,
            height: proportionalSize.height * 100,
            xPoint: proportionalSize.minX * 100,
            yPoint: proportionalSize.minY * 100,
            positionMode: .coordinates,
            sizeMode: .custom
        )
    }

    // MARK: Directional Screens

    /// Finds a screen to a set edge from the screen of reference.
    /// - Parameters:
    ///   - currentScreen: the screen of reference, i.e. the current screen.
    ///   - direction: the direction of the screen we want to find.
    ///   - canRestartCycle: whether this should continuously loop through all screens, rather than returning `nil` at the end.
    /// - Returns: the screen at the respective edge, or the first screen in the row/column if `canRestartCycle` is enabled. Otherwise, it will return `nil`.
    static func directionalScreen(
        from currentScreen: NSScreen,
        direction: NavigationDirection,
        canWrap: Bool = true
    ) -> NSScreen? {
        let currentDisplayID = currentScreen.displayID
        let otherScreens = NSScreen.screens.filter { $0.displayID != currentDisplayID }

        return navigationUtility.directionalItem(
            from: currentScreen,
            others: otherScreens,
            direction: direction,
            canWrap: canWrap
        )
    }
}

private extension Array where Element: Hashable {
    func next(from item: Element) -> Element? {
        guard let index = firstIndex(of: item) else {
            return nil
        }

        if index + 1 < count {
            return self[index + 1]
        }

        return nil
    }

    func previous(from item: Element) -> Element? {
        guard let index = firstIndex(of: item) else {
            return nil
        }

        if index - 1 >= 0 {
            return self[index - 1]
        }

        return nil
    }
}
