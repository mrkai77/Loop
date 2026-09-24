#if DEBUG

import AppKit
import Subsurface
import SwiftUI

@MainActor
final class GestureDebugOverlayController {
    static let isEnabled = ProcessInfo.processInfo.isEnvironmentFlagEnabled("LOOP_GESTURE_DEBUG_OVERLAY")

    let model = GestureDebugOverlayModel()
    private var windowController: NSWindowController?
    private var preserveDuringSwipeReset = false

    func begin(
        originCentroid: CGPoint,
        fingerCount: Int,
        recognitionThreshold: CGFloat,
        actionCount: Int,
        swipeStep: CGFloat,
        magnifyStep: CGFloat,
        screenCenter: CGPoint
    ) {
        model.begin(
            originCentroid: originCentroid,
            fingerCount: fingerCount,
            recognitionThreshold: recognitionThreshold,
            actionCount: actionCount,
            swipeStep: swipeStep,
            magnifyStep: magnifyStep
        )

        let size = CGSize(width: 520, height: 520)
        let panel: ActivePanel
        if let existing = windowController?.window as? ActivePanel {
            panel = existing
        } else {
            panel = ActivePanel(
                contentRect: CGRect(origin: .zero, size: size),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: true
            )
            panel.ignoresMouseEvents = true
            panel.becomesKeyOnlyIfNeeded = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.hasShadow = false
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
            panel.contentView = NSHostingView(rootView: GestureDebugOverlayView(model: model))
            windowController = NSWindowController(window: panel)
        }

        panel.setContentSize(size)
        panel.setFrameOrigin(
            CGPoint(x: screenCenter.x - size.width / 2, y: screenCenter.y - size.height / 2)
        )
        panel.orderFrontRegardless()
    }

    func updateDetermining(centroid: CGPoint, fingerCount: Int) {
        model.updateDetermining(centroid: centroid, fingerCount: fingerCount)
    }

    func updateSwipe(
        centroid: CGPoint,
        translation: CGPoint,
        angle: CGFloat,
        distance: CGFloat,
        fingerCount: Int
    ) {
        model.updateSwipe(
            centroid: centroid,
            translation: translation,
            angle: angle,
            distance: distance,
            fingerCount: fingerCount
        )
    }

    func recordSwipeCommit(distance: CGFloat, slot: Int? = nil) {
        model.recordSwipeCommit(distance: distance, slot: slot)
    }

    func recordSwipeActionReset() {
        preserveDuringSwipeReset = true
        model.recordSwipeActionReset()
    }

    func updateMagnify(
        centroid: CGPoint,
        distance: CGFloat,
        originDistance: CGFloat,
        fingerCount: Int
    ) {
        model.updateMagnify(
            centroid: centroid,
            distance: distance,
            originDistance: originDistance,
            fingerCount: fingerCount
        )
    }

    func recordMagnifyCommit(distance: CGFloat) {
        model.recordMagnifyCommit(distance: distance)
    }

    func updateRawContacts(_ contacts: [MTContact]) {
        model.updateRawContacts(contacts)
    }

    func close(force: Bool = false) {
        guard force || !preserveDuringSwipeReset else { return }
        preserveDuringSwipeReset = false
        model.clear()
        windowController?.window?.orderOut(nil)
        windowController?.close()
        windowController = nil
    }
}

#endif
