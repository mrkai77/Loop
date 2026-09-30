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

    /// `magnify` is left out, as its raw value (30) collides with `dockControl`
    private static let gestureEventTypes: Set<UInt32> = [
        UInt32(NSEvent.EventType.gesture.rawValue),
        UInt32(NSEvent.EventType.rotate.rawValue),
        UInt32(NSEvent.EventType.swipe.rawValue),
        UInt32(NSEvent.EventType.smartMagnify.rawValue)
    ]

    private static let scrollPhaseEnded: Int64 = 4
    private static let scrollPhaseCancelled: Int64 = 8
    private static let momentumPhaseEnd: Int64 = 3
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
        let eventTypes: [CGEventType] = [.scrollWheel] + Self.gestureEventTypes.compactMap(CGEventType.init(rawValue:))

        let newMonitor = ActiveEventMonitor(
            "gesture_blocker",
            events: eventTypes,
            callback: Self.makeEventHandler(activeCount: activeCount)
        )

        newMonitor.start()

        // Left unset on failure, so the next `start()` tries again
        guard newMonitor.isEnabled else {
            log.warn("Failed to start gesture blocker event tap")
            newMonitor.stop()
            return
        }

        monitor = newMonitor
    }

    private static func makeEventHandler(
        activeCount: OSAllocatedUnfairLock<Int>
    ) -> (CGEvent) -> Unmanaged<CGEvent>? {
        { event in
            guard activeCount.withLock({ $0 > 0 }) else {
                return Unmanaged.passUnretained(event)
            }

            if event.type == .scrollWheel {
                return handleScroll(event)
            }

            if gestureEventTypes.contains(event.type.rawValue) {
                return handleGesture(event)
            }

            return Unmanaged.passUnretained(event)
        }
    }

    private static func handleScroll(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        let phase = event.getIntegerValueField(.scrollWheelEventScrollPhase)
        let momentumPhase = event.getIntegerValueField(.scrollWheelEventMomentumPhase)

        // Mouse wheel scrolls are discrete and phaseless
        guard isContinuous || phase != 0 || momentumPhase != 0 else {
            return Unmanaged.passUnretained(event)
        }

        // Let ends through, so apps don't stay mid-scroll
        let isEnd = phase == scrollPhaseEnded || phase == scrollPhaseCancelled || momentumPhase == momentumPhaseEnd
        guard isEnd else { return nil }

        for field in scrollDeltaFields {
            event.setIntegerValueField(field, value: 0)
        }
        for field in scrollFixedDeltaFields {
            event.setDoubleValueField(field, value: 0)
        }

        return Unmanaged.passUnretained(event)
    }

    private static func handleGesture(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        // Let ends through, so apps don't stay mid-zoom
        let phase = CGEventField.GesturePhase(rawValue: event.getIntegerValueField(.gesturePhase))
        if phase == .ended || phase == .cancelled {
            return Unmanaged.passUnretained(event)
        }

        return nil
    }
}
