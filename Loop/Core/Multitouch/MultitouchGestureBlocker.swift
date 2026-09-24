//
//  MultitouchGestureBlocker.swift
//  Loop
//
//  Created by Kai Azim on 2026-04-05.
//

import AppKit
import Scribe

/// Reference-counted because the blocker is shared across in-flight
/// gestures: one gesture ending mustn't disable blocking for others still
/// active. `start()` is also idempotent so duplicate calls don't leak the
/// previous `ActiveEventMonitor` (it self-retains via `Unmanaged.passRetained`).
@Loggable
final class MultitouchGestureBlocker {
    private var monitor: ActiveEventMonitor?
    private var activeCount: Int = 0

    func start() {
        if monitor != nil {
            activeCount += 1
            return
        }

        log.info("Starting gesture blocker")

        let eventTypes: [CGEventType] = [
            .scrollWheel,
            CGEventType(rawValue: UInt32(NSEvent.EventType.gesture.rawValue)),
            CGEventType(rawValue: UInt32(NSEvent.EventType.rotate.rawValue)),
            CGEventType(rawValue: UInt32(NSEvent.EventType.swipe.rawValue)),
            CGEventType(rawValue: UInt32(NSEvent.EventType.smartMagnify.rawValue))
        ].compactMap(\.self)

        let newMonitor = ActiveEventMonitor("gesture_blocker", events: eventTypes) { _ in .ignore }
        newMonitor.start()

        guard newMonitor.isEnabled else {
            log.warn("Failed to start gesture blocker")
            newMonitor.stop()
            return
        }

        monitor = newMonitor
        activeCount = 1
    }

    func stop() {
        guard let monitor else { return }

        activeCount -= 1
        guard activeCount == 0 else { return }

        monitor.stop()
        self.monitor = nil

        log.info("Stopped gesture blocker")
    }
}
