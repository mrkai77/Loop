//
//  PaddingConfigurationView.swift
//  Loop
//
//  Created by Kai Azim on 2024-04-19.
//

import Luminare
import SwiftUI
import Tome

struct PaddingConfigurationView: View {
    @Environment(\.luminareAnimation) private var luminareAnimation
    @TomeValue(\.enablePadding) private var enablePadding

    @TomeValue(\.padding) private var storedPadding
    @State private var paddingModel = Tome.padding
    @State private var isDeferringDefaultsCommit = false
    @Binding var isPresented: Bool

    let range: ClosedRange<Double> = 0...100

    var body: some View {
        LuminareForm {
            ScreenView {
                PaddingPreview($paddingModel)
            }
            .disabled(!enablePadding)

            LuminareSection {
                LuminareToggle("Apply padding", isOn: $enablePadding)
            }

            Group {
                LuminareSection {
                    paddingMode()

                    if paddingModel.mode == .simple {
                        nonScreenPaddingConfiguration()
                    } else {
                        screenSidesPaddingConfiguration()
                    }
                }

                if paddingModel.mode == .custom {
                    LuminareSection {
                        screenInsetsPaddingConfiguration()
                    }
                }
            }
            .disabled(!enablePadding)

            Button {
                isPresented = false
            } label: {
                Text("Done", comment: "Label for a button that closes a modal window")
            }
            .buttonStyle(.luminare(overrideUseMainStyle: true))
            .luminareCornerRadius(8)
        }
        .onChange(of: storedPadding) { newValue in
            // Pick up hand edits; the guard below avoids writing fallback values back
            paddingModel = newValue
        }
        .onChange(of: paddingModel) { _ in
            guard !isDeferringDefaultsCommit, paddingModel != storedPadding else { return }
            // This fixes some weird animations.
            storedPadding = paddingModel
        }
    }

    func paddingMode() -> some View {
        LuminarePicker(
            elements: PaddingConfiguration.Mode.allCases,
            selection: Binding(
                get: {
                    paddingModel.mode
                },
                set: { newValue in
                    withAnimation(luminareAnimation) {
                        paddingModel.mode = newValue

                        if paddingModel.mode == .simple {
                            if paddingModel.allEqual {
                                let window = paddingModel.window
                                paddingModel.top = window
                                paddingModel.bottom = window
                                paddingModel.right = window
                                paddingModel.left = window
                            } else {
                                paddingModel.window = 0
                                paddingModel.top = 0
                                paddingModel.bottom = 0
                                paddingModel.right = 0
                                paddingModel.left = 0
                            }
                        }
                    }
                }
            ),
            columns: 2
        ) { mode in
            HStack(spacing: 6) {
                if mode == .custom {
                    Image(systemName: "slider.horizontal.3")
                    Text("Custom")
                } else {
                    Image(systemName: "square")
                    Text("Simple")
                }
            }
            .fixedSize()
        }
        .luminareRoundingBehavior(top: true)
    }

    func nonScreenPaddingConfiguration() -> some View {
        LuminareSlider(
            "Padding",
            value: Binding(
                get: {
                    paddingModel.window
                },
                set: {
                    let value = ($0 * 100).rounded() / 100
                    paddingModel.window = value
                    paddingModel.top = value
                    paddingModel.bottom = value
                    paddingModel.right = value
                    paddingModel.left = value
                }
            ),
            in: range,
            format: .number.precision(.fractionLength(0...1)),
            clampsUpper: false,
            suffix: Text("px", comment: "Unit symbol: pixels"),
            onEditingChanged: handleSliderEditingChanged,
            onEditingCommit: commitSliderChanges
        )
    }

    @ViewBuilder
    func screenSidesPaddingConfiguration() -> some View {
        LuminareSlider(
            String(localized: "Top", comment: "Label for a slider in Loop’s padding settings"),
            value: $paddingModel.top.doubleBinding,
            in: range,
            format: .number.precision(.fractionLength(0...1)),
            clampsUpper: false,
            suffix: Text("px", comment: "Unit symbol: pixels"),
            onEditingChanged: handleSliderEditingChanged,
            onEditingCommit: commitSliderChanges
        )
        .luminareSliderLayout(.compact(textBoxWidth: 76))

        LuminareSlider(
            String(localized: "Bottom", comment: "Label for a slider in Loop’s padding settings"),
            value: $paddingModel.bottom.doubleBinding,
            in: range,
            format: .number.precision(.fractionLength(0...1)),
            clampsUpper: false,
            suffix: Text("px", comment: "Unit symbol: pixels"),
            onEditingChanged: handleSliderEditingChanged,
            onEditingCommit: commitSliderChanges
        )
        .luminareSliderLayout(.compact(textBoxWidth: 76))

        LuminareSlider(
            String(localized: "Right", comment: "Label for a slider in Loop’s padding settings"),
            value: $paddingModel.right.doubleBinding,
            in: range,
            format: .number.precision(.fractionLength(0...1)),
            clampsUpper: false,
            suffix: Text("px", comment: "Unit symbol: pixels"),
            onEditingChanged: handleSliderEditingChanged,
            onEditingCommit: commitSliderChanges
        )
        .luminareSliderLayout(.compact(textBoxWidth: 76))

        LuminareSlider(
            String(localized: "Left", comment: "Label for a slider in Loop’s padding settings"),
            value: $paddingModel.left.doubleBinding,
            in: range,
            format: .number.precision(.fractionLength(0...1)),
            clampsUpper: false,
            suffix: Text("px", comment: "Unit symbol: pixels"),
            onEditingChanged: handleSliderEditingChanged,
            onEditingCommit: commitSliderChanges
        )
        .luminareSliderLayout(.compact(textBoxWidth: 76))
    }

    @ViewBuilder
    func screenInsetsPaddingConfiguration() -> some View {
        LuminareSlider(
            String(localized: "Window gaps", comment: "Label for a slider in Loop’s padding settings"),
            value: $paddingModel.window.doubleBinding,
            in: range,
            format: .number.precision(.fractionLength(0...1)),
            clampsUpper: false,
            suffix: Text("px", comment: "Unit symbol: pixels"),
            onEditingChanged: handleSliderEditingChanged,
            onEditingCommit: commitSliderChanges
        )
        .luminareSliderLayout(.compact(textBoxWidth: 76))

        LuminareSlider(
            value: $paddingModel.externalBar.doubleBinding,
            in: range,
            format: .number.precision(.fractionLength(0...1)),
            suffix: Text("px", comment: "Unit symbol: pixels"),
            onEditingChanged: handleSliderEditingChanged,
            onEditingCommit: commitSliderChanges
        ) {
            Text("External bar", comment: "Label for a slider in Loop’s padding settings")
                .padding(.trailing, 4)
                .luminareToolTip(attachedTo: .topTrailing) {
                    Text("Use this if you use a custom menu bar.")
                        .padding(6)
                }
        }
        .luminareSliderLayout(.compact(textBoxWidth: 76))
    }

    private func handleSliderEditingChanged(_ isEditing: Bool) {
        isDeferringDefaultsCommit = isEditing
    }

    private func commitSliderChanges() {
        isDeferringDefaultsCommit = false
        guard paddingModel != storedPadding else { return }
        storedPadding = paddingModel
    }
}
