//
//  PaddingConfiguration.swift
//  Loop
//
//  Created by Kai Azim on 2024-02-01.
//

import Defaults
import SwiftUI

struct PaddingConfiguration: Codable, Defaults.Serializable, Hashable {
    var window: CGFloat
    var externalBar: CGFloat
    var top: CGFloat
    var bottom: CGFloat
    var right: CGFloat
    var left: CGFloat

    var configureScreenPadding: Bool

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
        configureScreenPadding: false
    )

    var allEqual: Bool {
        window == top && window == bottom && window == right && window == left
    }

    func applyToBounds(
        _ bounds: CGRect,
        screen: NSScreen? = nil
    ) -> CGRect {
        let notchOffset: CGFloat = if Defaults[.ignoreNotch], let screen {
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

extension PaddingConfiguration {
    static func getConfiguredPadding(for screen: NSScreen?) -> PaddingConfiguration {
        if #available(macOS 15, *), Defaults[.useSystemWindowManagerWhenAvailable] {
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
                configureScreenPadding: false
            )
        } else {
            let respectsPaddingThreshold = if let screen {
                Defaults[.paddingMinimumScreenSize] == 0 || screen.diagonalSize > Defaults[.paddingMinimumScreenSize]
            } else {
                true
            }
            let enablePadding = Defaults[.enablePadding] && respectsPaddingThreshold

            return enablePadding ? Defaults[.padding] : .zero
        }
    }
}
