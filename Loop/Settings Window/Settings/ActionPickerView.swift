//
//  ActionPickerView.swift
//  Loop
//
//  Created by Kai Azim on 2026-11-22.
//

import Defaults
import Luminare
import SwiftUI

/// Picks an action or a link to another binding. Leaves out links that would loop back to `owner`,
/// and bindings of its own kind, which only a cycle step can link to.
struct ActionPickerView: View {
    enum Item: Hashable, Identifiable {
        case direction(WindowDirection)
        case binding(BindingIdentity)

        var id: Self { self }
    }

    @BindingLinks private var resolver
    @Default(.enableRadialMenuCustomization) private var enableRadialMenuCustomization

    @State private var searchText = ""
    @State private var searchResults: [Item] = []
    @FocusState private var isSearchFocused: Bool

    @Binding private var selection: Item
    /// `nil` for a cycle step, which can't link to a cycle, so can't loop back to its own
    private let owner: BindingIdentity?

    init(selection: Binding<Item>, owner: BindingIdentity?) {
        self._selection = selection
        self.owner = owner
    }

    private var isInCycle: Bool {
        owner == nil
    }

    private var directionSections: [PickerSection<Item>] {
        PickerSection.windowDirections.compactMap { section in
            // A cycle already repeats its steps
            let items = isInCycle ? section.items.filter { !WindowAction($0).allowsRapidRepeat } : section.items
            return items.isEmpty ? nil : PickerSection(section.title, items.map(Item.direction))
        }
    }

    private var moreSection: PickerSection<Item> {
        PickerSection(
            String(localized: "More", comment: "Section header in the action picker of the Keybinds tab"),
            isInCycle ? [Item.direction(.custom)] : [Item.direction(.custom), .direction(.cycle)]
        )
    }

    private var linkSections: [PickerSection<Item>] {
        let resolver = resolver

        func section(_ title: String, _ bindings: [BindingIdentity]) -> PickerSection<Item>? {
            let items = bindings
                .filter { $0.kind != owner?.kind }
                .filter { identity in resolver.canBeLinked(identity) && !(owner.map { resolver.wouldLoop(linking: $0, to: identity) } ?? false) }
                .filter { !isInCycle || resolver.canBeLinked(fromCycle: $0) }
                .map(Item.binding)
            return items.isEmpty ? nil : PickerSection(title, items)
        }

        return [
            section(
                String(localized: "Your Keybinds", comment: "Section header in the action picker, listing the user’s keybinds to link to"),
                resolver.keybinds.map(\.identity)
            ),
            section(
                String(localized: "Your Gestures", comment: "Section header in the action picker, listing the user’s gestures to link to"),
                resolver.gestures.map(\.identity)
            ),
            section(
                String(localized: "Your Radial Menu", comment: "Section header in the action picker, listing the user’s radial menu actions to link to"),
                // The built-in radial menu isn't saved, so edits made through a link to it would be lost
                enableRadialMenuCustomization ? resolver.radialMenuActions.map(\.identity) : []
            )
        ].compactMap(\.self)
    }

    private var allSections: [PickerSection<Item>] {
        directionSections + [moreSection] + linkSections
    }

    var body: some View {
        let resolver = resolver

        return VStack(spacing: 0) {
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
                        selection: $selection,
                        searchResults: $searchResults,
                        proxy: proxy,
                        sections: allSections
                    ) { item in
                        HStack(spacing: 8) {
                            switch item {
                            case let .direction(direction):
                                IconView(direction: direction)
                                Text(direction.name)
                            case let .binding(identity):
                                if let action = resolver.target(of: identity)?.resolvedAction(with: resolver) {
                                    IconView(action: action)
                                    Text(action.getName())
                                        .lineLimit(1)
                                }

                                Spacer()

                                BindingKindIcon(kind: identity.kind)
                                    .foregroundStyle(.secondary)
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
                case let .binding(identity): resolver.target(of: identity)?.resolvedAction(with: resolver)?.getName()
                }

                return name.flatMap { Self.fuzzyScore($0, key) }.map { (item, $0) }
            }
            .sorted { $0.1 < $1.1 }
            .map(\.0)

        searchResults = matches + moreSection.items
    }

    /// Scores how well a search pattern matches an action name. Lower scores rank higher.
    /// - Parameters:
    ///   - text: The action name to match against.
    ///   - pattern: The search text entered by the user.
    /// - Returns: `0` for a prefix match, `1` for a substring match, `2` if the pattern's
    ///   characters appear in order within the text, or `nil` if there is no match.
    static func fuzzyScore(_ text: String, _ pattern: String) -> Int? {
        let text = text.lowercased()
        let pattern = pattern.lowercased()

        // Strong prefix match
        if text.hasPrefix(pattern) { return 0 }

        // Contains substring
        if text.contains(pattern) { return 1 }

        // Subsequence fuzzy match (letters appear in order)
        var tIndex = text.startIndex
        var pIndex = pattern.startIndex
        while tIndex < text.endIndex, pIndex < pattern.endIndex {
            if text[tIndex] == pattern[pIndex] {
                pIndex = pattern.index(after: pIndex)
            }
            tIndex = text.index(after: tIndex)
        }

        if pIndex == pattern.endIndex { return 2 }

        return nil
    }
}

struct BindingKindIcon: View {
    let kind: LoopBindingKind

    var body: some View {
        image
    }

    private var image: Image {
        switch kind {
        case .keybind: Image(systemName: "keyboard.fill")
        case .gesture: Image(systemName: "hand.draw.fill")
        case .radialMenu: Image(.loop)
        }
    }
}

// MARK: - Selections

@MainActor
extension BindingTarget {
    /// A link that leads nowhere shows as no action
    func pickerItem(with resolver: BindingLinkResolver) -> ActionPickerView.Item {
        switch self {
        case let .action(action): .direction(action.direction)
        case let .link(link): resolver.identity(of: link).map(ActionPickerView.Item.binding) ?? .direction(.noAction)
        }
    }

    /// A link changes the binding it links to, and is only unlinked with its link button.
    /// Returns the picked direction, so the row can open its editor.
    mutating func pick(_ item: ActionPickerView.Item) -> WindowDirection? {
        switch item {
        case let .binding(identity):
            self = .link(BindingStore.link(to: identity))
            return nil
        case let .direction(direction):
            if let link, BindingStore.save(direction, through: link) {
                return direction
            }

            var action = action ?? WindowAction(.noAction)
            action.pick(direction)
            self = .action(action)
            return direction
        }
    }
}
