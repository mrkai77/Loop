//
//  WindowDirection.swift
//  Loop
//
//  Created by Kai Azim on 2023-06-14.
//

import SwiftUI
import Tome

/// Enum that stores all possible resizing options
enum WindowDirection: String, CaseIterable, Identifiable, Codable, Tome.Serializable {
    var id: Self { self }

    /// "Empty" actions.
    /// `noAction` is explicitly chosen or user-bound.
    /// `noSelection` is the default state before any radial menu selection is made.
    case noAction = "none"
    case noSelection = "no-selection"

    // General Actions
    case maximize
    case almostMaximize = "almost-maximize"
    case fullscreen
    case maximizeHeight = "maximize-height"
    case maximizeWidth = "maximize-width"
    case fillAvailableSpace = "fill-available-space"
    case undo
    case initialFrame = "initial-frame"
    case hide
    case minimize
    case minimizeOthers = "minimize-others"
    case macOSCenter = "macos-center"
    case center

    // Halves
    case topHalf = "top-half"
    case rightHalf = "right-half"
    case bottomHalf = "bottom-half"
    case leftHalf = "left-half"
    case horizontalCenterHalf = "horizontal-center-half"
    case verticalCenterHalf = "vertical-center-half"

    // Quarters
    case topLeftQuarter = "top-left-quarter"
    case topRightQuarter = "top-right-quarter"
    case bottomRightQuarter = "bottom-right-quarter"
    case bottomLeftQuarter = "bottom-left-quarter"

    // Horizontal Thirds
    case rightThird = "right-third"
    case rightTwoThirds = "right-two-thirds"
    case horizontalCenterThird = "horizontal-center-third"
    case leftThird = "left-third"
    case leftTwoThirds = "left-two-thirds"

    // Horizontal Fourths
    case firstFourth = "first-fourth"
    case secondFourth = "second-fourth"
    case thirdFourth = "third-fourth"
    case fourthFourth = "fourth-fourth"
    case leftThreeFourths = "left-three-fourths"
    case rightThreeFourths = "right-three-fourths"

    // Vertical Thirds
    case topThird = "top-third"
    case topTwoThirds = "top-two-thirds"
    case verticalCenterThird = "vertical-center-third"
    case bottomThird = "bottom-third"
    case bottomTwoThirds = "bottom-two-thirds"

    /// Screen Switching
    case nextScreen = "next-screen"
    case previousScreen = "previous-screen"
    case leftScreen = "left-screen"
    case rightScreen = "right-screen"
    case topScreen = "top-screen"
    case bottomScreen = "bottom-screen"

    /// Space Switching (move the window to another Mission Control space).
    case nextSpace = "next-space"
    case previousSpace = "previous-space"
    case moveToSpace1 = "move-to-space-1"
    case moveToSpace2 = "move-to-space-2"
    case moveToSpace3 = "move-to-space-3"
    case moveToSpace4 = "move-to-space-4"
    case moveToSpace5 = "move-to-space-5"
    case moveToSpace6 = "move-to-space-6"
    case moveToSpace7 = "move-to-space-7"
    case moveToSpace8 = "move-to-space-8"
    case moveToSpace9 = "move-to-space-9"
    case moveToSpace10 = "move-to-space-10"
    case moveToSpace11 = "move-to-space-11"
    case moveToSpace12 = "move-to-space-12"
    case moveToSpace13 = "move-to-space-13"
    case moveToSpace14 = "move-to-space-14"
    case moveToSpace15 = "move-to-space-15"
    case moveToSpace16 = "move-to-space-16"

    // Size Adjustment
    case larger
    case smaller
    case scaleUp = "scale-up"
    case scaleDown = "scale-down"

    /// Shrink
    case shrinkTop = "shrink-top"
    case shrinkBottom = "shrink-bottom"
    case shrinkRight = "shrink-right"
    case shrinkLeft = "shrink-left"
    case shrinkHorizontal = "shrink-horizontal"
    case shrinkVertical = "shrink-vertical"

    /// Grow
    case growTop = "grow-top"
    case growBottom = "grow-bottom"
    case growRight = "grow-right"
    case growLeft = "grow-left"
    case growHorizontal = "grow-horizontal"
    case growVertical = "grow-vertical"

    /// Move
    case moveUp = "move-up"
    case moveDown = "move-down"
    case moveRight = "move-right"
    case moveLeft = "move-left"

    /// Focus
    case focusUp = "focus-up"
    case focusDown = "focus-down"
    case focusRight = "focus-right"
    case focusLeft = "focus-left"
    case focusNextInStack = "focus-next-in-stack"

    // Stash
    case stash
    case unstash

    /// Custom Actions
    case custom
    case cycle

    // These are used in the menubar resize submenu & keybind configuration
    static var general: [WindowDirection] { [.fullscreen, .maximize, .almostMaximize, .maximizeHeight, .maximizeWidth, .fillAvailableSpace, .center, .macOSCenter, .minimize, .minimizeOthers, .hide] }
    static var halves: [WindowDirection] { [.topHalf, .verticalCenterHalf, .bottomHalf, .leftHalf, .horizontalCenterHalf, .rightHalf] }
    static var quarters: [WindowDirection] { [.topLeftQuarter, .topRightQuarter, .bottomLeftQuarter, .bottomRightQuarter] }
    static var horizontalThirds: [WindowDirection] { [.rightThird, .rightTwoThirds, .horizontalCenterThird, .leftTwoThirds, .leftThird] }
    static var verticalThirds: [WindowDirection] { [.topThird, .topTwoThirds, .verticalCenterThird, .bottomTwoThirds, .bottomThird] }
    static var horizontalFourths: [WindowDirection] { [.firstFourth, .secondFourth, .thirdFourth, .fourthFourth, .leftThreeFourths, .rightThreeFourths] }
    static var screenSwitching: [WindowDirection] { [.nextScreen, .previousScreen, .leftScreen, .rightScreen, .topScreen, .bottomScreen] }
    static var spaceSwitching: [WindowDirection] {
        [
            .nextSpace, .previousSpace,
            .moveToSpace1, .moveToSpace2, .moveToSpace3, .moveToSpace4,
            .moveToSpace5, .moveToSpace6, .moveToSpace7, .moveToSpace8,
            .moveToSpace9, .moveToSpace10, .moveToSpace11, .moveToSpace12,
            .moveToSpace13, .moveToSpace14, .moveToSpace15, .moveToSpace16
        ]
    }

    static var relativeSpaceSwitching: [WindowDirection] { [.nextSpace, .previousSpace] }
    static var numberedSpaceSwitching: [WindowDirection] { Array(spaceSwitching.dropFirst(relativeSpaceSwitching.count)) }

    static var sizeAdjustment: [WindowDirection] { [.larger, .smaller, .scaleUp, .scaleDown] }
    static var shrink: [WindowDirection] { [.shrinkTop, .shrinkBottom, .shrinkRight, .shrinkLeft, .shrinkHorizontal, .shrinkVertical] }
    static var grow: [WindowDirection] { [.growTop, .growBottom, .growRight, .growLeft, .growHorizontal, .growVertical] }
    static var move: [WindowDirection] { [.moveUp, .moveDown, .moveRight, .moveLeft] }
    static var focus: [WindowDirection] { [.focusUp, .focusDown, .focusRight, .focusLeft, .focusNextInStack] }
    static var more: [WindowDirection] { [.initialFrame, .undo, .custom, .cycle] }

    // Computed properties for checking conditions
    var isNoOp: Bool { [.noSelection, .noAction].contains(self) }
    var willChangeScreen: Bool { WindowDirection.screenSwitching.contains(self) }
    var willChangeSpace: Bool { WindowDirection.spaceSwitching.contains(self) }
    var willAdjustSize: Bool { WindowDirection.sizeAdjustment.contains(self) }
    var willShrink: Bool { WindowDirection.shrink.contains(self) }
    var willGrow: Bool { WindowDirection.grow.contains(self) }
    var willMove: Bool { WindowDirection.move.contains(self) }
    var willFocusWindow: Bool { WindowDirection.focus.contains(self) }
    var willCenter: Bool { [.center, .macOSCenter, .verticalCenterHalf, .horizontalCenterHalf].contains(self) }
    var isCustomizable: Bool { [.custom, .stash].contains(self) }

    /// The action that undoes a step of this one, such as smaller for larger
    /// Imagine this as "cycling backwards but for non-cycle actions" :)
    var opposite: WindowDirection? {
        switch self {
        case .larger: .smaller
        case .smaller: .larger
        case .scaleUp: .scaleDown
        case .scaleDown: .scaleUp
        case .shrinkTop: .growTop
        case .shrinkBottom: .growBottom
        case .shrinkRight: .growRight
        case .shrinkLeft: .growLeft
        case .shrinkHorizontal: .growHorizontal
        case .shrinkVertical: .growVertical
        case .growTop: .shrinkTop
        case .growBottom: .shrinkBottom
        case .growRight: .shrinkRight
        case .growLeft: .shrinkLeft
        case .growHorizontal: .shrinkHorizontal
        case .growVertical: .shrinkVertical
        case .moveUp: .moveDown
        case .moveDown: .moveUp
        case .moveRight: .moveLeft
        case .moveLeft: .moveRight
        case .focusUp: .focusDown
        case .focusDown: .focusUp
        case .focusRight: .focusLeft
        case .focusLeft: .focusRight
        default: nil
        }
    }

    /// Whether this direction resolves to a concrete target frame. False for no-op,
    /// minimize/hide/minimizeOthers, cycle, and focus/space/screen-switching actions —
    /// none of which produce a frame. Shared by `WindowFrameResolver.getFrame` and
    /// `ResizeContext.recomputeTargetFrame` so the two "no-frame" lists can't drift apart.
    var hasTargetFrame: Bool {
        let noFrameActions: [WindowDirection] = [.noAction, .noSelection, .cycle, .minimize, .minimizeOthers, .hide]
        return !(noFrameActions.contains(self) || willFocusWindow || willChangeSpace || willChangeScreen)
    }

    var hasRadialMenuAngle: Bool {
        let noAngleActions: [WindowDirection] = [.noAction, .noSelection, .minimize, .minimizeOthers, .hide, .initialFrame, .undo, .cycle]
        return !(noAngleActions.contains(self) || shouldFillRadialMenu || willChangeScreen || willChangeSpace || willAdjustSize || willShrink || willGrow || willMove || willFocusWindow)
    }

    var shouldFillRadialMenu: Bool {
        [.fullscreen, .maximize, .almostMaximize, .maximizeHeight, .maximizeWidth, .fillAvailableSpace].contains(self) || willCenter
    }

    var frameMultiplyValues: CGRect? {
        switch self {
        case .maximize: .init(x: 0, y: 0, width: 1.0, height: 1.0)
        case .almostMaximize: .init(x: 0.5 / 10.0, y: 0.5 / 10.0, width: 9.0 / 10.0, height: 9.0 / 10.0)
        case .fullscreen: .init(x: 0, y: 0, width: 1.0, height: 1.0)
        // Halves
        case .topHalf: .init(x: 0, y: 0, width: 1.0, height: 1.0 / 2.0)
        case .rightHalf: .init(x: 1.0 / 2.0, y: 0, width: 1.0 / 2.0, height: 1.0)
        case .bottomHalf: .init(x: 0, y: 1.0 / 2.0, width: 1.0, height: 1.0 / 2.0)
        case .leftHalf: .init(x: 0, y: 0, width: 1.0 / 2.0, height: 1.0)
        case .horizontalCenterHalf: .init(x: 1.0 / 4.0, y: 0, width: 1.0 / 2.0, height: 1.0)
        case .verticalCenterHalf: .init(x: 0, y: 1.0 / 4.0, width: 1.0, height: 1.0 / 2.0)
        // Quarters
        case .topLeftQuarter: .init(x: 0, y: 0, width: 1.0 / 2.0, height: 1.0 / 2.0)
        case .topRightQuarter: .init(x: 1.0 / 2.0, y: 0, width: 1.0 / 2.0, height: 1.0 / 2.0)
        case .bottomRightQuarter: .init(x: 1.0 / 2.0, y: 1.0 / 2.0, width: 1.0 / 2.0, height: 1.0 / 2.0)
        case .bottomLeftQuarter: .init(x: 0, y: 1.0 / 2.0, width: 1.0 / 2.0, height: 1.0 / 2.0)
        // Thirds (Horizontal)
        case .rightThird: .init(x: 2.0 / 3.0, y: 0, width: 1.0 / 3.0, height: 1.0)
        case .rightTwoThirds: .init(x: 1.0 / 3.0, y: 0, width: 2.0 / 3.0, height: 1.0)
        case .horizontalCenterThird: .init(x: 1.0 / 3.0, y: 0, width: 1.0 / 3.0, height: 1.0)
        case .leftThird: .init(x: 0, y: 0, width: 1.0 / 3.0, height: 1.0)
        case .leftTwoThirds: .init(x: 0, y: 0, width: 2.0 / 3.0, height: 1.0)
        // Thirds (Vertical)
        case .topThird: .init(x: 0, y: 0, width: 1.0, height: 1.0 / 3.0)
        case .topTwoThirds: .init(x: 0, y: 0, width: 1.0, height: 2.0 / 3.0)
        case .verticalCenterThird: .init(x: 0, y: 1.0 / 3.0, width: 1.0, height: 1.0 / 3.0)
        case .bottomThird: .init(x: 0, y: 2.0 / 3.0, width: 1.0, height: 1.0 / 3.0)
        case .bottomTwoThirds: .init(x: 0, y: 1.0 / 3.0, width: 1.0, height: 2.0 / 3.0)
        // Fourths (Horizontal)
        case .firstFourth: .init(x: 0, y: 0, width: 1.0 / 4.0, height: 1.0)
        case .secondFourth: .init(x: 1.0 / 4.0, y: 0, width: 1.0 / 4.0, height: 1.0)
        case .thirdFourth: .init(x: 2.0 / 4.0, y: 0, width: 1.0 / 4.0, height: 1.0)
        case .fourthFourth: .init(x: 3.0 / 4.0, y: 0, width: 1.0 / 4.0, height: 1.0)
        case .leftThreeFourths: .init(x: 0, y: 0, width: 3.0 / 4.0, height: 1.0)
        case .rightThreeFourths: .init(x: 1.0 / 4.0, y: 0, width: 3.0 / 4.0, height: 1.0)
        default: nil
        }
    }

    var focusDirection: NavigationDirection? {
        switch self {
        case .focusLeft: .left
        case .focusRight: .right
        case .focusUp: .top
        case .focusDown: .bottom
        default: nil
        }
    }

    /// If this direction targets a Mission Control space, returns the resolved destination.
    var spaceDestination: WindowActionEngine.SpaceDestination? {
        switch self {
        case .nextSpace: .nextSpace
        case .previousSpace: .previousSpace
        case .moveToSpace1: .desktop(1)
        case .moveToSpace2: .desktop(2)
        case .moveToSpace3: .desktop(3)
        case .moveToSpace4: .desktop(4)
        case .moveToSpace5: .desktop(5)
        case .moveToSpace6: .desktop(6)
        case .moveToSpace7: .desktop(7)
        case .moveToSpace8: .desktop(8)
        case .moveToSpace9: .desktop(9)
        case .moveToSpace10: .desktop(10)
        case .moveToSpace11: .desktop(11)
        case .moveToSpace12: .desktop(12)
        case .moveToSpace13: .desktop(13)
        case .moveToSpace14: .desktop(14)
        case .moveToSpace15: .desktop(15)
        case .moveToSpace16: .desktop(16)
        default: nil
        }
    }
}

extension WindowDirection: CustomDebugStringConvertible {
    var debugDescription: String {
        rawValue
    }
}
