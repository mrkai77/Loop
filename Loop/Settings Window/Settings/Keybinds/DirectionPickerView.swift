//
//  DirectionPickerView.swift
//  Loop
//
//  Created by Kai Azim on 2025-10-18.
//

import SwiftUI

struct DirectionPickerView: View {
    @State private var searchText = ""
    @State private var searchResults: [WindowDirection] = []
    @FocusState private var isSearchFocused: Bool

    @Binding private var direction: WindowDirection
    private let isInCycle: Bool

    private var sections: [PickerSection<WindowDirection>] {
        let sections = PickerSection.windowDirections

        guard isInCycle else { return sections }
        return sections.compactMap { section in
            // Remove repeatable actions; we're already in a cycle
            let items = section.items.filter { !WindowAction($0).allowsRapidRepeat }
            return items.isEmpty ? nil : PickerSection(section.title, items)
        }
    }

    private var moreSection: PickerSection<WindowDirection> {
        let title = String(localized: "More", comment: "Section header in the action picker of the Keybinds tab")
        if isInCycle {
            return .init(title, [WindowDirection.custom])
        } else {
            return .init(title, [WindowDirection.custom, WindowDirection.cycle])
        }
    }

    private var sectionItems: [WindowDirection] {
        sections
            .map(\.items)
            .flatMap(\.self)
    }

    init(direction: Binding<WindowDirection>, isInCycle: Bool) {
        self._direction = direction
        self.isInCycle = isInCycle
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField(
                String(localized: "Search for a window action", defaultValue: "Search…"),
                text: $searchText
            )
            .textFieldStyle(.plain)
            .focused($isSearchFocused)
            .padding(12)

            Divider()

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    PickerList(
                        selection: $direction,
                        searchResults: $searchResults,
                        proxy: proxy,
                        sections: sections + [moreSection]
                    ) { item in
                        HStack(spacing: 8) {
                            IconView(direction: item)

                            Text(item.name)
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

        let matches = sectionItems
            .compactMap { item -> (WindowDirection, Int)? in
                if let score = fuzzyScore(item.name, key) {
                    return (item, score)
                }
                return nil
            }
            .sorted { $0.1 < $1.1 }
            .map(\.0)

        searchResults = matches + moreSection.items
    }

    private func fuzzyScore(_ text: String, _ pattern: String) -> Int? {
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
                pIndex = text.index(after: pIndex)
            }
            tIndex = text.index(after: tIndex)
        }

        if pIndex == pattern.endIndex { return 2 }

        return nil
    }
}
