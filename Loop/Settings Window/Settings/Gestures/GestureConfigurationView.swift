//
//  GestureConfigurationView.swift
//  Loop
//
//  Created by Kai Azim on 2026-04-16.
//

import Luminare
import SwiftUI

struct GestureConfigurationView: View {
    @Environment(\.luminareAnimation) private var luminareAnimation

    @State private var gesture: GestureBinding
    @Binding private var externalGesture: GestureBinding
    @Binding private var isPresented: Bool

    init(gesture: Binding<GestureBinding>, isPresented: Binding<Bool>) {
        self.gesture = gesture.wrappedValue
        self._externalGesture = gesture
        self._isPresented = isPresented
    }

    private var kindBinding: Binding<GestureBinding.Kind> {
        Binding(
            get: { gesture.kind },
            set: { newKind in
                let oldKind = gesture.kind
                gesture.kind = newKind

                if newKind == .radialMenu {
                    gesture.action = .radialMenuActions
                } else if oldKind == .radialMenu {
                    gesture.action = .singleAction(.custom(.init(.noAction)))
                }
            }
        )
    }

    private var categoryBinding: Binding<GestureCategory> {
        Binding(
            get: { GestureCategory(kind: gesture.kind) },
            set: { category in
                switch category {
                case .all:
                    kindBinding.wrappedValue = .radialMenu
                case .swipe:
                    if !gesture.kind.isDirectionalSwipe {
                        kindBinding.wrappedValue = .swipeRight
                    }
                case .magnify:
                    kindBinding.wrappedValue = .magnifyOut
                }
            }
        )
    }

    private var swipeDirectionBinding: Binding<SwipeDirection> {
        Binding(
            get: { SwipeDirection(kind: gesture.kind) ?? .right },
            set: { kindBinding.wrappedValue = $0.kind }
        )
    }

    private var magnifyGestureBinding: Binding<MagnifyGesture> {
        Binding(
            get: { MagnifyGesture(kind: gesture.kind) ?? .magnifyOut },
            set: { kindBinding.wrappedValue = $0.kind }
        )
    }

    private var fingerCountBinding: Binding<Int> {
        Binding(
            get: { gesture.fingerCount },
            set: { count in
                gesture.fingerCount = count

                if isActivationZoneDisabled {
                    gesture.activationZone = .titlebar
                }
            }
        )
    }

    private var isActivationZoneDisabled: Bool {
        gesture.fingerCount <= 2
    }

    var body: some View {
        LuminareForm {
            LuminareSection(outerPadding: 0) {
                LuminareTextField(
                    gesture.defaultName,
                    text: Binding(
                        get: { gesture.name ?? "" },
                        set: { gesture.name = $0 }
                    )
                )
                .luminareFilledStates(.none)
                .luminareBorderedStates(.none)
            }

            LuminareSection {
                LuminarePicker(
                    compactElements: GestureCategory.allCases,
                    selection: categoryBinding
                ) { category in
                    HStack(spacing: 6) {
                        category.image
                            .frame(width: 12)

                        Text(category.displayName)
                    }
                    .fixedSize()
                }
                .luminareContentSize(hasFixedHeight: true)
                .luminareRoundingBehavior(top: true, bottom: gesture.kind == .radialMenu)

                if GestureCategory(kind: gesture.kind) == .swipe {
                    LuminarePickerMenu(
                        "Direction",
                        selection: swipeDirectionBinding,
                        items: SwipeDirection.allCases
                    ) { direction in
                        Text("\(direction.image) \(direction.displayName)")
                    }
                }

                if GestureCategory(kind: gesture.kind) == .magnify {
                    LuminarePickerMenu(
                        "Gesture",
                        selection: magnifyGestureBinding,
                        items: MagnifyGesture.allCases
                    ) { magnifyGesture in
                        Text("\(magnifyGesture.image) \(magnifyGesture.displayName)")
                    }
                }
            }
            .luminareCornerRadius(16)

            LuminareSection {
                LuminareSliderPicker(
                    "Fingers",
                    Array(2...5),
                    selection: fingerCountBinding
                ) { count in
                    Text("\(count)")
                        .monospaced()
                }
                .luminareSliderPickerLayout(.compact(textBoxWidth: 24))

                LuminarePicker(
                    compactElements: GestureBinding.ActivationZone.allCases,
                    selection: $gesture.activationZone
                ) { option in
                    HStack(spacing: 6) {
                        Image(systemName: option.systemImage)

                        Text(option.displayName)
                    }
                    .fixedSize()
                }
                .luminareContentSize(hasFixedHeight: true)
                .luminareRoundingBehavior(bottom: true)
                .opacity(isActivationZoneDisabled ? 0.5 : 1)
                .disabled(isActivationZoneDisabled)
            }
            .luminareCornerRadius(16)

            Button {
                isPresented = false
            } label: {
                Text("Close", comment: "Label for a button that closes a modal window")
            }
            .buttonStyle(.luminare(overrideUseMainStyle: true))
            .luminareCornerRadius(8)
        }
        .animation(luminareAnimation, value: gesture.kind)
        .onChange(of: gesture) { externalGesture = $0 }
    }
}

private enum GestureCategory: CaseIterable, Equatable {
    case all
    case swipe
    case magnify

    init(kind: GestureBinding.Kind) {
        switch kind {
        case .radialMenu:
            self = .all
        case .swipeUp, .swipeDown, .swipeLeft, .swipeRight:
            self = .swipe
        case .magnifyOut, .magnifyIn:
            self = .magnify
        }
    }

    var displayName: String {
        switch self {
        case .all:
            String(localized: "Both", comment: "Gesture category label: swipe and magnify gestures")
        case .swipe:
            String(localized: "Swipe", comment: "Gesture category label: swipe")
        case .magnify:
            String(localized: "Magnify", comment: "Gesture category label: magnify")
        }
    }

    var image: Image {
        switch self {
        case .all:
            Image(.loop)
        case .swipe:
            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
        case .magnify:
            Image(systemName: "arrow.down.left.and.arrow.up.right")
        }
    }
}

private enum SwipeDirection: CaseIterable {
    case up
    case down
    case left
    case right

    init?(kind: GestureBinding.Kind) {
        switch kind {
        case .swipeUp:
            self = .up
        case .swipeDown:
            self = .down
        case .swipeLeft:
            self = .left
        case .swipeRight:
            self = .right
        case .radialMenu, .magnifyOut, .magnifyIn:
            return nil
        }
    }

    var kind: GestureBinding.Kind {
        switch self {
        case .up:
            .swipeUp
        case .down:
            .swipeDown
        case .left:
            .swipeLeft
        case .right:
            .swipeRight
        }
    }

    var displayName: String {
        switch self {
        case .up:
            String(localized: "Up", comment: "Swipe direction picker option: up")
        case .down:
            String(localized: "Down", comment: "Swipe direction picker option: down")
        case .left:
            String(localized: "Left", comment: "Swipe direction picker option: left")
        case .right:
            String(localized: "Right", comment: "Swipe direction picker option: right")
        }
    }

    var image: Image {
        kind.image
    }
}

private enum MagnifyGesture: CaseIterable {
    case magnifyOut
    case magnifyIn

    init?(kind: GestureBinding.Kind) {
        switch kind {
        case .magnifyOut:
            self = .magnifyOut
        case .magnifyIn:
            self = .magnifyIn
        case .radialMenu, .swipeUp, .swipeDown, .swipeLeft, .swipeRight:
            return nil
        }
    }

    var kind: GestureBinding.Kind {
        switch self {
        case .magnifyOut:
            .magnifyOut
        case .magnifyIn:
            .magnifyIn
        }
    }

    var displayName: String {
        switch self {
        case .magnifyOut:
            String(localized: "Pinch", comment: "Magnify gesture picker option: pinch")
        case .magnifyIn:
            String(localized: "Spread", comment: "Magnify gesture picker option: spread")
        }
    }

    var image: Image {
        kind.image
    }
}
