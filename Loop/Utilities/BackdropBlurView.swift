//
//  BackdropBlurView.swift
//  Loop
//
//  Created by Kai Azim on 2026-11-21.
//

import SwiftUI

/// A pass-through Gaussian blur of everything behind the window.
struct BackdropBlurView: NSViewRepresentable {
    let radius: CGFloat

    func makeNSView(context _: Context) -> BackdropBlurNSView {
        BackdropBlurNSView(radius: radius)
    }

    func updateNSView(_ view: BackdropBlurNSView, context _: Context) {
        view.radius = radius
    }
}

final class BackdropBlurNSView: NSVisualEffectView {
    var radius: CGFloat {
        didSet {
            guard radius != oldValue else { return }
            reduceToBlur()
        }
    }

    init(radius: CGFloat) {
        self.radius = radius
        super.init(frame: .zero)

        // A behind-window visual effect view is what makes AppKit sample the content behind the window,
        // so this works without making the window transparent. Its material is then reduced to just a blur.
        material = .menu
        blendingMode = .behindWindow
        state = .active
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// The blur is purely visual
    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }

    // AppKit rebuilds the material's layers on these occasions (such as appearance changes),
    // so the blur is reapplied after each one. Reapplying is a no-op when nothing has changed.

    override func layout() {
        super.layout()
        reduceToBlur()
    }

    override func updateLayer() {
        super.updateLayer()
        reduceToBlur()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        reduceToBlur()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        reduceToBlur()
    }

    /// Reduces AppKit's material to a plain Gaussian blur of the given radius.
    private func reduceToBlur() {
        guard
            let layer,
            let backdropLayer = Self.findBackdropLayer(in: layer),
            let filters = backdropLayer.filters as? [NSObject]
        else {
            return
        }

        // Keep only the blur (and SDR normalization), dropping the material's saturation boost
        let keptFilters = filters.filter { filter in
            let type = Self.filterType(of: filter)
            return type == "gaussianBlur" || type == "sdrNormalize"
        }

        guard let blurFilter = keptFilters.first(where: { Self.filterType(of: $0) == "gaussianBlur" }) else {
            return
        }

        let radiusChanged = (blurFilter.value(forKey: "inputRadius") as? CGFloat) != radius
        if radiusChanged {
            blurFilter.setValue(radius, forKey: "inputRadius")
        }

        // Filters are only applied when reassigned, so reassign them only when something changed
        if radiusChanged || keptFilters.count != filters.count {
            backdropLayer.filters = keptFilters
        }

        // Hide the material's tint layers, which sit beside the backdrop layer
        for sibling in backdropLayer.superlayer?.sublayers ?? [] where sibling !== backdropLayer && !sibling.isHidden {
            sibling.isHidden = true
        }
    }

    private static func filterType(of filter: NSObject) -> String? {
        filter.value(forKey: "type") as? String
    }

    private static func findBackdropLayer(in layer: CALayer) -> CALayer? {
        if String(describing: type(of: layer)) == "CABackdropLayer" {
            return layer
        }

        for sublayer in layer.sublayers ?? [] {
            if let backdropLayer = findBackdropLayer(in: sublayer) {
                return backdropLayer
            }
        }

        return nil
    }
}
