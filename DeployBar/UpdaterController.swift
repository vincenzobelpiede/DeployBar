import Foundation
import Sparkle

/// Thin wrapper around Sparkle's SPUStandardUpdaterController so the rest of
/// the app can call `UpdaterController.shared.checkForUpdates()` from a
/// SwiftUI button without dragging Sparkle types into the views.
@MainActor
final class UpdaterController: NSObject, ObservableObject, SPUUpdaterDelegate {
    static let shared = UpdaterController()

    private(set) lazy var controller: SPUStandardUpdaterController = {
        SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
    }()

    @Published var canCheckForUpdates: Bool = true

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
