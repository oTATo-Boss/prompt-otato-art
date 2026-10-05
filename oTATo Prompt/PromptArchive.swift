import CryptoKit
import Foundation
import SwiftData

enum ArchiveError: LocalizedError {
    case invalidHeader
    case checksumMismatch
    case unsupportedVersion(Int)
    case invalidData(String)

    var errorDescription: String? {
        switch self {
        case .invalidHeader: return "这不是有效的 oTATo 资料库备份。"
        case .checksumMismatch: return "备份文件不完整或已损坏。"
        case .unsupportedVersion(let version): return "不支持此备份版本（\(version)）。"
        case .invalidData(let detail): return "备份内容无效：\(detail)"
        }
    }
}

struct ArchiveSummary {
    let promptCount: Int
    let trashedPromptCount: Int
    let folderCount: Int
    let tagCount: Int
    let coverCount: Int
    let createdAt: Date
    /// Set after a successful restore. The safety backup is retained on disk.
    let preRestoreBackupURL: URL?
}

/// A portable, checksum-protected archive containing all SwiftData records and
/// cover bytes. The format is a short header, SHA-256 digest, then JSON data.
enum PromptArchiveService {
    private static let magic = Data("OTATOARCHIVE/1\n".utf8)
    private static let currentVersion = 1

    private struct LibraryRecord: Codable {
        let version: Int
        let createdAt: Date
        let prompts: [PromptRecord]
        let folders: [FolderRecord]
        let tags: [TagRecord]
        let covers: [CoverRecord]
    }

    private struct PromptRecord: Codable {
        let id: UUID
        let title: String
        let content: String
        let formatRaw: String
        let folderID: UUID?
        let tagIDs: [UUID]
        let isFavorite: Bool
        let coverPath: String?
        let coverWidth: Int?
        let coverHeight: Int?
        let coverFileSize: Int?
        let coverHash: String?
        let coverCropX: Double
        let coverCropY: Double
        let coverCropWidth: Double
        let coverCropHeight: Double
        let createdAt: Date
        let updatedAt: Date
        let lastUsedAt: Date?
        let deletedAt: Date?
        let sortIndex: Double?
    }

    private struct FolderRecord: Codable {
        let id: UUID
        let name: String
        let parentID: UUID?
        let sortIndex: Double
        let createdAt: Date
        let deletedAt: Date?
    }

    private struct TagRecord: Codable {
        let id: UUID
        let name: String
        let normalizedName: String
        let createdAt: Date
    }

    private struct CoverRecord: Codable {
        let path: String
        let data: Data
    }

    /// Creates a single `.otatoarchive` file. Pass all records, including
    /// trashed prompts and folders, for a complete library backup.
    static func createArchive(
        prompts: [Prompt],
        folders: [Folder],
        tags: [Tag],
        at destination: URL
    ) throws {
        let access = destination.startAccessingSecurityScopedResource()
        defer { if access { destination.stopAccessingSecurityScopedResource() } }
        let paths = Set(prompts.compactMap(\.coverPath))
        var covers: [CoverRecord] = []
        for path in paths.sorted() {
            try validateCoverPath(path)
            let bytes = try Data(contentsOf: PromptStorage.url(forRelativePath: path))
            covers.append(CoverRecord(path: path, data: bytes))
        }

        let record = LibraryRecord(
            version: currentVersion,
            createdAt: .now,
            prompts: prompts.map {
                PromptRecord(
                    id: $0.id, title: $0.title, content: $0.content,
                    formatRaw: $0.formatRaw, folderID: $0.folderID,
                    tagIDs: $0.tags.map(\.id), isFavorite: $0.isFavorite,
                    coverPath: $0.coverPath, coverWidth: $0.coverWidth,
                    coverHeight: $0.coverHeight, coverFileSize: $0.coverFileSize,
                    coverHash: $0.coverHash, coverCropX: $0.coverCropX,
                    coverCropY: $0.coverCropY, coverCropWidth: $0.coverCropWidth,
                    coverCropHeight: $0.coverCropHeight, createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt, lastUsedAt: $0.lastUsedAt,
                    deletedAt: $0.deletedAt, sortIndex: $0.sortIndex
                )
            },
            folders: folders.map {
                FolderRecord(id: $0.id, name: $0.name, parentID: $0.parentID,
                             sortIndex: $0.sortIndex, createdAt: $0.createdAt,
                             deletedAt: $0.deletedAt)
            },
            tags: tags.map {
                TagRecord(id: $0.id, name: $0.name,
                          normalizedName: $0.normalizedName, createdAt: $0.createdAt)
            },
            covers: covers
        )
        try validate(record)
        let payload = try JSONEncoder().encode(record)
        var bytes = magic
        bytes.append(contentsOf: SHA256.hash(data: payload))
        bytes.append(payload)
        try bytes.write(to: destination, options: .atomic)
    }

    /// Checks format, checksum, references, folder cycles, and cover paths
    /// without changing the user's library.
    static func inspectArchive(at url: URL) throws -> ArchiveSummary {
        summary(for: try readArchive(at: url), preRestoreBackupURL: nil)
    }

    /// Validates the incoming archive, makes a full backup of the current
    /// library, stages cover files, then replaces all records transactionally.
    /// A validation or safety-backup failure does not modify the database.
    @discardableResult
    @MainActor
    static func restoreArchive(at url: URL, into context: ModelContext) throws -> ArchiveSummary {
        let incoming = try readArchive(at: url)
        let existingPrompts = try context.fetch(FetchDescriptor<Prompt>())
        let existingFolders = try context.fetch(FetchDescriptor<Folder>())
        let existingTags = try context.fetch(FetchDescriptor<Tag>())
        try PromptStorage.createDirectories()

        let backupName = "pre-restore-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString).otatoarchive"
        let safetyBackup = PromptStorage.backupsURL.appendingPathComponent(backupName)
        try createArchive(
            prompts: existingPrompts,
            folders: existingFolders,
            tags: existingTags,
            at: safetyBackup
        )

        var coverPathMap: [String: String] = [:]
        var stagedCovers: [URL] = []
        do {
            for cover in incoming.covers {
                let ext = URL(fileURLWithPath: cover.path).pathExtension.lowercased()
                let filename = "restored-\(UUID().uuidString).\(ext.isEmpty ? "bin" : ext)"
                let relativePath = "Covers/\(filename)"
                let destination = PromptStorage.url(forRelativePath: relativePath)
                try cover.data.write(to: destination, options: .atomic)
                coverPathMap[cover.path] = relativePath
                stagedCovers.append(destination)
            }

            try context.transaction {
                for prompt in existingPrompts { context.delete(prompt) }
                for folder in existingFolders { context.delete(folder) }
                for tag in existingTags { context.delete(tag) }

                let newTags = incoming.tags.map {
                    Tag(id: $0.id, name: $0.name, normalizedName: $0.normalizedName,
                        createdAt: $0.createdAt)
                }
                for tag in newTags { context.insert(tag) }
                let tagsByID = Dictionary(uniqueKeysWithValues: newTags.map { ($0.id, $0) })

                for folder in incoming.folders {
                    context.insert(Folder(
                        id: folder.id, name: folder.name, parentID: folder.parentID,
                        sortIndex: folder.sortIndex, createdAt: folder.createdAt,
                        deletedAt: folder.deletedAt
                    ))
                }
                for prompt in incoming.prompts {
                    let restored = Prompt(
                        id: prompt.id, title: prompt.title, content: prompt.content,
                        formatRaw: prompt.formatRaw, folderID: prompt.folderID,
                        isFavorite: prompt.isFavorite,
                        coverPath: prompt.coverPath.flatMap { coverPathMap[$0] },
                        coverWidth: prompt.coverWidth, coverHeight: prompt.coverHeight,
                        coverFileSize: prompt.coverFileSize, coverHash: prompt.coverHash,
                        coverCropX: prompt.coverCropX, coverCropY: prompt.coverCropY,
                        coverCropWidth: prompt.coverCropWidth,
                        coverCropHeight: prompt.coverCropHeight,
                        createdAt: prompt.createdAt, updatedAt: prompt.updatedAt,
                        lastUsedAt: prompt.lastUsedAt, sortIndex: prompt.sortIndex,
                        deletedAt: prompt.deletedAt
                    )
                    context.insert(restored)
                    // macOS 14 requires both records in the same context before
                    // a relationship can connect them.
                    restored.tags = prompt.tagIDs.compactMap { tagsByID[$0] }
                }
                try context.save()
            }
        } catch {
            context.rollback()
            for cover in stagedCovers { try? FileManager.default.removeItem(at: cover) }
            throw error
        }
        PromptSearch.clearIndex()
        return summary(for: incoming, preRestoreBackupURL: safetyBackup)
    }

    private static func summary(for record: LibraryRecord, preRestoreBackupURL: URL?) -> ArchiveSummary {
        ArchiveSummary(
            promptCount: record.prompts.count,
            trashedPromptCount: record.prompts.filter { $0.deletedAt != nil }.count,
            folderCount: record.folders.count,
            tagCount: record.tags.count,
            coverCount: record.covers.count,
            createdAt: record.createdAt,
            preRestoreBackupURL: preRestoreBackupURL
        )
    }

    private static func readArchive(at url: URL) throws -> LibraryRecord {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let bytes = try Data(contentsOf: url)
        guard bytes.count >= magic.count + 32,
              bytes.prefix(magic.count) == magic else {
            throw ArchiveError.invalidHeader
        }
        let expectedDigest = bytes[magic.count..<(magic.count + 32)]
        let payload = Data(bytes.dropFirst(magic.count + 32))
        guard Data(SHA256.hash(data: payload)) == expectedDigest else {
            throw ArchiveError.checksumMismatch
        }
        guard let record = try? JSONDecoder().decode(LibraryRecord.self, from: payload) else {
            throw ArchiveError.invalidData("无法读取备份内容")
        }
        try validate(record)
        return record
    }

    private static func validate(_ record: LibraryRecord) throws {
        guard record.version == currentVersion else {
            throw ArchiveError.unsupportedVersion(record.version)
        }
        let promptIDs = Set(record.prompts.map(\.id))
        let folderIDs = Set(record.folders.map(\.id))
        let tagIDs = Set(record.tags.map(\.id))
        let coverPaths = Set(record.covers.map(\.path))
        guard promptIDs.count == record.prompts.count,
              folderIDs.count == record.folders.count,
              tagIDs.count == record.tags.count,
              coverPaths.count == record.covers.count else {
            throw ArchiveError.invalidData("存在重复的 ID 或封面路径")
        }
        let coversByPath = Dictionary(uniqueKeysWithValues: record.covers.map { ($0.path, $0) })

        let foldersByID = Dictionary(uniqueKeysWithValues: record.folders.map { ($0.id, $0) })
        for folder in record.folders {
            var visited: Set<UUID> = [folder.id]
            var parent = folder.parentID
            while let id = parent {
                guard let linked = foldersByID[id] else {
                    throw ArchiveError.invalidData("文件夹父级不存在")
                }
                guard visited.insert(id).inserted else {
                    throw ArchiveError.invalidData("文件夹层级存在循环")
                }
                parent = linked.parentID
            }
        }
        for prompt in record.prompts {
            guard PromptFormat(rawValue: prompt.formatRaw) != nil else {
                throw ArchiveError.invalidData("Prompt 格式无效")
            }
            if let folderID = prompt.folderID, !folderIDs.contains(folderID) {
                throw ArchiveError.invalidData("Prompt 所属文件夹不存在")
            }
            guard Set(prompt.tagIDs).isSubset(of: tagIDs),
                  Set(prompt.tagIDs).count == prompt.tagIDs.count else {
                throw ArchiveError.invalidData("Prompt 标签引用无效")
            }
            if let path = prompt.coverPath, !coverPaths.contains(path) {
                throw ArchiveError.invalidData("Prompt 封面文件缺失")
            }
            if let path = prompt.coverPath, let cover = coversByPath[path] {
                if let size = prompt.coverFileSize, size != cover.data.count {
                    throw ArchiveError.invalidData("封面文件大小与记录不一致")
                }
                if let hash = prompt.coverHash {
                    let actual = SHA256.hash(data: cover.data)
                        .map { String(format: "%02x", $0) }.joined()
                    if actual.caseInsensitiveCompare(hash) != .orderedSame {
                        throw ArchiveError.invalidData("封面文件与记录不一致")
                    }
                }
            }
            if let width = prompt.coverWidth, width <= 0 {
                throw ArchiveError.invalidData("封面尺寸无效")
            }
            if let height = prompt.coverHeight, height <= 0 {
                throw ArchiveError.invalidData("封面尺寸无效")
            }
            guard prompt.coverCropX.isFinite, prompt.coverCropY.isFinite,
                  prompt.coverCropWidth.isFinite, prompt.coverCropHeight.isFinite,
                  (0...1).contains(prompt.coverCropX), (0...1).contains(prompt.coverCropY),
                  (0...1).contains(prompt.coverCropWidth),
                  (0...1).contains(prompt.coverCropHeight),
                  prompt.coverCropX + prompt.coverCropWidth <= 1.000001,
                  prompt.coverCropY + prompt.coverCropHeight <= 1.000001 else {
                throw ArchiveError.invalidData("封面裁切范围无效")
            }
        }
        for cover in record.covers { try validateCoverPath(cover.path) }
    }

    private static func validateCoverPath(_ path: String) throws {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count == 2,
              components[0] == "Covers",
              !components[1].isEmpty,
              components[1] != ".",
              components[1] != "..",
              !path.contains("\\") else {
            throw ArchiveError.invalidData("封面路径无效")
        }
    }
}
