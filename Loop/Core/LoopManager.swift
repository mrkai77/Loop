//
//  LoopManager.swift
//  Loop
//
//  Created by Kai Azim on 2023-08-15.
//

import Defaults
import os
import Scribe
import SwiftUI

@Loggable
@MainActor
final class LoopManager {
    static let shared = LoopManager()
    private init() {}

    /// Context for the current resize operation, tracking frame and edge adjustment state.
    /// Initialized when Loop opens with a target window and screen.
    private(set) var resizeContext: ResizeContext = .init()

    private let windowActionCache = WindowActionCache()
    private let indicatorService = WindowActionIndicatorService()
    private let updater = Updater.shared

    private var accessibilityCheckerTask: Task<(), Never>?
    private var gestureToggleTask: Task<(), Never>?

    /// Opening prepares resizeContext asynchronously. We track that setup separately
    /// so rapid trigger events cannot act on the previous/default context.
    private var isLoopOpening: Bool = false
    private var pendingOpeningAction: WindowAction?
    private var shouldCancelOpening: Bool = false
    private var hideIndicatorOnNoSelection = false
    private var actionRevision: UInt64 = 0

    private(set) var isLoopActive: Bool = false {
        didSet {
            let value = isLoopActive
            isLoopActiveMirror.withLock { $0 = value }
        }
    }

    private let isLoopActiveMirror = OSAllocatedUnfairLock<Bool>(initialState: false)
    nonisolated var isLoopActiveAtomic: Bool {
        isLoopActiveMirror.withLock { $0 }
    }

    private let hasParentCycleActionMirror = OSAllocatedUnfairLock<Bool>(initialState: false)
    nonisolated var hasParentCycleActionAtomic: Bool {
        hasParentCycleActionMirror.withLock { $0 }
    }

    private lazy var triggerKeyTimeoutTimer = TriggerKeyTimeoutTimer(
        closeCallback: { [weak self] forceClose in
            Task { await self?.closeLoop(forceClose: forceClose) }
        }
    )

    private(set) lazy var keybindTrigger = KeybindTrigger(
        windowActionCache: windowActionCache,
        openCallback: { [weak self] action in
            Task {
                try? await self?.openLoop(
                    startingAction: action,
                    hideIndicatorOnNoSelection: Defaults[.hideOnNoSelectionForKeybinds]
                )
            }
        },
        closeCallback: { [weak self] forceClose in
            Task {
                await self?.closeLoop(forceClose: forceClose)
            }
        },
        checkIfLoopOpen: { [weak self] in
            self?.isLoopActiveAtomic ?? false
        }
    )

    private(set) lazy var middleClickTrigger = MiddleClickTrigger(
        openCallback: { [weak self] action in
            Task {
                try? await self?.openLoop(
                    startingAction: action,
                    hideIndicatorOnNoSelection: Defaults[.hideOnNoSelectionForKeybinds]
                )
            }
        },
        closeCallback: { [weak self] forceClose in
            Task {
                await self?.closeLoop(forceClose: forceClose)
            }
        },
        checkIfLoopOpen: { [weak self] in self?.isLoopActiveAtomic ?? false }
    )

    private(set) lazy var multitouchTrigger = MultitouchTrigger(
        windowActionCache: windowActionCache,
        openCallback: { [weak self] action, window in
            guard let self else { return .cancelled }
            return try await openLoop(
                startingAction: action,
                window: window,
                hideIndicatorOnNoSelection: Defaults[.hideOnNoSelectionForGestures]
            )
        },
        closeCallback: { [weak self] forceClose in
            Task {
                await self?.closeLoop(forceClose: forceClose)
            }
        },
        changeAction: { [weak self] action, reverse in
            Task {
                await self?.changeAction(action, reverse: reverse)
            }
        },
        checkIfLoopOpen: { [weak self] in
            self?.isLoopActive ?? false
        }
    )

    private(set) lazy var mouseInteractionObserver = MouseInteractionObserver(
        windowActionCache: windowActionCache,
        changeAction: { [weak self] newAction in
            Task {
                // If the mouse moved, that means that the keybind trigger should no longer passthrough special events such as the emoji key.
                self?.keybindTrigger.canPassthroughNextSpecialEvent = false
                await self?.changeAction(newAction, canAdvanceCycle: false)
            }
        },
        advanceSelectedAction: { [weak self] selectedAction in
            Task {
                guard let self else { return }

                if let selectedAction, selectedAction.id != self.resizeContext.action.id {
                    return
                }

                if let selectedAction {
                    await self.changeAction(
                        selectedAction,
                        disableHapticFeedback: true,
                        canAdvanceCycle: false
                    )
                } else if let parent = self.resizeContext.parentAction {
                    await self.changeAction(
                        parent,
                        disableHapticFeedback: true,
                        canAdvanceCycle: true
                    )
                }
            }
        },
        canSelectNextCycleitem: { [weak self] in
            self?.hasParentCycleActionAtomic ?? false
        },
        checkIfLoopOpen: { [weak self] in self?.isLoopActiveAtomic ?? false }
    )

    func start() {
        if !Defaults[.enableGestures] || !AccessibilityManager.shared.isGranted {
            SystemGestureManager.reconcile(
                enableGestures: false,
                disableConflicts: Defaults[.disableConflictingSystemGestures],
                gestures: Defaults[.gestures]
            )
        }

        accessibilityCheckerTask = Task(priority: .background) { [weak self] in
            for await status in AccessibilityManager.shared.stream(initial: true) {
                guard let self, !Task.isCancelled else {
                    return
                }

                if status {
                    await keybindTrigger.start()
                    middleClickTrigger.start()
                    if Defaults[.enableGestures] {
                        multitouchTrigger.start()
                    }
                } else {
                    keybindTrigger.stop()
                    middleClickTrigger.stop()
                    multitouchTrigger.stop()
                }
            }
        }

        gestureToggleTask = Task(priority: .background) { [weak self] in
            for await enabled in Defaults.updates(.enableGestures, initial: false) {
                guard let self, !Task.isCancelled else { break }

                if enabled, AccessibilityManager.shared.isGranted {
                    multitouchTrigger.start()
                } else {
                    multitouchTrigger.stop()
                }
            }
        }
    }

    func shutdown() {
        actionRevision += 1

        accessibilityCheckerTask?.cancel()
        accessibilityCheckerTask = nil
        gestureToggleTask?.cancel()
        gestureToggleTask = nil

        indicatorService.closeAll()

        keybindTrigger.stop()
        middleClickTrigger.stop()
        mouseInteractionObserver.stop()
        multitouchTrigger.shutdown()
        triggerKeyTimeoutTimer.cancel()

        isLoopOpening = false
        pendingOpeningAction = nil
        shouldCancelOpening = false
        isLoopActive = false
        hasParentCycleActionMirror.withLock { $0 = false }
    }
}

enum LoopManagerError: LocalizedError {
    case accessibilityNotGranted
    case appExcluded
    case fullscreenWindow

    var errorDescription: String? {
        switch self {
        case .accessibilityNotGranted:
            "Cannot open Loop: accessibility permission not granted"
        case .appExcluded:
            "Cannot open Loop: app is excluded"
        case .fullscreenWindow:
            "Cannot open Loop: target window is fullscreen"
        }
    }
}

enum LoopOpenResult {
    case opened
    case alreadyOpening
    case alreadyOpen
    case cancelled
}

// MARK: - Opening/Closing Loop

extension LoopManager {
    private func openLoop(
        startingAction: WindowAction,
        window: Window? = nil,
        hideIndicatorOnNoSelection: Bool
    ) async throws -> LoopOpenResult {
        guard AccessibilityManager.shared.isGranted else {
            throw LoopManagerError.accessibilityNotGranted
        }

        guard !isLoopOpening else {
            if startingAction.direction != .noSelection {
                pendingOpeningAction = startingAction
            }
            return .alreadyOpening
        }

        guard !isLoopActive else {
            // If using Karabiner-Elements, TriggerKeybindObserver may call openLoop twice, as key events arrive in quick succession.
            // This happens because Karabiner-Elements sends modifier keys and other keys as separate, rapid events.
            // As a result, Loop might be opened before the full keybind is pressed.
            // In these cases, we can simply update the action instead of reopening the Loop.
            if startingAction.direction != .noSelection { // Can switch to .noAction still!
                await changeAction(startingAction, disableHapticFeedback: true)
            }

            return .alreadyOpen
        }

        let window = window ?? WindowUtility.userDefinedTargetWindow()

        guard window?.isAppExcluded != true else {
            throw LoopManagerError.appExcluded
        }

        guard (window?.fullscreen ?? false && Defaults[.ignoreFullscreen]) == false else {
            throw LoopManagerError.fullscreenWindow
        }

        actionRevision += 1
        isLoopOpening = true
        self.hideIndicatorOnNoSelection = hideIndicatorOnNoSelection
        pendingOpeningAction = nil
        shouldCancelOpening = false
        hasParentCycleActionMirror.withLock { $0 = false }

        defer {
            isLoopOpening = false
            pendingOpeningAction = nil
            shouldCancelOpening = false
        }

        log.info("Opening Loop with starting action: \(startingAction.description) and target window: \(window?.description ?? "(none)")")

        // Refresh accent colors in case user has enabled the wallpaper processor
        Task {
            await AccentColorController.shared.refresh()
        }

        let initialFrame: CGRect = if let window {
            // In case of a stashed window, use the revealed frame instead to prevent issue with frame calculation later.
            await StashManager.shared.getRevealedFrameForStashedWindow(
                id: window.cgWindowID
            ) ?? window.frame
        } else {
            .zero
        }

        resizeContext = ResizeContext(
            window: window,
            initialFrame: initialFrame,
            initialMousePosition: NSEvent.mouseLocation
        )
        await resizeContext.refreshResolvedState()

        guard !shouldCancelOpening else {
            return .cancelled
        }

        if !Defaults[.disableCursorInteraction] {
            mouseInteractionObserver.start(initialMousePosition: resizeContext.initialMousePosition)
        }

        isLoopActive = true
        indicatorService.openAndUpdate(context: resizeContext, hideOnNoSelection: hideIndicatorOnNoSelection)

        await changeAction(pendingOpeningAction ?? startingAction, disableHapticFeedback: true)

        triggerKeyTimeoutTimer.start()
        return .opened
    }

    private func closeLoop(forceClose: Bool) async {
        if forceClose {
            actionRevision += 1
        }

        if isLoopOpening {
            shouldCancelOpening = true
        }

        guard isLoopActive == true else { return }
        log.info("Closing Loop (force closed: \(forceClose))")

        indicatorService.closeAll()
        isLoopActive = false
        hasParentCycleActionMirror.withLock { $0 = false }

        triggerKeyTimeoutTimer.cancel()
        mouseInteractionObserver.stop()

        // Handle normal actions with a target window
        if !forceClose {
            // If the preview was disabled, the window will already be in the specified action's frame.
            // So only resize the window if the preview is enabled.
            if Defaults[.previewVisibility],
               !resizeContext.action.direction.willFocusWindow {
                Task {
                    _ = try? await WindowActionEngine.shared.apply(context: resizeContext)
                }
            }

            // Icon stuff
            Defaults[.timesLooped] += 1
            IconManager.checkIfUnlockedNewIcon()
        }

        Task {
            if updater.shouldAutoPresentUpdateWindow {
                await updater.showUpdateWindowIfEligible()
            }
        }
    }
}

// MARK: - Changing Actions

extension LoopManager {
    /// Changes the action to the provided one, or the next cycle action if available.
    /// - Parameters:
    ///   - newAction: The action to change to. If a cycle is provided, Loop will use the current action as context to choose an appropriate next action.
    ///   - triggeredFromScreenChange: If this action was triggered from a screen change, this will prevent cycle keybinds from infinitely changing screens.
    ///   - disableHapticFeedback: This will prevent haptic feedback.
    ///   - canAdvanceCycle: This will prevent the cycle from advancing if set to false. This is currently used when changing actions via the radial menu.
    private func changeAction(
        _ newAction: WindowAction,
        triggeredFromScreenChange: Bool = false,
        disableHapticFeedback: Bool = false,
        canAdvanceCycle: Bool = true,
        reverse: Bool = false
    ) async {
        let originatingContext = resizeContext

        guard
            isLoopActive,
            let currentScreen = originatingContext.screen ?? resolveAndStoreTargetScreen(
                action: newAction,
                window: originatingContext.window
            )
        else {
            return
        }

        let incomingAllowsRepeatedSelection = newAction.allowsRepeatedSelection

        guard originatingContext.action.id != newAction.id || incomingAllowsRepeatedSelection else {
            return
        }

        actionRevision += 1
        let originatingRevision = actionRevision

        var newAction: WindowAction = newAction
        var newParentAction: WindowAction? = nil
        var cycleProposal: CycleActionCoordinator.Proposal?

        triggerKeyTimeoutTimer.cancel()
        triggerKeyTimeoutTimer.start()

        if newAction.direction == .cycle {
            newParentAction = newAction
            cycleProposal = proposeCycleAction(
                newAction,
                canAdvance: canAdvanceCycle,
                reverse: reverse
            )
            if let cycleProposal {
                newAction = cycleProposal.action
            } else if !canAdvanceCycle {
                newAction = .init(.noAction)
            }

            // Prevents an endless loop of cycling screens. example: when a cycle only consists of:
            // 1. next screen
            // 2. previous screen
            if triggeredFromScreenChange, newAction.direction.willChangeScreen {
                performHapticFeedback()
                return
            }

            // Commit before the screen or target changes, even if the child is already current
            if let cycleProposal, let newParentAction {
                guard let committedAction = resizeContext.commitCycleAction(
                    cycleProposal,
                    in: newParentAction
                ) else {
                    return
                }

                newAction = committedAction
            }

            if cycleProposal != nil,
               newAction == resizeContext.action,
               !canAdvanceCycle || (
                   !newAction.direction.willChangeScreen &&
                       !newAction.allowsRepeatedSelection
               ),
               let newParentAction {
                if resizeContext.parentAction != newParentAction {
                    setResizeAction(to: resizeContext.action, parent: newParentAction)
                }
                return
            }
        } else {
            // By removing the parent cycle action, a left click will not advance the user's previously set cycle.
            newParentAction = nil
        }

        if let stashedWindow = StashManager.shared.stashedWindow(for: newAction, on: currentScreen) {
            let preparedTarget = await ResizeContext.prepareWindowTarget(stashedWindow.window)

            guard resizeContext === originatingContext,
                  actionRevision == originatingRevision
            else {
                return
            }

            originatingContext.commitWindowTarget(preparedTarget)
        }

        if newAction.direction.willChangeScreen {
            var newScreen: NSScreen = currentScreen

            if newAction.direction == .nextScreen,
               let nextScreen = ScreenUtility.nextScreen(from: currentScreen) {
                newScreen = nextScreen
            }

            if newAction.direction == .previousScreen,
               let previousScreen = ScreenUtility.previousScreen(from: currentScreen) {
                newScreen = previousScreen
            }

            if newAction.direction == .leftScreen,
               let leftScreen = ScreenUtility.directionalScreen(from: currentScreen, direction: .left) {
                newScreen = leftScreen
            }

            if newAction.direction == .rightScreen,
               let rightScreen = ScreenUtility.directionalScreen(from: currentScreen, direction: .right) {
                newScreen = rightScreen
            }

            if newAction.direction == .topScreen,
               let topScreen = ScreenUtility.directionalScreen(from: currentScreen, direction: .top) {
                newScreen = topScreen
            }

            if newAction.direction == .bottomScreen,
               let bottomScreen = ScreenUtility.directionalScreen(from: currentScreen, direction: .bottom) {
                newScreen = bottomScreen
            }

            // If the current action is either `.noAction`/`.noSelection`, or `.smaller`/`.larger` etc,
            // then we will preserve the window's proportional frame relative to the current screen on the new screen.
            if resizeContext.action.direction.isNoOp || resizeContext.action.willManipulateExistingWindowFrame {
                if let targetWindow = resizeContext.window {
                    let screenSwitchingCustomActionName = "autogenerated_screen_switching_action"

                    if let lastAction = await WindowRecords.shared.getCurrentAction(for: targetWindow),
                       lastAction.getName() != screenSwitchingCustomActionName,
                       !lastAction.forceProportionalFrameOnScreenChange {
                        setResizeAction(to: lastAction, parent: nil)
                    } else {
                        let currentFrame = targetWindow.frame

                        let adjustedBounds = PaddingConfiguration
                            .getConfiguredPadding(for: currentScreen)
                            .applyToBounds(currentScreen.cgSafeScreenFrame, screen: currentScreen)

                        let proportionalSize = CGRect(
                            x: (currentFrame.minX - adjustedBounds.minX) / adjustedBounds.width,
                            y: (currentFrame.minY - adjustedBounds.minY) / adjustedBounds.height,
                            width: currentFrame.width / adjustedBounds.width,
                            height: currentFrame.height / adjustedBounds.height
                        )

                        setResizeAction(
                            to: .init(
                                .custom,
                                keybind: [],
                                name: screenSwitchingCustomActionName,
                                unit: .percentage,
                                width: proportionalSize.width * 100,
                                height: proportionalSize.height * 100,
                                xPoint: proportionalSize.minX * 100,
                                yPoint: proportionalSize.minY * 100,
                                positionMode: .coordinates,
                                sizeMode: .custom
                            ),
                            parent: nil
                        )
                    }
                } else {
                    setResizeAction(to: .init(.center), parent: nil)
                }
            }

            resizeContext.setScreen(to: newScreen)
            indicatorService.openAndUpdate(context: resizeContext, hideOnNoSelection: hideIndicatorOnNoSelection)

            if let parent = newParentAction {
                setResizeAction(to: newAction, parent: newParentAction)
                await changeAction(parent, triggeredFromScreenChange: true)
            } else {
                if !Defaults[.previewVisibility] {
                    if !disableHapticFeedback {
                        performHapticFeedback()
                    }

                    Task {
                        _ = try await WindowActionEngine.shared.apply(context: resizeContext)
                    }
                }
            }

            log.info("Screen changed: \(newScreen.localizedName)")

            return
        }

        if newAction != resizeContext.action || newAction.allowsRepeatedSelection {
            if !disableHapticFeedback {
                performHapticFeedback()
            }

            let previousActionWasNoOp = resizeContext.action.direction.isNoOp
            setResizeAction(to: newAction, parent: newParentAction)
            if !Defaults[.previewVisibility], !previousActionWasNoOp {
                await resizeContext.refreshResolvedState()
            }
            indicatorService.openAndUpdate(context: resizeContext, hideOnNoSelection: hideIndicatorOnNoSelection)

            Task { [weak self, originatingContext] in
                // If the action is to focus a window in a specific direction, find and activate that window
                // This can work even without a current window (navigates from screen center)
                if newAction.direction.willFocusWindow {
                    if let newTargetWindow = await WindowActionEngine.shared.resolveFocusTarget(
                        newAction,
                        currentWindow: originatingContext.window
                    ) {
                        let preparedTarget = await ResizeContext.prepareWindowTarget(newTargetWindow)

                        guard let self,
                              resizeContext === originatingContext,
                              actionRevision == originatingRevision
                        else {
                            return
                        }

                        originatingContext.commitWindowTarget(preparedTarget)
                        log.info("Focusing window: \(newTargetWindow.description)")
                        newTargetWindow.focus()
                    }
                } else if !Defaults[.previewVisibility] {
                    _ = try? await WindowActionEngine.shared.apply(context: originatingContext)
                }
            }

            log.info("Window action changed: \(newAction.description)")
        }
    }

    private func proposeCycleAction(
        _ action: WindowAction,
        canAdvance: Bool,
        reverse: Bool
    ) -> CycleActionCoordinator.Proposal? {
        // Allow cycling backwards only if:
        // - Shift is not part of the action's keybind (eligibleForReverseCycle)
        // - Shift is not part of the trigger key
        // - The user has enabled the setting
        let allowReverseCycle = action.eligibleForReverseCycle
            && Defaults[.triggerKey].contains(.kVK_Shift) == false
            && Defaults[.cycleBackwardsOnShiftPressed]

        let mode: CycleActionCoordinator.SelectionMode = if canAdvance {
            reverse || (allowReverseCycle && keybindTrigger.effectiveEventFlags.contains(.maskShift))
                ? .advance(.backward)
                : .advance(.forward)
        } else {
            .selectCurrent
        }

        return resizeContext.proposeCycleAction(
            in: action,
            restartAtBeginningWhenInterrupted: Defaults[.cycleModeRestartEnabled],
            mode: mode
        )
    }

    private func performHapticFeedback() {
        if Defaults[.hapticFeedback] {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }

    private func setResizeAction(to newAction: WindowAction, parent newParentAction: WindowAction?) {
        resizeContext.setAction(to: newAction, parent: newParentAction)
        hasParentCycleActionMirror.withLock { $0 = newParentAction != nil }
    }

    /// Resolves the target screen for `screenToResizeOn`.
    ///
    /// By default, this uses the user's `useScreenWithCursor` setting.
    /// For actions that move windows between screens, the screen containing the window is preferred to ensure deterministic behavior.
    /// - Parameters:
    ///   - action: The window action being performed.
    ///   - window: The window to be resized, if any.
    /// - Returns: The screen the window should be on after the action.
    private func resolveAndStoreTargetScreen(action: WindowAction, window: Window?) -> NSScreen? {
        var targetScreen = Defaults[.useScreenWithCursor] ? NSScreen.screenWithMouse : NSScreen.main

        if action.direction.willChangeScreen,
           let window,
           let screen = ScreenUtility.screenContaining(window) {
            targetScreen = screen
        }

        resizeContext.setScreen(to: targetScreen)

        if !resizeContext.action.direction.isNoOp {
            // If a screen was previously not selected, then the preview needs to be opened.
            indicatorService.openAndUpdate(context: resizeContext, hideOnNoSelection: hideIndicatorOnNoSelection)
        }

        return targetScreen
    }
}
