//
//  SystemGestureFilter.swift
//  Loop
//
//  Created by Kai Azim on 2026-09-24.
//

import CoreGraphics
import os
import Scribe
import Subsurface

/// Suppresses Dock gestures (Spaces, Mission Control, App Exposé) that conflict with Loop's.
@Loggable
final class SystemGestureFilter {
    enum DockGesture: Hashable, CaseIterable {
        case swipeLeft, swipeRight, swipeUp, swipeDown, pinch, spread
    }

    struct Claims {
        var anywhere: Set<DockGesture> = []
        var titlebarOnly: Set<DockGesture> = []
    }

    private enum Owner {
        case loop, dock
    }

    private enum TitlebarLookup {
        case pending, inside, outside
    }

    private struct State {
        var isRunning = false
        var claims: [Int: Claims] = [:]
        /// Active finger count per multitouch device
        var fingerCounts: [UInt64: Int] = [:]
        /// Incremented whenever the fingers touch down or lift, so stale lookups are discarded
        var touchID = 0
        var hasLookedUpTouch = false
        var titlebarLookup = TitlebarLookup.pending
        var isMissionControlShowing = false
        /// Absent while undecided
        var owners: [Int: Owner] = [:]
        var sequenceGeneration = 0

        var fingerCount: Int {
            fingerCounts.values.max() ?? 0
        }

        /// The Dock keeps its gestures while Mission Control is showing, so they can dismiss it
        func owner(fingerCount: Int) -> Owner? {
            isMissionControlShowing ? .dock : owners[fingerCount]
        }
    }

    private struct Hold {
        var events: [CGEvent]
        let fingerCount: Int
        let touchID: Int
        let motion: CGEventField.DockSwipeMotion
        let claims: Claims
        let start: ContinuousClock.Instant
        var direction: DockGesture?
    }

    private enum Sequence {
        case passing
        case dropping
        case holding(Hold)
    }

    private enum Resolution {
        case loop(reason: String)
        case dock(reason: String)
        case awaitingTitlebar
        case awaitingDirection
    }

    private let gestureMonitor: SubsurfaceMonitor
    private let isCursorInTitlebar: @MainActor (_ touchID: Int) -> Bool
    private let state = OSAllocatedUnfairLock(initialState: State())
    private var eventMonitor: ActiveEventMonitor?
    private var contactsTask: Task<(), Never>?

    /// How long a sequence may wait on the titlebar lookup before the Dock gets it
    private static let titlebarDeadline: Duration = .milliseconds(40)
    private static let ownProcessID = Int64(getpid())

    /// Only touched on the event tap thread
    private var sequence = Sequence.passing
    private var sequenceGeneration = 0

    init(
        gestureMonitor: SubsurfaceMonitor,
        isCursorInTitlebar: @escaping @MainActor (_ touchID: Int) -> Bool
    ) {
        self.gestureMonitor = gestureMonitor
        self.isCursorInTitlebar = isCursorInTitlebar
    }

    /// Starts filtering, or updates the claimed gestures if already running.
    func start(claiming claims: [Int: Claims]) {
        state.withLock {
            $0.claims = claims
            $0.isRunning = true
        }

        if contactsTask == nil {
            // Detached so contact frames are counted off the main actor
            contactsTask = Task.detached(priority: .userInitiated) { [weak self, gestureMonitor] in
                for await (device, contacts) in gestureMonitor.contacts() {
                    guard !Task.isCancelled, let self else { break }
                    guard let deviceID = device.deviceID else { continue }
                    updateFingerCount(
                        SubsurfaceContactFilter.activeTouches(from: SubsurfaceContactFilter.removePalms(from: contacts)).count,
                        deviceID: deviceID
                    )
                }
            }
        }

        guard eventMonitor == nil else { return }

        log.info("Starting system gesture filter")
        state.withLock { $0.sequenceGeneration += 1 }

        let newMonitor = ActiveEventMonitor(
            "system_gesture_filter",
            events: [.dockControl]
        ) { [weak self] proxy, event in
            guard let self else { return Unmanaged.passUnretained(event) }
            return handle(event, proxy: proxy)
        }
        newMonitor.start()

        guard newMonitor.isEnabled else {
            log.warn("Failed to start system gesture filter")
            newMonitor.stop()
            return
        }

        eventMonitor = newMonitor
    }

    func stop() {
        contactsTask?.cancel()
        contactsTask = nil
        state.withLock { $0 = State(sequenceGeneration: $0.sequenceGeneration + 1) }

        guard let eventMonitor else { return }
        eventMonitor.stop()
        self.eventMonitor = nil

        log.info("Stopped system gesture filter")
    }

    /// Identifies the touch in progress, changing whenever the fingers touch down or lift
    var currentTouchID: Int {
        state.withLock(\.touchID)
    }

    func canClaimCurrentTouch(fingerCount: Int) -> Bool {
        state.withLock { !$0.isRunning || $0.owner(fingerCount: fingerCount) != .dock }
    }

    /// Returns false if the Dock is already acting on the stroke
    func claimCurrentTouch(fingerCount: Int) -> Bool {
        state.withLock { state in
            guard state.isRunning else { return true }
            guard state.owner(fingerCount: fingerCount) != .dock else { return false }
            state.owners[fingerCount] = .loop
            return true
        }
    }

    func releaseCurrentTouch(fingerCount: Int) {
        state.withLock { state in
            guard state.isRunning else { return }
            state.owners[fingerCount] = .dock
        }
    }

    private func updateFingerCount(_ count: Int, deviceID: UInt64) {
        let lookupTouchID: Int? = state.withLock { state in
            let wasTouching = state.fingerCount > 0
            state.fingerCounts[deviceID] = count

            if wasTouching != (state.fingerCount > 0) {
                state.touchID += 1
                state.hasLookedUpTouch = false
                state.titlebarLookup = .pending
                state.isMissionControlShowing = false
                state.owners.removeAll()
            }

            // Look up once enough fingers are down for the smallest claim
            let lookupFingerCount = max(state.claims.keys.min() ?? 2, 2)
            guard !state.hasLookedUpTouch, state.fingerCount >= lookupFingerCount else { return nil }
            state.hasLookedUpTouch = true
            return state.touchID
        }

        guard let lookupTouchID else { return }

        Task { @MainActor [isCursorInTitlebar, state] in
            let isInTitlebar = isCursorInTitlebar(lookupTouchID)
            let isMissionControlShowing = MissionControl.isShowing
            state.withLock { state in
                guard state.touchID == lookupTouchID else { return }
                state.titlebarLookup = isInTitlebar ? .inside : .outside
                state.isMissionControlShowing = isMissionControlShowing
            }
        }
    }

    /// Called on the event tap thread. Each Dock swipe sequence reaches the Dock whole and in order, or not at all,
    /// as the Dock can't recover from a sequence it didn't see from `began`.
    private func handle(_ event: CGEvent, proxy: CGEventTapProxy) -> Unmanaged<CGEvent>? {
        let forward = Unmanaged.passUnretained(event)

        guard event.getIntegerValueField(.gestureHIDType) == CGEventField.GestureHIDType.dockSwipe.rawValue else {
            return forward
        }

        // Dock swipes posted by other apps are theirs to manage
        let sourceProcessID = event.getIntegerValueField(.eventSourceUnixProcessID)
        guard sourceProcessID == 0 || sourceProcessID == Self.ownProcessID else {
            return forward
        }

        let generation = state.withLock(\.sequenceGeneration)
        if generation != sequenceGeneration {
            sequenceGeneration = generation
            sequence = .passing
        }

        let phase = CGEventField.GesturePhase(rawValue: event.getIntegerValueField(.gesturePhase))

        if phase == .began {
            if case let .holding(hold) = sequence {
                log.debug("Dock swipe (\(hold.fingerCount) fingers, \(hold.motion)): dropped \(hold.events.count) held events, a new sequence began before it ended")
            }
            return beginSequence(event) ? forward : nil
        }

        let isEnd = phase == .ended || phase == .cancelled

        switch sequence {
        case .passing:
            return forward
        case .dropping:
            if isEnd { sequence = .passing }
            return nil
        case var .holding(hold):
            if isEnd {
                sequence = .passing
                log.debug("Dock swipe (\(hold.fingerCount) fingers, \(hold.motion)): dropped, ended while held (\(ContinuousClock.now - hold.start))")
                return nil
            }

            let progress = event.getDoubleValueField(.dockSwipeProgress)
            if hold.direction == nil, progress != 0 {
                hold.direction = Self.gestures(motion: hold.motion, progress: progress).first
            }

            let isPastDeadline = ContinuousClock.now - hold.start >= Self.titlebarDeadline
            switch settle(hold, isPastDeadline: isPastDeadline) {
            case .awaitingTitlebar, .awaitingDirection:
                hold.events.append(event.copy() ?? event)
                sequence = .holding(hold)
                return nil
            case let .loop(reason):
                sequence = .dropping
                log.debug("Dock swipe (\(hold.fingerCount) fingers, \(hold.motion)): Loop after holding \(hold.events.count) events for \(ContinuousClock.now - hold.start), \(reason)")
                return nil
            case let .dock(reason):
                sequence = .passing
                // Posted from this tap's position, so they reach the Dock before the current event
                for heldEvent in hold.events {
                    heldEvent.tapPostEvent(proxy)
                }
                log.debug("Dock swipe (\(hold.fingerCount) fingers, \(hold.motion)): Dock after holding \(hold.events.count) events for \(ContinuousClock.now - hold.start), \(reason)")
                return forward
            }
        }
    }

    /// Decides a new sequence at `began`, returning whether to forward it.
    private func beginSequence(_ event: CGEvent) -> Bool {
        let (isRunning, fingerCount, touchID, claims) = state.withLock { state in
            (state.isRunning, state.fingerCount, state.touchID, state.claims[state.fingerCount])
        }

        guard isRunning,
              let motion = CGEventField.DockSwipeMotion(rawValue: event.getIntegerValueField(.dockSwipeMotion))
        else {
            sequence = .passing
            return true
        }

        let progress = event.getDoubleValueField(.dockSwipeProgress)
        let hold = Hold(
            events: [event.copy() ?? event],
            fingerCount: fingerCount,
            touchID: touchID,
            motion: motion,
            claims: claims ?? Claims(),
            start: .now,
            direction: progress == 0 ? nil : Self.gestures(motion: motion, progress: progress).first
        )

        switch settle(hold, isPastDeadline: false) {
        case let .loop(reason):
            sequence = .dropping
            log.debug("Dock swipe (\(fingerCount) fingers, \(motion)): Loop, \(reason)")
            return false
        case let .dock(reason):
            sequence = .passing
            log.debug("Dock swipe (\(fingerCount) fingers, \(motion)): Dock, \(reason)")
            return true
        case .awaitingTitlebar:
            sequence = .holding(hold)
            log.debug("Dock swipe (\(fingerCount) fingers, \(motion)): holding for the titlebar lookup")
            return false
        case .awaitingDirection:
            sequence = .holding(hold)
            log.debug("Dock swipe (\(fingerCount) fingers, \(motion)): holding for the stroke's direction")
            return false
        }
    }

    /// An owner already recorded for the touch wins; otherwise the resolved owner is recorded.
    private func settle(_ hold: Hold, isPastDeadline: Bool) -> Resolution {
        state.withLock { state in
            let isSameTouch = state.touchID == hold.touchID

            switch isSameTouch ? state.owner(fingerCount: hold.fingerCount) : nil {
            case .loop:
                return .loop(reason: "Loop owns the touch")
            case .dock:
                return .dock(reason: state.isMissionControlShowing ? "Mission Control is showing" : "the Dock owns the touch")
            case nil:
                let titlebar = isSameTouch ? state.titlebarLookup : .pending
                let resolution = Self.resolve(hold, titlebar: titlebar, isPastDeadline: isPastDeadline)
                guard isSameTouch else { return resolution }
                switch resolution {
                case .loop: state.owners[hold.fingerCount] = .loop
                case .dock: state.owners[hold.fingerCount] = .dock
                case .awaitingTitlebar, .awaitingDirection: break
                }
                return resolution
            }
        }
    }

    private static func resolve(_ hold: Hold, titlebar: TitlebarLookup, isPastDeadline: Bool) -> Resolution {
        let directions = hold.direction.map { [$0] } ?? gestures(motion: hold.motion, progress: 0)

        var owners: Set<Owner> = []
        var dependsOnTitlebar = false
        var missedDeadline = false
        var isAwaitingTitlebar = false

        for direction in directions {
            if hold.claims.anywhere.contains(direction) {
                owners.insert(.loop)
            } else if hold.claims.titlebarOnly.contains(direction) {
                dependsOnTitlebar = true
                switch titlebar {
                case .inside:
                    owners.insert(.loop)
                case .outside:
                    owners.insert(.dock)
                case .pending:
                    if isPastDeadline {
                        missedDeadline = true
                        owners.insert(.dock)
                    } else {
                        isAwaitingTitlebar = true
                    }
                }
            } else {
                owners.insert(.dock)
            }
        }

        // Only one direction of the axis is claimed
        if owners.count > 1 {
            return .awaitingDirection
        }
        if isAwaitingTitlebar {
            return .awaitingTitlebar
        }

        let directionDescription = hold.direction.map { "\($0) " } ?? ""
        switch owners.first {
        case .loop:
            return .loop(reason: dependsOnTitlebar ? "\(directionDescription)claimed and started in a titlebar" : "\(directionDescription)claimed anywhere")
        case .dock, nil:
            if missedDeadline {
                return .dock(reason: "titlebar lookup missed its \(titlebarDeadline) deadline")
            }
            return .dock(reason: dependsOnTitlebar ? "\(directionDescription)claimed but started outside a titlebar" : "\(directionDescription)not claimed")
        }
    }

    /// Both directions of the axis when `progress` is zero
    private static func gestures(motion: CGEventField.DockSwipeMotion, progress: Double) -> [DockGesture] {
        let (negative, positive): (DockGesture, DockGesture)
        switch motion {
        case .horizontal: (negative, positive) = (.swipeRight, .swipeLeft)
        case .vertical: (negative, positive) = (.swipeUp, .swipeDown)
        case .pinch: (negative, positive) = (.pinch, .spread)
        }

        if progress < 0 { return [negative] }
        if progress > 0 { return [positive] }
        return [negative, positive]
    }
}

// MARK: - Claims

extension SystemGestureFilter {
    /// Maps each finger count to the Dock gestures that Loop's gestures would conflict with.
    static func claims(for gestures: [GestureBinding]) -> [Int: Claims] {
        GestureBinding.activeGestures(in: gestures)
            .reduce(into: [:]) { result, gesture in
                let dockGestures = dockGestures(for: gesture.kind)
                switch gesture.effectiveActivationZone {
                case .anywhere:
                    result[gesture.fingerCount, default: Claims()].anywhere.formUnion(dockGestures)
                case .titlebar:
                    result[gesture.fingerCount, default: Claims()].titlebarOnly.formUnion(dockGestures)
                }
            }
    }

    private static func dockGestures(for kind: GestureBinding.Kind) -> Set<DockGesture> {
        switch kind {
        case .radialMenu: Set(DockGesture.allCases)
        case .swipeLeft: [.swipeLeft]
        case .swipeRight: [.swipeRight]
        case .swipeUp: [.swipeUp]
        case .swipeDown: [.swipeDown]
        case .magnifyOut: [.pinch]
        case .magnifyIn: [.spread]
        }
    }
}
