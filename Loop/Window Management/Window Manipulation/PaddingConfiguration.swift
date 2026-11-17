//
//  PaddingConfiguration.swift
//  Loop
//
//  Created by Kai Azim on 2024-02-01.
//

import SwiftUI
import Tome

struct PaddingConfiguration: Hashable, Tome.Serializable {
    var window: CGFloat
    var externalBar: CGFloat
    var top: CGFloat
    var bottom: CGFloat
    var right: CGFloat
    var left: CGFloat

    enum Mode: String, Codable, CaseIterable, Tome.Serializable {
        case simple
        case custom
    }

    var mode: Mode

    var totalTopPadding: CGFloat {
        top + externalBar
    }

    static var zero = PaddingConfiguration(
        window: 0,
        externalBar: 0,
        top: 0,
        bottom: 0,
        right: 0,
        left: 0,
        mode: .simple
    )

    var allEqual: Bool {
        window == top && window == bottom && window == right && window == left
    }

    func applyToBounds(
        _ bounds: CGRect,
        screen: NSScreen? = nil
    ) -> CGRect {
        let notchOffset: CGFloat = if Tome.ignoreNotch, let screen {
            screen.menubarHeight
        } else {
            0
        }
        let effectiveTopPadding = max(0, totalTopPadding - notchOffset)

        return bounds
            .padding(.leading, left)
            .padding(.trailing, right)
            .padding(.bottom, bottom)
            .padding(.top, effectiveTopPadding)
    }

    /// Applies padding to a frame that was calculated using non-padded bounds.
    /// This scales the frame proportionally into the padded working area and applies inner window padding.
    /// - Parameters:
    ///   - frame: The frame calculated using non-padded bounds.
    ///   - bounds: The original non-padded bounds (e.g., screen frame).
    ///   - action: The window action, used to determine padding behavior.
    ///   - window: The window being resized, if any.
    /// - Returns: The frame with padding applied.
    func applyToWindow(
        frame: CGRect,
        paddedBounds bounds: CGRect,
        action: WindowAction,
        resolvedWindowProperties: Window.ResolvedProperties?
    ) -> CGRect {
        guard bounds.size.area > 0, frame.size.area > 0 else { return frame }

        var result = frame

        // Handle non-resizable windows by centering within the frame (no size changes)
        if let resolvedWindowProperties, !resolvedWindowProperties.isResizable {
            let centeredFrame = resolvedWindowProperties.frame.size
                .center(inside: result)
                .pushInside(bounds)

            return centeredFrame
        }

        // Apply inner padding if applicable
        guard action.isInnerPaddingApplicable else { return result }

        result = applyInnerPadding(
            to: result,
            paddedBounds: bounds,
            action: action
        )

        return result
    }

    /// Applies inner window padding to the sides of the frame that don't touch the bounds edges.
    private func applyInnerPadding(to frame: CGRect, paddedBounds: CGRect, action: WindowAction) -> CGRect {
        var result = frame.intersection(paddedBounds)
        let halfPadding = window / 2

        // Handle macOS center special case
        if action.direction == .macOSCenter, frame.height >= paddedBounds.height {
            result.origin.y = paddedBounds.minY
            result.size.height = paddedBounds.height
        }

        // Center actions don't get inner padding
        if action.direction == .center || action.direction == .macOSCenter {
            return result
        }

        // Apply half padding to sides not touching bounds
        if abs(result.minX - paddedBounds.minX) > 1 {
            result = result.padding(.leading, halfPadding)
        }
        if abs(result.maxX - paddedBounds.maxX) > 1 {
            result = result.padding(.trailing, halfPadding)
        }
        if abs(result.minY - paddedBounds.minY) > 1 {
            result = result.padding(.top, halfPadding)
        }
        if abs(result.maxY - paddedBounds.maxY) > 1 {
            result = result.padding(.bottom, halfPadding)
        }

        return result
    }
}

/// A missing field means zero (or `simple`), and only fields that differ are written.
extension PaddingConfiguration: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case mode
        case gap
        case edges
        case customMenuBar = "custom-menu-bar"
    }

    enum EdgeKeys: String, CodingKey {
        case top, bottom, left, right
    }

    /// `[padding]` also holds `enabled`, `minimum-screen-size` and `ignore-notch` as separate keys.
    static let tomeManagedFields: [String]? = CodingKeys.allCases.map(\.rawValue)

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let edges = container.contains(.edges) ? try container.nestedContainer(keyedBy: EdgeKeys.self, forKey: .edges) : nil
        func length<Key: CodingKey>(_ container: KeyedDecodingContainer<Key>?, _ key: Key) throws -> CGFloat {
            try container?.decodeIfPresent(CGFloat.self, forKey: key) ?? 0
        }
        try self.init(
            window: length(container, .gap),
            externalBar: length(container, .customMenuBar),
            top: length(edges, .top),
            bottom: length(edges, .bottom),
            right: length(edges, .right),
            left: length(edges, .left),
            mode: container.decodeIfPresent(Mode.self, forKey: .mode) ?? .simple
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if mode != .simple { try container.encode(mode, forKey: .mode) }
        if window != 0 { try container.encode(window, forKey: .gap) }
        let edges = [(EdgeKeys.top, top), (.bottom, bottom), (.left, left), (.right, right)].filter { $0.1 != 0 }
        if !edges.isEmpty {
            var nested = container.nestedContainer(keyedBy: EdgeKeys.self, forKey: .edges)
            for (key, value) in edges { try nested.encode(value, forKey: key) }
        }
        if externalBar != 0 { try container.encode(externalBar, forKey: .customMenuBar) }
    }
}

extension PaddingConfiguration {
    static func getConfiguredPadding(for screen: NSScreen?) -> PaddingConfiguration {
        if #available(macOS 15, *), Tome.useSystemWindowManagerWhenAvailable {
            guard SystemWindowManager.MoveAndResize.enablePadding else {
                return .zero
            }

            let padding = SystemWindowManager.MoveAndResize.padding

            return PaddingConfiguration(
                window: padding,
                externalBar: 0,
                top: padding,
                bottom: padding,
                right: padding,
                left: padding,
                mode: .simple
            )
        } else {
            let respectsPaddingThreshold = if let screen {
                Tome.paddingMinimumScreenSize == 0 || screen.diagonalSize > Tome.paddingMinimumScreenSize
            } else {
                true
            }
            let enablePadding = Tome.enablePadding && respectsPaddingThreshold

            return enablePadding ? Tome.padding : .zero
        }
    }
}
