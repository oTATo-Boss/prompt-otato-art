import Combine
import Foundation
import Sparkle

/// The signed release uses Sparkle's feed and EdDSA public key from Info.plist.
/// Development builds never contact the public update feed.
@MainActor
final class UpdaterService: ObservableObject {
    private let controller: SPUStandardUpdaterController
    private var observations = Set<AnyCancellable>()
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = false

    var isAvailable: Bool {
        #if DEBUG
        false
        #else
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1"
        #endif
    }

    init() {
        #if DEBUG
        let startsUpdater = false
        #else
        let startsUpdater = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1"
        #endif
        controller = SPUStandardUpdaterController(
            startingUpdater: startsUpdater,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        #if !DEBUG
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] available in self?.canCheckForUpdates = available }
            .store(in: &observations)
        controller.updater.publisher(for: \.automaticallyChecksForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in self?.automaticallyChecksForUpdates = enabled }
            .store(in: &observations)
        #endif
    }

    func checkForUpdates() {
        #if !DEBUG
        guard canCheckForUpdates else { return }
        controller.checkForUpdates(nil)
        #endif
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        #if !DEBUG
        guard isAvailable else { return }
        controller.updater.automaticallyChecksForUpdates = enabled
        #endif
    }
}
