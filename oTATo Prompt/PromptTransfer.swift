import CryptoKit
import Foundation
import SwiftData

// MARK: - Markdown and TXT

struct ImportedPromptText: Sendable {
    let title: String
    let content: String
    let format: PromptFormat
}

enum PromptTextTransfer {
    enum TransferError: LocalizedError {
        case unsupportedFormat(String)
        case invalidEncoding(String)

        var errorDescription: String? {
            switch self {
            case .unsupportedFormat(let filename): return "只支持 .md 和 .txt 文件：\(filename)"
            case .invalidEncoding(let filename): return "无法按 UTF-8 读取文件：\(filename)"
            }
        }
    }

    nonisolated static func read(_ url: URL) throws -> ImportedPromptText {
        switch url.pathExtension.lowercased() {
        case "md", "txt": break
        default: throw TransferError.unsupportedFormat(url.lastPathComponent)
        }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        guard let content = String(data: data, encoding: .utf8) else {
            throw TransferError.invalidEncoding(url.lastPathComponent)
        }
        let title = url.deletingPathExtension().lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return ImportedPromptText(
            title: title.isEmpty ? "未命名 Prompt" : title,
            content: content,
            format: .markdown
        )
    }

    /// Every file is decoded before a caller creates any database objects.
    nonisolated static func readAll(_ urls: [URL]) throws -> [ImportedPromptText] {
        var files: [ImportedPromptText] = []
        files.reserveCapacity(urls.count)
        for url in urls { files.append(try read(url)) }
        return files
    }

    /// An invalid file or failed save leaves the existing library unchanged.
    @discardableResult
    @MainActor
    static func importFiles(_ urls: [URL], into context: ModelContext, folderID: UUID? = nil) throws -> [Prompt] {
        try importTexts(readAll(urls), into: context, folderID: folderID)
    }

    /// Insert fully decoded text in one transaction after file I/O has finished.
    @discardableResult
    @MainActor
    static func importTexts(_ files: [ImportedPromptText], into context: ModelContext,
                            folderID: UUID? = nil) throws -> [Prompt] {
        let prompts = files.map {
            Prompt(title: $0.title, content: $0.content,
                   formatRaw: PromptFormat.markdown.rawValue, folderID: folderID)
        }
        do {
            try context.transaction {
                for prompt in prompts { context.insert(prompt) }
                try context.save()
            }
            return prompts
        } catch {
            context.rollback()
            throw error
        }
    }

    @discardableResult
    static func write(content: String, format: PromptFormat, to url: URL) throws -> URL {
        let ext = "md"
        let destination = url.pathExtension.lowercased() == ext
            ? url : url.deletingPathExtension().appendingPathExtension(ext)
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        try Data(content.utf8).write(to: destination, options: .atomic)
        return destination
    }

    /// Exports ordinary text files while preserving the folder hierarchy.
    /// Existing files and folders are never overwritten.
    static func writeCollection(prompts: [Prompt], folders: [Folder], to directory: URL) throws -> [URL] {
        let access = directory.startAccessingSecurityScopedResource()
        defer { if access { directory.stopAccessingSecurityScopedResource() } }
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let byID = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0) })
        var urlsByID: [UUID: URL] = [:]

        func directoryFor(_ id: UUID?, visiting: Set<UUID> = []) throws -> URL {
            guard let id, let folder = byID[id] else { return directory }
            if let cached = urlsByID[id] { return cached }
            guard !visiting.contains(id) else { throw ArchiveError.invalidData("文件夹层级存在循环") }
            var next = visiting
            next.insert(id)
            let parent = try directoryFor(folder.parentID, visiting: next)
            let base = safeFileName(folder.name)
            var candidate = parent.appendingPathComponent(base, isDirectory: true)
            var suffix = 2
            while manager.fileExists(atPath: candidate.path) {
                candidate = parent.appendingPathComponent("\(base) \(suffix)", isDirectory: true)
                suffix += 1
            }
            try manager.createDirectory(at: candidate, withIntermediateDirectories: true)
            urlsByID[id] = candidate
            return candidate
        }

        var written: [URL] = []
        do {
            for prompt in prompts {
                let parent = try directoryFor(prompt.folderID)
                let ext = "md"
                let stem = safeFileName(prompt.title)
                var destination = parent.appendingPathComponent(stem).appendingPathExtension(ext)
                var suffix = 2
                while manager.fileExists(atPath: destination.path) {
                    destination = parent.appendingPathComponent("\(stem) \(suffix)").appendingPathExtension(ext)
                    suffix += 1
                }
                try Data(prompt.content.utf8).write(to: destination, options: .atomic)
                written.append(destination)
            }
            return written
        } catch {
            for url in written { try? manager.removeItem(at: url) }
            throw error
        }
    }

    private static func safeFileName(_ name: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/:\\").union(.controlCharacters)
        let cleaned = name.components(separatedBy: forbidden).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return cleaned.isEmpty ? "未命名 Prompt" : String(cleaned.prefix(80))
    }
}
