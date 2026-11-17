//
//  GestureItemView.swift
//  Loop
//
//  Created by Kai Azim on 2026-04-16.
//

import Luminare
import SwiftUI

struct GestureItemView: View {
    @Environment(\.luminareAnimation) private var luminareAnimation
    @Environment(\.luminareSectionHorizontalPadding) private var horizontalPadding

    @Binding private var gesture: GestureBinding
    private let hasConflict: Bool
    private let overridesRadialMenu: Bool

    @State private var isGestureConfigPresented = false

    init(_ gesture: Binding<GestureBinding>, hasConflict: Bool, overridesRadialMenu: Bool) {
        _gesture = gesture
        self.hasConflict = hasConflict
        self.overridesRadialMenu = overridesRadialMenu
    }

    var body: some View {
        ZStack {
            actionIndicator
                .frame(maxWidth: .infinity, alignment: .leading)

            gestureConfiguration
                .luminareToolTip(attachedTo: .topTrailing, hidden: !hasConflict && !overridesRadialMenu) {
                    Text(
                        hasConflict
                            ? String(localized: "Another gesture is set up the same way.", comment: "Tooltip shown on a conflicting gesture in settings")
                            : String(localized: "Takes priority over the radial menu for this gesture.", comment: "Tooltip shown on a gesture in settings that overrides one direction of a radial menu gesture using the same finger count")
                    )
                    .padding(6)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 12)
    }

    private var gestureConfiguration: some View {
        Group {
            if let displayName = gesture.displayName {
                Button {
                    isGestureConfigPresented = true
                } label: {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(displayName)
                            .lineLimit(1)

                        if gesture.activationZone == .titlebar {
                            Text(gesture.activationZone.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .fontWeight(.regular)
                    .padding(.horizontal, 4)
                    .contentShape(.rect)
                    .animation(luminareAnimation, value: gesture.activationZone)
                }
                .luminareFilledStates([.hovering, .pressed])
                .luminareBorderedStates(.hovering)
                .opacity(hasConflict ? 0.5 : 1)
            } else {
                Button {
                    isGestureConfigPresented = true
                } label: {
                    Text(String(localized: "Set Gesture…", comment: "Button title on a gesture that has no trigger set yet. Opens the gesture configuration."))
                        .lineLimit(1)
                        .padding(.horizontal, horizontalPadding)
                }
            }
        }
        .luminareContentSize(contentMode: .fit, hasFixedHeight: true)
        .luminareRoundingBehavior(top: true, bottom: true)
        .luminareMinHeight(24)
        .help(String(localized: "Customize this gesture.", comment: "Help text shown when hovering a gesture configuration button"))
        .padding(.leading, -4)
        .luminareModal(isPresented: $isGestureConfigPresented) {
            GestureConfigurationView(
                gesture: $gesture,
                isPresented: $isGestureConfigPresented
            )
            .frame(width: 380)
        }
        .luminareModalCornerRadius(24)
    }

    @ViewBuilder
    private var actionIndicator: some View {
        if gesture.kind == .radialMenu {
            // The radial menu can't be changed here, but shares the button so it lines up with other actions
            HStack(spacing: 2) {
                Button {} label: {
                    HStack(spacing: 8) {
                        Image(.loop)
                            .frame(width: 18)

                        Text(String(localized: "Radial Menu", comment: "Label shown for a gesture configured to open the radial menu"))
                            .fontWeight(.regular)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 4)
                }
                .luminareContentSize(contentMode: .fit, hasFixedHeight: true)
                .luminareRoundingBehavior(top: true, bottom: true)
                .luminareFilledStates([.hovering, .pressed])
                .luminareBorderedStates(.hovering)
                .luminareMinHeight(24)
                .allowsHitTesting(false)
                .padding(.leading, -4)
            }
        } else {
            ActionTargetEditorView(target: $gesture.target, owner: gesture.reference)
        }
    }
}
