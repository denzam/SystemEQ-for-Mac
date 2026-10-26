import Combine
import Foundation
import Sparkle

// MARK: - Update Driver

@MainActor
protocol AppUpdateDriving: AnyObject {
    var canCheckForUpdates: Bool { get }
    var availability: AnyPublisher<Bool, Never> { get }
    var automaticChecksEnabled: Bool { get set }
    var automaticCheckChanges: AnyPublisher<Bool, Never> { get }
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

    var automaticChecksEnabled: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    var automaticCheckChanges: AnyPublisher<Bool, Never> {
        controller.updater.publisher(for: \.automaticallyChecksForUpdates).eraseToAnyPublisher()
    }

    func start() throws {
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
    @Published private(set) var automaticChecksEnabled = false

    private let driver: any AppUpdateDriving
    private var started = false
    private var observation: AnyCancellable?
    private var automaticCheckObservation: AnyCancellable?

    init(driver: any AppUpdateDriving) {
        self.driver = driver
        observation = driver.availability.sink { [weak self] available in
            guard let self else { return }
            canCheckForUpdates = started && available
        }
        automaticCheckObservation = driver.automaticCheckChanges.sink { [weak self] enabled in
            guard let self else { return }
            automaticChecksEnabled = started && enabled
        }
        do {
            try driver.start()
            started = true
            canCheckForUpdates = driver.canCheckForUpdates
            automaticChecksEnabled = driver.automaticChecksEnabled
        } catch {
            startupFailed = true
            dlog("Update service could not start: \(error.localizedDescription)", category: .general)
        }
    }

    func checkForUpdates() {
        guard started, canCheckForUpdates else { return }
        driver.checkForUpdates()
    }

    func setAutomaticChecksEnabled(_ enabled: Bool) {
        guard started else { return }
        driver.automaticChecksEnabled = enabled
        automaticChecksEnabled = driver.automaticChecksEnabled
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }
}
