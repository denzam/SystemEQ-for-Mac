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
}
