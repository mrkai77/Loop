//
//  SystemGestureFilter.swift
//  Loop
//
//  Created by Kai Azim on 2026-09-24.
//

import CoreGraphics
import Foundation
import os
import Scribe
import Subsurface

/// Suppresses Dock gestures (Spaces, Mission Control, App Exposé) that conflict with Loop's.
@Loggable
final class SystemGestureFilter {
    enum DockGesture: Hashable, CaseIterable {
        case swipeLeft, swipeRight, swipeUp, swipeDown, pinch, spread

        var isSwipe: Bool {
            switch self {
            case .swipeLeft, .swipeRight, .swipeUp, .swipeDown: true
            case .pinch, .spread: false
            }
        }
    }

    enum ScrollOwner {
        case loop
        case apps
        /// Loop hasn't decided whether it takes the stroke
        case undecided
    }

    struct Claims {
        var anywhere: Set<DockGesture> = []
        var titlebarOnly: Set<DockGesture> = []

        var isEmpty: Bool {
            anywhere.isEmpty && titlebarOnly.isEmpty
        }
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
        /// Active finger count per device
        var fingerCounts: [UInt64: Int] = [:]
        var touchID = 0
        var isTouching = false
        var hasLookedUpTouch = false
        var titlebarLookup = TitlebarLookup.pending
        var isMissionControlShowing = false
        /// Absent while undecided
        var owners: [Int: Owner] = [:]
        var sequenceGeneration = 0

        var fingerCount: Int {
            fingerCounts.values.max() ?? 0
        }

        /// Look up once enough fingers are down for the smallest claim
        var lookupFingerCount: Int? {
            claims.filter { !$0.value.isEmpty }.keys.min().map { max($0, 2) }
        }
    }

    private struct Hold {
        var events: [CGEvent]
        let fingerCount: Int
        let touchID: Int?
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

        if !startEventMonitor() {
            log.warn("Failed to start system gesture filter")
        }
    }

    func stop() {
        contactsTask?.cancel()
        contactsTask = nil
        state.withLock { state in
            state = State(touchID: state.touchID, sequenceGeneration: state.sequenceGeneration + 1)
        }

        guard let eventMonitor else { return }
        eventMonitor.stop()
        self.eventMonitor = nil

        log.info("Stopped system gesture filter")
    }

    var currentTouchID: Int {
        state.withLock(\.touchID)
    }

    func canClaimCurrentTouch(fingerCount: Int) -> Bool {
        state.withLock { state in
            !state.isRunning || (!state.isMissionControlShowing && state.owners[fingerCount] != .dock)
        }
    }

    /// Returns false if the Dock is already acting on the stroke
    func claimCurrentTouch(fingerCount: Int) -> Bool {
        state.withLock { state in
            guard state.isRunning else { return true }
            // The Dock keeps its gestures while Mission Control is showing, so they can dismiss it
            guard !state.isMissionControlShowing, state.owners[fingerCount] != .dock else { return false }
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

    /// macOS turns unassigned three and four-finger swipes into scrolls
    func scrollOwner(heldFor elapsed: Duration, direction: DockGesture?) -> ScrollOwner {
        state.withLock { state in
            guard state.isRunning, state.isTouching else { return .apps }

            // Kept until every finger lifts, as fingers rarely leave together
            if state.owners.values.contains(.loop) {
                return .loop
            }

            guard state.owners[state.fingerCount] != .dock,
                  !state.isMissionControlShowing,
                  let claims = state.claims[state.fingerCount]
            else {
                return .apps
            }

            let mayBeInTitlebar = switch state.titlebarLookup {
            case .inside: true
            case .outside: false
            case .pending: elapsed < Self.titlebarDeadline
            }

            // Pinches never scroll
            let claimedSwipes = (mayBeInTitlebar ? claims.anywhere.union(claims.titlebarOnly) : claims.anywhere)
                .filter(\.isSwipe)

            guard !claimedSwipes.isEmpty else { return .apps }
            if let direction, !claimedSwipes.contains(direction) {
                return .apps
            }
            return .undecided
        }
    }

    // MARK: Lifecycle

    @discardableResult
    private func startEventMonitor() -> Bool {
        resetTouches()

        let newMonitor = ActiveEventMonitor(
            "system_gesture_filter",
            events: [.dockControl]
        ) { [weak self] proxy, event in
            guard let self else { return Unmanaged.passUnretained(event) }
            return handle(event, proxy: proxy)
        }

        newMonitor.start()

        guard newMonitor.isEnabled else {
            newMonitor.stop()
            return false
        }

        eventMonitor = newMonitor
        return true
    }

    private func resetTouches() {
        state.withLock { state in
            state.owners.removeAll()
            state.hasLookedUpTouch = false
            state.titlebarLookup = .pending
            state.isMissionControlShowing = false
            state.sequenceGeneration += 1
            if state.isTouching {
                state.touchID += 1
            }
        }
    }

    // MARK: Touches

    private func updateFingerCount(_ count: Int, deviceID: UInt64) {
        let lookupTouchID: Int? = state.withLock { state in
            guard state.isRunning else { return nil }

            // Devices report zero contacts when they stop or are removed
            if count > 0 {
                state.fingerCounts[deviceID] = count
            } else {
                state.fingerCounts.removeValue(forKey: deviceID)
            }

            let isTouching = state.fingerCount > 0
            if isTouching != state.isTouching {
                state.isTouching = isTouching
                state.hasLookedUpTouch = false
                state.titlebarLookup = .pending
                state.isMissionControlShowing = false
                state.owners.removeAll()

                if isTouching {
                    state.touchID += 1
                }
            }

            guard isTouching,
                  !state.hasLookedUpTouch,
                  let lookupFingerCount = state.lookupFingerCount,
                  state.fingerCount >= lookupFingerCount
            else {
                return nil
            }

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

    // MARK: Events

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
                log.debug("Dock swipe (\(hold.fingerCount) fingers, \(hold.motion)): dropped, ended while held (\(Self.elapsed(since: hold.start)))")
                return nil
            }

            let progress = event.getDoubleValueField(.dockSwipeProgress)
            if hold.direction == nil, progress != 0 {
                hold.direction = Self.gesture(motion: hold.motion, progress: progress)
            }

            let isPastDeadline = ContinuousClock.now - hold.start >= Self.titlebarDeadline
            switch settle(hold, isPastDeadline: isPastDeadline) {
            case .awaitingTitlebar, .awaitingDirection:
                hold.events.append(event.copy() ?? event)
                sequence = .holding(hold)
                return nil
            case let .loop(reason):
                sequence = .dropping
                log.debug("Dock swipe (\(hold.fingerCount) fingers, \(hold.motion)): Loop after holding \(hold.events.count) events for \(Self.elapsed(since: hold.start)), \(reason)")
                return nil
            case let .dock(reason):
                sequence = .passing
                // Posted from this tap's position, so they reach the Dock before the current event
                for heldEvent in hold.events {
                    heldEvent.tapPostEvent(proxy)
                }
                log.debug("Dock swipe (\(hold.fingerCount) fingers, \(hold.motion)): Dock after holding \(hold.events.count) events for \(Self.elapsed(since: hold.start)), \(reason)")
                return forward
            }
        }
    }

    /// Decides a new sequence at `began`, returning whether to forward it.
    private func beginSequence(_ event: CGEvent) -> Bool {
        let (isRunning, fingerCount, touchID, claims) = state.withLock { state in
            (state.isRunning, state.fingerCount, state.isTouching ? state.touchID : nil, state.claims[state.fingerCount])
        }

        guard isRunning,
              let motion = CGEventField.DockSwipeMotion(rawValue: event.getIntegerValueField(.dockSwipeMotion))
        else {
            sequence = .passing
            return true
        }

        if state.withLock(\.isMissionControlShowing) {
            sequence = .passing
            log.debug("Dock swipe (\(fingerCount) fingers, \(motion)): Dock, Mission Control is showing")
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
            direction: progress == 0 ? nil : Self.gesture(motion: motion, progress: progress)
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

    /// An owner already recorded for the touch wins
    private func settle(_ hold: Hold, isPastDeadline: Bool) -> Resolution {
        state.withLock { state in
            switch state.owners[hold.fingerCount] {
            case .loop:
                return .loop(reason: "Loop owns the touch")
            case .dock:
                return .dock(reason: "the Dock owns the touch")
            case nil:
                let titlebar = state.touchID == hold.touchID ? state.titlebarLookup : .pending
                let resolution = Self.resolve(hold, titlebar: titlebar, isPastDeadline: isPastDeadline)
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

    private static func elapsed(since start: ContinuousClock.Instant) -> Duration {
        ContinuousClock.now - start
    }

    private static func gesture(motion: CGEventField.DockSwipeMotion, progress: Double) -> DockGesture? {
        gestures(motion: motion, progress: progress).first
    }

    /// Both directions of the axis when `progress` is zero
    private static func gestures(motion: CGEventField.DockSwipeMotion, progress: Double) -> [DockGesture] {
        let (negative, positive): (DockGesture, DockGesture) = switch motion {
        case .horizontal: (.swipeRight, .swipeLeft)
        case .vertical: (.swipeUp, .swipeDown)
        case .pinch: (.pinch, .spread)
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
