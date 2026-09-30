import Combine
import Foundation
import Sparkle

/// The signed release uses Sparkle's feed and EdDSA public key from Info.plist.
/// Debug builds keep the update UI disabled while the public feed is unpublished.
@MainActor
final class UpdaterService: ObservableObject {
    private let controller: SPUStandardUpdaterController
    private var availabilityObservation: AnyCancellable?
    @Published private(set) var canCheckForUpdates = false

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1",
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        #if !DEBUG
        availabilityObservation = controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] available in self?.canCheckForUpdates = available }
        #endif
    }

    func checkForUpdates() {
        #if !DEBUG
        controller.checkForUpdates(nil)
        #endif
    }
}
