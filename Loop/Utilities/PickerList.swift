//
//  PickerList.swift
//  Loop
//
//  Created by Kai Azim on 2024-08-25.
//

import Luminare
import Scribe
import SwiftUI

struct PickerList<Content, V>: View where Content: View, V: Hashable, V: Identifiable {
    @Environment(\.luminareDismiss) private var dismiss
    private let eventMonitorManager: PickerListEventMonitorManager = .shared

    @Binding var selection: V
    @Binding var searchResults: [V]

    @State private var arrowSelection: V?

    private let proxy: ScrollViewProxy
    private let sections: [PickerSection<V>]
    private let content: (V) -> Content

    init(
        selection: Binding<V>,
        searchResults: Binding<[V]>,
        proxy: ScrollViewProxy,
        sections: [PickerSection<V>],
        @ViewBuilder content: @escaping (V) -> Content
    ) {
        self._selection = selection
        self._searchResults = searchResults
        self.sections = sections
        self.proxy = proxy
        self.content = content
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 4) {
            if searchResults.isEmpty {
                sectionsView
            } else {
                searchResultsView
            }
        }
        .onChange(of: searchResults) { _ in arrowSelection = nil }
        .onAppear {
            setupEventMonitor(reader: proxy)
        }
    }

    private var sectionsView: some View {
        ForEach(sections) { section in
            Section {
                ForEach(section.items, id: \.self) { item in
                    PopoverPickerItem(
                        selection: $selection,
                        arrowSelection: arrowSelection,
                        item: item,
                        content: content
                    )
                    .id(item)
                }
            } header: {
                Text(section.title)
                    .foregroundStyle(.secondary)
                    .padding([.top, .horizontal], 6)
            }
        }
    }

    private var searchResultsView: some View {
        ForEach(searchResults) { item in
            PopoverPickerItem(
                selection: $selection,
                arrowSelection: arrowSelection,
                item: item,
                content: content
            )
            .id(item)
        }
    }

    private func setupEventMonitor(reader: ScrollViewProxy) {
        eventMonitorManager.addMonitor(
            for: "pickerList",
            matching: [.keyDown]
        ) { event in
            switch event.keyCode {
            case .kVK_DownArrow:
                updateArrowSelection(increment: true, reader: reader)
            case .kVK_UpArrow:
                updateArrowSelection(increment: false, reader: reader)
            case .kVK_Return:
                if let arrowSelection {
                    selection = arrowSelection
                    dismiss()
                }
            case .kVK_Escape:
                dismiss()
            default:
                return event
            }
            return nil
        }
    }

    private func updateArrowSelection(increment: Bool, reader: ScrollViewProxy) {
        let items = searchResults.isEmpty ? sections.flatMap(\.items) : searchResults
        guard !items.isEmpty else { return }

        let currentIndex = items.firstIndex(where: { $0 == arrowSelection }) ?? (increment ? -1 : items.count)
        let nextIndex = currentIndex + (increment ? 1 : -1)

        // Ensure nextIndex is valid
        guard nextIndex >= 0, nextIndex < items.count else {
            Log.error("Invalid nextIndex: \(nextIndex), items count: \(items.count)", category: .pickerList)
            return
        }

        let newSelection = items[nextIndex]
        arrowSelection = newSelection

        // Only scroll if the selection is valid and not nil
        guard let validSelection = arrowSelection else {
            Log.info("arrowSelection is nil, skipping scroll", category: .pickerList)
            return
        }

        reader.scrollTo(validSelection, anchor: .center)
    }
}

extension LogCategory {
    static let pickerList = LogCategory("PickerList")
}

struct PopoverPickerItem<Content, V>: View where Content: View, V: Hashable {
    @Environment(\.luminareDismiss) private var dismiss
    @Environment(\.luminareAnimationFast) private var animationFast

    @State private var isHovering = false
    @Binding var selection: V
    let arrowSelection: V?
    let item: V
    let content: (V) -> Content

    private var isSelected: Bool {
        selection == item || arrowSelection == item
    }

    var body: some View {
        Button {
            selection = item
            dismiss()
        } label: {
            content(item)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
        }
        .buttonStyle(.luminare(overrideIsHovering: isSelected))
        .luminareFilledStates([.hovering, .pressed])
        .luminareBorderedStates(.hovering)
    }
}

struct PickerSection<V>: Identifiable, Hashable where V: Hashable, V: Identifiable {
    var id: String { title }

    let title: String
    let items: [V]

    init(_ title: String, _ items: [V]) {
        self.title = title
        self.items = items
    }
}

extension PickerSection where V == WindowDirection {
    static var windowDirections: [PickerSection<WindowDirection>] {
        windowDirections(allDesktops: false)
    }

    /// `allDesktops` lists every desktop action, like the CLI does, instead of only as many as there are desktops right now
    static func windowDirections(allDesktops: Bool) -> [PickerSection<WindowDirection>] {
        let spaceSwitching = allDesktops ? WindowDirection.spaceSwitching : visibleSpaceSwitchingDirections()
        let spaceSwitchingSections: [PickerSection<WindowDirection>] = spaceSwitching.isEmpty ? [] : [
            .init(String(localized: "Space Switching", comment: "Section header in the action picker of the Keybinds tab"), spaceSwitching)
        ]

        return [
            .init(String(localized: "General", comment: "Section header in the action picker of the Keybinds tab"), WindowDirection.general),
            .init(String(localized: "Halves", comment: "Section header in the action picker of the Keybinds tab"), WindowDirection.halves),
            .init(String(localized: "Quarters", comment: "Section header in the action picker of the Keybinds tab"), WindowDirection.quarters),
            .init(String(localized: "Horizontal Thirds", comment: "Section header in the action picker of the Keybinds tab"), WindowDirection.horizontalThirds),
            .init(String(localized: "Vertical Thirds", comment: "Section header in the action picker of the Keybinds tab"), WindowDirection.verticalThirds),
            .init(String(localized: "Horizontal Fourths", comment: "Section header in the action picker of the Keybinds tab"), WindowDirection.horizontalFourths),
            .init(String(localized: "Screen Switching", comment: "Section header in the action picker of the Keybinds tab"), WindowDirection.screenSwitching)
        ] + spaceSwitchingSections + [
            .init(String(localized: "Size Adjustment", comment: "Section header in the action picker of the Keybinds tab"), WindowDirection.sizeAdjustment),
            .init(String(localized: "Shrink", comment: "Section header in the action picker of the Keybinds tab"), WindowDirection.shrink),
            .init(String(localized: "Grow", comment: "Section header in the action picker of the Keybinds tab"), WindowDirection.grow),
            .init(String(localized: "Move", comment: "Section header in the action picker of the Keybinds tab"), WindowDirection.move),
            .init(String(localized: "Focus", comment: "Section header in the action picker of the Keybinds tab"), WindowDirection.focus),
            .init(String(localized: "Stash", comment: "Section header in the action picker of the Keybinds tab"), [WindowDirection.stash, WindowDirection.unstash]),
            .init(String(localized: "Go Back", comment: "Section header in the action picker of the Keybinds tab"), [WindowDirection.initialFrame, WindowDirection.undo])
        ]
    }

    private static func visibleSpaceSwitchingDirections() -> [WindowDirection] {
        guard #available(macOS 14.0, *) else {
            return []
        }

        let maximumDesktopCount = SkyLightToolBelt.maximumDesktopCount()
        guard maximumDesktopCount > 1 else {
            return []
        }

        let visibleNumberedActions = WindowDirection.numberedSpaceSwitching
            .prefix(maximumDesktopCount)

        return WindowDirection.relativeSpaceSwitching + visibleNumberedActions
    }
}
