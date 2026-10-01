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
    @Default(.windowSnapping) private var windowSnapping
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
                // Window snapping always uses the preview, so only offer that choice when it's enabled
                if windowSnapping {
                    LuminarePickerMenu(
                        "Preview",
                        selection: previewVisibilityOption,
                        items: PreviewVisibilityOption.allCases
                    ) { option in
                        Text(option.title)
                    }
                } else {
                    LuminareToggle(
                        "Preview",
                        isOn: Binding(
                            get: { previewVisibilityOption.wrappedValue == .always },
                            set: { previewVisibilityOption.wrappedValue = $0 ? .always : .windowSnappingOnly }
                        )
                    )
                }

                if isPreviewUsed {
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
            }

            if isPreviewUsed {
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
                                "Radius",
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
                        LuminareToggle("Blur", isOn: $previewBackgroundEnableBlur)

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
        }
        .animation(luminareAnimation, value: previewUseWindowCornerRadius)
        .animation(luminareAnimation, value: windowSnapping)
        .animation(luminareAnimation, value: previewVisibility)
    }

    /// Window snapping always uses the preview, so it's only unused when both are off
    private var isPreviewUsed: Bool {
        previewVisibility || windowSnapping
    }

    private var previewVisibilityOption: Binding<PreviewVisibilityOption> {
        Binding(
            get: { previewVisibility ? .always : .windowSnappingOnly },
            set: { previewVisibility = $0 == .always }
        )
    }
}

/// When the preview is shown, stored as `previewVisibility`
private enum PreviewVisibilityOption: CaseIterable {
    case always
    case windowSnappingOnly

    var title: String {
        switch self {
        case .always: String(localized: "Always", comment: "Preview visibility option: show the preview when looping and window snapping")
        case .windowSnappingOnly: String(localized: "Window Snapping Only", comment: "Preview visibility option: only show the preview when window snapping")
        }
    }
}
