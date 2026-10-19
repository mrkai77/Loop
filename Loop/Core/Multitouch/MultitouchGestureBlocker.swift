//
//  MultitouchGestureBlocker.swift
//  Loop
//
//  Created by Kai Azim on 2026-04-05.
//

import AppKit
import os
import Scribe

/// Stops trackpad scrolls and gestures from reaching apps while a Loop gesture is active.
/// Reference-counted, so one gesture ending doesn't stop blocking for another.
@Loggable
final class MultitouchGestureBlocker {
    private var monitor: ActiveEventMonitor?

    private let activeCount = OSAllocatedUnfairLock<Int>(initialState: 0)
    private let systemGestureFilter: SystemGestureFilter

    private struct Hold {
        var events: [CGEvent] = []
        let start = ContinuousClock.now
        let hasForwarded: Bool
        /// Y points down
        var translation = CGVector.zero
    }

    private enum ScrollSequence {
        case passing(hasForwarded: Bool)
        case holding(Hold)
        case dropping(hasForwarded: Bool)
    }

    private enum NavigationSwipe {
        case passing(hasForwarded: Bool)
        case holding(events: [CGEvent], start: ContinuousClock.Instant)
        case dropping(hasForwarded: Bool)
    }

    /// Only touched on the event tap thread
    private var scrollSequence = ScrollSequence.passing(hasForwarded: false)
    private var lastScrollPhase: Int64 = 0
    /// Decided when momentum begins, as a new stroke's `mayBegin` can arrive mid-momentum
    private var isDroppingMomentum = false
    private var navigationSwipe = NavigationSwipe.passing(hasForwarded: false)
    private var magnification = NavigationSwipe.passing(hasForwarded: false)

    /// Touch frames, force clicks and gesture brackets pass, as dropping them can leave apps mid-gesture.
    /// Zoom is held separately, the same way scrolls are, until Loop accepts or releases the pinch.
    private static let blockedGestureHIDTypes: Set<Int64> = [
        CGEventField.GestureHIDType.rotation.rawValue,
        CGEventField.GestureHIDType.zoomToggle.rawValue
    ]

    private static let scrollPhaseBegan: Int64 = 1
    private static let scrollPhaseEnded: Int64 = 4
    private static let scrollPhaseCancelled: Int64 = 8
    private static let scrollPhaseMayBegin: Int64 = 128
    private static let momentumPhaseBegin: Int64 = 1
    private static let momentumPhaseEnd: Int64 = 3
    private static let directionDistance: CGFloat = 4
    /// Loop splits directions at 45°
    private static let directionAxisRatio: CGFloat = 1.5

    private static let scrollDeltaFields: [CGEventField] = [
        .scrollWheelEventDeltaAxis1,
        .scrollWheelEventDeltaAxis2,
        .scrollWheelEventDeltaAxis3,
        .scrollWheelEventPointDeltaAxis1,
        .scrollWheelEventPointDeltaAxis2,
        .scrollWheelEventPointDeltaAxis3
    ]

    private static let scrollFixedDeltaFields: [CGEventField] = [
        .scrollWheelEventFixedPtDeltaAxis1,
        .scrollWheelEventFixedPtDeltaAxis2,
        .scrollWheelEventFixedPtDeltaAxis3
    ]

    init(systemGestureFilter: SystemGestureFilter) {
        self.systemGestureFilter = systemGestureFilter
    }

    func start() {
        guard monitor == nil else { return }

        log.info("Starting gesture blocker")
        startMonitor()
    }

    /// Also resets the reference count, as every gesture has been stopped by then. This clears any leaked `acquire()`.
    func stop() {
        activeCount.withLock { $0 = 0 }

        guard let monitor else { return }

        monitor.stop()
        self.monitor = nil

        log.info("Stopped gesture blocker")
    }

    func acquire() {
        let count = activeCount.withLock { count in
            count += 1
            return count
        }

        if count == 1 {
            if monitor == nil {
                log.warn("Gesture blocker activated without an event tap; trackpad events won't be suppressed")
            }
            log.debug("Gesture blocker activated")
        }
    }

    func release() {
        let count = activeCount.withLock { count in
            count = max(0, count - 1)
            return count
        }

        if count == 0 {
            log.debug("Gesture blocker deactivated")
        }
    }

    private func startMonitor() {
        scrollSequence = .passing(hasForwarded: false)
        lastScrollPhase = 0
        isDroppingMomentum = false
        navigationSwipe = .passing(hasForwarded: false)
        magnification = .passing(hasForwarded: false)

        // Gestures arrive as `NSEvent.EventType.gesture`, told apart by their HID type
        let eventTypes: [CGEventType] = [.scrollWheel, CGEventType(rawValue: UInt32(NSEvent.EventType.gesture.rawValue))!]

        let newMonitor = ActiveEventMonitor(
            "gesture_blocker",
            events: eventTypes
        ) { [weak self] proxy, event in
            guard let self else { return Unmanaged.passUnretained(event) }
            return handle(event, proxy: proxy)
        }

        newMonitor.start()

        // Left unset on failure, so the next `start()` tries again
        guard newMonitor.isEnabled else {
            log.warn("Failed to start gesture blocker event tap")
            newMonitor.stop()
            return
        }

        monitor = newMonitor
    }

    private func handle(_ event: CGEvent, proxy: CGEventTapProxy) -> Unmanaged<CGEvent>? {
        if event.type == .scrollWheel {
            return handleScroll(event, proxy: proxy)
        }

        let hidType = event.getIntegerValueField(.gestureHIDType)
        if hidType == CGEventField.GestureHIDType.navigationSwipe.rawValue {
            return handleNavigationSwipe(event, proxy: proxy)
        }

        if hidType == CGEventField.GestureHIDType.zoom.rawValue {
            return handleMagnification(event, proxy: proxy)
        }

        guard Self.blockedGestureHIDTypes.contains(hidType), activeCount.withLock({ $0 > 0 }) else {
            return Unmanaged.passUnretained(event)
        }

        return Self.handleGesture(event)
    }

    // MARK: Scrolls

    /// Holds a stroke while Loop decides on it, as it scrolls before Loop recognizes it
    private func handleScroll(_ event: CGEvent, proxy: CGEventTapProxy) -> Unmanaged<CGEvent>? {
        let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        let phase = event.getIntegerValueField(.scrollWheelEventScrollPhase)
        let momentumPhase = event.getIntegerValueField(.scrollWheelEventMomentumPhase)

        // Mouse wheel scrolls are discrete and phaseless
        guard isContinuous || phase != 0 || momentumPhase != 0 else {
            return Unmanaged.passUnretained(event)
        }

        let forward = Unmanaged.passUnretained(event)

        if phase == Self.scrollPhaseMayBegin || phase == Self.scrollPhaseBegan {
            beginScroll(phase: phase)
        }
        if phase != 0 {
            lastScrollPhase = phase
        }

        if momentumPhase != 0 {
            if momentumPhase == Self.momentumPhaseBegin {
                isDroppingMomentum = if case .dropping = scrollSequence { true } else { false }
            }
            let isDropped = isDroppingMomentum
            if momentumPhase == Self.momentumPhaseEnd {
                isDroppingMomentum = false
            }
            return isDropped ? nil : forward
        }

        // Phaseless, such as from smooth scrolling utilities, so not part of a stroke
        guard phase != 0 else {
            return activeCount.withLock { $0 > 0 } ? nil : forward
        }

        switch scrollSequence {
        case let .passing(hasForwarded):
            if systemGestureFilter.scrollOwner(heldFor: .zero, direction: nil) == .loop {
                scrollSequence = .dropping(hasForwarded: hasForwarded)
                return dropScroll(event, hasForwarded: hasForwarded)
            }
            scrollSequence = .passing(hasForwarded: true)
            return forward

        case var .holding(hold):
            let movement = Self.fingerTranslation(of: event)
            hold.translation.dx += movement.dx
            hold.translation.dy += movement.dy
            let elapsed = ContinuousClock.now - hold.start
            let owner = systemGestureFilter.scrollOwner(heldFor: elapsed, direction: Self.direction(of: hold.translation))

            switch owner {
            case .loop:
                scrollSequence = .dropping(hasForwarded: hold.hasForwarded)
                log.debug("Dropped \(hold.events.count) held scroll events, Loop took the stroke")
                return dropScroll(event, hasForwarded: hold.hasForwarded)
            case .undecided where isScrollOpen:
                hold.events.append(event.copy() ?? event)
                scrollSequence = .holding(hold)
                return nil
            case .apps, .undecided:
                scrollSequence = .passing(hasForwarded: true)
                // Posted from this tap's position, so they reach apps before the current event
                for heldEvent in hold.events {
                    heldEvent.tapPostEvent(proxy)
                }
                log.debug("Replayed \(hold.events.count) held scroll events after \(elapsed)")
                return forward
            }

        case let .dropping(hasForwarded):
            return dropScroll(event, hasForwarded: hasForwarded)
        }
    }

    private var isScrollOpen: Bool {
        lastScrollPhase != 0 && lastScrollPhase != Self.scrollPhaseEnded && lastScrollPhase != Self.scrollPhaseCancelled
    }

    /// Decided again at `began`, as more fingers may have landed since `mayBegin`
    private func beginScroll(phase: Int64) {
        let hasForwarded: Bool
        // Anything else starts a new stroke, in case the last one's end was missed
        if phase == Self.scrollPhaseBegan, lastScrollPhase == Self.scrollPhaseMayBegin {
            guard case let .passing(forwarded) = scrollSequence else { return }
            hasForwarded = forwarded
        } else {
            hasForwarded = false
        }

        switch systemGestureFilter.scrollOwner(heldFor: .zero, direction: nil) {
        case .loop:
            scrollSequence = .dropping(hasForwarded: hasForwarded)
        case .undecided:
            scrollSequence = .holding(Hold(hasForwarded: hasForwarded))
        case .apps:
            scrollSequence = .passing(hasForwarded: hasForwarded)
        }
    }

    /// With natural scrolling, deltas follow the fingers
    private static func fingerTranslation(of event: CGEvent) -> CGVector {
        guard let nsEvent = NSEvent(cgEvent: event) else { return .zero }
        let sign: CGFloat = nsEvent.isDirectionInvertedFromDevice ? 1 : -1
        return CGVector(dx: nsEvent.scrollingDeltaX * sign, dy: nsEvent.scrollingDeltaY * sign)
    }

    private static func direction(of translation: CGVector) -> SystemGestureFilter.DockGesture? {
        let horizontal = abs(translation.dx)
        let vertical = abs(translation.dy)
        guard max(horizontal, vertical) >= directionDistance else { return nil }

        if horizontal >= vertical * directionAxisRatio {
            return translation.dx > 0 ? .swipeRight : .swipeLeft
        }
        if vertical >= horizontal * directionAxisRatio {
            return translation.dy > 0 ? .swipeDown : .swipeUp
        }
        return nil
    }

    private func dropScroll(_ event: CGEvent, hasForwarded: Bool) -> Unmanaged<CGEvent>? {
        let phase = event.getIntegerValueField(.scrollWheelEventScrollPhase)

        // Let ends through, so apps don't stay mid-scroll
        guard hasForwarded, phase == Self.scrollPhaseEnded || phase == Self.scrollPhaseCancelled else {
            return nil
        }

        for field in Self.scrollDeltaFields {
            event.setIntegerValueField(field, value: 0)
        }
        for field in Self.scrollFixedDeltaFields {
            event.setDoubleValueField(field, value: 0)
        }

        return Unmanaged.passUnretained(event)
    }

    // MARK: Navigation Swipes

    /// Apps swipe between pages from these, so they're held like scrolls while Loop decides on the stroke
    private func handleNavigationSwipe(_ event: CGEvent, proxy: CGEventTapProxy) -> Unmanaged<CGEvent>? {
        let forward = Unmanaged.passUnretained(event)
        let phase = CGEventField.GesturePhase(rawValue: event.getIntegerValueField(.gesturePhase))
        let isEnd = phase == .ended || phase == .cancelled
        let direction = Self.direction(ofSwipeMask: event.getIntegerValueField(.swipeMask))

        if phase == .began {
            navigationSwipe = switch systemGestureFilter.scrollOwner(heldFor: .zero, direction: direction) {
            case .loop: .dropping(hasForwarded: false)
            case .undecided: .holding(events: [], start: .now)
            case .apps: .passing(hasForwarded: false)
            }
        }

        switch navigationSwipe {
        case let .passing(hasForwarded):
            if !isEnd, systemGestureFilter.scrollOwner(heldFor: .zero, direction: nil) == .loop {
                navigationSwipe = .dropping(hasForwarded: hasForwarded)
                return nil
            }
            navigationSwipe = .passing(hasForwarded: !isEnd)
            return forward

        case let .holding(events, start):
            switch systemGestureFilter.scrollOwner(heldFor: ContinuousClock.now - start, direction: direction) {
            case .loop:
                navigationSwipe = isEnd ? .passing(hasForwarded: false) : .dropping(hasForwarded: false)
                log.debug("Dropped \(events.count) held navigation swipe events, Loop took the stroke")
                return nil
            case .undecided where !isEnd:
                navigationSwipe = .holding(events: events + [event.copy() ?? event], start: start)
                return nil
            case .apps, .undecided:
                navigationSwipe = .passing(hasForwarded: !isEnd)
                // Posted from this tap's position, so they reach apps before the current event
                for heldEvent in events {
                    heldEvent.tapPostEvent(proxy)
                }
                log.debug("Replayed \(events.count) held navigation swipe events after \(ContinuousClock.now - start)")
                return forward
            }

        case let .dropping(hasForwarded):
            guard isEnd else { return nil }
            navigationSwipe = .passing(hasForwarded: false)
            // Let ends through to apps that saw the swipe begin, so they don't stay mid-swipe
            return hasForwarded ? forward : nil
        }
    }

    // MARK: Magnification

    /// Apps zoom from these. Held until Loop accepts the pinch or the stroke is clearly not one of its gestures.
    private func handleMagnification(_ event: CGEvent, proxy: CGEventTapProxy) -> Unmanaged<CGEvent>? {
        let forward = Unmanaged.passUnretained(event)
        let phase = CGEventField.GesturePhase(rawValue: event.getIntegerValueField(.gesturePhase))
        let isEnd = phase == .ended || phase == .cancelled

        if phase == .began {
            magnification = switch systemGestureFilter.magnificationOwner(heldFor: .zero) {
            case .loop: .dropping(hasForwarded: false)
            case .undecided: .holding(events: [], start: .now)
            case .apps: .passing(hasForwarded: false)
            }
        }

        switch magnification {
        case let .passing(hasForwarded):
            if !isEnd, systemGestureFilter.magnificationOwner(heldFor: .zero) == .loop {
                magnification = .dropping(hasForwarded: hasForwarded)
                return nil
            }
            magnification = .passing(hasForwarded: !isEnd)
            return forward

        case let .holding(events, start):
            switch systemGestureFilter.magnificationOwner(heldFor: ContinuousClock.now - start) {
            case .loop:
                magnification = isEnd ? .passing(hasForwarded: false) : .dropping(hasForwarded: false)
                log.debug("Dropped \(events.count) held magnification events, Loop took the stroke")
                return nil
            case .undecided where !isEnd:
                magnification = .holding(events: events + [event.copy() ?? event], start: start)
                return nil
            case .apps, .undecided:
                magnification = .passing(hasForwarded: !isEnd)
                for heldEvent in events {
                    heldEvent.tapPostEvent(proxy)
                }
                log.debug("Replayed \(events.count) held magnification events after \(ContinuousClock.now - start)")
                return forward
            }

        case let .dropping(hasForwarded):
            guard isEnd else { return nil }
            magnification = .passing(hasForwarded: false)
            // Let ends through to apps that saw the zoom begin, so they don't stay mid-zoom
            return hasForwarded ? forward : nil
        }
    }

    /// `IOHIDSwipeMask` bits, following the fingers
    private static func direction(ofSwipeMask mask: Int64) -> SystemGestureFilter.DockGesture? {
        switch mask {
        case 1: .swipeUp
        case 2: .swipeDown
        case 4: .swipeLeft
        case 8: .swipeRight
        default: nil
        }
    }

    // MARK: Gestures

    private static func handleGesture(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        // Let ends through, so apps don't stay mid-zoom
        let phase = CGEventField.GesturePhase(rawValue: event.getIntegerValueField(.gesturePhase))
        if phase == .ended || phase == .cancelled {
            return Unmanaged.passUnretained(event)
        }

        return nil
    }
}
