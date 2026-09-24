#if DEBUG

import Foundation
import SwiftUI

struct GestureDebugOverlayView: View {
    @ObservedObject var model: GestureDebugOverlayModel

    private let canvasSize: CGFloat = 520

    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, size in
                drawReference(in: &context, size: size)
                drawRings(in: &context, size: size)
                drawMagnificationRing(in: &context, size: size)
                drawContacts(in: &context, size: size)
            }

//            diagnostics
//                .padding(10)
//                .background(.black.opacity(0.45), in: .rect(cornerRadius: 8))
//                .padding(10)
        }
        .frame(width: canvasSize, height: canvasSize)
        .allowsHitTesting(false)
    }

    private var diagnostics: some View {
        let snapshot = model.snapshot
        let translation = snapshot.translation
        let magnifyDelta = if let distance = snapshot.magnifyDistance,
                               let origin = snapshot.magnifyOriginDistance {
            String(format: "%.4f", distance - origin)
        } else {
            "-"
        }

        return VStack(alignment: .leading, spacing: 2) {
            Text("DEBUG TRACKPAD GESTURE")
                .fontWeight(.semibold)
            Text("kind: \(snapshot.kind.rawValue)  fingers: \(snapshot.fingerCount)")
            Text("scale: \(Int(snapshot.scale)) pt/unit")
            Text("centroid marker: Subsurface event")
            Text("centroid: \(format(snapshot.processedCentroid))")
            Text("translation: \(format(translation))  r: \(format(snapshot.radialDistance))")
            Text("angle: \(format(snapshot.swipeAngle))")
            Text("recognition: \(format(snapshot.recognitionThreshold))")
            Text("swipe baseline: \(format(snapshot.swipeBaseline))  step: \(format(snapshot.swipeStep))")
            Text("swipe action reset: \(snapshot.swipeActionReset ? "yes" : "no")")
            Text("slot: \(snapshot.swipeSlot.map(String.init) ?? "-")")
            Text("magnify: \(format(snapshot.magnifyDistance)) / origin \(format(snapshot.magnifyOriginDistance))")
            Text("magnify Δ: \(magnifyDelta)")
            Text("magnify activation: abs(Δ) >= \(format(snapshot.magnifyStep))")
            Text("magnify committed: \(format(snapshot.magnifyBaseline))")
        }
        .font(.caption)
        .foregroundStyle(.white)
        .fixedSize()
    }

    private func drawReference(in context: inout GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let snapshot = model.snapshot
        let maxRadius = min(size.width, size.height) / 2 - 6

        for angle in snapshot.swipeBoundaries {
            let endpoint = point(from: center, angle: angle, radius: maxRadius)
            var path = Path()
            path.move(to: center)
            path.addLine(to: endpoint)
            context.stroke(path, with: .color(.cyan.opacity(0.32)), lineWidth: 1.5)
        }

        let recognitionRadius = snapshot.recognitionThreshold * snapshot.scale
        if recognitionRadius > 0, recognitionRadius <= maxRadius {
            context.stroke(
                Path(ellipseIn: CGRect(
                    x: center.x - recognitionRadius,
                    y: center.y - recognitionRadius,
                    width: recognitionRadius * 2,
                    height: recognitionRadius * 2
                )),
                with: .color(.yellow.opacity(0.7)),
                lineWidth: 1.5
            )
        }
    }

    private func drawRings(in context: inout GraphicsContext, size: CGSize) {
        guard let baseline = model.snapshot.swipeBaseline else { return }
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let maxRadius = min(size.width, size.height) / 2 - 6
        let radii = RadialGestureGeometry.thresholdRadii(
            baseline: baseline,
            step: model.snapshot.swipeStep,
            maximum: maxRadius / model.snapshot.scale
        )

        for radius in radii {
            let renderedRadius = radius * model.snapshot.scale
            let isBaseline = abs(radius - baseline) < 0.0001
            let isNext = abs(abs(radius - baseline) - model.snapshot.swipeStep) < 0.0001
            let color: Color = isBaseline ? .green : (isNext ? .orange : .purple)
            let lineWidth: CGFloat = 1.5

            context.stroke(
                Path(ellipseIn: CGRect(
                    x: center.x - renderedRadius,
                    y: center.y - renderedRadius,
                    width: renderedRadius * 2,
                    height: renderedRadius * 2
                )),
                with: .color(color.opacity(isBaseline || isNext ? 0.8 : 0.35)),
                lineWidth: lineWidth
            )
        }
    }

    private func drawMagnificationRing(in context: inout GraphicsContext, size: CGSize) {
        let snapshot = model.snapshot
        guard let distance = snapshot.magnifyDistance,
              let originDistance = snapshot.magnifyOriginDistance,
              let baseline = snapshot.swipeBaseline,
              let radius = RadialGestureGeometry.magnificationDisplayRadius(
                  distance: distance,
                  originDistance: originDistance,
                  activationRadius: baseline,
                  ringStep: snapshot.swipeStep,
                  magnificationStep: snapshot.magnifyStep
              )
        else {
            return
        }

        let renderedRadius = radius * snapshot.scale
        let maxRadius = min(size.width, size.height) / 2 - 6
        guard renderedRadius > 0, renderedRadius <= maxRadius else { return }

        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        context.stroke(
            Path(ellipseIn: CGRect(
                x: center.x - renderedRadius,
                y: center.y - renderedRadius,
                width: renderedRadius * 2,
                height: renderedRadius * 2
            )),
            with: .color(.teal.opacity(0.9)),
            lineWidth: 1.5
        )
    }

    private func drawContacts(in context: inout GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let snapshot = model.snapshot

        for (index, finger) in snapshot.fingers.enumerated() {
            let point = plot(finger.position, origin: snapshot.originCentroid, center: center, scale: snapshot.scale)
            let color = [Color.red, .blue, .green, .pink, .mint, .indigo][index % 6]
            context.fill(
                Path(ellipseIn: CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10)),
                with: .color(color.opacity(0.75))
            )
            context.stroke(
                Path(ellipseIn: CGRect(x: point.x - 8, y: point.y - 8, width: 16, height: 16)),
                with: .color(color.opacity(0.45)),
                lineWidth: 1.5
            )
        }

        if let centroid = snapshot.processedCentroid {
            let point = plot(centroid, origin: snapshot.originCentroid, center: center, scale: snapshot.scale)
            var crosshair = Path()
            crosshair.move(to: CGPoint(x: point.x - 9, y: point.y))
            crosshair.addLine(to: CGPoint(x: point.x + 9, y: point.y))
            crosshair.move(to: CGPoint(x: point.x, y: point.y - 9))
            crosshair.addLine(to: CGPoint(x: point.x, y: point.y + 9))
            context.stroke(crosshair, with: .color(.white.opacity(0.95)), lineWidth: 1.5)
        }
    }

    private func plot(
        _ point: CGPoint,
        origin: CGPoint?,
        center: CGPoint,
        scale: CGFloat
    ) -> CGPoint {
        guard let origin else { return center }
        let offset = model.displayOffset(for: point, origin: origin, scale: scale)
        return CGPoint(
            x: center.x + offset.x,
            y: center.y - offset.y
        )
    }

    private func point(from center: CGPoint, angle: CGFloat, radius: CGFloat) -> CGPoint {
        CGPoint(
            x: center.x + sin(angle) * radius,
            y: center.y - cos(angle) * radius
        )
    }

    private func format(_ point: CGPoint?) -> String {
        guard let point else { return "-" }
        return String(format: "%.4f, %.4f", point.x, point.y)
    }

    private func format(_ value: CGFloat?) -> String {
        guard let value else { return "-" }
        return String(format: "%.4f", value)
    }
}

#endif
