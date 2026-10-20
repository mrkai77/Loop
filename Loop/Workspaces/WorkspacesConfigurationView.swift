//
//  WorkspacesConfigurationView.swift
//  Loop
//
//  Created on 2026-10-20.
//

import Defaults
import Luminare
import SwiftUI

struct WorkspacesConfigurationView: View {
    @ObservedObject private var displayMemory: DisplayMemoryManager = .shared

    @Default(.displayMemoryEnabled) private var displayMemoryEnabled
    @Default(.workspaceHotKeysEnabled) private var workspaceHotKeysEnabled
    @Default(.displayLayouts) private var displayLayouts
    @Default(.workspaces) private var workspaces

    var body: some View {
        LuminareForm {
            workspacesSection
            displayMemorySection
        }
    }

    // MARK: Workspaces

    private var workspacesSection: some View {
        LuminareSection(String(localized: "Workspaces", comment: "Section header shown in settings")) {
            LuminareButtonRow {
                Button(String(localized: "Save Current Layout…", comment: "Button to save every visible window as a workspace")) {
                    WorkspaceManager.shared.promptToSaveCurrentLayout()
                }
            }

            LuminareToggle("Enable ⌃⌥⌘1 – ⌃⌥⌘9 shortcuts", isOn: $workspaceHotKeysEnabled)

            if workspaces.isEmpty {
                VStack {
                    Text("No workspaces")
                        .font(.title3)
                    Text("Arrange your windows, then click “Save Current Layout…”")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding()
            } else {
                ForEach(workspaces) { workspace in
                    WorkspaceRowView(
                        workspace: workspace,
                        showsHotKey: workspaceHotKeysEnabled,
                        workspaces: $workspaces
                    )
                }
            }
        }
    }

    // MARK: Display Memory

    private var sortedLayoutKeys: [String] {
        displayLayouts.keys.sorted { displayLayouts[$0]?.updatedAt ?? .distantPast > displayLayouts[$1]?.updatedAt ?? .distantPast }
    }

    private func displayLayoutRow(key: String, layout: DisplayLayout) -> some View {
        HStack(spacing: 8) {
            Image(systemName: key == NSScreen.configurationKey ? "display.2" : "display")
                .frame(width: 24)

            VStack(alignment: .leading) {
                Text(layout.name)
                Text("\(layout.windows.count) windows · \(layout.updatedAt.formatted(.relative(presentation: .named)))")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            Spacer()

            Button {
                DisplayMemoryManager.shared.forgetLayout(key)
            } label: {
                Image(systemName: "trash")
                    .padding(4)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
    }

    private var displayMemorySection: some View {
        LuminareSection(String(localized: "Display Memory", comment: "Section header shown in settings")) {
            LuminareToggle("Restore windows when displays reconnect", isOn: $displayMemoryEnabled)

            HStack {
                Text("Current displays")
                Spacer()
                Text(displayMemory.currentConfigurationName)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 34)

            LuminareButtonRow {
                Button(String(localized: "Restore Now (⌃⌥⌘0)", comment: "Button to restore the window layout for the current displays")) {
                    Task { await DisplayMemoryManager.shared.restoreLayout() }
                }
                .disabled(displayLayouts[NSScreen.configurationKey] == nil)

                Button(String(localized: "Forget All", comment: "Button to delete every remembered display layout"), role: .destructive) {
                    displayLayouts.removeAll()
                }
                .disabled(displayLayouts.isEmpty)
            }

            ForEach(sortedLayoutKeys, id: \.self) { key in
                if let layout = displayLayouts[key] {
                    displayLayoutRow(key: key, layout: layout)
                }
            }
        }
    }
}

private struct WorkspaceRowView: View {
    let workspace: Workspace
    let showsHotKey: Bool
    @Binding var workspaces: [Workspace]

    private var index: Int? {
        workspaces.firstIndex { $0.id == workspace.id }
    }

    private var hotKey: String? {
        guard showsHotKey, let index, index < 9 else { return nil }
        return WorkspaceHotKeys.displayString(for: UInt32(index + 1))
    }

    private func binding(_ keyPath: WritableKeyPath<Workspace, Bool>) -> Binding<Bool> {
        Binding {
            workspace[keyPath: keyPath]
        } set: { newValue in
            guard let index else { return }
            workspaces[index][keyPath: keyPath] = newValue
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            appIcons

            VStack(alignment: .leading) {
                Text(workspace.name)
                Text(subtitle)
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                WorkspaceManager.shared.apply(workspace)
            } label: {
                Image(systemName: "play.fill")
                    .padding(4)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help(String(localized: "Apply", comment: "Help text for the button that applies a workspace"))

            Menu {
                Toggle(String(localized: "Open Missing Apps", comment: "Workspace option"), isOn: binding(\.launchMissingApps))
                Toggle(String(localized: "Hide Other Apps", comment: "Workspace option"), isOn: binding(\.hideOtherApps))

                Divider()

                Button(String(localized: "Replace with Current Layout", comment: "Re-save a workspace from the visible windows")) {
                    WorkspaceManager.shared.updateWithCurrentLayout(workspace)
                }
                Button(String(localized: "Rename…", comment: "Rename a workspace")) {
                    WorkspaceManager.shared.promptToRename(workspace)
                }

                Divider()

                Button(String(localized: "Move Up", comment: "Move a workspace up the list, which changes its shortcut")) {
                    move(by: -1)
                }
                .disabled(index == 0)
                Button(String(localized: "Move Down", comment: "Move a workspace down the list, which changes its shortcut")) {
                    move(by: 1)
                }
                .disabled(index == workspaces.count - 1)

                Divider()

                Button(String(localized: "Delete", comment: "Delete a workspace"), role: .destructive) {
                    WorkspaceManager.shared.delete(workspace)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
    }

    private var subtitle: String {
        let apps = workspace.appNames.joined(separator: ", ")
        guard let hotKey else { return apps }
        return "\(hotKey) · \(apps)"
    }

    private var appIcons: some View {
        HStack(spacing: -8) {
            ForEach(Array(workspace.bundleIDs.prefix(3)), id: \.self) { bundleID in
                Group {
                    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                            .resizable()
                    } else {
                        Image(systemName: "app.dashed")
                            .resizable()
                    }
                }
                .frame(width: 24, height: 24)
            }
        }
        .frame(width: 48, alignment: .leading)
    }

    private func move(by offset: Int) {
        guard let index else { return }
        let destination = index + offset
        guard workspaces.indices.contains(destination) else { return }
        workspaces.swapAt(index, destination)
    }
}
