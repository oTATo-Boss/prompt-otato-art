//
//  oTATo_PromptApp.swift
//  oTATo Prompt
//
//  Created by Griffith on 2026/9/28.
//

import AppKit
import Combine
import SwiftData
import SwiftUI

@main
struct oTATo_PromptApp: App {
    @NSApplicationDelegateAdaptor(AppLifetimeDelegate.self) private var lifetime
    private let app: AppCoordinator
    private let launchError: String?

    init() {
        do {
            let isPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
            let container = try PromptPersistence.makeContainer(inMemory: isPreview)
            app = AppCoordinator(container: container)
            launchError = nil
        } catch {
            let fallback = try! PromptPersistence.makeContainer(inMemory: true)
            let failedApp = AppCoordinator(container: fallback)
            failedApp.menuBarEnabled = false
            app = failedApp
            launchError = error.localizedDescription
        }
    }

    var body: some Scene {
        WindowGroup("oTATo prompt", id: "main") {
            if launchError == nil {
                RootWindowView(app: app, lifetime: lifetime)
                    .modelContainer(app.container)
            } else {
                StoreFailureView(message: launchError ?? "无法打开本地资料库。")
            }
        }
        .defaultSize(width: 1280, height: 820)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新建 Prompt") { app.requestNewPrompt() }
                    .keyboardShortcut("n", modifiers: .command)
            }
            CommandMenu("Prompt") {
                Button("搜索提示词") { app.requestSearch() }
                    .keyboardShortcut("f", modifiers: .command)
                Button("快速搜索浮层") { app.toggleGlobalSearch() }
                Button("复制当前 Prompt") { app.requestCopySelected() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                Button("收藏或取消收藏") { app.toggleFavoriteSelected() }
                    .keyboardShortcut("d", modifiers: .command)
                Button("移到废纸篓") { app.trashSelected() }
                    .keyboardShortcut(.delete, modifiers: .command)
            }
        }

        MenuBarExtra("oTATo prompt", image: "MenuBarIcon", isInserted: Binding(
            get: { app.menuBarEnabled },
            set: { app.menuBarEnabled = $0 }
        )) {
            MenuBarView()
                .environmentObject(app)
                .modelContainer(app.container)
                .modifier(AppAppearanceModifier())
                .applyAppAccent()
        }
        .menuBarExtraStyle(.window)

        Settings {
            AppSettingsView()
                .environmentObject(app)
                .modelContainer(app.container)
                .modifier(AppAppearanceModifier())
                .applyAppAccent()
        }
    }
}

private struct RootWindowView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var app: AppCoordinator
    @ObservedObject private var startup: AppStartupState
    let lifetime: AppLifetimeDelegate

    init(app: AppCoordinator, lifetime: AppLifetimeDelegate) {
        self.app = app
        startup = app.startup
        self.lifetime = lifetime
    }

    var body: some View {
        ZStack {
            ContentView()
                .disabled(!startup.isReady)
                .accessibilityHidden(!startup.isReady)
            if !startup.isReady {
                StartupLoadingView(startup: startup) { startup.prepare(in: app.container) }
            }
        }
            .environmentObject(app)
            .frame(minWidth: 900, minHeight: 620)
            .modifier(AppAppearanceModifier())
            .applyAppAccent()
            .background(StartupWindowAttachment(app: app))
            .toolbar(startup.isReady ? .visible : .hidden, for: .windowToolbar)
            .onAppear {
                lifetime.coordinator = app
                app.openWindowAction = {
                    if !app.reopenMainWindow() { openWindow(id: "main") }
                }
                app.start()
                startup.prepare(in: app.container)
            }
    }
}

private struct AppAppearanceModifier: ViewModifier {
    @AppStorage("appearanceMode") private var appearanceMode = "system"
    @State private var systemColorScheme = currentSystemColorScheme()

    private var colorScheme: ColorScheme {
        switch appearanceMode {
        case "light": .light
        case "dark": .dark
        default: systemColorScheme
        }
    }

    func body(content: Content) -> some View {
        content
            .preferredColorScheme(colorScheme)
            .onAppear { systemColorScheme = Self.currentSystemColorScheme() }
            .onReceive(DistributedNotificationCenter.default()
                .publisher(for: Notification.Name("AppleInterfaceThemeChangedNotification"))
                .receive(on: RunLoop.main)) { _ in
                    systemColorScheme = Self.currentSystemColorScheme()
                }
    }

    private static func currentSystemColorScheme() -> ColorScheme {
        NSApplication.shared.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? .dark : .light
    }
}

private struct StoreFailureView: View {
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label("无法打开资料库", systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            Text(message)
        }
        .frame(minWidth: 600, minHeight: 400)
    }
}
