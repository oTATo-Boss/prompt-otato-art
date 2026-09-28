import Foundation
import SwiftData

enum PromptFormat: String, CaseIterable, Codable, Identifiable {
    case markdown
    case txt

    var id: String { rawValue }
    var fileExtension: String { self == .markdown ? "md" : "txt" }
}

/// Coordinates use a top-left origin and fractions of the original image (0...1).
struct CoverCrop: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    static let full = CoverCrop(x: 0, y: 0, width: 1, height: 1)

    init(x: Double, y: Double, width: Double, height: Double) {
        self.x = min(max(x.isFinite ? x : 0, 0), 0.99)
        self.y = min(max(y.isFinite ? y : 0, 0), 0.99)
        self.width = min(max(width.isFinite ? width : 1, 0.01), 1 - self.x)
        self.height = min(max(height.isFinite ? height : 1, 0.01), 1 - self.y)
    }
}

/// Keep this v1 definition intact when adding future migrations.
enum PromptSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] { [Prompt.self, Folder.self, Tag.self] }

    @Model
    final class Prompt {
        var id: UUID
        var title: String
        var content: String
        var formatRaw: String
        var folderID: UUID?
        var isFavorite: Bool
        /// Relative to Application Support/oTATo, for example Covers/<uuid>.jpg.
        var coverPath: String?
        var coverWidth: Int?
        var coverHeight: Int?
        var coverFileSize: Int?
        var coverHash: String?
        var coverCropX: Double
        var coverCropY: Double
        var coverCropWidth: Double
        var coverCropHeight: Double
        var createdAt: Date
        var updatedAt: Date
        var lastUsedAt: Date?
        var sortIndex: Double?
        /// A non-nil timestamp means the record is in the app's Trash.
        var deletedAt: Date?
        @Relationship(inverse: \PromptSchemaV1.Tag.prompts) var tags: [PromptSchemaV1.Tag]

        var format: PromptFormat {
            get { PromptFormat(rawValue: formatRaw) ?? .markdown }
            set { formatRaw = newValue.rawValue }
        }

        var tagNames: [String] {
            tags.map(\.name).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        }

        var coverCrop: CoverCrop {
            get {
                CoverCrop(
                    x: coverCropX, y: coverCropY,
                    width: coverCropWidth, height: coverCropHeight
                )
            }
            set {
                coverCropX = newValue.x
                coverCropY = newValue.y
                coverCropWidth = newValue.width
                coverCropHeight = newValue.height
            }
        }

        init(
            id: UUID = UUID(),
            title: String = "",
            content: String = "",
            formatRaw: String = PromptFormat.markdown.rawValue,
            folderID: UUID? = nil,
            isFavorite: Bool = false,
            coverPath: String? = nil,
            coverWidth: Int? = nil,
            coverHeight: Int? = nil,
            coverFileSize: Int? = nil,
            coverHash: String? = nil,
            coverCropX: Double = 0,
            coverCropY: Double = 0,
            coverCropWidth: Double = 1,
            coverCropHeight: Double = 1,
            createdAt: Date = .now,
            updatedAt: Date = .now,
            lastUsedAt: Date? = nil,
            sortIndex: Double? = nil,
            deletedAt: Date? = nil,
            tags: [PromptSchemaV1.Tag] = []
        ) {
            self.id = id
            self.title = title
            self.content = content
            self.formatRaw = formatRaw
            self.folderID = folderID
            self.isFavorite = isFavorite
            self.coverPath = coverPath
            self.coverWidth = coverWidth
            self.coverHeight = coverHeight
            self.coverFileSize = coverFileSize
            self.coverHash = coverHash
            self.coverCropX = coverCropX
            self.coverCropY = coverCropY
            self.coverCropWidth = coverCropWidth
            self.coverCropHeight = coverCropHeight
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.lastUsedAt = lastUsedAt
            self.sortIndex = sortIndex
            self.deletedAt = deletedAt
            self.tags = tags
        }
    }

    @Model
    final class Folder {
        var id: UUID
        var name: String
        var parentID: UUID?
        var sortIndex: Double
        var createdAt: Date
        var deletedAt: Date?

        init(
            id: UUID = UUID(),
            name: String,
            parentID: UUID? = nil,
            sortIndex: Double = 0,
            createdAt: Date = .now,
            deletedAt: Date? = nil
        ) {
            self.id = id
            self.name = name
            self.parentID = parentID
            self.sortIndex = sortIndex
            self.createdAt = createdAt
            self.deletedAt = deletedAt
        }
    }

    @Model
    final class Tag {
        var id: UUID
        var name: String
        var normalizedName: String
        var createdAt: Date
        var prompts: [PromptSchemaV1.Prompt]

        init(
            id: UUID = UUID(),
            name: String,
            normalizedName: String? = nil,
            createdAt: Date = .now,
            prompts: [PromptSchemaV1.Prompt] = []
        ) {
            self.id = id
            self.name = name
            self.normalizedName = normalizedName ?? Self.normalize(name)
            self.createdAt = createdAt
            self.prompts = prompts
        }

        static func normalize(_ name: String) -> String {
            name.trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        }
    }
}

typealias Prompt = PromptSchemaV1.Prompt
typealias Folder = PromptSchemaV1.Folder
typealias Tag = PromptSchemaV1.Tag

enum PromptMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [PromptSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}
