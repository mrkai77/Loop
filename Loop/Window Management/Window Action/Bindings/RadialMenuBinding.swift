//
//  RadialMenuBinding.swift
//  Loop
//
//  Created by Kai Azim on 2025-11-11.
//

import Defaults
import Foundation

/// A radial menu slot, running an action or the action of a binding it links to.
/// Each slot has its own id, so the same action can appear more than once
struct RadialMenuBinding: ActionBinding, Codable, Defaults.Serializable {
    static let bindingKind = LoopBindingKind.radialMenu

    let id: UUID
    var configID: String?
    var target: BindingTarget

    init(id: UUID = UUID(), configID: String? = nil, target: BindingTarget = .action(WindowAction(.noAction))) {
        self.id = id
        self.configID = configID
        self.target = target
    }

    var bindingTarget: BindingTarget? {
        target
    }

    mutating func setTarget(_ target: BindingTarget) -> Bool {
        self.target = target
        return true
    }
}

// MARK: - Coding

/// Written with the same keys as before, so older versions still read the radial menu
extension RadialMenuBinding {
    private enum CodingKeys: String, CodingKey {
        case id
        case target = "type"
        case configID
    }
}

// MARK: - Defaults

extension RadialMenuBinding {
    static let defaults: [RadialMenuBinding] = [
        RadialMenuBinding(
            configID: "top-cycle",
            target: .action(WindowAction(.init(localized: "Top Cycle"), cycle: [.init(.topHalf), .init(.topThird), .init(.topTwoThirds)]))
        ),
        RadialMenuBinding(configID: "top-right-quarter", target: .action(WindowAction(.topRightQuarter))),
        RadialMenuBinding(
            configID: "right-cycle",
            target: .action(WindowAction(.init(localized: "Right Cycle"), cycle: [.init(.rightHalf), .init(.rightThird), .init(.rightTwoThirds)]))
        ),
        RadialMenuBinding(configID: "bottom-right-quarter", target: .action(WindowAction(.bottomRightQuarter))),
        RadialMenuBinding(
            configID: "bottom-cycle",
            target: .action(WindowAction(.init(localized: "Bottom Cycle"), cycle: [.init(.bottomHalf), .init(.bottomThird), .init(.bottomTwoThirds)]))
        ),
        RadialMenuBinding(configID: "bottom-left-quarter", target: .action(WindowAction(.bottomLeftQuarter))),
        RadialMenuBinding(
            configID: "left-cycle",
            target: .action(WindowAction(.init(localized: "Left Cycle"), cycle: [.init(.leftHalf), .init(.leftThird), .init(.leftTwoThirds)]))
        ),
        RadialMenuBinding(configID: "top-left-quarter", target: .action(WindowAction(.topLeftQuarter))),
        RadialMenuBinding(
            configID: "maximize-macos-center",
            target: .action(WindowAction("\(WindowDirection.maximize.name) + \(WindowDirection.macOSCenter.name)", cycle: [.init(.maximize), .init(.macOSCenter)]))
        )
    ]

    static var userConfigured: [RadialMenuBinding] {
        Defaults[.enableRadialMenuCustomization] ? Defaults[.radialMenuActions] : defaults
    }
}
