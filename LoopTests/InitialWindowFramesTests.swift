import CoreGraphics
@testable import Loop
import Testing

struct InitialWindowFramesTests {
    private let bounds = CGRect(x: -1600, y: 25, width: 1600, height: 1000)
    private let currentSize = CGSize(width: 900, height: 700)

    @Test func existingWindowsAreOnlyABaseline() {
        var windows = InitialWindowTracker(existing: [1, 2])
        let firstExisting = windows.insert(1)
        let secondExisting = windows.insert(2)
        let newWindow = windows.insert(3)
        let duplicate = windows.insert(3) // Enumeration and notification for the same launch window.
        windows.remove(3)
        let reused = windows.insert(3) // Identity reused after destruction.
        #expect(!firstExisting)
        #expect(!secondExisting)
        #expect(newWindow)
        #expect(!duplicate)
        #expect(reused)
    }

    @Test func literalPixelsAreNotScaledLikeAnEditorPreview() {
        let action = WindowAction(
            .custom,
            keybind: [],
            unit: .pixels,
            anchor: .bottomRight,
            width: 800,
            height: 600,
            positionMode: .generic,
            sizeMode: .custom
        )
        #expect(InitialWindowFrames.frame(for: action, bounds: bounds, currentSize: currentSize)
            == CGRect(x: -800, y: 425, width: 800, height: 600))
    }

    @Test func percentagesUseTheCurrentDisplaysUsableBounds() {
        let action = InitialWindowFrames.defaultAction(name: "Example")
        #expect(InitialWindowFrames.frame(for: action, bounds: bounds, currentSize: currentSize)
            == CGRect(x: -1400, y: 150, width: 1200, height: 750))
    }

    @Test func coordinatesAreRelativeToTheDisplayOrigin() {
        let action = WindowAction(
            .custom,
            keybind: [],
            unit: .pixels,
            width: 400,
            height: 300,
            xPoint: 100,
            yPoint: 50,
            positionMode: .coordinates,
            sizeMode: .custom
        )
        #expect(InitialWindowFrames.frame(for: action, bounds: bounds, currentSize: currentSize)
            == CGRect(x: -1500, y: 75, width: 400, height: 300))
    }

    @Test func acceptedMinimumSizeIsReanchored() {
        let action = WindowAction(
            .custom,
            keybind: [],
            unit: .pixels,
            anchor: .bottomRight,
            width: 300,
            height: 200,
            positionMode: .generic,
            sizeMode: .custom
        )
        #expect(InitialWindowFrames.frame(
            for: action,
            bounds: bounds,
            currentSize: currentSize,
            resizedSize: CGSize(width: 600, height: 400)
        )
            == CGRect(x: -600, y: 625, width: 600, height: 400))
    }

    @Test func anOversizedMinimumKeepsTheTopLeftReachable() {
        let action = InitialWindowFrames.defaultAction(name: "Example")
        #expect(InitialWindowFrames.frame(
            for: action,
            bounds: bounds,
            currentSize: currentSize,
            resizedSize: CGSize(width: 2000, height: 1200)
        )
            == CGRect(x: -1600, y: 25, width: 2000, height: 1200))
    }

    @Test func sharedGeometryStillSupportsInteractiveSizeModes() {
        var action = InitialWindowFrames.defaultAction(name: "Example")
        action.sizeMode = .preserveSize
        #expect(WindowFrameResolver.customFrame(for: action, bounds: bounds, currentSize: currentSize)
            == CGRect(x: -1250, y: 175, width: 900, height: 700))
        action.sizeMode = .initialSize
        #expect(WindowFrameResolver.customFrame(
            for: action,
            bounds: bounds,
            currentSize: currentSize,
            initialSize: CGSize(width: 800, height: 600)
        )
            == CGRect(x: -1200, y: 225, width: 800, height: 600))
    }

    @Test func coordinatesOutsideTheDisplayAreClamped() {
        let action = WindowAction(
            .custom,
            keybind: [],
            unit: .percentage,
            width: 50,
            height: 50,
            xPoint: 100,
            yPoint: -50,
            positionMode: .coordinates,
            sizeMode: .custom
        )
        #expect(InitialWindowFrames.frame(for: action, bounds: bounds, currentSize: currentSize)
            == CGRect(x: -800, y: 25, width: 800, height: 500))
    }

    @Test func invalidAndDynamicActionsAreRejected() {
        var action = InitialWindowFrames.defaultAction(name: "Example")
        action.width = .nan
        #expect(InitialWindowFrames.frame(for: action, bounds: bounds, currentSize: currentSize) == nil)
        action.width = 0
        #expect(InitialWindowFrames.frame(for: action, bounds: bounds, currentSize: currentSize) == nil)
        action.width = 75
        action.sizeMode = .initialSize
        #expect(InitialWindowFrames.frame(for: action, bounds: bounds, currentSize: currentSize) == nil)
        #expect(InitialWindowFrames.frame(for: .init(.maximize), bounds: bounds, currentSize: currentSize) == nil)
    }
}
