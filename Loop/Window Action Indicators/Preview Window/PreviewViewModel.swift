//
//  PreviewViewModel.swift
//  Loop
//
//  Created by Kai Azim on 2025-11-25.
//

import Defaults
import Scribe
import SwiftUI

@Loggable
@MainActor
final class PreviewViewModel: ObservableObject {
    @Published private(set) var computedFrame: CGRect = .zero
    @Published private(set) var isShown: Bool = false
    @Published private(set) var overrideCornerRadii: RectangleCornerRadii?

    private let isSettingsPreview: Bool

    init(isSettingsPreview: Bool) {
        self.isSettingsPreview = isSettingsPreview
    }

    func setIsShown(_ newState: Bool) {
        withAnimation(Defaults[.animationConfiguration].previewWindow) {
            isShown = newState
        }
    }

    func updateContext(with context: ResizeContext, isScreenSwitch: Bool) {
        if #available(macOS 26.0, *), let window = context.window {
            overrideCornerRadii = Self.getCornerRadius(for: window)
        } else {
            overrideCornerRadii = nil
        }

        let isCurrentlyHidden = !isShown
        var paddedFrame = context.getTargetFrame().padded

        if let bounds = context.screen?.displayBounds {
            paddedFrame.origin.x -= bounds.minX
            paddedFrame.origin.y -= bounds.minY
        }

        // Frameless actions (no-op, minimize/hide, focus, space/screen switching) have no target
        // frame; hide the preview rather than leaving the previous action's cached frame on screen
        // (`recomputeTargetFrame` deliberately keeps that cache so grow/shrink/move can resize from it).
        // In settings preview, actions that manipulate existing window frames (larger/smaller,
        // grow/shrink, move) cannot be previewed without a real window.
        let shouldBecomeVisible = if !context.action.direction.hasTargetFrame {
            false
        } else if isSettingsPreview, context.action.willManipulateExistingWindowFrame {
            false
        } else {
            paddedFrame.size.area > 0
        }

        var newShownState: Bool = isShown
        var newComputedFrame: CGRect = computedFrame

        // If the window is currently shown, but needs to be hidden
        if !isCurrentlyHidden, !shouldBecomeVisible {
            newShownState = false
        }

        // If the window is currently hidden, but it needs to be shown.
        else if isCurrentlyHidden, shouldBecomeVisible {
            if !isScreenSwitch {
                let startingFrame = computeStartingFrame(
                    for: Defaults[.previewStartingPosition],
                    targetFrame: paddedFrame,
                    context: context
                )

                // Set starting position without animation
                computedFrame = startingFrame
            }

            newShownState = true
            newComputedFrame = paddedFrame
        }

        // Window is already visible and should stay visible - update frame
        else if !isCurrentlyHidden, shouldBecomeVisible {
            newComputedFrame = paddedFrame
        }

        if isScreenSwitch {
            computedFrame = newComputedFrame
            isShown = newShownState
        } else {
            withAnimation(Defaults[.animationConfiguration].previewWindow) {
                computedFrame = newComputedFrame
                isShown = newShownState
            }
        }

        log.ui("Current previewed frame: \(computedFrame) for \(context.action)")
    }

    private func computeStartingFrame(
        for position: PreviewStartingPosition,
        targetFrame: CGRect,
        context: ResizeContext
    ) -> CGRect {
        switch position {
        case .screenCenter:
            // Animate from zero at center of screen
            guard var centerPosition = context.screen?.frame.center else {
                return targetFrame
            }
            if let screenFrame = context.screen?.frame {
                centerPosition.x -= screenFrame.minX
                centerPosition.y -= screenFrame.minY
            }
            return CGRect(origin: centerPosition, size: .zero)

        case .radialMenu:
            // Center the preview window on the initial mouse position
            var mousePosition = context.initialMousePosition
            if let screenFrame = context.screen?.frame {
                mousePosition.x -= screenFrame.minX
                mousePosition.y -= screenFrame.minY
            }
            return CGRect(origin: mousePosition, size: .zero)

        case .actionCenter:
            // Center the preview window on the action's target frame (at 80% size)
            let previewWidth = targetFrame.width * 0.8
            let previewHeight = targetFrame.height * 0.8

            return CGRect(
                x: targetFrame.midX - previewWidth / 2,
                y: targetFrame.midY - previewHeight / 2,
                width: previewWidth,
                height: previewHeight
            )
        }
    }

    @available(macOS 26.0, *)
    private static func getCornerRadius(for window: Window) -> RectangleCornerRadii? {
        var cornerRadii: RectangleCornerRadii? = nil

        if Defaults[.previewUseWindowCornerRadius],
           let radii = SkyLightToolBelt.getCornerRadii(windowID: window.cgWindowID),
           radii != .init(topLeading: 0, bottomLeading: 0, bottomTrailing: 0, topTrailing: 0) {
            cornerRadii = radii
        }

        return cornerRadii
    }
}
