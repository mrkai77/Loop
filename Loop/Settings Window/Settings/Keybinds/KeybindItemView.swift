//
//  KeybindItemView.swift
//  Loop
//
//  Created by Kai Azim on 2024-05-03.
//

import Luminare
import SwiftUI
import Tome

struct KeybindItemView: View {
    @TomeValue(\.triggerKey) private var triggerKey

    @Binding private var action: KeyBinding
    /// Conflicting keybinds are all disabled
    private let hasConflict: Bool

    init(_ action: Binding<KeyBinding>, hasConflict: Bool) {
        _action = action
        self.hasConflict = hasConflict
    }

    var body: some View {
        ZStack {
            ActionTargetEditorView(target: $action.target, owner: action.reference)
                .frame(maxWidth: .infinity, alignment: .leading)

            keybindCombination
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 12)
    }

    private var keybindCombination: some View {
        HStack {
            HStack(spacing: 6) {
                keycorderSection()
                    .padding(.leading, 4)
                    .luminareToolTip(attachedTo: .topLeading, hidden: !hasConflict) {
                        Text("Another keybind uses this key combination.")
                            .padding(6)
                    }
                    .luminareTint(overridingWith: .red)
            }
            .fixedSize()
        }
        .luminareCornerRadius(8)
    }

    // MARK: - Helper Methods

    /// Switches to standard mode (keeps the keybind)
    private func restoreStandardMode() {
        action.keys.names.subtract(triggerKey.names)
        action.bypassTriggerKey = false
    }

    /// Merges trigger key into action key and switches to bypass mode
    private func switchToBypassMode() {
        action.keys.names.formUnion(triggerKey.names)
        action.bypassTriggerKey = true
    }

    /// Clears the keybind and switches to standard mode
    private func clearKeybind() {
        action.keys = []
        action.bypassTriggerKey = false
    }

    private func keycorderSection() -> some View {
        HStack(spacing: 6) {
            if action.bypassTriggerKey != true {
                HStack(spacing: 6) {
                    ForEach(KeyNames.components(from: triggerKey.names).compactMap(KeyNames.modifierSystemImage), id: \.self) { image in
                        Text("\(Image(systemName: image))")
                    }
                }
                .font(.callout)
                .padding(6)
                .frame(height: 27)
                .luminareSurface()

                Image(systemName: "plus")
                    .foregroundStyle(.secondary)
            }

            Keycorder($action)
                .opacity(hasConflict || action.keys.isEmpty ? 0.5 : 1)
        }
        .contextMenu {
            if action.bypassTriggerKey == true {
                Button("Link Trigger Key", action: restoreStandardMode)
            } else {
                Button("Unlink Trigger Key", action: switchToBypassMode)
            }

            Button("Clear Keybind", action: clearKeybind)
        }
    }
}
