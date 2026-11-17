//
//  WindowAction.swift
//  Loop
//
//  Created by Kai Azim on 2023-10-28.
//

import Defaults
import SwiftUI

/// Codable because stash recovery records store actions in Defaults.
struct WindowAction: Codable, Identifiable, Hashable, Sendable, Defaults.Serializable {
    private(set) var id: UUID
    var kind: Kind {
        didSet { kind = kind.normalized }
    }

    private static let sharedNoSelectionId = UUID()

    enum Kind: Codable, Hashable {
        case builtin(WindowDirection)
        case custom(FrameAction)
        case cycle(CycleAction)
        case stash(FrameAction)

        /// Payload directions can't be stored as built-ins.
        var normalized: Self {
            switch self {
            case .builtin(.custom): .custom(.init())
            case .builtin(.cycle): .cycle(.init())
            case .builtin(.stash): .stash(.init(position: .anchor(.topLeft)))
            default: self
            }
        }
    }

    init(_ direction: WindowDirection) {
        self.id = direction == .noSelection ? Self.sharedNoSelectionId : UUID()
        switch direction {
        case .custom: self.kind = .custom(.init())
        case .cycle: self.kind = .cycle(.init())
        case .stash: self.kind = .stash(.init(position: .anchor(.topLeft)))
        default: self.kind = .builtin(direction)
        }
    }

    init(kind: Kind, id: UUID = UUID()) {
        self.id = id
        self.kind = kind.normalized
    }

    init(_ name: String? = nil, cycle: [WindowAction]) {
        self.init(kind: .cycle(.init(name: name, steps: cycle.map(ActionTarget.windowAction))))
    }

    init(_ cycle: [WindowAction]) { self.init(nil, cycle: cycle) }

    func withRuntimeID(_ id: UUID) -> Self {
        var action = self
        action.id = id
        return action
    }

    var direction: WindowDirection {
        get {
            switch kind {
            case let .builtin(direction): direction
            case .custom: .custom
            case .cycle: .cycle
            case .stash: .stash
            }
        }
        set {
            guard direction != newValue else { return }
            let identity = id
            self = Self(newValue)
            id = identity
        }
    }

    var name: String? {
        get {
            switch kind {
            case .builtin: nil
            case let .custom(payload): payload.name
            case let .cycle(payload): payload.name
            case let .stash(payload): payload.name
            }
        }
        set {
            switch kind {
            case .builtin: break
            case var .custom(payload): payload.name = newValue; kind = .custom(payload)
            case var .cycle(payload): payload.name = newValue; kind = .cycle(payload)
            case var .stash(payload): payload.name = newValue; kind = .stash(payload)
            }
        }
    }

    /// Retrieves the name of the action, either from the `name` property or from the `direction` enum.
    /// - Returns: the name of the action.
    func getName() -> String {
        if let name, !name.isEmpty, hasCustomizableName {
            name
        } else {
            direction.name
        }
    }

    /// Determines if an action is eligible for custom names set by the user.
    var hasCustomizableName: Bool {
        direction == .custom || direction == .stash || direction == .cycle
    }

    /// Determines if the action will manipulate the existing window frame, rather than setting an entirely new frame from scratch.
    var willManipulateExistingWindowFrame: Bool {
        if direction.willAdjustSize ||
            direction.willShrink ||
            direction.willGrow ||
            direction.willMove {
            return true
        }

        return false
    }

    /// Whether held keys or continuous gestures may repeatedly trigger this action.
    ///
    /// Keyboard events can arrive repeatedly while a keybind is held down, and gesture
    /// recognizers can commit repeatedly as movement crosses step thresholds.
    var allowsRapidRepeat: Bool {
        willManipulateExistingWindowFrame || direction.willFocusWindow
    }

    /// Whether selecting this same action again should still run through Loop's action pipeline.
    ///
    /// Undo and stash are not rapid-repeat actions, but selecting them again should still
    /// apply: undo walks back another recorded action, and stash toggles an existing stashed window.
    var allowsRepeatedSelection: Bool {
        allowsRapidRepeat || direction == .undo || direction == .stash
    }

    var forceProportionalFrameOnScreenChange: Bool {
        direction.willCenter || willManipulateExistingWindowFrame
    }

    /// Determines if padding can be applied to the action.
    var isInnerPaddingApplicable: Bool {
        if direction == .undo || direction == .initialFrame {
            return false
        }

        // These adjust the window's existing frame, which already has any padding it needs.
        // Applying it again would shrink the window a little every time.
        if willManipulateExistingWindowFrame {
            return false
        }

        if direction.isCustomizable, size == .initial || size == .preserve {
            return false
        }

        return true
    }

    /// Determines the angle to show in the radial menu, if applicable.
    /// Examples of actions where the radial menu angle is not applicable:
    /// - No action (noAction)
    /// - Hiding the window (hide)
    /// - Minimizing the window (minimize)
    /// - Cycling through actions (cycle) - the selected action's angle will be used instead within the radial menu's selected action logic.
    ///
    /// - Parameter context: the resize context containing the pre-computed target frame.
    /// - Returns: the angle to show in the radial menu, or `nil` if the action does not have a radial menu angle.
    func radialMenuAngle(context: ResizeContext) -> Angle? {
        guard direction.hasRadialMenuAngle else {
            return nil
        }

        let targetFrame = context.getTargetFrame().normalized
        let angle = CGPoint(x: 0.5, y: 0.5).angle(to: targetFrame.center)
        let result: Angle = angle * -1

        return result.normalized()
    }
}

extension WindowAction: CustomStringConvertible {
    var description: String {
        "WindowAction(direction: \(direction), name: \(getName()))"
    }
}
