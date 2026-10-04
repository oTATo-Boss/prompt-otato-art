import SwiftUI

struct PromptFilterPanel: View {
    @Binding var filter: PromptLibraryFilter
    let tags: [PromptTagFilterOption]
    let resultCount: Int
    let scopeTitle: String
    let onDone: () -> Void

    @State private var tagQuery = ""
    @State private var tagMode = TagSelectionMode.include
    @FocusState private var tagSearchFocused: Bool
    @Environment(\.appAccentStyle) private var accent

    private enum TagSelectionMode: String, CaseIterable, Identifiable {
        case include = "包含标签"
        case exclude = "排除标签"
        var id: Self { self }
    }

    private var visibleTags: [PromptTagFilterOption] {
        let query = tagQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? tags : tags.filter { $0.name.localizedStandardContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            VStack(spacing: 10) {
                tagSearch
                tagControls
                tagChoices
                Divider()
                VStack(spacing: 8) {
                    PromptFilterChoiceRow(title: "收藏", value: $filter.favorite)
                    PromptFilterChoiceRow(title: "封面", value: $filter.cover)
                    PromptFilterChoiceRow(title: "更新时间", value: $filter.updated)
                    PromptFilterChoiceRow(title: "标签状态", value: Binding(
                        get: { filter.tagPresence },
                        set: { filter.setTagPresence($0) }
                    ))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            Divider()
            HStack {
                Button { filter.reset() } label: {
                    Text("清除筛选")
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                }
                    .buttonStyle(PromptFilterQuietButtonStyle())
                    .disabled(!filter.isActive)
                Spacer()
                Button("完成", action: onDone)
                    .appPrimaryAction()
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .frame(height: 48)
        }
        .frame(width: 420)
        .frame(maxHeight: 530)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(accent.tint)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 10) {
                Text("筛选提示词")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("\(resultCount) 条结果")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("筛选结果：\(resultCount) 条提示词")
                Button(action: onDone) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(PromptFilterQuietButtonStyle())
                .accessibilityLabel("关闭筛选面板")
                .help("关闭筛选面板，保留当前筛选条件")
            }
            Text("筛选范围：\(scopeTitle)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private var tagSearch: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜索标签", text: $tagQuery)
                .textFieldStyle(.plain)
                .focused($tagSearchFocused)
                .focusEffectDisabled()
                .accessibilityLabel("搜索可选标签")
            if !tagQuery.isEmpty {
                Button { tagQuery = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除标签搜索")
            }
        }
        .font(.system(size: 11))
        .padding(.horizontal, 9)
        .frame(height: 29)
        .background(accent.controlFill, in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(tagSearchFocused ? accent.focusOutline
                              : Color(nsColor: .separatorColor), lineWidth: 0.75)
        }
    }

    private var tagControls: some View {
        HStack(spacing: 12) {
            Picker("选择标签的用途", selection: $tagMode) {
                ForEach(TagSelectionMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 172)
            Picker("包含标签的匹配方式", selection: $filter.tagMatch) {
                ForEach(PromptLibraryFilter.TagMatch.allCases) { match in
                    Text(match.rawValue).tag(match)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .disabled(filter.tagPresence == .untagged)
        }
        .font(.system(size: 11))
        .controlSize(.small)
        .frame(height: 26)
    }

    private var tagChoices: some View {
        Group {
            if visibleTags.isEmpty {
                VStack(spacing: 5) {
                    Image(systemName: "tag")
                        .font(.system(size: 18, weight: .light))
                    Text(tagQuery.isEmpty ? "当前范围还没有标签" : "没有匹配的标签")
                        .font(.system(size: 11))
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical) {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 7),
                                        GridItem(.flexible(), spacing: 7)], spacing: 7) {
                        ForEach(visibleTags) { option in
                            tagButton(option)
                        }
                    }
                    .padding(.trailing, 1)
                    .padding(.vertical, 1)
                }
            }
        }
        .frame(height: 124)
    }

    private func tagButton(_ option: PromptTagFilterOption) -> some View {
        let included = filter.selectedTagIDs.contains(option.id)
        let excluded = filter.excludedTagIDs.contains(option.id)
        let selected = tagMode == .include ? included : excluded
        let symbol = selected ? (tagMode == .include ? "checkmark.circle.fill" : "minus.circle.fill")
            : excluded ? "minus.circle" : included ? "checkmark.circle" : "circle"
        let state = included ? "已包含" : excluded ? "已排除" : "未选择"
        return Button {
            if tagMode == .include { filter.toggleTag(option.id) }
            else { filter.toggleExcludedTag(option.id) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 10))
                Text(option.name)
                    .font(.system(size: 11, weight: selected ? .medium : .regular))
                    .lineLimit(1)
                Spacer(minLength: 3)
                Text("\(option.promptCount)")
                    .font(.system(size: 10).monospacedDigit())
                    .opacity(0.65)
            }
            .padding(.horizontal, 8)
            .frame(height: 29)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(PromptFilterQuietButtonStyle(selected: selected))
        .accessibilityLabel("\(option.name)，\(option.promptCount) 条提示词，\(state)")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help("\(option.name)：\(state)。点击\(tagMode == .include ? "包含" : "排除")此标签。")
    }
}

struct PromptActiveFilterSummary: View {
    @Binding var filter: PromptLibraryFilter
    let tags: [PromptTagFilterOption]

    private func tagName(_ id: UUID) -> String {
        tags.first(where: { $0.id == id })?.name ?? "标签"
    }

    private func orderedIDs(_ ids: Set<UUID>) -> [UUID] {
        ids.sorted {
            let lhs = tagName($0)
            let rhs = tagName($1)
            return lhs == rhs ? $0.uuidString < $1.uuidString
                : lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
    }

    var body: some View {
        if filter.isActive {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 6) {
                    Text("筛选")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    if filter.selectedTagIDs.count > 1 {
                        Text(filter.tagMatch.rawValue)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(orderedIDs(filter.selectedTagIDs), id: \.self) { id in
                        PromptFilterRemovalChip(title: "#\(tagName(id))", symbol: "plus") {
                            filter.selectedTagIDs.remove(id)
                        }
                    }
                    ForEach(orderedIDs(filter.excludedTagIDs), id: \.self) { id in
                        PromptFilterRemovalChip(title: "排除 #\(tagName(id))", symbol: "minus") {
                            filter.excludedTagIDs.remove(id)
                        }
                    }
                    if filter.favorite != .any {
                        PromptFilterRemovalChip(title: filter.favorite.rawValue, symbol: "star") {
                            filter.favorite = .any
                        }
                    }
                    if filter.cover != .any {
                        PromptFilterRemovalChip(title: filter.cover.rawValue, symbol: "photo") {
                            filter.cover = .any
                        }
                    }
                    if filter.updated != .any {
                        PromptFilterRemovalChip(title: filter.updated.rawValue, symbol: "clock") {
                            filter.updated = .any
                        }
                    }
                    if filter.tagPresence != .any {
                        PromptFilterRemovalChip(title: filter.tagPresence.rawValue, symbol: "tag") {
                            filter.setTagPresence(.any)
                        }
                    }
                    Button { filter.reset() } label: {
                        Text("清除全部")
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                    }
                        .font(.system(size: 10))
                        .buttonStyle(PromptFilterQuietButtonStyle())
                        .accessibilityLabel("清除全部筛选条件")
                }
                .padding(.vertical, 3)
            }
            .frame(height: 30)
        }
    }
}

private struct PromptFilterChoiceRow<Value>: View
where Value: RawRepresentable & CaseIterable & Identifiable & Hashable, Value.RawValue == String {
    let title: String
    @Binding var value: Value

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .leading)
            Picker(title, selection: $value) {
                ForEach(Array(Value.allCases)) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .font(.system(size: 11))
            .controlSize(.small)
            .accessibilityLabel(title)
        }
        .frame(height: 28)
    }
}

private struct PromptFilterRemovalChip: View {
    let title: String
    let symbol: String
    let remove: () -> Void

    var body: some View {
        Button(action: remove) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 8, weight: .medium))
                Text(title).font(.system(size: 10))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .frame(height: 24)
            .contentShape(Capsule())
        }
        .buttonStyle(PromptFilterQuietButtonStyle(active: true, cornerRadius: 12))
        .accessibilityLabel("移除筛选：\(title)")
        .help("移除筛选：\(title)")
    }
}

private struct PromptFilterQuietButtonStyle: ButtonStyle {
    var selected = false
    var active = false
    var cornerRadius: CGFloat = 6

    func makeBody(configuration: Configuration) -> some View {
        Surface(configuration: configuration, selected: selected, active: active, cornerRadius: cornerRadius)
    }

    private struct Surface: View {
        let configuration: ButtonStyle.Configuration
        let selected: Bool
        let active: Bool
        let cornerRadius: CGFloat
        @Environment(\.appAccentStyle) private var accent
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.isFocused) private var isFocused
        @State private var hovering = false

        var body: some View {
            configuration.label
                .foregroundStyle(selected || active ? accent.selectedForeground : Color.primary)
                .background(selected || active ? accent.selectedFill
                            : hovering ? accent.hoverFill : accent.controlFill,
                            in: RoundedRectangle(cornerRadius: cornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(isFocused ? accent.focusOutline : Color.clear, lineWidth: 0.75)
                }
                .opacity(!isEnabled ? 0.4 : configuration.isPressed ? 0.7 : 1)
                .onHover { hovering = $0 }
        }
    }
}

#if DEBUG
private struct PromptFilterPreview: View {
    @State private var filter = PromptLibraryFilter()

    private let options: [PromptTagFilterOption] = [
        .init(id: UUID(), name: "写实", promptCount: 23),
        .init(id: UUID(), name: "人物一致", promptCount: 19),
        .init(id: UUID(), name: "3D/CG", promptCount: 16),
        .init(id: UUID(), name: "四视图", promptCount: 12),
        .init(id: UUID(), name: "面部特写", promptCount: 8),
        .init(id: UUID(), name: "换装", promptCount: 7),
        .init(id: UUID(), name: "动漫", promptCount: 5),
        .init(id: UUID(), name: "分镜", promptCount: 4)
    ]

    var body: some View {
        PromptFilterPanel(filter: $filter, tags: options,
                          resultCount: filter.isActive ? 12 : 48,
                          scopeTitle: "image prompt", onDone: {})
    }
}

#Preview("筛选 · 深色", traits: .fixedLayout(width: 420, height: 530)) {
    PromptFilterPreview()
        .preferredColorScheme(.dark)
        .environment(\.appAccentStyle, AppAccentStyle(palette: .notes, colorScheme: .dark))
}

#Preview("筛选 · 浅色", traits: .fixedLayout(width: 420, height: 530)) {
    PromptFilterPreview()
        .preferredColorScheme(.light)
        .environment(\.appAccentStyle, AppAccentStyle(palette: .monochrome, colorScheme: .light))
}
#endif
