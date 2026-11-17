//
//  RadialMenuView.swift
//  Loop
//
//  Created by Kai Azim on 2023-01-24.
//

import Defaults
import Luminare
import SwiftUI
import Tome

struct RadialMenuView: View {
    @Environment(\.luminareAnimation) private var luminareAnimation
    @Environment(\.appearsActive) private var appearsActive
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var accentColorController: AccentColorController = .shared
    @ObservedObject private var viewModel: RadialMenuViewModel
    private let radialMenuSize: CGFloat = 100

    @TomeValue(\.radialMenuCornerRadius) private var radialMenuCornerRadius
    @TomeValue(\.radialMenuThickness) private var radialMenuThickness
    @TomeValue(\.animationConfiguration) private var animationConfiguration

    init(viewModel: RadialMenuViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        ZStack {
            if #available(macOS 26.0, *) {
                postTahoeView()
            } else {
                preTahoeView()
            }
        }
        .padding(40)
        .fixedSize()
        .animation(animationConfiguration.radialMenuSize, value: viewModel.currentAction)
        .animation(luminareAnimation, value: [accentColorController.color1, accentColorController.color2])
        .onAppear {
            viewModel.setIsShown(true, animationDuration: viewModel.isSettingsPreview ? 0.0 : 0.1)
        }
    }

    @available(macOS 26.0, *)
    private func postTahoeView() -> some View {
        // GlassEffectContainer with the materialize glass effect transition causes an exception:
        //   "The window has been marked as needing another Update Constraints..."
        // This bug can be reproduced on macOS 26.0.0 and 26.0.1. We have yet to find the macOS version where it starts working correctly and reliably,
        // but for now, we have disabled the materialization Liquid Glass transition.
        ZStack {
            if viewModel.isShown {
                ZStack {
                    radialMenuFill()
                        .mask(directionSelectorMask)
                        .glassEffect(
                            .regular.tint(accentColorController.color1.opacity(0.025)),
                            in: .rect(cornerRadius: radialMenuCornerRadius) // Using the radial menu thickness here causes a seam in the middle
                        )
                        .mask(radialMenuMask)

                    if appearsActive {
                        let borderColor: Color = colorScheme == .dark ? .white.opacity(0.25).mix(with: accentColorController.color1, by: 0.25) : .white

                        // Since the glass is just masked to the radial menu shape, it will be missing its inner border.
                        // This emulates a liquid glass inner border.
                        let innerBorderThickness: CGFloat = 0.5
                        RoundedRectangle(cornerRadius: radialMenuCornerRadius)
                            .inset(by: radialMenuThickness - innerBorderThickness)
                            .strokeBorder(lineWidth: innerBorderThickness)
                            .foregroundStyle(borderColor)
                            .mask {
                                LinearGradient(
                                    colors: [
                                        .white,
                                        .clear,
                                        .white
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            }
                    }

                    overlayImage()
                }
                .transition(.scale(scale: 1.25).combined(with: .opacity))
            }
        }
        .compositingGroup()
        .frame(width: radialMenuSize, height: radialMenuSize)
        .shadow(color: .black.opacity(viewModel.isShadowShown ? 0.2 : 0), radius: 10)
        .scaleEffect(viewModel.shouldFillRadialMenu ? 0.85 : 1.0)
    }

    private func preTahoeView() -> some View {
        ZStack {
            ZStack {
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow, state: .active)

                radialMenuFill()
                    .mask(directionSelectorMask)

                radialMenuBorder()
            }
            .mask(radialMenuMask)

            overlayImage()
        }
        .frame(width: radialMenuSize, height: radialMenuSize)
        .shadow(radius: 10)
        .compositingGroup()
        .opacity(viewModel.isShown ? 1 : 0)
        .scaleEffect(viewModel.shouldFillRadialMenu ? 0.85 : 1.0)
    }

    private func radialMenuFill() -> some View {
        Rectangle()
            .fill(
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
            )
    }

    private func directionSelectorMask() -> some View {
        ZStack {
            if viewModel.shouldFillRadialMenu {
                Color.white
            } else {
                ZStack {
                    if radialMenuCornerRadius >= radialMenuSize / 2 - 2 {
                        DirectionSelectorCircleSegment(
                            angle: viewModel.angle,
                            radialMenuSize: radialMenuSize
                        )
                    } else {
                        DirectionSelectorSquareSegment(
                            angle: viewModel.angle,
                            radialMenuCornerRadius: radialMenuCornerRadius,
                            radialMenuThickness: radialMenuThickness
                        )
                    }
                }
                .compositingGroup()
                .opacity(viewModel.shouldHideDirectionSelector ? 0 : 1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func radialMenuBorder() -> some View {
        ZStack {
            if radialMenuCornerRadius >= radialMenuSize / 2 - 2 {
                Circle()
                    .stroke(.quinary, lineWidth: 2)

                Circle()
                    .stroke(.quinary, lineWidth: 2)
                    .padding(radialMenuThickness)
            } else {
                RoundedRectangle(cornerRadius: radialMenuCornerRadius)
                    .stroke(.quinary, lineWidth: 2)

                RoundedRectangle(cornerRadius: radialMenuCornerRadius - radialMenuThickness)
                    .stroke(.quinary, lineWidth: 2)
                    .padding(radialMenuThickness)
            }
        }
    }

    private func radialMenuMask() -> some View {
        ZStack {
            if radialMenuCornerRadius >= radialMenuSize / 2 - 2 {
                Circle()
                    .strokeBorder(.black, lineWidth: radialMenuThickness)
            } else {
                RoundedRectangle(cornerRadius: radialMenuCornerRadius)
                    .strokeBorder(.black, lineWidth: radialMenuThickness)
            }
        }
    }

    private func overlayImage() -> some View {
        ZStack {
            if let image = viewModel.radialMenuImage {
                if #available(macOS 26.0, *) {
                    image
                        .transition(.symbolEffect(.drawOn, options: .speed(2)))
                        .contentTransition(.symbolEffect(.replace, options: .speed(2)))
                } else {
                    image
                }
            }
        }
        .foregroundStyle(accentColorController.color1)
        .font(.system(size: 20, weight: .bold))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
