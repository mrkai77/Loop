//
//  PreviewConfiguration.swift
//  Loop
//
//  Created by Kai Azim on 2024-04-19.
//

import Defaults
import Luminare
import SwiftUI

struct PreviewConfigurationView: View {
    @Environment(\.luminareAnimation) private var luminareAnimation

    @Default(.previewVisibility) private var previewVisibility
    @Default(.moveCursorWithWindow) private var moveCursorWithWindow
    @Default(.previewPadding) private var previewPadding
    @Default(.previewCornerRadius) private var previewCornerRadius
    @Default(.previewBorderThickness) private var previewBorderThickness
    @Default(.previewUseWindowCornerRadius) private var previewUseWindowCornerRadius
    @Default(.previewBackgroundStyle) private var previewBackgroundStyle
    @Default(.previewBackgroundEnableBlur) private var previewBackgroundEnableBlur
    @Default(.previewBackgroundAccentOpacity) private var previewBackgroundAccentOpacity

    var body: some View {
        LuminareForm {
            LuminareSection {
                LuminareToggle(
                    isOn: Binding(
                        get: {
                            previewVisibility
                        },
                        set: {
                            previewVisibility = $0

                            if !previewVisibility {
                                moveCursorWithWindow = false
                            }
                        }
                    )
                ) {
                    Text("Show preview when looping")
                        .padding(.trailing, 4)
                        .luminareToolTip(attachedTo: .topTrailing, hidden: previewVisibility) {
                            Text("Window snapping will still use the preview.")
                                .padding(6)
                        }
                        .animation(luminareAnimation, value: previewVisibility)
                }

                LuminareSlider(
                    "Padding",
                    value: $previewPadding.doubleBinding,
                    in: 0...20,
                    format: .number.precision(.fractionLength(0...0)),
                    clampsUpper: false,
                    clampsLower: true,
                    suffix: Text("px", comment: "Unit symbol: pixels")
                )

                // On macOS Sequoia and below, simply show the corner radius slider.
                if #unavailable(macOS 26) {
                    LuminareSlider(
                        "Corner radius",
                        value: $previewCornerRadius.doubleBinding,
                        in: 0...25,
                        format: .number.precision(.fractionLength(0...0)),
                        clampsUpper: false,
                        clampsLower: true,
                        suffix: Text("px", comment: "Unit symbol: pixels")
                    )
                }

                LuminareSlider(
                    "Border thickness",
                    value: $previewBorderThickness.doubleBinding,
                    in: 0...10,
                    format: .number.precision(.fractionLength(0...0)),
                    clampsUpper: false,
                    clampsLower: true,
                    suffix: Text("px", comment: "Unit symbol: pixels")
                )
            }

            // On macOS Tahoe and above, Loop has the ability to read the selected window's corner radius.
            // So display it in a separate section, with the option to configure this functionality.
            if #available(macOS 26, *) {
                LuminareSection("Corner Radius") {
                    LuminareToggle(
                        "Match target window",
                        isOn: $previewUseWindowCornerRadius
                    )

                    if !previewUseWindowCornerRadius {
                        LuminareSlider(
                            "Corner radius",
                            value: $previewCornerRadius.doubleBinding,
                            in: 0...25,
                            format: .number.precision(.fractionLength(0...0)),
                            clampsUpper: false,
                            clampsLower: true,
                            suffix: Text("px", comment: "Unit symbol: pixels")
                        )
                    }
                }
            }

            LuminareSection("Background") {
                LuminarePickerMenu(
                    "Style",
                    selection: $previewBackgroundStyle,
                    items: PreviewBackgroundStyle.allCases
                ) { style in
                    Text(style.displayName)
                }

                if previewBackgroundStyle == .custom {
                    LuminareToggle("Enable blur", isOn: $previewBackgroundEnableBlur)

                    LuminareSlider(
                        "Accent opacity",
                        value: $previewBackgroundAccentOpacity.doubleBinding,
                        in: 0...1,
                        step: 0.1,
                        format: .percent.precision(.fractionLength(0...0)),
                        clampsUpper: true,
                        clampsLower: true
                    )
                }
            }
            .animation(luminareAnimation, value: previewBackgroundStyle)
        }
        .animation(luminareAnimation, value: previewUseWindowCornerRadius)
    }
}
