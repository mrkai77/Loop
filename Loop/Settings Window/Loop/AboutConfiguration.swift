//
//  AboutConfiguration.swift
//  Loop
//
//  Created by Kai Azim on 2024-04-26.
//

import Combine
import Defaults
import Luminare
import SwiftUI

@MainActor
final class AboutConfigurationModel: ObservableObject {
    @Published var isHoveringOverVersionCopier = false
    @Published var isHoveringOverUpdateButton = false
    @Published var didCompleteCopyToClipboard: Bool = false
    @Published private(set) var updateButtonMessage: String?

    let credits: [CreditItem] = [
        .init(
            "Kai",
            Text("Development", comment: "Role title shown in Loop’s credits section."),
            url: .init(string: "https://github.com/mrkai77")!,
            avatar: Image(.kai)
        ),
        .init(
            "Kami",
            Text("Development", comment: "Role title shown in Loop’s credits section."),
            url: .init(string: "https://github.com/senpaihunters")!,
            avatar: Image(.kami)
        ),
        .init(
            "Jace",
            Text("Design", comment: "Role title shown in Loop’s credits section."),
            url: .init(string: "https://x.com/jacethings")!,
            avatar: Image(.jace)
        ),
        .init(
            .init(localized: "Contributors on GitHub"),
            Text("Some features, ideas, and bug fixes", comment: "Role title for contributors on GitHub shown in Loop’s credits section."),
            url: .init(string: "https://github.com/MrKai77/Loop/graphs/contributors")!,
            avatar: Image(.github)
        )
    ]

    /// A max of 28 W's can fit in here :)
    private let upToDateText: [String] = [
        .init(localized: "No updates available message 01", defaultValue: "Engage! …in the current version, it's the latest."),
        .init(localized: "No updates available message 02", defaultValue: "This app is more up to date than my diary entries!"),
        .init(localized: "No updates available message 03", defaultValue: "You're in the clear, no updates in the atmosphere!"),
        .init(localized: "No updates available message 04", defaultValue: "The odds are ever in your favor, no updates today!"),
        .init(localized: "No updates available message 05", defaultValue: "Our app is on a digital diet. No new bytes allowed."),
        .init(localized: "No updates available message 06", defaultValue: "New version? Sorry, we're too attached to this one."),
        .init(localized: "No updates available message 07", defaultValue: "Your Loop is Loopier than ever, no updates found!"),
        .init(localized: "No updates available message 08", defaultValue: "I'm giving it all she's got, Captain! No updates!"),
        .init(localized: "No updates available message 09", defaultValue: "In a galaxy far, far away… still no updates!"),
        .init(localized: "No updates available message 10", defaultValue: "You've got the precious, no updates needed!"),
        .init(localized: "No updates available message 11", defaultValue: "Riding at warp speed, no updates in sight!"),
        .init(localized: "No updates available message 12", defaultValue: "This is not the update you're looking for!"),
        .init(localized: "No updates available message 13", defaultValue: "We've misplaced the 'Update' button. Oops!"),
        .init(localized: "No updates available message 14", defaultValue: "I swear it was here somewhere… one sec"),
        .init(localized: "No updates available message 15", defaultValue: "An apple a day keeps the… updates away."),
        .init(localized: "No updates available message 16", defaultValue: "May the Force be with you… next time!"),
        .init(localized: "No updates available message 17", defaultValue: "The Force is strong with this version!"),
        .init(localized: "No updates available message 18", defaultValue: "Just a small town app, same old version"),
        .init(localized: "No updates available message 19", defaultValue: "Winter is coming. Updates aren't yet."),
        .init(localized: "No updates available message 20", defaultValue: "Sweet dreams are made of… no updates"),
        .init(localized: "No updates available message 21", defaultValue: "The update fairy skipped us this week."),
        .init(localized: "No updates available message 22", defaultValue: "Stay sharp, more intel coming soon!"),
        .init(localized: "No updates available message 23", defaultValue: "You're cruising on the latest tech!"),
        .init(localized: "No updates available message 24", defaultValue: "We’ll be back. With updates… later"),
        .init(localized: "No updates available message 25", defaultValue: "A penny for your… lack of updates."),
        .init(localized: "No updates available message 26", defaultValue: "You've already got the best Loop!"),
        .init(localized: "No updates available message 27", defaultValue: "One does not simply update Loop."),
        .init(localized: "No updates available message 28", defaultValue: "All work and no… no updates…"),
        .init(localized: "No updates available message 29", defaultValue: "A watched pot never… updates."),
        .init(localized: "No updates available message 30", defaultValue: "99 problems, updates ain't one."),
        .init(localized: "No updates available message 31", defaultValue: "I… uhh… one sec I lost it"),
        .init(localized: "No updates available message 32", defaultValue: "You’ve leveled up to the max!"),
        .init(localized: "No updates available message 33", defaultValue: "Beggars can't be… updaters."),
        .init(localized: "No updates available message 34", defaultValue: "Money can't buy… updates."),
        .init(localized: "No updates available message 35", defaultValue: "No new intel, Commander."),
        .init(localized: "No updates available message 36", defaultValue: "No updates? Great Scott!"),
        .init(localized: "No updates available message 37", defaultValue: "No updates, Mr. Anderson"),
        .init(localized: "No updates available message 38", defaultValue: "No updates in Ba Sing Se"),
        .init(localized: "No updates available message 39", defaultValue: "Updates? In this economy?"),
        .init(localized: "No updates available message 40", defaultValue: "Check back next time!"),
        .init(localized: "No updates available message 41", defaultValue: "Loop is in its prime!"),
        .init(localized: "No updates available message 42", defaultValue: "All systems are a-go!"),
        .init(localized: "No updates available message 43", defaultValue: "You're up to date :)"),
        .init(localized: "No updates available message 44", defaultValue: "No updates yet!")
    ]
    private var shuffledTexts: [String] = []

    private func getNextUpToDateText() -> String {
        // If shuffledTexts is empty, fill it with a shuffled version of upToDateText
        if shuffledTexts.isEmpty {
            shuffledTexts = upToDateText.filter { $0 != "-" }.shuffled()
        }
        // Pop the last element to ensure it's not repeated until all have been shown
        return shuffledTexts.popLast() ?? upToDateText[0] // Fallback string
    }

    func showUpdatesUnavailableText() async {
        updateButtonMessage = getNextUpToDateText()
        let currentTitle = updateButtonMessage

        try? await Task.sleep(for: .seconds(2))

        if updateButtonMessage == currentTitle {
            updateButtonMessage = nil
        }
    }

    func copyVersionToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(
            "Version \(VersionDisplay.current.fullDisplay)",
            forType: NSPasteboard.PasteboardType.string
        )

        didCompleteCopyToClipboard = true

        Task { @MainActor in
            try await Task.sleep(for: .seconds(2))
            didCompleteCopyToClipboard = false
        }
    }
}

struct CreditItem: Identifiable, Equatable {
    var id: String { name }

    let name: String
    let description: Text?
    let url: URL
    let avatar: Image

    init(_ name: String, _ description: Text? = nil, url: URL, avatar: Image) {
        self.name = name
        self.description = description
        self.avatar = avatar
        self.url = url
    }
}

struct AboutConfigurationView: View {
    @Environment(\.luminareAnimation) private var luminareAnimation
    @Environment(\.luminareAnimationFast) private var luminareAnimationFast
    @Environment(\.openURL) private var openURL

    @StateObject private var model = AboutConfigurationModel()
    @ObservedObject private var updater = Updater.shared

    @Default(.timesLooped) private var timesLooped
    @Default(.currentIcon) private var currentIcon
    @Default(.includeDevelopmentVersions) private var includeDevelopmentVersions
    @Default(.automaticallyUpdate) private var automaticallyUpdate

    private var updateButtonEnabled: Bool {
        updater.updatesEnabled || model.isHoveringOverUpdateButton
    }

    private var updateButtonDefaultText: String {
        if updater.updatesEnabled {
            updater.updateState.text
        } else {
            model.isHoveringOverUpdateButton ? "`sudo upgrade loop`" : String(localized: "Updates are disabled")
        }
    }

    private var updateButtonText: String {
        model.updateButtonMessage ?? updateButtonDefaultText
    }

    var body: some View {
        LuminareForm {
            iconHeader
            updateSection
            communitySection
            creditsSection
        }
    }

    private var iconHeader: some View {
        LuminareSection {
            HStack {
                if let image = NSImage(named: currentIcon) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 60)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(Bundle.main.appName)
                        .fontWeight(.medium)

                    Text(
                        model.isHoveringOverVersionCopier
                            ? "Version \(Text(VersionDisplay.current.fullDisplay))"
                            : (timesLooped >= 1_000_000 ? "You've looped… uhh… I… lost count…" : "You've looped \(timesLooped) times!")
                    )
                    .contentTransition(.numericText(countsDown: !model.isHoveringOverVersionCopier))
                    .animation(luminareAnimation, value: timesLooped)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                if model.isHoveringOverVersionCopier {
                    Button {
                        model.copyVersionToClipboard()
                    } label: {
                        Image(systemName: "document.on.clipboard")
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
                    .luminarePopover(
                        isPresented: $model.didCompleteCopyToClipboard,
                        arrowEdge: .bottom,
                        shouldHideAnchor: true
                    ) {
                        Text("Copied!")
                            .padding(6)
                    }
                }
            }
            .padding(.trailing, 8)
            .padding(4)
            .onHover { model.isHoveringOverVersionCopier = $0 }
            .animation(luminareAnimationFast, value: model.isHoveringOverVersionCopier)
        }
    }

    private var updateSection: some View {
        LuminareSection {
            LuminareButtonRow {
                Button {
                    Task {
                        await updater.fetchLatestInfo(bypassUpdatesEnabled: true)

                        switch updater.updateState {
                        case .available:
                            await updater.showUpdateWindowIfEligible()
                        case .unavailable:
                            await model.showUpdatesUnavailableText()
                        case .osNotSupported:
                            break
                        }
                    }
                } label: {
                    Text(.init(updateButtonText))
                        .contentTransition(.numericText())
                        .animation(luminareAnimation, value: updateButtonText)
                }
                .disabled(!updateButtonEnabled)
                .onHover { model.isHoveringOverUpdateButton = $0 }
            }
            .luminareRoundingBehavior(top: true)

            LuminareToggle("Include development versions", isOn: $includeDevelopmentVersions)

            LuminareToggle(isOn: $automaticallyUpdate) {
                Text("Automatically install updates")
                    .padding(.trailing, automaticallyUpdate ? 4 : 0)
                    .luminareToolTip(attachedTo: .topTrailing, hidden: !automaticallyUpdate) {
                        Text("Updates will only be installed when \(Bundle.main.appName) is in the background.")
                            .padding(6)
                    }
                    .animation(luminareAnimation, value: automaticallyUpdate)
            }
        }
    }

    private var communitySection: some View {
        LuminareSection {
            Text(
                "Share feedback on our GitHub page, where you can let us know about any bugs, suggest features, or share other ideas. If Loop has improved your workflow, you can also donate :)"
            )
            .padding(8)

            LuminareButtonRow {
                Button("Send Feedback") {
                    openURL(URL(string: "https://github.com/MrKai77/Loop")!)
                }

                Button("Join Discord") {
                    openURL(URL(string: "https://discord.gg/2CZ2N6PKjq")!)
                }

                Button("Donate") {
                    openURL(URL(string: "https://github.com/sponsors/MrKai77")!)
                }
            }
            .luminareRoundingBehavior(bottom: true)
        }
    }

    private var creditsSection: some View {
        LuminareSection(String(localized: "Credits", comment: "Section header shown in settings")) {
            ForEach(model.credits) { credit in
                creditView(credit)
                    .luminareRoundingBehavior(
                        top: (credit == model.credits.first) == true,
                        bottom: (credit == model.credits.last) == true
                    )
            }
        }
    }

    private func creditView(_ credit: CreditItem) -> some View {
        HStack(spacing: 12) {
            credit.avatar
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 40)
                .overlay {
                    Circle()
                        .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                }
                .clipShape(.circle)

            VStack(alignment: .leading) {
                Text(credit.name)

                if let description = credit.description {
                    description
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                openURL(credit.url)
            } label: {
                Image(systemName: "link")
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
        .padding(12)
    }
}
