//
//  RadialMenuActionItemView.swift
//  Loop
//
//  Created by Kai Azim on 2025-12-08.
//

import Luminare
import SwiftUI

struct RadialMenuActionItemView: View {
    @Binding private var action: RadialMenuBinding
    private let moveUp: () -> ()
    private let moveDown: () -> ()

    init(
        _ action: Binding<RadialMenuBinding>,
        moveUp: @escaping () -> (),
        moveDown: @escaping () -> ()
    ) {
        _action = action
        self.moveUp = moveUp
        self.moveDown = moveDown
    }

    var body: some View {
        HStack(spacing: 12) {
            ActionTargetEditorView(target: $action.target, owner: action.reference)

            Spacer()

            HStack(spacing: 8) {
                Button(action: moveUp) {
                    Image(systemName: "arrow.up")
                        .frame(width: 27, height: 27)
                        .font(.callout)
                        .contentShape(.rect)
                }
                .luminareContentSize(aspectRatio: 1.0, contentMode: .fit, hasFixedHeight: true)
                .luminareRoundingBehavior(top: true, bottom: true)

                Button(action: moveDown) {
                    Image(systemName: "arrow.down")
                        .frame(width: 27, height: 27)
                        .font(.callout)
                        .contentShape(.rect)
                }
                .luminareContentSize(aspectRatio: 1.0, contentMode: .fit, hasFixedHeight: true)
                .luminareRoundingBehavior(top: true, bottom: true)
            }
        }
        .padding(.horizontal, 12)
    }
}
