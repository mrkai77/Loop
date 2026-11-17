//
//  IconView.swift
//  Loop
//
//  Created by Kai Azim on 2026-01-21.
//

import SwiftUI

/// An icon to represent a `WindowAction`. For a cycle, pass `ActionTargetEditorGraph.iconAction(for:)`.
/// Icons will prioritize using the action's `icon` property, then a simple frame preview, and finally a default icon.
/// - the `icon` property is used for common actions like hide, minimize, growing and shrinking, which cannot be easily represented by a frame.
/// - a simple frame preview is used for more general actions such as right half, maximize, and center, as well as custom keybinds when available.
/// - finally, a default icon is used for cycle actions and actions without a specific icon or frame representation as backup (just in case, they shouldn't be needed in practice).
struct IconView: NSViewRepresentable {
    private let source: Source
    private let size: CGSize

    private enum Source {
        case action(WindowAction)
        case direction(WindowDirection)
    }

    init(
        action: WindowAction,
        size: CGSize = .init(
            width: 18,
            height: 14
        )
    ) {
        self.source = .action(action)
        self.size = size
    }

    init(
        direction: WindowDirection,
        size: CGSize = .init(
            width: 18,
            height: 14
        )
    ) {
        self.source = .direction(direction)
        self.size = size
    }

    func makeNSView(context _: Context) -> IconRenderView {
        let view = IconRenderView()
        setSource(on: view, animated: false)

        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: size.width),
            view.heightAnchor.constraint(equalToConstant: size.height)
        ])

        return view
    }

    func updateNSView(_ view: IconRenderView, context _: Context) {
        setSource(on: view, animated: true)
    }

    private func setSource(on view: IconRenderView, animated: Bool) {
        switch source {
        case let .action(action):
            view.setAction(to: action, animated: animated)
        case let .direction(direction):
            view.setDirection(to: direction, animated: animated)
        }
    }
}

final class IconRenderView: NSView {
    private var currentAction: WindowAction?
    private var currentKind: WindowAction.Kind?
    private var lastDisplayMode: DisplayMode?

    private let strokeLayer = CAShapeLayer()
    private let fillLayer = CAShapeLayer()
    private let imageLayer = CALayer()

    private let cornerRadius: CGFloat = 3
    private let inset: CGFloat = 2
    private let strokeWidth: CGFloat = 1.5

    enum DisplayMode {
        case frame(CGRect)
        case image(NSImage)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func setAction(
        to action: WindowAction,
        animated: Bool
    ) {
        guard action.kind != currentKind else { return }

        currentKind = action.kind
        currentAction = action
        updatePath(duration: animated ? 0.2 : 0.0)
    }

    func setDirection(
        to direction: WindowDirection,
        animated: Bool
    ) {
        let action = WindowAction(direction)
        guard action.kind != currentKind else { return }

        currentKind = action.kind
        currentAction = action
        updatePath(duration: animated ? 0.2 : 0.0)
    }

    override func layout() {
        super.layout()
        updatePath(duration: 0.0)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    // MARK: - Private

    private func setup() {
        wantsLayer = true
        clipsToBounds = true

        layer?.addSublayer(strokeLayer)
        layer?.addSublayer(fillLayer)
        layer?.addSublayer(imageLayer)

        strokeLayer.lineWidth = 1
        strokeLayer.cornerCurve = .continuous
        fillLayer.cornerCurve = .continuous
        imageLayer.contentsGravity = .resizeAspect

        updateColors()
    }

    private func updateColors() {
        strokeLayer.fillColor = .clear
        strokeLayer.strokeColor = NSColor.textColor.cgColor
        fillLayer.fillColor = NSColor.textColor.cgColor

        if case let .image(image) = lastDisplayMode {
            imageLayer.contents = processImage(image, color: .textColor)
        }
    }

    private func updatePath(duration: CFTimeInterval) {
        strokeLayer.frame = bounds
        fillLayer.frame = bounds

        let strokeInset = strokeWidth / 2
        processStrokeLayerPath(strokeInset: strokeInset)

        let fillInset = strokeInset + inset
        let fillBounds = bounds.insetBy(dx: fillInset, dy: fillInset)

        guard let displayMode = determineDisplayMode(fillBounds: fillBounds) else {
            fillLayer.opacity = 0
            imageLayer.opacity = 0
            return
        }

        switch displayMode {
        case let .frame(fillRect):
            let newPath = CGPath(
                roundedRect: fillRect,
                cornerWidth: cornerRadius - inset,
                cornerHeight: cornerRadius - inset,
                transform: nil
            )
            animateAlpha(layer: fillLayer, to: 1, duration: duration)
            animateAlpha(layer: imageLayer, to: 0, duration: duration)
            animatePath(layer: fillLayer, to: newPath, duration: duration)
        case let .image(image):
            imageLayer.contents = processImage(image, color: .textColor)
            imageLayer.frame = getImageBounds(for: image)
            animateAlpha(layer: fillLayer, to: 0, duration: duration)
            animateAlpha(layer: imageLayer, to: 1, duration: duration)
        }

        lastDisplayMode = displayMode
    }

    private func processStrokeLayerPath(strokeInset: CGFloat) {
        let strokeRect = bounds.insetBy(dx: strokeInset, dy: strokeInset)
        let strokePath = CGPath(
            roundedRect: strokeRect,
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )
        strokeLayer.path = strokePath
    }

    private func determineDisplayMode(fillBounds: CGRect) -> DisplayMode? {
        guard let currentAction else { return nil }

        if let image = currentAction.image {
            return .image(image.nsImage)
        }

        let frame = WindowFrameResolver.getFrame(
            for: currentAction,
            bounds: .init(origin: .zero, size: .init(width: 1, height: 1)),
            padding: .zero
        ).flipY(maxY: 1)

        if frame.size.area != 0 {
            let fillFrame = CGRect(
                x: fillBounds.minX + fillBounds.width * frame.minX,
                y: fillBounds.minY + fillBounds.height * frame.minY,
                width: fillBounds.width * frame.width,
                height: fillBounds.height * frame.height
            )

            return .frame(fillFrame)
        }

        if let image = currentAction.backupImage {
            return .image(image.nsImage)
        }

        return nil
    }

    private func animatePath(
        layer: CAShapeLayer,
        to target: CGPath,
        duration: CFTimeInterval
    ) {
        if duration > 0 {
            let animation = CABasicAnimation(keyPath: "path")
            animation.fromValue = layer.path
            animation.toValue = target
            animation.duration = duration
            animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(animation, forKey: "path")
        }

        layer.path = target
    }

    private func animateAlpha(
        layer: CALayer,
        to target: Float,
        duration: CFTimeInterval
    ) {
        if duration > 0 {
            let animation = CABasicAnimation(keyPath: "opacity")
            animation.fromValue = layer.opacity
            animation.toValue = target
            animation.duration = duration
            animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(animation, forKey: "opacity")
        }

        layer.opacity = target
    }

    private func processImage(_ image: NSImage, color: NSColor) -> NSImage? {
        guard image.isTemplate else { return image }
        let image = image.withSymbolConfiguration(.init(pointSize: 12, weight: .bold)) ?? image

        let sizedImage = NSImage(size: image.size)
        sizedImage.lockFocus()
        defer { sizedImage.unlockFocus() }

        image.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
        color.setFill()
        let rect = NSRect(origin: .zero, size: image.size)
        rect.fill(using: .sourceIn)

        return sizedImage
    }

    private func getImageBounds(for image: NSImage) -> NSRect {
        let insetBounds = bounds.insetBy(dx: strokeWidth, dy: strokeWidth)
        let imageAspectRatio = image.size.width / max(image.size.height, 1)
        let boundsAspectRatio = insetBounds.width / max(insetBounds.height, 1)

        let imageSize = if imageAspectRatio > boundsAspectRatio {
            CGSize(
                width: insetBounds.width,
                height: insetBounds.width / imageAspectRatio
            )
        } else {
            CGSize(
                width: insetBounds.height * imageAspectRatio,
                height: insetBounds.height
            )
        }

        let squareRect = CGRect(
            x: insetBounds.midX - imageSize.width / 2,
            y: insetBounds.midY - imageSize.height / 2,
            width: imageSize.width,
            height: imageSize.height
        )
        return squareRect
    }
}
