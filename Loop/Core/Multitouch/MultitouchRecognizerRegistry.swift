//
//  MultitouchRecognizerRegistry.swift
//  Loop
//
//  Created by Kai Azim on 2026-07-06.
//

import Foundation
import Scribe
import Subsurface

@Loggable
@MainActor
final class MultitouchRecognizerRegistry {
    typealias EventHandler = @MainActor (SubsurfaceGestureEvent, Int) async -> ()

    struct Entry {
        let recognizer: SubsurfaceGestureRecognizer
        let session: MultitouchGestureSession
        var task: Task<(), Never>?
        var radialMenuGesture: GestureBinding?
        var directionalGestures: [GestureBinding]
        var magnifyOutGesture: GestureBinding?
        var magnifyInGesture: GestureBinding?

        static func categorize(
            _ gestures: [GestureBinding]
        ) -> (radial: GestureBinding?, directionals: [GestureBinding], magnifyOut: GestureBinding?, magnifyIn: GestureBinding?) {
            let radial = gestures.first { $0.kind == .radialMenu }
            let gesturesByPriority = gestures.sortedByActionability
            let directionals = gesturesByPriority.filter(\.kind.isDirectionalSwipe)
            let magnifyOut = gesturesByPriority.first { $0.kind == .magnifyOut }
            let magnifyIn = gesturesByPriority.first { $0.kind == .magnifyIn }
            return (radial, directionals, magnifyOut, magnifyIn)
        }
    }

    struct StopResult {
        let didOpenLoopWithGesture: Bool
        let didAcquireGestureBlocker: Bool
    }

    private let gestureMonitor: SubsurfaceMonitor
    private let handleEvent: EventHandler
    private var entries: [Int: Entry] = [:]
    /// Logged only when they change, as rebuilds also follow unrelated keybind edits
    private var conflictingGestureIDs: Set<UUID> = []

    init(
        gestureMonitor: SubsurfaceMonitor,
        handleEvent: @escaping EventHandler
    ) {
        self.gestureMonitor = gestureMonitor
        self.handleEvent = handleEvent
    }

    func entry(for fingerCount: Int) -> Entry? {
        entries[fingerCount]
    }

    func session(for fingerCount: Int) -> MultitouchGestureSession? {
        entries[fingerCount]?.session
    }

    func rebuild(with gestures: [GestureBinding]) -> [StopResult] {
        logConflictingGestures(in: gestures)

        let gesturesByFingerCount = Dictionary(grouping: GestureBinding.activeGestures(in: gestures), by: \.fingerCount)
        let neededFingerCounts = Set(gesturesByFingerCount.keys)

        var stopResults: [StopResult] = []
        for fingerCount in Array(entries.keys) where !neededFingerCounts.contains(fingerCount) {
            if let stopResult = stopRecognizer(for: fingerCount) {
                stopResults.append(stopResult)
            }
            entries.removeValue(forKey: fingerCount)
        }

        for (fingerCount, gestures) in gesturesByFingerCount {
            let (radial, directionals, magnifyOut, magnifyIn) = Entry.categorize(gestures)
            if entries[fingerCount] == nil {
                startRecognizer(for: fingerCount, radial: radial, directionals: directionals, magnifyOut: magnifyOut, magnifyIn: magnifyIn)
            } else {
                entries[fingerCount]?.radialMenuGesture = radial
                entries[fingerCount]?.directionalGestures = directionals
                entries[fingerCount]?.magnifyOutGesture = magnifyOut
                entries[fingerCount]?.magnifyInGesture = magnifyIn
            }
        }

        return stopResults
    }

    func stopAll() -> [StopResult] {
        var stopResults: [StopResult] = []
        for fingerCount in Array(entries.keys) {
            if let stopResult = stopRecognizer(for: fingerCount) {
                stopResults.append(stopResult)
            }
        }
        entries.removeAll()
        return stopResults
    }

    func contains(session: MultitouchGestureSession, for fingerCount: Int) -> Bool {
        entries[fingerCount]?.session === session
    }

    var hasRecognizers: Bool {
        !entries.isEmpty
    }

    private func logConflictingGestures(in gestures: [GestureBinding]) {
        let conflictingIDs = GestureBinding.conflictingActionableIDs(in: gestures)
        guard conflictingIDs != conflictingGestureIDs else { return }
        conflictingGestureIDs = conflictingIDs

        guard !conflictingIDs.isEmpty else {
            log.info("No gestures are disabled by finger count conflicts")
            return
        }

        let conflictingGestures = gestures
            .filter { conflictingIDs.contains($0.id) }
            .map { "\($0.fingerCount)-finger \($0.kind)" }
        log.warn("Disabled gestures that conflict on the same finger count: \(conflictingGestures.joined(separator: ", "))")
    }

    private func startRecognizer(
        for fingerCount: Int,
        radial: GestureBinding?,
        directionals: [GestureBinding],
        magnifyOut: GestureBinding?,
        magnifyIn: GestureBinding?
    ) {
        let recognizer = SubsurfaceGestureRecognizer(
            fingerCount: fingerCount,
            recognizedGestureTypes: [.swipe, .magnify],
            requiresExactFingerCountToContinue: true
        )

        entries[fingerCount] = Entry(
            recognizer: recognizer,
            session: MultitouchGestureSession(),
            task: nil,
            radialMenuGesture: radial,
            directionalGestures: directionals,
            magnifyOutGesture: magnifyOut,
            magnifyInGesture: magnifyIn
        )

        let task = Task { [weak self] in
            guard let self else { return }
            for await event in recognizer.events(from: gestureMonitor) {
                guard !Task.isCancelled else { break }
                await handleEvent(event, fingerCount)
            }
        }
        entries[fingerCount]?.task = task
    }

    private func stopRecognizer(for fingerCount: Int) -> StopResult? {
        guard let entry = entries[fingerCount] else { return nil }
        entry.task?.cancel()
        entry.recognizer.reset()
        return StopResult(
            didOpenLoopWithGesture: entry.session.didOpenLoopWithThisGesture,
            didAcquireGestureBlocker: entry.session.releaseGestureBlocker()
        )
    }
}

private extension Array where Element == GestureBinding {
    var sortedByActionability: [GestureBinding] {
        sorted {
            if $0.resolvesToNoAction != $1.resolvesToNoAction {
                return !$0.resolvesToNoAction
            }

            return false
        }
    }
}
