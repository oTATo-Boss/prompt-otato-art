import AppKit
import Combine
import SwiftData
import SwiftUI

enum GlobalSearchDefaultCollection: String {
    case favorites
    case recentlyUsed

    static let preferenceKey = "globalSearchDefaultCollection"
}

@MainActor
final class GlobalSearchController: NSObject, NSWindowDelegate {
    private weak var app: AppCoordinator?
    private let state = GlobalSearchState()
    private var panel: GlobalSearchPanel?
    private var keyMonitor: Any?
    private var previousApplication: NSRunningApplication?
    private weak var previousKeyWindow: NSWindow?
    private var isDismissing = false

    init(app: AppCoordinator) {
        self.app = app
        super.init()
    }

    deinit {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    }

    func toggle() {
        if panel?.isVisible == true {
            dismiss(restoreFocus: true)
        } else {
            show()
        }
    }

    func dismiss(restoreFocus: Bool) {
        guard !isDismissing else { return }
        isDismissing = true
        state.cancelAll()
        panel?.orderOut(nil)
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        let applicationToRestore = previousApplication
        let windowToRestore = previousKeyWindow
        previousApplication = nil
        previousKeyWindow = nil
        if restoreFocus {
            self.restoreFocus(to: applicationToRestore, window: windowToRestore)
        }
        isDismissing = false
    }

    private func restoreFocus(to application: NSRunningApplication?, window: NSWindow?) {
        if let application,
           application.processIdentifier != NSRunningApplication.current.processIdentifier {
            application.activate(options: [])
        } else if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        guard panel?.isVisible == true, !isDismissing else { return }
        dismiss(restoreFocus: false)
    }

    private func show() {
        guard let app else { return }
        previousApplication = NSWorkspace.shared.frontmostApplication
        previousKeyWindow = NSApp.keyWindow
        do {
            try state.load(from: app.container.mainContext)
        } catch {
            state.showError(error.localizedDescription)
        }

        let panel = ensurePanel()
        switch UserDefaults.standard.string(forKey: "appearanceMode") {
        case "light": panel.appearance = NSAppearance(named: .aqua)
        case "dark": panel.appearance = NSAppearance(named: .darkAqua)
        default: panel.appearance = nil
        }
        position(panel)
        panel.makeKeyAndOrderFront(nil)
        state.requestFocus()
        if keyMonitor == nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.handleKey(event) else { return event }
                return nil
            }
        }
    }

    private func ensurePanel() -> GlobalSearchPanel {
        if let panel { return panel }
        let panel = GlobalSearchPanel(
            contentRect: NSRect(x: 0, y: 0, width: 640,
                                height: GlobalSearchView.preferredHeight(for: state.results.count)),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: GlobalSearchView(
            state: state,
            onCopy: { [weak self] prompt in self?.copy(prompt) },
            onOpen: { [weak self] prompt in self?.open(prompt) },
            onCancel: { [weak self] in self?.dismiss(restoreFocus: true) },
            onHeightChange: { [weak self] height in self?.resizePanel(to: height) }
        ).applyAppAccent())
        self.panel = panel
        return panel
    }

    private func position(_ panel: NSPanel) {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let screen else { panel.center(); return }
        let frame = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(
            x: frame.midX - panel.frame.width / 2,
            y: frame.midY - panel.frame.height / 2
        ))
    }

    private func resizePanel(to height: CGFloat) {
        guard let panel, abs(panel.frame.height - height) > 1 else { return }
        let top = panel.frame.maxY
        var frame = panel.frame
        frame.size.height = height
        frame.origin.y = top - height
        if let screen = panel.screen {
            frame.origin.y = min(max(frame.origin.y, screen.visibleFrame.minY + 16),
                                 screen.visibleFrame.maxY - height - 16)
        }
        panel.setFrame(frame, display: true, animate: false)
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard panel?.isKeyWindow == true else { return false }
        switch event.keyCode {
        case 125: // Down arrow
            state.moveSelection(by: 1)
            return true
        case 126: // Up arrow
            state.moveSelection(by: -1)
            return true
        case 36, 76: // Return and keypad Enter
            guard let prompt = state.selectedPrompt else { return true }
            if event.modifierFlags.contains(.command) {
                open(prompt)
            } else {
                copy(prompt)
            }
            return true
        case 53: // Escape
            dismiss(restoreFocus: true)
            return true
        default:
            return false
        }
    }

    private func copy(_ prompt: Prompt) {
        guard let app else { return }
        app.requestCopy(prompt, source: .globalSearch)
    }

    private func open(_ prompt: Prompt) {
        dismiss(restoreFocus: false)
        app?.requestOpen(prompt.id)
    }
}

private final class GlobalSearchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class GlobalSearchState: ObservableObject {
    @Published var query = "" {
        didSet { scheduleSearch() }
    }
    @Published private(set) var results: [Prompt] = []
    @Published private(set) var selectedIndex = 0
    @Published private(set) var errorMessage: String?
    @Published private(set) var focusRequest = 0

    private var prompts: [Prompt] = []
    private var folders: [Folder] = []
    private var searchTask: Task<Void, Never>?
    private var prepareTask: Task<Void, Never>?

    var selectedPrompt: Prompt? {
        guard results.indices.contains(selectedIndex) else { return nil }
        return results[selectedIndex]
    }

    func load(from context: ModelContext) throws {
        cancelAll()
        prompts = try context.fetch(FetchDescriptor<Prompt>())
        folders = try context.fetch(FetchDescriptor<Folder>())
        errorMessage = nil
        query = ""
        let prompts = self.prompts
        let folders = self.folders
        prepareTask = Task(priority: .utility) {
            await PromptSearch.prepareIndex(prompts, folders: folders)
        }
    }

    func showError(_ message: String) {
        prompts = []
        folders = []
        results = []
        errorMessage = message
    }

    func requestFocus() { focusRequest += 1 }

    func refreshResults() { searchNow() }

    func moveSelection(by offset: Int) {
        guard !results.isEmpty else { return }
        selectedIndex = (selectedIndex + offset + results.count) % results.count
    }

    func cancelSearch() {
        searchTask?.cancel()
        searchTask = nil
    }

    func cancelAll() {
        cancelSearch()
        prepareTask?.cancel()
        prepareTask = nil
    }

    private func scheduleSearch() {
        cancelSearch()
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            searchNow()
            return
        }
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            self?.searchNow()
        }
    }

    private func searchNow() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            let preference = GlobalSearchDefaultCollection(
                rawValue: UserDefaults.standard.string(forKey: GlobalSearchDefaultCollection.preferenceKey) ?? ""
            ) ?? .favorites
            let scope: PromptSearch.Scope = preference == .favorites ? .favorites : .recentlyUsed
            results = PromptSearch.search(prompts, query: "", scope: scope, folders: folders, limit: 8)
        } else {
            results = PromptSearch.search(prompts, query: trimmed, folders: folders, limit: 10)
        }
        selectedIndex = 0
    }
}

@MainActor
private struct GlobalSearchView: View {
    @Environment(\.appAccentStyle) private var accent
    @ObservedObject var state: GlobalSearchState
    let onCopy: (Prompt) -> Void
    let onOpen: (Prompt) -> Void
    let onCancel: () -> Void
    let onHeightChange: (CGFloat) -> Void

    @AppStorage("globalHotkeyDisplay") private var hotkeyDisplay = "⌥ Space"
    @AppStorage("globalSearchDefaultCollection") private var defaultCollection = GlobalSearchDefaultCollection.favorites.rawValue
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var searchFocused: Bool
    @State private var hoveredPromptID: UUID?

    private var emptyCollectionTitle: String {
        defaultCollection == GlobalSearchDefaultCollection.recentlyUsed.rawValue ? "最近" : "收藏"
    }

    static func preferredHeight(for resultCount: Int) -> CGFloat {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let available = (screen?.visibleFrame.height ?? 800) - 48
        return min(max(340, 224 + CGFloat(resultCount) * 82), min(740, available))
    }

    private var panelHeight: CGFloat { Self.preferredHeight(for: state.results.count) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image("BrandMark")
                    .resizable()
                    .renderingMode(.template)
                    .foregroundStyle(colorScheme == .dark ? Color.white : Color.primary)
                    .frame(width: 30, height: 30)
                    .accessibilityHidden(true)
                Text("oTATo prompt")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("快速搜索与复制")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 22)
            .frame(height: 57)

            HStack(spacing: 13) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 19, weight: .regular))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("搜索标题、标签或正文", text: $state.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 19))
                    .focused($searchFocused)
                    .accessibilityLabel("搜索提示词")
                if !state.query.isEmpty {
                    Button {
                        state.query = ""
                        searchFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("清除搜索")
                }
                Text(hotkeyDisplay)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 5))
                    .accessibilityLabel("全局快捷键：\(hotkeyDisplay)")
            }
            .padding(.horizontal, 15)
            .frame(height: 57)
            .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 11))
            .overlay {
                RoundedRectangle(cornerRadius: 11)
                    .strokeBorder(.primary.opacity(0.15), lineWidth: 1)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)

            HStack {
                Text(state.query.isEmpty ? emptyCollectionTitle : "搜索结果")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if !state.results.isEmpty {
                    Text("\(state.results.count) 条")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 23)
            .frame(height: 35)

            if let error = state.errorMessage {
                emptyState(icon: "exclamationmark.triangle", message: error)
            } else if state.results.isEmpty {
                emptyState(
                    icon: state.query.isEmpty
                        ? (emptyCollectionTitle == "收藏" ? "star" : "clock") : "magnifyingglass",
                    message: state.query.isEmpty
                        ? (emptyCollectionTitle == "收藏" ? "还没有收藏的提示词" : "还没有最近使用的提示词")
                        : "没有找到匹配的提示词"
                )
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 3) {
                            ForEach(Array(state.results.enumerated()), id: \.element.id) { index, prompt in
                                Button { onCopy(prompt) } label: {
                                    resultRow(prompt, selected: index == state.selectedIndex,
                                              hovered: hoveredPromptID == prompt.id)
                                }
                                .buttonStyle(.plain)
                                .onHover { hoveredPromptID = $0 ? prompt.id : nil }
                                .accessibilityLabel("复制 \(prompt.title)")
                                .accessibilityValue(index == state.selectedIndex ? "已选中" : "")
                                .id(index)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                    }
                    // LazyVStack can retain the old row views when the query replaces
                    // the result set with a different collection of SwiftData models.
                    .id(state.results.map(\.id))
                    .onChange(of: state.selectedIndex) { _, newValue in
                        withAnimation(.easeOut(duration: 0.12)) {
                            proxy.scrollTo(newValue, anchor: .center)
                        }
                    }
                }
            }

            Rectangle()
                .fill(.primary.opacity(0.10))
                .frame(height: 1)
                .padding(.horizontal, 20)
            HStack(spacing: 5) {
                keycap("↑")
                keycap("↓")
                Text("选择")
                Spacer().frame(width: 13)
                keycap("Enter")
                Text("复制")
                Spacer().frame(width: 13)
                keycap("⌘ Enter")
                Text("打开")
                Spacer()
                Button("关闭", action: onCancel)
                    .buttonStyle(.plain)
                    .accessibilityLabel("关闭全局搜索")
                keycap("Esc")
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 21)
            .frame(height: 48)
        }
        .frame(width: 640, height: panelHeight)
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(.regularMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(colorScheme == .dark
                              ? Color(red: 0.10, green: 0.10, blue: 0.10).opacity(0.70)
                              : Color.white.opacity(0.30))
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.primary.opacity(0.12)))
        .onAppear {
            onHeightChange(panelHeight)
            focusSearchField()
        }
        .onChange(of: state.results.count) { _, _ in onHeightChange(panelHeight) }
        .onChange(of: state.focusRequest) { _, _ in focusSearchField() }
        .onChange(of: defaultCollection) { _, _ in state.refreshResults() }
        .onExitCommand(perform: onCancel)
    }

    private func resultRow(_ prompt: Prompt, selected: Bool, hovered: Bool) -> some View {
        HStack(spacing: 14) {
            cover(for: prompt)
            VStack(alignment: .leading, spacing: 5) {
                Text(prompt.title.isEmpty ? "未命名 Prompt" : prompt.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if prompt.coverPath == nil {
                    Text(PromptPresentation.preview(prompt.content))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 5) {
                    ForEach(Array(prompt.tagNames.prefix(3)), id: \.self) { tag in
                        Text("#\(tag)")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(accent.controlFill, in: Capsule())
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "doc.on.doc")
                .font(.system(size: 17))
                .foregroundStyle(.primary)
                .frame(width: 29)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 12)
        .frame(height: 79)
        .background(selected ? accent.softSelection : hovered ? accent.hoverFill : Color.clear,
                    in: RoundedRectangle(cornerRadius: 11))
        .contentShape(RoundedRectangle(cornerRadius: 11))
    }

    @ViewBuilder
    private func cover(for prompt: Prompt) -> some View {
        CoverThumbnail(prompt: prompt, maxPixelSize: 192) {
            Image(systemName: "doc.text")
                .font(.system(size: 23, weight: .ultraLight))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 88, height: 49.5)
        .background(.primary.opacity(0.065))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private func keycap(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.primary.opacity(0.065), in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.primary.opacity(0.08)))
    }

    private func emptyState(icon: String, message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.title2).foregroundStyle(.secondary)
            Text(message).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func focusSearchField() {
        DispatchQueue.main.async { searchFocused = true }
    }
}
