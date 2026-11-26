//
//  InitialWindowPlacementConfigurationView.swift
//  Loop
//

import Defaults
import Luminare
import SwiftUI

struct InitialWindowPlacementConfigurationView: View {
    @Binding var isPresented: Bool
    @Default(.initialWindowFrames) private var frames
    @State private var editingID: String?
    @State private var draft = WindowAction(.custom)
    @State private var selectedIDs = Set<String>()
    @State private var pickerError: String?

    var body: some View {
        if let editingID {
            CustomActionConfigurationView(
                action: $draft,
                // Done saves the edited placement and returns to the app list in the same modal.
                isPresented: Binding(
                    get: { true },
                    set: { presented in
                        guard !presented else { return }
                        frames[editingID] = draft
                        selectedIDs = [editingID]
                        self.editingID = nil
                    }
                ),
                placementAppName: appName(editingID)
            )
        } else {
            LuminareForm {
                Text("Initial Window Placement")
                    .font(.headline)

                LuminareSection {
                    LuminareButtonRow {
                        Button("Add") { chooseApp() }
                        Button("Remove", role: .destructive) {
                            frames = frames.filter { !selectedIDs.contains($0.key) }
                            selectedIDs.removeAll()
                        }
                        .disabled(selectedIDs.isEmpty)
                        .keyboardShortcut(.delete)
                    }
                    .luminareRoundingBehavior(top: true)

                    LuminareList(items: .constant(frames.keys.sorted()), selection: $selectedIDs, id: \.self) { item in
                        let id = item.wrappedValue
                        HStack(spacing: 8) {
                            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                    .resizable()
                                    .frame(width: 24, height: 24)
                            } else {
                                Image(systemName: "app")
                                    .frame(width: 24, height: 24)
                            }

                            Text(verbatim: appName(id))
                            Spacer()

                            Button {
                                edit(id)
                            } label: {
                                Image(systemName: "slider.horizontal.3")
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Edit placement")
                            .help("Edit placement")
                        }
                        .padding(.horizontal, 12)
                        .moveDisabled(true)
                    } emptyView: {
                        VStack {
                            Text("No configured apps")
                                .font(.title3)
                            Text("Click “Add” to add an app")
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                        .padding()
                    }
                    .luminareListFixedHeight(until: 250)
                    .luminareRoundingBehavior(bottom: true)
                }

                if let pickerError {
                    Text(verbatim: pickerError)
                        .foregroundStyle(.secondary)
                }

                Button("Done") { isPresented = false }
                    .buttonStyle(.luminare(overrideUseMainStyle: true))
            }
        }
    }

    private func appName(_ id: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else {
            return id
        }
        return FileManager.default.displayName(atPath: url.path)
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask).first
        pickerError = nil
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        guard let id = Bundle(url: url)?.bundleIdentifier else {
            pickerError = String(localized: "This app has no bundle identifier.")
            return
        }
        guard InitialWindowFrames.allowsPlacement(bundleID: id, url: url) else {
            pickerError = String(localized: "Loop skips window placement for this app.")
            return
        }
        edit(id)
    }

    private func edit(_ id: String) {
        draft = frames[id] ?? WindowAction(.custom)
        draft.direction = .custom
        draft.sizeMode = .custom
        editingID = id
    }
}
