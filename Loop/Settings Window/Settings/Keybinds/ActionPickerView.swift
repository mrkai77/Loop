//
//  ActionPickerView.swift
//  Loop
//
//  Created by Kai Azim on 2026-01-02.
//

import SwiftUI
import Tome

/// Picks an action, or a reference to another binding.
/// `owner` hides the binding being edited and references that would loop.
struct ActionPickerView: View {
    @TomeValue(\.keyBindings) private var keybinds
    @TomeValue(\.gestureBindings) private var gestures
    @TomeValue(\.radialMenuBindings) private var radialBindings

    @State private var searchText = ""
    @State private var searchResults: [ActionTarget] = []
    @FocusState private var isSearchFocused: Bool

    @Binding private var selection: ActionTarget
    private let owner: BindingReference?
    /// `false` for cycle steps, which can't be cycles.
    private let allowsCycles: Bool

    private let directionSections: [PickerSection<ActionTarget>] = {
        let windowDirections = PickerSection.windowDirections
            .map { section in
                PickerSection(
                    section.title,
                    section.items.map { ActionTarget.windowAction(.init($0)) }
                )
            }

        let moreSection = PickerSection(
            String(localized: "More", comment: "Section header in the action picker of the Keybinds tab"),
            [WindowDirection.custom, WindowDirection.cycle].map { ActionTarget.windowAction(.init($0)) }
        )

        return windowDirections + [moreSection]
    }()

    private var keybindsSection: PickerSection<ActionTarget> {
        PickerSection(
            "Your Keybinds",
            keybinds.map { .reference($0.reference) }
        )
    }

    private var allSections: [PickerSection<ActionTarget>] {
        let sections = directionSections + [keybindsSection,
                                            PickerSection("Your Gestures", gestures.filter { $0.kind != .radialMenu }.map { .reference($0.reference) }),
                                            PickerSection("Your Radial Menu", radialBindings.map { .reference($0.reference) })]
        return sections.map { section in
            PickerSection(section.title, section.items.filter { item in
                if !allowsCycles, resolvedPickerAction(item)?.direction == .cycle { return false }
                // Remove repeatable actions; we're already in a cycle
                if !allowsCycles, case let .windowAction(action) = item, action.allowsRapidRepeat { return false }
                guard let owner else { return true }
                return !item.isReference || graph.canSetTarget(item, for: owner)
            })
        }
    }

    private var allSectionItems: [ActionTarget] {
        allSections
            .map(\.items)
            .flatMap(\.self)
    }

    private var managedSelection: Binding<ActionTarget> {
        Binding(get: { selection }, set: { picked in
            var promotedGraph = graph
            let picked = promotedGraph.promoted(picked) ?? picked
            promotedGraph.commit()
            if case let .windowAction(previous) = selection, case let .windowAction(action) = picked {
                selection = .windowAction(previous.direction == action.direction ? previous : action.withRuntimeID(previous.id))
            } else {
                selection = picked
            }
        })
    }

    init(selection: Binding<ActionTarget>, owner: BindingReference? = nil, allowsCycles: Bool = true) {
        self._selection = selection
        self.owner = owner
        self.allowsCycles = allowsCycles
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
                        selection: managedSelection,
                        searchResults: $searchResults,
                        proxy: proxy,
                        sections: allSections
                    ) { item in
                        HStack(spacing: 8) {
                            if let action = resolvedPickerAction(item) {
                                HStack(spacing: 8) {
                                    IconView(action: graph.iconAction(for: action))

                                    Text(action.getName())
                                        .fontWeight(.regular)
                                        .lineLimit(1)
                                }
                            } else {
                                Image(systemName: "bolt.horizontal.fill")
                            }

                            Spacer()

                            if item.isReference {
                                Image(systemName: "keyboard")
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
        .onChange(of: searchText) { _ in computeSearchResults() }
        .onChange(of: graph) { _ in computeSearchResults() }
        .onChange(of: owner) { _ in computeSearchResults() }
    }

    private var graph: ActionTargetEditorGraph {
        .init(keyBindings: keybinds, gestureBindings: gestures, radialMenuBindings: radialBindings)
    }

    /// Doesn't give the referenced binding a written id just to display it.
    private func resolvedPickerAction(_ target: ActionTarget) -> WindowAction? {
        let candidate: ActionTarget? = switch target {
        case let .reference(reference): graph.target(of: reference)
        case .windowAction: target
        }
        return candidate.flatMap(graph.resolve)
    }

    private func computeSearchResults() {
        guard !searchText.isEmpty else {
            searchResults = []
            return
        }

        let key = searchText.lowercased()

        let matches = allSectionItems
            .compactMap { item -> (ActionTarget, Int)? in
                guard let action = resolvedPickerAction(item) else { return nil }

                if let score = DirectionPickerView.fuzzyScore(action.getName(), key) {
                    return (item, score)
                }

                return nil
            }
            .sorted { $0.1 < $1.1 }
            .map(\.0)

        searchResults = matches
    }
}
