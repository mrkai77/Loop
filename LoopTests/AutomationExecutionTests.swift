//
//  AutomationExecutionTests.swift
//  LoopTests
//
//  Created by Kai Azim on 2026-11-25.
//

import Foundation
@testable import Loop
import Testing

struct LoopTargetOptionsTests {
    @Test(arguments: [
        LoopTargetOptions(),
        LoopTargetOptions(windowID: 12),
        LoopTargetOptions(bundleID: "com.apple.Safari", screenID: 3),
        LoopTargetOptions(windowID: 7, screenID: 1)
    ])
    func optionsSurviveTheTripFromTheCLIToLoop(options: LoopTargetOptions) throws {
        #expect(try LoopTargetOptions(queryItems: options.queryItems) == options)
    }
}

@MainActor
struct AutomationQueueTests {
    private let request = AutomationRequest(command: .route(.list(.windows)))

    @Test func commandsRunInTheOrderTheyArrive() async {
        var order: [Int] = []
        var calls = 0
        let queue = AutomationQueue { _ in
            calls += 1
            let call = calls
            if call == 1 {
                try? await Task.sleep(for: .milliseconds(100))
            }
            order.append(call)
            return LoopAutomationResponse(result: .windowList(LoopWindowListResult(windows: [])))
        }

        async let first = queue.run(request)
        try? await Task.sleep(for: .milliseconds(10))
        async let second = queue.run(request)
        _ = await (first, second)

        #expect(order == [1, 2])
    }

    @Test func aSlowCommandTimesOut() async {
        let queue = AutomationQueue { _ in
            try? await Task.sleep(for: .milliseconds(300))
            return LoopAutomationResponse(result: .windowList(LoopWindowListResult(windows: [])))
        }

        let response = await queue.run(request, deadline: .now + .milliseconds(50))
        #expect(response.error?.code == .timeout)
    }

    @Test func aCommandWhoseCallerGaveUpDoesntRun() async {
        var ran = 0
        let queue = AutomationQueue { _ in
            ran += 1
            try? await Task.sleep(for: .milliseconds(200))
            return LoopAutomationResponse(result: .windowList(LoopWindowListResult(windows: [])))
        }

        async let blocking = queue.run(request)
        try? await Task.sleep(for: .milliseconds(10))
        let stale = await queue.run(request, deadline: .now + .milliseconds(50))
        _ = await blocking
        // Lets the skipped command reach its deadline check
        _ = await queue.run(request)

        #expect(stale.error?.code == .timeout)
        #expect(ran == 2)
    }
}

@MainActor
struct AutomationRunnerTests {
    @Test func aCycleStopsAtAnotherScreenSwitch() {
        let next = WindowAction(.nextScreen)
        let cycle = WindowAction(cycle: [next, WindowAction(.previousScreen)])
        #expect(AutomationRunner.cycleAction(after: next, in: cycle) == nil)
    }

    @Test func aCycleGoesOnToItsNextStepAfterAScreenSwitch() {
        let next = WindowAction(.nextScreen)
        let cycle = WindowAction(cycle: [next, WindowAction(.leftHalf)])
        #expect(AutomationRunner.cycleAction(after: next, in: cycle)?.direction == .leftHalf)
    }
}
