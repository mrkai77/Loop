//
//  IconConfiguration.swift
//  Loop
//
//  Created by Kai Azim on 2024-04-19.
//

import Defaults
import Luminare
import SwiftUI

final class IconConfigurationModel: ObservableObject {
    @Published var showingLockedAlert = false
    @Published var selectedLockedMessage: String = ""

    let lockedMessages: [String] = [
        .init(localized: "Locked icon message 1", defaultValue: "You don’t have that yet!"),
        .init(localized: "Locked icon message 2", defaultValue: "Who do you think you are, trying to access these top secret icons?"),
        .init(localized: "Locked icon message 3", defaultValue: "Patience is a virtue, and your key to this icon."),
        .init(localized: "Locked icon message 4", defaultValue: "This icon is locked, but your potential is not!"),
        .init(localized: "Locked icon message 5", defaultValue: "Keep Looping, and this icon will be yours in no time."),
        .init(localized: "Locked icon message 6", defaultValue: "This icon is still under wraps, stay tuned!"),
        .init(localized: "Locked icon message 7", defaultValue: "Some icons are worth the wait, don't you think?"),
        .init(localized: "Locked icon message 8", defaultValue: "Not yet, but you're closer than you were yesterday!"),
        .init(localized: "Locked icon message 9", defaultValue: "Unlocking this icon is just a matter of time and Loops."),
        .init(localized: "Locked icon message 10", defaultValue: "This icon is like a fine wine, it needs more time."),
        .init(localized: "Locked icon message 11", defaultValue: "Stay curious, and soon this icon will be within your reach."),
        .init(localized: "Locked icon message 12", defaultValue: "Keep up the good work, and this icon will be your reward."),
        .init(localized: "Locked icon message 13", defaultValue: "This icon is reserved for the most dedicated Loopers."),
        .init(localized: "Locked icon message 14", defaultValue: "Your journey is not yet complete, this icon awaits at the end."),
        .init(localized: "Locked icon message 15", defaultValue: "In due time, this icon shall be revealed to you."),
        .init(localized: "Locked icon message 16", defaultValue: "Patience, young Looper, this icon is not far away."),
        .init(localized: "Locked icon message 17", defaultValue: "The journey of a thousand Loops begins with a single step."),
        .init(localized: "Locked icon message 18", defaultValue: "Every Loop brings you closer to the treasure that awaits."),
        .init(localized: "Locked icon message 19", defaultValue: "With each Loop, the lock on this icon weakens."),
        .init(localized: "Locked icon message 20", defaultValue: "Loop after Loop, your dedication carves the key to success."),
        .init(localized: "Locked icon message 21", defaultValue: "The icons are not just unlocked; they're earned, Loop by Loop."),
        .init(localized: "Locked icon message 22", defaultValue: "As the Loops accumulate, so too will your collection of icons."),
        .init(localized: "Locked icon message 23", defaultValue: "Think of each Loop as a riddle, solving the mystery of the locked icon."),
        .init(localized: "Locked icon message 24", defaultValue: "Your persistence in Looping is the master key to all icons."),
        .init(localized: "Locked icon message 25", defaultValue: "Loop around the obstacles; your reward is just beyond them."),
        .init(localized: "Locked icon message 26", defaultValue: "Each Loop you complete plants the seeds for icons to grow."),
        .init(localized: "Locked icon message 27", defaultValue: "Like the moon's phases, your icons will reveal themselves in cycles of Loops."),
        .init(localized: "Locked icon message 28", defaultValue: "The icons await, hidden behind the veil of Loops yet to be made.")
    ]
    private var shuffledTexts: [String] = []

    func getNextUpToDateText() -> String {
        // If shuffledTexts is empty, fill it with a shuffled version of lockedMessages
        if shuffledTexts.isEmpty {
            shuffledTexts = lockedMessages.filter { $0 != "-" }.shuffled()
        }
        // Pop the last element to ensure it's not repeated until all have been shown
        return shuffledTexts.popLast() ?? lockedMessages[0] // Fallback string
    }

    func handleNotificationChange() {
        if Defaults[.notificationWhenIconUnlocked] {
            AppDelegate.sendNotification(
                Bundle.main.appName,
                .init(localized: "Icon notifications enabled", defaultValue: "You’ll be notified when you unlock a new icon.")
            )
            if !AppDelegate.areNotificationsEnabled() {
                Defaults[.notificationWhenIconUnlocked] = false
                userDisabledNotificationsAlert()
            }
        }
    }

    private func userDisabledNotificationsAlert() {
        Task { @MainActor in
            guard let window = SettingsWindowManager.shared.window else { return }
            let alert = NSAlert()
            alert.messageText = .init(localized: "Notification permits: info", defaultValue: "Notifications for \(Bundle.main.appName) are turned off.")
            alert.informativeText = .init(localized: "Notification permits: request", defaultValue: "Turn them on in System Settings.")

            let button = alert.addButton(withTitle: .init(localized: "Notification permits: open notification settings", defaultValue: "Open System Settings"))

            // Reference: https://x.com/leoshimo/status/1975642593569738755
            if #available(macOS 26.0, *) {
                button.tintProminence = .primary
            }

            alert.alertStyle = .warning
            let modalResponse = await alert.beginSheetModal(for: window)

            if modalResponse == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
            }
        }
    }

    func nextIconUnlockLoopCount(timesLooped: Int) -> Int {
        Icon.all.first { $0.unlockTime > timesLooped }?.unlockTime ?? 0
    }
}

struct IconConfigurationView: View {
    @Environment(\.openURL) var openURL
    @StateObject private var model = IconConfigurationModel()

    @Default(.currentIcon) var currentIcon
    @Default(.showDockIcon) var showDockIcon
    @Default(.notificationWhenIconUnlocked) var notificationWhenIconUnlocked

    var body: some View {
        LuminareForm {
            LuminareSection {
                LuminarePicker(
                    elements: Icon.all,
                    selection: Binding(
                        get: { IconManager.currentAppIcon },
                        set: {
                            currentIcon = $0.assetName

                            Task {
                                IconManager.refreshCurrentAppIcon()
                            }
                        }
                    )
                ) { icon in
                    IconVew(model: model, icon: icon)
                        .aspectRatio(1, contentMode: .fit)
                        .alert(isPresented: $model.showingLockedAlert) {
                            Alert(
                                title: Text(.init(localized: "Locked icon alert title", defaultValue: "Icon Locked")),
                                message: Text(model.selectedLockedMessage),
                                dismissButton: .default(Text("OK"))
                            )
                        }
                }
                .luminareRoundingBehavior(top: true, bottom: true)
            }

            LuminareSection {
                LuminareToggle("Show in Dock", isOn: $showDockIcon)
                LuminareToggle(
                    "Notify when new icons are unlocked",
                    isOn: Binding(
                        get: {
                            notificationWhenIconUnlocked
                        },
                        set: {
                            notificationWhenIconUnlocked = $0
                            model.handleNotificationChange()
                        }
                    )
                )
            }
        }
    }
}

struct IconVew: View {
    @Environment(\.luminareAnimation) private var luminareAnimation

    @ObservedObject var model: IconConfigurationModel
    let icon: Icon

    @State private var hasBeenUnlocked: Bool = false
    @Default(.timesLooped) var timesLooped
    @State private var nextUnlockCount: Int = -1
    @State private var loopsLeft: Int = -1

    var body: some View {
        ZStack {
            if hasBeenUnlocked {
                unlockedIconView
            } else {
                lockedIconView
            }
        }
        .onAppear {
            hasBeenUnlocked = icon.isSelectable

            if !hasBeenUnlocked {
                nextUnlockCount = model.nextIconUnlockLoopCount(timesLooped: timesLooped)
                loopsLeft = nextUnlockCount - timesLooped
            }
        }
        .onChange(of: timesLooped) { _ in
            withAnimation(luminareAnimation) {
                hasBeenUnlocked = icon.isSelectable

                if !hasBeenUnlocked {
                    nextUnlockCount = model.nextIconUnlockLoopCount(timesLooped: timesLooped)
                    loopsLeft = nextUnlockCount - timesLooped
                }
            }
        }
    }

    private var unlockedIconView: some View {
        Image(nsImage: NSImage(named: icon.assetName)!)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .padding(10)
            .transition(.scale(scale: 0.8).combined(with: .opacity))
    }

    private var lockedIconView: some View {
        VStack(alignment: .center) {
            Spacer()

            Image(systemName: "lock")
                .foregroundStyle(.secondary)

            Text(
                nextUnlockCount == icon.unlockTime ?
                    .init(localized: "Loops left to unlock new icon", defaultValue: "\(loopsLeft) Loops left") :
                    .init(localized: "App icon is locked", defaultValue: "Locked")
            )
            .font(.caption)
            .foregroundColor(.secondary)
            .contentTransition(.numericText())
            .multilineTextAlignment(.center)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(.rect)
        .onTapGesture {
            model.selectedLockedMessage = model.getNextUpToDateText()
            model.showingLockedAlert = true
        }
    }
}
