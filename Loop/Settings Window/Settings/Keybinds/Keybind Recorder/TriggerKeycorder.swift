//
//  TriggerKeycorder.swift
//  Loop
//
//  Created by Kai Azim on 2023-09-11.
//

import Defaults
import Luminare
import SwiftUI

struct TriggerKeycorder: View {
    @EnvironmentObject private var model: KeybindsConfigurationModel
    @Environment(\.luminareAnimation) private var luminareAnimation
    @Environment(\.appearsActive) private var appearsActive

    let keyLimit: Int = 5

    @Default(.sideDependentTriggerKey) private var sideDependentTriggerKey

    @Binding private var validCurrentKey: Set<CGKeyCode>
    @State private var selectionKey: Set<CGKeyCode>

    @State private var eventMonitor: LocalEventMonitor?
    @State private var shouldShake: Bool = false
    @State private var isHovering: Bool = false
    @State private var isActive: Bool = false
    @State private var tooManyKeysPopup: Bool = false

    @State private var totalWidth: CGFloat = 0
    @State private var triggerKeyIndicatorWidth: CGFloat = 0
    @State private var changeButtonWidth: CGFloat = 0

    private var sortedKeys: [CGKeyCode] {
        let selectionKey: Set<CGKeyCode> = sideDependentTriggerKey ? selectionKey : selectionKey.baseModifiers
        return selectionKey.sorted()
    }

    private var shouldShowChangeButton: Bool {
        let totalLeadingWidth = triggerKeyIndicatorWidth + 4.0
        return (totalWidth - totalLeadingWidth) < changeButtonWidth
    }

    init(_ key: Binding<Set<CGKeyCode>>) {
        self._validCurrentKey = key
        _selectionKey = State(initialValue: key.wrappedValue)
    }

    var body: some View {
        ZStack {
            triggerKeyIndicator
                .onGeometryChange(for: CGFloat.self, of: \.size.width) { triggerKeyIndicatorWidth = $0 }
                .frame(maxWidth: .infinity, alignment: .leading)

            changeButton
                .onGeometryChange(for: CGFloat.self, of: \.size.width) { changeButtonWidth = $0 }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .opacity(shouldShowChangeButton ? 0 : 1)
        }
        .buttonStyle(.luminare(overrideUseMainStyle: true))
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { totalWidth = $0 }
    }

    private var triggerKeyIndicator: some View {
        Button {
            guard !isActive else { return }
            startObservingKeys()
        } label: {
            if selectionKey.isEmpty {
                Text(isActive ? "Set a trigger key…" : "None")
                    .frame(height: 32)
                    .padding(.horizontal, 12)
            } else {
                HStack(spacing: 12) {
                    ForEach(sortedKeys, id: \.self) { key in
                        TriggerKeycorderKeyView(key: key)

                        if key != sortedKeys.last {
                            Divider()
                                .padding(.vertical, 1)
                        }
                    }
                }
                .frame(height: 32)
                .padding(.horizontal, 12)
            }
        }
        .modifier(ShakeEffect(shakes: shouldShake ? 2 : 0))
        .animation(luminareAnimation, value: sideDependentTriggerKey)
        .animation(Animation.default, value: shouldShake)
        .popover(isPresented: $tooManyKeysPopup, arrowEdge: .bottom) {
            Text("You can only use up to \(keyLimit) keys in your trigger key.")
                .multilineTextAlignment(.center)
                .padding(8)
        }
        .onHover { hovering in
            isHovering = hovering
        }
        .onChange(of: model.currentEventMonitor) { _ in
            if let eventMonitor, model.currentEventMonitor != eventMonitor {
                finishedObservingKeys(wasForced: true)
            }
        }
        .onChange(of: appearsActive) { _ in
            if appearsActive {
                finishedObservingKeys(wasForced: true)
            }
        }
        .onChange(of: validCurrentKey) { _ in
            if selectionKey != validCurrentKey {
                selectionKey = validCurrentKey
            }
        }
        .fixedSize()
    }

    private var changeButton: some View {
        Button {
            guard !isActive else { return }
            startObservingKeys()
        } label: {
            Text("Change")
                .frame(height: 32)
                .padding(.horizontal, 12)
        }
        .fixedSize()
    }

    private func startObservingKeys() {
        selectionKey = []
        isActive = true

        LoopManager.shared.keybindTrigger.stop()

        eventMonitor = LocalEventMonitor(events: [.keyDown, .flagsChanged]) { event in
            // keyDown event is only used to track escape key, as its flags can include an Fn flag that isn't actually held
            if event.type == .keyDown {
                if event.keyCode == CGKeyCode.kVK_Escape {
                    finishedObservingKeys(wasForced: true)
                }
                return nil
            }

            let flags = CGEventFlags(cocoaFlags: event.modifierFlags)
            let keycodes = flags.keyCodes
            selectionKey.formUnion(keycodes)

            if keycodes.isEmpty, !selectionKey.isEmpty {
                finishedObservingKeys()
                return nil
            }

            if !keycodes.isEmpty, selectionKey.isEmpty {
                shake()
            }

            return nil
        }

        eventMonitor!.start()
        model.currentEventMonitor = eventMonitor
    }

    private func finishedObservingKeys(wasForced: Bool = false) {
        var willSet = !wasForced

        if selectionKey.count > keyLimit {
            willSet = false
            shake()
            tooManyKeysPopup = true
        }

        isActive = false

        if willSet {
            // Set the valid keybind to the current selected one
            validCurrentKey = selectionKey
        } else {
            // Set preview keybind back to previous one
            selectionKey = validCurrentKey
        }

        eventMonitor?.stop()
        eventMonitor = nil

        Task {
            await LoopManager.shared.keybindTrigger.start()
        }
    }

    private func shake() {
        Task {
            shouldShake.toggle()
        }
    }
}

struct TriggerKeycorderKeyView: View {
    @Default(.sideDependentTriggerKey) private var sideDependentTriggerKey
    private static let defaultIconName = "exclamationmark.circle.fill"
    let key: CGKeyCode

    var body: some View {
        HStack(spacing: 4) {
            let keyImage = Image(systemName: key.modifierSystemImage ?? Self.defaultIconName)

            if sideDependentTriggerKey {
                let side: String = key.isModifierOnRightSide
                    ? String(localized: "Right", comment: "Side of a trigger key")
                    : String(localized: "Left", comment: "Side of a trigger key")

                Text(
                    "\(side) \(keyImage)",
                    comment: "Format for modifier key + side; %1$@ is the key (e.g. command), %2$@ is the side (left/right)"
                )
            } else {
                keyImage
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fixedSize(horizontal: true, vertical: false)
    }
}
