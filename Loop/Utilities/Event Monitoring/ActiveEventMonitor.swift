//
//  ActiveEventMonitor.swift
//  Loop
//
//  Created by Kai Azim on 2025-10-12.
//

import CoreGraphics
import Scribe

/// Active event monitor that can process and alter events when needed.
final class ActiveEventMonitor: BaseEventTapMonitor {
    private let eventCallback: (CGEvent) -> Unmanaged<CGEvent>?

    enum EventHandling {
        case forward
        case ignore
    }

    /// Initializes an `ActiveEventMonitor`, with a simplified callback.
    /// - Parameters:
    ///   - name: a human-readable identifier used in log messages.
    ///   - tapLocation: the location at which this event tap will be placed.
    ///   - placement: whether to add this monitor as a head or tail relative to other event monitors within this tap.
    ///   - events: the events to capture within this event monitor.
    ///   - callback: a callback to process received events. Return `forward` to pass the event along, `ignore` to block the event from reaching downstream receivers.
    convenience init(
        _ name: String,
        tapLocation: CGEventTapLocation = .cgSessionEventTap,
        placement: CGEventTapPlacement = .tailAppendEventTap,
        events: [CGEventType],
        callback: @escaping (CGEvent) -> EventHandling
    ) {
        self.init(
            name,
            tapLocation: tapLocation,
            placement: placement,
            events: events,
            callback: { callback($0) == .forward ? Unmanaged.passUnretained($0) : nil }
        )
    }

    /// Initializes an `ActiveEventMonitor`.
    /// - Parameters:
    ///   - name: a human-readable identifier used in log messages.
    ///   - tapLocation: the location at which this event tap will be placed.
    ///   - placement: whether to add this monitor as a head or tail relative to other event monitors within this tap.
    ///   - events: the events to capture within this event monitor.
    ///   - callback: a callback to process and potentially alter received events.
    init(
        _ name: String,
        tapLocation: CGEventTapLocation = .cgSessionEventTap,
        placement: CGEventTapPlacement = .tailAppendEventTap,
        events: [CGEventType],
        callback: @escaping (CGEvent) -> Unmanaged<CGEvent>?
    ) {
        self.eventCallback = callback
        super.init()

        let eventsOfInterest = events.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        let callback: CGEventTapCallBack = { _, eventType, event, refcon in
            guard let refcon else { return nil }
            let observer = Unmanaged<ActiveEventMonitor>.fromOpaque(refcon).takeUnretainedValue()

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
            return observer.handleEvent(event: event)
        }

        let userInfo = Unmanaged.passRetained(self).toOpaque()

        if let eventTap = CGEvent.tapCreate(
            tap: tapLocation,
            place: placement,
            options: .defaultTap,
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

    private func handleEvent(event: CGEvent) -> Unmanaged<CGEvent>? {
        eventCallback(event)
    }
}
