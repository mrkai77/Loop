//
//  WindowFrameResolver.swift
//  Loop
//
//  Created by Kai Azim on 2026-01-20.
//

import Defaults
import Scribe
import SwiftUI

@Loggable(style: .static)
enum WindowFrameResolver {
    typealias FrameResult = (frame: CGRect, sidesToAdjust: Edge.Set?)

    /// Sync convenience that doesn't resolve window properties, nor records.
    /// Use this for UI previews, icon generation, stash frame computation, and recursive calls.
    /// - Parameters:
    ///   - action: the window action to calculate the frame for.
    ///   - window: the window to be manipulated (can be nil for UI previews).
    ///   - bounds: the boundary within which the window should be manipulated.
    /// - Returns: the computed frame (raw, without padding).
    static func getFrame(
        for action: WindowAction,
        bounds: CGRect,
        padding: PaddingConfiguration? = nil
    ) -> CGRect {
        let context = ResizeContext(window: nil, bounds: bounds, padding: padding, action: action)
        return getFrame(resizeContext: context).frame
    }

    /// Async convenience that resolves both window properties and records.
    /// Use this when the action may need record data (e.g. `.initialFrame`).
    static func getFrame(
        for action: WindowAction,
        window: Window?,
        bounds: CGRect,
        padding: PaddingConfiguration? = nil
    ) async -> CGRect {
        let context = ResizeContext(window: window, bounds: bounds, padding: padding, action: action)
        await context.refreshResolvedState()
        return getFrame(resizeContext: context).frame
    }

    /// Returns the frame for the specified window action using the provided resize context.
    /// The returned frame is non-padded. Use `PaddingConfiguration.apply(to:bounds:action:window:)` to apply padding.
    /// - Parameter resizeContext: the context containing window, screen, bounds, and tracking frame/edge adjustment state.
    /// - Returns: a tuple containing the computed frame and the sides to adjust for grow/shrink actions.
    static func getFrame(resizeContext: ResizeContext) -> FrameResult {
        let action = resizeContext.action
        let bounds = resizeContext.paddedBounds
        let direction = action.direction

        guard direction.hasTargetFrame else {
            return (CGRect(origin: bounds.center, size: .zero), nil)
        }

        var sidesToAdjust: Edge.Set? = if action.willManipulateExistingWindowFrame {
            resizeContext.sidesToAdjust
        } else {
            nil
        }

        var result: CGRect = calculateTargetFrame(
            sidesToAdjust: &sidesToAdjust,
            context: resizeContext
        )

        if result.size.width < 0 || result.size.height < 0 || !result.isFinite {
            result = CGRect(origin: bounds.center, size: .zero)
        }

        return (result, sidesToAdjust)
    }

    static func getRevealedFrame(resizeContext: ResizeContext) -> CGRect {
        resizeContext.getTargetFrame().padded
    }

    static func getRevealedFrame(for action: WindowAction, window: Window, screen: NSScreen) async -> CGRect {
        let context = ResizeContext(window: window, screen: screen, action: action)
        await context.refreshResolvedState()
        return getRevealedFrame(resizeContext: context)
    }

    static func getStashedFrame(for action: WindowAction, window: Window, screen: NSScreen, peekSize: CGFloat, maxPeekPercent: CGFloat = 0.2) async -> CGRect {
        let bounds = screen.cgSafeScreenFrame
        let revealedFrame = await getFrame(for: action, window: window, bounds: bounds)

        return getStashedFrame(
            for: action,
            revealedFrame: revealedFrame,
            bounds: bounds,
            peekSize: peekSize,
            maxPeekPercent: maxPeekPercent
        )
    }

    static func getStashedFrame(for action: WindowAction, revealedFrame: CGRect, bounds: CGRect, peekSize: CGFloat, maxPeekPercent: CGFloat = 0.2) -> CGRect {
        var frame = revealedFrame
        let minPeekSize: CGFloat = 1

        switch action.stashEdge {
        case .left, .right:
            let maxPeekSize = frame.width * maxPeekPercent
            let clampedPeekSize = max(minPeekSize, min(peekSize, maxPeekSize))

            if action.stashEdge == .left {
                frame.origin.x = bounds.minX - frame.width + clampedPeekSize
            } else {
                frame.origin.x = bounds.maxX - clampedPeekSize
            }

        case .bottom:
            let maxPeekSize = frame.height * maxPeekPercent
            let clampedPeekSize = max(minPeekSize, min(peekSize, maxPeekSize))
            frame.origin.y = bounds.maxY - clampedPeekSize

        case .none:
            break
        }

        return frame
    }
}

// MARK: - Calculators

extension WindowFrameResolver {
    /// Calculates the target frame for the specified window action based on the direction, window, bounds, and whether it is a preview.
    /// - Parameters:
    ///   - sidesToAdjust: inout parameter for tracking which edges to adjust during grow/shrink actions.
    ///   - context: the context tracking frame and edge adjustment state.
    /// - Returns: the calculated target frame for the specified window action.
    private static func calculateTargetFrame(
        sidesToAdjust: inout Edge.Set?,
        context: ResizeContext
    ) -> CGRect {
        let bounds = context.paddedBounds
        let action = context.action
        let properties = context.resolvedWindowProperties

        let direction = action.direction
        var result: CGRect = .zero

        if direction.frameMultiplyValues != nil {
            result = applyFrameMultiplyValues(for: action, to: bounds)

        } else if direction.willAdjustSize {
            // Can't grow or shrink a window that is not resizable
            if let properties, !properties.isResizable {
                return properties.frame
            }

            let frameToResizeFrom = context.lastAppliedFrame ?? context.cachedTargetFrame.raw

            // Compute which edges to adjust based on edges touching bounds
            let edgesTouchingBounds = frameToResizeFrom.getEdgesTouchingBounds(bounds)
            sidesToAdjust = .all.subtracting(edgesTouchingBounds)

            let proportional: [WindowDirection] = [.scaleUp, .scaleDown]
            result = calculateSizeAdjustment(
                for: action,
                frameToResizeFrom: frameToResizeFrom,
                bounds: bounds,
                proportionalIfPossible: proportional.contains(direction),
                sidesToAdjust: sidesToAdjust
            )

        } else if direction.willShrink || direction.willGrow {
            // Can't grow or shrink a window that is not resizable
            if let properties, !properties.isResizable {
                return properties.frame
            }

            // This allows for control over each side
            let frameToResizeFrom = context.lastAppliedFrame ?? context.cachedTargetFrame.raw

            // Compute which edges to adjust based on direction
            switch direction {
            case .shrinkTop, .growTop:
                sidesToAdjust = .top
            case .shrinkBottom, .growBottom:
                sidesToAdjust = .bottom
            case .shrinkLeft, .growLeft:
                sidesToAdjust = .leading
            case .shrinkHorizontal, .growHorizontal:
                sidesToAdjust = [.leading, .trailing]
            case .shrinkVertical, .growVertical:
                sidesToAdjust = [.top, .bottom]
            default:
                sidesToAdjust = .trailing
            }

            result = calculateSizeAdjustment(
                for: action,
                frameToResizeFrom: frameToResizeFrom,
                bounds: bounds,
                sidesToAdjust: sidesToAdjust
            )

        } else if direction.willMove {
            // Read the last applied frame (falling back to the cached target) instead of
            // `context.getTargetFrame()`. `getTargetFrame()` would recompute this very
            // context and re-enter here, recursing until the stack overflows. Matching the
            // grow/shrink branches above also keeps moves anchored to the window's actual
            // position rather than a theoretical (possibly clamped-away) target frame.
            let frameToResizeFrom = context.lastAppliedFrame ?? context.cachedTargetFrame.raw

            result = calculatePositionAdjustment(for: action, frameToResizeFrom: frameToResizeFrom)

        } else if direction.isCustomizable {
            result = calculateCustomFrame(for: action, bounds: bounds, record: context.resolvedRecord, windowProperties: properties)

        } else if direction == .center {
            result = calculateCenterFrame(bounds: bounds, windowProperties: properties)

        } else if direction == .macOSCenter {
            result = calculateMacOSCenterFrame(bounds: bounds, windowProperties: properties)

        } else if direction == .undo, let properties {
            result = getLastActionFrame(context: context, bounds: bounds, windowProperties: properties)

        } else if direction == .initialFrame, let properties {
            result = getInitialFrame(record: context.resolvedRecord, windowProperties: properties)

        } else if direction == .maximizeHeight, let properties {
            result = getMaximizeHeightFrame(bounds: bounds, padding: context.padding, windowProperties: properties)

        } else if direction == .maximizeWidth, let properties {
            result = getMaximizeWidthFrame(bounds: bounds, padding: context.padding, windowProperties: properties)

        } else if direction == .unstash, let properties {
            result = getInitialFrame(record: context.resolvedRecord, windowProperties: properties)

        } else if direction == .fillAvailableSpace, let window = context.window {
            result = getFillAvailableSpaceFrame(window: window, windowProperties: properties)
        }

        return result
    }

    /// Applies the window direction's frame multiply values to the given bounds.
    /// - Parameters:
    ///   - action: the window action containing the direction with frame multiply values.
    ///   - bounds: the bounds to which the frame multiply values will be applied on.
    /// - Returns: a new `CGRect` with the frame multiply values applied.
    private static func applyFrameMultiplyValues(for action: WindowAction, to bounds: CGRect) -> CGRect {
        guard let frameMultiplyValues = action.direction.frameMultiplyValues else {
            return .zero
        }

        return CGRect(
            x: bounds.origin.x + (bounds.width * frameMultiplyValues.minX),
            y: bounds.origin.y + (bounds.height * frameMultiplyValues.minY),
            width: bounds.width * frameMultiplyValues.width,
            height: bounds.height * frameMultiplyValues.height
        )
    }

    /// Calculates the user-specified custom frame relative to the provided bounds.
    /// - Parameters:
    ///   - action: the window action containing custom frame parameters.
    ///   - bounds: the bounds within which the window should be manipulated.
    ///   - record: pre-resolved window records for initial frame lookup.
    ///   - windowProperties: pre-resolved window properties (frame, isResizable).
    /// - Returns: the calculated custom frame based on the specified parameters.
    private static func calculateCustomFrame(for action: WindowAction, bounds: CGRect, record: WindowRecords.ResolvedRecord?, windowProperties: Window.ResolvedProperties?) -> CGRect {
        var result = CGRect(origin: bounds.origin, size: .zero)

        // Size Calculation

        if let sizeMode = action.sizeMode, sizeMode == .preserveSize, let windowProperties {
            result.size = windowProperties.frame.size

        } else if let sizeMode = action.sizeMode, sizeMode == .initialSize, windowProperties != nil {
            if let initialFrame = record?.initialFrame {
                result.size = initialFrame.size
            }

        } else { // sizeMode would be custom
            switch action.unit {
            case .pixels:
                if windowProperties == nil {
                    let mainScreen = NSScreen.main ?? NSScreen.screens[0]
                    result.size.width = (CGFloat(action.width ?? .zero) / mainScreen.frame.width) * bounds.width
                    result.size.height = (CGFloat(action.height ?? .zero) / mainScreen.frame.height) * bounds.height
                } else {
                    result.size.width = action.width ?? .zero
                    result.size.height = action.height ?? .zero
                }
            default:
                if let width = action.width {
                    result.size.width = bounds.width * (width / 100.0)
                }

                if let height = action.height {
                    result.size.height = bounds.height * (height / 100.0)
                }
            }
        }

        // Position Calculation

        if let positionMode = action.positionMode, positionMode == .coordinates {
            switch action.unit {
            case .pixels:
                if windowProperties == nil {
                    let mainScreen = NSScreen.main ?? NSScreen.screens[0]
                    result.origin.x = (CGFloat(action.xPoint ?? .zero) / mainScreen.frame.width) * bounds.width
                    result.origin.y = (CGFloat(action.yPoint ?? .zero) / mainScreen.frame.height) * bounds.height
                } else {
                    // Note that bounds are ignored deliberately here
                    result.origin.x += action.xPoint ?? .zero
                    result.origin.y += action.yPoint ?? .zero
                }
            default:
                if let xPoint = action.xPoint {
                    result.origin.x += bounds.width * (xPoint / 100.0)
                }

                if let yPoint = action.yPoint {
                    result.origin.y += bounds.height * (yPoint / 100.0)
                }
            }
        } else { // positionMode would be generic
            switch action.anchor {
            case .top:
                result.origin.x = bounds.midX - result.width / 2
            case .topRight:
                result.origin.x = bounds.maxX - result.width
            case .right:
                result.origin.x = bounds.maxX - result.width
                result.origin.y = bounds.midY - result.height / 2
            case .bottomRight:
                result.origin.x = bounds.maxX - result.width
                result.origin.y = bounds.maxY - result.height
            case .bottom:
                result.origin.x = bounds.midX - result.width / 2
                result.origin.y = bounds.maxY - result.height
            case .bottomLeft:
                result.origin.y = bounds.maxY - result.height
            case .left:
                result.origin.y = bounds.midY - result.height / 2
            case .center:
                result.origin.x = bounds.midX - result.width / 2
                result.origin.y = bounds.midY - result.height / 2
            case .macOSCenter:
                let yOffset = getMacOSCenterYOffset(windowHeight: result.height, screenHeight: bounds.height)
                result.origin.x = bounds.midX - result.width / 2
                result.origin.y = (bounds.midY - result.height / 2) + yOffset
            default:
                break
            }
        }

        return result
    }

    /// Calculates the center frame for the window based on the provided bounds. The window's size will not be manipulated if valid properties are passed in.
    /// - Parameters:
    ///   - bounds: the bounds within which the window should be centered.
    ///   - windowProperties: pre-resolved window properties. If `nil`, the center frame will be calculated based on the bounds (and therefore resized).
    /// - Returns: the calculated center frame for the window.
    private static func calculateCenterFrame(bounds: CGRect, windowProperties: Window.ResolvedProperties?) -> CGRect {
        let windowSize: CGSize = if let windowProperties {
            windowProperties.frame.size
        } else {
            .init(width: bounds.width / 2, height: bounds.height / 2)
        }

        return CGRect(
            origin: CGPoint(
                x: bounds.midX - (windowSize.width / 2),
                y: bounds.midY - (windowSize.height / 2)
            ),
            size: windowSize
        )
    }

    /// Calculates the "macOS center" frame for the window based on the provided bounds. The window's size will not be manipulated if valid properties are passed in.
    ///
    /// What is a "macOS center"? It is a center frame that is also shifted upwards by a certain amount, determined by the height of the window and the screen height.
    /// Fun fact: this behavior can also be reproduced in your own NSWindows by calling its `center()` method!
    ///
    /// - Parameters:
    ///   - bounds: the bounds within which the window should be centered.
    ///   - windowProperties: pre-resolved window properties. If `nil`, the center frame will be calculated based on the bounds (and therefore resized).
    /// - Returns: the calculated "macOS center" frame for the window.
    private static func calculateMacOSCenterFrame(bounds: CGRect, windowProperties: Window.ResolvedProperties?) -> CGRect {
        let windowSize: CGSize = if let windowProperties {
            windowProperties.frame.size
        } else {
            .init(width: bounds.width / 2, height: bounds.height / 2)
        }

        let yOffset = getMacOSCenterYOffset(
            windowHeight: windowSize.height,
            screenHeight: bounds.height
        )

        return CGRect(
            origin: CGPoint(
                x: bounds.midX - (windowSize.width / 2),
                y: bounds.midY - (windowSize.height / 2) + yOffset
            ),
            size: windowSize
        )
    }

    /// This static function is used to calculate the Y offset for a window to be "macOS centered" on the screen
    /// It is identical to `NSWindow.center()`.
    /// - Parameters:
    ///   - windowHeight: Height of the window to be resized
    ///   - screenHeight: Height of the screen the window will be resized on
    /// - Returns: The Y offset of the window, to be added onto the screen's midY point.
    private static func getMacOSCenterYOffset(windowHeight: CGFloat, screenHeight: CGFloat) -> CGFloat {
        let halfScreenHeight = screenHeight / 2
        let windowHeightPercent = windowHeight / screenHeight
        return (0.5 * windowHeightPercent - 0.5) * halfScreenHeight
    }

    /// Retrieves the last action frame for the specified window, based on the last action recorded in `WindowRecords`.
    /// - Parameters:
    ///   - context: the current resize context, used to preserve window and record snapshots across recursive resolution.
    ///   - bounds: the bounds within which the window should be manipulated.
    ///   - windowProperties: pre-resolved window properties.
    /// - Returns: the frame of the last action performed on the window, or the current frame if no last action is found.
    private static func getLastActionFrame(context: ResizeContext, bounds: CGRect, windowProperties: Window.ResolvedProperties) -> CGRect {
        if let previousAction = context.resolvedRecord?.lastAction {
            log.info("Last action was \(previousAction.description)")

            let recursiveContext = context.derivedContext(action: previousAction, bounds: bounds)
            return getFrame(resizeContext: recursiveContext).frame
        } else {
            log.info("Didn't find frame to undo; using current frame")
            return windowProperties.frame
        }
    }

    /// Retrieves the initial frame for the specified window, based on the initial frame recorded in `WindowRecords`.
    /// - Parameters:
    ///   - record: pre-resolved window records.
    ///   - windowProperties: pre-resolved window properties.
    /// - Returns: the initial frame of the window, or the current frame if no initial frame is found.
    private static func getInitialFrame(record: WindowRecords.ResolvedRecord?, windowProperties: Window.ResolvedProperties) -> CGRect {
        if let initialFrame = record?.initialFrame {
            return initialFrame
        } else {
            log.info("Didn't find initial frame; using current frame")
            return windowProperties.frame
        }
    }

    /// Computes a new window frame with the maximum height that fits within the given bounds.
    /// - Parameters:
    ///   - bounds: the area within which the window should be resized.
    ///   - padding: the padding that the user has configured to apply to windows.
    ///   - windowProperties: pre-resolved window properties.
    /// - Returns: a CGRect representing a frame that maximizes the window's height.
    private static func getMaximizeHeightFrame(
        bounds: CGRect,
        padding: PaddingConfiguration,
        windowProperties: Window.ResolvedProperties
    ) -> CGRect {
        CGRect(
            x: windowProperties.frame.minX - padding.window / 2,
            y: bounds.minY,
            width: windowProperties.frame.width + padding.window,
            height: bounds.height
        )
    }

    /// Computes a new window frame with the maximum width that fits within the given bounds.
    /// - Parameters:
    ///   - bounds: the area within which the window should be resized.
    ///   - padding: the padding that the user has configured to apply to windows.
    ///   - windowProperties: pre-resolved window properties.
    /// - Returns: a CGRect representing a frame that maximizes the window's width.
    private static func getMaximizeWidthFrame(
        bounds: CGRect,
        padding: PaddingConfiguration,
        windowProperties: Window.ResolvedProperties
    ) -> CGRect {
        CGRect(
            x: bounds.minX,
            y: windowProperties.frame.minY - padding.window / 2,
            width: bounds.width,
            height: windowProperties.frame.height + padding.window
        )
    }

    /// Computes a new window frame that takes up the most area, without overlapping with other windows.
    /// Other windows that already overlap with the current window will be ignored.
    /// - Parameters:
    ///   - window: the window, needed for `ScreenUtility.screenContaining`.
    ///   - windowProperties: pre-resolved window properties.
    /// - Returns: a CGRect representing a frame that makes a window fill the most available space.
    private static func getFillAvailableSpaceFrame(window: Window, windowProperties: Window.ResolvedProperties?) -> CGRect {
        let currentFrame = windowProperties?.frame ?? window.frame

        guard let screen = ScreenUtility.screenContaining(window) ?? NSScreen.main else { return currentFrame }
        let screenFrame = screen.cgSafeScreenFrame

        let nonIntersectingWindowFrames = WindowUtility.windowList()
            .map(\.frame)
            .filter { !$0.intersects(currentFrame) } // Ensure it doesn't intersect with the current window
            .map { $0.intersection(screenFrame) } // Crop it to the screen frame

        /// Computes the closest window obstacle in each of the four cardinal directions
        /// (left, right, top, bottom) relative to the current window, and returns the boundaries
        /// formed by these obstacles, constrained to the screen frame.
        func computeBoundaries() -> (minX: CGFloat, minY: CGFloat, maxX: CGFloat, maxY: CGFloat) {
            var minX = screenFrame.minX
            var minY = screenFrame.minY
            var maxX = screenFrame.maxX
            var maxY = screenFrame.maxY

            for frame in nonIntersectingWindowFrames {
                if frame.maxX <= currentFrame.minX { minX = max(minX, frame.maxX) }
                if frame.maxY <= currentFrame.minY { minY = max(minY, frame.maxY) }
                if frame.minX >= currentFrame.maxX { maxX = min(maxX, frame.minX) }
                if frame.minY >= currentFrame.maxY { maxY = min(maxY, frame.minY) }
            }

            return (minX, minY, maxX, maxY)
        }

        let (minX, minY, maxX, maxY) = computeBoundaries()

        // Needed for Hashable conformance
        struct Boundary: Hashable {
            let min: CGFloat
            let max: CGFloat
        }

        let uniqueXBoundaries: Set<Boundary> = [
            Boundary(min: minX, max: maxX), // Respect obstacles in both directions
            Boundary(min: currentFrame.minX, max: maxX), // Keep left, expand right
            Boundary(min: minX, max: currentFrame.maxX), // Expand left, keep right
            Boundary(min: currentFrame.minX, max: screenFrame.maxX), // Keep left, expand right to screen edge
            Boundary(min: screenFrame.minX, max: currentFrame.maxX), // Expand left to screen edge, keep right
            Boundary(min: screenFrame.minX, max: screenFrame.maxX) // Full screen width
        ]

        let uniqueYBoundaries: Set<Boundary> = [
            Boundary(min: minY, max: maxY), // Respect obstacles in both directions
            Boundary(min: currentFrame.minY, max: maxY), // Keep bottom, expand top
            Boundary(min: minY, max: currentFrame.maxY), // Expand bottom, keep top
            Boundary(min: currentFrame.minY, max: screenFrame.maxY), // Keep bottom, expand top to screen edge
            Boundary(min: screenFrame.minY, max: currentFrame.maxY), // Expand bottom to screen edge, keep top
            Boundary(min: screenFrame.minY, max: screenFrame.maxY) // Full screen height
        ]

        // Generate all possible combinations of x/y boundaries and filter it to valid candidates.
        // A candidate is valid if it doesn't overlap with any other window.
        let validCandidates = uniqueXBoundaries.flatMap { xBound in
            uniqueYBoundaries.compactMap { yBound in
                let combination = CGRect(
                    x: xBound.min,
                    y: yBound.min,
                    width: xBound.max - xBound.min,
                    height: yBound.max - yBound.min
                )

                return nonIntersectingWindowFrames.allSatisfy { !$0.intersects(combination) } ? combination : nil
            }
        }

        return validCandidates.max { $0.size.area < $1.size.area } ?? currentFrame
    }

    /// Calculates the size adjustment for the specified frame based on the bounds and the direction of the action.
    /// - Parameters:
    ///   - action: the window action containing the direction.
    ///   - frameToResizeFrom: the frame to apply the size adjustment to.
    ///   - bounds: the bounds within which the frame should be resized.
    ///   - proportionalIfPossible: if true and all edges are resized, scales proportionally about the center instead of insetting each side.
    ///   - sidesToAdjust: which edges to adjust during the resize.
    /// - Returns: the adjusted frame after applying the size adjustment based on the direction and bounds.
    private static func calculateSizeAdjustment(
        for action: WindowAction,
        frameToResizeFrom: CGRect,
        bounds: CGRect,
        proportionalIfPossible: Bool = false,
        sidesToAdjust: Edge.Set?
    ) -> CGRect {
        let direction = action.direction
        let step = Defaults[.sizeIncrement] * ((direction == .larger || direction == .scaleUp || direction.willGrow) ? -1 : 1)

        let previewPadding = Defaults[.previewPadding]
        let minSize = CGSize(
            width: previewPadding + 100,
            height: previewPadding + 100
        )

        func insetAllEdges(_ rect: CGRect) -> CGRect {
            rect.inset(by: step, minSize: minSize)
        }

        func scaleAllEdgesIfPossible(_ rect: CGRect) -> CGRect? {
            guard proportionalIfPossible, rect.width > 0, rect.height > 0 else { return nil }

            let sx = (rect.width - 2 * step) / rect.width
            let sy = (rect.height - 2 * step) / rect.height
            var targetUniformScale = min(sx, sy)

            guard targetUniformScale.isFinite, targetUniformScale > 0 else { return nil }
            let minScaleToSatisfyMinWidth = minSize.width / rect.width
            let minScaleToSatisfyMinHeight = minSize.height / rect.height
            let minUniformScale = max(minScaleToSatisfyMinWidth, minScaleToSatisfyMinHeight)
            targetUniformScale = max(targetUniformScale, minUniformScale)

            let rectCenter = CGPoint(
                x: rect.midX,
                y: rect.midY
            )

            let scaledSize = CGSize(
                width: rect.width * targetUniformScale,
                height: rect.height * targetUniformScale
            )

            let scaledRect = CGRect(
                x: rectCenter.x - scaledSize.width / 2,
                y: rectCenter.y - scaledSize.height / 2,
                width: scaledSize.width,
                height: scaledSize.height
            )

            return scaledRect
        }

        var result = frameToResizeFrom

        if let edges = sidesToAdjust {
            let resizeAllEdges = edges.isEmpty || edges.contains(.all)

            if resizeAllEdges {
                result = scaleAllEdgesIfPossible(result) ?? insetAllEdges(result)
            } else {
                result = result.padding(edges, step)

                if result.width < minSize.width {
                    result.size.width = minSize.width
                    result.origin.x = frameToResizeFrom.midX - minSize.width / 2
                }
                if result.height < minSize.height {
                    result.size.height = minSize.height
                    result.origin.y = frameToResizeFrom.midY - minSize.height / 2
                }
            }
        }

        result = result
            .intersection(bounds)

        if result.size.approximatelyEqual(to: frameToResizeFrom.size, tolerance: 2) {
            result = frameToResizeFrom
        }

        return result
    }

    /// Calculates the position adjustment for the specified frame based on the direction of the action.
    /// - Parameters:
    ///   - action: the window action containing the direction.
    ///   - frameToResizeFrom: the frame to apply the position adjustment to.
    /// - Returns: the adjusted frame after applying the position adjustment based on the direction.
    private static func calculatePositionAdjustment(for action: WindowAction, frameToResizeFrom: CGRect) -> CGRect {
        let direction = action.direction
        var result = frameToResizeFrom

        if direction == .moveUp {
            result.origin.y -= Defaults[.sizeIncrement]
        } else if direction == .moveDown {
            result.origin.y += Defaults[.sizeIncrement]
        } else if direction == .moveRight {
            result.origin.x += Defaults[.sizeIncrement]
        } else if direction == .moveLeft {
            result.origin.x -= Defaults[.sizeIncrement]
        }

        return result
    }
}
