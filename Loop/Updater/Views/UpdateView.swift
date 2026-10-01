//
//  UpdateView.swift
//  Loop
//
//  Created by Kami on 15/06/2024.
//

import Defaults
import Luminare
import SwiftUI

struct UpdateView: View {
    @Environment(\.luminareTintColor) var tintColor
    @Environment(\.luminareAnimation) var luminareAnimation
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject var updater = Updater.shared

    @Default(.currentIcon) private var currentIcon

    @State private var isShowingTheLoopTimes: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                if isShowingTheLoopTimes {
                    theLoopTimesView()
                        .padding(.top, 18)
                        .padding(.bottom, 8)
                        .contentShape(.rect)
                        .onTapGesture {
                            withAnimation(.smooth(duration: 0.25)) {
                                isShowingTheLoopTimes.toggle()
                            }
                        }

                    VStack(spacing: 4) {
                        Divider()

                        updateDateView()

                        Divider()
                    }
                } else {
                    appIconView()
                        .onTapGesture {
                            withAnimation(.smooth(duration: 0.25)) {
                                isShowingTheLoopTimes.toggle()
                            }
                        }

                    versionChangeView()
                }
            }

            changelogView()
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }

            footerView()
        }
        .frame(width: 500, height: 480)
        .padding(.top, 38) // titlebar
        .luminareBackground()
    }

    private func theLoopTimesView() -> some View {
        ZStack {
            if colorScheme == .dark {
                TheLoopTimes()
                    .fill(
                        .shadow(.inner(color: .black.opacity(0.1), radius: 3))
                            .shadow(.inner(color: .black.opacity(0.3), radius: 5, y: 3))
                    )
                    .foregroundStyle(.primary.opacity(0.7))
                    .blendMode(.overlay)
            } else {
                TheLoopTimes()
                    .foregroundStyle(.primary.opacity(0.7))
                    .blendMode(.overlay)

                TheLoopTimes()
                    .fill(
                        .shadow(.inner(color: .black.opacity(0.1), radius: 3))
                            .shadow(.inner(color: .black.opacity(0.3), radius: 5, y: 3))
                    )
                    .blendMode(.overlay)
            }

            TheLoopTimes()
                .stroke(.primary.opacity(0.1), lineWidth: 1)
                .blendMode(.luminosity)
        }
        .aspectRatio(883.88 / 135.53, contentMode: .fit)
        .frame(width: 400)
    }

    @ViewBuilder
    private func appIconView() -> some View {
        if let image = NSImage(named: currentIcon) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 128)
        }
    }

    private func updateDateView() -> some View {
        ZStack {
            if let updateDate = updater.updateManifest?.publishedAt {
                Text(updateDate.formatted(date: .complete, time: .shortened))
                    .fontDesign(.serif)
                    .foregroundStyle(.tertiary)
                    .fontWeight(.medium)
            } else {
                versionChangeView()
            }
        }
    }

    private func versionChangeView() -> some View {
        ZStack {
            versionChangeText()
                .foregroundStyle(.tertiary)
                .fontWeight(.medium)
        }
    }

    private func versionChangeText() -> some View {
        HStack {
            let currentVersion = VersionDisplay.current

            if let targetRelease = updater.updateManifest {
                let targetVersion = targetRelease.versionDisplay()

                Text(currentVersion.shortDisplay)
                Image(systemName: "arrow.right")
                Text(targetVersion.shortDisplay)
            } else {
                Text("Updating from \(Text(currentVersion.shortDisplay))")
                    .fontWeight(.semibold)
            }
        }
    }

    private func changelogView() -> some View {
        ScrollView(showsIndicators: false) {
            VStack { // Using LazyVStack seems to cause visual glitches
                ForEach(updater.changelog) { section in
                    let isExpanded = updater.expandedChangelogSections.contains(section.id)

                    ChangelogSectionView(
                        section: section,
                        isExpanded: isExpanded,
                        onToggle: {
                            withAnimation(.smooth(duration: 0.25)) {
                                if isExpanded {
                                    updater.expandedChangelogSections.remove(section.id)
                                } else {
                                    updater.expandedChangelogSections.insert(section.id)
                                }
                            }
                        }
                    )
                }
            }
            .padding(.top, 10)
            .padding(12)
        }
    }

    private func footerView() -> some View {
        HStack {
            Button {
                Updater.shared.dismissWindow()
            } label: {
                Text(updater.installState.isFailure ? "Try Again Later" : "Remind Me Later")
                    .contentTransition(.numericText())
                    .padding(.trailing, 4)
                    .luminareToolTip(attachedTo: .topTrailing, hidden: updater.installState.errorDescription == nil) {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.secondary)
                                .padding(4)

                            Text(updater.installState.errorDescription ?? "")
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: 300, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(12)
                    }
            }
            .disabled(updater.installState == .installing || updater.installState == .readyToRestart)

            Button(role: updater.installState.isFailure ? .destructive : nil) {
                Task {
                    if updater.installState == .readyToRestart {
                        await Updater.shared.relaunchAfterUpdate()
                        return
                    }

                    try await Updater.shared.downloadAndInstallUpdate()
                }
            } label: {
                ZStack {
                    if updater.installState == .installing {
                        Capsule()
                            .frame(maxWidth: .infinity)
                            .frame(height: 5)
                            .foregroundStyle(.quinary)
                            .overlay {
                                GeometryReader { geo in
                                    Capsule()
                                        .foregroundStyle(tintColor)
                                        .frame(width: CGFloat(updater.progressBar) * geo.size.width)
                                        .animation(.smooth(duration: 0.8), value: updater.progressBar)
                                        .shadow(color: tintColor.opacity(0.1), radius: 12)
                                        .shadow(color: tintColor.opacity(0.4), radius: 6)
                                        .shadow(color: tintColor, radius: 1)
                                }
                            }
                            .padding(.horizontal, 12)
                    }

                    Text(updater.installState.label)
                        .contentTransition(.numericText())
                        .opacity(updater.installState == .installing ? 0 : 1)
                        .opacity(updater.installState.isFailure ? 0.5 : 1.0)
                }
            }
            .allowsHitTesting(updater.installState.isUpdateButtonInteractive)
        }
        .buttonStyle(.luminare(overrideUseMainStyle: true))
        .luminareCornerRadius(8)
        .padding(12)
        .animation(luminareAnimation, value: updater.installState)
        .overlay {
            VStack {
                Divider()
                Spacer()
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
