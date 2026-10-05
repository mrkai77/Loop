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

    /// Around the arrangement, starting from the screen at the top left. "Previous screen"
    /// walks it counterclockwise.
    case clockwise = 1

    var id: Self { self }

    var name: LocalizedStringKey {
        switch self {
        case .zShaped:
            "Z-shaped"
        case .clockwise:
            "Clockwise"
        }
    }

    var image: Image {
        switch self {
        case .zShaped:
            Image(.arrowTriangleheadSwapRotated)
        case .clockwise:
            // Named arrow.trianglehead.2.clockwise.rotate.90 since macOS 15; the old name works everywhere.
            Image(systemName: "arrow.triangle.2.circlepath")
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
            Self.clockwiseOrder(elements, frame: frame)
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

// MARK: - Clockwise order

private extension ScreenOrder {
    /// Walks around the arrangement, outermost screens first.
    ///
    /// The outline of the arrangement is traced clockwise from the top left corner of its top
    /// left screen, and each screen is visited the first time the outline reaches it. Screens
    /// the outline never reaches are inside the arrangement, and are walked the same way once
    /// the ones around them have been.
    ///
    /// The outline steps straight across gaps between screens rather than following them in,
    /// so a gap doesn't pull the screens deep inside it into the middle of the cycle.
    ///
    /// Only the screens' edges are used, never their centers, so a row stays a row however its
    /// screens are aligned, and resizing a screen doesn't move its neighbors to another ring.
    static func clockwiseOrder<Element>(_ elements: [Element], frame: (Element) -> CGRect) -> [Element] {
        // Two screens cycle the same way whatever order they're in.
        guard elements.count > 2 else {
            return elements.sorted { zShapedOrder(frame($0), frame($1)) }
        }

        let frames = elements.map(frame)
        var remaining = Array(frames.indices)
        var result: [Element] = []

        while !remaining.isEmpty {
            let ring = outermostRing(of: remaining, frames: frames)

            // A ring always has a screen in it, but should one ever come back empty, keep the
            // rest in the order they were given rather than loop here forever.
            guard !ring.isEmpty else {
                result += remaining.map { elements[$0] }
                break
            }

            result += ring.map { elements[$0] }

            let visited = Set(ring)
            remaining.removeAll { visited.contains($0) }
        }

        return result
    }
}

// MARK: - Outline

private extension ScreenOrder {
    /// A corner of a cell in the grid that the arrangement is cut into.
    struct Vertex: Hashable {
        let column: Int
        let row: Int
    }

    /// Listed clockwise, so that turning right is the next case along.
    enum Direction: Int {
        case right, down, left, up
    }

    /// One side of a grid cell that lies on the outline, pointing clockwise around the arrangement.
    struct OutlineEdge: Equatable {
        let from: Vertex
        let to: Vertex
        let direction: Direction

        /// The screen this part of the outline belongs to, or `nil` where it bridges a gap.
        let screen: Int?
    }

    /// Traces the outline of the given screens and returns the ones on it, in clockwise order,
    /// starting from the screen at the top left.
    /// - Parameters:
    ///   - screens: indices into `frames` of the screens to consider.
    ///   - frames: the frames of every screen, in a coordinate space whose y axis points up.
    /// - Returns: indices into `frames`. Never empty unless `screens` is.
    static func outermostRing(of screens: [Int], frames: [CGRect]) -> [Int] {
        guard screens.count > 1 else {
            return screens
        }

        // Cut the arrangement along every screen edge, so that each cell of the grid is either
        // entirely inside one screen or entirely outside all of them.
        let xs = Set(screens.flatMap { [frames[$0].minX, frames[$0].maxX] }).sorted()
        let ys = Set(screens.flatMap { [frames[$0].minY, frames[$0].maxY] }).sorted()
        let columns = xs.count - 1
        let rows = ys.count - 1

        let owners: [[Int?]] = (0 ..< columns).map { column in
            (0 ..< rows).map { row in
                let middle = CGPoint(x: (xs[column] + xs[column + 1]) / 2, y: (ys[row] + ys[row + 1]) / 2)
                return screens.first { frames[$0].contains(middle) }
            }
        }

        // Fill in the gaps: any empty cell with the arrangement on both sides of it, left and
        // right or above and below, is treated as part of it, so the outline bridges the gap.
        var isSolid = owners.map { $0.map { $0 != nil } }
        var didFill = true

        while didFill {
            didFill = false

            for column in 0 ..< columns {
                for row in 0 ..< rows where !isSolid[column][row] {
                    let isBetweenColumns = (0 ..< column).contains { isSolid[$0][row] }
                        && (column + 1 ..< columns).contains { isSolid[$0][row] }
                    let isBetweenRows = (0 ..< row).contains { isSolid[column][$0] }
                        && (row + 1 ..< rows).contains { isSolid[column][$0] }

                    if isBetweenColumns || isBetweenRows {
                        isSolid[column][row] = true
                        didFill = true
                    }
                }
            }
        }

        func solid(_ column: Int, _ row: Int) -> Bool {
            (0 ..< columns).contains(column) && (0 ..< rows).contains(row) && isSolid[column][row]
        }

        /// The screen the outline runs along, looking inwards through any bridged gap.
        ///
        /// A gap less than half as deep as the screen at the bottom of it is tall (or wide, for a
        /// gap in the side of the arrangement) is only screens being slightly out of line, like a
        /// row with one screen a point lower, so the outline belongs to that screen. Anything
        /// deeper is a real gap, and the outline across it belongs to no screen.
        func screen(behind direction: Direction, of column: Int, _ row: Int) -> Int? {
            var column = column
            var row = row
            let outline = switch direction {
            case .right: ys[row + 1]
            case .down: xs[column + 1]
            case .left: ys[row]
            case .up: xs[column]
            }

            while solid(column, row) {
                if let owner = owners[column][row] {
                    let depth = switch direction {
                    case .right: outline - ys[row + 1]
                    case .down: outline - xs[column + 1]
                    case .left: ys[row] - outline
                    case .up: xs[column] - outline
                    }

                    let size = switch direction {
                    case .right, .left: frames[owner].height
                    case .down, .up: frames[owner].width
                    }

                    return depth < size / 2 ? owner : nil
                }

                switch direction {
                case .right: row -= 1
                case .down: column -= 1
                case .left: row += 1
                case .up: column += 1
                }
            }

            return nil
        }

        // Every side of a cell that faces empty space is part of the outline.
        var outgoing: [Vertex: [OutlineEdge]] = [:]
        var edgeCount = 0

        for column in 0 ..< columns {
            for row in 0 ..< rows where isSolid[column][row] {
                let topLeft = Vertex(column: column, row: row + 1)
                let topRight = Vertex(column: column + 1, row: row + 1)
                let bottomRight = Vertex(column: column + 1, row: row)
                let bottomLeft = Vertex(column: column, row: row)
                var edges: [(from: Vertex, to: Vertex, direction: Direction)] = []

                if !solid(column, row + 1) {
                    edges.append((topLeft, topRight, .right))
                }

                if !solid(column + 1, row) {
                    edges.append((topRight, bottomRight, .down))
                }

                if !solid(column, row - 1) {
                    edges.append((bottomRight, bottomLeft, .left))
                }

                if !solid(column - 1, row) {
                    edges.append((bottomLeft, topLeft, .up))
                }

                for edge in edges {
                    outgoing[edge.from, default: []].append(
                        OutlineEdge(
                            from: edge.from,
                            to: edge.to,
                            direction: edge.direction,
                            screen: screen(behind: edge.direction, of: column, row)
                        )
                    )
                }

                edgeCount += edges.count
            }
        }

        // The top of the highest cell is always on the outside of the arrangement, never around a hole in it.
        guard
            let column = (0 ..< columns).first(where: { solid($0, rows - 1) }),
            let start = outgoing[Vertex(column: column, row: rows)]?.first(where: { $0.direction == .right })
        else {
            return screens
        }

        var outline: [OutlineEdge] = []
        var edge = start

        repeat {
            outline.append(edge)

            // Where two screens only meet at a corner, which macOS doesn't allow, turning right
            // keeps the outline around one of them. The other is then walked as its own ring.
            let options = outgoing[edge.to] ?? []
            let next = [1, 0, 3].lazy
                .compactMap { turn in
                    options.first { $0.direction.rawValue == (edge.direction.rawValue + turn) % 4 }
                }
                .first

            guard let next else {
                break
            }

            edge = next
        } while edge != start && outline.count <= edgeCount

        // The cycle has no natural beginning, so start it where the eye does: at the top left
        // corner of the screen nearest the top left of the arrangement. zShapedOrder can't pick
        // it, as it contradicts itself for staggered screens, which would make the start (and
        // with it the whole cycle, since screens can be on the outline twice) depend on which
        // order the screens are looked at in.
        let bounds = screens.reduce(CGRect.null) { $0.union(frames[$1]) }

        func distanceFromTopLeft(_ screen: Int) -> (CGFloat, CGFloat, CGFloat) {
            let frame = frames[screen]
            return (hypot(frame.minX - bounds.minX, frame.maxY - bounds.maxY), frame.minX, -frame.maxY)
        }

        guard let first = outline.compactMap(\.screen).min(by: { distanceFromTopLeft($0) < distanceFromTopLeft($1) }) else {
            return screens
        }

        let startIndex = outline.indices
            .filter { outline[$0].screen == first && outline[$0].direction == .right }
            .min { outline[$0].from.column < outline[$1].from.column }
            ?? outline.firstIndex { $0.screen == first }
            ?? 0

        var ring: [Int] = []

        for offset in outline.indices {
            if let screen = outline[(startIndex + offset) % outline.count].screen, !ring.contains(screen) {
                ring.append(screen)
            }
        }

        return ring
    }
}
