@testable import Loop
import SwiftUI
import Testing

struct InitialWindowPlacementTests {
    @Test func frameStaysReachableOnASecondaryDisplay() {
        let bounds = CGRect(x: -1600, y: 25, width: 1600, height: 1000)
        let oversized = CGRect(x: -1800, y: -100, width: 2000, height: 1200)
        #expect(InitialWindowFrames.constrain(oversized, to: bounds) == bounds)
        #expect(WindowEngine.anchoredFrame(for: oversized.size, within: bounds, targetEdges: [.trailing, .bottom], bounds: bounds)
            == CGRect(x: -1600, y: 25, width: 2000, height: 1200))
        #expect(InitialWindowFrames.constrain(CGRect(x: 100, y: 900, width: 800, height: 600), to: bounds)
            == CGRect(x: -800, y: 425, width: 800, height: 600))
        #expect(InitialWindowFrames.constrain(CGRect(x: 0, y: 0, width: -800, height: 600), to: bounds) == nil)
    }

    @Test @MainActor func retriesAnInitiallyNonresizableWindow() async {
        var attempts = 0
        let ready = await InitialWindowFrames.waitUntilReady {
            attempts += 1
            return attempts == 1 ? .wait : .ready
        }
        #expect(ready)
        #expect(attempts == 2)
    }

    @Test @MainActor func skipStopsImmediatelyAndWaitingIsBounded() async {
        var skipped = 0
        let shouldSkip = await InitialWindowFrames.waitUntilReady {
            skipped += 1
            return .skip
        }
        var waited = 0
        let neverReady = await InitialWindowFrames.waitUntilReady {
            waited += 1
            return .wait
        }
        #expect(!shouldSkip && skipped == 1)
        #expect(!neverReady && waited == 4)
    }

    @Test @MainActor func cancellationStopsPendingPlacement() async {
        var attempts = 0
        var task: Task<Bool, Never>?
        await withCheckedContinuation { continuation in
            task = Task {
                await InitialWindowFrames.waitUntilReady {
                    attempts += 1
                    if attempts == 1 { continuation.resume() }
                    return attempts == 1 ? .wait : .ready
                }
            }
        }
        task?.cancel()
        let ready = await task?.value
        #expect(ready == false)
        #expect(attempts == 1)
    }
}
