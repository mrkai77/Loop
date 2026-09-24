//
//  MultitouchTrigger.swift
//  Loop
//
//  Created by Kai Azim on 2026-01-30.
//

import AppKit
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
    private let changeActionCallback: (WindowAction, _ reverse: Bool, _ canAdvanceCycle: Bool) -> ()
    private let checkIfLoopOpen: () -> Bool

    private let gestureMonitor = SubsurfaceMonitor()
    private let gestureBlocker: MultitouchGestureBlocker = .init()
    private(set) lazy var systemGestureFilter = SystemGestureFilter(
        gestureMonitor: gestureMonitor,
        isCursorInTitlebar: { [weak self] touchID in self?.targetResolver.isCursorInTitlebar(touchID: touchID) ?? false }
    )

    #if DEBUG
        let debugOverlayController = GestureDebugOverlayController()
        private var debugContactsTask: Task<(), Never>?
    #endif
    lazy var recognizerRegistry = MultitouchRecognizerRegistry(
        gestureMonitor: gestureMonitor
    ) { [weak self] event, fingerCount in
        guard let self else { return }
        await handleGestureEvent(event, fingerCount: fingerCount)
    }

    let targetResolver = MultitouchTargetResolver()

    private var gesturesObservationTask: Task<(), Never>?
    private var radialMenuActionsObservationTask: Task<(), Never>?
    private var isStarted = false

    let swipeCycleStepSize: CGFloat = 0.15
    let magnifyStepSize: CGFloat = 0.2

    var radialMenuActions = RadialMenuAction.userConfiguredActions

    private static let failedToResolveKeybindAction: WindowAction = .init(.noAction)

    init(
        windowActionCache: WindowActionCache,
        openCallback: @escaping (WindowAction, Window) async throws -> LoopOpenResult,
        closeCallback: @escaping (Bool) -> (),
        changeAction: @escaping (WindowAction, _ reverse: Bool, _ canAdvanceCycle: Bool) -> (),
        checkIfLoopOpen: @escaping () -> Bool
    ) {
        self.windowActionCache = windowActionCache
        self.openCallback = openCallback
        self.closeCallback = closeCallback
        self.changeActionCallback = changeAction
        self.checkIfLoopOpen = checkIfLoopOpen
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true

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

        gesturesObservationTask?.cancel()
        gesturesObservationTask = nil
        radialMenuActionsObservationTask?.cancel()
        radialMenuActionsObservationTask = nil

        systemGestureFilter.stop()
        gestureMonitor.stop()
        #if DEBUG
            closeDebugOverlay(force: true)
        #endif
        handleStopResults(recognizerRegistry.stopAll())
        targetResolver.reset()
    }

    func shutdown() {
        stop()
    }

    private func updateSystemGestureFilter() {
        guard isStarted, recognizerRegistry.hasRecognizers else {
            systemGestureFilter.stop()
            return
        }

        systemGestureFilter.start(claiming: SystemGestureFilter.claims(for: Defaults[.gestures]))
    }

    private func rebuildRecognizers() {
        #if DEBUG
            closeDebugOverlay(force: true)
        #endif
        handleStopResults(recognizerRegistry.rebuild(with: Defaults[.gestures]))
        if recognizerRegistry.hasRecognizers {
            gestureMonitor.start()
        } else {
            gestureMonitor.stop()
        }
        updateSystemGestureFilter()
    }

    private func handleStopResults(_ stopResults: [MultitouchRecognizerRegistry.StopResult]) {
        #if DEBUG
            if !stopResults.isEmpty {
                closeDebugOverlay(force: true)
            }
        #endif
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
        #if DEBUG
            updateDebugOverlay(for: event)
        #endif

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
    @discardableResult
    func handleGestureBegan(fingerCount: Int, gesture: GestureBinding) -> Bool {
        guard let session = recognizerRegistry.session(for: fingerCount),
              session.shouldAttemptBegin(with: gesture)
        else {
            return false
        }

        let allowsRapidRepeat = resolvedWindowAction(from: gesture)?.allowsRapidRepeat == true
        let activationContext = targetResolver.activationContext(
            for: gesture,
            touchID: systemGestureFilter.currentTouchID,
            allowsRapidRepeat: allowsRapidRepeat
        )

        let loopWasAlreadyOpen = checkIfLoopOpen()

        releaseGestureBlocker(for: session)

        guard systemGestureFilter.canClaimCurrentTouch(fingerCount: fingerCount) else {
            session.abandonStroke()
            return false
        }

        guard session.begin(
            activationContext: activationContext,
            gesture: gesture,
            loopWasAlreadyOpen: loopWasAlreadyOpen
        ) else {
            systemGestureFilter.releaseCurrentTouch(fingerCount: fingerCount)
            // Keep the DEBUG overlay alive, as it follows the physical stroke
            return false
        }

        // Claimed only once accepted, so the filter never sees Loop own a stroke it's about to reject
        guard systemGestureFilter.claimCurrentTouch(fingerCount: fingerCount) else {
            session.reject()
            return false
        }

        session.setSwipeActivationDistance(
            recognizerRegistry.entry(for: fingerCount)?.recognizer.minimumSwipeTranslation
        )

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

        case let .ended(reason):
            endStroke(for: fingerCount, reason: reason)

        case .cancelled:
            endStroke(for: fingerCount, reason: nil)

        default:
            break
        }
    }

    #if DEBUG
        /// Swipe and magnify updates are handled in their own handlers, after
        /// their recognizer entry is resolved.
        private func updateDebugOverlay(for event: SubsurfaceGestureEvent) {
            guard GestureDebugOverlayController.isEnabled else { return }

            switch event {
            case let .determining(centroid, fingerCount):
                // The overlay visualizes the physical stroke, even when activation
                // policy rejects its configured action (for example, a titlebar-only
                // gesture that began elsewhere).
                beginDebugGestureIfNeeded(centroid: centroid, fingerCount: fingerCount)
                debugOverlayController.updateDetermining(centroid: centroid, fingerCount: fingerCount)
            case let .unresolvedEnded(reason):
                let shouldForceClose = switch reason {
                case .lifted, .timedOut, .cancelled:
                    true
                case .fingerCountChanged:
                    false
                }
                closeDebugOverlay(force: shouldForceClose)
            case let .rotation(rotation):
                switch rotation.phase {
                case .ended(_), .cancelled:
                    closeDebugOverlay(force: true)
                default:
                    break
                }
            case .swipe, .magnify:
                break
            }
        }

        func beginDebugGestureIfNeeded(centroid: CGPoint, fingerCount: Int) {
            guard GestureDebugOverlayController.isEnabled,
                  let entry = recognizerRegistry.entry(for: fingerCount),
                  entry.radialMenuGesture != nil ||
                  !entry.directionalGestures.isEmpty ||
                  entry.magnifyOutGesture != nil ||
                  entry.magnifyInGesture != nil,
                  !debugOverlayController.model.snapshot.visible
            else {
                return
            }

            let threshold = entry.recognizer.minimumSwipeTranslation
            let center: CGPoint = if Defaults[.lockRadialMenuToCenter], let screen = NSScreen.main {
                CGPoint(x: screen.frame.midX, y: screen.frame.midY)
            } else {
                NSEvent.mouseLocation
            }
            let actionCount: Int = if entry.radialMenuGesture != nil {
                max(radialMenuActions.count - 1, 0)
            } else if !entry.directionalGestures.isEmpty {
                // Directional swipes always occupy the four cardinal quadrants,
                // even when only a subset of those directions has an action.
                4
            } else {
                0
            }
            debugOverlayController.begin(
                originCentroid: centroid,
                fingerCount: fingerCount,
                recognitionThreshold: threshold,
                actionCount: actionCount,
                swipeStep: swipeCycleStepSize,
                magnifyStep: magnifyStepSize,
                screenCenter: center
            )
            startDebugContactsIfNeeded()
        }

        private func startDebugContactsIfNeeded() {
            guard debugContactsTask == nil else { return }
            debugContactsTask = Task { [weak self] in
                guard let self else { return }
                for await (_, contacts) in gestureMonitor.contacts() {
                    guard !Task.isCancelled else { break }
                    debugOverlayController.updateRawContacts(contacts)
                }
            }
        }

        private func closeDebugOverlay(force: Bool = false) {
            debugOverlayController.close(force: force)
            guard !debugOverlayController.model.snapshot.visible else { return }
            debugContactsTask?.cancel()
            debugContactsTask = nil
        }
    #endif

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
                    systemGestureFilter.releaseCurrentTouch(fingerCount: fingerCount)
                }
                #if DEBUG
                    closeDebugOverlay(force: true)
                #endif
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

    /// An added finger starts a different gesture, so it force-closes Loop
    func endStroke(for fingerCount: Int, reason: SubsurfaceGestureEvent.GestureEndReason?) {
        resetLoopState(for: fingerCount, forceClose: reason == .fingerCountChanged(.increased))
    }

    /// - Parameter endsStroke: false when Loop abandons a stroke still in progress, keeping it locked
    func resetLoopState(for fingerCount: Int, forceClose: Bool = false, endsStroke: Bool = true) {
        guard let session = recognizerRegistry.session(for: fingerCount) else {
            return
        }

        if session.didOpenLoopWithThisGesture {
            closeCallback(forceClose)
        }

        releaseGestureBlocker(for: session)
        if endsStroke {
            session.reset()
        } else {
            session.abandonStroke()
        }
        #if DEBUG
            closeDebugOverlay(force: true)
        #endif
    }

    @discardableResult
    func resetSwipeActionIfNeeded(fingerCount: Int, distance: CGFloat) -> Bool {
        guard let session = recognizerRegistry.session(for: fingerCount) else {
            return false
        }

        if session.resetSwipeActionIfNeeded(distance: distance) {
            changeAction(.init(.noSelection))
            #if DEBUG
                debugOverlayController.recordSwipeActionReset()
            #endif
            return true
        }

        return session.shouldSuppressSwipeAction(distance: distance)
    }

    private func releaseGestureBlocker(for session: MultitouchGestureSession) {
        if session.releaseGestureBlocker() {
            gestureBlocker.stop()
        }
    }
}

// MARK: - Actions

extension MultitouchTrigger {
    func clearActionSelection() {
        changeAction(.init(.noSelection))
    }

    private func changeAction(_ action: WindowAction, reverse: Bool = false, canAdvanceCycle: Bool = true) {
        changeActionCallback(action, reverse, canAdvanceCycle)
    }

    func isCycleAction(_ gesture: GestureBinding) -> Bool {
        resolvedWindowAction(from: gesture)?.direction == .cycle
    }

    func triggerRadialMenuAction(
        at index: Int,
        from actions: ArraySlice<RadialMenuAction>,
        reverse: Bool = false,
        canAdvanceCycle: Bool = true
    ) {
        guard actions.indices.contains(index) else { return }
        let action = actions[index]

        let resolvedAction: WindowAction = switch action.type {
        case let .custom(windowAction):
            windowAction
        case let .keybindReference(id):
            resolveKeybindReference(id)
        }

        changeAction(resolvedAction, reverse: reverse, canAdvanceCycle: canAdvanceCycle)
    }

    func resolvedWindowAction(from gesture: GestureBinding) -> WindowAction? {
        guard case let .singleAction(actionType) = gesture.action else { return nil }
        switch actionType {
        case let .custom(action): return action
        case let .keybindReference(id): return resolveKeybindReference(id)
        }
    }

    func triggerSingleAction(from gesture: GestureBinding, reverse: Bool = false, canAdvanceCycle: Bool = true) {
        guard let resolvedAction = resolvedWindowAction(from: gesture) else { return }
        changeAction(resolvedAction, reverse: reverse, canAdvanceCycle: canAdvanceCycle)
    }

    func triggerSwitchedGesture(_ gesture: GestureBinding, session: MultitouchGestureSession) {
        triggerSingleAction(from: gesture, canAdvanceCycle: !session.isRevisitingAction)

        if let window = session.pendingTargetWindow,
           resolvedWindowAction(from: gesture)?.allowsRapidRepeat == true {
            targetResolver.rememberRepeatableWindow(window, allowsRapidRepeat: true)
        }
    }

    private func resolveKeybindReference(_ id: UUID) -> WindowAction {
        if let cached = windowActionCache.actionsByIdentifier[id] {
            return cached
        }
        log.warn("Gesture references keybind \(id) that no longer exists")
        return Self.failedToResolveKeybindAction
    }
}
