import Defaults
import Luminare
import SwiftUI

struct InitialWindowFramesConfigurationView: View {
    @Default(.initialWindowFramesEnabled) private var enabled
    @Default(.initialWindowFrames) private var frames
    @Binding var isPresented: Bool
    @State private var editingBundleID: String?

    var body: some View {
        LuminareForm {
            LuminareSection {
                LuminareToggle("Set initial window frames", isOn: $enabled)
                Text("Apply a configured size and position to new windows on their current display. Existing windows and excluded apps are left alone.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            LuminareSection {
                ForEach(frames.keys.sorted(), id: \.self) { id in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(frames[id]?.name ?? id)
                            Text(id).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Edit…") { editingBundleID = id }
                        Button(role: .destructive) { frames[id] = nil } label: {
                            Image(systemName: "minus.circle")
                        }
                        .help("Remove app")
                        .accessibilityLabel("Remove app")
                    }
                }
                Button("Add app…") { showAppChooser() }
            }
            Button("Done") { isPresented = false }
                .buttonStyle(.luminare(overrideUseMainStyle: true))
        }
        .luminareModal(isPresented: Binding(get: { editingBundleID != nil }, set: { if !$0 { editingBundleID = nil } })) {
            if let id = editingBundleID, let action = frames[id] {
                CustomActionConfigurationView(
                    action: Binding(get: { frames[id] ?? action }, set: { frames[id] = $0 }),
                    isPresented: Binding(get: { editingBundleID != nil }, set: { if !$0 { editingBundleID = nil } }),
                    sizeModes: [.custom]
                )
                .frame(width: 400)
            }
        }
    }

    private func showAppChooser() {
        Task { @MainActor in
            guard let window = NSApp.keyWindow ?? SettingsWindowManager.shared.window else { return }
            let panel = NSOpenPanel()
            panel.worksWhenModal = true
            panel.allowedContentTypes = [.application]
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            panel.directoryURL = FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask).first
            guard await panel.beginSheetModal(for: window) == .OK,
                  let url = panel.url, let bundle = Bundle(url: url),
                  let id = bundle.bundleIdentifier, id != Bundle.main.bundleIdentifier else { return }
            if frames[id] == nil {
                frames[id] = InitialWindowFrames.defaultAction(name: FileManager.default.displayName(atPath: url.path))
            }
            editingBundleID = id
        }
    }
}
