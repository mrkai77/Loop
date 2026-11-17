//
//  TriggerDelayTimer.swift
//  Loop
//
//  Created by Kai Azim on 2025-10-27.
//

import Defaults
import Foundation
import Tome

/// A utility class that delays triggering an action until a specified amount of time has passed.
///
/// It is used to defer the execution of a callback (in this case, opening Loop) by a user-configurable
/// duration, as defined by the user's `Tome.triggerDelay` setting.
/// When using keybinds, you may also want to update the starting action without restarting the timer.
/// In that case, use the `updateStartingAction` method.
final class TriggerDelayTimer {
    private var triggerDelayTimer: Task<(), Never>?
    private var startingAction: WindowAction = .init(.noSelection)
    private let openCallback: (WindowAction) -> ()
    /// Clamped, since a hand-edited value can be negative or huge.
    private var triggerDelay: Duration { min(max(Tome.triggerDelay, .zero), .seconds(86400)) }

    /// Indicates whether the delay timer is currently active.
    var isActive: Bool { triggerDelayTimer != nil }

    /// Creates a new `TriggerDelayTimer` instance with the specified callback to invoke after a user-configured delay has elapsed.
    /// - Parameter openCallback: A closure that is called once the trigger delay completes successfully. The closure receives the latest `WindowAction` depending on what has been set.
    init(openCallback: @escaping (WindowAction) -> ()) {
        self.openCallback = openCallback
    }

    deinit {
        cancel()
    }

    /// Handles a trigger event (such as a key press) and starts or restarts the delay timer.
    ///
    /// If another trigger is received before the delay elapses, the previous timer is canceled and restarted.
    /// Once the configured delay duration passes without interruption, the provided callback is invoked, with the latest inputted starting action.
    /// - Parameter startingAction: The `WindowAction` associated with the trigger.
    func handleTrigger(startingAction action: WindowAction) {
        startingAction = action
        cancel() // Ensure no previous timer is active

        triggerDelayTimer = Task { @MainActor in
            try? await Task.sleep(for: triggerDelay)
            guard !Task.isCancelled else { return }

            openCallback(startingAction)
            cancel()
        }
    }

    /// Updates the stored `startingAction` value without restarting the timer. To be used with keybinds.
    /// - Parameter newAction: The new `WindowAction` to associate with the current trigger delay.
    func updateStartingAction(with newAction: WindowAction) {
        startingAction = newAction
    }

    /// Cancels any active delay timer and clears the stored action.
    func cancel() {
        triggerDelayTimer?.cancel()
        triggerDelayTimer = nil
        startingAction = .init(.noSelection)
    }
}
