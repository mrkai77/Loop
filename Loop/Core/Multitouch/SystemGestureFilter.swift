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
        case undecided, loop, dock
    }

    private enum Sequence {
        case passing
        case dropping
        /// Started the unbound way on a partly bound axis. The Dock is sent a cancel if Loop claims it
        case provisional
        /// Started the bound way on a partly bound axis. Replayed to the Dock if Loop doesn't claim it
        case holding(began: CGEvent)
    }

    private enum Decision {
        case forward, drop
        case replay(began: CGEvent, current: CGEvent)
        case cancel(CGEvent)
    }

    private struct State {
        var isRunning = false
        var claims: [Int: Claims] = [:]
        /// Active finger count per multitouch device
        var fingerCounts: [UInt64: Int] = [:]
        /// Incremented whenever the fingers touch down or lift, so stale lookups are discarded
        var touchID = 0
        var hasLookedUpTouch = false
        /// Titlebar-only gestures stay claimed until known: losing a stroke beats both reacting
        var isTouchInTitlebar: Bool?
        var isMissionControlShowing = false
        var owners: [Int: Owner] = [:]

        var fingerCount: Int {
            fingerCounts.values.max() ?? 0
        }

        func claimedGestures(fingerCount: Int) -> Set<DockGesture> {
            guard let claims = claims[fingerCount] else { return [] }
            return isTouchInTitlebar == false ? claims.anywhere : claims.anywhere.union(claims.titlebarOnly)
        }

        /// The Dock keeps its gestures while Mission Control is showing, so they can dismiss it
        func owner(fingerCount: Int) -> Owner {
            isMissionControlShowing ? .dock : owners[fingerCount] ?? .undecided
        }
    }

    private let gestureMonitor: SubsurfaceMonitor
    private let isCursorInTitlebar: @MainActor (_ touchID: Int) -> Bool
    private let state = OSAllocatedUnfairLock(initialState: State())
    private var eventMonitor: ActiveEventMonitor?
    private var contactsTask: Task<(), Never>?

    /// Marks events Loop re-posts to the Dock, so the filter lets them through
    private static let repostMarker: Int64 = 0x4C4F_4F50
    /// Kept small, as the Dock jumps to the current progress when a held `began` is replayed
    private static let holdReleaseProgress: Double = 0.05

    /// Only touched on the event tap thread
    private var sequence = Sequence.passing
    private var sequenceFingerCount = 0

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

        let newMonitor = ActiveEventMonitor(
            "system_gesture_filter",
            events: [.dockControl]
        ) { [weak self] event in
            self?.handle(event) ?? .forward
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
        state.withLock { $0 = State() }

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
                state.isTouchInTitlebar = nil
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
                state.isTouchInTitlebar = isInTitlebar
                state.isMissionControlShowing = isMissionControlShowing
            }
        }
    }

    private func handle(_ event: CGEvent) -> ActiveEventMonitor.EventHandling {
        guard event.getIntegerValueField(.gestureHIDType) == CGEventField.GestureHIDType.dockSwipe.rawValue,
              event.getIntegerValueField(.eventSourceUserData) != Self.repostMarker
        else {
            return .forward
        }

        switch decide(for: event) {
        case .forward:
            return .forward
        case .drop:
            return .ignore
        case let .replay(began, current):
            repost(began)
            repost(current)
            return .ignore
        case let .cancel(current):
            current.setIntegerValueField(.gesturePhase, value: CGEventField.GesturePhase.cancelled.rawValue)
            current.setDoubleValueField(.dockSwipeVelocity, value: 0)
            repost(current)
            return .ignore
        }
    }

    private func decide(for event: CGEvent) -> Decision {
        let phase = CGEventField.GesturePhase(rawValue: event.getIntegerValueField(.gesturePhase))
        let motion = CGEventField.DockSwipeMotion(rawValue: event.getIntegerValueField(.dockSwipeMotion))
        let progress = event.getDoubleValueField(.dockSwipeProgress)

        if phase == .began {
            sequence = beginSequence(event, motion: motion, progress: progress)
            switch sequence {
            case .passing, .provisional: return .forward
            case .dropping, .holding: return .drop
            }
        }

        let isEnd = phase == .ended || phase == .cancelled
        defer {
            if isEnd { sequence = .passing }
        }

        switch sequence {
        case .passing:
            return .forward
        case .dropping:
            return .drop
        case .provisional:
            let fingerCount = sequenceFingerCount
            guard state.withLock({ $0.owner(fingerCount: fingerCount) }) == .loop else { return .forward }
            sequence = .dropping
            return .cancel(event.copy() ?? event)
        case let .holding(began):
            let fingerCount = sequenceFingerCount
            let owner: Owner = state.withLock { state in
                let owner = state.owner(fingerCount: fingerCount)
                guard owner == .undecided,
                      abs(progress) >= Self.holdReleaseProgress,
                      Self.gestures(motion: motion, progress: progress)
                      .isDisjoint(with: state.claimedGestures(fingerCount: fingerCount))
                else {
                    return owner
                }
                state.owners[fingerCount] = .dock
                return .dock
            }

            switch owner {
            case .undecided:
                return .drop
            case .loop:
                sequence = .dropping
                return .drop
            case .dock:
                sequence = .passing
                // A sequence ending while held was too small for the Dock to act on
                return isEnd ? .drop : .replay(began: began, current: event.copy() ?? event)
            }
        }
    }

    private func beginSequence(_ event: CGEvent, motion: CGEventField.DockSwipeMotion?, progress: Double) -> Sequence {
        let (fingerCount, owner, claimed) = state.withLock { state in
            let fingerCount = state.fingerCount
            return (fingerCount, state.owner(fingerCount: fingerCount), state.claimedGestures(fingerCount: fingerCount))
        }
        sequenceFingerCount = fingerCount

        switch owner {
        case .loop:
            return .dropping
        case .dock:
            return .passing
        case .undecided:
            let axis = Self.gestures(motion: motion, progress: 0)
            let claimedOnAxis = axis.intersection(claimed)

            if claimedOnAxis.isEmpty {
                setOwner(.dock, fingerCount: fingerCount)
                return .passing
            }
            if claimedOnAxis == axis {
                setOwner(.loop, fingerCount: fingerCount)
                return .dropping
            }

            let startsClaimedWay = !Self.gestures(motion: motion, progress: progress).isDisjoint(with: claimedOnAxis)
            return startsClaimedWay ? .holding(began: event.copy() ?? event) : .provisional
        }
    }

    private func setOwner(_ owner: Owner, fingerCount: Int) {
        state.withLock { $0.owners[fingerCount] = owner }
    }

    private func repost(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: Self.repostMarker)
        event.post(tap: .cgSessionEventTap)
    }

    /// Both directions of the axis when `progress` is zero
    private static func gestures(motion: CGEventField.DockSwipeMotion?, progress: Double) -> Set<DockGesture> {
        let (negative, positive): (DockGesture, DockGesture)
        switch motion {
        case .horizontal: (negative, positive) = (.swipeRight, .swipeLeft)
        case .vertical: (negative, positive) = (.swipeUp, .swipeDown)
        case .pinch: (negative, positive) = (.pinch, .spread)
        case nil: return []
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
