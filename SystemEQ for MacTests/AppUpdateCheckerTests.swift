@testable import SystemEQ_for_Mac
import XCTest

@MainActor
final class AppUpdateCheckerTests: XCTestCase {
    func testNewerVersionComparison() {
        XCTAssertTrue(AppUpdateChecker.isNewerVersion("1.4.0", than: "1.3.0"))
        XCTAssertTrue(AppUpdateChecker.isNewerVersion("v2.0", than: "1.9.9"))
        XCTAssertFalse(AppUpdateChecker.isNewerVersion("1.3.0", than: "1.3"))
        XCTAssertFalse(AppUpdateChecker.isNewerVersion("1.2.9", than: "1.3.0"))
    }

    func testVersionComparisonPadsMissingComponents() {
        XCTAssertTrue(AppUpdateChecker.isNewerVersion("1.3.1", than: "1.3"))
        XCTAssertFalse(AppUpdateChecker.isNewerVersion("1.3", than: "1.3.0"))
    }
}
