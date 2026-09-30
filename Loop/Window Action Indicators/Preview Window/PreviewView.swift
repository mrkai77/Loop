//
//  PreviewView.swift
//  Loop
//
//  Created by Kai Azim on 2023-01-24.
//

import Defaults
import SwiftUI

struct PreviewView: View {
    @Environment(\.luminareAnimation) private var luminareAnimation
    @ObservedObject private var accentColorController: AccentColorController = .shared
    @ObservedObject private var viewModel: PreviewViewModel

    @Default(.previewPadding) private var previewPadding
    @Default(.previewCornerRadius) private var previewCornerRadius
    @Default(.previewUseWindowCornerRadius) private var previewUseWindowCornerRadius
    @Default(.previewBorderThickness) private var previewBorderThickness
    @Default(.previewBackgroundEnableBlur) private var previewEnableBlur
    @Default(.previewBackgroundAccentOpacity) private var previewBackgroundAccentOpacity

    init(viewModel: PreviewViewModel) {
        self.viewModel = viewModel
    }

    private var cornerRadii: RectangleCornerRadii {
        // Prefer the window's own radii, but skip if the padded inset would be sharp.
        if let inset = viewModel.overrideCornerRadii?.inset(by: previewPadding),
           inset != .zero {
            return inset
        }

        // Fall back to 16pt when using window radii, otherwise the user's radius
        let radius: CGFloat = if #available(macOS 26, *), previewUseWindowCornerRadius {
            16
        } else {
            previewCornerRadius
        }

        return RectangleCornerRadii(
            topLeading: radius,
            bottomLeading: radius,
            bottomTrailing: radius,
            topTrailing: radius
        )
    }

    var body: some View {
        windowView()
            .compositingGroup()
            .frame(width: viewModel.computedFrame.width, height: viewModel.computedFrame.height)
            .offset(x: viewModel.computedFrame.minX, y: viewModel.computedFrame.minY)
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .topLeading
            )
            .opacity(viewModel.isShown ? 1 : 0)
    }

    private func windowView() -> some View {
        ZStack {
            ZStack {
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow, state: .active)
                    .opacity(previewEnableBlur ? 1 : 0)
                    .animation(luminareAnimation, value: previewEnableBlur)

                LinearGradient(
                    gradient: Gradient(
                        colors: [
                            accentColorController.color1,
                            accentColorController.color2
                        ]
                    ),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .opacity(previewBackgroundAccentOpacity)
                .animation(luminareAnimation, value: previewBackgroundAccentOpacity)
            }
            .clipShape(.rect(cornerRadii: cornerRadii))

            UnevenRoundedRectangle(cornerRadii: cornerRadii)
                .strokeBorder(.quinary, lineWidth: 1)

            UnevenRoundedRectangle(cornerRadii: cornerRadii)
                .stroke(
                    LinearGradient(
                        gradient: Gradient(
                            colors: [
                                accentColorController.color1,
                                accentColorController.color2
                            ]
                        ),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: previewBorderThickness
                )
        }
        .padding(previewPadding + previewBorderThickness / 2)
        .animation(luminareAnimation, value: [accentColorController.color1, accentColorController.color2])
    }
}
