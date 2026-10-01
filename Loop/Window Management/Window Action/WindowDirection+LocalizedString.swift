//
//  WindowDirection+LocalizedString.swift
//  Loop
//
//  Created by phlpsong on 2024/3/31.
//

import Luminare
import SwiftUI

extension WindowDirection {
    var infoText: LocalizedStringKey? {
        switch self {
        case .macOSCenter: "\(name) places windows slightly above center,\nwhich many people find more comfortable."
        case .stash: "Each \(name) action tracks one window. To stash\nmore windows, add more \(name) actions."
        default: nil
        }
    }

    var name: String {
        switch self {
        case .noAction, .noSelection:
            String(localized: "No Action", comment: "Window action: no selection")
        case .maximize:
            String(localized: "Maximize", comment: "Window action")
        case .almostMaximize:
            String(localized: "Almost Maximize", comment: "Window action")
        case .maximizeHeight:
            String(localized: "Maximize Height", comment: "Window action")
        case .maximizeWidth:
            String(localized: "Maximize Width", comment: "Window action")
        case .fillAvailableSpace:
            String(localized: "Fill Available Space", comment: "Window action")
        case .fullscreen:
            String(localized: "Full Screen", comment: "Window action")
        case .undo:
            String(localized: "Undo", comment: "Window action")
        case .initialFrame:
            String(localized: "Initial Frame", comment: "Window action")
        case .hide:
            String(localized: "Hide", comment: "Window action")
        case .minimize:
            String(localized: "Minimize", comment: "Window action")
        case .minimizeOthers:
            String(localized: "Minimize Others", comment: "Window action")
        case .macOSCenter:
            String(localized: "macOS Center", comment: "Window action")
        case .center:
            String(localized: "Center", comment: "Window action")
        case .topHalf:
            String(localized: "Top Half", comment: "Window action")
        case .rightHalf:
            String(localized: "Right Half", comment: "Window action")
        case .bottomHalf:
            String(localized: "Bottom Half", comment: "Window action")
        case .leftHalf:
            String(localized: "Left Half", comment: "Window action")
        case .horizontalCenterHalf:
            String(localized: "Horizontal Center Half", comment: "Window action")
        case .verticalCenterHalf:
            String(localized: "Vertical Center Half", comment: "Window action")
        case .topLeftQuarter:
            String(localized: "Top Left Quarter", comment: "Window action")
        case .topRightQuarter:
            String(localized: "Top Right Quarter", comment: "Window action")
        case .bottomRightQuarter:
            String(localized: "Bottom Right Quarter", comment: "Window action")
        case .bottomLeftQuarter:
            String(localized: "Bottom Left Quarter", comment: "Window action")
        case .rightThird:
            String(localized: "Right Third", comment: "Window action")
        case .rightTwoThirds:
            String(localized: "Right Two Thirds", comment: "Window action")
        case .horizontalCenterThird:
            String(localized: "Horizontal Center Third", comment: "Window action")
        case .leftThird:
            String(localized: "Left Third", comment: "Window action")
        case .leftTwoThirds:
            String(localized: "Left Two Thirds", comment: "Window action")
        case .topThird:
            String(localized: "Top Third", comment: "Window action")
        case .topTwoThirds:
            String(localized: "Top Two Thirds", comment: "Window action")
        case .verticalCenterThird:
            String(localized: "Vertical Center Third", comment: "Window action")
        case .bottomThird:
            String(localized: "Bottom Third", comment: "Window action")
        case .bottomTwoThirds:
            String(localized: "Bottom Two Thirds", comment: "Window action")
        case .firstFourth:
            String(localized: "First Fourth", comment: "Window action")
        case .secondFourth:
            String(localized: "Second Fourth", comment: "Window action")
        case .thirdFourth:
            String(localized: "Third Fourth", comment: "Window action")
        case .fourthFourth:
            String(localized: "Fourth Fourth", comment: "Window action")
        case .leftThreeFourths:
            String(localized: "Left Three Fourths", comment: "Window action")
        case .rightThreeFourths:
            String(localized: "Right Three Fourths", comment: "Window action")
        case .nextScreen:
            String(localized: "Next Screen", comment: "Window action")
        case .previousScreen:
            String(localized: "Previous Screen", comment: "Window action")
        case .leftScreen:
            String(localized: "Left Screen", comment: "Window action")
        case .rightScreen:
            String(localized: "Right Screen", comment: "Window action")
        case .topScreen:
            String(localized: "Top Screen", comment: "Window action")
        case .bottomScreen:
            String(localized: "Bottom Screen", comment: "Window action")
        case .nextSpace:
            String(localized: "Move to Next Space", comment: "Window action")
        case .previousSpace:
            String(localized: "Move to Previous Space", comment: "Window action")
        case .moveToSpace1, .moveToSpace2, .moveToSpace3, .moveToSpace4,
             .moveToSpace5, .moveToSpace6, .moveToSpace7, .moveToSpace8,
             .moveToSpace9, .moveToSpace10, .moveToSpace11, .moveToSpace12,
             .moveToSpace13, .moveToSpace14, .moveToSpace15, .moveToSpace16:
            moveToDesktopName
        case .larger:
            String(localized: "Larger", comment: "Window action")
        case .smaller:
            String(localized: "Smaller", comment: "Window action")
        case .scaleUp:
            String(localized: "Larger (Proportional)", comment: "Window action")
        case .scaleDown:
            String(localized: "Smaller (Proportional)", comment: "Window action")
        case .shrinkTop:
            String(localized: "Shrink Top", comment: "Window action")
        case .shrinkBottom:
            String(localized: "Shrink Bottom", comment: "Window action")
        case .shrinkRight:
            String(localized: "Shrink Right", comment: "Window action")
        case .shrinkLeft:
            String(localized: "Shrink Left", comment: "Window action")
        case .shrinkHorizontal:
            String(localized: "Shrink Horizontally", comment: "Window action")
        case .shrinkVertical:
            String(localized: "Shrink Vertically", comment: "Window action")
        case .growTop:
            String(localized: "Grow Top", comment: "Window action")
        case .growBottom:
            String(localized: "Grow Bottom", comment: "Window action")
        case .growRight:
            String(localized: "Grow Right", comment: "Window action")
        case .growLeft:
            String(localized: "Grow Left", comment: "Window action")
        case .growHorizontal:
            String(localized: "Grow Horizontally", comment: "Window action")
        case .growVertical:
            String(localized: "Grow Vertically", comment: "Window action")
        case .moveUp:
            String(localized: "Move Up", comment: "Window action")
        case .moveDown:
            String(localized: "Move Down", comment: "Window action")
        case .moveRight:
            String(localized: "Move Right", comment: "Window action")
        case .moveLeft:
            String(localized: "Move Left", comment: "Window action")
        case .focusUp:
            String(localized: "Focus Up", comment: "Window action")
        case .focusDown:
            String(localized: "Focus Down", comment: "Window action")
        case .focusRight:
            String(localized: "Focus Right", comment: "Window action")
        case .focusLeft:
            String(localized: "Focus Left", comment: "Window action")
        case .focusNextInStack:
            String(localized: "Focus Next in Stack", comment: "Window action")
        case .stash:
            String(localized: "Stash", comment: "Window action")
        case .unstash:
            String(localized: "Unstash", comment: "Window action")
        case .custom:
            String(localized: "Custom", comment: "Window action")
        case .cycle:
            String(localized: "Cycle", comment: "Window action")
        }
    }

    private var moveToDesktopName: String {
        let desktopNumber = Int(spaceDestination?.desktopNumber ?? 0)
        return String(
            localized: "Move to Desktop \(desktopNumber)",
            comment: "Window action; moves the current window to the Mission Control desktop identified by the number."
        )
    }
}
