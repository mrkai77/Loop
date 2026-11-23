//
//  RadialMenuActionItemView.swift
//  Loop
//
//  Created by Kai Azim on 2025-12-08.
//

import Luminare
import SwiftUI

struct RadialMenuActionItemView: View {
    @State private var action: RadialMenuBinding
    @Binding private var externalAction: RadialMenuBinding
    private let moveUp: () -> ()
    private let moveDown: () -> ()

    init(
        _ action: Binding<RadialMenuBinding>,
        moveUp: @escaping () -> (),
        moveDown: @escaping () -> ()
    ) {
        self.action = action.wrappedValue
        self._externalAction = action
        self.moveUp = moveUp
        self.moveDown = moveDown
    }

    var body: some View {
        BindingRow {
            BindingActionSelection(target: $action.target, owner: action.identity, help: "Customize this radial menu action.")
        } trailing: {
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
        .padding(.horizontal, 12)
        .onChange(of: action) { externalAction = $0 }
        .onChange(of: externalAction) { if $0 != action { action = $0 } }
    }
}
