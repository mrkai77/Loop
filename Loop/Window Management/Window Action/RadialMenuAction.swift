//
//  RadialMenuAction.swift
//  Loop
//
//  Created by Kai Azim on 2025-11-11.
//

import Defaults
import Foundation

/// A safe, identifiable wrapper around `ActionType`.
/// This avoids duplicate IDs when the same action or keybind appears more than once in the radial menu.
/// By giving each wrapped value its own custom ID, we keep identities stable across updates and
/// can correctly distinguish duplicate items within the menu.
struct RadialMenuAction: Identifiable, Codable, Hashable, Defaults.Serializable {
    let id: UUID
    var type: ActionType

    /// An action of its own, or a link to a keybind, gesture or radial menu action.
    /// Links to keybinds keep their own case, which older versions of Loop read. Other links are a `noAction` action with
    /// `WindowAction.link` set, like linked keybinds, so older versions read them as doing nothing rather than dropping them.
    enum ActionType: Identifiable, Codable, Hashable {
        case custom(WindowAction)
        case keybindReference(UUID)

        init(_ link: BindingLink) {
            switch link.kind {
            case .keybind:
                self = .keybindReference(link.id)
            case .gesture, .radialMenu:
                var action = WindowAction(.noAction)
                action.link = link
                self = .custom(action)
            }
        }

        var id: UUID {
            switch self {
            case let .custom(windowAction):
                windowAction.link?.id ?? windowAction.id
            case let .keybindReference(id):
                id
            }
        }

        var link: BindingLink? {
            switch self {
            case let .custom(action): action.link
            case let .keybindReference(id): BindingLink(.keybind, id: id)
            }
        }

        /// `nil` for a link
        var customAction: WindowAction? {
            if case let .custom(action) = self, action.link == nil { action } else { nil }
        }

        var resolvedAction: WindowAction? {
            resolvedAction(with: BindingLinkResolver())
        }

        func resolvedAction(with resolver: BindingLinkResolver) -> WindowAction? {
            link.map(resolver.action) ?? customAction
        }

        var isLink: Bool {
            link != nil
        }

        /// The id of the action this runs, for the radial menu while it's open.
        /// Links use the resolver the keybind cache keeps up to date, as reading settings here would decode them on every update.
        var associatedActionId: UUID {
            isLink ? resolvedAction(with: WindowActionCache.shared.linkResolver)?.id ?? id : id
        }
    }

    private init(id: UUID, type: ActionType) {
        self.id = id
        self.type = type
    }

    static func custom(_ action: WindowAction) -> Self {
        self.init(
            id: .init(),
            type: .custom(action)
        )
    }

    static func keybindReference(_ id: UUID) -> Self {
        link(BindingLink(.keybind, id: id))
    }

    static func link(_ link: BindingLink) -> Self {
        self.init(
            id: .init(),
            type: .init(link)
        )
    }

    // MARK: Computed Helpers

    /// The id of the action this runs, so the radial menu can tell which slot is selected
    var associatedActionId: UUID {
        type.associatedActionId
    }

    var resolved: WindowAction? {
        type.resolvedAction
    }
}

extension RadialMenuAction {
    static let defaultRadialMenuActions: [RadialMenuAction] = [
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

    static var userConfiguredActions: [RadialMenuAction] {
        Defaults[.enableRadialMenuCustomization] ? Defaults[.radialMenuActions] : defaultRadialMenuActions
    }
}
