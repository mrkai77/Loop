//
//  WindowTransformAnimation.swift
//  Loop
//
//  Created by Kai Azim on 2023-09-02.
//

import SwiftUI

private enum ResizeAnimationConstraint {
    case none
    case fixedAxes(width: Bool, height: Bool)
    case fixedAspectRatio(CGFloat)

    var hasFixedAxes: Bool {
        if case .fixedAxes = self {
            return true
        }

        return false
    }
}

/// Animate a window's resize!
@MainActor
final class WindowTransformAnimation: NSAnimation {
    private var targetFrame: CGRect
    private let originalFrame: CGRect
    private let window: Window
    private let writer: FrameWriter
    private let bounds: CGRect
    private let shouldSetSize: Bool
    private let targetEdges: Edge.Set
    private let stationaryAxes: (x: Bool, y: Bool)
    private var didCallCompletionHandler: Bool = false
    private let completionHandler: (Error?) -> ()

    private var lastWindowFrame: CGRect = .zero
    private var constraint: ResizeAnimationConstraint = .none

    // Using ids for each ongoing animation, we can cancel as a new window animation is started for that specific window
    private var id: UUID = .init()
    static var activeAnimationByWindow: [CGWindowID: WindowTransformAnimation] = [:]

    init(
        _ newRect: CGRect,
        window: Window,
        writer: FrameWriter,
        bounds: CGRect,
        shouldSetSize: Bool,
        completionHandler: @escaping (Error?) -> ()
    ) {
        let originalFrame = window.frame
        self.targetFrame = newRect
        self.originalFrame = originalFrame
        self.window = window
        self.writer = writer
        self.bounds = bounds
        self.shouldSetSize = shouldSetSize
        self.targetEdges = newRect.getEdgesTouchingBounds(bounds)
        self.stationaryAxes = (
            x: newRect.origin.x.approximatelyEquals(to: originalFrame.origin.x, tolerance: 2) &&
                newRect.width.approximatelyEquals(to: originalFrame.width, tolerance: 2),
            y: newRect.origin.y.approximatelyEquals(to: originalFrame.origin.y, tolerance: 2) &&
                newRect.height.approximatelyEquals(to: originalFrame.height, tolerance: 2)
        )
        self.completionHandler = completionHandler
        super.init(duration: 0.3, animationCurve: .easeOut)
        self.frameRate = Float(NSScreen.main?.displayMode?.refreshRate ?? 60.0)
        self.animationBlockingMode = .nonblocking
        self.lastWindowFrame = originalFrame

        if let existing = Self.activeAnimationByWindow[window.cgWindowID] {
            existing.cancel()
        }

        Self.activeAnimationByWindow[window.cgWindowID] = self
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func start() {
        super.start()
    }

    override func stop() {
        super.stop()
        Self.activeAnimationByWindow[window.cgWindowID] = nil

        if !didCallCompletionHandler {
            completionHandler(nil)
        }

        didCallCompletionHandler = true
    }

    func cancel() {
        super.stop()
        Self.activeAnimationByWindow[window.cgWindowID] = nil

        if !didCallCompletionHandler {
            completionHandler(CancellationError())
        }

        didCallCompletionHandler = true
    }

    override var currentProgress: NSAnimation.Progress {
        didSet {
            apply(progress: currentValue)

            if currentValue >= 1.0 {
                stop()
            }
        }
    }

    private func apply(progress: Float) {
        let value = CGFloat(1.0 - pow(1.0 - progress, 3))

        let requestedFrame = CGRect(
            x: round(originalFrame.origin.x + value * (targetFrame.origin.x - originalFrame.origin.x)),
            y: round(originalFrame.origin.y + value * (targetFrame.origin.y - originalFrame.origin.y)),
            width: round(originalFrame.size.width + value * (targetFrame.size.width - originalFrame.size.width)),
            height: round(originalFrame.size.height + value * (targetFrame.size.height - originalFrame.size.height))
        )

        var newFrame = requestedFrame
        var currentOrigin = lastWindowFrame.origin
        let resizeTolerance: CGFloat = 2

        let sizeToSet = sizeToSet(for: requestedFrame)

        if shouldSetSize, !lastWindowFrame.size.approximatelyEqual(to: sizeToSet, tolerance: resizeTolerance) {
            let growsHorizontally = sizeToSet.width > lastWindowFrame.width + resizeTolerance
            let growsVertically = sizeToSet.height > lastWindowFrame.height + resizeTolerance

            if let preResizeOrigin = predictedPreResizeOrigin(
                requestedFrame: requestedFrame,
                sizeToSet: sizeToSet
            ) {
                if !lastWindowFrame.origin.approximatelyEqual(to: preResizeOrigin, tolerance: 1) {
                    writer.setPosition(preResizeOrigin)
                    currentOrigin = preResizeOrigin
                }
            } else if growsHorizontally || growsVertically {
                var preResizeOrigin = lastWindowFrame.origin
                if growsHorizontally {
                    preResizeOrigin.x = requestedFrame.origin.x
                }
                if growsVertically {
                    preResizeOrigin.y = requestedFrame.origin.y
                }
                if !lastWindowFrame.origin.approximatelyEqual(to: preResizeOrigin, tolerance: 1) {
                    writer.setPosition(preResizeOrigin)
                    currentOrigin = preResizeOrigin
                }
            }

            writer.setSize(sizeToSet)
            if bounds != .zero {
                let actualFrame = window.frame
                updateConstraint(actualFrame: actualFrame, requestedFrame: requestedFrame, tolerance: resizeTolerance)

                if WindowEngine.shouldAnchorDuringAnimation(
                    actualSize: actualFrame.size,
                    requestedSize: requestedFrame.size
                ) {
                    newFrame = animationAnchoredFrame(
                        for: actualFrame.size,
                        within: requestedFrame,
                        currentOrigin: currentOrigin
                    )
                } else {
                    newFrame = CGRect(
                        origin: requestedFrame.origin,
                        size: actualFrame.size
                    )
                    .pushInside(bounds)
                }
            }
        } else if bounds != .zero, constraint.hasFixedAxes {
            newFrame = animationAnchoredFrame(
                for: lastWindowFrame.size,
                within: requestedFrame,
                currentOrigin: lastWindowFrame.origin
            )
        } else if bounds != .zero {
            newFrame = newFrame.pushInside(bounds)
        }

        if !currentOrigin.approximatelyEqual(to: newFrame.origin, tolerance: 1) {
            writer.setPosition(newFrame.origin)
        }

        lastWindowFrame = window.frame
    }

    private func animationAnchoredFrame(
        for actualSize: CGSize,
        within requestedFrame: CGRect,
        currentOrigin: CGPoint
    ) -> CGRect {
        var frame = WindowEngine.anchoredFrame(
            for: actualSize,
            within: requestedFrame,
            targetEdges: targetEdges,
            bounds: bounds
        )

        if stationaryAxes.x, actualSize.width.approximatelyEquals(to: requestedFrame.width, tolerance: 2) {
            frame.origin.x = currentOrigin.x
        }
        if stationaryAxes.y, actualSize.height.approximatelyEquals(to: requestedFrame.height, tolerance: 2) {
            frame.origin.y = currentOrigin.y
        }

        return frame.pushInside(bounds)
    }

    private func sizeToSet(for requestedFrame: CGRect) -> CGSize {
        switch constraint {
        case .none, .fixedAspectRatio:
            requestedFrame.size
        case let .fixedAxes(width, height):
            CGSize(
                width: width ? lastWindowFrame.width : requestedFrame.width,
                height: height ? lastWindowFrame.height : requestedFrame.height
            )
        }
    }

    private func predictedPreResizeOrigin(requestedFrame: CGRect, sizeToSet: CGSize) -> CGPoint? {
        guard case let .fixedAspectRatio(aspectRatio) = constraint,
              bounds != .zero else {
            return nil
        }

        let predictedSize = sizeToSet.fitting(aspectRatio: aspectRatio)
        return animationAnchoredFrame(
            for: predictedSize,
            within: requestedFrame,
            currentOrigin: lastWindowFrame.origin
        )
        .origin
    }

    private func updateConstraint(actualFrame: CGRect, requestedFrame: CGRect, tolerance: CGFloat) {
        let acceptedSize = actualFrame.size
        guard acceptedSize.width <= requestedFrame.width + tolerance,
              acceptedSize.height <= requestedFrame.height + tolerance else {
            constraint = .none
            return
        }

        let requestedWidthChanged = !requestedFrame.width.approximatelyEquals(
            to: lastWindowFrame.width,
            tolerance: tolerance
        )
        let requestedHeightChanged = !requestedFrame.height.approximatelyEquals(
            to: lastWindowFrame.height,
            tolerance: tolerance
        )

        if requestedWidthChanged, requestedHeightChanged,
           hasStableAspectRatio(acceptedSize, comparedTo: lastWindowFrame.size),
           WindowEngine.shouldAnchorDuringAnimation(
               actualSize: acceptedSize,
               requestedSize: requestedFrame.size,
               tolerance: tolerance
           ), acceptedSize.width > 0, acceptedSize.height > 0 {
            constraint = .fixedAspectRatio(acceptedSize.width / acceptedSize.height)
            return
        }

        if case .fixedAxes = constraint {
            return
        }

        let shouldLockWidth = shouldLockSizeAxis(
            actual: actualFrame.width,
            previous: lastWindowFrame.width,
            requested: requestedFrame.width,
            tolerance: tolerance
        )

        let shouldLockHeight = shouldLockSizeAxis(
            actual: actualFrame.height,
            previous: lastWindowFrame.height,
            requested: requestedFrame.height,
            tolerance: tolerance
        )

        if didSizeChange(acceptedSize, comparedTo: lastWindowFrame.size, tolerance: tolerance),
           hasStableAspectRatio(acceptedSize, comparedTo: lastWindowFrame.size),
           WindowEngine.shouldAnchorDuringAnimation(
               actualSize: acceptedSize,
               requestedSize: requestedFrame.size,
               tolerance: tolerance
           ), acceptedSize.width > 0, acceptedSize.height > 0 {
            constraint = .fixedAspectRatio(acceptedSize.width / acceptedSize.height)
            return
        }

        if shouldLockWidth || shouldLockHeight {
            constraint = .fixedAxes(width: shouldLockWidth, height: shouldLockHeight)
        }
    }

    private func didSizeChange(_ size: CGSize, comparedTo previousSize: CGSize, tolerance: CGFloat) -> Bool {
        !size.approximatelyEqual(to: previousSize, tolerance: tolerance)
    }

    private func hasStableAspectRatio(_ size: CGSize, comparedTo previousSize: CGSize) -> Bool {
        guard size.width > 0, size.height > 0,
              previousSize.width > 0, previousSize.height > 0 else {
            return false
        }

        return (size.width / size.height).approximatelyEquals(
            to: previousSize.width / previousSize.height,
            tolerance: 0.01
        )
    }

    private func shouldLockSizeAxis(
        actual: CGFloat,
        previous: CGFloat,
        requested: CGFloat,
        tolerance: CGFloat
    ) -> Bool {
        let requestedChanged = !requested.approximatelyEquals(to: previous, tolerance: tolerance)
        let actualDidNotChange = actual.approximatelyEquals(to: previous, tolerance: tolerance)
        let constrainedBelowRequest = actual <= requested + tolerance

        return requestedChanged && actualDidNotChange && constrainedBelowRequest
    }
}
