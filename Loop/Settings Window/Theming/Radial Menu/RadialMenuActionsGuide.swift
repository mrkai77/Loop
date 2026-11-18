//
//  RadialMenuActionsGuide.swift
//  Loop
//
//  Created by Kai Azim on 2026-01-01.
//

import Luminare
import SwiftUI
import Tome

struct RadialMenuActionsGuide: View {
    @EnvironmentObject private var windowModel: SettingsWindowManager
    @ObservedObject private var accentColorController: AccentColorController = .shared
    @Environment(\.luminareAnimation) private var luminareAnimation

    @TomeValue(\.radialMenuBindings) private var radialMenuActions
    @TomeValue(\.keyBindings) private var keyBindings
    @TomeValue(\.gestureBindings) private var gestures

    private var graph: ActionTargetEditorGraph {
        .init(keyBindings: keyBindings, gestureBindings: gestures, radialMenuBindings: radialMenuActions)
    }

    private var radialActions: [RadialMenuBinding] {
        Array(radialMenuActions.dropLast())
    }

    private var centerAction: RadialMenuBinding {
        radialMenuActions.last ?? .custom(.init(.noAction))
    }

    private var activeAction: WindowAction {
        windowModel.previewedParentAction ?? windowModel.previewedAction
    }

    private var selectedColor: Color {
        windowModel.isPreviewingUserSelection ? accentColorController.color1.opacity(0.6) : accentColorController.color2.opacity(0.3)
    }

    private var buttonShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 12)
    }

    var body: some View {
        ZStack {
            if let centerResolved = graph.previewAction(for: centerAction.target) {
                actionButton(
                    action: centerResolved,
                    isActive: centerResolved == activeAction
                ) {
                    IconView(action: graph.iconAction(for: centerResolved))
                }
            } else {
                actionButton(isActive: false) {
                    Image(systemName: "bolt.horizontal.fill")
                        .foregroundStyle(.secondary)
                }
            }

            RadialLayout {
                ForEach(radialActions, id: \.id) { action in
                    if let resolved = graph.previewAction(for: action.target) {
                        actionButton(
                            action: resolved,
                            isActive: resolved == activeAction
                        ) {
                            IconView(action: graph.iconAction(for: resolved))
                        }
                    } else {
                        actionButton(isActive: false) {
                            Image(systemName: "bolt.horizontal.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .compositingGroup()
        .shadow(radius: 8)
        .frame(width: 200, height: 200)
        .animation(luminareAnimation, value: radialMenuActions)
    }

    private func actionButton(
        action: WindowAction? = nil,
        isActive: Bool,
        content: () -> some View
    ) -> some View {
        Button {
            guard let action else {
                return
            }

            if windowModel.previewedParentAction ?? windowModel.previewedAction == action {
                windowModel.isPreviewingUserSelection.toggle()
            } else {
                windowModel.isPreviewingUserSelection = true
            }

            if windowModel.isPreviewingUserSelection {
                windowModel.setPreviewedAction(to: action)
            }
        } label: {
            ZStack {
                if #available(macOS 26.0, *) {
                    content()
                        .frame(width: 30, height: 30)
                        .glassEffect(
                            .clear.tint(isActive ? selectedColor : nil),
                            in: buttonShape
                        )
                } else {
                    content()
                        .frame(width: 30, height: 30)
                }
            }
            .background {
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                    .padding(0.5) // Fixes odd clipping behavior where slither of view is shown at top
                    .clipShape(buttonShape)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .scaleEffect(isActive ? 1.05 : 0.95)
        .disabled(action == nil)
        .animation(luminareAnimation, value: isActive)
    }
}
