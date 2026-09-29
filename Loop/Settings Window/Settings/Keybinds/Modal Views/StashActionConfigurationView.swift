//
//  StashActionConfigurationView.swift
//  Loop
//
//  Created by Guillaume Clédat on 19/06/2025.
//

import Defaults
import Foundation
import Luminare
import SwiftUI

struct StashActionConfigurationView: View {
    @Environment(\.luminareAnimation) private var luminareAnimation

    @Binding private var windowAction: WindowAction
    @Binding private var isPresented: Bool

    @State private var action: WindowAction
    @State private var currentTab: Tab = .position
    @State private var isDeferringExternalCommit = false

    private enum Tab: LocalizedStringKey, CaseIterable {
        case position = "Position", size = "Unstashed Size"

        var image: Image {
            switch self {
            case .position:
                Image(systemName: "viewfinder")
            case .size:
                Image(systemName: "rectangle.expand.diagonal")
            }
        }
    }

    private let defaultAnchor: CustomWindowActionAnchor = .topLeft

    private var anchors: [CustomWindowActionAnchor] {
        [.topLeft, .none, .topRight,
         .left, .none, .right,
         .bottomLeft, .bottom, .bottomRight]
    }

    private var sizeModes: [CustomWindowActionSizeMode] {
        [.custom, .preserveSize]
    }

    private var actionUnit: CustomWindowActionUnit {
        action.unit ?? .percentage
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
            ScreenView(isBlurred: action.sizeMode != .custom) {
                ActionPreview(action: action)
            }

            configurationSections()
            actionButtons()
        }
        .onChange(of: action) { newValue in
            guard !isDeferringExternalCommit else { return }
            windowAction = newValue
        }
    }

    @ViewBuilder
    private func configurationSections() -> some View {
        LuminareSection(outerPadding: 0) {
            LuminareTextField(
                WindowDirection.stash.name,
                text: Binding(get: { action.name ?? "" }, set: { action.name = $0 })
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
        .animation(luminareAnimation, value: action.unit)
        .onAppear {
            if action.unit == nil {
                action.unit = .percentage
            }

            if action.sizeMode == nil {
                action.sizeMode = .custom
            }

            if action.width == nil {
                action.width = 80
            }

            if action.height == nil {
                action.height = 80
            }

            if action.positionMode == nil {
                action.positionMode = .generic
            }

            if action.anchor == nil {
                action.anchor = defaultAnchor
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
                Text(tab.rawValue)
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
                .disabled(action.sizeMode != .custom)

            Button {
                isPresented = false
            } label: {
                Text("Close", comment: "Label for a button that closes a modal window")
            }
        }
        .buttonStyle(.luminare(overrideUseMainStyle: true))
        .luminareCornerRadius(8)
    }

    @ViewBuilder
    private func positionConfiguration() -> some View {
        if action.positionMode ?? .generic == .generic {
            LuminarePicker(
                elements: anchors,
                selection: Binding(
                    get: {
                        action.anchor ?? defaultAnchor
                    },
                    set: { newValue in
                        withAnimation(luminareAnimation) {
                            action.anchor = newValue
                        }
                    }
                ),
                columns: 3
            ) { anchor in
                if let action = anchor.iconAction {
                    IconView(action: action)
                }
            }
            .luminareRoundingBehavior(top: true, bottom: true)
        } else {
            LuminareSlider(
                String(localized: "X", comment: "X axis label"),
                value: Binding(
                    get: {
                        action.xPoint ?? 0
                    },
                    set: {
                        action.xPoint = actionUnit.roundIfNeeded($0)
                    }
                ),
                in: actionUnit == .percentage ? 0...100 : 0...Double(screenSize.width),
                format: .number.precision(actionUnit.fractionLength),
                clampsUpper: false,
                suffix: Text(action.unit?.suffix ?? CustomWindowActionUnit.percentage.suffix),
                onEditingChanged: handleSliderEditingChanged,
                onEditingCommit: commitSliderChanges
            )

            LuminareSlider(
                String(localized: "Y", comment: "Y axis label"),
                value: Binding(
                    get: {
                        action.yPoint ?? 0
                    },
                    set: {
                        action.yPoint = actionUnit.roundIfNeeded($0)
                    }
                ),
                in: actionUnit == .percentage ? 0...100 : 0...Double(screenSize.height),
                format: .number.precision(actionUnit.fractionLength),
                clampsUpper: false,
                suffix: Text(action.unit?.suffix ?? CustomWindowActionUnit.percentage.suffix),
                onEditingChanged: handleSliderEditingChanged,
                onEditingCommit: commitSliderChanges
            )
        }
    }

    @ViewBuilder
    private func sizeConfiguration() -> some View {
        LuminarePicker(
            elements: sizeModes,
            selection: Binding(
                get: {
                    action.sizeMode ?? .custom
                },
                set: { newValue in
                    withAnimation(luminareAnimation) {
                        action.sizeMode = newValue
                    }
                }
            ),
            columns: 2
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
            bottom: action.sizeMode != .custom
        )

        if action.sizeMode ?? .custom == .custom {
            LuminareSlider(
                "Width",
                value: Binding(
                    get: {
                        action.width ?? 100
                    },
                    set: {
                        action.width = actionUnit.roundIfNeeded($0)
                    }
                ),
                in: actionUnit == .percentage ? 0...100 : 0...Double(screenSize.width),
                format: .number.precision(actionUnit.fractionLength),
                clampsUpper: false,
                suffix: .init(action.unit?.suffix ?? CustomWindowActionUnit.percentage.suffix),
                onEditingChanged: handleSliderEditingChanged,
                onEditingCommit: commitSliderChanges
            )

            LuminareSlider(
                "Height",
                value: Binding(
                    get: {
                        action.height ?? 100
                    },
                    set: {
                        action.height = actionUnit.roundIfNeeded($0)
                    }
                ),
                in: actionUnit == .percentage ? 0...100 : 0...Double(screenSize.height),
                format: .number.precision(actionUnit.fractionLength),
                clampsUpper: false,
                suffix: .init(action.unit?.suffix ?? CustomWindowActionUnit.percentage.suffix),
                onEditingChanged: handleSliderEditingChanged,
                onEditingCommit: commitSliderChanges
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
}
