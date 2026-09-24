//
//  ExcludedAppsConfiguration.swift
//  Loop
//
//  Created by Kai Azim on 2024-05-25.
//

import Defaults
import Luminare
import SwiftUI

struct ExcludedAppsConfigurationView: View {
    @Default(.excludedApps) private var excludedApps
    @State private var selectedApps = Set<URL>()

    var body: some View {
        LuminareForm {
            LuminareSection {
                LuminareButtonRow {
                    Button("Add") {
                        showAppChooser()
                    }

                    Button("Remove", role: .destructive) {
                        excludedApps.removeAll { selectedApps.contains($0) }
                    }
                    .disabled(selectedApps.isEmpty)
                    .keyboardShortcut(.delete)
                }
                .luminareRoundingBehavior(top: true)

                LuminareList(
                    items: $excludedApps,
                    selection: $selectedApps,
                    id: \.self
                ) { item in
                    ExcludedListAppView(url: item.wrappedValue)
                        .equatable()
                } emptyView: {
                    VStack {
                        Text("No excluded applications")
                            .font(.title3)
                        Text("Press \"Add\" to add an application")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                    .padding()
                }
                .luminareRoundingBehavior(bottom: true)
            }
        }
    }

    func showAppChooser() {
        Task { @MainActor in
            guard let window = SettingsWindowManager.shared.window else { return }

            let panel = NSOpenPanel()
            panel.worksWhenModal = true
            panel.allowsMultipleSelection = true
            panel.canChooseDirectories = false
            panel.canChooseFiles = true
            panel.allowedContentTypes = [.application]
            panel.allowsOtherFileTypes = false
            panel.resolvesAliases = true
            panel.directoryURL = FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask).first

            let result = await panel.beginSheetModal(for: window)

            if result == .OK {
                let appsToAdd = panel.urls.compactMap { excludedApps.contains($0) ? nil : $0 }
                excludedApps.append(contentsOf: appsToAdd)
            }
        }
    }
}

struct ExcludedListAppView: View, Equatable {
    @State var app: App

    init(url: URL) {
        self.app = App(url: url) ?? App(
            bundleID: "unknown",
            displayName: url.lastPathComponent,
            path: url.relativePath,
            url: url.absoluteURL,
            icon: .init(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil)
        )
    }

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let icon = app.icon {
                    Image(nsImage: icon)
                } else {
                    ProgressView()
                }
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading) {
                Text(app.displayName)

                Text(app.path)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            Spacer()

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: app.path)])
            } label: {
                Group {
                    if #available(macOS 26, *) {
                        Image(systemName: "finder")
                    } else {
                        Image(systemName: "arrow.up.forward")
                    }
                }
                .padding(4)
                .contentShape(.rect)
            }
            .luminareContentSize(
                aspectRatio: 1.0,
                contentMode: .fit,
                hasFixedHeight: true
            )
            .luminareRoundingBehavior(top: true, bottom: true)
            .luminareSurfaceStyle(.flat)
        }
        .padding(.horizontal, 12)
        .task {
            app = await app.loadIconIfNeeded()
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.app.url == rhs.app.url
    }

    struct App: Identifiable {
        var id: String { bundleID }
        let bundleID: String
        let icon: NSImage?
        let displayName: String
        let path: String
        let url: URL

        init?(url: URL) {
            guard
                let meta = NSMetadataItem(url: url),
                let bundleId = meta.value(forAttribute: NSMetadataItemCFBundleIdentifierKey) as? String,
                let displayName = meta.value(forAttribute: NSMetadataItemDisplayNameKey) as? String,
                let path = meta.value(forAttribute: NSMetadataItemPathKey) as? String
            else {
                return nil
            }

            self.bundleID = bundleId
            self.icon = nil
            self.displayName = displayName
            self.path = path
            self.url = url
        }

        init(bundleID: String, displayName: String, path: String, url: URL, icon: NSImage?) {
            self.bundleID = bundleID
            self.displayName = displayName
            self.path = path
            self.url = url
            self.icon = icon
        }

        func loadIconIfNeeded() async -> App {
            guard icon == nil else { return self }

            return .init(
                bundleID: bundleID,
                displayName: displayName,
                path: path,
                url: url,
                icon: NSWorkspace.shared.icon(forFile: path)
            )
        }
    }
}
