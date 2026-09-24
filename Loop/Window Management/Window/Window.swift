//
//  Window.swift
//  Loop
//
//  Created by Kai Azim on 2023-09-01.
//

import Defaults
import Scribe
import SwiftUI

enum WindowError: LocalizedError {
    case sheetWindow
    case blockedBundleID
    case cannotGetWindow
    case filteredOutFromWindowInfo
    case invalidWindowTags
    case invalidWindowLevel(CGWindowLevel)

    var errorDescription: String? {
        switch self {
        case .sheetWindow:
            "Invalid window: sheet"
        case .blockedBundleID:
            "Invalid window: blocked bundle ID"
        case .cannotGetWindow:
            "Could not get the element's window"
        case .filteredOutFromWindowInfo:
            "Filtered out from window info"
        case .invalidWindowTags:
            "Invalid window tags"
        case let .invalidWindowLevel(level):
            "Invalid window: level \(level) is outside the manageable range"
        }
    }
}

@Loggable
final class Window {
    let axWindow: AXUIElement
    let cgWindowID: CGWindowID
    let pid: pid_t
    let nsRunningApplication: NSRunningApplication?

    private static let invalidBundleIDs: Set<String> = [
        "com.apple.PIPAgent", // PIP windows
        "com.apple.notificationcenterui" // Widgets & Notification Center
    ]

    var isOwnWindow: Bool {
        nsRunningApplication?.bundleIdentifier == Bundle.main.bundleIdentifier
    }

    /// Initialize a window from an AXUIElement
    /// - Parameter element: The AXUIElement to initialize the window with. If it is not a window, an error will be thrown
    convenience init(
        element: AXUIElement,
        pid: pid_t? = nil,
        nsRunningApplication: NSRunningApplication? = nil
    ) throws {
        try self.init(
            element: element,
            pid: pid,
            nsRunningApplication: nsRunningApplication,
            knownWindowLevel: nil
        )
    }

    private init(
        element: AXUIElement,
        pid _pid: pid_t?,
        nsRunningApplication _nsRunningApplication: NSRunningApplication?,
        knownWindowLevel: CGWindowLevel?
    ) throws {
        self.axWindow = element
        self.cgWindowID = try element.getWindowID()

        if let _nsRunningApplication {
            self.pid = _nsRunningApplication.processIdentifier
            self.nsRunningApplication = _nsRunningApplication
        } else if let _pid {
            self.pid = _pid
            self.nsRunningApplication = NSRunningApplication(processIdentifier: pid)
        } else {
            let pid = try axWindow.getPID()
            self.pid = pid
            self.nsRunningApplication = NSRunningApplication(processIdentifier: pid)
        }

        guard role != .sheet else {
            throw WindowError.sheetWindow
        }

        if let level = knownWindowLevel ?? SkyLightToolBelt.getWindowLevel(windowID: cgWindowID),
           level < kCGNormalWindowLevel || level >= kCGPopUpMenuWindowLevel {
            throw WindowError.invalidWindowLevel(level)
        }

        guard SkyLightToolBelt.areWindowTagsValid(windowID: cgWindowID) else {
            throw WindowError.invalidWindowTags
        }

        if let bundleIdentifier = nsRunningApplication?.bundleIdentifier,
           Self.invalidBundleIDs.contains(bundleIdentifier) {
            throw WindowError.blockedBundleID
        }
    }

    /// Initialize a window from a PID. The frontmost app with the given PID will be used.
    /// - Parameter pid: The PID of the app to get the window from
    convenience init(pid: pid_t) throws {
        let element = AXUIElementCreateApplication(pid)
        guard let window: AXUIElement = try element.getValue(.focusedWindow) else {
            throw WindowError.cannotGetWindow
        }
        try self.init(
            element: window,
            pid: pid,
            nsRunningApplication: nil
        )
    }

    /// Retrieve a window from a `CGWindowID`.
    /// - Parameter windowID: The window ID to look up.
    static func fromWindowID(_ windowID: CGWindowID) throws -> Window {
        guard let windowInfoList = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) as? [[String: AnyObject]],
              let windowInfo = windowInfoList.first
        else {
            throw WindowError.cannotGetWindow
        }

        return try fromWindowInfo(windowInfo)
    }

    /// Retrieve a window from an entry in a dictionary returned by `CGWindowListCopyWindowInfo`.
    /// - Parameter windowInfo: The dictionary containing information about the window.
    static func fromWindowInfo(_ windowInfo: [String: AnyObject]) throws -> Window {
        // First, check if we can initialize a window simply based on its PID.
        guard
            let alpha = windowInfo[kCGWindowAlpha as String] as? Double, alpha > 0.01, // Ignore invisible windows
            let pid = windowInfo[kCGWindowOwnerPID as String] as? pid_t
        else {
            throw WindowError.filteredOutFromWindowInfo
        }

        let knownWindowLevel = windowInfo[kCGWindowLayer as String] as? CGWindowLevel
        if let knownWindowLevel,
           knownWindowLevel < kCGNormalWindowLevel || knownWindowLevel >= kCGPopUpMenuWindowLevel {
            throw WindowError.invalidWindowLevel(knownWindowLevel)
        }

        let element = AXUIElementCreateApplication(pid)
        guard let windowElements: [AXUIElement] = try element.getValue(.windows),
              !windowElements.isEmpty
        else {
            throw WindowError.cannotGetWindow
        }

        // If there’s only one window, use that as there's no need to grab its frame
        if windowElements.count == 1 {
            let window = try Window(
                element: windowElements[0],
                pid: pid,
                nsRunningApplication: nil,
                knownWindowLevel: knownWindowLevel
            )
            if let windowID = windowInfo[kCGWindowNumber as String] as? CGWindowID,
               window.cgWindowID != windowID {
                throw WindowError.cannotGetWindow
            }
            return window
        }

        // If we can retrieve bounds, then filter candidates out by their respective frames.
        let candidates: [AXUIElement] = if let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: CGFloat],
                                           let frame = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) {
            windowElements.filter {
                if let position: CGPoint = try? $0.getValue(.position),
                   let size: CGSize = try? $0.getValue(.size) {
                    return position == frame.origin && size == frame.size
                }
                return false
            }
        } else {
            windowElements
        }

        let windows = candidates.compactMap {
            try? Window(
                element: $0,
                pid: pid,
                nsRunningApplication: nil,
                knownWindowLevel: knownWindowLevel
            )
        }

        if let windowID = windowInfo[kCGWindowNumber as String] as? CGWindowID {
            guard let match = windows.first(where: { $0.cgWindowID == windowID }) else {
                throw WindowError.cannotGetWindow
            }
            return match
        } else if let first = windows.first {
            return first
        }

        return try Window(
            element: windowElements[0],
            pid: pid,
            nsRunningApplication: nil,
            knownWindowLevel: knownWindowLevel
        )
    }

    var role: NSAccessibility.Role? {
        do {
            guard let value: String = try axWindow.getValue(.role) else {
                return nil
            }
            return NSAccessibility.Role(rawValue: value)
        } catch {
            log.error("Failed to get role: \(error.localizedDescription)")
            return nil
        }
    }

    var subrole: NSAccessibility.Subrole? {
        do {
            guard let value: String = try axWindow.getValue(.subrole) else {
                return nil
            }
            return NSAccessibility.Subrole(rawValue: value)
        } catch {
            log.error("Failed to get subrole: \(error.localizedDescription)")
            return nil
        }
    }

    var title: String? {
        do {
            return try axWindow.getValue(.title)
        } catch {
            log.error("Failed to get title: \(error.localizedDescription)")
            return nil
        }
    }

    var enhancedUserInterface: Bool {
        get {
            do {
                let appWindow = AXUIElementCreateApplication(pid)
                let result: Bool? = try appWindow.getValue(.enhancedUserInterface)
                return result ?? false
            } catch {
                log.error("Failed to get enhancedUserInterface: \(error.localizedDescription)")
                return false
            }
        }
        set {
            do {
                let appWindow = AXUIElementCreateApplication(pid)
                try appWindow.setValue(.enhancedUserInterface, value: newValue)
            } catch {
                log.error("Failed to set enhancedUserInterface: \(error.localizedDescription)")
            }
        }
    }

    /// Focus the window.
    @MainActor
    func focus() {
        let fronted = SkyLightToolBelt.makeFrontProcess(
            windowID: cgWindowID,
            pid: pid
        )

        if !fronted {
            nsRunningApplication?.activate(options: .activateIgnoringOtherApps)
        }

        _ = SkyLightToolBelt.makeKeyWindow(
            windowID: cgWindowID,
            pid: pid
        )

        try? axWindow.performAction(.raise)
    }

    var isAppExcluded: Bool {
        if let nsRunningApplication,
           let path = nsRunningApplication.bundleURL {
            return Defaults[.excludedApps].contains(path)
        }
        return false
    }

    var fullscreen: Bool {
        get {
            do {
                let result: NSNumber? = try axWindow.getValue(.fullScreen)
                return result?.boolValue ?? false
            } catch {
                log.error("Failed to get fullscreen: \(error.localizedDescription)")
                return false
            }
        }
        set {
            do {
                try axWindow.setValue(.fullScreen, value: newValue)
            } catch {
                log.error("Failed to set fullscreen: \(error.localizedDescription)")
            }
        }
    }

    func toggleFullscreen() {
        fullscreen = !fullscreen
    }

    /// Check with the `NSRunningApplication` if the app is hidden (⌘H).
    var isApplicationHidden: Bool {
        nsRunningApplication?.isHidden ?? false
    }

    /// Checks if the app has any visible windows using the `CGWindow` API.
    ///
    /// This is useful because `NSRunningApplication.isHidden` might return `false`
    /// even when the app has no visible windows (for example, if it's a menu bar app).
    /// This method iterates through the list of on-screen windows and checks if
    /// any window belongs to this application and is visible.
    ///
    /// - Returns: `true` if no visible windows are found (i.e., the app is "hidden"); `false` otherwise.
    var isWindowHidden: Bool {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]

        guard let windowListInfo = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return true
        }

        for windowInfo in windowListInfo {
            if let pid = windowInfo[kCGWindowOwnerPID as String] as? pid_t,
               let nsRunningApplication,
               pid == nsRunningApplication.processIdentifier,
               let isVisible = windowInfo[kCGWindowIsOnscreen as String] as? Bool,
               isVisible {
                return false
            }
        }

        return true
    }

    @discardableResult
    func setHidden(_ state: Bool) -> Bool {
        var result = false
        if state {
            result = nsRunningApplication?.hide() ?? false
        } else {
            result = nsRunningApplication?.unhide() ?? false
        }
        return result
    }

    @discardableResult
    func toggleHidden() -> Bool {
        if !isApplicationHidden {
            return setHidden(true)
        }
        return setHidden(false)
    }

    var minimized: Bool {
        get {
            do {
                let result: NSNumber? = try axWindow.getValue(.minimized)
                return result?.boolValue ?? false
            } catch {
                log.error("Failed to get minimized: \(error.localizedDescription)")
                return false
            }
        }
        set {
            do {
                try axWindow.setValue(.minimized, value: newValue)
            } catch {
                log.error("Failed to set minimized: \(error.localizedDescription)")
            }
        }
    }

    func toggleMinimized() {
        minimized = !minimized
    }

    var position: CGPoint {
        do {
            guard let result: CGPoint = try axWindow.getValue(.position) else {
                return .zero
            }
            return result
        } catch {
            log.error("Failed to get position: \(error.localizedDescription)")
            return .zero
        }
    }

    func setPosition(_ point: CGPoint) {
        if isOwnWindow {
            Task { @MainActor in
                guard let win = ownNSWindow() else { return }
                win.setFrameOrigin(CGRect(origin: point, size: win.frame.size).flipY(screen: .screens[0]).origin)
            }
        } else {
            do {
                try axWindow.setValue(.position, value: point)
            } catch {
                log.error("Failed to set position: \(error.localizedDescription)")
            }
        }
    }

    var size: CGSize {
        do {
            guard let result: CGSize = try axWindow.getValue(.size) else {
                return .zero
            }
            return result
        } catch {
            log.error("Failed to get size: \(error.localizedDescription)")
            return .zero
        }
    }

    func setSize(_ size: CGSize) {
        if isOwnWindow {
            Task { @MainActor in
                guard let win = ownNSWindow() else { return }
                win.setFrame(CGRect(origin: win.frame.origin, size: size), display: false)
            }
        } else {
            do {
                try axWindow.setValue(.size, value: size)
            } catch {
                log.error("Failed to set size: \(error.localizedDescription)")
            }
        }
    }

    var isResizable: Bool {
        do {
            let result: Bool = try axWindow.canSetValue(.size)
            return result
        } catch {
            log.error("Failed to determine if window size can be set: \(error.localizedDescription)")
            return true
        }
    }

    var frame: CGRect {
        CGRect(origin: position, size: size)
    }

    /// Returns `true` and applies the frame using AppKit if this window belongs to Loop itself.
    /// AX APIs are unavailable for our own process, so we delegate to `NSWindow` instead.
    @MainActor
    @discardableResult
    private func applyOwnWindowFrame(_ rect: CGRect) -> Bool {
        guard isOwnWindow else {
            return false
        }
        guard let window = ownNSWindow() else {
            log.info("Failed to get own main window to resize")
            return true
        }
        NSAnimationContext.runAnimationGroup { context in
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.33, 1, 0.68, 1)
            window.animator().setFrame(rect.flipY(screen: .screens[0]), display: false)
        }
        return true
    }

    @MainActor
    private func ownNSWindow() -> NSWindow? {
        NSApp.windows.first { $0.windowNumber == cgWindowID } ?? NSApp.keyWindow ?? NSApp.mainWindow
    }

    @discardableResult
    private func applyOwnWindowFrameSynchronously(_ rect: CGRect) -> Bool {
        guard isOwnWindow else {
            return false
        }

        if Thread.isMainThread {
            MainActor.assumeIsolated {
                guard let window = ownNSWindow() else {
                    log.info("Failed to get own main window to resize")
                    return
                }
                window.setFrame(rect.flipY(screen: .screens[0]), display: false)
            }
        } else {
            DispatchQueue.main.sync {
                MainActor.assumeIsolated {
                    guard let window = ownNSWindow() else {
                        log.info("Failed to get own main window to resize")
                        return
                    }
                    window.setFrame(rect.flipY(screen: .screens[0]), display: false)
                }
            }
        }

        return true
    }

    func setFrame(
        _ rect: CGRect,
        sizeFirst: Bool = false,
        resolvedProperties: ResolvedProperties? = nil
    ) async {
        guard await !MainActor.run(resultType: Bool.self, body: { applyOwnWindowFrame(rect) }) else {
            return
        }

        let enhancedUI = resolvedProperties?.isEnhancedUserInterface ?? enhancedUserInterface
        let shouldSetSize = resolvedProperties?.isResizable ?? true

        if enhancedUI {
            let appName = nsRunningApplication?.localizedName
            log.info("\(appName ?? "This app")'s enhanced UI will be temporarily disabled while resizing.")
            enhancedUserInterface = false
        }

        if sizeFirst, shouldSetSize {
            setSize(rect.size)
        }

        setPosition(rect.origin)

        if shouldSetSize {
            setSize(rect.size)
        }

        if enhancedUI {
            enhancedUserInterface = true
        }
    }

    func setFrameSynchronously(
        _ rect: CGRect,
        sizeFirst: Bool = false,
        resolvedProperties: ResolvedProperties? = nil
    ) {
        guard !applyOwnWindowFrameSynchronously(rect) else {
            return
        }

        let enhancedUI = resolvedProperties?.isEnhancedUserInterface ?? enhancedUserInterface
        let shouldSetSize = resolvedProperties?.isResizable ?? true

        if enhancedUI {
            let appName = nsRunningApplication?.localizedName
            log.info("\(appName ?? "This app")'s enhanced UI will be temporarily disabled while resizing.")
            enhancedUserInterface = false
        }

        if sizeFirst, shouldSetSize {
            setSize(rect.size)
        }

        setPosition(rect.origin)

        if shouldSetSize {
            setSize(rect.size)
        }

        if enhancedUI {
            enhancedUserInterface = true
        }
    }

    @MainActor
    func setFrameAnimated(
        _ rect: CGRect,
        bounds: CGRect,
        resolvedProperties: ResolvedProperties? = nil
    ) async throws {
        try Task.checkCancellation()

        guard !applyOwnWindowFrame(rect) else {
            return
        }

        let enhancedUI = resolvedProperties?.isEnhancedUserInterface ?? enhancedUserInterface
        let shouldSetSize = resolvedProperties?.isResizable ?? true

        if enhancedUI {
            let appName = nsRunningApplication?.localizedName
            log.info("\(appName ?? "This app")'s enhanced UI will be temporarily disabled while resizing.")
            enhancedUserInterface = false
        }
        defer {
            if enhancedUI {
                enhancedUserInterface = true
            }
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(), Error>) in
            let animation = WindowTransformAnimation(
                rect,
                window: self,
                bounds: bounds,
                shouldSetSize: shouldSetSize
            ) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }

            animation.start()
        }
    }
}

extension Window: CustomStringConvertible {
    var description: String {
        "Window(id: \(cgWindowID), app: '\(nsRunningApplication?.localizedName ?? "<unknown>")', title: '\(title ?? "<unknown>")')"
    }
}

extension Window: Equatable {
    static func == (lhs: Window, rhs: Window) -> Bool {
        lhs.cgWindowID == rhs.cgWindowID
    }
}

// MARK: - ResolvedProperties

extension Window {
    /// Pre-resolved snapshot of a window's AX properties for synchronous access.
    /// Avoids repeated IPC round-trips when multiple properties are needed.
    struct ResolvedProperties {
        let frame: CGRect
        let isResizable: Bool
        let isFullscreen: Bool
        let isEnhancedUserInterface: Bool

        init(from window: Window) {
            self.frame = window.frame // 2 AX calls (position + size)
            self.isResizable = window.isResizable // 1 AX call
            self.isFullscreen = window.fullscreen // 1 AX call
            self.isEnhancedUserInterface = window.enhancedUserInterface // 1 AX call on app element
        }

        /// Creates a new snapshot with an updated frame, preserving stable properties.
        /// Used after a resize to avoid re-reading from AX.
        /// `isFullscreen` is always false post-resize, as we exited fullscreen to perform the resize.
        init(updating frame: CGRect, from other: ResolvedProperties) {
            self.frame = frame
            self.isResizable = other.isResizable
            self.isFullscreen = false
            self.isEnhancedUserInterface = other.isEnhancedUserInterface
        }
    }
}
