import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PromptCreateView: View {
    @AppStorage("editorFontSize") private var editorFontSize = 16.0
    @AppStorage("editorWrapLines") private var editorWrapLines = true

    let folders: [Folder]
    let titlebarInset: CGFloat
    let onCreate: (String, String, PromptFormat, UUID?, [String], Bool, NSImage?, CoverCrop) throws -> Void
    let onCancel: () -> Void

    @State private var title = ""
    @State private var content = ""
    @State private var folderID: UUID?
    @State private var tags = ""
    @State private var isFavorite = false
    @State private var coverImage: NSImage?
    @State private var coverHovering = false
    @State private var coverDropTargeted = false
    @State private var showCover = false
    @State private var showDiscard = false
    @State private var errorMessage: String?
    @State private var editorCommand: EditorCommand?

    init(folders: [Folder], initialFolderID: UUID?, titlebarInset: CGFloat = 20,
         onCreate: @escaping (String, String, PromptFormat, UUID?, [String], Bool, NSImage?, CoverCrop) throws -> Void,
         onCancel: @escaping () -> Void) {
        self.folders = folders
        self.titlebarInset = titlebarInset
        self.onCreate = onCreate
        self.onCancel = onCancel
        _folderID = State(initialValue: initialFolderID)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: cancel) { Label("返回", systemImage: "chevron.left") }
                    .buttonStyle(.plain)
                    .modifier(EditorHoverSurface())
                Text("新建 Prompt")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
            }
            .padding(.leading, titlebarInset)
            .padding(.trailing, 20)
            .frame(height: 60)
            Divider()

            VStack(alignment: .leading, spacing: 14) {
                metadata
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Prompt 内容")
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Text("\(content.count) / 100,000")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 32)
                    Divider()
                    formattingToolbar
                    Divider()
                    NativeTextEditor(text: $content, fontSize: editorFontSize,
                                     wrapLines: editorWrapLines, command: editorCommand)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityLabel("Prompt 正文")
                }
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 0.5)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Divider()
            HStack {
                Spacer()
                Button("取消", action: cancel)
                    .frame(minWidth: 80)
                Button("创建 Prompt", action: create)
                    .buttonStyle(.borderedProminent)
                    .frame(minWidth: 118)
                    .disabled((title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                               content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ||
                              title.count > 50 || content.count > 100_000 || parsedTags.count > 10)
            }
            .controlSize(.regular)
            .padding(.horizontal, 20)
            .frame(height: 58)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .confirmationDialog("放弃新建 Prompt？", isPresented: $showDiscard) {
            Button("放弃更改", role: .destructive, action: onCancel)
            Button("继续编辑", role: .cancel) {}
        } message: { Text("尚未创建的内容将会丢失。") }
        .alert("无法创建 Prompt", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "未知错误") }
    }

    private var metadata: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("标题")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextField("输入标题", text: $title)
                        .textFieldStyle(.plain)
                        .font(.system(size: 21, weight: .semibold))
                        .frame(height: 38)
                        .accessibilityLabel("Prompt 标题")
                }

                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("保存位置")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        FolderPicker(folders: folders, selection: $folderID)
                            .labelsHidden()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(height: 30)
                    }
                    .frame(width: 160, alignment: .leading)

                    VStack(alignment: .leading, spacing: 5) {
                        Text("标签")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        TextField("添加标签，用逗号分隔", text: $tags)
                            .textFieldStyle(.plain)
                            .frame(height: 30)
                            .accessibilityLabel("标签")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("封面")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button { isFavorite.toggle() } label: {
                        Image(systemName: isFavorite ? "star.fill" : "star")
                            .frame(width: 18, height: 16)
                    }
                    .buttonStyle(.plain)
                    .modifier(EditorHoverSurface())
                    .accessibilityLabel(isFavorite ? "取消收藏" : "创建后加入收藏")
                    .help(isFavorite ? "取消收藏" : "创建后加入收藏")
                }
                coverThumbnail
            }
            .frame(width: 144)
        }
    }

    private var coverThumbnail: some View {
        Button { showCover.toggle() } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(coverHovering || coverDropTargeted ? 0.065 : 0.025))
                if let coverImage {
                    Image(nsImage: coverImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 144, height: 81)
                } else {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 144, height: 81)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 0.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { coverHovering = $0 }
        .onDrop(of: [.fileURL, .image], isTargeted: $coverDropTargeted, perform: receiveCover)
        .popover(isPresented: $showCover, arrowEdge: .bottom) { coverPopover }
        .accessibilityLabel(coverImage == nil ? "添加封面" : "更换封面")
        .help("添加或更换封面")
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
        .frame(height: 34)
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

    private var coverPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("封面").font(.headline)
            CoverPreview(image: coverImage)
                .aspectRatio(16 / 9, contentMode: .fit)
                .onDrop(of: [.fileURL, .image], isTargeted: nil, perform: receiveCover)
            HStack {
                Button("选择图片", action: chooseCover)
                Button("从剪贴板粘贴", action: pasteCover)
                if coverImage != nil {
                    Button("移除", role: .destructive) { coverImage = nil }
                }
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .frame(width: 330)
    }

    private var parsedTags: [String] {
        tags.split(whereSeparator: { $0 == "," || $0 == "，" || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func create() {
        do {
            try onCreate(title, content, .markdown, folderID, parsedTags,
                         isFavorite, coverImage, .full)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func cancel() {
        if title.isEmpty && content.isEmpty && tags.isEmpty && coverImage == nil {
            onCancel()
        } else { showDiscard = true }
    }

    private func chooseCover() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK, let url = panel.url,
              let image = NSImage(contentsOf: url) else { return }
        coverImage = image
    }

    private func pasteCover() {
        guard let image = NSPasteboard.general.readObjects(forClasses: [NSImage.self])?.first as? NSImage else {
            errorMessage = "剪贴板中没有图片。"
            return
        }
        coverImage = image
    }

    private func receiveCover(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        if provider.canLoadObject(ofClass: NSImage.self) {
            _ = provider.loadObject(ofClass: NSImage.self) { image, _ in
                guard let image = image as? NSImage else { return }
                Task { @MainActor in coverImage = image }
            }
            return true
        }
        _ = provider.loadObject(ofClass: NSURL.self) { object, _ in
            guard let url = object as? URL, let image = NSImage(contentsOf: url) else { return }
            Task { @MainActor in coverImage = image }
        }
        return true
    }
}

#if DEBUG
#Preview("新建 · 深色紧凑", traits: .fixedLayout(width: 650, height: 560)) {
    PromptCreateView(folders: [], initialFolderID: nil,
                     onCreate: { _, _, _, _, _, _, _, _ in }, onCancel: {})
        .preferredColorScheme(.dark)
        .environment(\.appAccentStyle, AppAccentStyle(palette: .monochrome, colorScheme: .dark))
        .tint(AppAccentStyle(palette: .monochrome, colorScheme: .dark).tint)
}

#Preview("新建 · 浅色紧凑", traits: .fixedLayout(width: 650, height: 560)) {
    PromptCreateView(folders: [], initialFolderID: nil,
                     onCreate: { _, _, _, _, _, _, _, _ in }, onCancel: {})
        .preferredColorScheme(.light)
        .environment(\.appAccentStyle, AppAccentStyle(palette: .monochrome, colorScheme: .light))
        .tint(AppAccentStyle(palette: .monochrome, colorScheme: .light).tint)
}
#endif
