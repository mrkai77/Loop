//
//  SettingsContentView.swift
//  Loop
//
//  Created by Kai Azim on 2025-10-18.
//

import Defaults
import Luminare
import SwiftUI

struct SettingsContentView: View {
    @ObservedObject var model: SettingsWindowManager
    @ObservedObject private var accentColorController: AccentColorController = .shared

    @Environment(\.luminareAnimation) private var animation
    @Environment(\.luminareTitleBarHeight) private var titleBarHeight
    @Default(.enableRadialMenuCustomization) var enableRadialMenuCustomization
    @Default(.radialMenuVisibility) var radialMenuVisibility
    @Default(.previewVisibility) var previewVisibility
    @Default(.windowSnapping) var windowSnapping

    private var showRadialMenu: Bool {
        model.showRadialMenu && radialMenuVisibility
    }

    /// Window snapping always uses the preview, so it's only unused when both are off
    private var showPreview: Bool {
        model.showPreview && (previewVisibility || windowSnapping)
    }

    private var showRadialMenuGuide: Bool {
        enableRadialMenuCustomization && model.showRadialMenu && model.currentTab == .radialMenu
    }

    var body: some View {
        LuminareDividedStack {
            LuminareSidebar {
                LuminareSidebarSection("Theming", selection: $model.currentTab, items: SettingsTab.themingTabs)
                LuminareSidebarSection("Settings", selection: $model.currentTab, items: SettingsTab.settingsTabs)
                LuminareSidebarSection("\(Bundle.main.appName)", selection: $model.currentTab, items: SettingsTab.loopTabs)
            }
            .frame(width: 230)
            .padding(.top, titleBarHeight)
            .luminareBackground()

            LuminarePane {
                model.currentTab.view()
            } header: {
                HStack {
                    model.currentTab.icon

                    Text(model.currentTab.title)
                        .font(.title2)

                    Spacer()

                    if #available(macOS 26.0, *) {
                        // mimics the toolbar buttons on macOS 26+.
                        // ideally this would use a native NSToolbar, but there doesn't seem to be a clean
                        // way to position a button beside the detail/inspector separator :/
                        Button {
                            model.showInspector.toggle()
                        } label: {
                            Image(systemName: "sidebar.right")
                                .font(.title3)
                                .foregroundStyle(Color.primary) // HierarchicalShapeStyle.primary incorrectly resolves to white in light mode, so we use Color.primary
                                .animation(animation, value: model.showInspector)
                                .frame(width: 28, height: 28)
                        }
                        .buttonBorderShape(.circle)
                        .buttonStyle(.glass(.regular.interactive()))
                        .tint(.clear)
                    } else {
                        Button {
                            model.showInspector.toggle()
                        } label: {
                            Image(systemName: "sidebar.right")
                                .animation(animation, value: model.showInspector)
                        }
                        .luminareContentSize(aspectRatio: 1, contentMode: .fit, hasFixedHeight: true)
                    }
                }
            }
            .frame(width: 390)

            if model.showInspector {
                // We use an overlay instead of a ZStack so the inspector’s contents
                // don’t influence the layout of the surrounding views (mainly as a precaution)
                Color.clear.overlay {
                    if showPreview || showRadialMenuGuide {
                        PreviewView(viewModel: model.previewViewModel)
                            .onGeometryChange(for: CGSize.self, of: \.size) {
                                model.setPreviewBounds(CGRect(origin: .zero, size: $0))
                            }
                    }

                    if showRadialMenu {
                        RadialMenuView(viewModel: model.radialMenuViewModel)
                            .allowsHitTesting(false)
                    }

                    if showRadialMenuGuide {
                        RadialMenuActionsGuide()
                    }
                }
                .animation(animation, value: [showRadialMenu, showPreview])
                .padding(12)
                .frame(width: 520)
            }
        }
        .luminareTint(overridingWith: accentColorController.color1)
        .ignoresSafeArea()
        .environmentObject(model)
    }
}
