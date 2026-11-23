//
//  WindowAction.swift
//  Loop
//
//  Created by Kai Azim on 2023-10-28.
//

import Defaults
import Scribe
import SwiftUI

/// The window action struct represents a single action that can be performed on a window, such as resizing, moving, or cycling through actions.
///
/// Common actions, such as right half, or bottom right quarter, are represented by `WindowDirection` enum, while user-made actions, such as custom frames and cycles are speciied by this struct.
struct WindowAction: Codable, Identifiable, Hashable, Equatable, Defaults.Serializable {
    private(set) var id: UUID
    private static var sharedNoSelectionId: UUID = .init()

    /// Initializes a `WindowAction` with the specified parameters. Only to be used when decoding from JSON.
    /// - Parameters:
    ///   - direction: the direction of the window action. If custom or cycle, use those and further specify the action with the parameters below.
    ///   - name: the name of the action. If `nil`, the name will be derived from the direction.
    ///   - unit: the unit of measurement for width and height.  This needs to be specified for custom actions.
    ///   - anchor: the anchor point for the action.  This needs to be specified for custom actions that use a `generic` ``positionMode``
    ///   - width: the width of the window. This needs to be specified for custom actions.
    ///   - height: the height of the window. This needs to be specified for custom actions.
    ///   - xPoint: the x-coordinate of the window's position. This needs to be specified for custom actions with a `coordinates` ``positionMode``.
    ///   - yPoint: the y-coordinate of the window's position. This needs to be specified for custom actions with a `coordinates` ``positionMode``.
    ///   - positionMode: whether to use anchors or exact coordinates to move a window. This needs to be specified for custom actions.
    ///   - sizeMode: the size mode of the action, which allows users to preserve size when manipulating a window.
    ///   - cycle: The cycling window actions.
    init(
        _ direction: WindowDirection,
        name: String? = nil,
        unit: CustomWindowActionUnit? = nil,
        anchor: CustomWindowActionAnchor? = nil,
        width: Double? = nil,
        height: Double? = nil,
        xPoint: Double? = nil,
        yPoint: Double? = nil,
        positionMode: CustomWindowActionPositionMode? = nil,
        sizeMode: CustomWindowActionSizeMode? = nil,
        cycle: [WindowAction]? = nil
    ) {
        self.id = UUID()
        self.direction = direction
        self.name = name
        self.unit = unit
        self.anchor = anchor
        self.width = width
        self.height = height
        self.positionMode = positionMode
        self.xPoint = xPoint
        self.yPoint = yPoint
        self.sizeMode = sizeMode
        self.cycle = cycle?.map(CycleStep.init)
    }

    /// Initializes a `WindowAction` with the specified direction.
    /// - Parameter direction: the direction of the window action.
    init(_ direction: WindowDirection) {
        if direction == .noSelection {
            self.id = Self.sharedNoSelectionId
        } else {
            self.id = UUID()
        }

        self.direction = direction
    }

    /// Initializes a cycle `WindowAction`. Used for user-defined cycles.
    /// - Parameters:
    ///   - name: the name of the cycle. If `nil`, a default name will be used (eg. "Cycle").
    ///   - cycle: the cycle of window actions. This is an array of `WindowAction` that will be cycled through when the action is triggered.
    init(_ name: String? = nil, cycle: [WindowAction]) {
        self.id = UUID()
        self.direction = .cycle
        self.name = name
        self.cycle = cycle.map(CycleStep.init)
    }

    /// Initializes a cycle without a name. Used in radial menu.
    /// - Parameter cycle: the cycle of window actions.
    init(_ cycle: [WindowAction]) {
        self.init(nil, cycle: cycle)
    }

    /// Generic Properties
    var direction: WindowDirection

    // Custom Keybind Properties
    var name: String?
    var unit: CustomWindowActionUnit?
    var anchor: CustomWindowActionAnchor?
    var sizeMode: CustomWindowActionSizeMode?
    var width: Double?
    var height: Double?
    var positionMode: CustomWindowActionPositionMode?
    var xPoint: Double?
    var yPoint: Double?

    /// Custom Cycle Properties
    var cycle: [CycleStep]?

    /// The cycle's actions, without linked steps until `BindingLinkResolver` resolves them
    var cycleActions: [WindowAction]? {
        cycle?.compactMap(\.target.action)
    }

    // MARK: - Methods

    var iconResolvedAction: WindowAction {
        if direction == .cycle, let first = cycleActions?.first {
            first
        } else {
            self
        }
    }

    struct SemanticKey: Hashable {
        let direction: WindowDirection
        let name: String?
        let unit: CustomWindowActionUnit?
        let anchor: CustomWindowActionAnchor?
        let sizeMode: CustomWindowActionSizeMode?
        let width: Double?
        let height: Double?
        let positionMode: CustomWindowActionPositionMode?
        let xPoint: Double?
        let yPoint: Double?
        let cycle: [CycleStepKey]?
    }

    enum CycleStepKey: Hashable {
        case action(SemanticKey)
        case link(BindingLink)
    }

    var semanticKey: SemanticKey {
        .init(
            direction: direction,
            name: name,
            unit: unit,
            anchor: anchor,
            sizeMode: sizeMode,
            width: width,
            height: height,
            positionMode: positionMode,
            xPoint: xPoint,
            yPoint: yPoint,
            cycle: cycle?.map { step in
                switch step.target {
                case let .action(action): .action(action.semanticKey)
                case let .link(link): .link(link)
                }
            }
        )
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

        if direction.isCustomizable, sizeMode == .initialSize || sizeMode == .preserveSize {
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

// MARK: - Coding

/// Written with the same keys as before, including the `keybind` older versions require
extension WindowAction {
    private enum CodingKeys: String, CodingKey {
        case id, direction, keybind, name, unit, anchor, sizeMode, width, height, positionMode, xPoint, yPoint, cycle
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Keybinds files and Rectangle imports have no ids
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.direction = try container.decode(WindowDirection.self, forKey: .direction)
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
        self.unit = try container.decodeIfPresent(CustomWindowActionUnit.self, forKey: .unit)
        self.anchor = try container.decodeIfPresent(CustomWindowActionAnchor.self, forKey: .anchor)
        self.sizeMode = try container.decodeIfPresent(CustomWindowActionSizeMode.self, forKey: .sizeMode)
        self.width = try container.decodeIfPresent(Double.self, forKey: .width)
        self.height = try container.decodeIfPresent(Double.self, forKey: .height)
        self.positionMode = try container.decodeIfPresent(CustomWindowActionPositionMode.self, forKey: .positionMode)
        self.xPoint = try container.decodeIfPresent(Double.self, forKey: .xPoint)
        self.yPoint = try container.decodeIfPresent(Double.self, forKey: .yPoint)
        self.cycle = try container.decodeIfPresent([CycleStep].self, forKey: .cycle)
    }

    func encode(to encoder: Encoder) throws {
        try encode(to: encoder, keybind: [])
    }

    /// Writes the action with its keybind's keys, as the two are one object on disk
    func encode(to encoder: Encoder, keybind: Set<CGKeyCode>) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(direction, forKey: .direction)
        try container.encode(keybind, forKey: .keybind)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(unit, forKey: .unit)
        try container.encodeIfPresent(anchor, forKey: .anchor)
        try container.encodeIfPresent(sizeMode, forKey: .sizeMode)
        try container.encodeIfPresent(width, forKey: .width)
        try container.encodeIfPresent(height, forKey: .height)
        try container.encodeIfPresent(positionMode, forKey: .positionMode)
        try container.encodeIfPresent(xPoint, forKey: .xPoint)
        try container.encodeIfPresent(yPoint, forKey: .yPoint)
        try container.encodeIfPresent(cycle, forKey: .cycle)
    }
}

// MARK: - Defaults

extension WindowAction {
    /// Fills in what a custom, stash or cycle action needs and doesn't have yet.
    /// Picking an action does this, and its editor does it for older actions
    mutating func fillDefaults() {
        switch direction {
        case .custom, .stash:
            unit = unit ?? .percentage
            sizeMode = sizeMode ?? .custom
            width = width ?? 80
            height = height ?? 80
            positionMode = positionMode ?? .generic
            // Stashed windows hide against a screen's edge, so they have no center anchor
            anchor = anchor ?? (direction == .stash ? .topLeft : .center)
        case .cycle:
            cycle = cycle ?? []
        default:
            break
        }
    }

    /// Runs `direction` instead, keeping the rest, so switching back restores a custom frame or cycle
    mutating func pick(_ direction: WindowDirection) {
        self.direction = direction
        fillDefaults()
    }
}

// MARK: - Identity

extension WindowAction {
    /// The action under its binding's id, as a keybind and its action share one
    func withID(_ id: UUID) -> WindowAction {
        var copy = self
        copy.id = id
        return copy
    }

    /// A copy with new ids for it and its steps, so the two never share cycle progress or radial menu selection
    func detached() -> WindowAction {
        var copy = self
        copy.id = UUID()
        copy.cycle = cycle?.map { $0.detached() }
        return copy
    }
}
