//
//  NSScreen+Extensions.swift
//  Loop
//
//  Created by Kai Azim on 2023-06-14.
//

import SwiftUI
import Tome

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return deviceDescription[key] as? CGDirectDisplayID
    }

    var displayMode: CGDisplayMode? {
        guard
            let id = displayID,
            let displayMode = CGDisplayCopyDisplayMode(id)
        else {
            return nil
        }

        return displayMode
    }

    static var screenWithMouse: NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        let screens = NSScreen.screens

        // Ask SkyLight first so we match WindowServer's tie-breaking at display boundaries.
        if let primary = screens.first,
           let displayID = SkyLightToolBelt.bestManagedDisplayID(forCGPoint: mouseLocation.flipY(screen: primary)),
           let match = screens.first(where: { $0.displayID == displayID }) {
            return match
        }

        // CGRect.contains uses half-open intervals [minX, maxX) × [minY, maxY),
        // excluding points on the maxX/maxY edges. So we cannot use frame.contains(_:)
        return screens.first {
            mouseLocation.x >= $0.frame.minX &&
                mouseLocation.x <= $0.frame.maxX &&
                mouseLocation.y >= $0.frame.minY &&
                mouseLocation.y <= $0.frame.maxY
        }
    }

    var cgSafeScreenFrame: CGRect {
        let cgbounds = displayBounds
        let visibleFrame = safeScreenFrame.flipY(screen: NSScreen.screens[0])

        // By setting safeScreenFrame to visibleFrame, we won't need to adjust its size.
        var safeScreenFrame = visibleFrame

        // By using visibleFrame, coordinates of multiple displays won't
        // work correctly, so we instead use screenFrame's origin.
        safeScreenFrame.origin = cgbounds.origin

        safeScreenFrame.origin.y += menubarHeight
        safeScreenFrame.origin.x -= cgbounds.minX - visibleFrame.minX

        return safeScreenFrame
    }

    var safeScreenFrame: NSRect {
        var frame = visibleFrame

        if Tome.respectStageManager,
           SystemWindowManager.StageManager.enabled,
           SystemWindowManager.StageManager.shown {
            if SystemWindowManager.StageManager.position == .leading {
                frame.origin.x += Tome.stageStripSize
            }

            frame.size.width -= Tome.stageStripSize
        }

        return frame
    }

    var displayBounds: CGRect {
        guard let displayID else {
            NSLog("Error: Failed to get NSScreen.displayID in NSScreen.displayBounds")
            return frame.flipY(screen: self)
        }

        return CGDisplayBounds(displayID)
    }

    var menubarHeight: CGFloat {
        frame.maxY - visibleFrame.maxY
    }

    func isSameScreen(_ other: NSScreen) -> Bool {
        displayID == other.displayID
    }

    // MARK: - Calculate physical screen size

    /// Returns diagonal size in inches
    var diagonalSize: CGFloat {
        let unitsPerInch = unitsPerInch
        let screenSizeInInches = CGSize(
            width: frame.width / unitsPerInch.width,
            height: frame.height / unitsPerInch.height
        )

        let diagonalSize = sqrt(
            pow(screenSizeInInches.width, 2) + pow(screenSizeInInches.height, 2)
        )

        return diagonalSize
    }

    private var unitsPerInch: CGSize {
        let screenDescription = deviceDescription

        guard let displayID,
              let displayUnitSize = (screenDescription[NSDeviceDescriptionKey.size] as? NSValue)?.sizeValue
        else {
            // This is the same as what CoreGraphics assumes if no EDID data is available from the display device
            // https://developer.apple.com/documentation/coregraphics/cgdisplayscreensize(_:)
            return CGSize(width: 72.0, height: 72.0)
        }

        // We need to convert from mm to inch because CGDisplayScreenSize returns units in mm.
        let millimetersPerInch: CGFloat = 25.4
        let displayPhysicalSize = CGDisplayScreenSize(displayID)

        return CGSize(
            width: millimetersPerInch * displayUnitSize.width / displayPhysicalSize.width,
            height: millimetersPerInch * displayUnitSize.height / displayPhysicalSize.height
        )
    }

    // MARK: - Screen overlap

    private func verticalOverlap(with other: NSScreen) -> CGFloat {
        let a = frame
        let b = other.frame

        let top = max(a.minY, b.minY)
        let bottom = min(a.maxY, b.maxY)
        return max(0, bottom - top)
    }

    private func horizontalOverlap(with other: NSScreen) -> CGFloat {
        let a = frame
        let b = other.frame

        let left = max(a.minX, b.minX)
        let right = min(a.maxX, b.maxX)
        return max(0, right - left)
    }

    private func screensInSameRow(screens: [NSScreen], overlapThreshold: CGFloat = 10.0) -> [NSScreen] {
        screens.filter { verticalOverlap(with: $0) >= overlapThreshold }
    }

    private func screensInSameColumn(screens: [NSScreen], overlapThreshold: CGFloat = 10.0) -> [NSScreen] {
        screens.filter { horizontalOverlap(with: $0) >= overlapThreshold }
    }

    func leftmostScreenInSameRow(overlapThreshold: CGFloat = 10.0) -> NSScreen {
        let sameRowScreens = screensInSameRow(screens: NSScreen.screens, overlapThreshold: overlapThreshold)

        let leftCandidates = sameRowScreens.filter { $0.frame.maxX <= self.frame.minX }

        guard !leftCandidates.isEmpty else {
            return self
        }

        var bestScreen: NSScreen? = nil
        var bestOverlap: CGFloat = -1

        for screen in leftCandidates {
            let overlap = verticalOverlap(with: screen)
            if overlap > bestOverlap || (overlap == bestOverlap && screen.frame.minX < bestScreen?.frame.minX ?? .infinity) {
                bestScreen = screen
                bestOverlap = overlap
            }
        }

        return bestScreen ?? self
    }

    func rightmostScreenInSameRow(overlapThreshold: CGFloat = 10.0) -> NSScreen {
        let sameRowScreens = screensInSameRow(screens: NSScreen.screens, overlapThreshold: overlapThreshold)

        let rightCandidates = sameRowScreens.filter { $0.frame.minX >= self.frame.maxX }

        guard !rightCandidates.isEmpty else {
            return self
        }

        var bestScreen: NSScreen? = nil
        var bestOverlap: CGFloat = -1

        for screen in rightCandidates {
            let overlap = verticalOverlap(with: screen)
            if overlap > bestOverlap || (overlap == bestOverlap && screen.frame.maxX > bestScreen?.frame.maxX ?? -.infinity) {
                bestScreen = screen
                bestOverlap = overlap
            }
        }

        return bestScreen ?? self
    }

    func bottommostScreenInSameColumn(overlapThreshold: CGFloat = 10.0) -> NSScreen {
        let sameColumnScreens = screensInSameColumn(screens: NSScreen.screens, overlapThreshold: overlapThreshold)

        let bottomCandidates = sameColumnScreens.filter { $0.frame.minY >= self.frame.maxY }

        guard !bottomCandidates.isEmpty else {
            return self
        }

        var bestScreen: NSScreen? = nil
        var bestOverlap: CGFloat = -1

        for screen in bottomCandidates {
            let overlap = horizontalOverlap(with: screen)
            if overlap > bestOverlap || (overlap == bestOverlap && screen.frame.maxY > bestScreen?.frame.maxY ?? -.infinity) {
                bestScreen = screen
                bestOverlap = overlap
            }
        }

        return bestScreen ?? self
    }
}
