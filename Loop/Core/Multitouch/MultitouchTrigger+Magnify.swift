//
//  MultitouchTrigger+Magnify.swift
//  Loop
//
//  Created by Kai Azim on 2026-01-30.
//

import CoreGraphics
import Subsurface

/// Magnify handling lives separately from the main trigger as it has its own
/// activation threshold and reversal model, including direction changes between
/// magnify-in and magnify-out gestures and radial-menu center commits
extension MultitouchTrigger {
    func handleMagnify(_ magnify: SubsurfaceGestureEvent.MagnifyEvent, fingerCount: Int) async {
        guard let entry = recognizerRegistry.entry(for: fingerCount) else { return }

        #if DEBUG
            if magnify.phase == .began || magnify.phase == .changed {
                // Keep the processed centroid synchronized with the raw contact dots
                // regardless of whether this gesture is eligible to activate.
                beginDebugGestureIfNeeded(centroid: magnify.centroid, fingerCount: magnify.fingerCount)
                debugOverlayController.updateMagnify(
                    centroid: magnify.centroid,
                    distance: magnify.distance,
                    originDistance: magnify.originDistance,
                    fingerCount: magnify.fingerCount
                )
            }
        #endif

        if let radialMenuGesture = entry.radialMenuGesture {
            await handleRadialMenuMagnify(magnify, fingerCount: fingerCount, gesture: radialMenuGesture)
            return
        }

        switch magnify.phase {
        case .began, .changed:
            guard let session = recognizerRegistry.session(for: fingerCount) else { return }

            if !session.hasGestureBegun {
                let initialGesture = magnify.distance >= magnify.originDistance ? entry.magnifyInGesture : entry.magnifyOutGesture
                guard let initialGesture else {
                    if magnify.phase == .began {
                        // No binding for this direction, so the stroke belongs to the Dock
                        systemGestureFilter.releaseCurrentTouch(fingerCount: fingerCount)
                    }
                    return
                }
                guard handleGestureBegan(fingerCount: fingerCount, gesture: initialGesture) else {
                    return
                }
            }

            guard let session = recognizerRegistry.session(for: fingerCount), !session.isGestureRejected,
                  let activeGesture = session.resolvedGesture
            else {
                return
            }

            if resetMagnifyActionIfNeeded(session: session, magnify: magnify) {
                return
            }

            let crossedActivationThreshold = hasCrossedActivationThreshold(magnify)
            if !session.hasCommittedMagnifyAction {
                guard crossedActivationThreshold,
                      await activateGestureIfNeeded(fingerCount: fingerCount)
                else {
                    return
                }
            } else if !session.hasActivated {
                return
            }

            guard let session = recognizerRegistry.session(for: fingerCount), !session.isGestureRejected else {
                return
            }

            if crossedActivationThreshold,
               magnifyReversalDetected(currentGesture: activeGesture, magnify: magnify) {
                let opposite = activeGesture.kind == .magnifyOut ? entry.magnifyInGesture : entry.magnifyOutGesture
                handleMagnifyReversal(
                    fingerCount: fingerCount,
                    currentGesture: activeGesture,
                    oppositeGesture: opposite,
                    distance: magnify.distance
                )
                return
            }

            #if DEBUG
                var didCommit = false
            #endif
            let allowsRapidRepeatAction = resolvedWindowAction(from: activeGesture).map {
                $0.allowsRapidRepeat || $0.direction == .cycle
            } ?? false

            session.commitMagnify(
                gesture: activeGesture,
                distance: magnify.distance,
                originDistance: magnify.originDistance,
                step: magnifyStepSize,
                allowsRapidRepeat: allowsRapidRepeatAction
            ) { reverse in
                #if DEBUG
                    didCommit = true
                #endif
                triggerSingleAction(
                    from: activeGesture,
                    reverse: reverse,
                    canAdvanceCycle: !session.isRevisitingAction
                )
            }

            #if DEBUG
                if didCommit {
                    debugOverlayController.recordMagnifyCommit(distance: magnify.distance)
                }
            #endif

        case let .ended(reason):
            endStroke(for: fingerCount, reason: reason)

        case .cancelled:
            endStroke(for: fingerCount, reason: nil)

        default:
            break
        }
    }

    /// Magnify within a radial menu gesture triggers the center (last) radial menu action.
    private func handleRadialMenuMagnify(
        _ magnify: SubsurfaceGestureEvent.MagnifyEvent,
        fingerCount: Int,
        gesture: GestureBinding
    ) async {
        switch magnify.phase {
        case .began, .changed:
            if magnify.phase == .began, recognizerRegistry.session(for: fingerCount)?.hasGestureBegun != true {
                handleGestureBegan(fingerCount: fingerCount, gesture: gesture)
            }
            guard let session = recognizerRegistry.session(for: fingerCount), !session.isGestureRejected else { return }
            if resetMagnifyActionIfNeeded(session: session, magnify: magnify) {
                return
            }
            if !session.hasCommittedMagnifyAction {
                guard hasCrossedActivationThreshold(magnify),
                      await activateGestureIfNeeded(fingerCount: fingerCount)
                else {
                    return
                }
            } else if !session.hasActivated {
                return
            }
            guard let session = recognizerRegistry.session(for: fingerCount), !session.isGestureRejected else { return }

            let actions = radialMenuActions
            guard !actions.isEmpty else { return }
            let centerActionIndex = actions.count - 1

            #if DEBUG
                var didCommit = false
            #endif
            session.commitRadialMagnify(
                distance: magnify.distance,
                originDistance: magnify.originDistance,
                step: magnifyStepSize
            ) { reverse in
                #if DEBUG
                    didCommit = true
                #endif
                triggerRadialMenuAction(
                    at: centerActionIndex,
                    from: actions[...],
                    reverse: reverse,
                    canAdvanceCycle: !session.isRevisitingAction
                )
            }

            #if DEBUG
                if didCommit {
                    debugOverlayController.recordMagnifyCommit(distance: magnify.distance)
                }
            #endif

        case let .ended(reason):
            endStroke(for: fingerCount, reason: reason)

        case .cancelled:
            endStroke(for: fingerCount, reason: nil)

        default:
            break
        }
    }

    private func magnifyReversalDetected(
        currentGesture: GestureBinding,
        magnify: SubsurfaceGestureEvent.MagnifyEvent
    ) -> Bool {
        switch currentGesture.kind {
        case .magnifyOut:
            magnify.distance >= magnify.originDistance
        case .magnifyIn:
            magnify.distance <= magnify.originDistance
        default:
            false
        }
    }

    private func hasCrossedActivationThreshold(_ magnify: SubsurfaceGestureEvent.MagnifyEvent) -> Bool {
        abs(magnify.distance - magnify.originDistance) >= magnifyStepSize
    }

    private func resetMagnifyActionIfNeeded(
        session: MultitouchGestureSession,
        magnify: SubsurfaceGestureEvent.MagnifyEvent
    ) -> Bool {
        let hadCommittedAction = session.hasCommittedMagnifyAction
        let isInsideNoSelectionZone = session.resetMagnifyActionIfNeeded(
            distance: magnify.distance,
            originDistance: magnify.originDistance,
            step: magnifyStepSize
        )
        if isInsideNoSelectionZone, hadCommittedAction {
            clearActionSelection()
        }
        return isInsideNoSelectionZone
    }

    private func handleMagnifyReversal(
        fingerCount: Int,
        currentGesture: GestureBinding,
        oppositeGesture: GestureBinding?,
        distance: CGFloat
    ) {
        guard let oppositeGesture else {
            // There is no action to reverse into. Keep the stroke alive, like swipes do
            return
        }

        guard let session = recognizerRegistry.session(for: fingerCount) else { return }
        if session.switchMagnifyGesture(to: oppositeGesture, distance: distance) {
            #if DEBUG
                debugOverlayController.recordMagnifyCommit(distance: distance)
            #endif
            triggerSwitchedGesture(oppositeGesture, session: session)
            return
        }

        if isCycleAction(currentGesture) {
            triggerSingleAction(from: currentGesture, reverse: true)
            recognizerRegistry.session(for: fingerCount)?.synchronizeMagnifyStepIndex(
                distance: distance,
                step: magnifyStepSize
            )
        } else {
            resetLoopState(for: fingerCount, forceClose: true, endsStroke: false)
        }
    }
}
