//
//  KeybindItemView.swift
//  Loop
//
//  Created by Kai Azim on 2024-05-03.
//

import Defaults
import Luminare
import SwiftUI

struct KeybindItemView: View {
    @Default(.triggerKey) private var triggerKey
    @Default(.keybinds) private var keybinds

    @State private var keybind: Keybind
    @Binding private var externalKeybind: Keybind

    init(_ keybind: Binding<Keybind>) {
        self.keybind = keybind.wrappedValue
        self._externalKeybind = keybind
    }

    private var hasDuplicateKeybinds: Bool {
        let others = keybinds.filter { $0.id != keybind.id }
        return Keybind.conflictingIDs(in: others + [keybind], triggerKey: triggerKey).contains(keybind.id)
    }

    var body: some View {
        // The row's 8 points of spacing and the action button's 4 points of padding make 12, as between the controls
        BindingRow(trailingSpacing: 6) {
            BindingActionSelection(
                target: $keybind.target,
                owner: keybind.identity,
                help: "Customize this keybind’s action."
            )
        } trailing: {
            if hasDuplicateKeybinds {
                LuminareToolTip(systemImage: "exclamationmark.triangle.fill", text: Text("Another keybind uses this key combination."))
            }

            // The trigger key is the same on every keybind, so a long name may cover it
            if !keybind.bypassTriggerKey {
                triggerKeyIndicator
                    .fadesWhenCrowded()
            }

            Keycorder($keybind)
                .opacity(hasDuplicateKeybinds || keybind.keys.isEmpty ? 0.5 : 1)
                .contextMenu { keybindMenu }
                .luminareTint(overridingWith: .red)
                .luminareCornerRadius(8)
                .fixedSize()
        }
        .padding(.horizontal, 12)
        .onChange(of: keybind) { externalKeybind = $0 }
        // Edits through a link from another row change this binding directly
        .onChange(of: externalKeybind) { if $0 != keybind { keybind = $0 } }
    }

    // MARK: - Helper Methods

    /// Switches to standard mode (keeps the keybind)
    private func restoreStandardMode() {
        keybind.keys = keybind.keys.subtracting(triggerKey)
        keybind.bypassTriggerKey = false
    }

    /// Merges trigger key into action key and switches to bypass mode
    private func switchToBypassMode() {
        keybind.keys = triggerKey.union(keybind.keys)
        keybind.bypassTriggerKey = true
    }

    /// Clears the keybind and switches to standard mode
    private func clearKeybind() {
        keybind.keys = []
        keybind.bypassTriggerKey = false
    }

    private var triggerKeyIndicator: some View {
        HStack(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(triggerKey.sorted().compactMap(\.modifierSystemImage), id: \.self) { image in
                    Text("\(Image(systemName: image))")
                }
            }
            .font(.callout)
            .padding(6)
            .frame(height: 27)
            .luminareSurface()
            .luminareCornerRadius(8)

            Image(systemName: "plus")
                .foregroundStyle(.secondary)
        }
        .contextMenu { keybindMenu }
    }

    @ViewBuilder
    private var keybindMenu: some View {
        if keybind.bypassTriggerKey {
            Button("Link Trigger Key", action: restoreStandardMode)
        } else {
            Button("Unlink Trigger Key", action: switchToBypassMode)
        }

        Button("Clear Keybind", action: clearKeybind)
    }
}
