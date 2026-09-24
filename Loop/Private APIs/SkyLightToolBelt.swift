//
//  SkyLightToolBelt.swift
//  Loop
//
//  Created by Kai Azim on 2025-11-24.
//

import Scribe
import SwiftUI

/// A wrapper for functions defined in `SkyLightSymbolLoader`
@Loggable(style: .static)
enum SkyLightToolBelt {
    struct ManagedDisplay {
        let identifier: UUID
        let spaces: [ManagedSpace]
        let currentSpace: ManagedSpace

        init?(dictionary: NSDictionary) {
            guard
                let identifier = UUID(uuidString: dictionary["Display Identifier"] as? String ?? ""),
                let spaces = (dictionary["Spaces"] as? [NSDictionary])?.compactMap({ ManagedSpace(dictionary: $0) }),
                let currentSpace = ManagedSpace(dictionary: dictionary["Current Space"] as? NSDictionary)
            else {
                return nil
            }

            self.identifier = identifier
            self.spaces = spaces
            self.currentSpace = currentSpace
        }
    }

    struct ManagedSpace {
        let id: UInt64
        let managedID: UInt64
        let type: UInt64
        let uuid: UUID?

        var isDesktop: Bool {
            type == 0
        }

        init?(dictionary: NSDictionary?) {
            guard
                let dictionary,
                let id = dictionary["id64"] as? UInt64,
                let managedID = dictionary["ManagedSpaceID"] as? UInt64,
                let type = dictionary["type"] as? UInt64
            else {
                return nil
            }

            self.id = id
            self.managedID = managedID
            self.type = type
            self.uuid = UUID(uuidString: dictionary["uuid"] as? String ?? "")
        }
    }

    /// Brings the window’s owning process to the front using SkyLight APIs.
    /// - Parameters:
    ///   - windowID: The `CGWindowID` of the window to make the frontmost process.
    ///   - pid: The PID of the target window's owner process.
    /// - Returns: Whether this operation was successful.
    static func makeFrontProcess(windowID: CGWindowID, pid: pid_t) -> Bool {
        guard let SLPSSetFrontProcessWithOptions = SkyLightSymbolLoader.SLPSSetFrontProcessWithOptions else {
            log.error("Failed to load SkyLight symbols in \(#function)")
            return false
        }

        var psn = ProcessSerialNumber()
        let status = GetProcessForPID(pid, &psn)

        guard status == noErr else {
            log.error("Failed to get PSN: \(status)")
            return false
        }

        let cgStatus = SLPSSetFrontProcessWithOptions(
            &psn,
            windowID,
            kCPSUserGenerated
        )

        guard cgStatus == .success else {
            log.error("Failed to set frontmost process with status: \(cgStatus.rawValue)")
            return false
        }

        return true
    }

    /// Byte layout for the `CGSEventRecord` posted by `makeKeyWindow`.
    /// Offsets are from CGSInternal's CGSEvent.h:
    /// https://github.com/NUIKit/CGSInternal/blob/master/CGSEvent.h
    private enum MakeKeyWindowEvent {
        /// Allocated buffer size. The record itself remains `recordLength` bytes; the extra zeroed padding
        /// prevents WindowServer encoding from reading beyond the allocation on macOS 14.7.4 and later.
        /// See:
        /// https://github.com/karinushka/paneru/issues/123
        static let bufferSize = 0x100
        /// The record's declared length.
        static let lengthOffset = 0x04
        static let recordLength: UInt8 = 0xF8
        /// The `CGSEventType`, matching the public `CGEventType` values. A mouse-down is enough to make the
        /// window key; omitting mouse-up prevents the event from activating a control. Thanks to AltTab for
        /// testing this behavior:
        /// https://github.com/lwouis/alt-tab-macos/commit/ec30bb13084e68cb3cde32ec415fdba1fd92876e
        static let eventTypeOffset = 0x08
        static let leftMouseDown: UInt8 = 0x01 // kCGEventLeftMouseDown
        /// The window-relative event point. This must be finite: filling these bytes with `0xFF` produces NaN,
        /// which can terminate Chromium PWA app-shim Mojo connections (#1132). It must also be far from the
        /// frame, since we (and AltTab) found that `(-1, -1)` can land in the resize region on macOS 27 and expand the
        /// window. A far bottom-right point avoids both issues and favors less interactive content if an app clamps it.
        static let windowLocationOffset = 0x20
        static let offContentPoint = CGPoint(x: 300_000, y: 300_000)
        /// The target `CGWindowID`. The event is delivered by id, not by the point above.
        static let windowIdOffset = 0x3C
        /// Undocumented flag retained from the upstream implementations.
        static let unknownFlagOffset = 0x3A
        static let unknownFlagValue: UInt8 = 0x10
    }

    /// Makes a window key within its owning process by posting a synthetic left-mouse-down event.
    ///
    /// Uses a private API. Derived from Hammerspoon / yabai / AltTab
    /// (https://github.com/Hammerspoon/hammerspoon/issues/370#issuecomment-545545468,
    /// https://github.com/lwouis/alt-tab-macos/commit/ec30bb13084e68cb3cde32ec415fdba1fd92876e).
    ///
    /// - Parameters:
    ///   - windowID: The `CGWindowID` of the window to focus.
    ///   - pid: The PID of the target window's owner process.
    /// - Returns: Whether this operation was successful.
    static func makeKeyWindow(windowID: CGWindowID, pid: pid_t) -> Bool {
        guard let SLPSPostEventRecordTo = SkyLightSymbolLoader.SLPSPostEventRecordTo else {
            log.error("Failed to load SkyLight symbols in \(#function)")
            return false
        }

        var wid = windowID
        var psn = ProcessSerialNumber()
        let status = GetProcessForPID(pid, &psn)

        guard status == noErr else {
            log.error("Failed to get PSN: \(status)")
            return false
        }

        var offContentPoint = MakeKeyWindowEvent.offContentPoint

        var bytes = [UInt8](repeating: 0, count: MakeKeyWindowEvent.bufferSize)
        bytes[MakeKeyWindowEvent.lengthOffset] = MakeKeyWindowEvent.recordLength
        bytes[MakeKeyWindowEvent.eventTypeOffset] = MakeKeyWindowEvent.leftMouseDown
        bytes[MakeKeyWindowEvent.unknownFlagOffset] = MakeKeyWindowEvent.unknownFlagValue
        memcpy(&bytes[MakeKeyWindowEvent.windowIdOffset], &wid, MemoryLayout<CGWindowID>.size)
        memcpy(&bytes[MakeKeyWindowEvent.windowLocationOffset], &offContentPoint, MemoryLayout<CGPoint>.size)

        let cgStatus = bytes.withUnsafeMutableBufferPointer { pointer in
            SLPSPostEventRecordTo(&psn, &pointer.baseAddress!.pointee)
        }

        guard cgStatus == .success else {
            log.error("Failed to post key-window event with status: \(cgStatus.rawValue)")
            return false
        }

        return true
    }

    /// Sets the background blur radius of a window.
    /// - Parameters:
    ///   - windowID: The `CGWindowID` of the window to manipulate.
    ///   - radius: The desired blur radius.
    /// - Returns: Whether this operation was successful.
    static func setBackgroundBlur(windowID: CGWindowID, radius: Int) {
        guard let SLSDefaultConnectionForThread = SkyLightSymbolLoader.SLSDefaultConnectionForThread,
              let SLSSetWindowBackgroundBlurRadius = SkyLightSymbolLoader.SLSSetWindowBackgroundBlurRadius
        else {
            log.error("Failed to load SkyLight symbols in \(#function)")
            return
        }

        let cid = SLSDefaultConnectionForThread()
        let status = SLSSetWindowBackgroundBlurRadius(
            cid,
            windowID,
            radius
        )

        if status != noErr {
            log.error("Failed to set window background blur radius")
        }
    }

    /// Returns the display ID containing the given point, using the same tie-breaking
    /// WindowServer uses at display boundaries.
    /// - Parameter cgPoint: The point in the CoreGraphics coordinate system.
    /// - Returns: The matching `CGDirectDisplayID`, or `nil` if the point isn't on any managed display.
    static func bestManagedDisplayID(forCGPoint cgPoint: CGPoint) -> CGDirectDisplayID? {
        guard let SLSMainConnectionID = SkyLightSymbolLoader.SLSMainConnectionID,
              let SLSCopyBestManagedDisplayForPoint = SkyLightSymbolLoader.SLSCopyBestManagedDisplayForPoint
        else {
            return nil
        }

        guard let uuidString = SLSCopyBestManagedDisplayForPoint(SLSMainConnectionID(), cgPoint)?.takeRetainedValue(),
              let uuid = CFUUIDCreateFromString(nil, uuidString)
        else {
            return nil
        }

        let displayID = CGDisplayGetDisplayIDFromUUID(uuid)
        return displayID != 0 ? displayID : nil
    }

    /// Finds the topmost window at a given screen position.
    /// - Parameter position: The screen position to check.
    /// - Returns: The `CGWindowID` of the window at the position, or `nil` if none found.
    static func windowIDAtPosition(_ position: CGPoint) -> CGWindowID? {
        guard let SLSMainConnectionID = SkyLightSymbolLoader.SLSMainConnectionID,
              let SLSFindWindowByGeometry = SkyLightSymbolLoader.SLSFindWindowByGeometry
        else {
            return nil
        }

        let cid = SLSMainConnectionID()
        var screenPoint = position
        var windowPoint = CGPoint.zero
        var hitWindowID: CGWindowID = 0
        var windowCID: Int32 = 0

        let status = SLSFindWindowByGeometry(cid, 0, 1, 0, &screenPoint, &windowPoint, &hitWindowID, &windowCID)
        guard status == .success else { return nil }

        return hitWindowID != 0 ? hitWindowID : nil
    }

    /// Checks whether a specific window has valid SkyLight tags and no parent window.
    static func areWindowTagsValid(windowID: CGWindowID) -> Bool {
        guard let SLSWindowQueryWindows = SkyLightSymbolLoader.SLSWindowQueryWindows,
              let SLSWindowQueryResultCopyWindows = SkyLightSymbolLoader.SLSWindowQueryResultCopyWindows,
              let SLSWindowIteratorAdvance = SkyLightSymbolLoader.SLSWindowIteratorAdvance,
              let SLSWindowIteratorGetWindowID = SkyLightSymbolLoader.SLSWindowIteratorGetWindowID,
              let SLSMainConnectionID = SkyLightSymbolLoader.SLSMainConnectionID
        else {
            log.error("Failed to load symbols in \(#function)")
            return false
        }

        let query = SLSWindowQueryWindows(SLSMainConnectionID(), [windowID] as CFArray, 0)
        let iterator = SLSWindowQueryResultCopyWindows(query)

        while SLSWindowIteratorAdvance(iterator) {
            guard SLSWindowIteratorGetWindowID(iterator) == windowID else { continue }
            return areWindowTagsValid(iterator)
        }

        return false
    }

    /// Captures images for each of the windows that are passed in.
    /// - Parameter windowIDs: The `CGWindowID`s for each of the windows to capture.
    /// - Returns: An array of `CGImage`s for each window, in the same order as the windows that were passed in.
    static func captureWindowList(windowIDs: [CGWindowID]) -> [CGImage] {
        guard let SLSMainConnectionID = SkyLightSymbolLoader.SLSMainConnectionID,
              let SLSHWCaptureWindowList = SkyLightSymbolLoader.SLSHWCaptureWindowList
        else {
            log.error("Failed to load SkyLight symbols in \(#function)")
            return []
        }

        var captureWindowIDs = windowIDs
        let options: SLSWindowCaptureOptions = [.ignoreGlobalClipShape, .bestResolution, .fullSize]

        let cid = SLSMainConnectionID()
        let images = SLSHWCaptureWindowList(
            cid,
            &captureWindowIDs,
            captureWindowIDs.count,
            options.rawValue
        ).takeRetainedValue() as! [CGImage]

        return images
    }

    /// Retrieves the CGWindowLevel for a specific window.
    /// - Parameter windowID: The `CGWindowID` of the window to query.
    /// - Returns: The window's level, or `nil` if the lookup failed.
    static func getWindowLevel(windowID: CGWindowID) -> CGWindowLevel? {
        guard let SLSMainConnectionID = SkyLightSymbolLoader.SLSMainConnectionID,
              let SLSGetWindowLevel = SkyLightSymbolLoader.SLSGetWindowLevel
        else {
            log.error("Failed to load SkyLight symbols in \(#function)")
            return nil
        }

        var level: Int32 = 0
        let status = SLSGetWindowLevel(SLSMainConnectionID(), windowID, &level)

        guard status == .success else {
            log.error("Failed to get window level for \(windowID): \(status.rawValue)")
            return nil
        }

        return level
    }

    /// Moves the window to a Mission Control desktop space.
    /// - Parameters:
    ///   - windowID: The `CGWindowID` of the window to move.
    ///   - spaceID: The target managed space id64.
    /// - Returns: Whether the window is on, or was moved to, the target space.
    @available(macOS 14.0, *)
    @discardableResult
    static func moveWindow(_ windowID: CGWindowID, toSpace spaceID: UInt64) -> Bool {
        if copySpaces(forWindows: [windowID]).contains(spaceID) {
            return true
        }

        let moved = SkyLightBridgedSPI.moveWindow(windowID, toSpace: spaceID)
        if !moved {
            log.error("SkyLight bridged window movement is unavailable")
        }

        return moved
    }

    /// Returns all managed displays and their spaces in Mission Control order.
    @available(macOS 14.0, *)
    static func copyDisplaysWithSpaces() -> [ManagedDisplay] {
        guard let result = SkyLightBridgedSPI.copyManagedDisplaySpaces() else {
            log.error("SkyLight bridged display space lookup is unavailable")
            return []
        }

        return result.compactMap(ManagedDisplay.init(dictionary:))
    }

    /// Returns the largest number of regular desktop spaces on any managed display.
    @available(macOS 14.0, *)
    static func maximumDesktopCount() -> Int {
        copyDisplaysWithSpaces()
            .map { display in
                display.spaces.filter(\.isDesktop).count
            }
            .max() ?? 0
    }

    /// Returns the managed space ids for the given windows.
    @available(macOS 14.0, *)
    static func copySpaces(forWindows windowIDs: [CGWindowID]) -> [UInt64] {
        guard let numbers = SkyLightBridgedSPI.copySpaces(forWindows: windowIDs, options: .allManaged) else {
            log.error("SkyLight bridged window space lookup is unavailable")
            return []
        }

        return numbers.map { UInt64(truncating: $0) }
    }

    /// Returns the first managed space id for a window, or `nil` if SkyLight cannot resolve it.
    @available(macOS 14.0, *)
    static func copySpace(forWindow windowID: CGWindowID) -> UInt64? {
        let spaceID = copySpaces(forWindows: [windowID]).first ?? 0
        return spaceID == 0 ? nil : spaceID
    }

    /// Resolves the desktop space adjacent to the window's current desktop.
    /// - Parameters:
    ///   - windowID: The target window.
    ///   - offset: `-1` for previous desktop, `1` for next desktop.
    @available(macOS 14.0, *)
    static func desktopSpace(forWindow windowID: CGWindowID, offset: Int) -> ManagedSpace? {
        guard offset != 0,
              let currentSpaceID = copySpace(forWindow: windowID),
              let display = copyDisplaysWithSpaces().first(where: { display in
                  display.spaces.contains { $0.id == currentSpaceID }
              })
        else {
            return nil
        }

        let desktops = display.spaces.filter(\.isDesktop)
        guard let currentIndex = desktops.firstIndex(where: { $0.id == currentSpaceID }) else {
            log.error("Window \(windowID) is not on a regular desktop space")
            return nil
        }

        let targetIndex = currentIndex + offset
        guard desktops.indices.contains(targetIndex) else {
            return nil
        }

        return desktops[targetIndex]
    }

    /// Resolves a 1-based desktop number on the display hosting the window's current space.
    @available(macOS 14.0, *)
    static func desktopSpace(forWindow windowID: CGWindowID, desktopNumber: UInt) -> ManagedSpace? {
        guard desktopNumber > 0,
              let currentSpaceID = copySpace(forWindow: windowID),
              let display = copyDisplaysWithSpaces().first(where: { display in
                  display.spaces.contains { $0.id == currentSpaceID }
              })
        else {
            return nil
        }

        let desktops = display.spaces.filter(\.isDesktop)
        let targetIndex = Int(desktopNumber - 1)

        guard desktops.indices.contains(targetIndex) else {
            return nil
        }

        return desktops[targetIndex]
    }

    /// Retrieves the corner radii for a specific window.
    /// - Parameter windowID: The `CGWindowID` of the window
    /// - Returns: The corner radii of the window if the operation was successful, or `nil` otherwise.
    @available(macOS 26.0, *)
    static func getCornerRadii(windowID: CGWindowID) -> RectangleCornerRadii? {
        guard let SLSMainConnectionID = SkyLightSymbolLoader.SLSMainConnectionID,
              let SLSWindowQueryWindows = SkyLightSymbolLoader.SLSWindowQueryWindows,
              let SLSWindowQueryResultCopyWindows = SkyLightSymbolLoader.SLSWindowQueryResultCopyWindows,
              let SLSWindowIteratorAdvance = SkyLightSymbolLoader.SLSWindowIteratorAdvance,
              let SLSWindowIteratorGetWindowID = SkyLightSymbolLoader.SLSWindowIteratorGetWindowID,
              let SLSWindowIteratorGetResolvedCornerRadii = SkyLightSymbolLoader.SLSWindowIteratorGetResolvedCornerRadii
        else {
            log.error("Failed to load SkyLight symbols in \(#function)")
            return nil
        }

        let windowIDsCFArray: CFArray = [windowID] as CFArray

        let cid = SLSMainConnectionID()
        let query = SLSWindowQueryWindows(cid, windowIDsCFArray, 0)
        let iterator = SLSWindowQueryResultCopyWindows(query)

        while SLSWindowIteratorAdvance(iterator) {
            guard areWindowTagsValid(iterator), SLSWindowIteratorGetWindowID(iterator) == windowID else {
                continue
            }

            guard let cornerRadii = SLSWindowIteratorGetResolvedCornerRadii(iterator, windowID).takeRetainedValue() as? [CGFloat],
                  cornerRadii.count == 4
            else {
                return nil
            }

            return RectangleCornerRadii(
                topLeading: cornerRadii[0],
                bottomLeading: cornerRadii[3],
                bottomTrailing: cornerRadii[2],
                topTrailing: cornerRadii[1]
            )
        }

        return nil
    }

    /// Forces the system to re-resolve icon appearance variants by flushing the Dock's icon cache.
    /// Re-saves the current `SLSIconAppearanceConfiguration`, causing the Dock to re-read the
    /// bundle's `.icon` file (which supports light/dark/clear variants).
    /// https://www.granola.ai/blog/so-you-think-its-easy-to-change-an-app-icon
    static func refreshIconAppearanceCache() {
        guard let cls = NSClassFromString("SLSIconAppearanceConfiguration") as? NSObject.Type else {
            log.error("SLSIconAppearanceConfiguration class not found")
            return
        }

        let fetchSelector = NSSelectorFromString("fetchCurrentIconAppearanceConfiguration")
        guard cls.responds(to: fetchSelector),
              let config = cls.perform(fetchSelector)?.takeUnretainedValue() as? NSObject else {
            log.error("Failed to fetch icon appearance configuration")
            return
        }

        let saveSelector = NSSelectorFromString("save")
        guard config.responds(to: saveSelector) else {
            log.error("Icon appearance configuration does not respond to save")
            return
        }

        config.perform(saveSelector)
    }

    /// Checks if the current window in an `SLSWindowIterator` has valid tags and no parent window.
    /// - Parameter iterator: The `SLSWindowIterator` object
    /// - Returns: Whether this window is valid.
    private static func areWindowTagsValid(_ iterator: CFTypeRef) -> Bool {
        guard let SLSWindowIteratorGetParentID = SkyLightSymbolLoader.SLSWindowIteratorGetParentID,
              let SLSWindowIteratorGetTags = SkyLightSymbolLoader.SLSWindowIteratorGetTags
        else {
            log.error("Failed to load SkyLight symbols in \(#function)")
            return false
        }

        let parentWindowID: CGWindowID = SLSWindowIteratorGetParentID(iterator)

        guard parentWindowID == 0 else {
            return false
        }

        let tags = SLSWindowTags(rawValue: SLSWindowIteratorGetTags(iterator))
        return tags.contains(.document) || tags.contains(.floating)
    }
}
