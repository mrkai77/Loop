//
//  EventTapThread.swift
//  Loop
//
//  Created by Kai Azim on 2026-05-06.
//

import CoreFoundation
import Foundation
import os

/// Owns the run loop used by global event taps.
final class EventTapThread: Thread {
    static let shared = EventTapThread(name: "\(Bundle.main.bundleID).EventTapThread")

    private let hasStarted = OSAllocatedUnfairLock(initialState: false)
    private let runLoopReady = DispatchGroup()
    private var eventTapRunLoop: CFRunLoop?

    var runLoop: CFRunLoop {
        let shouldStart = hasStarted.withLock { hasStarted in
            defer { hasStarted = true }
            return !hasStarted
        }

        if shouldStart {
            start()
        }

        runLoopReady.wait()

        guard let eventTapRunLoop else {
            preconditionFailure("EventTapThread failed to publish its run loop")
        }

        return eventTapRunLoop
    }

    private init(name: String) {
        runLoopReady.enter()
        super.init()
        self.name = name
        qualityOfService = .userInteractive
    }

    override func main() {
        eventTapRunLoop = CFRunLoopGetCurrent()

        var sourceContext = CFRunLoopSourceContext()
        let keepAliveSource = CFRunLoopSourceCreate(
            kCFAllocatorDefault,
            0,
            &sourceContext
        )

        if let eventTapRunLoop, let keepAliveSource {
            CFRunLoopAddSource(eventTapRunLoop, keepAliveSource, .commonModes)
        }

        runLoopReady.leave()
        CFRunLoopRun()
    }
}
