#if DEBUG

    import CoreGraphics
    import Subsurface
    import SwiftUI

    let gestureDebugPointsPerNormalizedUnit: CGFloat = 500

    struct GestureDebugFinger: Identifiable, Equatable {
        let id: Int32
        let position: CGPoint
    }

    enum GestureDebugKind: String {
        case determining
        case swipe
        case magnify
    }

    struct GestureDebugSnapshot {
        static let empty = Self()

        var visible = false
        var kind: GestureDebugKind = .determining
        var originCentroid: CGPoint?
        var processedCentroid: CGPoint?
        var translation: CGPoint = .zero
        var radialDistance: CGFloat = 0
        var swipeAngle: CGFloat = 0
        var fingerCount = 0
        var fingers: [GestureDebugFinger] = []
        var recognitionThreshold: CGFloat = 0
        var swipeStep: CGFloat = 0
        var swipeBaseline: CGFloat?
        var swipeActionReset = false
        var swipeSlot: Int?
        var swipeActionCount = 0
        var swipeBoundaries: [CGFloat] = []
        var magnifyDistance: CGFloat?
        var magnifyOriginDistance: CGFloat?
        var magnifyBaseline: CGFloat?
        var magnifyStep: CGFloat = 0
        var scale: CGFloat = gestureDebugPointsPerNormalizedUnit
    }

    @MainActor
    final class GestureDebugOverlayModel: ObservableObject {
        @Published private(set) var snapshot = GestureDebugSnapshot.empty
        private var rawContacts: [GestureDebugFinger] = []
        private var activeFingerCount = 0

        func begin(
            originCentroid: CGPoint,
            fingerCount: Int,
            recognitionThreshold: CGFloat,
            actionCount: Int,
            swipeStep: CGFloat,
            magnifyStep: CGFloat
        ) {
            activeFingerCount = fingerCount
            rawContacts = []
            snapshot = GestureDebugSnapshot(
                visible: true,
                originCentroid: originCentroid,
                recognitionThreshold: recognitionThreshold,
                swipeStep: swipeStep,
                swipeBaseline: recognitionThreshold > 0 ? recognitionThreshold : nil,
                swipeActionCount: actionCount,
                swipeBoundaries: RadialGestureGeometry.slotBoundaryAngles(actionCount: actionCount),
                magnifyStep: magnifyStep
            )
            snapshot.fingerCount = fingerCount
            applyRawContacts()
        }

        func updateDetermining(centroid: CGPoint, fingerCount: Int) {
            if snapshot.originCentroid == nil {
                begin(
                    originCentroid: centroid,
                    fingerCount: fingerCount,
                    recognitionThreshold: snapshot.recognitionThreshold,
                    actionCount: snapshot.swipeActionCount,
                    swipeStep: snapshot.swipeStep,
                    magnifyStep: snapshot.magnifyStep
                )
            }
            snapshot.kind = .determining
            snapshot.processedCentroid = centroid
            snapshot.translation = relativePosition(of: centroid)
            snapshot.radialDistance = hypot(snapshot.translation.x, snapshot.translation.y)
            snapshot.fingerCount = fingerCount
        }

        func updateSwipe(
            centroid: CGPoint,
            translation: CGPoint,
            angle: CGFloat,
            distance: CGFloat,
            fingerCount: Int
        ) {
            if snapshot.originCentroid == nil {
                begin(
                    originCentroid: CGPoint(x: centroid.x - translation.x, y: centroid.y - translation.y),
                    fingerCount: fingerCount,
                    recognitionThreshold: snapshot.recognitionThreshold,
                    actionCount: snapshot.swipeActionCount,
                    swipeStep: snapshot.swipeStep,
                    magnifyStep: snapshot.magnifyStep
                )
            }
            snapshot.kind = .swipe
            snapshot.processedCentroid = centroid
            snapshot.translation = translation
            snapshot.radialDistance = distance
            snapshot.swipeAngle = angle
            snapshot.fingerCount = fingerCount
        }

        func recordSwipeCommit(distance: CGFloat, slot: Int? = nil) {
            let firstActionDistance = snapshot.recognitionThreshold > 0
                ? snapshot.recognitionThreshold
                : distance
            let baseline = snapshot.swipeBaseline ?? firstActionDistance
            snapshot.swipeBaseline = baseline
            snapshot.swipeActionReset = false
            snapshot.swipeSlot = slot
        }

        func recordSwipeActionReset() {
            snapshot.swipeActionReset = true
        }

        func updateMagnify(
            centroid: CGPoint,
            distance: CGFloat,
            originDistance: CGFloat,
            fingerCount: Int
        ) {
            if snapshot.originCentroid == nil {
                begin(
                    originCentroid: centroid,
                    fingerCount: fingerCount,
                    recognitionThreshold: snapshot.recognitionThreshold,
                    actionCount: snapshot.swipeActionCount,
                    swipeStep: snapshot.swipeStep,
                    magnifyStep: snapshot.magnifyStep
                )
            }
            snapshot.kind = .magnify
            snapshot.processedCentroid = centroid
            snapshot.translation = relativePosition(of: centroid)
            snapshot.radialDistance = hypot(snapshot.translation.x, snapshot.translation.y)
            snapshot.magnifyDistance = distance
            snapshot.magnifyOriginDistance = originDistance
            snapshot.fingerCount = fingerCount
        }

        func recordMagnifyCommit(distance: CGFloat) {
            snapshot.magnifyBaseline = distance
        }

        func updateRawContacts(_ contacts: [MTContact]) {
            let active = SubsurfaceContactFilter.activeTouches(
                from: SubsurfaceContactFilter.removePalms(from: contacts)
            )
            guard activeFingerCount > 0, active.count == activeFingerCount else { return }

            rawContacts = active.map {
                GestureDebugFinger(
                    id: $0.id,
                    position: CGPoint(
                        x: CGFloat($0.normalizedVector.position.x),
                        y: CGFloat($0.normalizedVector.position.y)
                    )
                )
            }
            applyRawContacts()
        }

        func clear() {
            rawContacts = []
            activeFingerCount = 0
            snapshot = .empty
        }

        func displayOffset(
            for point: CGPoint,
            origin: CGPoint,
            scale: CGFloat = gestureDebugPointsPerNormalizedUnit
        ) -> CGPoint {
            CGPoint(
                x: (point.x - origin.x) * scale,
                y: (point.y - origin.y) * scale
            )
        }

        private func applyRawContacts() {
            guard snapshot.originCentroid != nil else {
                snapshot.fingers = rawContacts
                return
            }
            snapshot.fingers = rawContacts
        }

        private func relativePosition(of point: CGPoint) -> CGPoint {
            guard let origin = snapshot.originCentroid else { return .zero }
            return CGPoint(x: point.x - origin.x, y: point.y - origin.y)
        }
    }

#endif
