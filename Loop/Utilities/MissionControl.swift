//
//  MissionControl.swift
//  Loop
//
//  Created by Kai Azim on 2026-09-24.
//

import AppKit

enum MissionControl {
    private static let overlayIdentifiers: Set<String> = ["mc", "appexpose"]

    /// The Dock posts no notifications for these, but adds a group to its AX tree while each is showing
    static var isShowing: Bool {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            return false
        }

        let dockElement = AXUIElementCreateApplication(dock.processIdentifier)
        // Loop can't open while this runs, so don't wait out the default timeout on a hung Dock
        AXUIElementSetMessagingTimeout(dockElement, 0.1)

        return dockElement.children.contains { element in
            guard let identifier: String = try? element.getValue(.identifier) else { return false }
            return overlayIdentifiers.contains(identifier)
        }
    }
}
