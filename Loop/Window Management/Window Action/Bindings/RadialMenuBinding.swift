//
//  RadialMenuBinding.swift
//  Loop
//
//  Created by Kai Azim on 2025-11-11.
//

import Foundation
import Tome

struct RadialMenuBinding: ConfigurationIdentifiable, Codable, Hashable, Sendable {
    static let category = "radial-menu"

    var id: UUID
    var configID: String?
    var target: ActionTarget

    var reference: ActionTarget { .radialMenuBinding(referenceID) }

    init(id: UUID = UUID(), configID: String? = nil, target: ActionTarget) {
        self.id = id
        self.configID = configID
        self.target = target
    }

    static func custom(_ action: WindowAction) -> Self { .init(target: .windowAction(action)) }
    var associatedActionId: UUID? { target.resolvedAction?.id }
}

extension RadialMenuBinding {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id
    }

    init(from decoder: Decoder) throws {
        let table = try decoder.container(keyedBy: CodingKeys.self)
        let configID = try table.decodeIfPresent(String.self, forKey: .id)
        try configID.map { try ConfigurationIdentity.validate($0, as: "radial menu id") }
        self.init(configID: configID, target: try ActionTarget(from: decoder))
        deriveIdentity()
    }

    func encode(to encoder: Encoder) throws {
        guard target != .radialMenuMode else {
            throw EncodingError.invalidValue(target, .init(codingPath: encoder.codingPath, debugDescription: "The radial menu is only a target of a radial-menu gesture"))
        }
        var table = encoder.container(keyedBy: CodingKeys.self)
        try table.encodeIfPresent(configID, forKey: .id)
        try target.encode(to: encoder)
    }
}

extension RadialMenuBinding {
    static let defaultRadialMenuActions: [RadialMenuBinding] = [
        .custom(
            WindowAction(
                .init(localized: "Top Cycle"),
                cycle: [.init(.topHalf), .init(.topThird), .init(.topTwoThirds)]
            )
        ),
        .custom(WindowAction(.topRightQuarter)),
        .custom(
            WindowAction(
                .init(localized: "Right Cycle"),
                cycle: [.init(.rightHalf), .init(.rightThird), .init(.rightTwoThirds)]
            )
        ),
        .custom(WindowAction(.bottomRightQuarter)),
        .custom(
            WindowAction(
                .init(localized: "Bottom Cycle"),
                cycle: [.init(.bottomHalf), .init(.bottomThird), .init(.bottomTwoThirds)]
            )
        ),
        .custom(WindowAction(.bottomLeftQuarter)),
        .custom(
            WindowAction(
                .init(localized: "Left Cycle"),
                cycle: [.init(.leftHalf), .init(.leftThird), .init(.leftTwoThirds)]
            )
        ),
        .custom(WindowAction(.topLeftQuarter)),
        .custom(
            WindowAction(
                "\(WindowDirection.maximize.name) + \(WindowDirection.macOSCenter.name)",
                cycle: [
                    .init(.maximize),
                    .init(.macOSCenter)
                ]
            )
        )
    ]

    static var userConfiguredActions: [RadialMenuBinding] {
        Tome.enableRadialMenuCustomization ? Tome.radialMenuActions : defaultRadialMenuActions
    }
}
