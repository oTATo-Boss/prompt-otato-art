import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct PromptEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var app: AppCoordinator
    @AppStorage("editorFontSize") private var editorFontSize = 16.0
    @AppStorage("editorWrapLines") private var editorWrapLines = true
    @AppStorage("editorPreviewEnabled") private var previewOnOpen = false

    let prompt: Prompt
    let folders: [Folder]
    let onBack: () -> Void
    let onCopy: () -> Void
    let onExport: () -> Void
    let onError: (String) -> Void

    @State private var title: String
    @State private var content: String
    @State private var format: PromptFormat
    @State private var folderID: UUID?
    @State private var tagInput: String
    @State private var pendingTag = ""
    @State private var addingTag = false
    @State private var showHeaderTagInput = false
    @State private var favorite: Bool
    @State private var preview = false
    @State private var showCrop = false
    @State private var cropImage: NSImage?
    @State private var cropInitial = CoverCrop.full
    @State private var recropping = false
    @State private var saveTask: Task<Void, Never>?
    @State private var saveError: String?
    @State private var insertion: EditorInsertion?
    @State private var openedLibraryRevision: Int?
    @State private var editorSessionID = UUID()
    @FocusState private var pendingTagFocused: Bool
    @FocusState private var headerTagFocused: Bool

    init(prompt: Prompt, folders: [Folder], onBack: @escaping () -> Void,
         onCopy: @escaping () -> Void, onExport: @escaping () -> Void,
         onError: @escaping (String) -> Void) {
        self.prompt = prompt
        self.folders = folders
        self.onBack = onBack
        self.onCopy = onCopy
        self.onExport = onExport
        self.onError = onError
        _title = State(initialValue: prompt.title)
        _content = State(initialValue: prompt.content)
        _format = State(initialValue: prompt.format)
        _folderID = State(initialValue: prompt.folderID)
        _tagInput = State(initialValue: prompt.tagNames.joined(separator: ", "))
        _favorite = State(initialValue: prompt.isFavorite)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    if flush(finalizeTitle: true) { onBack() }
                } label: { Label("返回", systemImage: "chevron.left") }
                .buttonStyle(.plain)
                Spacer()
                Button(action: copyCurrent) { Label("复制 Prompt", systemImage: "doc.on.doc") }
                    .buttonStyle(.bordered)
            }
            .padding(.horizontal, 18).frame(height: 60)
            Divider()

            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    editorHeader
                    Divider()
                    editorBody
                        .background(Color(nsColor: .textBackgroundColor),
                                    in: RoundedRectangle(cornerRadius: 8))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.7))
                        }
                        .padding(.horizontal, 22)
                        .padding(.bottom, 14)
                    Divider()
                    editorFooter
                }
                .frame(maxWidth: .infinity)
                Divider()
                inspector
                    .frame(width: 300)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            openedLibraryRevision = app.libraryRevision
            preview = previewOnOpen && format == .markdown
            app.selectedPromptID = prompt.id
            app.installEditorFlush(owner: editorSessionID) { flush(finalizeTitle: true) }
        }
        .onDisappear {
            saveTask?.cancel()
            if openedLibraryRevision == app.libraryRevision && prompt.deletedAt == nil {
                _ = flush(finalizeTitle: true)
            }
            app.clearEditorFlush(owner: editorSessionID)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { saveTask?.cancel(); flush(finalizeTitle: true) }
        }
        .onChange(of: title) { _, _ in scheduleSave() }
        .onChange(of: content) { _, _ in scheduleSave() }
        .onChange(of: format) { _, _ in scheduleSave() }
        .onChange(of: folderID) { _, _ in scheduleSave() }
        .onChange(of: tagInput) { _, _ in scheduleSave() }
        .onChange(of: favorite) { _, _ in scheduleSave() }
        .onChange(of: prompt.isFavorite) { _, value in
            if favorite != value { favorite = value }
        }
        .onChange(of: prompt.folderID) { _, value in
            if folderID != value { folderID = value }
        }
        .onChange(of: prompt.tagNames) { _, value in
            let names = value.joined(separator: ", ")
            if Set(parsedTags) != Set(value) { tagInput = names }
        }
        .sheet(isPresented: $showCrop) {
            if let cropImage {
                CoverCropSheet(image: cropImage, initialCrop: cropInitial) { crop in
                    do {
                        if recropping {
                            try PromptLibrary.setCoverCrop(crop, for: prompt, in: context)
                        } else {
                            let stored = try PromptStorage.saveCoverAsset(image: cropImage)
                            try PromptLibrary.setCover(stored, crop: crop, for: prompt, in: context)
                        }
                    } catch { onError(error.localizedDescription) }
                    showCrop = false
                } onCancel: { showCrop = false }
            }
        }
    }

    private var editorHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                TextField("提示词标题", text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 23, weight: .semibold))
                    .accessibilityLabel("Prompt 标题")
                Text(PromptPresentation.date(prompt.updatedAt))
                    .font(.caption).foregroundStyle(.secondary)
            }
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(parsedTags, id: \.self) { tag in
                        Text("#\(tag)")
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .background(Color.primary.opacity(0.075), in: Capsule())
                    }
                    if parsedTags.isEmpty {
                        Text("添加标签可更快找到它")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                    Button {
                        showHeaderTagInput = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 26, height: 24)
                            .background(Color.primary.opacity(0.075), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(parsedTags.count >= 10)
                    .help("添加标签")
                    .accessibilityLabel("添加标签")
                    .popover(isPresented: $showHeaderTagInput, arrowEdge: .bottom) {
                        HStack(spacing: 8) {
                            TextField("输入标签", text: $pendingTag)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 180)
                                .focused($headerTagFocused)
                                .onSubmit {
                                    addTag()
                                    showHeaderTagInput = false
                                }
                            Button("添加") {
                                addTag()
                                showHeaderTagInput = false
                            }
                            .disabled(pendingTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        .padding(12)
                        .onAppear { headerTagFocused = true }
                    }
                }
            }
            .scrollIndicators(.hidden)
            .frame(height: 24)
        }
        .padding(.horizontal, 22).padding(.vertical, 27)
    }

    private var editorBody: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Picker("格式", selection: $format) {
                    Text("Markdown").tag(PromptFormat.markdown)
                    Text("TXT").tag(PromptFormat.txt)
                }
                .pickerStyle(.menu).frame(width: 125)
                if format == .markdown && !preview {
                    Divider().frame(height: 18)
                    formattingButton("粗体", "bold", "**加粗文本**")
                    formattingButton("斜体", "italic", "*斜体文本*")
                    formattingButton("代码", "chevron.left.forwardslash.chevron.right", "`代码`")
                    formattingButton("链接", "link", "[链接文字](https://)")
                    formattingButton("列表", "list.bullet", "- 列表项")
                    formattingButton("引用", "text.quote", "> 引用")
                }
                Spacer()
                if format == .markdown {
                    Button(preview ? "编辑" : "预览") { preview.toggle() }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(preview ? "返回源文编辑" : "预览 Markdown")
                }
            }
            .controlSize(.small)
            .padding(.horizontal, 20).frame(height: 38)
            Divider()
            Group {
                if preview && format == .markdown {
                    ScrollView {
                        Text(markdownAttributed)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .textSelection(.enabled)
                            .padding(22)
                    }
                } else {
                    NativeTextEditor(text: $content, fontSize: editorFontSize,
                                     wrapLines: editorWrapLines,
                                     insertion: insertion)
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .accessibilityLabel("Prompt 正文")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let saveError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text("保存失败：\(saveError)")
                    Spacer()
                    Button("重试") { flush(finalizeTitle: false) }
                }
                .font(.caption).foregroundStyle(.red)
                .padding(.horizontal, 20).padding(.vertical, 8)
            }
        }
    }

    private var editorFooter: some View {
        HStack(spacing: 8) {
            Text("共 \(content.count) 个字符")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize()
            Spacer(minLength: 4)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    if format == .markdown {
                        Button {
                            preview.toggle()
                        } label: {
                            Label(preview ? "编辑" : "预览", systemImage: preview ? "pencil" : "eye")
                                .frame(minWidth: 72, minHeight: 28)
                        }
                        .buttonStyle(.bordered)
                    }
                    Button {
                        if flush(finalizeTitle: true) { onExport() }
                    } label: {
                        Label("导出…", systemImage: "square.and.arrow.up")
                            .frame(minWidth: 76, minHeight: 28)
                    }
                    .buttonStyle(.bordered)
                    Button(action: copyCurrent) {
                        Label("复制 Prompt", systemImage: "doc.on.doc")
                            .frame(minWidth: 118, minHeight: 28)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .fixedSize()
                HStack(spacing: 6) {
                    if format == .markdown {
                        Button { preview.toggle() } label: {
                            Image(systemName: preview ? "pencil" : "eye")
                                .frame(minWidth: 26, minHeight: 28)
                        }
                        .help(preview ? "编辑" : "预览")
                        .accessibilityLabel(preview ? "编辑" : "预览")
                        .buttonStyle(.bordered)
                    }
                    Button {
                        if flush(finalizeTitle: true) { onExport() }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .frame(minWidth: 26, minHeight: 28)
                    }
                    .help("导出…")
                    .accessibilityLabel("导出…")
                    .buttonStyle(.bordered)
                    Button(action: copyCurrent) {
                        Label("复制 Prompt", systemImage: "doc.on.doc")
                            .frame(minWidth: 100, minHeight: 28)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .fixedSize()
            }
        }
        .controlSize(.regular)
        .padding(.horizontal, 20).frame(height: 56)
    }

    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("封面").font(.system(size: 12, weight: .semibold))
                CoverPreview(image: PromptPresentation.croppedImage(for: prompt))
                    .frame(height: 160)
                    .onDrop(of: [.fileURL, .image], isTargeted: nil, perform: receiveCover)
                    .overlay(alignment: .topTrailing) {
                        Menu {
                            if prompt.coverPath != nil {
                                Button("裁切封面", systemImage: "crop.rotate") { recropCover() }
                            }
                            Button("从剪贴板粘贴", systemImage: "doc.on.clipboard") { pasteCover() }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 14, weight: .semibold))
                                .frame(width: 30, height: 30)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7))
                        }
                        .menuStyle(.borderlessButton)
                        .accessibilityLabel("更多封面操作")
                        .padding(8)
                    }
                HStack(spacing: 8) {
                    Button(action: chooseCover) {
                        Label(prompt.coverPath == nil ? "添加封面" : "更换封面", systemImage: "photo")
                            .frame(maxWidth: .infinity, minHeight: 30)
                    }
                    if prompt.coverPath != nil {
                        Button {
                            do { try PromptLibrary.setCover(nil, for: prompt, in: context) }
                            catch { onError(error.localizedDescription) }
                        } label: {
                            Label("移除", systemImage: "trash")
                                .frame(maxWidth: .infinity, minHeight: 30)
                        }
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                Divider()
                Text("标签").font(.system(size: 12, weight: .semibold))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), spacing: 7)],
                          alignment: .leading, spacing: 8) {
                    ForEach(parsedTags, id: \.self) { tag in
                        Button { removeTag(tag) } label: {
                            Text("#\(tag)")
                                .font(.system(size: 12))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 7)
                                .background(Color.primary.opacity(0.07), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .help("移除标签 \(tag)")
                        .accessibilityLabel("移除标签 \(tag)")
                    }
                    Button {
                        addingTag = true
                        pendingTagFocused = true
                    } label: {
                        Label("添加标签", systemImage: "plus")
                            .font(.system(size: 12))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 7)
                            .background(Color.primary.opacity(0.07), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(parsedTags.count >= 10)
                }
                .padding(9)
                .background(Color(nsColor: .textBackgroundColor),
                            in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.7))
                }
                if addingTag {
                    TextField("输入标签后按回车", text: $pendingTag)
                        .textFieldStyle(.roundedBorder)
                        .focused($pendingTagFocused)
                        .onSubmit(addTag)
                        .accessibilityLabel("添加标签，最多 10 个")
                }
                Text("最多 10 个，每个不超过 20 字")
                    .font(.caption2).foregroundStyle(.secondary)
                Divider()
                Text("分类").font(.system(size: 12, weight: .semibold))
                FolderPicker(folders: folders, selection: $folderID)
                Divider()
                Toggle("已收藏", isOn: $favorite)
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    LabeledContent("创建时间", value: PromptPresentation.date(prompt.createdAt))
                    LabeledContent("最后编辑", value: PromptPresentation.date(prompt.updatedAt))
                    if let last = prompt.lastUsedAt {
                        LabeledContent("最后使用", value: PromptPresentation.date(last))
                    }
                }
                .font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 32)
            .padding(.bottom, 16)
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

    private var markdownAttributed: AttributedString {
        (try? AttributedString(markdown: content)) ?? AttributedString(content)
    }

    private func formattingButton(_ name: String, _ symbol: String, _ snippet: String) -> some View {
        Button {
            insertion = EditorInsertion(text: snippet)
        } label: { Image(systemName: symbol) }
            .buttonStyle(.borderless)
            .help(name)
            .accessibilityLabel("插入\(name)")
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            if !Task.isCancelled { flush(finalizeTitle: false) }
        }
    }

    @discardableResult
    private func flush(finalizeTitle: Bool) -> Bool {
        guard prompt.deletedAt == nil,
              openedLibraryRevision == app.libraryRevision else { return false }
        do {
            guard title.count <= 100 else {
                throw PromptLibraryError.invalidTitle
            }
            let resolved: String
            if finalizeTitle && title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                resolved = (try? PromptLibrary.resolvedTitle(title, content: content)) ?? "未命名 Prompt"
            } else {
                resolved = title
            }
            let changed = prompt.title != resolved || prompt.content != content ||
                prompt.format != format || prompt.folderID != folderID ||
                prompt.isFavorite != favorite || Set(prompt.tagNames) != Set(parsedTags)
            guard changed else { saveError = nil; return true }
            prompt.title = resolved
            prompt.content = content
            prompt.format = format
            prompt.folderID = folderID
            prompt.isFavorite = favorite
            try PromptLibrary.setTags(parsedTags, for: prompt, in: context)
            prompt.updatedAt = .now
            try context.save()
            saveError = nil
            return true
        } catch {
            context.rollback()
            saveError = error.localizedDescription
            return false
        }
    }

    private func copyCurrent() {
        if flush(finalizeTitle: true) { onCopy() }
    }

    private func chooseCover() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.canChooseFiles = true
        guard panel.runModal() == .OK, let url = panel.url,
              let image = NSImage(contentsOf: url) else { return }
        cropImage = image; cropInitial = .full; recropping = false; showCrop = true
    }

    private func pasteCover() {
        guard let image = NSPasteboard.general.readObjects(forClasses: [NSImage.self])?.first as? NSImage else {
            onError("剪贴板中没有图片。")
            return
        }
        cropImage = image; cropInitial = .full; recropping = false; showCrop = true
    }

    private func recropCover() {
        guard let path = prompt.coverPath, let image = PromptStorage.loadCover(at: path) else { return }
        cropImage = image; cropInitial = prompt.coverCrop; recropping = true; showCrop = true
    }

    private func receiveCover(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        if provider.canLoadObject(ofClass: NSImage.self) {
            _ = provider.loadObject(ofClass: NSImage.self) { image, _ in
                guard let image = image as? NSImage else { return }
                Task { @MainActor in
                    cropImage = image; cropInitial = .full; recropping = false; showCrop = true
                }
            }
            return true
        }
        _ = provider.loadObject(ofClass: NSURL.self) { object, _ in
            guard let url = object as? URL, let image = NSImage(contentsOf: url) else { return }
            Task { @MainActor in
                cropImage = image; cropInitial = .full; recropping = false; showCrop = true
            }
        }
        return true
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
                    Image(nsImage: image).resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
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
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5) }
    }
}

struct CoverCropSheet: View {
    let image: NSImage
    let initialCrop: CoverCrop
    let onApply: (CoverCrop) -> Void
    let onCancel: () -> Void
    @State private var zoom = 1.0
    @State private var horizontal = 0.5
    @State private var vertical = 0.5

    private var baseSize: (Double, Double) {
        let ratio = image.size.width / max(image.size.height, 1)
        return ratio >= 1.6 ? (1.6 / ratio, 1) : (1, ratio / 1.6)
    }
    private var crop: CoverCrop {
        let width = baseSize.0 / zoom, height = baseSize.1 / zoom
        return CoverCrop(x: (1 - width) * horizontal, y: (1 - height) * vertical,
                         width: width, height: height)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("裁切封面").font(.title3.weight(.semibold))
            CoverPreview(image: PromptPresentation.crop(image, to: crop))
                .frame(width: 480, height: 300)
            LabeledContent("缩放") { Slider(value: $zoom, in: 1...3).frame(width: 300) }
            LabeledContent("水平位置") { Slider(value: $horizontal, in: 0...1).frame(width: 300) }
            LabeledContent("垂直位置") { Slider(value: $vertical, in: 0...1).frame(width: 300) }
            HStack {
                Text("封面将以 16:10 显示").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("取消", action: onCancel)
                Button("使用封面") { onApply(crop) }.buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .onAppear {
            zoom = max(1, min(3, baseSize.0 / initialCrop.width))
            horizontal = initialCrop.x / max(1 - initialCrop.width, 0.001)
            vertical = initialCrop.y / max(1 - initialCrop.height, 0.001)
        }
    }
}
