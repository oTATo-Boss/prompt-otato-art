import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PromptCreateView: View {
    @AppStorage("defaultPromptFormat") private var defaultFormat = "markdown"
    @AppStorage("editorFontSize") private var editorFontSize = 16.0
    @AppStorage("editorWrapLines") private var editorWrapLines = true

    let folders: [Folder]
    let onCreate: (String, String, PromptFormat, UUID?, [String], Bool, NSImage?, CoverCrop) throws -> Void
    let onCancel: () -> Void

    @State private var title = ""
    @State private var content = ""
    @State private var format: PromptFormat = .markdown
    @State private var folderID: UUID?
    @State private var tags = ""
    @State private var isFavorite = false
    @State private var coverImage: NSImage?
    @State private var coverCrop = CoverCrop.full
    @State private var showCrop = false
    @State private var showDiscard = false
    @State private var errorMessage: String?
    @FocusState private var titleFocused: Bool

    init(folders: [Folder], initialFolderID: UUID?,
         onCreate: @escaping (String, String, PromptFormat, UUID?, [String], Bool, NSImage?, CoverCrop) throws -> Void,
         onCancel: @escaping () -> Void) {
        self.folders = folders
        self.onCreate = onCreate
        self.onCancel = onCancel
        _folderID = State(initialValue: initialFolderID)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: cancel) { Label("返回", systemImage: "chevron.left") }
                    .buttonStyle(.plain)
                Text("新建 Prompt").font(.system(size: 15, weight: .semibold))
                    .padding(.leading, 12)
                Spacer()
            }
            .padding(.horizontal, 18).frame(height: 60)
            Divider()
            GeometryReader { geometry in
                let wide = geometry.size.width >= 900
                HStack(spacing: 12) {
                    mainForm(wide: wide)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    inspector
                        .frame(width: wide ? 360 : 270)
                        .frame(maxHeight: .infinity)
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
            }
            Divider()
            HStack {
                Spacer()
                Button("取消", action: cancel)
                    .frame(minWidth: 92)
                Button("创建 Prompt", action: create)
                    .buttonStyle(.borderedProminent)
                    .frame(minWidth: 120)
                    .disabled((title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                               content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ||
                              title.count > 50 || parsedTags.count > 10)
            }
            .controlSize(.large)
            .padding(.horizontal, 20).frame(height: 60)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            format = PromptFormat(rawValue: defaultFormat) ?? .markdown
            titleFocused = true
        }
        .confirmationDialog("放弃新建 Prompt？", isPresented: $showDiscard) {
            Button("放弃更改", role: .destructive, action: onCancel)
            Button("继续编辑", role: .cancel) {}
        } message: { Text("尚未创建的内容将会丢失。") }
        .alert("无法创建 Prompt", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "未知错误") }
        .sheet(isPresented: $showCrop) {
            if let coverImage {
                CoverCropSheet(image: coverImage, initialCrop: coverCrop) { crop in
                    coverCrop = crop
                    showCrop = false
                } onCancel: { showCrop = false }
            }
        }
    }

    private func mainForm(wide: Bool) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                LabeledContent("标题") {
                    VStack(alignment: .trailing, spacing: 4) {
                        TextField("输入标题", text: $title)
                            .textFieldStyle(.roundedBorder)
                            .focused($titleFocused)
                            .accessibilityLabel("Prompt 标题")
                        Text("\(title.count)/50")
                            .font(.caption2)
                            .foregroundStyle(title.count > 50 ? Color.red : Color.secondary)
                    }
                }
                LabeledContent("保存位置") {
                    FolderPicker(folders: folders, selection: $folderID)
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                LabeledContent("标签") {
                    VStack(alignment: .leading, spacing: 5) {
                        TextField("输入标签，用逗号分隔", text: $tags)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("标签")
                            .onSubmit {
                                if !tags.isEmpty && !tags.hasSuffix(", ") { tags += ", " }
                            }
                        HStack {
                            Text("例如：风景、摄影、Midjourney")
                            Spacer(minLength: 4)
                            Text("\(parsedTags.count)/10")
                                .foregroundStyle(parsedTags.count > 10 ? Color.red : Color.secondary)
                        }
                        .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                LabeledContent("输出格式") {
                    Picker("输出格式", selection: $format) {
                        Text("Markdown").tag(PromptFormat.markdown)
                        Text("TXT").tag(PromptFormat.txt)
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 190)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Prompt 内容").font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Text("\(content.count) / 100,000")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    NativeTextEditor(text: $content, fontSize: editorFontSize,
                                     wrapLines: editorWrapLines)
                        .frame(minHeight: 220)
                        .padding(7)
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                        .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5) }
                        .accessibilityLabel("Prompt 正文")
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("快速模板").font(.system(size: 12, weight: .semibold))
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8),
                                             count: wide ? 4 : 2), spacing: 8) {
                        templateButton("图片生成", "photo", "风格、场景、构图", """
                                # 角色
                                描述主体：{{主体}}

                                # 场景
                                {{场景}}

                                # 要求
                                - 风格：{{风格}}
                                - 光线：
                                - 构图：
                                """)
                        templateButton("视频提示词", "film", "分镜、运镜、时长", """
                                # 场景
                                {{场景}}

                                # 镜头运动
                                - 景别：
                                - 运镜：

                                # 风格与节奏
                                {{风格}}
                                """)
                        templateButton("文案", "text.alignleft", "营销、标题、脚本", """
                                # 目标
                                {{目标}}

                                # 受众
                                {{受众}}

                                # 语气
                                {{语气}}

                                # 正文
                                """)
                        templateButton("角色设定", "person.crop.square", "人设、性格、背景", """
                                # 角色
                                姓名：{{姓名}}
                                背景：
                                性格：

                                # 目标与冲突
                                目标：
                                冲突：

                                # 语言风格
                                """)
                    }
                }
            }
            .padding(20)
        }
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(Color(nsColor: .separatorColor).opacity(0.45)) }
    }

    private var inspector: some View {
        ScrollView {
            VStack(spacing: 12) {
                inspectorCard {
                    Text("添加封面").font(.system(size: 13, weight: .semibold))
                    CoverPreview(image: coverImage.map { PromptPresentation.crop($0, to: coverCrop) })
                        .frame(height: 180)
                        .onDrop(of: [.fileURL, .image], isTargeted: nil, perform: receiveCover)
                        .overlay {
                            if coverImage == nil {
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(Color(nsColor: .separatorColor),
                                                  style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                            }
                        }
                    Text("支持 JPG、PNG、WEBP；建议 16:10 比例")
                        .font(.caption2).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Button(action: chooseCover) {
                            Label("上传图片", systemImage: "photo")
                                .frame(maxWidth: .infinity, minHeight: 27)
                        }
                        .buttonStyle(.borderedProminent)
                        Button(action: pasteCover) {
                            Text("从剪贴板粘贴")
                                .frame(maxWidth: .infinity, minHeight: 27)
                        }
                        .buttonStyle(.bordered)
                    }
                    .controlSize(.regular)
                    if coverImage != nil {
                        HStack(spacing: 12) {
                            Button("重新裁切") { showCrop = true }
                            Button("移除", role: .destructive) { coverImage = nil }
                        }
                        .buttonStyle(.plain).font(.caption)
                    }
                }
                inspectorCard {
                    HStack(spacing: 5) {
                        Text("变量预览").font(.system(size: 13, weight: .semibold))
                        Image(systemName: "questionmark.circle")
                            .foregroundStyle(.secondary)
                            .help("在正文中使用双花括号标记变量，复制时填写。")
                        Spacer()
                    }
                    Group {
                        if PromptTemplate.variables(in: content).isEmpty {
                            Text("在正文中输入 {{变量名}}，复制时可填写。")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            FlowVariableList(names: PromptTemplate.variables(in: content))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
                }
                inspectorCard {
                    Text("其他设置").font(.system(size: 13, weight: .semibold))
                    Toggle(isOn: $isFavorite) {
                        Label("创建后加入收藏", systemImage: "star")
                    }
                    .toggleStyle(.switch)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 8)
        }
    }

    private func inspectorCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12, content: content)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.45))
            }
    }

    private func templateButton(_ name: String, _ symbol: String,
                                _ description: String, _ template: String) -> some View {
        Button {
            if !content.isEmpty && !content.hasSuffix("\n") { content += "\n\n" }
            content += template
        } label: {
            HStack(spacing: 7) {
                Image(systemName: symbol).font(.system(size: 15))
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 3) {
                    Text(name).font(.system(size: 11, weight: .medium))
                    Text(description).font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 9).frame(height: 56)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.45),
                            in: RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.65))
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("插入\(name)模板")
    }

    private func create() {
        do {
            try onCreate(title, content, format, folderID, parsedTags, isFavorite, coverImage, coverCrop)
        } catch {
            errorMessage = error.localizedDescription
            titleFocused = true
        }
    }

    private var parsedTags: [String] {
        tags.split(whereSeparator: { $0 == "," || $0 == "，" || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
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
        coverImage = image; coverCrop = .full; showCrop = true
    }

    private func pasteCover() {
        guard let image = NSPasteboard.general.readObjects(forClasses: [NSImage.self])?.first as? NSImage else {
            errorMessage = "剪贴板中没有图片。"
            return
        }
        coverImage = image; coverCrop = .full; showCrop = true
    }

    private func receiveCover(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        if provider.canLoadObject(ofClass: NSImage.self) {
            _ = provider.loadObject(ofClass: NSImage.self) { image, _ in
                guard let image = image as? NSImage else { return }
                Task { @MainActor in coverImage = image; coverCrop = .full; showCrop = true }
            }
            return true
        }
        _ = provider.loadObject(ofClass: NSURL.self) { object, _ in
            guard let url = object as? URL, let image = NSImage(contentsOf: url) else { return }
            Task { @MainActor in coverImage = image; coverCrop = .full; showCrop = true }
        }
        return true
    }
}

private struct FlowVariableList: View {
    let names: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(names, id: \.self) { name in
                Text("{{\(name)}}")
                    .font(.system(size: 11, design: .monospaced))
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Color(nsColor: .quaternaryLabelColor).opacity(0.15), in: Capsule())
            }
        }
    }
}
