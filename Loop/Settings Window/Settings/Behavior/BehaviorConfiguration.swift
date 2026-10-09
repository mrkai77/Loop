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
            draggingSection
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
                selection: windowSelection,
                items: WindowSelection.allCases
            ) { selection in
                Text("\(Image(selection.icon)) \(selection.title)")
            }

            // If the system WM is enabled, the window under the cursor requires focus.
            if resizeWindowUnderCursor, !useSystemWindowManagerWhenAvailable {
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

    private var windowSelection: Binding<WindowSelection> {
        Binding(
            get: { resizeWindowUnderCursor ? .underCursor : .frontmost },
            set: { resizeWindowUnderCursor = $0 == .underCursor }
        )
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
        .onChange(of: stashedWindowVisiblePadding) { _ in
            Task { await StashManager.shared.onConfigurationChanged() }
        }
    }
}

/// Which window Loop acts on, stored as `resizeWindowUnderCursor`
private enum WindowSelection: CaseIterable {
    case frontmost
    case underCursor

    var title: String {
        switch self {
        case .frontmost: String(localized: "Active", comment: "Target window option: act on the active window")
        case .underCursor: String(localized: "Under Cursor", comment: "Window selection option: act on the window under the cursor")
        }
    }

    var icon: ImageResource {
        switch self {
        case .frontmost: .interfaceWindowOnRectangleDashed
        case .underCursor: .interfaceWindowAndPointerArrow
        }
    }
}
