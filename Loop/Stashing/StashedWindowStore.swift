//
//  StashedWindowStore.swift
//  Loop
//
//  Created by Guillaume Clédat on 28/05/2025.
//

import Defaults
import Foundation
import Scribe
import SwiftUI

@MainActor
protocol StashedWindowsStoreDelegate: AnyObject {
    var stashedWindowVisiblePadding: CGFloat { get }
    func onStashedWindowsRestored()
}

/// Keep the stashed windows and the revealed window ids both in memory and in Defaults.
/// Restore windows stashed from a previous session.
@Loggable
@MainActor
final class StashedWindowsStore {
    weak var delegate: StashedWindowsStoreDelegate?

    private(set) var stashed: [CGWindowID: StashedWindowInfo] = [:]
    private(set) var revealed: Set<CGWindowID> = []

    /// Hold data from `Defaults[.stashManagerStashedWindows]` for windows that failed to be restored.
    private var failedToRestore: [CGWindowID: WindowAction] = [:]
    private var spaceObserverTask: Task<(), Never>?

    // MARK: - Public methods

    func restore() async {
        await restoreStashedWindows()
    }

    func isWindowRevealed(_ id: CGWindowID) -> Bool {
        revealed.contains(id)
    }

    func markWindowAsRevealed(_ id: CGWindowID) {
        revealed.insert(id)
    }

    func markWindowAsHidden(_ id: CGWindowID) {
        revealed.remove(id)
    }

    /// Return the stashed window that match the given `action` and `screen`
    func stashedWindow(for action: WindowAction, on screen: NSScreen) -> StashedWindowInfo? {
        stashed.values.first { $0.action.id == action.id && $0.screen.isSameScreen(screen) }
    }

    func setStashedWindow(cgWindowID: CGWindowID, to window: StashedWindowInfo?) {
        guard stashed[cgWindowID] != window else {
            return
        }

        stashed[cgWindowID] = window

        Defaults[.stashManagerStashedWindows] = stashed.mapValues(\.action)
        log.info("Persisted stashed windows (count: \(stashed.count))")
    }

    // MARK: Private methods

    private func restoreStashedWindows() async {
        let windows = WindowUtility.windowList()
        let defaultStashedWindows = Defaults[.stashManagerStashedWindows]
        var restoredStashedWindows: [CGWindowID: StashedWindowInfo] = [:]

        for (windowId, direction) in defaultStashedWindows {
            guard let stashedWindow = await getStashedWindow(for: windowId, in: windows, action: direction) else {
                failedToRestore[windowId] = direction
                continue
            }

            restoredStashedWindows[windowId] = stashedWindow
        }

        if !restoredStashedWindows.isEmpty {
            stashed = restoredStashedWindows
            log.info("\(restoredStashedWindows.count) stashed window restored.")
            delegate?.onStashedWindowsRestored()
        }

        if !failedToRestore.isEmpty {
            log.error("Failed to restore \(failedToRestore.count) window(s).")

            // Window restoration usually fail because the window is on another space and will
            // not be returned by WindowEngine.windowList until the user goes to that space.
            spaceObserverTask = Task { [weak self] in
                let notifications = NSWorkspace.shared.notificationCenter.notifications(
                    named: NSWorkspace.activeSpaceDidChangeNotification
                )

                for await _ in notifications {
                    guard !Task.isCancelled else { return }
                    await self?.onSpaceChanged()
                }
            }
        }
    }

    private func onSpaceChanged() async {
        let windows = WindowUtility.windowList()
        var restored = 0

        log.info("Space changed. Attempting to restore windows.")

        for (windowId, direction) in failedToRestore {
            guard let stashedWindow = await getStashedWindow(for: windowId, in: windows, action: direction) else {
                continue
            }

            stashed[windowId] = stashedWindow
            failedToRestore.removeValue(forKey: windowId)
            restored += 1
        }

        if restored > 0 {
            delegate?.onStashedWindowsRestored()
        }

        if failedToRestore.isEmpty {
            spaceObserverTask?.cancel()
            spaceObserverTask = nil
        }
    }

    private func getStashedWindow(for windowId: CGWindowID, in windows: [Window], action: WindowAction) async -> StashedWindowInfo? {
        guard let window = windows.first(where: { $0.cgWindowID == windowId }) else { return nil }
        guard let screen = ScreenUtility.screenContaining(window) ?? NSScreen.main else { return nil }
        guard let peekSize = delegate?.stashedWindowVisiblePadding else { return nil }

        return await StashedWindowInfo.create(
            window: window,
            screen: screen,
            action: action,
            peekSize: peekSize
        )
    }
}
