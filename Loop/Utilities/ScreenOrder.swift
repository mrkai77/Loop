//
//  ScreenOrder.swift
//  Loop
//
//  Created by Anand Hegde on 2026-09-20.
//

import Defaults
import SwiftUI

/// The order in which "Next/Previous Screen" walks through the user's screens.
enum ScreenOrder: Int, Defaults.Serializable, CaseIterable, Identifiable {
    /// Row by row from top to bottom, and each row from left to right.
    case zShaped = 0

    /// Around the arrangement, starting from the screen at the top left.
    case clockwise = 1

    /// Around the arrangement in the opposite direction.
    case counterclockwise = 2

    var id: Self { self }

    var name: LocalizedStringKey {
        switch self {
        case .zShaped:
            "Z-shaped"
        case .clockwise:
            "Clockwise"
        case .counterclockwise:
            "Counterclockwise"
        }
    }

    @ViewBuilder
    var image: some View {
        switch self {
        case .zShaped:
            Image(.arrowTriangleheadSwapRotated)
        case .clockwise:
            // Named arrow.trianglehead.2.clockwise.rotate.90 since macOS 15; the old name works everywhere.
            Image(systemName: "arrow.triangle.2.circlepath")
        case .counterclockwise:
            // arrow.trianglehead.2.counterclockwise.rotate.90 needs macOS 15, so mirror the clockwise symbol instead.
            Image(systemName: "arrow.triangle.2.circlepath")
                .scaleEffect(x: -1, y: 1)
        }
    }

    /// Sorts screens into the traversal order this case describes.
    /// - Parameters:
    ///   - elements: the screens to sort.
    ///   - frame: the frame of a screen, in a coordinate space whose y axis points up.
    /// - Returns: the screens, in the order they should be cycled through.
    func sorted<Element>(_ elements: [Element], frame: (Element) -> CGRect) -> [Element] {
        switch self {
        case .zShaped:
            elements.sorted { Self.zShapedOrder(frame($0), frame($1)) }
        case .clockwise:
            Self.rotationalOrder(elements, frame: frame, isClockwise: true)
        case .counterclockwise:
            Self.rotationalOrder(elements, frame: frame, isClockwise: false)
        }
    }
}

// MARK: - Z-shaped order

private extension ScreenOrder {
    /// Whether one screen comes before another when reading the arrangement like a page.
    static func zShapedOrder(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        if rhs.maxY <= lhs.minY {
            return true
        }

        if lhs.maxY <= rhs.minY {
            return false
        }

        return lhs.minX < rhs.minX
    }
}

// MARK: - Rotational order

private extension ScreenOrder {
    /// A screen paired with the geometry the sort needs, so that frames are only asked for once.
    struct Placed<Element> {
        let id: Int
        let element: Element
        let frame: CGRect
        var center: CGPoint { frame.center }
    }

    /// Walks around the arrangement, outermost screens first.
    ///
    /// Screens on the outside of the arrangement form the first ring and are visited in turn;
    /// any screens left inside it form the next ring, and so on. An arrangement without an
    /// inside, which is every arrangement of two screens and any number of screens in a row,
    /// is a single ring.
    static func rotationalOrder<Element>(
        _ elements: [Element],
        frame: (Element) -> CGRect,
        isClockwise: Bool
    ) -> [Element] {
        // Two screens cycle the same way around whichever direction is chosen.
        guard elements.count > 2 else {
            return elements.sorted { zShapedOrder(frame($0), frame($1)) }
        }

        var remaining = elements.enumerated().map { Placed(id: $0.offset, element: $0.element, frame: frame($0.element)) }
        var result: [Element] = []

        while !remaining.isEmpty {
            let ringIndices = outermostRing(of: remaining.map(\.center))

            // Every screen is on the outside of something, so this should not happen. Should it
            // ever, fall back to the original order rather than spin here forever.
            guard !ringIndices.isEmpty else {
                result += remaining
                    .sorted { zShapedOrder($0.frame, $1.frame) }
                    .map(\.element)
                break
            }

            let ring = ringIndices.map { remaining[$0] }
            result += ordered(ring, isClockwise: isClockwise).map(\.element)

            let visited = Set(ringIndices)
            remaining = remaining.indices
                .filter { !visited.contains($0) }
                .map { remaining[$0] }
        }

        return result
    }

    /// Orders one ring of screens, starting from the screen closest to the top left.
    static func ordered<Element>(_ ring: [Placed<Element>], isClockwise: Bool) -> [Placed<Element>] {
        guard ring.count > 2 else {
            return ring.sorted { zShapedOrder($0.frame, $1.frame) }
        }

        var result = isCollinear(ring.map(\.center))
            ? straightLineOrder(ring, isClockwise: isClockwise)
            : angularOrder(ring, isClockwise: isClockwise)

        // The cycle has no natural beginning, so start it where the eye does.
        let topLeft = ring.min { zShapedOrder($0.frame, $1.frame) }

        if let topLeft, let start = result.firstIndex(where: { $0.id == topLeft.id }) {
            result = Array(result[start...] + result[..<start])
        }

        return result
    }

    /// Orders screens that are all in a line, along that line.
    ///
    /// A row is the top of the circle, where clockwise runs to the right; a column is the right
    /// of it, where clockwise runs downwards.
    static func straightLineOrder<Element>(
        _ ring: [Placed<Element>],
        isClockwise: Bool
    ) -> [Placed<Element>] {
        let centers = ring.map(\.center)
        let width = (centers.map(\.x).max() ?? 0) - (centers.map(\.x).min() ?? 0)
        let height = (centers.map(\.y).max() ?? 0) - (centers.map(\.y).min() ?? 0)

        let result = width >= height
            ? ring.sorted { $0.center.x < $1.center.x }
            : ring.sorted { $0.center.y > $1.center.y }

        return isClockwise ? result : result.reversed()
    }

    /// Orders screens by the angle at which they sit around the middle of their ring.
    static func angularOrder<Element>(_ ring: [Placed<Element>], isClockwise: Bool) -> [Placed<Element>] {
        let centers = ring.map(\.center)
        let middle = CGPoint(
            x: centers.map(\.x).reduce(0, +) / CGFloat(centers.count),
            y: centers.map(\.y).reduce(0, +) / CGFloat(centers.count)
        )

        // Angles increase counterclockwise, since the y axis points up.
        let result = ring.sorted { lhs, rhs in
            angle(of: lhs.center, around: middle) < angle(of: rhs.center, around: middle)
        }

        return isClockwise ? result.reversed() : result
    }

    static func angle(of point: CGPoint, around middle: CGPoint) -> CGFloat {
        atan2(point.y - middle.y, point.x - middle.x)
    }
}

// MARK: - Geometry

private extension ScreenOrder {
    /// Screens are laid out on a grid of points, so anything this small is a rounding error.
    static let tolerance: CGFloat = 0.001

    /// Finds the screens on the outside of an arrangement.
    ///
    /// This is the convex hull of their centers, keeping the centers that sit on one of its
    /// edges so that a straight row of screens stays in one ring rather than losing its middle.
    /// - Returns: the indices of the screens forming the outside of the arrangement.
    static func outermostRing(of points: [CGPoint]) -> [Int] {
        guard points.count > 2 else {
            return Array(points.indices)
        }

        let sorted = points.indices.sorted { lhs, rhs in
            points[lhs].x == points[rhs].x
                ? points[lhs].y < points[rhs].y
                : points[lhs].x < points[rhs].x
        }

        func chain(_ indices: [Int]) -> [Int] {
            var hull: [Int] = []

            for index in indices {
                while hull.count >= 2,
                      cross(points[hull[hull.count - 2]], points[hull[hull.count - 1]], points[index]) < -tolerance {
                    hull.removeLast()
                }

                hull.append(index)
            }

            return hull
        }

        return Set(chain(sorted)).union(chain(sorted.reversed())).sorted()
    }

    static func isCollinear(_ points: [CGPoint]) -> Bool {
        guard points.count > 2, let first = points.first else {
            return true
        }

        guard let second = points.first(where: { $0 != first }) else {
            return true
        }

        return points.allSatisfy { abs(cross(first, second, $0)) < tolerance }
    }

    /// The cross product of `origin → a` and `origin → b`, which is positive when the turn
    /// from one to the other is counterclockwise.
    static func cross(_ origin: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        (a.x - origin.x) * (b.y - origin.y) - (a.y - origin.y) * (b.x - origin.x)
    }
}
