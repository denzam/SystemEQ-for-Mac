@testable import SystemEQ_for_Mac
import XCTest

final class ProjectMHelperClientTests: XCTestCase {
    func testStartupCommandsReplayNonDefaultIntent() {
        XCTAssertEqual(
            ProjectMHelperClient.startupCommands(
                category: "Fractals",
                weight: "Heavy",
                quality: "Low",
                shuffle: false,
                locked: true
            ),
            ["CATEGORY:Fractals", "WEIGHT:Heavy", "QUALITY:Low", "SHUFFLE:0", "LOCK:1"]
        )
    }

    func testStartupCommandsOmitHelperDefaults() {
        XCTAssertTrue(
            ProjectMHelperClient.startupCommands(
                category: "All",
                weight: "All",
                quality: "High",
                shuffle: true,
                locked: false
            ).isEmpty
        )
    }

    func testReportedSelectionReplacesSynchronizedIntent() {
        XCTAssertTrue(ProjectMHelperClient.shouldAdoptReportedSelection(selected: "Heavy", current: "Heavy"))
    }

    func testReportedSelectionDoesNotReplacePendingIntent() {
        XCTAssertFalse(ProjectMHelperClient.shouldAdoptReportedSelection(selected: "Heavy", current: "All"))
    }
}
