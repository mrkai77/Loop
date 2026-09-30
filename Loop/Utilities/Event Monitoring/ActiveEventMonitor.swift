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
    private let eventCallback: (CGEventTapProxy, CGEvent) -> Unmanaged<CGEvent>?

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
    convenience init(
        _ name: String,
        tapLocation: CGEventTapLocation = .cgSessionEventTap,
        placement: CGEventTapPlacement = .tailAppendEventTap,
        events: [CGEventType],
        callback: @escaping (CGEvent) -> Unmanaged<CGEvent>?
    ) {
        self.init(
            name,
            tapLocation: tapLocation,
            placement: placement,
            events: events,
            proxyCallback: { _, event in callback(event) }
        )
    }

    /// Initializes an `ActiveEventMonitor` whose callback also receives the tap proxy.
    /// The proxy is only valid for the duration of the callback, and can be used with `CGEventTapPostEvent`
    /// to post events from this tap's position, ahead of the event currently being processed.
    /// - Parameters:
    ///   - name: a human-readable identifier used in log messages.
    ///   - tapLocation: the location at which this event tap will be placed.
    ///   - placement: whether to add this monitor as a head or tail relative to other event monitors within this tap.
    ///   - events: the events to capture within this event monitor.
    ///   - proxyCallback: a callback to process and potentially alter received events, called on `EventTapThread`.
    init(
        _ name: String,
        tapLocation: CGEventTapLocation = .cgSessionEventTap,
        placement: CGEventTapPlacement = .tailAppendEventTap,
        events: [CGEventType],
        proxyCallback: @escaping (CGEventTapProxy, CGEvent) -> Unmanaged<CGEvent>?
    ) {
        self.eventCallback = proxyCallback
        super.init()

        let eventsOfInterest = events.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        let callback: CGEventTapCallBack = { proxy, eventType, event, refcon in
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
            return observer.handleEvent(proxy: proxy, event: event)
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

    private func handleEvent(proxy: CGEventTapProxy, event: CGEvent) -> Unmanaged<CGEvent>? {
        eventCallback(proxy, event)
    }
}
