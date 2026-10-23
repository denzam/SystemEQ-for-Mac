import Combine
import Foundation
import Sparkle

// MARK: - Update Driver

@MainActor
protocol AppUpdateDriving: AnyObject {
    var canCheckForUpdates: Bool { get }
    var availability: AnyPublisher<Bool, Never> { get }
    func start() throws
    func checkForUpdates()
}

@MainActor
private final class SparkleUpdateDriver: AppUpdateDriving {
    private let controller = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    var canCheckForUpdates: Bool {
        controller.updater.canCheckForUpdates
    }
    var availability: AnyPublisher<Bool, Never> {
        controller.updater.publisher(for: \.canCheckForUpdates).eraseToAnyPublisher()
    }

    func start() throws {
        controller.updater.automaticallyChecksForUpdates = false
        controller.updater.automaticallyDownloadsUpdates = false
        controller.updater.sendsSystemProfile = false
        try controller.updater.start()
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}

// MARK: - App Update Checker

@MainActor
final class AppUpdateChecker: ObservableObject {
    static let shared = AppUpdateChecker(driver: SparkleUpdateDriver())

    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var startupFailed = false

    private let driver: any AppUpdateDriving
    private var started = false
    private var observation: AnyCancellable?

    init(driver: any AppUpdateDriving) {
        self.driver = driver
        observation = driver.availability.sink { [weak self] available in
            guard let self else { return }
            canCheckForUpdates = started && available
        }
        do {
            try driver.start()
            started = true
            canCheckForUpdates = driver.canCheckForUpdates
        } catch {
            startupFailed = true
            dlog("Update service could not start: \(error.localizedDescription)", category: .general)
        }
    }

    func checkForUpdates() {
        guard started, canCheckForUpdates else { return }
        driver.checkForUpdates()
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }
}
