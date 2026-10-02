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
    let embedded: Bool
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

    init(prompt: Prompt, folders: [Folder], titlebarInset: CGFloat = 20, embedded: Bool = false,
         onBack: @escaping () -> Void,
         onExport: @escaping (String, String) -> Void,
         onError: @escaping (String) -> Void) {
        self.prompt = prompt
        self.folders = folders
        self.titlebarInset = titlebarInset
        self.embedded = embedded
        self.onBack = onBack
        self.onExport = onExport
        self.onError = onError
        _title = State(initialValue: prompt.title)
        _content = State(initialValue: prompt.content)
        _folderID = State(initialValue: prompt.folderID)
        _tagInput = State(initialValue: prompt.tagNames.joined(separator: ", "))
        _favorite = State(initialValue: prompt.isFavorite)
        _coverImage = State(initialValue: embedded ? nil : PromptPresentation.croppedImage(for: prompt))
    }

    var body: some View {
        GeometryReader { geometry in
            let wide = !embedded && geometry.size.width >= 840
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    if embedded { embeddedActions }
                    editorPane(compact: geometry.size.width < 540)
                }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if wide {
                    Divider()
                    inspector.frame(width: 270)
                }
            }
            .toolbar {
                if !embedded {
                    ToolbarItem(placement: .navigation) {
                        Button(action: onBack) { Label("返回", systemImage: "chevron.left") }
                            .help("返回资料库")
                    }
                    if #available(macOS 26.0, *) {
                        ToolbarSpacer(.flexible, placement: .primaryAction)
                    }
                    if !wide {
                        ToolbarItem(placement: .primaryAction) {
                            inspectorButton
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        saveButton
                            .keyboardShortcut("s", modifiers: .command)
                    }
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

    private var inspectorButton: some View {
        Button { showInspector.toggle() } label: {
            Label("详情", systemImage: "sidebar.right")
        }
        .help("封面、标签与保存位置")
        .popover(isPresented: $showInspector, arrowEdge: .bottom) {
            inspector.frame(width: 290, height: 490)
        }
    }

    private var embeddedActions: some View {
        HStack(spacing: 12) {
            Text("最后编辑 \(PromptPresentation.date(prompt.updatedAt))")
                .font(.caption).foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            Button { favorite.toggle() } label: {
                Image(systemName: favorite ? "star.fill" : "star")
                    .foregroundStyle(favorite ? accent.actionForeground : Color.primary)
            }
            .buttonStyle(.plain)
            .modifier(EditorHoverSurface())
            .help(favorite ? "取消收藏" : "收藏")
            .accessibilityLabel(favorite ? "取消收藏" : "收藏")
            Button("保存", action: saveCurrent)
                .appPrimaryAction()
                .keyboardShortcut("s", modifiers: .command)
        }
        .padding(.horizontal, 20)
        .frame(height: 36)
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

    private func editorPane(compact: Bool) -> some View {
        VStack(spacing: 0) {
            if embedded {
                embeddedMetadata(compact: compact)
            } else {
            VStack(alignment: .leading, spacing: 7) {
                TextField("提示词标题", text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: embedded ? 20 : 23, weight: .semibold))
                    .frame(height: embedded ? 30 : 34)
                    .accessibilityLabel("Prompt 标题")
                if !embedded {
                    Text("最后编辑 \(PromptPresentation.date(prompt.updatedAt))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
            }

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
                if embedded { exportButton.labelStyle(.iconOnly) }
                else { exportButton }
                Button(action: copyCurrent) {
                    Label("复制 Prompt", systemImage: "doc.on.doc")
                }
                .appPrimaryAction()
            }
            .padding(.horizontal, 20)
            .frame(height: 58)
        }
    }

    private func embeddedMetadata(compact: Bool) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                TextField("提示词标题", text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 20, weight: .semibold))
                    .frame(height: 30)
                    .help(title)
                    .accessibilityLabel("Prompt 标题")
                embeddedFolderControl
                embeddedTagControls
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            embeddedCover(width: compact ? 80 : 112)
        }
        .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 10)
    }

    private var embeddedFolderControl: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder").foregroundStyle(.secondary)
            FolderPicker(folders: folders, selection: $folderID)
                .labelsHidden()
                .frame(width: 160, alignment: .leading)
                .accessibilityLabel("保存位置")
        }
        .font(.system(size: 11))
        .frame(height: 26)
    }

    private var embeddedTagControls: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(parsedTags, id: \.self) { tag in
                    HStack(spacing: 5) {
                        Text("#\(tag)").lineLimit(1)
                        Button { removeTag(tag) } label: {
                            Image(systemName: "xmark").font(.system(size: 8, weight: .semibold))
                                .frame(width: 14, height: 18)
                        }
                        .buttonStyle(.plain)
                        .help("移除标签 \(tag)")
                        .accessibilityLabel("移除标签 \(tag)")
                    }
                    .font(.system(size: 11))
                    .padding(.leading, 8).padding(.trailing, 4).padding(.vertical, 3)
                    .background(accent.controlFill, in: Capsule())
                }
                addEmbeddedTagButton
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .scrollIndicators(.hidden)
        .frame(height: 26)
    }

    private var addEmbeddedTagButton: some View {
        Button {
            pendingTag = ""
            addingTag = true
        } label: {
            Label("添加标签", systemImage: "plus")
                .font(.system(size: 11))
        }
        .buttonStyle(.plain)
        .modifier(EditorHoverSurface())
        .fixedSize()
        .disabled(parsedTags.count >= 10)
        .popover(isPresented: $addingTag, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                Text("添加标签").font(.headline)
                TextField("标签，用逗号分隔", text: $pendingTag)
                    .textFieldStyle(.roundedBorder)
                    .focused($pendingTagFocused)
                    .onSubmit(addTag)
                    .accessibilityLabel("添加标签，最多 10 个")
                HStack {
                    Spacer()
                    Button("取消") { addingTag = false }
                    Button("添加", action: addTag).appPrimaryAction()
                        .disabled(pendingTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(16).frame(width: 280)
            .onAppear { pendingTagFocused = true }
        }
    }

    private func embeddedCover(width: CGFloat) -> some View {
        VStack(spacing: 4) {
            Button(action: chooseCover) {
                Group {
                    if coverChanged, let coverImage {
                        Image(nsImage: coverImage).resizable().scaledToFit()
                    } else if !coverChanged && hasCover {
                        CoverThumbnail(prompt: prompt, maxPixelSize: 384, prioritizeVisible: true) {
                            Image(systemName: "photo").foregroundStyle(.secondary)
                        }
                    } else {
                        Image(systemName: "photo.badge.plus").foregroundStyle(.secondary)
                    }
                }
                .frame(width: width, height: width * 9 / 16)
                .background(accent.controlFill, in: RoundedRectangle(cornerRadius: 5))
                .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            .help(hasCover ? "更换封面" : "添加封面")
            .accessibilityLabel(hasCover ? "更换封面" : "添加封面")
            .onDrop(of: [.fileURL, .image], isTargeted: nil, perform: receiveCover)
            HStack(spacing: 5) {
                coverAction("上传封面", "photo.badge.plus", chooseCover)
                coverAction("粘贴封面", "doc.on.clipboard", pasteCover)
                if hasCover { coverAction("移除封面", "trash", removeCover) }
            }
            .frame(height: 20)
        }
        .frame(width: width)
    }

    private func coverAction(_ name: String, _ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 11)) }
            .buttonStyle(.plain)
            .modifier(EditorHoverSurface())
            .help(name).accessibilityLabel(name)
    }

    private var exportButton: some View {
        Button { onExport(title, content) } label: {
            Label("导出…", systemImage: "square.and.arrow.up")
        }
        .appSecondaryAction()
        .help("导出提示词")
    }

    private var formattingToolbar: some View {
        HStack(spacing: embedded ? 5 : 11) {
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
                Group {
                    if embedded && !coverChanged && prompt.coverPath != nil {
                        CoverThumbnail(prompt: prompt, maxPixelSize: 768, prioritizeVisible: true) {
                            CoverPreview(image: nil)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    } else {
                        CoverPreview(image: coverImage)
                    }
                }
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .onDrop(of: [.fileURL, .image], isTargeted: nil, perform: receiveCover)
                HStack(spacing: 6) {
                    Button(hasCover ? "更换封面" : "添加封面", action: chooseCover)
                    Button("粘贴", action: pasteCover)
                    if hasCover {
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

    private var hasCover: Bool {
        coverChanged ? coverImage != nil : prompt.coverPath != nil
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
