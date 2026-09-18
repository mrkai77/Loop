//
//  MultitouchTrigger.swift
//  Loop
//
//  Created by Kai Azim on 2026-01-30.
//

import Defaults
import Scribe
import Subsurface
import SwiftUI

@Loggable
@MainActor
final class MultitouchTrigger {
    private let windowActionCache: WindowActionCache
    private let openCallback: (WindowAction, Window) async throws -> LoopOpenResult
    private let closeCallback: (Bool) -> ()
    private let changeAction: (WindowAction, Bool) -> ()
    private let checkIfLoopOpen: () -> Bool

    private let gestureMonitor = SubsurfaceMonitor()
    private let gestureBlocker: MultitouchGestureBlocker = .init()
    lazy var recognizerRegistry = MultitouchRecognizerRegistry(
        gestureMonitor: gestureMonitor
    ) { [weak self] event, fingerCount in
        guard let self else { return }
        await handleGestureEvent(event, fingerCount: fingerCount)
    }

    let targetResolver = MultitouchTargetResolver()

    private var gesturesObservationTask: Task<(), Never>?
    private var radialMenuActionsObservationTask: Task<(), Never>?
    private var systemGestureReconciliationTask: Task<(), Never>?
    private var isStarted = false

    let swipeCycleStepSize: CGFloat = 0.15
    let magnifyStepSize: CGFloat = 0.2
    let cardinalBiasedRadialMenuActionCount = 8

    var radialMenuActions = RadialMenuAction.userConfiguredActions

    private static let failedToResolveKeybindAction: WindowAction = .init(.noAction)

    init(
        windowActionCache: WindowActionCache,
        openCallback: @escaping (WindowAction, Window) async throws -> LoopOpenResult,
        closeCallback: @escaping (Bool) -> (),
        changeAction: @escaping (WindowAction, Bool) -> (),
        checkIfLoopOpen: @escaping () -> Bool
    ) {
        self.windowActionCache = windowActionCache
        self.openCallback = openCallback
        self.closeCallback = closeCallback
        self.changeAction = changeAction
        self.checkIfLoopOpen = checkIfLoopOpen

        startSystemGestureReconciliation()
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true

        startSystemGestureReconciliation()
        reconcileSystemGestures()
        rebuildRecognizers()
        radialMenuActions = RadialMenuAction.userConfiguredActions

        gesturesObservationTask = Task { [weak self] in
            // Watch keybinds too, so gestures referencing a deleted keybind stay in sync.
            for await _ in Defaults.updates(.gestures, .keybinds, initial: false) {
                guard !Task.isCancelled, let self else { break }
                rebuildRecognizers()
            }
        }

        radialMenuActionsObservationTask = Task { [weak self] in
            for await _ in Defaults.updates(.enableRadialMenuCustomization, .radialMenuActions, initial: false) {
                guard !Task.isCancelled, let self else { break }
                radialMenuActions = RadialMenuAction.userConfiguredActions
            }
        }
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false

        reconcileSystemGestures()
        gesturesObservationTask?.cancel()
        gesturesObservationTask = nil
        radialMenuActionsObservationTask?.cancel()
        radialMenuActionsObservationTask = nil

        gestureMonitor.stop()
        handleStopResults(recognizerRegistry.stopAll())
        targetResolver.reset()
    }

    func shutdown() {
        stop()
        systemGestureReconciliationTask?.cancel()
        systemGestureReconciliationTask = nil
        SystemGestureManager.restore()
    }

    private func startSystemGestureReconciliation() {
        guard systemGestureReconciliationTask == nil else { return }

        systemGestureReconciliationTask = Task(priority: .background) { [weak self] in
            let updates = Defaults.updates(
                .enableGestures,
                .disableConflictingSystemGestures,
                .gestures
            )

            for await _ in updates {
                guard !Task.isCancelled, let self else { break }
                reconcileSystemGestures()
            }
        }
    }

    private func reconcileSystemGestures() {
        SystemGestureManager.reconcile(
            enableGestures: isStarted && Defaults[.enableGestures],
            disableConflicts: Defaults[.disableConflictingSystemGestures],
            gestures: Defaults[.gestures]
        )
    }

    private func rebuildRecognizers() {
        handleStopResults(recognizerRegistry.rebuild(with: Defaults[.gestures]))
        if recognizerRegistry.hasRecognizers {
            gestureMonitor.start()
        } else {
            gestureMonitor.stop()
        }
    }

    private func handleStopResults(_ stopResults: [MultitouchRecognizerRegistry.StopResult]) {
        for stopResult in stopResults {
            if stopResult.didOpenLoopWithGesture {
                closeCallback(false)
            }
            if stopResult.didAcquireGestureBlocker {
                gestureBlocker.stop()
            }
        }
    }

    private func handleGestureEvent(_ event: SubsurfaceGestureEvent, fingerCount: Int) async {
        switch event {
        case let .swipe(swipe):
            await handleSwipe(swipe, fingerCount: fingerCount)
        case let .magnify(magnify):
            await handleMagnify(magnify, fingerCount: fingerCount)
        case .determining:
            await handleEarlyRadialMenuGesture(phase: .determining, fingerCount: fingerCount)
        case .unresolvedEnded:
            await handleEarlyRadialMenuGesture(phase: event.phase, fingerCount: fingerCount)
        case let .rotation(rotation):
            await handleEarlyRadialMenuGesture(phase: rotation.phase, fingerCount: fingerCount)
        }
    }

    /// Begins a gesture session by resolving its target window and blocking trackpad events.
    /// Radial-menu sessions begin during `.determining`; directional swipe and magnify sessions
    /// begin after Subsurface recognizes the gesture. Opening Loop may still be gated separately.
    @discardableResult
    func handleGestureBegan(fingerCount: Int, gesture: GestureBinding) -> Bool {
        let allowsRapidRepeat = resolvedWindowAction(from: gesture)?.allowsRapidRepeat == true
        let activationContext = targetResolver.activationContext(
            for: gesture,
            allowsRapidRepeat: allowsRapidRepeat
        )

        let loopWasAlreadyOpen = checkIfLoopOpen()

        guard let session = recognizerRegistry.session(for: fingerCount) else { return false }
        releaseGestureBlocker(for: session)
        guard session.begin(
            activationContext: activationContext,
            gesture: gesture,
            loopWasAlreadyOpen: loopWasAlreadyOpen
        ) else {
            return false
        }

        targetResolver.rememberRepeatableWindow(
            activationContext.targetWindow,
            allowsRapidRepeat: allowsRapidRepeat
        )

        gestureBlocker.start()
        session.acquireGestureBlocker()
        return true
    }

    private func handleEarlyRadialMenuGesture(
        phase: SubsurfaceGesturePhase,
        fingerCount: Int
    ) async {
        // Radial-menu gestures intentionally activate while Subsurface is still determining
        // the gesture. The presentation policy decides whether the no-selection state is visible.
        guard let gesture = recognizerRegistry.entry(for: fingerCount)?.radialMenuGesture else { return }

        switch phase {
        case .determining, .began, .changed:
            guard let session = recognizerRegistry.session(for: fingerCount),
                  !session.isGestureRejected
            else {
                return
            }

            if !session.hasGestureBegun {
                guard handleGestureBegan(fingerCount: fingerCount, gesture: gesture) else {
                    return
                }
            }
            _ = await activateGestureIfNeeded(fingerCount: fingerCount)

        case .ended(_), .cancelled:
            resetLoopState(for: fingerCount)

        default:
            break
        }
    }

    /// Opens Loop on the target window captured when the gesture session began. Radial-menu
    /// gestures call this during `.determining`, though the no-selection state may remain hidden;
    /// directional swipes activate on `.began`, while magnify gestures gate on displacement.
    func activateGestureIfNeeded(fingerCount: Int) async -> Bool {
        guard let session = recognizerRegistry.session(for: fingerCount), !session.isGestureRejected else { return false }

        if session.hasActivated { return true }

        var openedLoop = false
        if let window = session.pendingTargetWindow {
            do {
                let result = try await openCallback(.init(.noSelection), window)
                openedLoop = result == .opened
            } catch {
                if recognizerRegistry.contains(session: session, for: fingerCount) {
                    session.reject()
                    releaseGestureBlocker(for: session)
                }
                return false
            }
        }

        guard recognizerRegistry.contains(session: session, for: fingerCount) else {
            if openedLoop {
                closeCallback(true)
            }
            return false
        }
        session.markActivated(openedLoop: openedLoop)
        return true
    }

    func resetLoopState(for fingerCount: Int, forceClose: Bool = false) {
        guard let session = recognizerRegistry.session(for: fingerCount) else {
            return
        }

        if session.didOpenLoopWithThisGesture {
            closeCallback(forceClose)
        }

        releaseGestureBlocker(for: session)
        session.reset()
    }

    private func releaseGestureBlocker(for session: MultitouchGestureSession) {
        if session.releaseGestureBlocker() {
            gestureBlocker.stop()
        }
    }
}

// MARK: - Actions

extension MultitouchTrigger {
    func isCycleAction(_ gesture: GestureBinding) -> Bool {
        resolvedWindowAction(from: gesture)?.direction == .cycle
    }

    func triggerRadialMenuAction(at index: Int, from actions: ArraySlice<RadialMenuAction>, reverse: Bool = false) {
        guard actions.indices.contains(index) else { return }
        let action = actions[index]

        let resolvedAction: WindowAction = switch action.type {
        case let .custom(windowAction):
            windowAction
        case let .keybindReference(id):
            resolveKeybindReference(id)
        }

        changeAction(resolvedAction, reverse)
    }

    func resolvedWindowAction(from gesture: GestureBinding) -> WindowAction? {
        guard case let .singleAction(actionType) = gesture.action else { return nil }
        switch actionType {
        case let .custom(action): return action
        case let .keybindReference(id): return resolveKeybindReference(id)
        }
    }

    func triggerSingleAction(from gesture: GestureBinding, reverse: Bool = false) {
        guard let resolvedAction = resolvedWindowAction(from: gesture) else { return }
        changeAction(resolvedAction, reverse)
    }

    private func resolveKeybindReference(_ id: UUID) -> WindowAction {
        if let cached = windowActionCache.actionsByIdentifier[id] {
            return cached
        }
        log.warn("Gesture references keybind \(id) that no longer exists")
        return Self.failedToResolveKeybindAction
    }
}
