//
//  CycleStepItemView.swift
//  Loop
//
//  Created by Kai Azim on 2026-11-23.
//

import Luminare
import SwiftUI

struct CycleStepItemView: View {
    @Binding var step: CycleStep
    let index: Int

    var body: some View {
        BindingRow(trailingSpacing: 6) {
            BindingActionSelection(
                target: $step.target,
                owner: nil,
                help: "Customize this step’s action."
            )
        } trailing: {
            Text("\(index + 1)")
                .frame(width: 27, height: 27)
                .luminareSurface()
                .luminareCornerRadius(8)
        }
        .padding(.horizontal, 12)
    }
}
