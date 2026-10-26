import Combine
@testable import SystemEQ_for_Mac
import XCTest

@MainActor
final class AppUpdateCheckerTests: XCTestCase {
    private final class Driver: AppUpdateDriving {
        let subject = CurrentValueSubject<Bool, Never>(false)
        var canCheckForUpdates: Bool {
            subject.value
        }
        var availability: AnyPublisher<Bool, Never> {
            subject.eraseToAnyPublisher()
        }
        let automaticSubject = CurrentValueSubject<Bool, Never>(false)
        var automaticChecksEnabled: Bool {
            get { automaticSubject.value }
            set { automaticSubject.send(newValue) }
        }
        var automaticCheckChanges: AnyPublisher<Bool, Never> {
            automaticSubject.eraseToAnyPublisher()
        }
        var startError: Error?
        var starts = 0
        var checks = 0

        func start() throws {
            starts += 1
            if let startError { throw startError }
            subject.send(true)
        }

        func checkForUpdates() {
            checks += 1
        }
    }

    func testStartsOnceAndUsesTheSameDriverForRepeatedChecks() {
        let driver = Driver()
        let checker = AppUpdateChecker(driver: driver)
        checker.checkForUpdates()
        checker.checkForUpdates()
        XCTAssertEqual(driver.starts, 1)
        XCTAssertEqual(driver.checks, 2)
        XCTAssertTrue(checker.canCheckForUpdates)
        XCTAssertFalse(checker.startupFailed)
    }

    func testFailedStartupCannotCheckOrBecomeAvailableLater() {
        let driver = Driver()
        driver.startError = NSError(domain: "fixture", code: 1)
        let checker = AppUpdateChecker(driver: driver)
        driver.subject.send(true)
        checker.checkForUpdates()
        XCTAssertTrue(checker.startupFailed)
        XCTAssertFalse(checker.canCheckForUpdates)
        XCTAssertEqual(driver.checks, 0)
    }

    func testUnavailableDriverCannotReceiveChecks() {
        let driver = Driver()
        let checker = AppUpdateChecker(driver: driver)
        driver.subject.send(false)
        checker.checkForUpdates()
        XCTAssertFalse(checker.canCheckForUpdates)
        XCTAssertEqual(driver.checks, 0)
        driver.subject.send(true)
        checker.checkForUpdates()
        XCTAssertEqual(driver.checks, 1)
    }

    func testCheckerRetainsDriverUntilItIsReleased() {
        var driver: Driver? = Driver()
        weak var retained = driver
        var checker: AppUpdateChecker? = driver.map { AppUpdateChecker(driver: $0) }
        driver = nil
        XCTAssertNotNil(retained)
        checker?.checkForUpdates()
        XCTAssertEqual(retained?.checks, 1)
        checker = nil
        XCTAssertNil(retained)
    }
    func testAutomaticChecksAreOptInAndDoNotRunForegroundChecks() {
        let driver = Driver()
        let checker = AppUpdateChecker(driver: driver)
        XCTAssertFalse(checker.automaticChecksEnabled)
        checker.setAutomaticChecksEnabled(true)
        XCTAssertTrue(driver.automaticChecksEnabled)
        XCTAssertTrue(checker.automaticChecksEnabled)
        XCTAssertEqual(driver.checks, 0)
        checker.setAutomaticChecksEnabled(false)
        XCTAssertFalse(driver.automaticChecksEnabled)
        XCTAssertFalse(checker.automaticChecksEnabled)
    }

    func testAutomaticPreferenceSurvivesCheckerRecreationAndExternalChanges() {
        let driver = Driver()
        driver.automaticChecksEnabled = true
        var checker: AppUpdateChecker? = AppUpdateChecker(driver: driver)
        XCTAssertTrue(checker?.automaticChecksEnabled == true)
        checker = nil
        let reopened = AppUpdateChecker(driver: driver)
        XCTAssertTrue(reopened.automaticChecksEnabled)
        driver.automaticSubject.send(false)
        XCTAssertFalse(reopened.automaticChecksEnabled)
        XCTAssertEqual(driver.checks, 0)
    }

    func testFailedStartupCannotEnableAutomaticChecks() {
        let driver = Driver()
        driver.startError = NSError(domain: "fixture", code: 2)
        let checker = AppUpdateChecker(driver: driver)
        checker.setAutomaticChecksEnabled(true)
        driver.automaticSubject.send(true)
        XCTAssertFalse(checker.automaticChecksEnabled)
        XCTAssertTrue(checker.startupFailed)
        XCTAssertEqual(driver.checks, 0)
    }

    func testBusyUpdaterCanKeepAutomaticPreferenceWithoutStartingManualCheck() {
        let driver = Driver()
        let checker = AppUpdateChecker(driver: driver)
        driver.subject.send(false)
        checker.setAutomaticChecksEnabled(true)
        checker.checkForUpdates()
        XCTAssertTrue(checker.automaticChecksEnabled)
        XCTAssertEqual(driver.checks, 0)
    }
}
