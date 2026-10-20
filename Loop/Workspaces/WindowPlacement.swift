//
//  WindowPlacement.swift
//  Loop
//
//  Created on 2026-10-20.
//

import Defaults
import SwiftUI

/// Identifies a display in a way that survives disconnecting and reconnecting it.
struct ScreenReference: Codable, Hashable {
    /// Stable per physical display, derived from `CGDisplayCreateUUIDFromDisplayID`.
    var uuid: String?
    var name: String
    /// Position of the screen when sorted left-to-right, used as a last resort.
    var index: Int

    @MainActor
    init(screen: NSScreen) {
        self.uuid = screen.displayUUID
        self.name = screen.localizedName
        self.index = NSScreen.screensSortedLeftToRight.firstIndex { $0.isSameScreen(screen) } ?? 0
    }

    /// Finds the matching screen among those currently connected, preferring the exact display,
    /// then a display with the same name, then the same position.
    @MainActor
    func resolve() -> NSScreen? {
        let screens = NSScreen.screensSortedLeftToRight

        if let uuid, let match = screens.first(where: { $0.displayUUID == uuid }) {
            return match
        }

        if let match = screens.first(where: { $0.localizedName == name }) {
            return match
        }

        if screens.indices.contains(index) {
            return screens[index]
        }

        return screens.first
    }
}

/// A window's position on a specific screen, recorded so it can be put back later.
struct WindowPlacement: Codable, Hashable {
    /// Only meaningful while the app that owns the window keeps running.
    var windowID: CGWindowID
    var bundleID: String
    var appName: String
    var title: String
    var screen: ScreenReference
    /// The window frame relative to the screen's top-left corner, in points.
    var frameInScreen: CGRect
    /// The screen size at the time of recording, so the frame can be scaled onto a different screen.
    var screenSize: CGSize

    /// Resolves the absolute frame (in global, top-left based coordinates) on the given screen.
    @MainActor
    func frame(on screen: NSScreen) -> CGRect {
        let bounds = screen.displayBounds

        guard bounds.size != screenSize, screenSize.width > 0, screenSize.height > 0 else {
            return frameInScreen.offsetBy(dx: bounds.minX, dy: bounds.minY)
        }

        let scaleX = bounds.width / screenSize.width
        let scaleY = bounds.height / screenSize.height

        return CGRect(
            x: bounds.minX + frameInScreen.minX * scaleX,
            y: bounds.minY + frameInScreen.minY * scaleY,
            width: frameInScreen.width * scaleX,
            height: frameInScreen.height * scaleY
        )
    }
}

/// The remembered window layout for one combination of connected displays.
struct DisplayLayout: Codable, Hashable, Defaults.Serializable {
    var name: String
    var windows: [WindowPlacement]
    var updatedAt: Date
}

/// A named arrangement of apps and windows that can be applied on demand.
struct Workspace: Codable, Hashable, Identifiable, Defaults.Serializable {
    var id: UUID = .init()
    var name: String
    /// Ordered front-to-back, as captured.
    var windows: [WindowPlacement]
    var launchMissingApps: Bool = true
    var hideOtherApps: Bool = false

    var bundleIDs: [String] {
        var seen = Set<String>()
        return windows.map(\.bundleID).filter { seen.insert($0).inserted }
    }

    var appNames: [String] {
        var seen = Set<String>()
        return windows.compactMap { seen.insert($0.bundleID).inserted ? $0.appName : nil }
    }
}

extension NSScreen {
    var displayUUID: String? {
        guard let displayID,
              let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue()
        else {
            return nil
        }
        return CFUUIDCreateString(nil, uuid) as String
    }

    static var screensSortedLeftToRight: [NSScreen] {
        screens.sorted { $0.frame.minX == $1.frame.minX ? $0.frame.minY > $1.frame.minY : $0.frame.minX < $1.frame.minX }
    }

    /// Identifies the current combination of connected displays, regardless of their arrangement.
    static var configurationKey: String {
        screens.map { $0.displayUUID ?? $0.localizedName }.sorted().joined(separator: "|")
    }

    static var configurationName: String {
        screensSortedLeftToRight.map(\.localizedName).joined(separator: " + ")
    }
}
