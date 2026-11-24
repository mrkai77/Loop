//
//  InitialWindowPlacementTests.swift
//  LoopTests
//

@testable import Loop
import SwiftUI
import Testing

struct InitialWindowPlacementTests {
    @Test func coordinatePlacementKeepsItsSizeAtTheRightEdge() {
        let bounds = CGRect(x: -1000, y: 0, width: 1000, height: 800)
        let action = WindowAction(
            .custom,
            keybind: [],
            unit: .percentage,
            width: 50,
            height: 50,
            xPoint: 80,
            yPoint: 0,
            positionMode: .coordinates,
            sizeMode: .custom
        )
        let context = ResizeContext(bounds: bounds, padding: .zero, action: action)
        #expect(InitialWindowFrames.placementFrame(in: context) == CGRect(x: -500, y: 0, width: 500, height: 400))
    }

    @Test(arguments: [CGSize(width: 0, height: 50), CGSize(width: 50, height: 0), .zero])
    func explicitZeroDimensionsReachTheWindowSetter(_ size: CGSize) {
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let action = WindowAction(
            .custom,
            keybind: [],
            unit: .percentage,
            width: size.width,
            height: size.height,
            positionMode: .coordinates,
            sizeMode: .custom
        )
        let context = ResizeContext(bounds: bounds, padding: .zero, action: action)
        let target = InitialWindowFrames.placementFrame(in: context)
        #expect(target?.size == CGSize(width: size.width * 10, height: size.height * 8))
    }

    @Test func frameStaysReachableOnASecondaryDisplay() {
        let bounds = CGRect(x: -1600, y: 25, width: 1600, height: 1000)
        let oversized = CGRect(x: -1800, y: -100, width: 2000, height: 1200)
        #expect(InitialWindowFrames.constrain(oversized, to: bounds) == bounds)
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
                    if attempts == 1 {
                        continuation.resume()
                    }
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
