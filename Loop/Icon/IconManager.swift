//
//  IconManager.swift
//  Loop
//
//  Created by Kai Azim on 2023-02-14.
//

import Defaults
import Luminare
import Scribe
import SwiftUI
import Tome
import UserNotifications

@Loggable(style: .static)
enum IconManager {
    static func returnUnlockedIcons() -> [Icon] {
        var returnValue: [Icon] = []
        for icon in Icon.all where icon.unlockTime <= Defaults[.timesLooped] {
            returnValue.append(icon)
        }

        return returnValue.reversed()
    }

    static func setAppIcon(to icon: Icon) {
        Defaults[.currentIcon] = icon.assetName
        refreshCurrentAppIcon()
    }

    static func setAppIcon(to assetName: String) {
        if let targetIcon = Icon.all.first(where: { $0.assetName == assetName }) {
            setAppIcon(to: targetIcon)
        }
    }

    /// This function is run at startup to set the current icon to the user's set icon.
    static func refreshCurrentAppIcon() {
        let iconName = Defaults[.currentIcon]

        guard let image = NSImage(named: iconName) else {
            log.error("Failed to load icon: \(iconName)")
            return
        }

        let isDefault = IconManager.currentAppIcon.isDefault

        // Notify the dock tile plugin first so it updates immediately
        DistributedNotificationCenter.default().post(
            name: .init("com.MrKai77.Loop.iconChanged"),
            object: nil,
            userInfo: [
                "iconName": iconName,
                "isDefault": isDefault
            ]
        )

        #if !DEBUG
            // Changing the app's actual icon on a developer build can cause Xcode to have incremental codesign issues.
            // To prevent this, we only change the icon on release builds.
            if isDefault {
                NSWorkspace.shared.setIcon(nil, forFile: Bundle.main.bundlePath, options: [])
            } else {
                NSWorkspace.shared.setIcon(image, forFile: Bundle.main.bundlePath, options: [])
            }

            deleteDockIconCache()
            SkyLightToolBelt.refreshIconAppearanceCache()
        #endif

        log.info("Set app icon to: \(iconName)")
    }

    static func checkIfUnlockedNewIcon() {
        guard Tome.notificationWhenIconUnlocked else { return }

        for icon in Icon.all where icon.unlockTime == Defaults[.timesLooped] {
            let content = UNMutableNotificationContent()

            content.title = Bundle.main.appName

            if let message = icon.unlockMessage {
                content.body = message
            } else {
                content.body = String(
                    localized: "Icon Unlock Message",
                    defaultValue: "You've unlocked a new icon: \(icon.name)!",
                    comment: "Default message shown when a new icon is unlocked"
                )
            }

            if let data = NSImage(named: icon.assetName)?.tiffRepresentation,
               let attachment = UNNotificationAttachment.create(NSData(data: data)) {
                content.attachments = [attachment]
                content.userInfo = ["icon": icon.assetName]
            }

            content.categoryIdentifier = "icon_unlocked"

            AppDelegate.sendNotification(content)
        }
    }

    /// Best-effort deletion of the Dock's icon cache file, forcing it to rebuild on next access.
    private static func deleteDockIconCache() {
        // The cache lives in the per-user cache dir (/C/), sibling to the temp dir (/T/)
        let cacheURL = FileManager.default.temporaryDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("C/com.apple.dock.iconcache")

        do {
            try FileManager.default.removeItem(at: cacheURL)
            log.debug("Deleted dock icon cache")
        } catch {
            log.debug("Failed to delete dock icon cache: \(error.localizedDescription)")
        }
    }

    static var currentAppIcon: Icon {
        Icon.all.first {
            $0.assetName == Defaults[.currentIcon]
        } ?? Icon.all.first!
    }
}
