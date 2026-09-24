//
//  PassiveEventMonitor.swift
//  Loop
//
//  Created by Kai Azim on 2025-10-12.
//

import CoreGraphics
import Scribe

/// Passive monitor that only listens to events.
/// Callback will be called on a separate thread to keep the CFMachPort's callback fast.
final class PassiveEventMonitor: BaseEventTapMonitor {
    private let eventCallback: (CGEvent) -> ()

    ///  Initializes a `PassiveEventMonitor`.
    /// - Parameters:
    ///   - name: a human-readable identifier used in log messages.
    ///   - tapLocation: the location at which this event tap will be placed.
    ///   - placement:  whether to add this monitor as a head or tail relative to other event monitors within this tap.
    ///   - events:  the events to capture within this event monitor.
    ///   - callback:  a callback to process the received event.
    init(
        _ name: String,
        tapLocation: CGEventTapLocation = .cgSessionEventTap,
        placement: CGEventTapPlacement = .tailAppendEventTap,
        events: [CGEventType],
        callback: @escaping (CGEvent) -> ()
    ) {
        self.eventCallback = callback
        super.init()

        let eventsOfInterest = events.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        let callback: CGEventTapCallBack = { _, eventType, event, refcon in
            guard let refcon else { return nil }
            let observer = Unmanaged<PassiveEventMonitor>.fromOpaque(refcon).takeUnretainedValue()

            // Tap management notifications carry a null event, so read eventType, not event.type
            if eventType == .tapDisabledByTimeout {
                if observer.isEnabled {
                    let tapRunLoop = EventTapThread.shared.runLoop
                    CFRunLoopPerformBlock(tapRunLoop, CFRunLoopMode.commonModes as CFTypeRef) {
                        observer.attemptRestart()
                    }
                    CFRunLoopWakeUp(tapRunLoop)
                }
                return nil
            }

            if eventType == .tapDisabledByUserInput {
                return nil
            }

            guard unsafeBitCast(event, to: UnsafeRawPointer?.self) != nil else { return nil }
            observer.eventCallback(event)
            return Unmanaged.passUnretained(event)
        }

        let userInfo = Unmanaged.passRetained(self).toOpaque()

        if let eventTap = CGEvent.tapCreate(
            tap: tapLocation,
            place: placement,
            options: .listenOnly,
            eventsOfInterest: eventsOfInterest,
            callback: callback,
            userInfo: userInfo
        ) {
            setupRunLoopSource(eventTap: eventTap, readableIdentifier: name)
        } else {
            log.info("Failed to create event tap")
            Unmanaged.passUnretained(self).release()
        }
    }
}
