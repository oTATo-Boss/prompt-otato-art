import AppKit
import CryptoKit
import Foundation
import SwiftData

struct StoredCover: Codable, Equatable {
    let relativePath: String
    let width: Int
    let height: Int
    let fileSize: Int
    let sha256: String
}

enum PromptStorageError: LocalizedError {
    case invalidImage
    case invalidCoverPath

    var errorDescription: String? {
        switch self {
        case .invalidImage: "无法读取封面图片。"
        case .invalidCoverPath: "封面路径无效。"
        }
    }
}

enum PromptStorage {
    static var applicationSupportURL: URL {
        #if DEBUG
        if let override = ProcessInfo.processInfo.environment["OTATO_QA_LIBRARY_ROOT"],
           !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        #endif
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("oTATo", isDirectory: true)
    }

    static var coversURL: URL {
        applicationSupportURL.appendingPathComponent("Covers", isDirectory: true)
    }

    static var backupsURL: URL {
        applicationSupportURL.appendingPathComponent("Backups", isDirectory: true)
    }

    static func url(forRelativePath path: String) -> URL {
        applicationSupportURL.appendingPathComponent(path).standardizedFileURL
    }

    static func validatedCoverURL(forRelativePath path: String) throws -> URL {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2,
              parts[0] == "Covers",
              !parts[1].isEmpty,
              parts[1] != ".",
              parts[1] != "..",
              !parts[1].contains("\\") else {
            throw PromptStorageError.invalidCoverPath
        }
        return url(forRelativePath: path)
    }

    static func createDirectories() throws {
        let manager = FileManager.default
        try manager.createDirectory(at: coversURL, withIntermediateDirectories: true)
        try manager.createDirectory(at: backupsURL, withIntermediateDirectories: true)
    }

    /// Saves a JPEG copy bounded to 1600 pixels on its longest edge.
    static func saveCoverAsset(image: NSImage) throws -> StoredCover {
        guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw PromptStorageError.invalidImage
        }
        try createDirectories()

        let scale = min(1, 1600.0 / Double(max(source.width, source.height)))
        let width = max(1, Int((Double(source.width) * scale).rounded()))
        let height = max(1, Int((Double(source.height) * scale).rounded()))
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            throw PromptStorageError.invalidImage
        }
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let rendered = context.makeImage(),
              let data = NSBitmapImageRep(cgImage: rendered).representation(
                using: .jpeg,
                properties: [.compressionFactor: 0.82]
              ) else {
            throw PromptStorageError.invalidImage
        }

        let relativePath = "Covers/\(UUID().uuidString.lowercased()).jpg"
        try data.write(to: validatedCoverURL(forRelativePath: relativePath), options: .atomic)
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return StoredCover(
            relativePath: relativePath,
            width: width,
            height: height,
            fileSize: data.count,
            sha256: hash
        )
    }

    static func saveCoverAsset(data: Data) throws -> StoredCover {
        guard let image = NSImage(data: data) else { throw PromptStorageError.invalidImage }
        return try saveCoverAsset(image: image)
    }

    /// Convenience for callers that only need the relative path.
    static func saveCover(image: NSImage) throws -> String {
        try saveCoverAsset(image: image).relativePath
    }

    static func saveCover(data: Data) throws -> String {
        try saveCoverAsset(data: data).relativePath
    }

    static func loadCover(at relativePath: String) -> NSImage? {
        guard let url = try? validatedCoverURL(forRelativePath: relativePath) else { return nil }
        return NSImage(contentsOf: url)
    }

    static func removeCover(at relativePath: String) throws {
        let url = try validatedCoverURL(forRelativePath: relativePath)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}

enum PromptPersistence {
    static var storeURL: URL {
        PromptStorage.applicationSupportURL.appendingPathComponent("oTATo.store")
    }

    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        if !inMemory { try PromptStorage.createDirectories() }
        let schema = Schema(versionedSchema: PromptSchemaV1.self)
        let configuration = inMemory
            ? ModelConfiguration(isStoredInMemoryOnly: true)
            : ModelConfiguration(url: storeURL)
        return try ModelContainer(
            for: schema,
            migrationPlan: PromptMigrationPlan.self,
            configurations: [configuration]
        )
    }
}
