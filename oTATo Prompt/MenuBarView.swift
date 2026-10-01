import SwiftData
import SwiftUI

/// A compact library entry point that keeps the copy action one click away.
struct MenuBarView: View {
    @Environment(\.appAccentStyle) private var accent
    @EnvironmentObject private var app: AppCoordinator
    @Environment(\.dismiss) private var dismiss
    @Query private var prompts: [Prompt]
    @Query private var folders: [Folder]

    @State private var searchText = ""
    @State private var settledSearch = ""
    @State private var searchTask: Task<Void, Never>?
    @State private var copied = false
    @State private var hoveredPromptID: UUID?
    @FocusState private var searchFocused: Bool

    private var activePrompts: [Prompt] { prompts.filter { $0.deletedAt == nil } }

    private var recentPrompts: [Prompt] {
        activePrompts.filter { $0.lastUsedAt != nil }
            .sorted { ($0.lastUsedAt ?? .distantPast) > ($1.lastUsedAt ?? .distantPast) }
            .prefix(4).map { $0 }
    }

    private var favoritePrompts: [Prompt] {
        activePrompts.filter(\.isFavorite)
            .sorted {
                let first = $0.lastUsedAt ?? .distantPast
                let second = $1.lastUsedAt ?? .distantPast
                return first == second ? $0.updatedAt > $1.updatedAt : first > second
            }
            .prefix(4).map { $0 }
    }

    private var searchResults: [Prompt] {
        PromptSearch.search(
            activePrompts, query: settledSearch, folders: folders, limit: 8
        )
    }

    private var listHeight: CGFloat {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let count = recentPrompts.count + favoritePrompts.count
            guard count > 0 else { return 80 }
            let sections = (recentPrompts.isEmpty ? 0 : 1) + (favoritePrompts.isEmpty ? 0 : 1)
            return min(560, CGFloat(count * 59 + sections * 21 + (sections - 1) * 14 + 20))
        }
        guard !settledSearch.isEmpty, !searchResults.isEmpty else { return 80 }
        return min(560, CGFloat(searchResults.count * 59 + 41))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索 Prompt…", text: $searchText)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .accessibilityLabel("搜索提示词")
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(accent.controlFill, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.75)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        menuSection("最近使用", prompts: recentPrompts, destination: .recentUse)
                        menuSection("收藏", prompts: favoritePrompts, destination: .favorites)
                        if recentPrompts.isEmpty && favoritePrompts.isEmpty {
                            emptyState("还没有最近使用或收藏的提示词")
                        }
                    } else if settledSearch.isEmpty {
                        emptyState("正在搜索…")
                    } else if searchResults.isEmpty {
                        emptyState("没有找到匹配的提示词")
                    } else {
                        menuSection("搜索结果", prompts: searchResults)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
            .frame(height: listHeight)

            Divider()
            footer
        }
        .frame(width: 430)
        .onAppear { searchFocused = true }
        .onDisappear { searchTask?.cancel() }
        .onChange(of: searchText) { _, value in
            searchTask?.cancel()
            if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                settledSearch = ""
            } else {
                settledSearch = ""
                searchTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(120))
                    if !Task.isCancelled { settledSearch = value }
                }
            }
        }
        .onChange(of: app.menuCopyCompleted) { _, _ in
            copied = true
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 400_000_000)
                dismiss()
                copied = false
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image("BrandMark")
                .resizable()
                .renderingMode(.template)
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)
            Text("oTATo prompt")
                .font(.headline)
            Spacer()
            if copied {
                Label("已复制", systemImage: "checkmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
            SettingsLink {
                Image(systemName: "gearshape")
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("设置")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func menuSection(_ title: String, prompts: [Prompt],
                             destination: LibraryShortcut? = nil) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if !prompts.isEmpty {
                HStack {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    if let destination {
                        Button {
                            app.requestCollection(destination)
                        } label: {
                            HStack(spacing: 2) {
                                Text("全部")
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9, weight: .semibold))
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.primary)
                        .accessibilityLabel("查看全部\(title)")
                    }
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                ForEach(prompts, id: \.id) { prompt in
                    promptRow(prompt)
                }
            }
        }
    }

    private func promptRow(_ prompt: Prompt) -> some View {
        Button {
            app.requestCopy(prompt, source: .menuBar)
        } label: {
            HStack(spacing: 10) {
                CoverThumbnail(prompt: prompt, maxPixelSize: 192) {
                    Image(systemName: "doc.richtext")
                        .font(.system(size: 19))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(width: 56, height: 31.5)
                .background(Color(nsColor: .textBackgroundColor))
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 3) {
                    Text(prompt.title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    if !prompt.tagNames.isEmpty {
                        Text(prompt.tagNames.prefix(3).map { "#\($0)" }.joined(separator: "   "))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 8)
            .frame(height: 54)
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .background(hoveredPromptID == prompt.id ? accent.hoverFill : accent.controlFill,
                        in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { hovering in hoveredPromptID = hovering ? prompt.id : nil }
        .accessibilityLabel("复制 \(prompt.title)")
    }

    private func emptyState(_ message: String) -> some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                app.requestNewPrompt()
            } label: {
                Label("新建 Prompt", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            Button {
                app.requestSearch()
            } label: {
                Label("打开主应用", systemImage: "arrow.up.forward.square")
                    .frame(maxWidth: .infinity)
            }
        }
        .appSecondaryAction()
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}
