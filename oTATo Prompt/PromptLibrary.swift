import Foundation
import SwiftData

enum PromptLibraryError: LocalizedError {
    case emptyPrompt
    case invalidTitle
    case invalidFolderName
    case invalidTagName
    case tooManyTags
    case duplicateTag
    case folderCycle
    case folderUnavailable
    case mustBeTrashed

    var errorDescription: String? {
        switch self {
        case .emptyPrompt: "标题和正文不能同时为空。"
        case .invalidTitle: "标题需在 1 到 100 个字符之间。"
        case .invalidFolderName: "文件夹名称不能为空。"
        case .invalidTagName: "标签需在 1 到 20 个字符之间。"
        case .tooManyTags: "每条 Prompt 最多可添加 10 个标签。"
        case .duplicateTag: "同名标签已存在。"
        case .folderCycle: "不能将文件夹移入自身或其子文件夹。"
        case .folderUnavailable: "目标文件夹不存在或已移入废纸篓。"
        case .mustBeTrashed: "请先将项目移入废纸篓。"
        }
    }
}

/// Shared mutations for the main window, menu bar and global search.
@MainActor
enum PromptLibrary {
    static func createPrompt(
        in context: ModelContext,
        title: String,
        content: String,
        format: PromptFormat = .markdown,
        folderID: UUID? = nil,
        tagNames: [String] = []
    ) throws -> Prompt {
        let finalTitle = try resolvedTitle(title, content: content)
        let names = try checkedTagNames(tagNames)
        try requireActiveFolder(folderID, in: context)
        // Keep the format argument while existing callers transition to a single
        // Markdown workflow. New records always use Markdown; older TXT records
        // remain readable through the unchanged v1 model.
        let prompt = Prompt(title: finalTitle, content: content,
                            formatRaw: PromptFormat.markdown.rawValue, folderID: folderID)
        context.insert(prompt)
        try setTags(names, for: prompt, in: context, save: false)
        try context.save()
        return prompt
    }

    static func resolvedTitle(_ title: String, content: String) throws -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw PromptLibraryError.emptyPrompt
            }
            let firstLine = content.split(whereSeparator: \.isNewline)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty } ?? "未命名 Prompt"
            return String(firstLine.prefix(100))
        }
        guard trimmed.count <= 100 else { throw PromptLibraryError.invalidTitle }
        return trimmed
    }

    static func touch(_ prompt: Prompt, in context: ModelContext) throws {
        prompt.updatedAt = .now
        try context.save()
    }

    /// Call only after the final text was successfully written to the pasteboard.
    static func markCopied(_ prompt: Prompt, in context: ModelContext) throws {
        prompt.lastUsedAt = .now
        try context.save()
    }

    static func setFavorite(_ favorite: Bool, for prompt: Prompt, in context: ModelContext) throws {
        guard prompt.isFavorite != favorite else { return }
        prompt.isFavorite = favorite
        // Collection membership is independent of content edits and ordering.
        try context.save()
    }

    static func move(_ prompt: Prompt, to folderID: UUID?, in context: ModelContext) throws {
        try requireActiveFolder(folderID, in: context)
        guard prompt.folderID != folderID else { return }
        prompt.folderID = folderID
        try touch(prompt, in: context)
    }

    static func setCover(
        _ cover: StoredCover?,
        crop: CoverCrop? = nil,
        for prompt: Prompt,
        in context: ModelContext
    ) throws {
        prompt.coverPath = cover?.relativePath
        prompt.coverWidth = cover?.width
        prompt.coverHeight = cover?.height
        prompt.coverFileSize = cover?.fileSize
        prompt.coverHash = cover?.sha256
        prompt.coverCrop = cover == nil ? .full : (crop ?? .full)
        try touch(prompt, in: context)
    }

    static func setCoverCrop(_ crop: CoverCrop, for prompt: Prompt, in context: ModelContext) throws {
        guard prompt.coverPath != nil, prompt.coverCrop != crop else { return }
        prompt.coverCrop = crop
        try touch(prompt, in: context)
    }

    static func setTags(_ names: [String], for prompt: Prompt, in context: ModelContext) throws {
        try setTags(names, for: prompt, in: context, save: true)
    }

    private static func setTags(_ names: [String], for prompt: Prompt, in context: ModelContext, save: Bool) throws {
        let checked = try checkedTagNames(names)
        let current = Set(prompt.tags.map(\.normalizedName))
        let requested = Set(checked.map(Tag.normalize))
        guard current != requested else { return }

        let existing = try context.fetch(FetchDescriptor<Tag>())
        var byName = Dictionary(existing.map { ($0.normalizedName, $0) }, uniquingKeysWith: { first, _ in first })
        var resolved: [Tag] = []
        for name in checked {
            let normalized = Tag.normalize(name)
            if let tag = byName[normalized] {
                resolved.append(tag)
            } else {
                let tag = Tag(name: name, normalizedName: normalized)
                context.insert(tag)
                byName[normalized] = tag
                resolved.append(tag)
            }
        }
        prompt.tags = resolved
        prompt.updatedAt = .now
        if save { try context.save() }
    }

    static func ensureTag(named name: String, in context: ModelContext) throws -> Tag {
        let checked = try checkedTagNames([name])[0]
        let normalized = Tag.normalize(checked)
        if let existing = try context.fetch(FetchDescriptor<Tag>()).first(where: { $0.normalizedName == normalized }) {
            return existing
        }
        let tag = Tag(name: checked, normalizedName: normalized)
        context.insert(tag)
        try context.save()
        return tag
    }

    static func renameTag(_ tag: Tag, to name: String, in context: ModelContext) throws {
        let checked = try checkedTagNames([name])[0]
        let normalized = Tag.normalize(checked)
        let all = try context.fetch(FetchDescriptor<Tag>())
        guard !all.contains(where: { $0.id != tag.id && $0.normalizedName == normalized }) else {
            throw PromptLibraryError.duplicateTag
        }
        guard tag.name != checked else { return }
        tag.name = checked
        tag.normalizedName = normalized
        let now = Date.now
        for prompt in tag.prompts { prompt.updatedAt = now }
        try context.save()
    }

    static func deleteTag(_ tag: Tag, in context: ModelContext) throws {
        let now = Date.now
        for prompt in tag.prompts { prompt.updatedAt = now }
        context.delete(tag)
        try context.save()
    }

    static func trash(_ prompt: Prompt, in context: ModelContext) throws {
        guard prompt.deletedAt == nil else { return }
        prompt.deletedAt = .now
        try context.save()
    }

    static func restore(_ prompt: Prompt, in context: ModelContext) throws {
        guard prompt.deletedAt != nil else { return }
        let folders = try context.fetch(FetchDescriptor<Folder>())
        if let folderID = prompt.folderID,
           !folders.contains(where: { $0.id == folderID && $0.deletedAt == nil }) {
            prompt.folderID = nil
        }
        prompt.deletedAt = nil
        prompt.updatedAt = .now
        try context.save()
    }

    static func purge(_ prompt: Prompt, in context: ModelContext) throws {
        guard prompt.deletedAt != nil else { throw PromptLibraryError.mustBeTrashed }
        let coverPath = prompt.coverPath
        PromptSearch.invalidate(prompt)
        context.delete(prompt)
        try context.save()
        if let coverPath {
            let remaining = try context.fetch(FetchDescriptor<Prompt>())
            if !remaining.contains(where: { $0.coverPath == coverPath }) {
                try? PromptStorage.removeCover(at: coverPath)
            }
        }
    }

    static func createFolder(
        in context: ModelContext,
        name: String,
        parentID: UUID? = nil,
        sortIndex: Double? = nil
    ) throws -> Folder {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PromptLibraryError.invalidFolderName }
        try requireActiveFolder(parentID, in: context)
        let siblings = try context.fetch(FetchDescriptor<Folder>())
            .filter { $0.parentID == parentID && $0.deletedAt == nil }
        let nextIndex = sortIndex ?? ((siblings.map(\.sortIndex).max() ?? -1) + 1)
        let folder = Folder(name: trimmed, parentID: parentID, sortIndex: nextIndex)
        context.insert(folder)
        try context.save()
        return folder
    }

    static func renameFolder(_ folder: Folder, to name: String, in context: ModelContext) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PromptLibraryError.invalidFolderName }
        guard folder.name != trimmed else { return }
        folder.name = trimmed
        try context.save()
    }

    static func moveFolder(_ folder: Folder, to parentID: UUID?, in context: ModelContext) throws {
        guard folder.parentID != parentID else { return }
        try requireActiveFolder(parentID, in: context)
        let folders = try context.fetch(FetchDescriptor<Folder>())
        let byID = Dictionary(folders.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var cursor = parentID
        while let id = cursor {
            guard id != folder.id else { throw PromptLibraryError.folderCycle }
            cursor = byID[id]?.parentID
        }
        folder.parentID = parentID
        try context.save()
    }

    enum FolderTrashMode {
        case moveContentsToParent
        case trashContents
    }

    /// The UI should ask which mode to use when the folder has contents.
    static func trash(
        _ folder: Folder,
        mode: FolderTrashMode = .trashContents,
        in context: ModelContext
    ) throws {
        guard folder.deletedAt == nil else { return }
        let folders = try context.fetch(FetchDescriptor<Folder>())
        let prompts = try context.fetch(FetchDescriptor<Prompt>())
        let now = Date.now
        switch mode {
        case .moveContentsToParent:
            for child in folders where child.parentID == folder.id && child.deletedAt == nil {
                child.parentID = folder.parentID
            }
            for prompt in prompts where prompt.folderID == folder.id && prompt.deletedAt == nil {
                prompt.folderID = folder.parentID
                prompt.updatedAt = now
            }
            folder.deletedAt = now
        case .trashContents:
            let ids = descendantIDs(of: folder.id, in: folders)
            for child in folders where ids.contains(child.id) && child.deletedAt == nil {
                child.deletedAt = now
            }
            for prompt in prompts where prompt.folderID.map(ids.contains) == true && prompt.deletedAt == nil {
                prompt.deletedAt = now
            }
        }
        try context.save()
    }

    static func restore(_ folder: Folder, in context: ModelContext) throws {
        guard let marker = folder.deletedAt else { return }
        let folders = try context.fetch(FetchDescriptor<Folder>())
        let prompts = try context.fetch(FetchDescriptor<Prompt>())
        let ids = descendantIDs(of: folder.id, in: folders)
        if let parentID = folder.parentID,
           !folders.contains(where: { $0.id == parentID && $0.deletedAt == nil }) {
            folder.parentID = nil
        }
        for child in folders where ids.contains(child.id) && child.deletedAt == marker {
            child.deletedAt = nil
        }
        for prompt in prompts where prompt.folderID.map(ids.contains) == true && prompt.deletedAt == marker {
            prompt.deletedAt = nil
            prompt.updatedAt = .now
        }
        try context.save()
    }

    static func purge(_ folder: Folder, in context: ModelContext) throws {
        guard folder.deletedAt != nil else { throw PromptLibraryError.mustBeTrashed }
        let folders = try context.fetch(FetchDescriptor<Folder>())
        let prompts = try context.fetch(FetchDescriptor<Prompt>())
        let ids = descendantIDs(of: folder.id, in: folders)
        let coverPaths = prompts.filter { $0.folderID.map(ids.contains) == true }.compactMap(\.coverPath)
        for prompt in prompts where prompt.folderID.map(ids.contains) == true {
            PromptSearch.invalidate(prompt)
            context.delete(prompt)
        }
        for child in folders where ids.contains(child.id) { context.delete(child) }
        try context.save()
        let remainingCoverPaths = Set(try context.fetch(FetchDescriptor<Prompt>()).compactMap(\.coverPath))
        for path in Set(coverPaths) where !remainingCoverPaths.contains(path) {
            try? PromptStorage.removeCover(at: path)
        }
    }

    /// A folder collection includes prompts in all active descendant folders.
    static func folderContents(of folderID: UUID, prompts: [Prompt], folders: [Folder]) -> [Prompt] {
        let activeFolders = folders.filter { $0.deletedAt == nil }
        guard activeFolders.contains(where: { $0.id == folderID }) else { return [] }
        let ids = descendantIDs(of: folderID, in: activeFolders)
        return prompts.filter {
            $0.deletedAt == nil && $0.folderID.map(ids.contains) == true
        }
    }

    static func directCount(for folderID: UUID?, in prompts: [Prompt]) -> Int {
        prompts.reduce(into: 0) { count, prompt in
            if prompt.deletedAt == nil && prompt.folderID == folderID { count += 1 }
        }
    }

    static func setManualOrder(_ orderedPrompts: [Prompt], in context: ModelContext) throws {
        for (index, prompt) in orderedPrompts.enumerated() {
            prompt.sortIndex = Double(index)
        }
        try context.save()
    }

    static func setFolderOrder(_ orderedFolders: [Folder], in context: ModelContext) throws {
        for (index, folder) in orderedFolders.enumerated() {
            folder.sortIndex = Double(index)
        }
        try context.save()
    }

    private static func requireActiveFolder(_ folderID: UUID?, in context: ModelContext) throws {
        guard let folderID else { return }
        let folders = try context.fetch(FetchDescriptor<Folder>())
        guard folders.contains(where: { $0.id == folderID && $0.deletedAt == nil }) else {
            throw PromptLibraryError.folderUnavailable
        }
    }

    private static func descendantIDs(of rootID: UUID, in folders: [Folder]) -> Set<UUID> {
        var ids: Set<UUID> = [rootID]
        var changed = true
        while changed {
            changed = false
            for folder in folders where folder.parentID.map(ids.contains) == true && !ids.contains(folder.id) {
                ids.insert(folder.id)
                changed = true
            }
        }
        return ids
    }

    private static func checkedTagNames(_ names: [String]) throws -> [String] {
        var result: [String] = []
        var seen: Set<String> = []
        for rawName in names {
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard (1...20).contains(name.count) else { throw PromptLibraryError.invalidTagName }
            let normalized = Tag.normalize(name)
            if seen.insert(normalized).inserted { result.append(name) }
        }
        guard result.count <= 10 else { throw PromptLibraryError.tooManyTags }
        return result
    }
}
