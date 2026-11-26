//
//  AutomationQueue.swift
//  Loop
//
//  Created by Kami on 06/03/2025.
//

import Foundation
import os
import Scribe

/// Runs automation commands from the URL scheme and `loop-cli` one at a time, in the order they arrive,
/// so two of them can't pick the same next cycle step
@Loggable
@MainActor
final class AutomationQueue {
    typealias Perform = @MainActor (AutomationRequest) async -> LoopAutomationResponse

    static let shared = AutomationQueue { request in
        await AutomationRunner().response(for: request)
    }

    private let perform: Perform
    private var lastCommand: Task<(), Never>?

    init(perform: @escaping Perform) {
        self.perform = perform
    }

    /// Time spent waiting for earlier commands counts, so a caller never waits past `deadline`.
    /// A command whose caller already gave up is skipped instead of running late.
    func run(
        _ request: AutomationRequest,
        deadline: ContinuousClock.Instant = .now + LoopAutomationJSON.commandTimeout
    ) async -> LoopAutomationResponse {
        let previousCommand = lastCommand
        let command = Task { @MainActor in
            await previousCommand?.value

            guard ContinuousClock.now < deadline else {
                self.log.warn("Skipped \(request.title), as it timed out before it started")
                return LoopAutomationResponse.failure(.timeout, message: "Command timed out before it started, so it didn’t run")
            }

            return await self.perform(request)
        }
        lastCommand = Task { _ = await command.value }

        let response = await Self.value(of: command, before: deadline)
        return response ?? .failure(.timeout, message: "Command timed out, so the action may still complete")
    }

    /// `nil` if `task` doesn't finish in time. It isn't cancelled, as cancelling could stop a resize partway through.
    private static func value<T: Sendable>(of task: Task<T, Never>, before deadline: ContinuousClock.Instant) async -> T? {
        await withCheckedContinuation { continuation in
            let race = TimeoutRace(continuation)

            let timer = Task {
                try? await Task.sleep(until: deadline, clock: .continuous)
                race.finish(with: nil)
            }

            Task {
                await race.finish(with: task.value)
                timer.cancel()
            }
        }
    }
}

private final class TimeoutRace<T: Sendable>: Sendable {
    private let continuation: OSAllocatedUnfairLock<CheckedContinuation<T?, Never>?>

    init(_ continuation: CheckedContinuation<T?, Never>) {
        self.continuation = OSAllocatedUnfairLock(initialState: continuation)
    }

    /// Takes the continuation under the lock and resumes it after, so resuming never runs while the lock is held
    func finish(with value: T?) {
        let continuation = continuation.withLock { state in
            defer { state = nil }
            return state
        }

        continuation?.resume(returning: value)
    }
}
