import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

private enum LibraryCollection: Hashable {
    case all, favorites, recentUse, recentEdit, uncategorized, trash, folder(UUID)
    var name: String {
        switch self {
        case .all: "所有提示词"
        case .favorites: "收藏"
        case .recentUse: "最近使用"
        case .recentEdit: "最近编辑"
        case .uncategorized: "未分类"
        case .trash: "废纸篓"
        case .folder: "文件夹"
        }
    }
}

private struct SidebarFolderNode: View {
    let folder: Folder
    let folders: [Folder]
    let prompts: [Prompt]
    let selectedID: UUID?
    let depth: Int
    let onSelect: (Folder) -> Void
    let onNewChild: (Folder) -> Void
    let onRename: (Folder) -> Void
    let onExport: (Folder) -> Void
    let onDelete: (Folder) -> Void
    let onDropItems: ([NSItemProvider], UUID) -> Bool
    @State private var expanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            ForEach(folders.filter { $0.parentID == folder.id }
                .sorted { $0.sortIndex < $1.sortIndex }) { child in
                SidebarFolderNode(folder: child, folders: folders, prompts: prompts,
                                  selectedID: selectedID, depth: depth + 1,
                                  onSelect: onSelect, onNewChild: onNewChild,
                                  onRename: onRename, onExport: onExport, onDelete: onDelete,
                                  onDropItems: onDropItems)
            }
        } label: {
            Button { onSelect(folder) } label: {
                HStack(spacing: 9) {
                    Image(systemName: "folder").frame(width: 16)
                    Text(folder.name).lineLimit(1)
                    Spacer(minLength: 3)
                    Text(PromptLibrary.folderContents(of: folder.id, prompts: prompts,
                                                     folders: folders).count.formatted())
                        .font(.caption).foregroundStyle(.secondary)
                }
                .font(.system(size: 12.5))
                .padding(.horizontal, 9).frame(height: 28)
                .contentShape(Rectangle())
                .modifier(SubtleHoverSurface(selected: selectedID == folder.id))
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("新建子文件夹") { onNewChild(folder) }
                Button("重命名") { onRename(folder) }
                Button("导出集合…") { onExport(folder) }
                Button("删除文件夹", role: .destructive) { onDelete(folder) }
            }
            .onDrag { NSItemProvider(object: "folder:\(folder.id.uuidString)" as NSString) }
            .onDrop(of: [.plainText], isTargeted: nil) { onDropItems($0, folder.id) }
        }
        .padding(.leading, CGFloat(depth * 13 + 2))
    }
}

private struct SearchFocusBoundary: NSViewRepresentable {
    let isFocused: Bool
    let onOutsideClick: () -> Void

    func makeNSView(context: Context) -> SearchFocusBoundaryView {
        SearchFocusBoundaryView()
    }

    func updateNSView(_ view: SearchFocusBoundaryView, context: Context) {
        view.isFocused = isFocused
        view.onOutsideClick = onOutsideClick
    }
}

private final class SearchFocusBoundaryView: NSView {
    var isFocused = false
    var onOutsideClick: () -> Void = {}
    private var mouseMonitor: Any?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
        guard window != nil else { return }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, self.isFocused, event.window === self.window,
                  !self.bounds.contains(self.convert(event.locationInWindow, from: nil)) else { return event }
            // Release the field editor before the click reaches its new target.
            self.window?.makeFirstResponder(nil)
            self.onOutsideClick()
            return event
        }
    }

    deinit {
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
    }
}

/// Native collection hosts have a separate responder chain. Keep library keys
/// working after leaving the toolbar search field without intercepting text entry.
private struct LibraryKeyBoundary: NSViewRepresentable {
    let onKey: (NSEvent) -> Bool
    func makeNSView(context: Context) -> KeyView { KeyView() }
    func updateNSView(_ view: KeyView, context: Context) { view.onKey = onKey }

    final class KeyView: NSView {
        var onKey: (NSEvent) -> Bool = { _ in false }
        private var monitor: Any?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, event.window === self.window, self.window?.attachedSheet == nil,
                      !(self.window?.firstResponder is NSTextView),
                      !(self.window?.firstResponder is NSControl), self.onKey(event) else { return event }
                return nil
            }
        }
        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}

private struct SubtleHoverSurface: ViewModifier {
    @Environment(\.appAccentStyle) private var accent
    @State private var isHovering = false
    let selected: Bool
    var cornerRadius: CGFloat = 6

    func body(content: Content) -> some View {
        content
            .background(selected ? accent.softSelection
                        : isHovering ? accent.hoverFill : Color.clear,
                        in: RoundedRectangle(cornerRadius: cornerRadius))
            .onHover { isHovering = $0 }
    }
}

private struct LibrarySearchSurface: ViewModifier {
    @Environment(\.appAccentStyle) private var accent
    let isFocused: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular, in: Capsule())
                .overlay {
                    if isFocused {
                        Capsule().strokeBorder(accent.focusOutline, lineWidth: 0.75)
                    }
                }
        } else {
            content
                .background(accent.controlFill, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(isFocused ? accent.focusOutline
                        : Color(nsColor: .separatorColor), lineWidth: 0.75)
                }
        }
    }
}

private struct LibraryChip: View {
    @Environment(\.appAccentStyle) private var accent
    @State private var isHovering = false
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .foregroundStyle(selected ? accent.selectedForeground : Color.primary)
                .background(selected ? accent.selectedFill
                            : isHovering ? accent.hoverFill : accent.controlFill, in: Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityValue(selected ? "已选择" : "未选择")
    }
}

struct ContentView: View {
    @Environment(\.appAccentStyle) private var accent
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var app: AppCoordinator
    @Query private var prompts: [Prompt]
    @Query private var folders: [Folder]
    @Query private var tags: [Tag]
    @AppStorage("cardSize") private var cardSize = "standard"
    @AppStorage("library.viewMode") private var viewMode = "grid"
    @AppStorage("library.sort") private var sort: PromptLibrarySort = .updated

    @State private var collection: LibraryCollection = .all
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var libraryFilter = PromptLibraryFilter()
    @State private var showingFilterPanel = false
    @State private var selection = PromptSelection()
    @State private var showingBatchTags = false
    @State private var batchTagInput = ""

    private var selectedPromptID: UUID? {
        get { selection.focusedID }
        nonmutating set { selection.single(newValue) }
    }

    private var selectedPrompts: [Prompt] { shownPrompts.filter { selection.ids.contains($0.id) } }
    private var listPrompt: Prompt? {
        guard selection.ids.count == 1 else { return nil }
        return shownPrompts.first { $0.id == selectedPromptID && $0.deletedAt == nil }
    }
    @State private var editingID: UUID?
    @State private var creating = false
    @State private var searchText = ""
    @State private var settledSearch = ""
    @State private var searchMatches: [Prompt] = []
    @State private var searchScope: PromptSearch.Scope = .all
    @State private var searchTask: Task<Void, Never>?
    @State private var importing = false
    @State private var importDestinationFolderID: UUID?
    @State private var importingFiles = false
    @State private var fileDropTargeted = false
    @State private var newFolderName = ""
    @State private var newFolderParent: UUID?
    @State private var showNewFolder = false
    @State private var folderToRename: Folder?
    @State private var renameText = ""
    @State private var folderToDelete: Folder?
    @State private var folderToPurge: Folder?
    @State private var errorMessage: String?
    @State private var toast: String?
    @State private var libraryWidth: CGFloat = 900
    @State private var pendingSearchFocus = false
    @FocusState private var searchFocused: Bool
    @FocusState private var libraryFocused: Bool

    private var activePrompts: [Prompt] { prompts.filter { $0.deletedAt == nil } }
    private var activeFolders: [Folder] { folders.filter { $0.deletedAt == nil } }
    private var trashedFolderRoots: [Folder] {
        let byID = Dictionary(folders.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return folders.filter { folder in
            guard let deletedAt = folder.deletedAt else { return false }
            guard let parentID = folder.parentID, let parent = byID[parentID] else { return true }
            return parent.deletedAt != deletedAt
        }
        .sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
    }
    private var searching: Bool { !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var selectedFolder: Folder? {
        guard case .folder(let id) = collection else { return nil }
        return activeFolders.first { $0.id == id }
    }
    private var selectedFolderID: UUID? { selectedFolder?.id }

    private var basePrompts: [Prompt] {
        let base: [Prompt]
        if searching {
            base = settledSearch.isEmpty ? [] : searchMatches
        } else {
            switch collection {
            case .all, .recentEdit: base = activePrompts
            case .favorites: base = activePrompts.filter(\.isFavorite)
            case .recentUse: base = activePrompts.filter { $0.lastUsedAt != nil }
            case .uncategorized: base = activePrompts.filter { $0.folderID == nil }
            case .trash: base = prompts.filter { $0.deletedAt != nil }
            case .folder(let id):
                base = PromptLibrary.folderContents(of: id, prompts: activePrompts, folders: activeFolders)
            }
        }
        return sort.sorted(base)
    }

    private var shownPrompts: [Prompt] {
        libraryFilter.apply(to: basePrompts)
    }

    private var availableTagOptions: [PromptTagFilterOption] {
        var counts: [UUID: Int] = [:]
        // Count before applying filters so choosing a tag does not reorder the strip.
        for prompt in basePrompts {
            for id in Set(prompt.tags.map(\.id)) { counts[id, default: 0] += 1 }
        }
        let selectedIDs = libraryFilter.selectedTagIDs.union(libraryFilter.excludedTagIDs)
        return tags.filter { counts[$0.id] != nil || selectedIDs.contains($0.id) }
            .map { PromptTagFilterOption(id: $0.id, name: $0.name, promptCount: counts[$0.id, default: 0]) }
            .sorted {
                if $0.promptCount != $1.promptCount { return $0.promptCount > $1.promptCount }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
    }

    private var filterScopeTitle: String {
        if searching { return "全部资料库的搜索结果" }
        if let folder = selectedFolder { return "\(folder.name) · 含子文件夹" }
        return collection.name
    }

    private var workspaceView: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar.navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
        } detail: {
            Group {
                if creating {
                    PromptCreateView(folders: activeFolders, initialFolderID: selectedFolderID,
                                     titlebarInset: detailHeaderInset,
                                     onCreate: createPrompt, onCancel: { creating = false })
                } else if let id = editingID,
                          let prompt = prompts.first(where: { $0.id == id && $0.deletedAt == nil }) {
                    PromptEditorView(prompt: prompt, folders: activeFolders,
                                     titlebarInset: detailHeaderInset,
                                     onBack: { editingID = nil },
                                     onExport: { export(prompt, title: $0, content: $1) },
                                     onError: { errorMessage = $0 })
                        .id(prompt.id)
                } else {
                    library
                }
            }
            .frame(minWidth: 650, minHeight: 580)
        }
        .frame(minWidth: 900, minHeight: 620)
    }

    private var workspaceWithDialogs: some View {
        workspaceView
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.plainText, UTType(filenameExtension: "md") ?? .plainText],
                      allowsMultipleSelection: true) { result in
            importFiles(result, folderID: importDestinationFolderID)
        }
        .alert("新建文件夹", isPresented: $showNewFolder) {
            TextField("文件夹名称", text: $newFolderName)
            Button("创建", action: createFolder)
            Button("取消", role: .cancel) {}
        }
        .alert("重命名文件夹", isPresented: Binding(
            get: { folderToRename != nil }, set: { if !$0 { folderToRename = nil } }
        )) {
            TextField("文件夹名称", text: $renameText)
            Button("重命名", action: renameFolder)
            Button("取消", role: .cancel) { folderToRename = nil }
        }
        .confirmationDialog("删除文件夹", isPresented: Binding(
            get: { folderToDelete != nil }, set: { if !$0 { folderToDelete = nil } }
        )) {
            Button("将内容移到上级文件夹") { deleteFolder(.moveContentsToParent) }
            Button("连同内容移入废纸篓", role: .destructive) { deleteFolder(.trashContents) }
            Button("取消", role: .cancel) { folderToDelete = nil }
        } message: {
            Text("请选择如何处理“\(folderToDelete?.name ?? "")”中的提示词。")
        }
        .confirmationDialog("永久删除文件夹？", isPresented: Binding(
            get: { folderToPurge != nil }, set: { if !$0 { folderToPurge = nil } }
        )) {
            Button("永久删除", role: .destructive) { purgeFolder() }
            Button("取消", role: .cancel) { folderToPurge = nil }
        } message: {
            Text("“\(folderToPurge?.name ?? "")”及其中的提示词将无法恢复。")
        }
        .alert("操作失败", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "未知错误") }
    }

    private var workspaceWithRequests: some View {
        workspaceWithDialogs
        .onChange(of: searchText) { _, _ in scheduleSearch() }
        .onChange(of: searchScope) { _, _ in scheduleSearch() }
        .onChange(of: PromptSearch.revision(prompts, folders: activeFolders)) { _, _ in
            if searching { scheduleSearch() }
        }
        .onChange(of: Set(tags.map(\.id))) { _, ids in
            libraryFilter.removeUnknownTags(validIDs: ids)
        }
        .onChange(of: app.openPromptID) { _, id in
            guard let id, let prompt = prompts.first(where: { $0.id == id }) else { return }
            open(prompt)
            app.openPromptID = nil
        }
        .onChange(of: app.createRequest) { _, count in
            guard count > 0 else { return }
            app.createRequest = 0
            startCreate()
        }
        .onChange(of: app.trashRevision) { _, _ in
            guard let id = app.lastTrashedPromptID else { return }
            if editingID == id { editingID = nil }
            if selectedPromptID == id { selectedPromptID = nil }
        }
        .onChange(of: app.libraryRevision) { _, _ in navigate(.all) }
        .onChange(of: app.searchRequest) { _, count in
            guard count > 0 else { return }
            app.searchRequest = 0
            focusSearch()
        }
        .onChange(of: app.collectionRequest) { _, target in
            guard let target else { return }
            app.collectionRequest = nil
            navigate(target == .recentUse ? .recentUse : .favorites)
        }
    }

    var body: some View {
        workspaceWithRequests
        .onChange(of: selection) { _, value in
            app.selectedPromptIDs = value.ids
            app.selectedPromptID = value.ids.count == 1 ? value.focusedID : nil
        }
        .onChange(of: shownPrompts.map(\.id)) { _, ids in
            if !creating && editingID == nil {
                selection.retain(ids)
                selectFirstListPromptIfNeeded()
            }
        }
        .onChange(of: viewMode) { _, _ in selectFirstListPromptIfNeeded() }
        .onAppear(perform: handleInitialRequests)
        .onDisappear { searchTask?.cancel() }
        .onChange(of: prompts.count) { _, _ in
            if app.startup.isReady {
                Task { await PromptSearch.prepareIndex(activePrompts, folders: activeFolders) }
            }
        }
        .task {
            if app.startup.isReady { await PromptSearch.prepareIndex(activePrompts, folders: activeFolders) }
        }
        .overlay(alignment: .bottom) {
            if let value = app.toastText {
                Label(value, systemImage: value == "已复制" ? "checkmark.circle.fill" : "info.circle")
                    .font(.callout).padding(.horizontal, 16).padding(.vertical, 9)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(radius: 8, y: 3).padding(.bottom, 18)
                    .allowsHitTesting(false)
            }
        }
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        settledSearch = ""; searchMatches = []
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        let scope = searchScope
        searchTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            let matches = await PromptSearch.searchAsync(prompts, query: query, scope: scope, folders: activeFolders)
            guard !Task.isCancelled else { return }
            searchMatches = matches; settledSearch = query
        }
    }

    private var detailHeaderInset: CGFloat {
        columnVisibility == .detailOnly ? 136 : 20
    }

    private func handleInitialRequests() {
        if searching { scheduleSearch() }
        if let id = app.openPromptID, let prompt = prompts.first(where: { $0.id == id }) {
            open(prompt)
            app.openPromptID = nil
        } else if app.createRequest > 0 {
            app.createRequest = 0
            startCreate()
        } else if app.searchRequest > 0 {
            app.searchRequest = 0
            focusSearch()
        } else if let target = app.collectionRequest {
            app.collectionRequest = nil
            navigate(target == .recentUse ? .recentUse : .favorites)
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    sidebarRow("所有提示词", "square.grid.2x2", activePrompts.count, .all)
                        .onDrop(of: [.plainText], isTargeted: nil) { receiveMove($0, into: nil) }
                    sidebarRow("收藏", "star", activePrompts.filter(\.isFavorite).count, .favorites)
                    sidebarRow("最近使用", "clock", activePrompts.filter { $0.lastUsedAt != nil }.count, .recentUse)
                    sidebarRow("最近编辑", "pencil", activePrompts.count, .recentEdit)
                    HStack {
                        Text("文件夹").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            newFolderParent = selectedFolderID
                            newFolderName = ""
                            showNewFolder = true
                        } label: {
                            Image(systemName: "plus")
                                .frame(width: 23, height: 23)
                                .modifier(SubtleHoverSurface(selected: false))
                        }
                        .buttonStyle(.plain).accessibilityLabel("新建文件夹")
                    }
                    .padding(.leading, 12).padding(.trailing, 15)
                    .padding(.top, 19).padding(.bottom, 5)
                    ForEach(activeFolders.filter { $0.parentID == nil }
                        .sorted { $0.sortIndex < $1.sortIndex }) { folder in
                        SidebarFolderNode(
                            folder: folder, folders: activeFolders, prompts: activePrompts,
                            selectedID: selectedFolderID, depth: 0,
                            onSelect: { navigate(.folder($0.id)) },
                            onNewChild: {
                                newFolderParent = $0.id; newFolderName = ""; showNewFolder = true
                            },
                            onRename: { folderToRename = $0; renameText = $0.name },
                            onExport: exportCollection,
                            onDelete: { folderToDelete = $0 },
                            onDropItems: { receiveMove($0, into: $1) }
                        )
                    }
                    sidebarRow("未分类", "tray", PromptLibrary.directCount(for: nil, in: activePrompts), .uncategorized)
                        .onDrop(of: [.plainText], isTargeted: nil) { receiveMove($0, into: nil) }
                    sidebarRow("废纸篓", "trash",
                               prompts.filter { $0.deletedAt != nil }.count + trashedFolderRoots.count, .trash)
                        .padding(.top, 14)
                }
                .padding(.horizontal, 8).padding(.bottom, 16)
            }
            .appScrollEdge()
            .appTopBar {
                HStack(spacing: 8) {
                    Image("BrandMark").resizable().renderingMode(.template)
                        .frame(width: 30, height: 30)
                        .accessibilityHidden(true)
                    Text("oTATo prompt").font(.system(size: 15, weight: .semibold))
                    Spacer()
                }
                .padding(.horizontal, 15).frame(height: 44)
            }
        }
    }

    private func sidebarRow(_ title: String, _ symbol: String, _ count: Int,
                            _ target: LibraryCollection) -> some View {
        Button { navigate(target) } label: {
            HStack(spacing: 9) {
                Image(systemName: symbol).frame(width: 16)
                Text(title).lineLimit(1)
                Spacer(minLength: 3)
                Text(count.formatted()).font(.caption).foregroundStyle(.secondary)
            }
            .font(.system(size: 12.5))
            .padding(.horizontal, 9).frame(height: 28)
            .contentShape(Rectangle())
            .modifier(SubtleHoverSurface(
                selected: collection == target && !searching))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title)，\(count) 个提示词")
    }

    private func libraryCard(_ prompt: Prompt) -> some View {
        PromptCardView(prompt: prompt, selected: selection.ids.contains(prompt.id), searchQuery: settledSearch,
                       onSelect: { select(prompt) }, onOpen: { open(prompt) },
                       onCopy: { app.requestCopy(prompt) }, onFavorite: { toggleFavorite(prompt) })
            .contextMenu { cardMenu(prompt) }
            .onDrag { NSItemProvider(object: "prompt:\(prompt.id.uuidString)" as NSString) }
    }

    private func libraryRow(_ prompt: Prompt) -> some View {
        PromptListRow(prompt: prompt, selected: selection.ids.contains(prompt.id),
                      searchQuery: settledSearch, onSelect: { select(prompt) })
            .contextMenu { cardMenu(prompt) }
            .onDrag { NSItemProvider(object: "prompt:\(prompt.id.uuidString)" as NSString) }
    }

    /// Date groups apply only to the chronological sort. A–Z remains one list.
    private var listSections: [(name: String, prompts: [Prompt])] {
        let values = shownPrompts
        guard sort == .updated else { return [("", values)] }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let week = calendar.date(byAdding: .day, value: -7, to: today) ?? today
        let month = calendar.date(byAdding: .day, value: -30, to: today) ?? today
        let groups = Dictionary(grouping: values) { prompt -> String in
            if calendar.isDateInToday(prompt.updatedAt) { return "今天" }
            if calendar.isDateInYesterday(prompt.updatedAt) { return "昨天" }
            if prompt.updatedAt >= week { return "过去 7 天" }
            if prompt.updatedAt >= month { return "过去 30 天" }
            return "更早"
        }
        return ["今天", "昨天", "过去 7 天", "过去 30 天", "更早"].compactMap { name in
            groups[name].map { (name, $0) }
        }
    }

    private var compactPromptList: some View {
        VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(searching ? "搜索结果" : selectedFolder?.name ?? collection.name)
                        .font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    Text("\(shownPrompts.count) 个提示词")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20).padding(.vertical, 12)
                Divider()
                libraryContents.appScrollEdge()
        }
            .focusable().focused($libraryFocused).focusEffectDisabled()
            .background { LibraryKeyBoundary(onKey: handleLibraryKey) }
    }

    private var listWorkspace: some View {
        HSplitView {
            compactPromptList
                .frame(minWidth: 300, idealWidth: 360, maxWidth: 440, maxHeight: .infinity)
            Group {
                if let prompt = listPrompt {
                    PromptEditorView(prompt: prompt, folders: activeFolders, embedded: true,
                                     onBack: {},
                                     onExport: { export(prompt, title: $0, content: $1) },
                                     onError: { errorMessage = $0 })
                        .id(prompt.id)
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: selection.ids.count > 1 ? "checkmark.circle" : "doc.text")
                            .font(.system(size: 30, weight: .ultraLight)).foregroundStyle(.tertiary)
                        Text(selection.ids.count > 1 ? "已选 \(selection.ids.count) 条提示词" : "选择一条提示词")
                            .font(.headline).foregroundStyle(.secondary)
                        if selection.ids.count > 1 {
                            Text("使用底部操作栏批量管理")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var libraryContents: some View {
        VStack(spacing: 0) {
            if searching && settledSearch.isEmpty {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if shownPrompts.isEmpty && (collection != .trash || searching || libraryFilter.isActive || trashedFolderRoots.isEmpty) { emptyState }
            else {
                Group {
                    if viewMode == "grid" && (collection != .trash || searching || libraryFilter.isActive || trashedFolderRoots.isEmpty) {
                        GeometryReader { geometry in
                            NativePromptGrid(prompts: shownPrompts, minimumWidth: cardMinimumWidth,
                                             topInset: geometry.frame(in: .global).minY, selection: selection.ids, searchQuery: settledSearch) { prompt in
                                AnyView(libraryCard(prompt))
                            }
                            .overlay(alignment: .top) {
                                // SwiftUI scroll-edge effects do not discover an AppKit
                                // scroll view. Keep the same soft header edge over its layers.
                                LinearGradient(stops: [
                                    .init(color: Color(nsColor: .windowBackgroundColor), location: 0),
                                    .init(color: Color(nsColor: .windowBackgroundColor),
                                          location: geometry.frame(in: .global).minY / max(1, geometry.frame(in: .global).minY + 12)),
                                    .init(color: Color(nsColor: .windowBackgroundColor).opacity(0), location: 1)
                                ], startPoint: .top, endPoint: .bottom)
                                .frame(height: geometry.frame(in: .global).minY + 12)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                            }
                            .ignoresSafeArea(.container, edges: .top)
                        }
                    } else {
                        ScrollView {
                            if collection == .trash && !searching && !libraryFilter.isActive && !trashedFolderRoots.isEmpty {
                                trashedFolderSection
                            }
                            if viewMode == "list" {
                                LazyVStack(alignment: .leading, spacing: 0) {
                                    ForEach(listSections, id: \.name) { section in
                                        if !section.name.isEmpty {
                                            Text(section.name)
                                                .font(.system(size: 13, weight: .semibold))
                                                .padding(.horizontal, 16)
                                                .padding(.top, 15).padding(.bottom, 8)
                                        }
                                        ForEach(section.prompts) { prompt in
                                            libraryRow(prompt)
                                            Divider().padding(.leading, 16).padding(.trailing, 10)
                                        }
                                    }
                                }
                                .padding(.horizontal, 10).padding(.bottom, 12)
                            } else {
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: cardMinimumWidth,
                                                                      maximum: cardMinimumWidth + 45), spacing: 16)], spacing: 16) {
                                    ForEach(shownPrompts) { prompt in
                                        libraryCard(prompt)
                                    }
                                }
                                .padding(.horizontal, 20).padding(.top, 15).padding(.bottom, 20)
                            }
                        }
                    }
                }

            }
        }
    }

    private var keyboardLibrary: some View {
        libraryContents
            .appScrollEdge()
            .focusable().focused($libraryFocused)
            .focusEffectDisabled()
            .background { LibraryKeyBoundary(onKey: handleLibraryKey) }
    }

    private func handleLibraryKey(_ event: NSEvent) -> Bool {
        guard !searchFocused, !creating, editingID == nil, !showingFilterPanel, !showingBatchTags else { return false }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers.contains(.command) {
            guard event.charactersIgnoringModifiers == "a" else { return false }
            selection.all(shownPrompts.map(\.id)); return true
        }
        guard !modifiers.contains(.option), !modifiers.contains(.control) else { return false }
        switch event.keyCode {
        case 123: moveSelection(-1, extend: modifiers.contains(.shift))
        case 124: moveSelection(1, extend: modifiers.contains(.shift))
        case 126: moveSelection(viewMode == "grid" ? -gridColumnCount : -1, extend: modifiers.contains(.shift))
        case 125: moveSelection(viewMode == "grid" ? gridColumnCount : 1, extend: modifiers.contains(.shift))
        case 36, 76: openSelected()
        case 49: copySelected()
        case 53: selection.single(nil)
        default: return false
        }
        return true
    }

    private var library: some View {
        Group {
            if viewMode == "list" {
                VStack(spacing: 0) {
                    libraryFilterBar
                    Divider()
                    listWorkspace
                }
            } else {
                keyboardLibrary.appTopBar { libraryFilterBar }
            }
        }
        .toolbar { libraryToolbar }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if selection.ids.count > 1 { batchActionBar }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onDrop(of: [.fileURL], isTargeted: $fileDropTargeted, perform: receiveFiles)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { libraryWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, width in libraryWidth = width }
            }
        }
        .onAppear {
            selection.retain(shownPrompts.map(\.id))
            selectFirstListPromptIfNeeded()
            // Keep the library keyboard-ready without giving the search field
            // its prominent AppKit focus ring on every window opening.
            DispatchQueue.main.async {
                if !pendingSearchFocus {
                    searchFocused = false
                    libraryFocused = true
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let toast {
                Label(toast, systemImage: "checkmark.circle.fill")
                    .font(.callout).padding(.horizontal, 16).padding(.vertical, 9)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(radius: 8, y: 3).padding(.bottom, 18)
            }
        }
        .overlay {
            if fileDropTargeted || importingFiles {
                VStack(spacing: 10) {
                    if importingFiles {
                        ProgressView().controlSize(.small)
                        Text("正在导入提示词…")
                    } else {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 26, weight: .light))
                        Text("松开以导入提示词")
                        Text("支持单个或多个 .md / .txt 文件")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .font(.callout.weight(.medium))
                .padding(.horizontal, 28).padding(.vertical, 22)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
                .allowsHitTesting(false)
            }
        }
    }

    private var libraryFilterBar: some View {
        VStack(spacing: 0) {
            if searching { searchScopes }
            tagStrip
            if libraryFilter.isActive {
                PromptActiveFilterSummary(filter: $libraryFilter, tags: availableTagOptions)
                    .padding(.horizontal, 20).padding(.bottom, 8)
            }
        }
    }

    private var trashedFolderSection: some View {
        LazyVStack(alignment: .leading, spacing: 8) {
            Text("文件夹")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(trashedFolderRoots) { folder in
                HStack(spacing: 10) {
                    Image(systemName: "folder")
                        .foregroundStyle(.secondary)
                    Text(folderPath(folder))
                        .lineLimit(1)
                    Spacer()
                    Button("恢复") { perform { try PromptLibrary.restore(folder, in: context) } }
                    Button("永久删除", role: .destructive) { folderToPurge = folder }
                }
                .font(.callout)
                .padding(10)
                .background(Color(nsColor: .controlBackgroundColor),
                            in: RoundedRectangle(cornerRadius: 7))
                .contextMenu {
                    Button("恢复") { perform { try PromptLibrary.restore(folder, in: context) } }
                    Button("永久删除", role: .destructive) { folderToPurge = folder }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    private func folderPath(_ folder: Folder) -> String {
        var names = [folder.name]
        var parentID = folder.parentID
        var visited = Set<UUID>([folder.id])
        while let id = parentID,
              let parent = folders.first(where: { $0.id == id }),
              visited.insert(id).inserted {
            names.insert(parent.name, at: 0)
            parentID = parent.parentID
        }
        return names.joined(separator: " / ")
    }
    private var cardMinimumWidth: CGFloat {
        cardSize == "compact" ? 190 : cardSize == "roomy" ? 270 : 230
    }
    private var gridColumnCount: Int {
        max(1, Int((libraryWidth - 40 + 16) / (cardMinimumWidth + 16)))
    }

    @ToolbarContentBuilder
    private var libraryToolbar: some ToolbarContent {
        ToolbarItem(id: "library.viewMode", placement: .navigation) {
            viewModePicker
        }
        if #available(macOS 26.0, *) {
            ToolbarSpacer(.fixed, placement: .navigation)
            ToolbarItem(id: "library.search", placement: .navigation) {
                librarySearchField
            }
            .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(id: "library.search", placement: .navigation) {
                librarySearchField
            }
        }
        if #available(macOS 26.0, *) {
            ToolbarSpacer(.flexible, placement: .primaryAction)
        }
        ToolbarItem(id: "library.sort", placement: .primaryAction) { sortMenu }
        if #available(macOS 26.0, *) {
            ToolbarSpacer(.fixed, placement: .primaryAction)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button(action: beginImport) {
                Label("导入", systemImage: "square.and.arrow.down")
            }
            .labelStyle(.titleAndIcon)
            .disabled(importingFiles)
            .help("导入一个或多个 .md / .txt 文件")
            .accessibilityLabel("导入提示词文件")
            Button(action: startCreate) {
                Label("新建 Prompt", systemImage: "plus")
            }
            .help("新建 Prompt")
        }
    }

    private var viewModePicker: some View {
        Picker(selection: $viewMode) {
            Image(systemName: "square.grid.2x2")
                .accessibilityLabel("网格视图")
                .tag("grid")
            Image(systemName: "list.bullet")
                .accessibilityLabel("列表视图")
                .tag("list")
        } label: {
            EmptyView()
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(width: 76)
        .accessibilityLabel("视图方式")
    }

    private var librarySearchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("搜索标题、标签…", text: $searchText)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .focusEffectDisabled()
                .accessibilityLabel("搜索提示词")
        }
        .padding(.horizontal, 11)
        .frame(width: 230, height: 32)
        .modifier(LibrarySearchSurface(isFocused: searchFocused))
        .background {
            SearchFocusBoundary(isFocused: searchFocused) {
                searchFocused = false
            }
        }
    }

    private var tagStrip: some View {
        HStack(spacing: 12) {
            NativeTagStrip(filter: $libraryFilter, tags: availableTagOptions)
                .frame(height: 29)
            Button { showingFilterPanel.toggle() } label: {
                HStack(spacing: 5) {
                    Label("筛选", systemImage: "line.3.horizontal.decrease")
                    if libraryFilter.isActive {
                        Text(libraryFilter.activeCriterionCount.formatted())
                            .font(.system(size: 10, weight: .semibold).monospacedDigit())
                            .foregroundStyle(accent.selectedForeground)
                            .padding(.horizontal, 5)
                            .frame(minWidth: 17, minHeight: 17)
                            .background(accent.selectedFill, in: Capsule())
                    }
                }
                .font(.system(size: 11))
                .padding(.horizontal, 8)
                .frame(height: 29)
                .contentShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .modifier(SubtleHoverSurface(selected: libraryFilter.isActive))
            .fixedSize()
            .accessibilityLabel("筛选提示词")
            .accessibilityValue(libraryFilter.isActive ? "\(libraryFilter.activeCriterionCount) 个条件" : "未筛选")
            .popover(isPresented: $showingFilterPanel, arrowEdge: .bottom) {
                PromptFilterPanel(filter: $libraryFilter, tags: availableTagOptions,
                                  resultCount: shownPrompts.count, scopeTitle: filterScopeTitle,
                                  onDone: { showingFilterPanel = false })
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 6)
    }

    private var sortMenu: some View {
        Menu {
            ForEach(PromptLibrarySort.allCases) { item in
                Toggle(item.name, isOn: Binding(
                    get: { sort == item },
                    set: { selected in if selected { sort = item } }
                ))
            }
        } label: {
            Label("排序", systemImage: "arrow.up.arrow.down")
                .font(.system(size: 11))
                .foregroundStyle(Color.primary)
        }
        .menuStyle(.button)
        .labelStyle(.titleAndIcon)
        .menuIndicator(.hidden)
        .tint(.primary)
        .fixedSize()
        .accessibilityLabel("提示词显示顺序")
        .accessibilityValue(sort.name)
    }

    private var searchScopes: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                scopeChip("全部", .all)
                scopeChip("标题", .title)
                scopeChip("标签", .tags)
                scopeChip("收藏", .favorites)
            }
            .padding(.horizontal, 20).padding(.vertical, 8)
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        LibraryChip(title: title, selected: selected, action: action)
    }
    private func scopeChip(_ title: String, _ scope: PromptSearch.Scope) -> some View {
        chip(title, selected: searchScope == scope) { searchScope = scope }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: searching ? "magnifyingglass" : collection == .favorites ? "star" :
                    collection == .trash ? "trash" : "square.stack")
                .font(.system(size: 36, weight: .ultraLight)).foregroundStyle(.tertiary)
            Text(emptyTitle).font(.system(size: 16, weight: .semibold))
            Text(libraryFilter.isActive ? "调整标签或其他条件，或清除筛选。" :
                 searching ? "试试其他关键词或切换搜索范围。" : "用 Prompt 开始整理你的灵感与工作流程。")
                .font(.callout).foregroundStyle(.secondary)
            if libraryFilter.isActive {
                HStack(spacing: 8) {
                    Button("清除筛选") { libraryFilter.reset() }
                        .appPrimaryAction()
                    if searching { Button("清除搜索") { searchText = "" } }
                }
            } else if searching {
                Button("清除搜索") { searchText = "" }
            } else if collection != .trash {
                HStack(spacing: 8) {
                    Button("新建 Prompt", action: startCreate).appPrimaryAction()
                    Button("导入 .md/.txt", action: beginImport)
                        .appSecondaryAction().disabled(importingFiles)
                }.padding(.top, 4)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private var emptyTitle: String {
        if libraryFilter.isActive { return "没有符合筛选条件的提示词" }
        if searching { return "没有找到匹配的提示词" }
        switch collection {
        case .favorites: return "收藏常用 Prompt 后会出现在这里"
        case .trash: return "废纸篓是空的"
        case .folder: return "这个文件夹还是空的"
        case .uncategorized: return "这里还没有提示词"
        default: return "还没有提示词"
        }
    }

    private var batchActionBar: some View {
        HStack(spacing: 14) {
            Text("已选 \(selection.ids.count) 条").font(.callout.weight(.medium))
            if selectedPrompts.allSatisfy({ $0.deletedAt != nil }) {
                Button("恢复") { applyBatch(.restore) }
            } else {
                Menu { batchMoveMenu } label: { Label("移动到", systemImage: "folder") }
                Button { batchTagInput = ""; showingBatchTags = true } label: { Label("添加标签", systemImage: "tag") }
                    .popover(isPresented: $showingBatchTags) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("为所选提示词添加标签").font(.headline)
                            TextField("标签，用逗号分隔", text: $batchTagInput)
                                .onSubmit { addBatchTags() }
                                .frame(width: 260)
                            HStack {
                                Spacer()
                                Button("取消") { showingBatchTags = false }
                                Button("添加", action: addBatchTags).appPrimaryAction()
                                    .disabled(batchTagInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }.padding(18)
                    }
                Menu {
                    Button("收藏") { applyBatch(.favorite(true)) }
                    Button("取消收藏") { applyBatch(.favorite(false)) }
                } label: { Label("收藏", systemImage: "star") }
                Button(role: .destructive) { applyBatch(.trash) } label: { Label("移到废纸篓", systemImage: "trash") }
            }
            Spacer(minLength: 0)
            Button { selection.single(nil) } label: { Image(systemName: "xmark") }
                .help("取消选择").accessibilityLabel("取消多选")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .top) { Divider() }
    }

    @ViewBuilder private var batchMoveMenu: some View {
        Button("未分类") { applyBatch(.move(nil)) }
        ForEach(activeFolders) { folder in
            Button(folderPath(folder)) { applyBatch(.move(folder.id)) }
        }
    }

    @ViewBuilder private var batchMenu: some View {
        Text("已选 \(selection.ids.count) 条提示词")
        if selectedPrompts.allSatisfy({ $0.deletedAt != nil }) {
            Button("恢复所选") { applyBatch(.restore) }
        } else {
            Menu("移动到") { batchMoveMenu }
            Menu("添加标签") {
                ForEach(tags) { tag in Button(tag.name) { applyBatch(.addTags([tag.name])) } }
            }
            Button("收藏所选") { applyBatch(.favorite(true)) }
            Button("取消收藏所选") { applyBatch(.favorite(false)) }
            Button("移到废纸篓", role: .destructive) { applyBatch(.trash) }
        }
    }

    private func addBatchTags() {
        let names = batchTagInput.components(separatedBy: CharacterSet(charactersIn: ",，"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !names.isEmpty else { return }
        if applyBatch(.addTags(names)) { showingBatchTags = false }
    }

    @discardableResult private func applyBatch(_ action: PromptLibrary.BatchAction) -> Bool {
        let targets = selectedPrompts
        do {
            try PromptLibrary.apply(action, to: targets, in: context)
            if case .trash = action { selection.single(nil) }
            showToast("已处理 \(targets.count) 条提示词")
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @ViewBuilder private func cardMenu(_ prompt: Prompt) -> some View {
        if selection.ids.count > 1 && selection.ids.contains(prompt.id) {
            batchMenu
        } else if prompt.deletedAt != nil {
            Button("恢复") { perform { try PromptLibrary.restore(prompt, in: context) } }
            Button("永久删除", role: .destructive) { perform { try PromptLibrary.purge(prompt, in: context) } }
        } else {
            Button("复制 Prompt") { app.requestCopy(prompt) }
            Button("编辑") { open(prompt) }
            Button(prompt.isFavorite ? "取消收藏" : "收藏") { toggleFavorite(prompt) }
            Menu("添加标签") {
                ForEach(tags) { tag in
                    Button(tag.name) {
                        perform { try PromptLibrary.setTags(Array(Set(prompt.tagNames + [tag.name])), for: prompt, in: context) }
                    }
                }
            }
            Menu("移动到") {
                Button("未分类") { move(prompt, to: nil) }
                ForEach(activeFolders) { folder in Button(folder.name) { move(prompt, to: folder.id) } }
            }
            Button("更换封面…") { chooseCover(for: prompt) }
            if prompt.coverPath != nil {
                Button("移除封面") { perform { try PromptLibrary.setCover(nil, for: prompt, in: context) } }
            }
            Button("导出…") { export(prompt) }
            Button("移到废纸篓", role: .destructive) {
                perform { try PromptLibrary.trash(prompt, in: context) }
            }
        }
    }

    private func navigate(_ target: LibraryCollection) {
        creating = false; editingID = nil; collection = target
        libraryFilter.reset(); showingFilterPanel = false
        selectedPromptID = nil; searchText = ""; settledSearch = ""
    }
    private func open(_ prompt: Prompt) {
        guard prompt.deletedAt == nil else { return }
        if viewMode == "list" {
            if !shownPrompts.contains(where: { $0.id == prompt.id }) {
                navigate(prompt.folderID.map(LibraryCollection.folder) ?? .all)
            }
            selectedPromptID = prompt.id; creating = false; editingID = nil
        } else {
            selectedPromptID = prompt.id; creating = false; editingID = prompt.id
        }
    }
    private func selectFirstListPromptIfNeeded() {
        guard viewMode == "list", !creating, editingID == nil, selection.ids.isEmpty else { return }
        selection.single(shownPrompts.first?.id)
    }
    private func startCreate() {
        editingID = nil; selectedPromptID = nil; creating = true
        searchFocused = false
    }
    private func focusSearch() {
        pendingSearchFocus = true
        editingID = nil
        creating = false
        DispatchQueue.main.async {
            searchFocused = true
            pendingSearchFocus = false
        }
    }
    private func folderName(_ id: UUID?) -> String {
        guard let id else { return "未分类" }
        return activeFolders.first { $0.id == id }?.name ?? "未分类"
    }

    private func createPrompt(title: String, content: String, format: PromptFormat,
                              folderID: UUID?, tagNames: [String], isFavorite: Bool,
                              coverImage: NSImage?, crop: CoverCrop) throws {
        var stored: StoredCover?
        var created: Prompt?
        do {
            if let coverImage { stored = try PromptStorage.saveCoverAsset(image: coverImage) }
            let prompt = try PromptLibrary.createPrompt(in: context, title: title, content: content,
                                                         format: .markdown, folderID: folderID, tagNames: tagNames)
            created = prompt
            if isFavorite { try PromptLibrary.setFavorite(true, for: prompt, in: context) }
            if let stored { try PromptLibrary.setCover(stored, crop: .full, for: prompt, in: context) }
            searchTask?.cancel()
            searchText = ""
            settledSearch = ""
            libraryFilter.reset()
            showingFilterPanel = false
            collection = folderID.map(LibraryCollection.folder) ?? .all
            creating = false
            editingID = nil
            selectedPromptID = prompt.id
        } catch {
            if let created {
                context.delete(created)
                try? context.save()
            }
            if let stored { try? PromptStorage.removeCover(at: stored.relativePath) }
            throw error
        }
    }
    private func toggleFavorite(_ prompt: Prompt) {
        perform { try PromptLibrary.setFavorite(!prompt.isFavorite, for: prompt, in: context) }
    }
    private func move(_ prompt: Prompt, to id: UUID?) {
        perform { try PromptLibrary.move(prompt, to: id, in: context) }
    }
    private func createFolder() {
        let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        perform {
            let count = activeFolders.filter { $0.parentID == newFolderParent }.count
            _ = try PromptLibrary.createFolder(in: context, name: name, parentID: newFolderParent,
                                                sortIndex: Double(count))
        }
    }
    private func renameFolder() {
        guard let folder = folderToRename else { return }
        let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        folderToRename = nil
        guard !name.isEmpty else { return }
        perform { try PromptLibrary.renameFolder(folder, to: name, in: context) }
    }
    private func deleteFolder(_ mode: PromptLibrary.FolderTrashMode) {
        guard let folder = folderToDelete else { return }
        folderToDelete = nil
        perform { try PromptLibrary.trash(folder, mode: mode, in: context) }
        if collection == .folder(folder.id) { navigate(.all) }
    }
    private func purgeFolder() {
        guard let folder = folderToPurge else { return }
        folderToPurge = nil
        perform { try PromptLibrary.purge(folder, in: context) }
    }
    private func beginImport() {
        guard !importingFiles else { return }
        importDestinationFolderID = selectedFolderID
        importing = true
    }

    private func importFiles(_ result: Result<[URL], Error>, folderID: UUID?) {
        switch result {
        case .success(let urls):
            guard !urls.isEmpty, !importingFiles else { return }
            let libraryRevision = app.libraryRevision
            importingFiles = true
            Task { @MainActor in
                defer { importingFiles = false }
                do { try await completeImport(urls, folderID: folderID, libraryRevision: libraryRevision) }
                catch { errorMessage = error.localizedDescription }
            }
        case .failure(let error):
            let failure = error as NSError
            if failure.domain != NSCocoaErrorDomain || failure.code != NSUserCancelledError {
                errorMessage = error.localizedDescription
            }
        }
    }

    @MainActor
    private func completeImport(_ urls: [URL], folderID: UUID?, libraryRevision: Int) async throws {
        let initialCollection = collection
        let startedInLibrary = !creating && editingID == nil
        let files = try await Task.detached(priority: .userInitiated) {
            try PromptTextTransfer.readAll(urls)
        }.value
        guard app.libraryRevision == libraryRevision else { return }
        if let folderID, !activeFolders.contains(where: { $0.id == folderID }) {
            throw PromptLibraryError.folderUnavailable
        }
        let created = try PromptTextTransfer.importTexts(files, into: context, folderID: folderID)
        guard !created.isEmpty else { return }
        if startedInLibrary, !creating, editingID == nil,
           collection == initialCollection {
            searchTask?.cancel()
            navigate(folderID.map(LibraryCollection.folder) ?? .all)
            selectedPromptID = created.first?.id
        }
        showToast("已导入 \(created.count) 个 Prompt")
    }

    private func receiveFiles(_ providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !fileProviders.isEmpty, !importingFiles else { return false }
        let folderID = selectedFolderID
        let libraryRevision = app.libraryRevision
        importingFiles = true
        Task { @MainActor in
            defer { importingFiles = false }
            do {
                var urls: [URL] = []
                for provider in fileProviders {
                    let url: URL? = await withCheckedContinuation { continuation in
                        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                            let resolved: URL?
                            if let item = item as? URL { resolved = item }
                            else if let data = item as? Data {
                                resolved = URL(dataRepresentation: data, relativeTo: nil)
                            } else if let text = item as? String {
                                resolved = URL(string: text)
                            } else { resolved = nil }
                            continuation.resume(returning: resolved)
                        }
                    }
                    guard let url, url.isFileURL else {
                        errorMessage = "无法读取拖入的文件。"
                        return
                    }
                    urls.append(url)
                }
                try await completeImport(urls, folderID: folderID, libraryRevision: libraryRevision)
            } catch { errorMessage = error.localizedDescription }
        }
        return true
    }
    private func export(_ prompt: Prompt, title: String? = nil, content: String? = nil) {
        let panel = NSSavePanel()
        let exportTitle = title ?? prompt.title
        panel.nameFieldStringValue = "\(exportTitle.isEmpty ? "未命名 Prompt" : exportTitle).md"
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        perform {
            _ = try PromptTextTransfer.write(content: content ?? prompt.content, format: .markdown, to: url)
            showToast("已导出 Prompt")
        }
    }
    private func chooseCover(for prompt: Prompt) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK, let url = panel.url,
              let image = NSImage(contentsOf: url) else { return }
        perform {
            let cover = try PromptStorage.saveCoverAsset(image: image)
            try PromptLibrary.setCover(cover, for: prompt, in: context)
        }
    }
    private func exportCollection(_ folder: Folder) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.prompt = "导出到此文件夹"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        perform {
            let written = try PromptTextTransfer.writeCollection(
                prompts: PromptLibrary.folderContents(of: folder.id, prompts: activePrompts,
                                                     folders: activeFolders),
                folders: activeFolders, to: url)
            showToast("已导出 \(written.count) 个 Prompt")
        }
    }
    private func receiveMove(_ providers: [NSItemProvider], into id: UUID?) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let value = object as? String else { return }
            Task { @MainActor in
                if value.hasPrefix("prompt:"), let uuid = UUID(uuidString: String(value.dropFirst(7))),
                   let prompt = prompts.first(where: { $0.id == uuid }) { move(prompt, to: id) }
                if value.hasPrefix("folder:"), let uuid = UUID(uuidString: String(value.dropFirst(7))),
                   let folder = folders.first(where: { $0.id == uuid }) {
                    if let id, folder.parentID == activeFolders.first(where: { $0.id == id })?.parentID {
                        var siblings = activeFolders.filter { $0.parentID == folder.parentID }
                            .sorted { $0.sortIndex < $1.sortIndex }
                        siblings.removeAll { $0.id == folder.id }
                        let index = siblings.firstIndex { $0.id == id } ?? siblings.count
                        siblings.insert(folder, at: index)
                        perform { try PromptLibrary.setFolderOrder(siblings, in: context) }
                    } else {
                        perform { try PromptLibrary.moveFolder(folder, to: id, in: context) }
                    }
                }
            }
        }
        return true
    }
    private func select(_ prompt: Prompt) {
        searchFocused = false
        let modifiers = NSEvent.modifierFlags
        selection.select(prompt.id, orderedIDs: shownPrompts.map(\.id),
                         toggle: modifiers.contains(.command), extend: modifiers.contains(.shift))
        libraryFocused = true
    }

    private func moveSelection(_ step: Int, extend: Bool = false) {
        guard !shownPrompts.isEmpty else { return }
        let current = shownPrompts.firstIndex { $0.id == selectedPromptID } ?? -1
        selection.select(shownPrompts[min(max(current + step, 0), shownPrompts.count - 1)].id,
                         orderedIDs: shownPrompts.map(\.id), toggle: false, extend: extend)
    }
    private func openSelected() {
        guard selection.ids.count == 1 else { return }
        guard let prompt = shownPrompts.first(where: { $0.id == selectedPromptID }) else { return }
        open(prompt)
    }
    private func copySelected() {
        guard selection.ids.count == 1 else { return }
        guard let prompt = shownPrompts.first(where: { $0.id == selectedPromptID && $0.deletedAt == nil }) else { return }
        app.requestCopy(prompt)
    }
    private func perform(_ work: () throws -> Void) {
        do { try work() } catch { errorMessage = error.localizedDescription }
    }
    private func showToast(_ value: String) {
        toast = value
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            if toast == value { toast = nil }
        }
    }
}

#if DEBUG
#Preview("资料库 · 深色", traits: .fixedLayout(width: 1100, height: 720)) {
    let container = try! PromptPersistence.makeContainer(inMemory: true)
    ContentView()
        .environmentObject(AppCoordinator(container: container))
        .modelContainer(container)
        .preferredColorScheme(.dark)
        .environment(\.appAccentStyle, AppAccentStyle(palette: .monochrome, colorScheme: .dark))
        .tint(AppAccentStyle(palette: .monochrome, colorScheme: .dark).tint)
}
#endif
