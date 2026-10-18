//
//  KeybindTrigger.swift
//  Loop
//
//  Created by Kai Azim on 2023-06-18.
//

import Cocoa
import Defaults
import Scribe

/// Monitors `keyDown`, `keyUp`, and `flagsChanged` events using an ActiveEventMonitor, invoking Loop’s open and close callbacks as needed.
/// Additionally, this class manages keybind action retrieval and updates Loop based on those actions.
@Loggable
final class KeybindTrigger {
    // Parameters
    private let windowActionCache: WindowActionCache
    private let openCallback: (WindowAction) -> ()
    private let closeCallback: (Bool) -> ()
    private let checkIfLoopOpen: () -> Bool

    // State-tracking
    private var pressedKeys: Set<CGKeyCode> = []
    private var fnKeyState = FnKeyState()
    private(set) var effectiveEventFlags: CGEventFlags = []
    private var eventMonitor: ActiveEventMonitor?

    private var systemKeybindCache: Set<Set<CGKeyCode>> = []
    private var keybindCacheUpdatedAt: ContinuousClock.Instant?
    private let keybindCacheLifetime: ContinuousClock.Duration = .seconds(30)

    /// Special events only contain the globe key, as it can also be used as an emoji key.
    private let specialEventKeys: [CGKeyCode] = [.kVK_Globe_Emoji]

    /// Will be set to `false` if the mouse has been moved by LoopManager.
    var canPassthroughNextSpecialEvent = true

    private var useTriggerDelay: Bool { Defaults[.triggerDelay] > 0.1 }
    private var doubleClickToTrigger: Bool { Defaults[.doubleClickToTrigger] }
    private var sideDependentTriggerKey: Bool { Defaults[.sideDependentTriggerKey] }
    private lazy var triggerDelayTimer = TriggerDelayTimer(openCallback: openCallback)

    private lazy var doubleClickTimer = DoubleClickTimer { [weak self] action in
        guard let self else { return }

        if useTriggerDelay {
            startTriggerDelayTimer(
                startingAction: action,
                overrideExistingTriggerDelayTimerAction: true
            )
        } else {
            openCallback(action)
        }
    }

    /// Initializes a ``KeybindObserver``.
    /// - Parameters:
    ///   - openCallback: what to do when the trigger key is pressed, and Loop should be activated.
    ///   - closeCallback: what to do when the trigger key is released, and Loop should be closed.
    init(
        windowActionCache: WindowActionCache,
        openCallback: @escaping (WindowAction) -> (),
        closeCallback: @escaping (Bool) -> (),
        checkIfLoopOpen: @escaping () -> Bool
    ) {
        self.windowActionCache = windowActionCache
        self.openCallback = openCallback
        self.closeCallback = closeCallback
        self.checkIfLoopOpen = checkIfLoopOpen
    }

    func start() async {
        guard await AccessibilityManager.shared.isGranted else {
            return
        }

        stop()

        let eventMonitor = ActiveEventMonitor(
            "keybind_trigger",
            events: [.keyDown, .keyUp, .flagsChanged]
        ) { [weak self] event -> ActiveEventMonitor.EventHandling in
            guard let self else { return .forward }

            return handle(event)
        }

        eventMonitor.start()
        self.eventMonitor = eventMonitor
    }

    private func handle(_ event: CGEvent) -> ActiveEventMonitor.EventHandling {
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            .baseKey(flags: .init(rawValue: UInt(event.flags.rawValue)))

        fnKeyState.update(type: event.type, keyCode: keyCode, flags: event.flags)
        let filteredFlags = fnKeyState.filteredFlags(event.flags, keyCode: keyCode)

        let isLoopOpen = checkIfLoopOpen()
        effectiveEventFlags = filteredFlags

        if event.type == .keyUp {
            pressedKeys.remove(keyCode)
        } else if event.type == .keyDown {
            pressedKeys.insert(keyCode)
        }

        // Special events such as the emoji key
        if specialEventKeys.contains(keyCode) {
            let canPassthrough = canPassthroughNextSpecialEvent
            canPassthroughNextSpecialEvent = true // reset
            return canPassthrough ? .forward : .ignore
        }

        let eventType: KeybindResolver.EventType? = switch event.type {
        case .keyDown: .keyDown
        case .keyUp: .keyUp
        case .flagsChanged: .flagsChanged
        default: nil
        }
        guard let eventType else { return .forward }

        let result = performKeybind(
            type: eventType,
            isARepeat: event.getIntegerValueField(.keyboardEventAutorepeat) == 1,
            flags: filteredFlags,
            isLoopOpen: isLoopOpen
        )

        if result == .consume {
            log.debug("Blocked event")
            return .ignore
        }

        // If this shouldn't consume the event, and Loop isn't in the process of opening (possibly due to trigger delays),
        // check if it was a system keybind (ex. screenshot), and in that case, passthrough and force-close Loop
        refreshSystemKeybindCacheIfNeeded()
        if result != .opening, event.type == .keyDown, systemKeybindCache.contains(pressedKeys) {
            closeLoop(forceClose: true)
        }

        return .forward
    }

    func stop() {
        eventMonitor?.stop()
        eventMonitor = nil

        // Reset states
        pressedKeys = []
        effectiveEventFlags = []
        fnKeyState.reset()
        canPassthroughNextSpecialEvent = true
    }

    /// Determines if an event corresponds to a valid Loop action.
    /// - Parameters:
    ///   - type: the type of this event.
    ///   - isARepeat: whether this event is a repeat event.
    ///   - flags: modifier flags associated with this event.
    ///   - isLoopOpen: whether Loop is currently open.
    /// - Returns: whether this event was processed by Loop.
    private func performKeybind(
        type: KeybindResolver.EventType,
        isARepeat: Bool,
        flags: CGEventFlags,
        isLoopOpen: Bool
    ) -> KeybindResolver.ResolvedHandling {
        let decision = KeybindResolver.resolve(
            .init(
                eventType: type,
                isRepeat: isARepeat,
                pressedKeys: pressedKeys,
                modifierKeys: flags.keyCodes,
                trigger: .init(
                    keys: Defaults[.triggerKey],
                    isSideDependent: sideDependentTriggerKey
                ),
                isLoopOpen: isLoopOpen,
                actionsByKeybind: windowActionCache.actionsByKeybind,
                bypassedActionsByKeybind: windowActionCache.bypassedActionsByKeybind
            )
        )
        switch decision.effect {
        case .none:
            break
        case let .open(action, overrideExistingTriggerDelayAction):
            openLoop(
                startingAction: action,
                overrideExistingTriggerDelayTimerAction: overrideExistingTriggerDelayAction
            )
        case let .close(force, notifyDoubleClickKeyUp):
            if notifyDoubleClickKeyUp {
                doubleClickTimer.handleKeyUp()
            }
            closeLoop(forceClose: force)
        }

        return decision.handling.resolve(isLoopOpenAfterEffect: checkIfLoopOpen())
    }

    private func openLoop(
        startingAction: WindowAction,
        overrideExistingTriggerDelayTimerAction: Bool
    ) {
        if checkIfLoopOpen() {
            openCallback(startingAction) // Only update Loop to the latest WindowAction
        } else {
            if doubleClickToTrigger {
                doubleClickTimer.handleKeyDown(startingAction: startingAction)
            } else if useTriggerDelay {
                startTriggerDelayTimer(
                    startingAction: startingAction,
                    overrideExistingTriggerDelayTimerAction: overrideExistingTriggerDelayTimerAction
                )
            } else {
                openCallback(startingAction)
            }
        }
    }

    private func closeLoop(forceClose: Bool) {
        triggerDelayTimer.cancel()
        closeCallback(forceClose)
        pressedKeys = []
    }

    private func startTriggerDelayTimer(
        startingAction: WindowAction,
        overrideExistingTriggerDelayTimerAction: Bool
    ) {
        // If a trigger delay timer is already active, only update its startingAction when
        // overrideExistingTriggerDelayTimerAction is true. If it's false, keep the existing
        // timer and its startingAction (do not create a new timer with nil).
        if triggerDelayTimer.isActive {
            if overrideExistingTriggerDelayTimerAction {
                triggerDelayTimer.updateStartingAction(with: startingAction)
            }
        } else {
            // No active timer, create one with the provided startingAction.
            triggerDelayTimer.handleTrigger(startingAction: startingAction)
        }
    }

    private func refreshSystemKeybindCacheIfNeeded() {
        let shouldRefresh: Bool = if let keybindCacheUpdatedAt {
            keybindCacheUpdatedAt.duration(to: .now) > keybindCacheLifetime
        } else {
            true
        }

        guard shouldRefresh else {
            return
        }

        systemKeybindCache = CGKeyCode.systemKeybinds
        keybindCacheUpdatedAt = .now
    }
}
