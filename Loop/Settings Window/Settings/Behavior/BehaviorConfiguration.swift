//
//  BehaviorConfiguration.swift
//  Loop
//
//  Created by Kai Azim on 2024-04-19.
//

import Defaults
import Luminare
import SwiftUI
import Tome

struct BehaviorConfigurationView: View {
    @Environment(\.luminareAnimation) private var luminareAnimation

    @Default(.launchAtLogin) var launchAtLogin
    @TomeValue(\.animationConfiguration) var animationConfiguration
    @TomeValue(\.windowSnapping) var windowSnapping
    @TomeValue(\.suppressMissionControlOnTopDrag) var suppressMissionControlOnTopDrag
    @TomeValue(\.restoreWindowFrameOnDrag) var restoreWindowFrameOnDrag
    @TomeValue(\.useSystemWindowManagerWhenAvailable) var useSystemWindowManagerWhenAvailable
    @TomeValue(\.useScreenWithCursor) var useScreenWithCursor
    @TomeValue(\.targetWindow) var targetWindow
    @TomeValue(\.focusWindowOnResize) var focusWindowOnResize
    @TomeValue(\.respectStageManager) var respectStageManager
    @TomeValue(\.stageStripSize) var stageStripSize
    @TomeValue(\.previewVisibility) var previewVisibility
    @TomeValue(\.stashedWindowVisiblePadding) var stashedWindowVisiblePadding
    @TomeValue(\.animateStashedWindows) var animateStashedWindows
    @TomeValue(\.shiftFocusWhenStashed) var shiftFocusWhenStashed

    @State private var isPaddingConfigurationViewPresented = false

    var body: some View {
        LuminareForm {
            generalSection
            windowSection
            draggingSection
            stageManagerSection
            stashSection
        }
        .animation(
            luminareAnimation,
            value: [
                targetWindow == .underCursor,
                windowSnapping,
                respectStageManager
            ]
        )
    }

    private var generalSection: some View {
        LuminareSection {
            LuminareToggle("Launch at login", isOn: $launchAtLogin)

            LuminareSliderPicker(
                "Animation speed",
                AnimationConfiguration.allCases.reversed(),
                selection: $animationConfiguration
            ) { item in
                Text(item.name)
                    .monospaced()
            }
        }
    }

    private var windowSection: some View {
        LuminareSection(String(localized: "Window", comment: "Section header shown in settings")) {
            LuminarePickerMenu(
                "Target window",
                selection: $targetWindow,
                items: WindowSelection.allCases
            ) { selection in
                Text("\(Image(selection.icon)) \(selection.title)")
            }

            // If the system WM is enabled, the window under the cursor requires focus.
            if targetWindow == .underCursor, !useSystemWindowManagerWhenAvailable {
                LuminareToggle("Focus window on resize", isOn: $focusWindowOnResize)
            }

            LuminareToggle("Move to cursor’s screen", isOn: $useScreenWithCursor)

            // Enabling the system window manager will override this option.
            if !useSystemWindowManagerWhenAvailable {
                LuminareButton("Padding", "Configure…") {
                    isPaddingConfigurationViewPresented = true
                }
                .luminareModal(isPresented: $isPaddingConfigurationViewPresented) {
                    PaddingConfigurationView(isPresented: $isPaddingConfigurationViewPresented)
                        .frame(width: 400)
                }
                .luminareModalCornerRadius(24)
            }
        }
    }

    private var draggingSection: some View {
        LuminareSection(String(localized: "Dragging", comment: "Section header shown in settings, for settings about dragging windows")) {
            // Enabling the system window manager will override this option.
            if !useSystemWindowManagerWhenAvailable {
                LuminareToggle("Restore size when dragging", isOn: $restoreWindowFrameOnDrag)
            }

            if #available(macOS 15, *) {
                LuminareToggle(isOn: $windowSnapping) {
                    if SystemWindowManager.MoveAndResize.snappingEnabled {
                        Text("Snap by dragging to screen edges")
                            .padding(.trailing, 4)
                            .luminareToolTip(attachedTo: .topTrailing) {
                                Text("macOS’s “Tile by dragging windows to screen edges” is turned on,\nwhich conflicts with Loop’s window snapping.")
                                    .padding(6)
                            }
                    } else {
                        Text("Snap by dragging to screen edges")
                    }
                }
            } else {
                LuminareToggle("Snap by dragging to screen edges", isOn: $windowSnapping)
            }

            if windowSnapping {
                LuminareToggle("Prevent Mission Control at top edge", isOn: $suppressMissionControlOnTopDrag)
            }
        }
    }

    private var stageManagerSection: some View {
        LuminareSection(String(localized: "Stage Manager", comment: "Section header shown in settings")) {
            LuminareToggle("Respect Stage Manager", isOn: $respectStageManager)

            if respectStageManager {
                LuminareSlider(
                    "Stage strip size",
                    value: $stageStripSize.doubleBinding,
                    in: 50...250,
                    format: .number.precision(.fractionLength(0...0)),
                    clampsUpper: false,
                    suffix: Text("px", comment: "Unit symbol: pixels")
                )
            }
        }
    }

    private var stashSection: some View {
        LuminareSection(String(localized: "Stash", comment: "Section header shown in settings")) {
            LuminareToggle("Animate stashing", isOn: $animateStashedWindows)

            LuminareSlider(
                String(localized: "Peek size", comment: "Thickness of the visible portion of the window when stashed"),
                value: $stashedWindowVisiblePadding.doubleBinding,
                in: 1...100,
                format: .number.precision(.fractionLength(0...0)),
                clampsUpper: false,
                suffix: Text("px", comment: "Unit symbol: pixels")
            )

            LuminareToggle("Focus next window when stashing", isOn: $shiftFocusWhenStashed)
        }
    }
}
