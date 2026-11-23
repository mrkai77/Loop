//
//  BindingRow.swift
//  Loop
//
//  Created by Kai Azim on 2026-11-23.
//

import SwiftUI

/// A binding row, with the action on the leading side and what runs it on the trailing side.
/// Views marked `fadesWhenCrowded()` give way to a long name, fading out where they're cut off
struct BindingRow<Leading: View, Trailing: View>: View {
    private let trailingSpacing: CGFloat
    private let leading: Leading
    private let trailing: Trailing

    init(
        trailingSpacing: CGFloat = 8,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.trailingSpacing = trailingSpacing
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        BindingRowLayout(spacing: 8, trailingSpacing: trailingSpacing) {
            leading
            trailing
        }
    }
}

extension View {
    func fadesWhenCrowded() -> some View {
        LeadingFadeClip { self }
            .layoutValue(key: FadesWhenCrowded.self, value: true)
    }
}

/// How far a cut off view fades, and how much of it always stays visible
private let fadeWidth: CGFloat = 12

private struct FadesWhenCrowded: LayoutValueKey {
    static let defaultValue = false
}

private struct BindingRowLayout: Layout {
    let spacing: CGFloat
    let trailingSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        guard let leading = subviews.first else {
            return .zero
        }

        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let idealWidth = leading.sizeThatFits(.unspecified).width + trailingWidth(of: sizes.dropFirst().map(\.width))
        return CGSize(width: proposal.width ?? idealWidth, height: sizes.map(\.height).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        guard let leading = subviews.first else {
            return
        }

        let trailing = Array(subviews.dropFirst())
        let idealWidths = trailing.map { $0.sizeThatFits(.unspecified).width }
        let fades = trailing.map { $0[FadesWhenCrowded.self] }

        let reservedWidths = zip(idealWidths, fades).map { $1 ? min($0, fadeWidth) : $0 }
        let leadingWidth = max(0, min(leading.sizeThatFits(.unspecified).width, bounds.width - trailingWidth(of: reservedWidths)))

        var spare = bounds.width - leadingWidth - trailingWidth(of: reservedWidths)
        var widths = reservedWidths
        for index in trailing.indices.reversed() where fades[index] {
            let extra = max(0, min(idealWidths[index] - reservedWidths[index], spare))
            widths[index] += extra
            spare -= extra
        }

        leading.place(
            at: CGPoint(x: bounds.minX, y: bounds.midY),
            anchor: .leading,
            proposal: ProposedViewSize(width: leadingWidth, height: bounds.height)
        )

        var x = bounds.maxX
        for index in trailing.indices.reversed() {
            trailing[index].place(
                at: CGPoint(x: x, y: bounds.midY),
                anchor: .trailing,
                proposal: ProposedViewSize(width: widths[index], height: bounds.height)
            )
            x -= widths[index] + trailingSpacing
        }
    }

    private func trailingWidth(of widths: [CGFloat]) -> CGFloat {
        guard !widths.isEmpty else {
            return 0
        }

        return widths.reduce(0, +) + CGFloat(widths.count - 1) * trailingSpacing + spacing
    }
}

/// Cuts off and fades the leading side when there isn't room, rather than squeezing the content
private struct LeadingFadeClip<Content: View>: View {
    @ViewBuilder let content: Content

    @State private var contentWidth: CGFloat = 0
    @State private var visibleWidth: CGFloat = 0


    private var isCutOff: Bool {
        contentWidth > visibleWidth + 0.5
    }

    var body: some View {
        content
            .fixedSize(horizontal: true, vertical: false)
            .onGeometryChange(for: CGFloat.self, of: \.size.width) { contentWidth = $0 }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .trailing)
            .onGeometryChange(for: CGFloat.self, of: \.size.width) { visibleWidth = $0 }
            .clipped()
            // Clipping doesn't stop the hidden part from taking clicks meant for the action's buttons
            .contentShape(.rect)
            .mask {
                if isCutOff {
                    HStack(spacing: 0) {
                        LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                            .frame(width: fadeWidth)
                        Color.black
                    }
                } else {
                    Color.black
                }
            }
    }
}
