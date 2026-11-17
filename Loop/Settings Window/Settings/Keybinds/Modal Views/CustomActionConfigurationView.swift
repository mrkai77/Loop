//
//  CustomActionConfigurationView.swift
//  Loop
//
//  Created by Kai Azim on 2024-04-27.
//

import Luminare
import SwiftUI

/// Edits both custom and stash actions.
struct CustomActionConfigurationView: View {
    @Environment(\.luminareAnimation) private var luminareAnimation

    @Binding private var windowAction: WindowAction
    @Binding private var isPresented: Bool

    @State private var action: WindowAction
    @State private var currentTab: Tab = .position
    @State private var isDeferringExternalCommit = false
    @State private var positionMemory = ActionPositionMemory()

    private enum Tab: LocalizedStringKey, CaseIterable {
        case position = "Position", size = "Size"

        var image: Image {
            switch self {
            case .position:
                Image(systemName: "viewfinder")
            case .size:
                Image(systemName: "rectangle.expand.diagonal")
            }
        }
    }

    private enum Dimension { case width, height, x, y }

    private var isStash: Bool {
        action.direction == .stash
    }

    private var anchors: [CustomWindowActionAnchor] {
        isStash
            ? [.topLeft, .none, .topRight,
               .left, .none, .right,
               .bottomLeft, .bottom, .bottomRight]
            : [.topLeft, .top, .topRight, .left, .center, .right, .bottomLeft, .bottom, .bottomRight]
    }

    private var sizeModes: [CustomWindowActionSizeMode] {
        isStash ? [.custom, .preserve] : CustomWindowActionSizeMode.allCases
    }

    private var defaultAnchor: CustomWindowActionAnchor {
        isStash ? .topLeft : .center
    }

    private var usesCoordinates: Bool {
        if case .coordinates = action.position { true } else { false }
    }

    private var usesCustomSize: Bool {
        if case .custom = action.size { true } else { false }
    }

    private var anchor: CustomWindowActionAnchor? {
        if case let .anchor(value) = action.position { value } else { nil }
    }

    private var showMacOSCenterToggle: Bool {
        !isStash && (anchor ?? .center == .center || anchor == .macOSCenter)
    }

    private let previewController = PreviewController()
    private let screenSize: CGSize = NSScreen.main?.frame.size ?? NSScreen.screens[0].frame.size

    init(action: Binding<WindowAction>, isPresented: Binding<Bool>) {
        _windowAction = action
        _isPresented = isPresented
        _action = State(initialValue: action.wrappedValue)
    }

    var body: some View {
        LuminareForm {
            ScreenView(isBlurred: !usesCustomSize) {
                ActionPreview(action: action)
            }

            configurationSections()
            actionButtons()
        }
        .onChange(of: action) { newValue in
            guard !isDeferringExternalCommit else { return }
            windowAction = newValue
        }
        .onChange(of: windowAction) { newValue in
            // Keep the draft while dragging
            if !isDeferringExternalCommit, action != newValue { action = newValue }
        }
        .onDisappear { previewController.close() }
    }

    @ViewBuilder
    private func configurationSections() -> some View {
        LuminareSection(outerPadding: 0) {
            LuminareTextField(
                action.direction.name,
                text: Binding(
                    get: { action.name ?? "" },
                    set: { action.name = $0 }
                )
            )
            .luminareFilledStates(.none)
            .luminareBorderedStates(.none)
        }

        LuminareSection(outerPadding: 0) {
            tabPicker()
        }

        LuminareSection(outerPadding: 0) {
            if currentTab == .position {
                positionConfiguration()
            } else {
                sizeConfiguration()
            }
        }
    }

    private func tabPicker() -> some View {
        LuminarePicker(
            elements: Tab.allCases,
            selection: $currentTab.animation(luminareAnimation),
            columns: 2
        ) { tab in
            HStack(spacing: 6) {
                tab.image

                if tab == .size, isStash {
                    Text("Unstashed Size")
                } else {
                    Text(tab.rawValue)
                }
            }
            .fixedSize()
        }
        .luminareContentSize(hasFixedHeight: true)
        .luminareRoundingBehavior(top: true, bottom: true)
    }

    private func actionButtons() -> some View {
        HStack(spacing: 8) {
            Button("Preview") {}
                .onLongPressGesture(
                    // Allows for a press-and-hold gesture to show the preview
                    minimumDuration: 100.0,
                    maximumDistance: .infinity,
                    pressing: { pressing in
                        if pressing {
                            guard let screen = NSScreen.main else { return }
                            let context = ResizeContext(screen: screen)
                            context.setAction(to: action, parent: nil)
                            previewController.open(context: context)
                        } else {
                            previewController.close()
                        }
                    },
                    perform: {}
                )
                .disabled(!usesCustomSize)

            Button {
                isPresented = false
            } label: {
                Text("Done", comment: "Label for a button that closes a modal window")
            }
        }
        .buttonStyle(.luminare(overrideUseMainStyle: true))
        .luminareCornerRadius(8)
    }

    @ViewBuilder
    private func positionConfiguration() -> some View {
        if !isStash {
            LuminareToggle(
                "Use coordinates",
                isOn: Binding(
                    get: {
                        usesCoordinates
                    },
                    set: { newValue in
                        withAnimation(luminareAnimation) {
                            action.position = positionMemory.switched(from: action.position, toCoordinates: newValue)
                        }
                    }
                )
            )
        }

        if !usesCoordinates {
            LuminarePicker(
                elements: anchors,
                selection: Binding(
                    get: {
                        // since center/macOS center use the same icon on the picker
                        if anchor == .macOSCenter {
                            return .center
                        }

                        return anchor ?? defaultAnchor
                    },
                    set: { newValue in
                        withAnimation(luminareAnimation) {
                            action.position = .anchor(newValue)
                        }
                    }
                ),
                columns: 3
            ) { anchor in
                if let action = anchor.iconAction {
                    IconView(action: action)
                }
            }
            .luminareRoundingBehavior(top: isStash, bottom: !showMacOSCenterToggle)

            if showMacOSCenterToggle {
                LuminareToggle(
                    isOn: Binding(
                        get: {
                            anchor == .macOSCenter
                        },
                        set: {
                            action.position = .anchor($0 ? .macOSCenter : .center)
                        }
                    )
                ) {
                    if let infoText = action.direction.infoText {
                        Text("Use macOS center", comment: "Toggle to enable macOS-style centering in custom actions")
                            .padding(.trailing, 4)
                            .luminareToolTip(attachedTo: .topTrailing) {
                                Text(infoText)
                                    .padding(6)
                            }
                    } else {
                        Text("Use macOS center", comment: "Toggle to enable macOS-style centering in custom actions")
                    }
                }
            }
        } else {
            lengthControl(Text(String(localized: "X", comment: "X axis label")), dimension: .x)
            lengthControl(Text(String(localized: "Y", comment: "Y axis label")), dimension: .y)
        }
    }

    @ViewBuilder
    private func sizeConfiguration() -> some View {
        LuminarePicker(
            elements: sizeModes,
            selection: Binding(
                get: {
                    switch action.size {
                    case .custom, nil: .custom
                    case .preserve: .preserve
                    case .initial: .initial
                    }
                },
                set: { newValue in
                    withAnimation(luminareAnimation) {
                        switch newValue {
                        case .custom:
                            if !usesCustomSize {
                                let dimensions = action.customDimensions
                                action.size = .custom(width: dimensions?.width, height: dimensions?.height)
                            }
                        case .preserve: action.size = .preserve
                        case .initial: action.size = .initial
                        }
                    }
                }
            ),
            columns: isStash ? 2 : 3
        ) { mode in
            VStack(spacing: 4) {
                mode.image
                Text(mode.name)
            }
            .padding(.vertical, 15)
            .compositingGroup()
        }
        .luminareContentSize(hasFixedHeight: true)
        .luminareRoundingBehavior(
            top: true,
            bottom: !usesCustomSize
        )

        if usesCustomSize {
            lengthControl(Text("Width"), dimension: .width)
            lengthControl(Text("Height"), dimension: .height)
        }
    }

    private func lengthControl(_ label: Text, dimension: Dimension) -> some View {
        let length = length(for: dimension) ?? ScreenLength(0)
        let maximum = dimension == .width || dimension == .x ? screenSize.width : screenSize.height

        return VStack(spacing: 0) {
            LuminareSlider(
                value: Binding(
                    get: {
                        self.length(for: dimension)?.value ?? 0
                    },
                    set: {
                        guard $0.isFinite else { return }
                        let unit = self.length(for: dimension)?.unit ?? .percent
                        setLength(ScreenLength($0, unit: unit).roundedToDisplayPrecision(), for: dimension)
                    }
                ),
                in: length.unit == .percent ? 0...100 : 0...Double(maximum),
                format: length.unit.format,
                clampsUpper: false,
                suffix: Text(length.unit == .percent ? "%" : "pt"),
                onEditingChanged: handleSliderEditingChanged,
                onEditingCommit: commitSliderChanges
            ) {
                label
            }

            LuminareToggle(
                "Use screen points",
                isOn: Binding(
                    get: {
                        self.length(for: dimension)?.unit == .points
                    },
                    set: { points in
                        var value = self.length(for: dimension) ?? ScreenLength(0)
                        value.unit = points ? .points : .percent
                        setLength(value.roundedToDisplayPrecision(), for: dimension)
                    }
                )
            )
        }
    }

    private func handleSliderEditingChanged(_ isEditing: Bool) {
        isDeferringExternalCommit = isEditing
    }

    private func commitSliderChanges() {
        isDeferringExternalCommit = false
        windowAction = action
    }

    private func length(for dimension: Dimension) -> ScreenLength? {
        switch dimension {
        case .width: action.customDimensions?.width
        case .height: action.customDimensions?.height
        case .x: if case let .coordinates(x, _) = action.position { x } else { nil }
        case .y: if case let .coordinates(_, y) = action.position { y } else { nil }
        }
    }

    private func setLength(_ length: ScreenLength, for dimension: Dimension) {
        switch dimension {
        case .width: action.size = .custom(width: length, height: self.length(for: .height))
        case .height: action.size = .custom(width: self.length(for: .width), height: length)
        case .x: action.position = .coordinates(x: length, y: self.length(for: .y))
        case .y: action.position = .coordinates(x: self.length(for: .x), y: length)
        }
    }
}
