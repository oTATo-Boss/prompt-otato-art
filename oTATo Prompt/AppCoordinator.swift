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
    let updater = UpdaterService()

    @Published var openPromptID: UUID?
    @Published var selectedPromptID: UUID?
    @Published var createRequest = 0
    @Published var searchRequest = 0
    @Published var collectionRequest: LibraryShortcut?
    @Published var toastText: String?
    @Published var hotkeyStatus = "尚未注册"
    @Published var hotkeyIsRegistered = false
    @Published var menuBarEnabled: Bool {
        didSet { UserDefaults.standard.set(menuBarEnabled, forKey: "menuBarEnabled") }
    }
    @Published var menuCopyCompleted = 0
    @Published private(set) var trashRevision = 0
    private(set) var lastTrashedPromptID: UUID?
    @Published private(set) var libraryRevision = 0

    var openWindowAction: (() -> Void)?
    /// Installed while an editor is visible so app-level commands use the latest draft.
    private var flushEditor: (() -> Bool)?
    private var flushEditorOwner: UUID?
    private var toastTask: Task<Void, Never>?
    private var globalSearchController: GlobalSearchController?
    private var hotkeyManager: GlobalHotKeyManager?
    private var started = false

    init(container: ModelContainer) {
        self.container = container
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "menuBarEnabled") == nil {
            defaults.set(true, forKey: "menuBarEnabled")
        }
        self.menuBarEnabled = defaults.bool(forKey: "menuBarEnabled")
        super.init()
    }

    func start() {
        guard !started else { return }
        started = true
        globalSearchController = GlobalSearchController(app: self)
        hotkeyManager = GlobalHotKeyManager { [weak self] in
            self?.globalSearchController?.toggle()
        }
        reloadGlobalHotkey()
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

    func installEditorFlush(owner: UUID, action: @escaping () -> Bool) {
        flushEditorOwner = owner
        flushEditor = action
    }

    func clearEditorFlush(owner: UUID) {
        guard flushEditorOwner == owner else { return }
        flushEditorOwner = nil
        flushEditor = nil
    }

    func requestCopy(_ prompt: Prompt, source: CopySource = .mainWindow) {
        do { try finishCopy(prompt, source: source) }
        catch { showToast(error.localizedDescription) }
    }

    func requestCopySelected() {
        guard flushEditor?() ?? true else { return }
        guard let prompt = selectedPrompt() else { return }
        requestCopy(prompt)
    }

    func toggleFavoriteSelected() {
        guard flushEditor?() ?? true else { return }
        guard let prompt = selectedPrompt() else { return }
        do { try PromptLibrary.setFavorite(!prompt.isFavorite, for: prompt, in: container.mainContext) }
        catch { showToast(error.localizedDescription) }
    }

    func trashSelected() {
        guard flushEditor?() ?? true else { return }
        guard let prompt = selectedPrompt() else { return }
        do {
            try PromptLibrary.trash(prompt, in: container.mainContext)
            selectedPromptID = nil
            flushEditor = nil
            flushEditorOwner = nil
            lastTrashedPromptID = prompt.id
            trashRevision += 1
        } catch { showToast(error.localizedDescription) }
    }

    /// Save the current draft before replacing the store. Incrementing the revision
    /// prevents a disappearing editor from writing its old draft into restored data.
    func prepareForLibraryRestore() -> Bool {
        guard flushEditor?() ?? true else { return false }
        globalSearchController?.dismiss(restoreFocus: false)
        libraryRevision += 1
        selectedPromptID = nil
        openPromptID = nil
        flushEditor = nil
        flushEditorOwner = nil
        return true
    }

    private func selectedPrompt() -> Prompt? {
        guard let id = selectedPromptID,
              let prompts = try? container.mainContext.fetch(FetchDescriptor<Prompt>()) else { return nil }
        return prompts.first { $0.id == id && $0.deletedAt == nil }
    }

    private func finishCopy(_ prompt: Prompt, source: CopySource) throws {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(prompt.content, forType: .string) else {
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
