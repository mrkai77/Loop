//
//  ActionPickerView.swift
//  Loop
//
//  Created by Kai Azim on 2026-11-22.
//

import Defaults
import SwiftUI

/// Picks an action for a keybind, gesture or radial menu action, or a link to another one of those.
/// Leaves out links that would loop back to `owner`, the binding being edited.
struct ActionPickerView: View {
    enum Item: Hashable, Identifiable {
        case direction(WindowDirection)
        case link(BindingLink)

        var id: Self { self }
    }

    @Default(.keybinds) private var keybinds
    @Default(.gestures) private var gestures
    @Default(.radialMenuActions) private var radialMenuActions
    @Default(.enableRadialMenuCustomization) private var enableRadialMenuCustomization

    @State private var searchText = ""
    @State private var searchResults: [Item] = []
    @FocusState private var isSearchFocused: Bool

    @Binding private var selection: Item
    private let owner: BindingLink

    init(selection: Binding<Item>, owner: BindingLink) {
        self._selection = selection
        self.owner = owner
    }

    private var resolver: BindingLinkResolver {
        BindingLinkResolver(keybinds: keybinds, gestures: gestures, radialMenuActions: radialMenuActions)
    }

    private var directionSections: [PickerSection<Item>] {
        PickerSection.windowDirections.map { section in
            PickerSection(section.title, section.items.map(Item.direction))
        }
    }

    private var moreSection: PickerSection<Item> {
        PickerSection(
            String(localized: "More", comment: "Section header in the action picker of the Keybinds tab"),
            [Item.direction(.custom), .direction(.cycle)]
        )
    }

    private var linkSections: [PickerSection<Item>] {
        let resolver = resolver

        func section(_ title: String, _ links: [BindingLink]) -> PickerSection<Item>? {
            let items = links
                .filter { resolver.canBeLinked($0) && !resolver.wouldLoop(linking: owner, to: $0) }
                .map(Item.link)
            return items.isEmpty ? nil : PickerSection(title, items)
        }

        return [
            section(
                String(localized: "Your Keybinds", comment: "Section header in the action picker, listing the user’s keybinds to link to"),
                keybinds.map { BindingLink(.keybind, id: $0.id) }
            ),
            section(
                String(localized: "Your Gestures", comment: "Section header in the action picker, listing the user’s gestures to link to"),
                gestures.map { BindingLink(.gesture, id: $0.id) }
            ),
            // The default radial menu's actions get new ids each launch, so they can only be linked to once it's customized
            enableRadialMenuCustomization ? section(
                String(localized: "Your Radial Menu", comment: "Section header in the action picker, listing the user’s radial menu actions to link to"),
                radialMenuActions.map { BindingLink(.radialMenu, id: $0.id) }
            ) : nil
        ].compactMap(\.self)
    }

    private var allSections: [PickerSection<Item>] {
        directionSections + [moreSection] + linkSections
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField(
                String(localized: "Search for a window action", defaultValue: "Search"),
                text: $searchText
            )
            .textFieldStyle(.plain)
            .focused($isSearchFocused)
            .padding(12)

            Divider()

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    PickerList(
                        selection: pickerSelection,
                        searchResults: $searchResults,
                        proxy: proxy,
                        sections: allSections
                    ) { item in
                        HStack(spacing: 8) {
                            switch item {
                            case let .direction(direction):
                                IconView(direction: direction)
                                Text(direction.name)
                            case let .link(link):
                                if let action = resolver.action(for: link) {
                                    IconView(action: action)
                                    Text(action.getName())
                                        .lineLimit(1)
                                }

                                Spacer()

                                BindingLinkIndicator(kind: link.kind)
                            }
                        }
                        .padding(.horizontal, 6)
                    }
                    .padding(8)
                    .luminareCornerRadius(12)
                }
            }
        }
        .onAppear {
            searchText = ""
            computeSearchResults()
            Task { @MainActor in
                isSearchFocused = true
            }
        }
        .onDisappear {
            searchText = ""
        }
        .onChange(of: searchText) { _ in
            computeSearchResults()
        }
    }

    /// Saves the radial menu before linking to one of its actions, so their ids stay the same after Loop relaunches
    private var pickerSelection: Binding<Item> {
        Binding(
            get: { selection },
            set: { newValue in
                if case let .link(link) = newValue, link.kind == .radialMenu {
                    Defaults[.radialMenuActions] = radialMenuActions
                }
                selection = newValue
            }
        )
    }

    private func computeSearchResults() {
        guard !searchText.isEmpty else {
            searchResults = []
            return
        }

        let key = searchText.lowercased()
        let resolver = resolver

        let matches = allSections
            .flatMap(\.items)
            .filter { !moreSection.items.contains($0) }
            .compactMap { item -> (Item, Int)? in
                let name = switch item {
                case let .direction(direction): direction.name
                case let .link(link): resolver.action(for: link)?.getName()
                }

                return name.flatMap { DirectionPickerView.fuzzyScore($0, key) }.map { (item, $0) }
            }
            .sorted { $0.1 < $1.1 }
            .map(\.0)

        searchResults = matches + moreSection.items
    }
}

struct BindingLinkIndicator: View {
    let kind: BindingLink.Kind

    var body: some View {
        image
            .foregroundStyle(.secondary)
    }

    private var image: Image {
        switch kind {
        case .keybind: Image(systemName: "keyboard.fill")
        case .gesture: Image(systemName: "hand.draw.fill")
        case .radialMenu: Image(.loop)
        }
    }
}

/// Hovering it explains the link and offers to unlink, which is the only way to, as picking another action changes the binding it links to.
struct BindingLinkBadge: View {
    let kind: BindingLink.Kind
    let unlink: () -> ()

    var body: some View {
        BindingLinkIndicator(kind: kind)
            .frame(width: 18, height: 18)
            .contentShape(.rect)
            .luminareToolTip(arrowEdge: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(help)
                        .fixedSize(horizontal: false, vertical: true)

                    Button(action: unlink) {
                        unlinkTitle
                    }
                    .buttonStyle(.luminare(overrideUseMainStyle: true))
                    .luminareCornerRadius(8)
                }
                .frame(width: 240, alignment: .leading)
                .padding(8)
            }
            .accessibilityAction(named: unlinkTitle, unlink)
    }

    private var unlinkTitle: Text {
        Text("Unlink", comment: "Button in the popover of a keybind, gesture or radial menu action that links to another, which unlinks it and keeps its action as its own")
    }

    private var help: String {
        switch kind {
        case .keybind:
            String(localized: "This action is linked to a keybind. Changes made to this action will affect both.", comment: "A tooltip on a gesture or radial menu action that links to a keybind, explaining that changes to its action also affect the keybind.")
        case .gesture:
            String(localized: "This action is linked to a gesture. Changes made to this action will affect both.", comment: "A tooltip on a keybind, gesture or radial menu action that links to a gesture, explaining that changes to its action also affect the gesture.")
        case .radialMenu:
            String(localized: "This action is linked to a radial menu action. Changes made to this action will affect both.", comment: "A tooltip on a keybind, gesture or radial menu action that links to a radial menu action, explaining that changes to its action also affect the radial menu action.")
        }
    }
}

// MARK: - Selections

extension RadialMenuAction.ActionType {
    var pickerItem: ActionPickerView.Item {
        link.map(ActionPickerView.Item.link) ?? .direction(customAction?.direction ?? .noAction)
    }

    init(_ item: ActionPickerView.Item) {
        switch item {
        case let .direction(direction): self = .custom(WindowAction(direction))
        case let .link(link): self.init(link)
        }
    }
}
