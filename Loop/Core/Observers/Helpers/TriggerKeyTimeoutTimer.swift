//
//  TriggerKeyTimeoutTimer.swift
//  Loop
//
//  Created by Kami on 06/01/2026.
//

import Defaults
import Foundation
import Tome

/// A utility class that automatically closes Loop if no action is taken within a specified timeout period.
///
/// This timer starts when Loop is opened and automatically triggers the close callback if the user
/// doesn't perform any action within the configured timeout duration (defined by `Tome.triggerKeyTimeout`).
/// The timer can be canceled if the user performs an action or manually closes Loop.
final class TriggerKeyTimeoutTimer {
    private var timeoutTimer: Task<(), Never>?
    private let closeCallback: (Bool) -> ()
    /// Clamped, since a hand-edited value can be negative or huge.
    private var timeout: Duration { min(max(Tome.triggerKeyTimeout, .zero), .seconds(86400)) }

    /// Indicates whether the timeout timer is currently active.
    var isActive: Bool { timeoutTimer != nil }

    /// Creates a new `TriggerKeyTimeoutTimer` instance with the specified callback to invoke after the timeout elapses.
    /// - Parameter closeCallback: A closure that is called once the timeout completes. The closure receives a boolean indicating whether to force close.
    init(closeCallback: @escaping (Bool) -> ()) {
        self.closeCallback = closeCallback
    }

    deinit {
        cancel()
    }

    /// Starts the timeout timer. If Loop is still open when the timeout elapses, the close callback is invoked.
    ///
    /// This should be called when Loop is opened. If a timeout is already active, it will be canceled and restarted.
    func start() {
        guard timeout > .zero else { return }

        cancel() // Ensure no previous timer is active

        timeoutTimer = Task { @MainActor in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }

            closeCallback(false) // Auto-close without forcing
            cancel()
        }
    }

    /// Cancels any active timeout timer.
    func cancel() {
        timeoutTimer?.cancel()
        timeoutTimer = nil
    }
}
