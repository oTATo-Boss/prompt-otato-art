import AppKit
import Combine
import ServiceManagement
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct AppSettingsView: View {
    let titlebarInset: CGFloat
    @EnvironmentObject private var app: AppCoordinator
    @Environment(\.modelContext) private var modelContext
    @Query private var prompts: [Prompt]
    @Query private var folders: [Folder]
    @Query private var tags: [Tag]

    @AppStorage("appearanceMode") private var appearanceMode = "system"
    @AppStorage("accentPalette") private var accentPalette = AppAccentPalette.monochrome.rawValue
    @AppStorage("cardSize") private var cardSize = "standard"
    @AppStorage("editorFontSize") private var editorFontSize = 16.0
    @AppStorage("editorWrapLines") private var editorWrapLines = true
    @AppStorage("globalHotkeyDisplay") private var hotkeyDisplay = "⌥ Space"
    @AppStorage("globalSearchDefaultCollection") private var globalSearchDefaultCollection = GlobalSearchDefaultCollection.favorites.rawValue

    @StateObject private var hotkeyRecorder = HotkeyRecorder()
    @State private var launchAtLogin = false
    @State private var loginFeedback: String?
    @State private var dataFeedback: String?
    @State private var errorMessage: String?
    @State private var pendingRestoreURL: URL?
    @State private var pendingRestoreSummary: ArchiveSummary?
    @State private var showRestoreConfirmation = false

    init(titlebarInset: CGFloat = 24) {
        self.titlebarInset = titlebarInset
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("设置")
                            .font(.system(size: 25, weight: .semibold))
                        Text("个性化设置，让创作更高效")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 4)
                    .padding(.leading, max(0, titlebarInset - 24))

                    LazyVGrid(columns: gridColumns(for: geometry.size.width),
                              alignment: .leading, spacing: 14) {
                        generalCard
                        shortcutCard
                        appearanceCard
                        editorCard
                        dataCard
                        aboutCard
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 26)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollIndicators(.automatic)
        }
        .frame(minWidth: 650, minHeight: 580)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { launchAtLogin = SMAppService.mainApp.status == .enabled }
        .onDisappear { hotkeyRecorder.stop() }
        .alert("替换当前资料库？", isPresented: $showRestoreConfirmation) {
            Button("替换并恢复", role: .destructive) { restoreConfirmedArchive() }
            Button("取消", role: .cancel) {
                pendingRestoreURL = nil
                pendingRestoreSummary = nil
            }
        } message: {
            Text(restoreConfirmationMessage)
        }
        .alert("操作失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "未知错误")
        }
    }

    private func gridColumns(for width: CGFloat) -> [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 14, alignment: .top),
              count: width >= 850 ? 2 : 1)
    }

    private func settingsCard<Content: View>(
        _ title: String, minHeight: CGFloat, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 10)
            Divider()
            content()
        }
        .padding(.horizontal, 18)
        .padding(.top, 15)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 13))
        .overlay {
            RoundedRectangle(cornerRadius: 13)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.42), lineWidth: 0.5)
        }
    }

    private func settingsRow<Accessory: View>(
        _ title: String, symbol: String, subtitle: String,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(spacing: 11) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .regular))
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            accessory()
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private var generalCard: some View {
        settingsCard("通用", minHeight: 206) {
            settingsRow("开机启动", symbol: "power",
                        subtitle: "登录后自动打开 oTATo prompt") {
                Toggle("开机启动", isOn: Binding(
                    get: { launchAtLogin },
                    set: { setLaunchAtLogin($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }
            Divider().padding(.leading, 35)
            settingsRow("菜单栏显示", symbol: "menubar.rectangle",
                        subtitle: "在菜单栏中显示应用图标") {
                Toggle("菜单栏显示", isOn: $app.menuBarEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .help("关闭后不在菜单栏驻留")
            }
            Divider().padding(.leading, 35)
            settingsRow("自动保存", symbol: "square.and.arrow.down",
                        subtitle: "编辑内容时自动保存") {
                Label("始终开启", systemImage: "checkmark.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            if let loginFeedback {
                Text(loginFeedback)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.top, 5)
            }
        }
    }

    private var shortcutCard: some View {
        settingsCard("快捷键", minHeight: 250) {
            settingsRow("全局搜索", symbol: "magnifyingglass",
                        subtitle: "在任意应用中唤起搜索") {
                Button(hotkeyRecorder.isRecording ? "请按快捷键…" : hotkeyDisplay) {
                    hotkeyRecorder.begin { keyCode, modifiers, label in
                        hotkeyDisplay = label
                        app.setGlobalHotkey(keyCode: keyCode, modifiers: modifiers)
                    }
                }
                .font(.system(size: 11, design: .monospaced))
                .buttonStyle(.bordered)
                .disabled(hotkeyRecorder.isRecording)
                .accessibilityLabel("重新录入全局搜索快捷键，当前为 \(hotkeyDisplay)")
                .help("录入时按 Esc 取消；请包含 Command、Option 或 Control。")
            }
            Divider().padding(.leading, 35)
            settingsRow("浮层默认内容", symbol: "rectangle.on.rectangle",
                        subtitle: "未输入关键词时显示") {
                Picker("浮层默认内容", selection: $globalSearchDefaultCollection) {
                    Text("收藏").tag(GlobalSearchDefaultCollection.favorites.rawValue)
                    Text("最近使用").tag(GlobalSearchDefaultCollection.recentlyUsed.rawValue)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 155)
            }
            Divider().padding(.leading, 35)
            settingsRow("复制 Prompt", symbol: "doc.on.doc",
                        subtitle: "快速复制选中的提示词") {
                shortcutBadge("⌘ ⇧ C")
            }
            Divider().padding(.leading, 35)
            settingsRow("新建 Prompt", symbol: "plus",
                        subtitle: "快速创建新的提示词") {
                shortcutBadge("⌘ N")
            }
            HStack(spacing: 8) {
                Text("⌘ F 搜索")
                Text("·")
                Text("⌘ D 收藏")
                Spacer()
                Text(app.hotkeyStatus)
                    .foregroundStyle(app.hotkeyIsRegistered ? Color.secondary : Color.orange)
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.leading, 35)
            .padding(.top, 4)
            if let recorderMessage = hotkeyRecorder.message {
                Text(recorderMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.top, 4)
            }
        }
    }

    private func shortcutBadge(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 11, design: .monospaced))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color(nsColor: .windowBackgroundColor),
                        in: RoundedRectangle(cornerRadius: 6))
    }

    private var appearanceCard: some View {
        settingsCard("外观", minHeight: 233) {
            settingsRow("主题模式", symbol: "sun.max",
                        subtitle: "跟随系统设置或手动选择主题") {
                Picker("主题模式", selection: $appearanceMode) {
                    Text("跟随系统").tag("system")
                    Text("浅色").tag("light")
                    Text("深色").tag("dark")
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 208)
            }
            Divider().padding(.leading, 35)
            settingsRow("高亮配色", symbol: "paintpalette",
                        subtitle: "选中项、按钮和焦点颜色") {
                Picker("高亮配色", selection: $accentPalette) {
                    Text("黑白反色").tag(AppAccentPalette.monochrome.rawValue)
                    Text("备忘录黄").tag(AppAccentPalette.notes.rawValue)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 208)
            }
            Divider().padding(.leading, 35)
            settingsRow("卡片大小", symbol: "rectangle",
                        subtitle: "调整提示词卡片的显示密度") {
                Picker("卡片尺寸", selection: $cardSize) {
                    Text("紧凑").tag("compact")
                    Text("标准").tag("standard")
                    Text("宽松").tag("roomy")
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 208)
            }
        }
    }

    private var editorCard: some View {
        settingsCard("编辑器", minHeight: 150) {
            settingsRow("字体大小", symbol: "textformat.size",
                        subtitle: "编辑器内的字体大小") {
                HStack(spacing: 7) {
                    Slider(value: $editorFontSize, in: 11...24, step: 1)
                        .frame(width: 125)
                        .accessibilityLabel("编辑器字体大小")
                    Text("\(Int(editorFontSize))")
                        .monospacedDigit()
                        .frame(width: 20, alignment: .trailing)
                }
                .font(.system(size: 11))
            }
            Divider().padding(.leading, 35)
            settingsRow("自动换行", symbol: "text.word.spacing",
                        subtitle: "编辑器中默认开启自动换行") {
                Toggle("自动换行", isOn: $editorWrapLines)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        }
    }

    private var dataCard: some View {
        settingsCard("数据与同步", minHeight: 234) {
            settingsRow("本地存储位置", symbol: "folder",
                        subtitle: PromptStorage.applicationSupportURL.path) {
                Button("打开") {
                    NSWorkspace.shared.activateFileViewerSelecting(
                        [PromptStorage.applicationSupportURL])
                }
                .buttonStyle(.bordered)
            }
            Divider().padding(.leading, 35)
            settingsRow("导入 .md / .txt", symbol: "square.and.arrow.down",
                        subtitle: "从本地文件导入提示词") {
                Button("导入", action: importTextFiles)
                    .buttonStyle(.bordered)
            }
            Divider().padding(.leading, 35)
            settingsRow("导出全部", symbol: "square.and.arrow.up",
                        subtitle: "按文件夹结构导出 Markdown 文件") {
                Button("导出", action: exportAllTextFiles)
                    .buttonStyle(.bordered)
            }
            Divider().padding(.leading, 35)
            settingsRow("完整资料库", symbol: "externaldrive",
                        subtitle: "保留标签、封面及文件夹结构") {
                Menu("备份与恢复") {
                    Button("创建备份…", action: createBackup)
                    Button("从备份恢复…", action: chooseArchiveToRestore)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 106)
            }
            if let dataFeedback {
                Label(dataFeedback, systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 5)
            }
        }
    }

    private var aboutCard: some View {
        settingsCard("关于", minHeight: 234) {
            HStack(spacing: 12) {
                Image("BrandMark")
                    .resizable()
                    .renderingMode(.template)
                    .frame(width: 42, height: 42)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("oTATo prompt")
                        .font(.system(size: 15, weight: .semibold))
                    Text("让好的提示词，激发更大的想象力。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .frame(minHeight: 58)
            Divider()
            settingsRow("版本", symbol: "info.circle",
                        subtitle: "当前安装的应用版本") {
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Divider().padding(.leading, 35)
            settingsRow("更新", symbol: "arrow.triangle.2.circlepath",
                        subtitle: app.updater.canCheckForUpdates
                        ? "从 oTATo 更新源检查版本" : "正式发布版启用") {
                Button("检查更新") { app.updater.checkForUpdates() }
                    .buttonStyle(.bordered)
                    .disabled(!app.updater.canCheckForUpdates)
            }
        }
    }

    private var restoreConfirmationMessage: String {
        guard let summary = pendingRestoreSummary else { return "当前资料库将被替换。" }
        return "备份包含 \(summary.promptCount) 条 Prompt、\(summary.folderCount) 个文件夹、\(summary.tagCount) 个标签和 \(summary.coverCount) 张封面。当前资料库会先自动备份，然后替换。"
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            if enabled && !launchAtLogin {
                loginFeedback = "请在系统设置的登录项中允许 oTATo prompt。"
            } else {
                loginFeedback = nil
            }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            errorMessage = error.localizedDescription
        }
    }

    private func importTextFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText, .plainText]
        guard panel.runModal() == .OK else { return }
        do {
            let imported = try PromptTextTransfer.importFiles(panel.urls, into: modelContext)
            dataFeedback = "已导入 \(imported.count) 条 Prompt"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func exportAllTextFiles() {
        let panel = NSOpenPanel()
        panel.prompt = "导出到这里"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let exported = try PromptTextTransfer.writeCollection(
                prompts: prompts.filter { $0.deletedAt == nil },
                folders: folders.filter { $0.deletedAt == nil },
                to: url
            )
            dataFeedback = "已导出 \(exported.count) 条 Prompt"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func createBackup() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "oTATo-\(Date.now.formatted(.iso8601.year().month().day().dateSeparator(.dash))).otatoarchive"
        panel.allowedContentTypes = [UTType(filenameExtension: "otatoarchive") ?? .data]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try PromptArchiveService.createArchive(
                prompts: prompts, folders: folders, tags: tags, at: url
            )
            dataFeedback = "完整资料库备份已创建"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func chooseArchiveToRestore() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType(filenameExtension: "otatoarchive") ?? .data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            pendingRestoreSummary = try PromptArchiveService.inspectArchive(at: url)
            pendingRestoreURL = url
            showRestoreConfirmation = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func restoreConfirmedArchive() {
        guard let url = pendingRestoreURL else { return }
        defer {
            pendingRestoreURL = nil
            pendingRestoreSummary = nil
        }
        guard app.prepareForLibraryRestore() else {
            errorMessage = "请先修复当前 Prompt 的保存错误，再恢复备份。"
            return
        }
        do {
            let restored = try PromptArchiveService.restoreArchive(at: url, into: modelContext)
            dataFeedback = "已恢复 \(restored.promptCount) 条 Prompt；原资料库已自动备份"
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

@MainActor
private final class HotkeyRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var message: String?
    private var monitor: Any?

    func begin(onCapture: @escaping (UInt16, UInt32, String) -> Void) {
        stop()
        message = nil
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isRecording else { return event }
            if event.keyCode == 53 {
                self.stop()
                return nil
            }
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            var carbonFlags: UInt32 = 0
            if flags.contains(.command) { carbonFlags |= 0x0100 }
            if flags.contains(.shift) { carbonFlags |= 0x0200 }
            if flags.contains(.option) { carbonFlags |= 0x0800 }
            if flags.contains(.control) { carbonFlags |= 0x1000 }
            guard carbonFlags & (0x0100 | 0x0800 | 0x1000) != 0 else {
                self.message = "请包含 Command、Option 或 Control。"
                return nil
            }
            let label = Self.label(for: event, flags: flags)
            self.stop()
            onCapture(event.keyCode, carbonFlags, label)
            return nil
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
    }

    private static func label(for event: NSEvent, flags: NSEvent.ModifierFlags) -> String {
        var label = ""
        if flags.contains(.control) { label += "⌃" }
        if flags.contains(.option) { label += "⌥" }
        if flags.contains(.shift) { label += "⇧" }
        if flags.contains(.command) { label += "⌘" }
        let key: String
        switch event.keyCode {
        case 49: key = "Space"
        case 36: key = "Return"
        case 48: key = "Tab"
        case 51: key = "Delete"
        case 123: key = "←"
        case 124: key = "→"
        case 125: key = "↓"
        case 126: key = "↑"
        default:
            key = event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)"
        }
        return label + " " + key
    }
}
