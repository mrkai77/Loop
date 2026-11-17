//
//  MiddleClickTrigger.swift
//  Loop
//
//  Created by Kai Azim on 2025-08-29.
//

import AppKit
import Defaults
import Tome

/// Reads middle-click events using a PassiveEventMonitor, and triggers Loop open/close callbacks, when appropriate.
final class MiddleClickTrigger {
    // Callbacks
    private let openCallback: (WindowAction) -> ()
    private let closeCallback: (Bool) -> ()
    private let checkIfLoopOpen: () -> Bool

    private var monitor: PassiveEventMonitor?

    // Defaults
    private var middleClickTriggersLoop: Bool { Tome.middleClickTriggersLoop }
    private var useTriggerDelay: Bool { Tome.enableTriggerDelayOnMiddleClick && Tome.triggerDelay > .milliseconds(100) }
    private var doubleClickToTrigger: Bool { Tome.doubleClickToTrigger }

    private lazy var triggerDelayTimer = TriggerDelayTimer(openCallback: openCallback)
    private lazy var doubleClickTimer = DoubleClickTimer { [weak self] action in
        guard let self else { return }

        if useTriggerDelay {
            triggerDelayTimer.handleTrigger(startingAction: .init(.noSelection))
        } else {
            openCallback(action)
        }
    }

    /// Initializes a ``MiddleClickObserver``.
    /// - Parameters:
    ///   - openCallback: what to do when the middle mouse button is pressed, and Loop should be activated.
    ///   - closeCallback: what to do when the middle mouse button is released, and Loop should be closed.
    init(
        openCallback: @escaping (WindowAction) -> (),
        closeCallback: @escaping (Bool) -> (),
        checkIfLoopOpen: @escaping () -> Bool
    ) {
        // We will never start off with an action from this trigger, so pass in nil
        self.openCallback = openCallback
        self.closeCallback = closeCallback
        self.checkIfLoopOpen = checkIfLoopOpen
    }

    func start() {
        stop()

        let monitor = PassiveEventMonitor(
            "middle_click_trigger",
            events: [.otherMouseDown, .otherMouseUp],
            callback: handleOtherMouseKeypress
        )
        monitor.start()

        self.monitor = monitor
    }

    func stop() {
        monitor?.stop()
        monitor = nil
    }

    // MARK: Private

    private func handleOtherMouseKeypress(_ event: CGEvent) {
        Task { @MainActor in
            guard middleClickTriggersLoop else {
                return
            }

            if event.type == .otherMouseDown,
               event.getIntegerValueField(.mouseEventButtonNumber) == 2 {
                if doubleClickToTrigger {
                    doubleClickTimer.handleKeyDown(startingAction: .init(.noSelection))
                } else if useTriggerDelay {
                    triggerDelayTimer.handleTrigger(startingAction: .init(.noSelection))
                } else {
                    openCallback(.init(.noSelection))
                }
            } else {
                if !checkIfLoopOpen() {
                    doubleClickTimer.handleKeyUp()
                }

                triggerDelayTimer.cancel()
                closeCallback(false)
            }
        }
    }
}
