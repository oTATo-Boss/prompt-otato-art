import AppKit
import Combine
import SwiftData
import SwiftUI

/// One preparation pass per process. Hiding the main window does not reset it.
@MainActor
final class AppStartupState: ObservableObject {
    @Published private(set) var isReady = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    @Published private(set) var progress = 0.0
    @Published private(set) var status = "正在准备资料库…"
    @Published private(set) var error: String?
    private var preparation: Task<Void, Never>?
    private var backgroundPreparation: Task<Void, Never>?
    private var dataPrepared = false
    private var layoutPrepared = false

    func prepare(in container: ModelContainer) {
        guard !isReady, preparation == nil else { return }
        error = nil
        preparation = Task { [self] in
            do {
                let context = container.mainContext
                let prompts = try context.fetch(FetchDescriptor<Prompt>()).filter { $0.deletedAt == nil }
                let folders = try context.fetch(FetchDescriptor<Folder>()).filter { $0.deletedAt == nil }
                let sort = PromptLibrarySort(rawValue: UserDefaults.standard.string(forKey: "library.sort") ?? "") ?? .updated
                let ordered = sort.sorted(prompts)
                PromptSearch.pruneIndex(keeping: Set(prompts.map(\.id)))
                // Prepare enough for the largest supported first viewport; large
                // libraries do not delay opening while every body is indexed.
                let initial = Array(ordered.prefix(32))
                async let initialIndex: Void = PromptSearch.prepareIndex(initial, folders: folders)
                let pixels = UserDefaults.standard.string(forKey: "library.viewMode") == "list" ? [192] : [768, 192]
                let requests = thumbnailWorkingSet(initial, pixelSizes: pixels)
                progress = 0.1
                status = "正在准备首屏与封面…"
                await CoverThumbnailCache.shared.preload(requests) { completed, total in
                    // Updating the loading label should not invalidate the entire library.
                    let next = 0.1 + 0.85 * Double(completed) / Double(max(1, total))
                    if next - self.progress >= 0.02 || completed == total { self.progress = next }
                }
                await initialIndex
                dataPrepared = true
                status = "正在准备界面…"
                finishIfPrepared()
                // The remaining work yields in small batches and shares both cache
                // budgets. It finishes once; hiding the window adds no timer or loop.
                backgroundPreparation = Task(priority: .utility) { [weak self] in
                    guard let self else { return }
                    await PromptSearch.prepareIndex(ordered, folders: folders)
                    guard !Task.isCancelled else { return }
                    await CoverThumbnailCache.shared.preload(self.thumbnailWorkingSet(ordered)) { _, _ in }
                }
            } catch {
                self.error = error.localizedDescription
                preparation = nil
            }
        }
    }

    func didPrepareLayout() {
        layoutPrepared = true
        finishIfPrepared()
    }

    private func finishIfPrepared() {
        guard dataPrepared, layoutPrepared, !isReady else { return }
        progress = 1
        isReady = true
        preparation = nil
    }

    func cancelBackgroundPreparation() {
        backgroundPreparation?.cancel()
        backgroundPreparation = nil
    }

    private func thumbnailWorkingSet(_ prompts: [Prompt], pixelSizes: [Int] = [768, 192]) -> [CoverThumbnailRequest] {
        // Keep startup bounded for very large libraries. Reserve room for visible
        // cells and detail covers inside the shared 96 MiB decoded-image cache.
        var requests: [CoverThumbnailRequest] = []
        var seen: Set<CoverThumbnailRequest> = []
        var bytes = 0
        for prompt in prompts {
            for pixels in pixelSizes {
                guard let request = CoverThumbnailRequest(prompt: prompt, maxPixelSize: pixels),
                      !seen.contains(request) else { continue }
                let width = Double(max(1, prompt.coverWidth ?? pixels))
                let height = Double(max(1, prompt.coverHeight ?? pixels))
                let scale = min(1, Double(pixels) / max(width, height))
                let cost = Int(ceil(width * scale) * ceil(height * scale)) * 4
                guard requests.count < 128, bytes + cost <= 80 * 1024 * 1024 else { return requests }
                requests.append(request)
                seen.insert(request)
                bytes += cost
            }
        }
        return requests
    }
}

struct StartupLoadingView: View {
    @ObservedObject var startup: AppStartupState
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image("BrandMark").resizable().renderingMode(.template).scaledToFit().frame(width: 48, height: 48)
            Text("oTATo prompt").font(.title2.weight(.semibold))
            if let error = startup.error {
                Text(error).font(.callout).foregroundStyle(.secondary)
                Button("重新准备", action: retry)
            } else {
                ProgressView(value: startup.progress).frame(width: 200)
                Text(startup.status).font(.callout).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
    }
}

/// Observe the real window and finish an initial layout behind the loading view.
struct StartupWindowAttachment: NSViewRepresentable {
    let app: AppCoordinator

    func makeNSView(context: Context) -> AttachmentView { AttachmentView(app: app) }
    func updateNSView(_ view: AttachmentView, context: Context) {}

    final class AttachmentView: NSView {
        private let app: AppCoordinator
        init(app: AppCoordinator) { self.app = app; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError("Created programmatically") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            app.retainMainWindow(window)
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window else { return }
                window.contentView?.layoutSubtreeIfNeeded()
                self.app.startup.didPrepareLayout()
            }
        }
    }
}

@MainActor
final class MainWindowRetentionDelegate: NSObject, NSWindowDelegate {
    private weak var original: NSWindowDelegate?
    init(forwarding original: NSWindowDelegate?) { self.original = original }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard original?.windowShouldClose?(sender) != false else { return false }
        // Keep the collection's reusable hosts, scroll position and decoded covers.
        sender.orderOut(nil)
        return false
    }

    override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || original?.responds(to: selector) == true
    }

    override func forwardingTarget(for selector: Selector!) -> Any? {
        if original?.responds(to: selector) == true { return original }
        return super.forwardingTarget(for: selector)
    }
}

@MainActor
final class AppLifetimeDelegate: NSObject, NSApplicationDelegate {
    weak var coordinator: AppCoordinator?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag, coordinator?.reopenMainWindow() == true { return false }
        return true
    }
}
