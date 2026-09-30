import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct PromptEditorView: View {
    @Environment(\.appAccentStyle) private var accent
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var app: AppCoordinator
    @AppStorage("editorFontSize") private var editorFontSize = 15.0
    @AppStorage("editorWrapLines") private var editorWrapLines = true

    let prompt: Prompt
    let folders: [Folder]
    let titlebarInset: CGFloat
    let onBack: () -> Void
    let onExport: (String, String) -> Void
    let onError: (String) -> Void

    @State private var title: String
    @State private var content: String
    @State private var folderID: UUID?
    @State private var tagInput: String
    @State private var pendingTag = ""
    @State private var addingTag = false
    @State private var favorite: Bool
    @State private var coverImage: NSImage?
    @State private var coverChanged = false
    @State private var showInspector = false
    @State private var saveError: String?
    @State private var editorCommand: EditorCommand?
    @State private var openedLibraryRevision: Int?
    @State private var editorSessionID = UUID()
    @FocusState private var pendingTagFocused: Bool

    init(prompt: Prompt, folders: [Folder], titlebarInset: CGFloat = 20,
         onBack: @escaping () -> Void,
         onExport: @escaping (String, String) -> Void,
         onError: @escaping (String) -> Void) {
        self.prompt = prompt
        self.folders = folders
        self.titlebarInset = titlebarInset
        self.onBack = onBack
        self.onExport = onExport
        self.onError = onError
        _title = State(initialValue: prompt.title)
        _content = State(initialValue: prompt.content)
        _folderID = State(initialValue: prompt.folderID)
        _tagInput = State(initialValue: prompt.tagNames.joined(separator: ", "))
        _favorite = State(initialValue: prompt.isFavorite)
        _coverImage = State(initialValue: PromptPresentation.croppedImage(for: prompt))
    }

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 840
            HStack(spacing: 0) {
                editorPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if wide {
                    Divider()
                    inspector.frame(width: 270)
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button(action: onBack) { Label("返回", systemImage: "chevron.left") }
                        .help("返回资料库")
                }
                if #available(macOS 26.0, *) {
                    ToolbarSpacer(.flexible, placement: .primaryAction)
                }
                if !wide {
                    ToolbarItem(placement: .primaryAction) {
                        Button { showInspector.toggle() } label: {
                            Label("详情", systemImage: "sidebar.right")
                        }
                        .popover(isPresented: $showInspector, arrowEdge: .bottom) {
                            inspector.frame(width: 290, height: 490)
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    saveButton
                        .keyboardShortcut("s", modifiers: .command)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            openedLibraryRevision = app.libraryRevision
            app.selectedPromptID = prompt.id
            app.installEditorActions(owner: editorSessionID, copy: copyCurrent,
                                     toggleFavorite: { favorite.toggle() })
        }
        .onDisappear {
            app.clearEditorActions(owner: editorSessionID)
        }
        .onChange(of: prompt.isFavorite) { _, value in
            if favorite != value { favorite = value }
        }
        .onChange(of: prompt.folderID) { _, value in
            if folderID != value { folderID = value }
        }
        .onChange(of: prompt.tagNames) { _, value in
            if Set(parsedTags) != Set(value) { tagInput = value.joined(separator: ", ") }
        }
    }

    @ViewBuilder
    private var saveButton: some View {
        if #available(macOS 26.0, *) {
            Button("保存", role: .confirm, action: saveCurrent)
        } else {
            Button("保存", action: saveCurrent)
                .buttonStyle(.borderedProminent)
        }
    }

    private var editorPane: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 7) {
                TextField("提示词标题", text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 23, weight: .semibold))
                    .accessibilityLabel("Prompt 标题")
                Text("最后编辑 \(PromptPresentation.date(prompt.updatedAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !parsedTags.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: 6) {
                            ForEach(parsedTags, id: \.self) { tag in
                                Text("#\(tag)")
                                    .font(.system(size: 11))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(accent.controlFill, in: Capsule())
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    .frame(height: 24)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 22)
            .padding(.vertical, 15)

            VStack(spacing: 0) {
                formattingToolbar
                Divider()
                NativeTextEditor(text: $content, fontSize: editorFontSize,
                                 wrapLines: editorWrapLines, command: editorCommand)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Prompt 正文")
                if let saveError {
                    Divider()
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text("保存失败：\(saveError)")
                        Spacer()
                        Button("重试", action: saveCurrent)
                    }
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                }
            }
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.75)
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 10) {
                Text("共 \(content.count) 个字符")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button { onExport(title, content) } label: {
                    Label("导出…", systemImage: "square.and.arrow.up")
                }
                .appSecondaryAction()
                Button(action: copyCurrent) {
                    Label("复制 Prompt", systemImage: "doc.on.doc")
                }
                .appPrimaryAction()
            }
            .padding(.horizontal, 20)
            .frame(height: 58)
        }
    }

    private var formattingToolbar: some View {
        HStack(spacing: 11) {
            formatButton("标题 1", "textformat.size.larger", .heading1)
            formatButton("标题 2", "textformat.size", .heading2)
            Divider().frame(height: 16)
            formatButton("粗体", "bold", .bold)
            formatButton("斜体", "italic", .italic)
            formatButton("列表", "list.bullet", .bullet)
            formatButton("引用", "text.quote", .quote)
            formatButton("代码", "chevron.left.forwardslash.chevron.right", .code)
            formatButton("链接", "link", .link)
            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
    }

    private func formatButton(_ name: String, _ symbol: String,
                              _ action: MarkdownFormatAction) -> some View {
        Button { editorCommand = EditorCommand(action: action) } label: {
            Image(systemName: symbol).frame(width: 19, height: 24)
        }
        .buttonStyle(.plain)
        .modifier(EditorHoverSurface())
        .help(name)
        .accessibilityLabel(name)
    }

    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 17) {
                Text("封面").font(.system(size: 12, weight: .semibold))
                CoverPreview(image: coverImage)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .onDrop(of: [.fileURL, .image], isTargeted: nil, perform: receiveCover)
                HStack(spacing: 6) {
                    Button(coverImage == nil ? "添加封面" : "更换封面", action: chooseCover)
                    Button("粘贴", action: pasteCover)
                    if coverImage != nil {
                        Button("移除", role: .destructive) { removeCover() }
                    }
                }
                .appSecondaryAction()
                Divider()
                Text("标签").font(.system(size: 12, weight: .semibold))
                if !parsedTags.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: 6) {
                        ForEach(parsedTags, id: \.self) { tag in
                            Button { removeTag(tag) } label: {
                                Text("#\(tag) ×")
                                    .font(.system(size: 11))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(accent.controlFill, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .modifier(EditorHoverSurface())
                            .help("移除标签 \(tag)")
                        }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
                if addingTag {
                    TextField("输入标签后按回车", text: $pendingTag)
                        .textFieldStyle(.plain)
                        .padding(7)
                        .background(Color(nsColor: .textBackgroundColor),
                                    in: RoundedRectangle(cornerRadius: 6))
                        .focused($pendingTagFocused)
                        .onSubmit(addTag)
                        .accessibilityLabel("添加标签，最多 10 个")
                } else {
                    Button {
                        addingTag = true
                        pendingTagFocused = true
                    } label: { Label("添加标签", systemImage: "plus") }
                    .appSecondaryAction()
                    .disabled(parsedTags.count >= 10)
                }
                Divider()
                Text("保存位置").font(.system(size: 12, weight: .semibold))
                FolderPicker(folders: folders, selection: $folderID)
                Toggle("已收藏", isOn: $favorite)
                Divider()
                VStack(alignment: .leading, spacing: 5) {
                    Text("创建于 \(PromptPresentation.date(prompt.createdAt))")
                    if let last = prompt.lastUsedAt {
                        Text("最近使用 \(PromptPresentation.date(last))")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
    }

    private var parsedTags: [String] {
        tagInput.split(whereSeparator: { $0 == "," || $0 == "，" || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func removeTag(_ tag: String) {
        tagInput = parsedTags.filter { $0 != tag }.joined(separator: ", ")
    }

    private func addTag() {
        let names = pendingTag.split(whereSeparator: { $0 == "," || $0 == "，" || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard names.allSatisfy({ $0.count <= 20 }) else {
            onError("每个标签不能超过 20 字。")
            return
        }
        var updated = parsedTags
        for name in names where !updated.contains(name) && updated.count < 10 {
            updated.append(name)
        }
        tagInput = updated.joined(separator: ", ")
        pendingTag = ""
        addingTag = false
    }

    private func saveCurrent() {
        if saveDraft() { onBack() }
    }

    @discardableResult
    private func saveDraft() -> Bool {
        guard prompt.deletedAt == nil,
              openedLibraryRevision == app.libraryRevision else { return false }
        var stored: StoredCover?
        do {
            let resolved: String
            if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                resolved = (try? PromptLibrary.resolvedTitle(title, content: content)) ?? "未命名 Prompt"
            } else {
                resolved = title
            }
            let edited = prompt.title != resolved || prompt.content != content ||
                prompt.folderID != folderID ||
                Set(prompt.tagNames) != Set(parsedTags) || coverChanged
            guard edited || prompt.isFavorite != favorite else { saveError = nil; return true }
            if coverChanged, let coverImage {
                stored = try PromptStorage.saveCoverAsset(image: coverImage)
            }
            prompt.title = resolved
            prompt.content = content
            prompt.folderID = folderID
            prompt.isFavorite = favorite
            try PromptLibrary.setTags(parsedTags, for: prompt, in: context, save: false)
            if coverChanged {
                try PromptLibrary.setCover(stored, crop: .full, for: prompt, in: context, save: false)
            }
            if edited { prompt.updatedAt = .now }
            try context.save()
            saveError = nil
            return true
        } catch {
            context.rollback()
            if let stored { try? PromptStorage.removeCover(at: stored.relativePath) }
            saveError = error.localizedDescription
            return false
        }
    }

    private func copyCurrent() {
        app.requestCopy(prompt, content: content)
    }

    private func chooseCover() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK, let url = panel.url,
              let image = NSImage(contentsOf: url) else { return }
        replaceCover(with: image)
    }

    private func pasteCover() {
        guard let image = NSPasteboard.general.readObjects(forClasses: [NSImage.self])?.first as? NSImage else {
            onError("剪贴板中没有图片。")
            return
        }
        replaceCover(with: image)
    }

    private func replaceCover(with image: NSImage) {
        coverImage = image
        coverChanged = true
    }

    private func removeCover() {
        coverImage = nil
        coverChanged = true
    }

    private func receiveCover(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        if provider.canLoadObject(ofClass: NSImage.self) {
            _ = provider.loadObject(ofClass: NSImage.self) { image, _ in
                guard let image = image as? NSImage else { return }
                Task { @MainActor in replaceCover(with: image) }
            }
            return true
        }
        _ = provider.loadObject(ofClass: NSURL.self) { object, _ in
            guard let url = object as? URL, let image = NSImage(contentsOf: url) else { return }
            Task { @MainActor in replaceCover(with: image) }
        }
        return true
    }
}

struct EditorHoverSurface: ViewModifier {
    @Environment(\.appAccentStyle) private var accent
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .foregroundStyle(.primary)
            .padding(.horizontal, 5)
            .background(hovering ? accent.hoverFill : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6))
            .onHover { hovering = $0 }
    }
}

struct FolderPicker: View {
    let folders: [Folder]
    @Binding var selection: UUID?

    var body: some View {
        Picker("保存位置", selection: $selection) {
            Text("未分类").tag(UUID?.none)
            ForEach(folders.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) { folder in
                Text(path(for: folder)).tag(Optional(folder.id))
            }
        }
        .pickerStyle(.menu)
        .tint(.primary)
    }

    private func path(for folder: Folder) -> String {
        var names = [folder.name]
        var parent = folder.parentID
        var visited = Set<UUID>([folder.id])
        while let id = parent, let next = folders.first(where: { $0.id == id }), visited.insert(id).inserted {
            names.insert(next.name, at: 0)
            parent = next.parentID
        }
        return names.joined(separator: " / ")
    }
}

struct CoverPreview: View {
    let image: NSImage?

    var body: some View {
        GeometryReader { geometry in
            Group {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .background(Color(nsColor: .textBackgroundColor))
                } else {
                    VStack(spacing: 7) {
                        Image(systemName: "photo.badge.plus").font(.title2)
                        Text("拖入或选择封面图片").font(.caption)
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .textBackgroundColor))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.75)
        }
        .accessibilityLabel(image == nil ? "未添加封面" : "封面图片")
    }
}
