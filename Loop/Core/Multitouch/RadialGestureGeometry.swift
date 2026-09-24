//
//  RadialGestureGeometry.swift
//  Loop
//

import CoreGraphics

enum RadialGestureGeometry {
    static func normalizedAngle(fromSubsurfaceAngle angle: CGFloat) -> CGFloat {
        var normalized = (.pi / 2 - angle).truncatingRemainder(dividingBy: 2 * .pi)
        if normalized < 0 {
            normalized += 2 * .pi
        }
        return normalized
    }

    static func slotIndex(
        angle: CGFloat,
        actionCount: Int,
        cardinalBias: CGFloat = 0.1
    ) -> Int {
        guard actionCount > 0 else { return 0 }

        let span = (2 * CGFloat.pi) / CGFloat(actionCount)
        let halfSpan = span / 2
        let adjusted = (angle + halfSpan).truncatingRemainder(dividingBy: 2 * .pi)
        let rawSegment = Int(adjusted / span) % actionCount

        guard actionCount == 8 else { return rawSegment }

        let segmentPosition = adjusted.truncatingRemainder(dividingBy: span) / span
        guard rawSegment % 2 != 0 else { return rawSegment }

        if segmentPosition < cardinalBias / 2 {
            return (rawSegment - 1 + actionCount) % actionCount
        }
        if segmentPosition > 1 - cardinalBias / 2 {
            return (rawSegment + 1) % actionCount
        }
        return rawSegment
    }

    /// Angles in Loop's normalized coordinate system where the selected slot changes.
    /// For the eight-action cardinal-biased layout, the boundaries are shifted inside
    /// intercardinal segments to match `slotIndex` exactly.
    static func slotBoundaryAngles(
        actionCount: Int,
        cardinalBias: CGFloat = 0.1
    ) -> [CGFloat] {
        guard actionCount > 0 else { return [] }

        let span = (2 * CGFloat.pi) / CGFloat(actionCount)
        let halfSpan = span / 2

        if actionCount != 8 {
            return (0 ..< actionCount).map { index in
                normalize(angle: CGFloat(index) * span - halfSpan)
            }
        }

        return (0 ..< actionCount).compactMap { segment in
            guard segment % 2 != 0 else { return nil }
            let start = CGFloat(segment) * span
            let lower = start + span * cardinalBias / 2
            return normalize(angle: lower - halfSpan)
        } + (0 ..< actionCount).compactMap { segment in
            guard segment % 2 != 0 else { return nil }
            let start = CGFloat(segment) * span
            let upper = start + span * (1 - cardinalBias / 2)
            return normalize(angle: upper - halfSpan)
        }
    }

    static func thresholdRadii(
        baseline: CGFloat,
        step: CGFloat,
        maximum: CGFloat
    ) -> [CGFloat] {
        guard step > 0, maximum >= 0 else { return [] }

        var radii: [CGFloat] = []
        if baseline <= maximum {
            var radius = baseline
            while radius <= maximum {
                radii.append(radius)
                radius += step
            }
        }

        var radius = baseline - step
        while radius >= 0 {
            if radius <= maximum {
                radii.append(radius)
            }
            radius -= step
        }

        return radii.sorted()
    }

    /// Maps magnification progress onto the swipe-ring geometry. The first
    /// magnification step reaches the baseline ring; every later step advances
    /// by one concentric-ring interval.
    static func magnificationDisplayRadius(
        distance: CGFloat,
        originDistance: CGFloat,
        activationRadius: CGFloat,
        ringStep: CGFloat,
        magnificationStep: CGFloat
    ) -> CGFloat? {
        guard activationRadius >= 0, ringStep >= 0, magnificationStep > 0 else {
            return nil
        }

        let progress = abs(distance - originDistance) / magnificationStep
        if progress <= 1 {
            return activationRadius * progress
        }
        return activationRadius + (progress - 1) * ringStep
    }

    private static func normalize(angle: CGFloat) -> CGFloat {
        let normalized = angle.truncatingRemainder(dividingBy: 2 * .pi)
        return normalized >= 0 ? normalized : normalized + 2 * .pi
    }
}
