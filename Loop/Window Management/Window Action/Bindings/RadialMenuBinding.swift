//
//  RadialMenuBinding.swift
//  Loop
//
//  Created by Kai Azim on 2025-11-11.
//

import Foundation

struct RadialMenuBinding: ActionBinding, Codable, Hashable, Sendable {
    static let bindingKind = BindingKind.radialMenu

    var id: UUID
    var configID: String?
    var target: ActionTarget

    init(id: UUID = UUID(), configID: String? = nil, target: ActionTarget) {
        self.id = id
        self.configID = configID
        self.target = target
    }

    static func custom(_ action: WindowAction) -> Self { .init(target: .windowAction(action)) }
}

extension RadialMenuBinding {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id
    }

    init(from decoder: Decoder) throws {
        let table = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(configID: Self.decodeConfigurationID(from: table, forKey: .id), target: ActionTarget(from: decoder))
        deriveIdentity()
    }

    func encode(to encoder: Encoder) throws {
        var table = encoder.container(keyedBy: CodingKeys.self)
        try encodeConfigurationID(into: &table, forKey: .id)
        try target.encode(to: encoder)
    }
}

extension RadialMenuBinding {
    static let defaults: [RadialMenuBinding] = [
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
}
