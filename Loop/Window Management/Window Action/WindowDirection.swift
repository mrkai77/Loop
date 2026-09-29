//
//  WindowDirection.swift
//  Loop
//
//  Created by Kai Azim on 2023-06-14.
//

import Defaults
import SwiftUI

/// Enum that stores all possible resizing options
enum WindowDirection: String, CaseIterable, Identifiable, Codable {
    var id: Self { self }

    /// "Empty" actions.
    /// `noAction` is explicitly chosen or user-bound.
    /// `noSelection` is the default state before any radial menu selection is made.
    case noAction = "NoAction", noSelection = "NoSelection"

    // General Actions
    case maximize = "Maximize", almostMaximize = "AlmostMaximize", fullscreen = "Fullscreen"
    case maximizeHeight = "MaximizeHeight", maximizeWidth = "MaximizeWidth", fillAvailableSpace = "FillAvailableSpace"
    case undo = "Undo", initialFrame = "InitialFrame", hide = "Hide", minimize = "Minimize", minimizeOthers = "MinimizeOthers"
    case macOSCenter = "MacOSCenter", center = "Center"

    // Halves
    case topHalf = "TopHalf", rightHalf = "RightHalf", bottomHalf = "BottomHalf", leftHalf = "LeftHalf"
    case horizontalCenterHalf = "HorizontalCenterHalf", verticalCenterHalf = "VerticalCenterHalf"

    // Quarters
    case topLeftQuarter = "TopLeftQuarter", topRightQuarter = "TopRightQuarter"
    case bottomRightQuarter = "BottomRightQuarter", bottomLeftQuarter = "BottomLeftQuarter"

    // Horizontal Thirds
    case rightThird = "RightThird", rightTwoThirds = "RightTwoThirds"
    case horizontalCenterThird = "HorizontalCenterThird"
    case leftThird = "LeftThird", leftTwoThirds = "LeftTwoThirds"

    // Horizontal Fourths
    case firstFourth = "FirstFourth", secondFourth = "SecondFourth", thirdFourth = "ThirdFourth", fourthFourth = "FourthFourth"
    case leftThreeFourths = "LeftThreeFourths", rightThreeFourths = "RightThreeFourths"

    // Vertical Thirds
    case topThird = "TopThird", topTwoThirds = "TopTwoThirds"
    case verticalCenterThird = "VerticalCenterThird"
    case bottomThird = "BottomThird", bottomTwoThirds = "BottomTwoThirds"

    /// Screen Switching
    case nextScreen = "NextScreen", previousScreen = "PreviousScreen", leftScreen = "LeftScreen", rightScreen = "RightScreen", topScreen = "TopScreen", bottomScreen = "BottomScreen"

    /// Space Switching (move the window to another Mission Control space).
    case nextSpace = "NextSpace", previousSpace = "PreviousSpace"
    case moveToSpace1 = "MoveToSpace1", moveToSpace2 = "MoveToSpace2", moveToSpace3 = "MoveToSpace3", moveToSpace4 = "MoveToSpace4"
    case moveToSpace5 = "MoveToSpace5", moveToSpace6 = "MoveToSpace6", moveToSpace7 = "MoveToSpace7", moveToSpace8 = "MoveToSpace8"
    case moveToSpace9 = "MoveToSpace9", moveToSpace10 = "MoveToSpace10", moveToSpace11 = "MoveToSpace11", moveToSpace12 = "MoveToSpace12"
    case moveToSpace13 = "MoveToSpace13", moveToSpace14 = "MoveToSpace14", moveToSpace15 = "MoveToSpace15", moveToSpace16 = "MoveToSpace16"

    // Size Adjustment
    case larger = "Larger", smaller = "Smaller"
    case scaleUp = "ScaleUp", scaleDown = "ScaleDown"

    /// Shrink
    case shrinkTop = "ShrinkTop", shrinkBottom = "ShrinkBottom", shrinkRight = "ShrinkRight", shrinkLeft = "ShrinkLeft", shrinkHorizontal = "ShrinkHorizontal", shrinkVertical = "ShrinkVertical"

    /// Grow
    case growTop = "GrowTop", growBottom = "GrowBottom", growRight = "GrowRight", growLeft = "GrowLeft", growHorizontal = "GrowHorizontal", growVertical = "GrowVertical"

    /// Move
    case moveUp = "MoveUp", moveDown = "MoveDown", moveRight = "MoveRight", moveLeft = "MoveLeft"

    /// Focus
    case focusUp = "FocusUp", focusDown = "FocusDown", focusRight = "FocusRight", focusLeft = "FocusLeft", focusNextInStack = "FocusNextInStack"

    // Stash
    case stash = "Stash"
    case unstash = "Unstash"

    /// Custom Actions
    case custom = "Custom", cycle = "Cycle"

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
