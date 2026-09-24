//
//  RadialMenuViewModel.swift
//  Loop
//
//  Created by Kai Azim on 2025-08-31.
//

import Defaults
import SwiftUI

/// This class is in charge of managing the state of the radial menu, including the current action, angle, and colors.
/// By keeping the state separate, we are able to use the same `RadialMenuView` both in the app's settings, as well as in actual usage.
@MainActor
final class RadialMenuViewModel: ObservableObject {
    @Published private(set) var angle: Double
    @Published private(set) var currentAction: WindowAction = .init(.noSelection)

    /// If a cycling action is chosen, this will represent the enclosing cycle action
    @Published private(set) var parentAction: WindowAction?

    @Published private(set) var isShown: Bool = false
    @Published private(set) var isShadowShown: Bool = false

    private var previousAction: WindowAction?
    private var context: ResizeContext?
    private var window: Window?
    let isSettingsPreview: Bool

    init(isSettingsPreview: Bool) {
        self.isSettingsPreview = isSettingsPreview
        self.angle = .zero
    }

    private var effectiveWindowAction: WindowAction {
        parentAction ?? currentAction
    }

    private var radialMenuActions: [RadialMenuAction] {
        RadialMenuAction.userConfiguredActions
    }

    private var directionalRadialMenuActions: [RadialMenuAction] {
        radialMenuActions.dropLast()
    }

    private var centerRadialMenuAction: RadialMenuAction? {
        radialMenuActions.last
    }

    /// Directional swipe gestures act like slots, pointing the radial menu the way the fingers moved
    private func directionalGestureAngle(for action: WindowAction) -> Angle? {
        guard Defaults[.enableGestures] else { return nil }

        return Defaults[.gestures].lazy.compactMap { gesture -> Angle? in
            guard case let .singleAction(actionType) = gesture.action, actionType.id == action.id else { return nil }
            return gesture.kind.radialMenuAngle
        }.first
    }

    var shouldFillRadialMenu: Bool {
        // If the user has the center action selected, then fill the radial menu
        if effectiveWindowAction.id == centerRadialMenuAction?.associatedActionId {
            return true
        }

        guard !directionalRadialMenuActions.contains(where: { $0.associatedActionId == effectiveWindowAction.id }),
              directionalGestureAngle(for: effectiveWindowAction) == nil
        else {
            return false
        }

        // Otherwise, default to the action's settings
        return effectiveWindowAction.direction.shouldFillRadialMenu
    }

    var shouldHideDirectionSelector: Bool {
        // If the current action is a user-set radial menu or directional gesture action, always show the direction selector
        if radialMenuActions.contains(where: { $0.associatedActionId == effectiveWindowAction.id }) ||
            directionalGestureAngle(for: effectiveWindowAction) != nil {
            return false
        }

        // Otherwise, default to the action's settings
        return currentAction.direction.hasRadialMenuAngle != true || (currentAction.direction.isCustomizable == true && currentAction.direction != .stash)
    }

    var radialMenuImage: Image? {
        if window == nil, !isSettingsPreview {
            Image(systemName: "exclamationmark.triangle")
        } else if let image = currentAction.image {
            image.image
        } else {
            nil
        }
    }

    func setIsShown(_ newState: Bool, animationDuration: TimeInterval) {
        let animationDuration = Defaults[.animationConfiguration].animateRadialMenuAppearance ? animationDuration : 0.0

        guard animationDuration != 0 else {
            isShown = newState
            isShadowShown = newState
            return
        }

        withAnimation(.smooth(duration: animationDuration)) {
            isShown = newState
        }

        let shadowAnimationTrimFactor = 0.05
        let shadowDelayOffset = newState ? shadowAnimationTrimFactor : 0.0
        withAnimation(.smooth(duration: animationDuration - shadowAnimationTrimFactor).delay(shadowDelayOffset)) {
            isShadowShown = newState
        }
    }

    func updateContext(with context: ResizeContext) {
        window = context.window

        previousAction = currentAction
        currentAction = context.action
        parentAction = context.parentAction

        recomputeAngle(context: context)
    }

    private func recomputeAngle(context: ResizeContext) {
        guard let targetAngle = calculateTargetAngle(context: context) else {
            return
        }

        let closestAngle = Angle.degrees(angle).angleDifference(to: targetAngle)
        let shouldAnimate = shouldAnimateTransition(closestAngle: closestAngle)
        let animation = Defaults[.animationConfiguration].radialMenuAngle

        withAnimation(shouldAnimate ? animation : .linear(duration: 0)) {
            angle += closestAngle.degrees
        }
    }

    private func calculateTargetAngle(context: ResizeContext) -> Angle? {
        // Check directional radial menu actions first
        if let index = directionalRadialMenuActions.firstIndex(where: { $0.associatedActionId == effectiveWindowAction.id }) {
            let actionAngleSpan = 360.0 / CGFloat(directionalRadialMenuActions.count)
            return Angle(degrees: CGFloat(index) * actionAngleSpan - 90)
        }

        if let gestureAngle = directionalGestureAngle(for: effectiveWindowAction) {
            return gestureAngle
        }

        // Otherwise, default to the current action's radial menu angle
        return currentAction.radialMenuAngle(context: context)
    }

    private func shouldAnimateTransition(closestAngle: Angle) -> Bool {
        guard abs(closestAngle.degrees) < 179 else { return false }

        if let previousAction {
            return directionalRadialMenuActions.contains(where: { $0.associatedActionId == previousAction.id }) ||
                directionalGestureAngle(for: previousAction) != nil ||
                previousAction.direction.hasRadialMenuAngle
        }

        return false
    }
}
