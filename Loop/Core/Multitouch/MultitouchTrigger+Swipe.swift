//
//  MultitouchTrigger+Swipe.swift
//  Loop
//
//  Created by Kai Azim on 2026-01-30.
//

import CoreGraphics
import Subsurface

/// Swipe handling lives separately from the main trigger as it has its own
/// gesture-selection rules: angle-to-direction mapping, origin-crossing reversal,
/// and radial-menu slot selection all build on swipe-specific geometry
extension MultitouchTrigger {
    func handleSwipe(_ swipe: SubsurfaceGestureEvent.SwipeEvent, fingerCount: Int) async {
        guard let entry = recognizerRegistry.entry(for: fingerCount) else { return }

        if let radialMenuGesture = entry.radialMenuGesture {
            await handleRadialMenuSwipe(swipe, fingerCount: fingerCount, gesture: radialMenuGesture)
        } else {
            let direction = directionalSwipeKind(angle: swipe.angle)
            let directionalGesture = entry.directionalGestures.first { $0.kind == direction }
            let isTerminal = switch swipe.phase {
            case .ended(_), .cancelled:
                true
            default:
                false
            }
            if directionalGesture != nil || entry.session.hasGestureBegun || isTerminal {
                await handleDirectionalSwipe(
                    swipe,
                    fingerCount: fingerCount,
                    direction: direction,
                    matchedGesture: directionalGesture
                )
            }
        }
    }

    private func handleRadialMenuSwipe(
        _ swipe: SubsurfaceGestureEvent.SwipeEvent,
        fingerCount: Int,
        gesture: GestureBinding
    ) async {
        switch swipe.phase {
        case .began, .changed:
            if swipe.phase == .began, recognizerRegistry.session(for: fingerCount)?.hasGestureBegun != true {
                handleGestureBegan(fingerCount: fingerCount, gesture: gesture)
            }
            guard await activateGestureIfNeeded(fingerCount: fingerCount),
                  let session = recognizerRegistry.session(for: fingerCount), !session.isGestureRejected
            else {
                return
            }

            let normalizedAngle = normalizedAngle(fromSubsurfaceAngle: swipe.angle)
            let actions = radialMenuActions.dropLast()
            guard actions.count > 1 else { return }

            let newIndex: Int
            if actions.count == cardinalBiasedRadialMenuActionCount {
                newIndex = indexWithCardinalBias(angle: normalizedAngle, actionCount: actions.count)
            } else {
                let actionAngleSpan = (.pi * 2) / CGFloat(actions.count)
                let halfAngleSpan = actionAngleSpan / 2.0
                newIndex = Int((normalizedAngle + halfAngleSpan) / actionAngleSpan) % actions.count
            }

            session.commitSwipe(
                distance: swipe.distance,
                newKey: .radialSlot(newIndex),
                step: swipeCycleStepSize
            ) { reverse in
                triggerRadialMenuAction(at: newIndex, from: actions, reverse: reverse)
            }

        case let .ended(reason):
            resetLoopState(
                for: fingerCount,
                forceClose: reason == .fingerCountChanged(.increased)
            )

        case .cancelled:
            resetLoopState(for: fingerCount)

        default:
            break
        }
    }

    private func handleDirectionalSwipe(
        _ swipe: SubsurfaceGestureEvent.SwipeEvent,
        fingerCount: Int,
        direction: GestureBinding.Kind,
        matchedGesture: GestureBinding?
    ) async {
        guard let entry = recognizerRegistry.entry(for: fingerCount) else { return }

        switch swipe.phase {
        case .began, .changed:
            guard let session = recognizerRegistry.session(for: fingerCount), !session.isGestureRejected else { return }

            if !session.hasGestureBegun {
                guard let matchedGesture else { return }
                guard handleGestureBegan(fingerCount: fingerCount, gesture: matchedGesture) else {
                    return
                }
            }

            guard await activateGestureIfNeeded(fingerCount: fingerCount),
                  let session = recognizerRegistry.session(for: fingerCount), !session.isGestureRejected,
                  let activeGesture = session.resolvedGesture ?? matchedGesture
            else {
                return
            }

            if direction != activeGesture.kind {
                if let oppositeDirection = oppositeDirectionalSwipeKind(of: activeGesture.kind),
                   direction == oppositeDirection {
                    let oppositeGesture = entry.directionalGestures.first { $0.kind == oppositeDirection }
                    handleSwipeReversal(
                        fingerCount: fingerCount,
                        currentGesture: activeGesture,
                        oppositeGesture: oppositeGesture,
                        distance: swipe.distance,
                        hasCrossedOrigin: hasSwipeCrossedOrigin(translation: swipe.translation, currentGesture: activeGesture)
                    )
                } else if let matchedGesture {
                    guard switchSwipeGesture(
                        fingerCount: fingerCount,
                        to: matchedGesture,
                        distance: swipe.distance
                    ) else {
                        resetLoopState(for: fingerCount, forceClose: true)
                        return
                    }
                } else {
                    resetLoopState(for: fingerCount, forceClose: true)
                }
                return
            }

            session.commitSwipe(
                distance: swipe.distance,
                newKey: .gesture(activeGesture.id),
                step: swipeCycleStepSize
            ) { reverse in
                triggerSingleAction(from: activeGesture, reverse: reverse)
            }

        case let .ended(reason):
            resetLoopState(
                for: fingerCount,
                forceClose: reason == .fingerCountChanged(.increased)
            )

        case .cancelled:
            resetLoopState(for: fingerCount)

        default:
            break
        }
    }

    private func oppositeDirectionalSwipeKind(of kind: GestureBinding.Kind) -> GestureBinding.Kind? {
        switch kind {
        case .swipeUp:
            .swipeDown
        case .swipeDown:
            .swipeUp
        case .swipeLeft:
            .swipeRight
        case .swipeRight:
            .swipeLeft
        default:
            nil
        }
    }

    private func hasSwipeCrossedOrigin(translation: CGPoint, currentGesture: GestureBinding) -> Bool {
        let projection: CGFloat = switch currentGesture.kind {
        case .swipeUp:
            translation.y
        case .swipeDown:
            -translation.y
        case .swipeRight:
            translation.x
        case .swipeLeft:
            -translation.x
        default:
            0
        }

        return projection < 0
    }

    private func switchSwipeGesture(
        fingerCount: Int,
        to gesture: GestureBinding,
        distance: CGFloat
    ) -> Bool {
        guard let session = recognizerRegistry.session(for: fingerCount),
              session.switchSwipeGesture(to: gesture, distance: distance)
        else {
            return false
        }
        triggerSingleAction(from: gesture, reverse: false)

        if let window = session.pendingTargetWindow,
           resolvedWindowAction(from: gesture)?.allowsRapidRepeat == true {
            targetResolver.rememberRepeatableWindow(window, allowsRapidRepeat: true)
        }

        return true
    }

    private func handleSwipeReversal(
        fingerCount: Int,
        currentGesture: GestureBinding,
        oppositeGesture: GestureBinding?,
        distance: CGFloat,
        hasCrossedOrigin: Bool
    ) {
        if hasCrossedOrigin, let oppositeGesture {
            guard let session = recognizerRegistry.session(for: fingerCount) else { return }
            if session.switchSwipeGesture(to: oppositeGesture, distance: distance) {
                triggerSingleAction(from: oppositeGesture, reverse: false)

                if let window = session.pendingTargetWindow,
                   resolvedWindowAction(from: oppositeGesture)?.allowsRapidRepeat == true {
                    targetResolver.rememberRepeatableWindow(window, allowsRapidRepeat: true)
                }
                return
            }
        }

        if isCycleAction(currentGesture) {
            triggerSingleAction(from: currentGesture, reverse: true)
            recognizerRegistry.session(for: fingerCount)?.updateLastCommitSwipeDistance(distance)
        } else {
            resetLoopState(for: fingerCount, forceClose: true)
        }
    }

    private func directionalSwipeKind(angle: CGFloat) -> GestureBinding.Kind {
        let normalizedAngle = normalizedAngle(fromSubsurfaceAngle: angle)

        if normalizedAngle >= 7 * .pi / 4 || normalizedAngle < .pi / 4 {
            return .swipeUp
        } else if normalizedAngle >= .pi / 4, normalizedAngle < 3 * .pi / 4 {
            return .swipeRight
        } else if normalizedAngle >= 3 * .pi / 4, normalizedAngle < 5 * .pi / 4 {
            return .swipeDown
        } else {
            return .swipeLeft
        }
    }

    private func normalizedAngle(fromSubsurfaceAngle angle: CGFloat) -> CGFloat {
        // Subsurface emits y-up angles (counterclockwise from +x); Loop uses 0 = up, growing clockwise.
        var normalizedAngle = (.pi / 2 - angle).truncatingRemainder(dividingBy: 2 * .pi)
        if normalizedAngle < 0 { normalizedAngle += 2 * .pi }
        return normalizedAngle
    }

    private func indexWithCardinalBias(angle: CGFloat, actionCount: Int, cardinalBias: CGFloat = 0.1) -> Int {
        let baseAngleSpan = (.pi * 2) / CGFloat(actionCount)
        let halfAngleSpan = baseAngleSpan / 2.0

        let adjustedAngle = (angle + halfAngleSpan).truncatingRemainder(dividingBy: .pi * 2)
        let rawSegment = Int(adjustedAngle / baseAngleSpan) % actionCount

        let segmentAngle = adjustedAngle.truncatingRemainder(dividingBy: baseAngleSpan)
        let normalizedPosition = segmentAngle / baseAngleSpan

        let isCurrentCardinal = rawSegment % 2 == 0

        if isCurrentCardinal {
            return rawSegment
        } else {
            if normalizedPosition < cardinalBias / 2 {
                return (rawSegment - 1 + actionCount) % actionCount
            } else if normalizedPosition > 1.0 - cardinalBias / 2 {
                return (rawSegment + 1) % actionCount
            } else {
                return rawSegment
            }
        }
    }
}
