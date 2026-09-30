//
//  BehaviorConfiguration.swift
//  Loop
//
//  Created by Kai Azim on 2024-04-19.
//

import Defaults
import Luminare
import SwiftUI

struct BehaviorConfigurationView: View {
    @Environment(\.luminareAnimation) private var luminareAnimation

    @Default(.launchAtLogin) var launchAtLogin
    @Default(.animationConfiguration) var animationConfiguration
    @Default(.windowSnapping) var windowSnapping
    @Default(.suppressMissionControlOnTopDrag) var suppressMissionControlOnTopDrag
    @Default(.restoreWindowFrameOnDrag) var restoreWindowFrameOnDrag
    @Default(.useSystemWindowManagerWhenAvailable) var useSystemWindowManagerWhenAvailable
    @Default(.useScreenWithCursor) var useScreenWithCursor
    @Default(.resizeWindowUnderCursor) var resizeWindowUnderCursor
    @Default(.focusWindowOnResize) var focusWindowOnResize
    @Default(.respectStageManager) var respectStageManager
    @Default(.stageStripSize) var stageStripSize
    @Default(.previewVisibility) var previewVisibility
    @Default(.stashedWindowVisiblePadding) var stashedWindowVisiblePadding
    @Default(.animateStashedWindows) var animateStashedWindows
    @Default(.shiftFocusWhenStashed) var shiftFocusWhenStashed

    @State private var isPaddingConfigurationViewPresented = false

    var body: some View {
        LuminareForm {
            generalSection
            windowSection
            windowSnappingSection
            stageManagerSection
            stashSection
        }
        .animation(
            luminareAnimation,
            value: [
                resizeWindowUnderCursor,
                windowSnapping,
                respectStageManager
            ]
        )
    }

    private var generalSection: some View {
        LuminareSection(String(localized: "General", comment: "Section header shown in settings")) {
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
                selection: windowSelection,
                items: WindowSelection.allCases
            ) { selection in
                Text("\(Image(systemName: selection.icon)) \(selection.title)")
            }

            // If the system WM is enabled, the window under the cursor requires focus.
            if resizeWindowUnderCursor, !useSystemWindowManagerWhenAvailable {
                LuminareToggle("Focus on resize", isOn: $focusWindowOnResize)
            }

            LuminareToggle("Move to cursor's screen", isOn: $useScreenWithCursor)

            // Enabling the system window manager will override these options.
            if !useSystemWindowManagerWhenAvailable {
                LuminareToggle("Restore window frame on drag", isOn: $restoreWindowFrameOnDrag)
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

    private var windowSelection: Binding<WindowSelection> {
        Binding(
            get: { resizeWindowUnderCursor ? .underCursor : .focused },
            set: { resizeWindowUnderCursor = $0 == .underCursor }
        )
    }

    private var windowSnappingSection: some View {
        LuminareSection(String(localized: "Window Snapping", comment: "Section header shown in settings")) {
            if #available(macOS 15, *) {
                LuminareToggle(isOn: $windowSnapping) {
                    if SystemWindowManager.MoveAndResize.snappingEnabled {
                        Text("Enable window snapping")
                            .padding(.trailing, 4)
                            .luminareToolTip(attachedTo: .topTrailing) {
                                Text("macOS's \"Tile by dragging windows to screen edges\" feature is currently\nenabled, which will conflict with Loop's window snapping functionality.")
                                    .padding(6)
                            }
                    } else {
                        Text("Enable window snapping")
                    }
                }
            } else {
                LuminareToggle("Enable window snapping", isOn: $windowSnapping)
            }

            if windowSnapping {
                LuminareToggle(isOn: $suppressMissionControlOnTopDrag) {
                    Text("Suppress Mission Control")
                        .padding(.trailing, 4)
                        .luminareToolTip(attachedTo: .topTrailing) {
                            Text("Whether to allow Mission Control to open when windows\nare dragged to the top of the screen.")
                                .padding(6)
                        }
                }
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
            LuminareToggle("Animated", isOn: $animateStashedWindows)

            LuminareSlider(
                String(localized: "Peek size", comment: "Thickness of the visible portion of the window when stashed"),
                value: $stashedWindowVisiblePadding.doubleBinding,
                in: 1...100,
                format: .number.precision(.fractionLength(0...0)),
                clampsUpper: false,
                suffix: Text("px", comment: "Unit symbol: pixels")
            )

            LuminareToggle("Shift focus when stashed", isOn: $shiftFocusWhenStashed)
        }
        .onChange(of: stashedWindowVisiblePadding) { _ in
            Task { await StashManager.shared.onConfigurationChanged() }
        }
    }
}

/// Which window Loop acts on, stored as `resizeWindowUnderCursor`
private enum WindowSelection: CaseIterable {
    case focused
    case underCursor

    var title: String {
        switch self {
        case .focused: String(localized: "Focused", comment: "Window selection option: act on the focused window")
        case .underCursor: String(localized: "Under Cursor", comment: "Window selection option: act on the window under the cursor")
        }
    }

    var icon: String {
        switch self {
        case .focused: "interface.window.on.rectangle.dashed"
        case .underCursor: "interface.window.and.pointer.arrow"
        }
    }
}
