import AppKit
import CryptoKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Covers are immutable assets. Include the hash and library URL so restoring
/// another library cannot reuse a thumbnail belonging to an older asset.
struct CoverThumbnailRequest: Hashable, Sendable {
    let url: URL
    let revision: String?
    let maxPixelSize: Int

    init?(prompt: Prompt, maxPixelSize: Int) {
        guard let path = prompt.coverPath,
              let url = try? PromptStorage.validatedCoverURL(forRelativePath: path) else { return nil }
        self.url = url
        revision = prompt.coverHash
        self.maxPixelSize = maxPixelSize
    }

    var cacheKey: NSString { "\(url.path)|\(revision ?? "")|\(maxPixelSize)" as NSString }
}

@MainActor
final class CoverThumbnailCache {
    static let shared = CoverThumbnailCache()
    private let cache = NSCache<NSString, NSImage>()
    private struct PendingLoad {
        let task: Task<NSImage?, Never>
        let operation: BlockOperation
        var defaultPriority: Operation.QueuePriority
    }
    private var pending: [CoverThumbnailRequest: PendingLoad] = [:]
    private var visibleRequests: [UUID: CoverThumbnailRequest] = [:]
    private let files: CoverThumbnailFiles
    private let persistenceQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "art.otato.prompt.thumbnail-persistence"
        queue.qualityOfService = .utility
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    private var completedLoads = 0
    private let decodingQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "art.otato.prompt.cover-thumbnails"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 2
        return queue
    }()

    init(cacheDirectory: URL? = nil) {
        files = CoverThumbnailFiles(directory: cacheDirectory ?? FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("oTATo/CoverThumbnails-v1", isDirectory: true))
        cache.totalCostLimit = 96 * 1024 * 1024
        cache.countLimit = 128
    }

    func cachedImage(for request: CoverThumbnailRequest) -> NSImage? {
        cache.object(forKey: request.cacheKey)
    }

    /// Feed only two loads at a time, sharing the same decoded cache as the cells.
    func preload(_ requests: [CoverThumbnailRequest],
                 progress: @MainActor (Int, Int) -> Void) async {
        await withTaskGroup(of: Void.self) { group in
            var next = 0
            var completed = 0
            for _ in 0..<min(2, requests.count) {
                let request = requests[next]
                next += 1
                group.addTask { _ = await self.image(for: request, prefetch: true) }
            }
            while await group.next() != nil {
                if Task.isCancelled { group.cancelAll(); break }
                completed += 1
                progress(completed, requests.count)
                if next < requests.count {
                    let request = requests[next]
                    next += 1
                    group.addTask { _ = await self.image(for: request, prefetch: true) }
                }
            }
        }
    }

    func setVisible(_ request: CoverThumbnailRequest?, owner: UUID, visible: Bool) {
        let previous = visibleRequests[owner]
        visibleRequests[owner] = visible ? request : nil
        for candidate in Set([previous, request].compactMap { $0 }) {
            updatePriority(for: candidate)
        }
    }

    private func updatePriority(for request: CoverThumbnailRequest) {
        if let load = pending[request], !load.operation.isExecuting, !load.operation.isFinished {
            load.operation.queuePriority = visibleRequests.values.contains(request) ? .veryHigh : load.defaultPriority
        }
    }

    func image(for request: CoverThumbnailRequest, prefetch: Bool = false) async -> NSImage? {
        if let image = cache.object(forKey: request.cacheKey) { return image }
        if var load = pending[request] {
            if !prefetch {
                load.defaultPriority = .high
                pending[request] = load
                updatePriority(for: request)
            }
            return await load.task.value
        }
        let operation = BlockOperation()
        operation.queuePriority = visibleRequests.values.contains(request) ? .veryHigh : prefetch ? .low : .high
        let files = self.files
        let persistenceQueue = self.persistenceQueue
        let task = Task { () -> NSImage? in
            let decoded: CGImage? = await withCheckedContinuation { continuation in
                operation.addExecutionBlock {
                    if let cached = files.load(request) {
                        continuation.resume(returning: cached)
                        return
                    }
                    // Decode at display resolution off the main thread. An
                    // NSImage(contentsOf:) defers JPEG decoding until drawing.
                    let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
                    guard let source = CGImageSourceCreateWithURL(request.url as CFURL, sourceOptions) else {
                        continuation.resume(returning: nil)
                        return
                    }
                    let options = [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: request.maxPixelSize,
                        kCGImageSourceShouldCacheImmediately: true
                    ] as CFDictionary
                    let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options)
                    continuation.resume(returning: image)
                    if let image {
                        // Persist after returning the image; cache writes never
                        // delay visible loads or run on the main thread.
                        persistenceQueue.addOperation { files.store(image, for: request) }
                    }
                }
                decodingQueue.addOperation(operation)
            }
            guard let decoded else { return nil }
            let image = NSImage(cgImage: decoded,
                                size: NSSize(width: decoded.width, height: decoded.height))
            cache.setObject(image, forKey: request.cacheKey,
                            cost: decoded.bytesPerRow * decoded.height)
            return image
        }
        pending[request] = PendingLoad(task: task, operation: operation, defaultPriority: prefetch ? .low : .high)
        let image = await task.value
        pending[request] = nil
        completedLoads += 1
        if completedLoads % 32 == 1 {
            persistenceQueue.addOperation { files.prune() }
        }
        return image
    }
}

/// Derived, disposable thumbnails live outside the library and backups. TIFF
/// stores the decoded pixels without lossy compression or JPEG resampling.
private struct CoverThumbnailFiles: Sendable {
    let directory: URL

    private func url(for request: CoverThumbnailRequest) -> URL? {
        // Source metadata also protects legacy covers without hashes, and does
        // not assume that a restored file's timestamp precedes the cache write.
        guard let values = try? FileManager.default.attributesOfItem(atPath: request.url.path),
              let bytes = values[.size] as? NSNumber,
              let modified = values[.modificationDate] as? Date else { return nil }
        let stamp = Int64((modified.timeIntervalSince1970 * 1_000).rounded())
        let key = "\(request.url.path)|\(request.revision ?? "")|\(request.maxPixelSize)|\(bytes.int64Value)|\(stamp)"
        let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(digest).appendingPathExtension("tiff")
    }

    func load(_ request: CoverThumbnailRequest) -> CGImage? {
        guard let file = url(for: request),
              let source = CGImageSourceCreateWithURL(file as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }

    func store(_ image: CGImage, for request: CoverThumbnailRequest) {
        let manager = FileManager.default
        guard let file = url(for: request) else { return }
        guard (try? manager.createDirectory(at: directory, withIntermediateDirectories: true)) != nil else { return }
        let temporary = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("tmp")
        defer { try? manager.removeItem(at: temporary) }
        guard let destination = CGImageDestinationCreateWithURL(temporary as CFURL, UTType.tiff.identifier as CFString, 1, nil)
        else { return }
        let options = [kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFCompression: 1]] as CFDictionary
        CGImageDestinationAddImage(destination, image, options)
        guard CGImageDestinationFinalize(destination) else { return }
        if manager.fileExists(atPath: file.path) {
            _ = try? manager.replaceItemAt(file, withItemAt: temporary)
        } else {
            try? manager.moveItem(at: temporary, to: file)
        }
    }

    func prune() {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]) else { return }
        let entries = urls.filter { $0.pathExtension == "tiff" }.compactMap { url -> (URL, Int, Date)? in
            guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
            return (url, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
        }.sorted { $0.2 < $1.2 }
        var size = entries.reduce(0) { $0 + $1.1 }
        for (url, bytes, _) in entries where size > 256 * 1024 * 1024 {
            if (try? FileManager.default.removeItem(at: url)) != nil { size -= bytes }
        }
    }
}

/// Loading and hover updates stay inside the cell; they do not refresh the
/// library or read the original image while the scroll view lays out a frame.
@MainActor
struct CoverThumbnail<Placeholder: View>: View {
    let request: CoverThumbnailRequest?
    let prioritizeVisible: Bool
    @ViewBuilder let placeholder: () -> Placeholder
    @State private var loaded: LoadedCover?

    private struct LoadedCover {
        let request: CoverThumbnailRequest
        let image: NSImage
    }

    init(prompt: Prompt, maxPixelSize: Int, prioritizeVisible: Bool = false,
         @ViewBuilder placeholder: @escaping () -> Placeholder) {
        request = CoverThumbnailRequest(prompt: prompt, maxPixelSize: maxPixelSize)
        self.prioritizeVisible = prioritizeVisible
        self.placeholder = placeholder
        if let request, let image = CoverThumbnailCache.shared.cachedImage(for: request) {
            _loaded = State(initialValue: LoadedCover(request: request, image: image))
        }
    }

    var body: some View {
        Group {
            if let loaded, loaded.request == request {
                Image(nsImage: loaded.image).resizable().scaledToFit()
            } else {
                placeholder()
            }
        }
        .task(id: request) {
            guard let request else { loaded = nil; return }
            guard loaded?.request != request else { return }
            let image = await CoverThumbnailCache.shared.image(for: request, prefetch: prioritizeVisible)
            guard !Task.isCancelled else { return }
            loaded = image.map { LoadedCover(request: request, image: $0) }
        }
        .modifier(ThumbnailVisibilityPriority(request: request, enabled: prioritizeVisible))
    }
}

private struct ThumbnailVisibilityPriority: ViewModifier {
    let request: CoverThumbnailRequest?
    let enabled: Bool
    @State private var owner = UUID()

    @ViewBuilder func body(content: Content) -> some View {
        if enabled {
            content
                // Lazy containers notify appearance for their prepared cells.
                // Avoid a per-image geometry observer running on every frame.
                .onAppear {
                    CoverThumbnailCache.shared.setVisible(request, owner: owner, visible: true)
                }
                .onChange(of: request) { _, value in
                    CoverThumbnailCache.shared.setVisible(value, owner: owner, visible: true)
                }
                .onDisappear { CoverThumbnailCache.shared.setVisible(nil, owner: owner, visible: false) }
        } else {
            content
        }
    }
}
