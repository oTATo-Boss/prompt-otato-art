import AppKit
import Combine
import SwiftData

enum CopySource {
    case mainWindow
    case menuBar
    case globalSearch
}

enum LibraryShortcut: Equatable {
    case recentUse
    case favorites
}

enum CopyError: LocalizedError {
    case pasteboardUnavailable

    var errorDescription: String? { "无法写入剪贴板，请重试。" }
}

@MainActor
final class AppCoordinator: NSObject, ObservableObject {
    let container: ModelContainer
    let startup = AppStartupState()
    let updater = UpdaterService()
    private let isPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"

    @Published var openPromptID: UUID?
    @Published var selectedPromptID: UUID?
    var selectedPromptIDs: Set<UUID> = []
    @Published var createRequest = 0
    @Published var searchRequest = 0
    @Published var collectionRequest: LibraryShortcut?
    @Published var toastText: String?
    @Published var hotkeyStatus = "尚未注册"
    @Published var hotkeyIsRegistered = false
    @Published var menuBarEnabled: Bool {
        didSet {
            if !isPreview { UserDefaults.standard.set(menuBarEnabled, forKey: "menuBarEnabled") }
        }
    }
    @Published var menuCopyCompleted = 0
    @Published private(set) var trashRevision = 0
    private(set) var lastTrashedPromptID: UUID?
    @Published private(set) var libraryRevision = 0

    var openWindowAction: (() -> Void)?
    /// Installed while an editor is visible so app-level commands use the latest draft.
    private var editorCopy: (() -> Void)?
    private var editorToggleFavorite: (() -> Void)?
    private var editorOwner: UUID?
    private var toastTask: Task<Void, Never>?
    private var globalSearchController: GlobalSearchController?
    private var hotkeyManager: GlobalHotKeyManager?
    private var started = false
    private var mainWindow: NSWindow?
    private var mainWindowDelegate: MainWindowRetentionDelegate?

    init(container: ModelContainer) {
        self.container = container
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            self.menuBarEnabled = false
        } else {
            let defaults = UserDefaults.standard
            if defaults.object(forKey: "menuBarEnabled") == nil {
                defaults.set(true, forKey: "menuBarEnabled")
            }
            self.menuBarEnabled = defaults.bool(forKey: "menuBarEnabled")
        }
        super.init()
    }

    func start() {
        guard !isPreview, !started else { return }
        started = true
        globalSearchController = GlobalSearchController(app: self)
        hotkeyManager = GlobalHotKeyManager { [weak self] in
            self?.globalSearchController?.toggle()
        }
        reloadGlobalHotkey()
    }

    func retainMainWindow(_ window: NSWindow) {
        guard mainWindow !== window else { return }
        mainWindow = window
        let delegate = MainWindowRetentionDelegate(forwarding: window.delegate)
        mainWindowDelegate = delegate
        window.delegate = delegate
        window.isReleasedWhenClosed = false
    }

    @discardableResult
    func reopenMainWindow() -> Bool {
        guard let mainWindow else { return false }
        if mainWindow.isMiniaturized { mainWindow.deminiaturize(nil) }
        mainWindow.makeKeyAndOrderFront(nil)
        return true
    }

    func reloadGlobalHotkey() {
        let keyCode = UInt32(UserDefaults.standard.object(forKey: "globalHotkeyKeyCode") as? Int ?? 49)
        let modifiers = UInt32(UserDefaults.standard.object(forKey: "globalHotkeyModifiers") as? Int ?? 0x0800)
        let result = hotkeyManager?.register(keyCode: keyCode, modifiers: modifiers) ?? false
        hotkeyIsRegistered = result
        hotkeyStatus = result ? "全局快捷键已启用" : "快捷键被系统或其他应用占用，请重新录入"
    }

    func setGlobalHotkey(keyCode: UInt16, modifiers: UInt32) {
        UserDefaults.standard.set(Int(keyCode), forKey: "globalHotkeyKeyCode")
        UserDefaults.standard.set(Int(modifiers), forKey: "globalHotkeyModifiers")
        reloadGlobalHotkey()
    }

    func requestOpen(_ id: UUID) {
        openPromptID = id
        openWindowAction?()
        NSApp.activate(ignoringOtherApps: true)
    }

    func requestNewPrompt() {
        createRequest += 1
        openWindowAction?()
        NSApp.activate(ignoringOtherApps: true)
    }

    func requestSearch() {
        searchRequest += 1
        openWindowAction?()
        NSApp.activate(ignoringOtherApps: true)
    }

    func requestCollection(_ target: LibraryShortcut) {
        collectionRequest = target
        openWindowAction?()
        NSApp.activate(ignoringOtherApps: true)
    }

    func toggleGlobalSearch() {
        globalSearchController?.toggle()
    }

    func installEditorActions(owner: UUID, copy: @escaping () -> Void,
                              toggleFavorite: @escaping () -> Void) {
        editorOwner = owner
        editorCopy = copy
        editorToggleFavorite = toggleFavorite
    }

    func clearEditorActions(owner: UUID) {
        guard editorOwner == owner else { return }
        editorOwner = nil
        editorCopy = nil
        editorToggleFavorite = nil
    }

    func requestCopy(_ prompt: Prompt, source: CopySource = .mainWindow, content: String? = nil) {
        do { try finishCopy(prompt, source: source, content: content) }
        catch { showToast(error.localizedDescription) }
    }

    func requestCopySelected() {
        if let editorCopy { editorCopy(); return }
        guard selectedPromptIDs.count <= 1 else { showToast("请选择单条提示词复制"); return }
        guard let prompt = selectedPrompt() else { return }
        requestCopy(prompt)
    }

    func toggleFavoriteSelected() {
        if let editorToggleFavorite { editorToggleFavorite(); return }
        if selectedPromptIDs.count > 1 {
            let targets = selectedPrompts()
            do { try PromptLibrary.apply(.favorite(!targets.allSatisfy(\.isFavorite)), to: targets, in: container.mainContext) }
            catch { showToast(error.localizedDescription) }
            return
        }
        guard let prompt = selectedPrompt() else { return }
        do { try PromptLibrary.setFavorite(!prompt.isFavorite, for: prompt, in: container.mainContext) }
        catch { showToast(error.localizedDescription) }
    }

    func trashSelected() {
        if editorOwner == nil && selectedPromptIDs.count > 1 {
            do {
                let targets = selectedPrompts()
                try PromptLibrary.apply(.trash, to: targets, in: container.mainContext)
                lastTrashedPromptID = targets.first?.id
                selectedPromptIDs.removeAll()
                selectedPromptID = nil
                trashRevision += 1
            } catch { showToast(error.localizedDescription) }
            return
        }
        guard let prompt = selectedPrompt() else { return }
        do {
            try PromptLibrary.trash(prompt, in: container.mainContext)
            selectedPromptID = nil
            editorCopy = nil
            editorToggleFavorite = nil
            editorOwner = nil
            lastTrashedPromptID = prompt.id
            trashRevision += 1
        } catch { showToast(error.localizedDescription) }
    }

    /// Replacing the store discards the current unsaved editing session.
    func prepareForLibraryRestore() -> Bool {
        startup.cancelBackgroundPreparation()
        globalSearchController?.dismiss(restoreFocus: false)
        libraryRevision += 1
        selectedPromptID = nil
        selectedPromptIDs.removeAll()
        openPromptID = nil
        editorCopy = nil
        editorToggleFavorite = nil
        editorOwner = nil
        return true
    }

    private func selectedPrompt() -> Prompt? {
        guard let id = selectedPromptID,
              let prompts = try? container.mainContext.fetch(FetchDescriptor<Prompt>()) else { return nil }
        return prompts.first { $0.id == id && $0.deletedAt == nil }
    }

    private func selectedPrompts() -> [Prompt] {
        let prompts = (try? container.mainContext.fetch(FetchDescriptor<Prompt>())) ?? []
        return prompts.filter { selectedPromptIDs.contains($0.id) && $0.deletedAt == nil }
    }

    private func finishCopy(_ prompt: Prompt, source: CopySource, content: String?) throws {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(content ?? prompt.content, forType: .string) else {
            throw CopyError.pasteboardUnavailable
        }
        do {
            try PromptLibrary.markCopied(prompt, in: container.mainContext)
            showToast("已复制")
        } catch {
            container.mainContext.rollback()
            showToast("已复制，但最近使用记录未更新")
        }
        if source == .globalSearch {
            globalSearchController?.dismiss(restoreFocus: true)
        } else if source == .menuBar {
            menuCopyCompleted += 1
        }
    }

    func showToast(_ message: String) {
        toastTask?.cancel()
        toastText = message
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            self?.toastText = nil
        }
    }
}
