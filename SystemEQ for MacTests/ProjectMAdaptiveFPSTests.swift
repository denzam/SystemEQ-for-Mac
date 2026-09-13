@testable import SystemEQ_for_Mac
import XCTest

@MainActor
final class ProjectMAdaptiveFPSTests: XCTestCase {
    func testFirstMeasurementIsWarmupOnly() {
        var controller = ProjectMAdaptiveFPS()

        XCTAssertEqual(controller.observe(measuredFPS: 12, presetLocked: false, hasPresetPath: true), .warmup)
        XCTAssertEqual(controller.adaptiveScale, 1.0)
    }

    func testLowFPSReducesScaleBeforeConsideringPresetSkip() {
        var controller = ProjectMAdaptiveFPS()
        _ = controller.observe(measuredFPS: 60, presetLocked: false, hasPresetPath: true)

        let decisions = (0..<3).map { _ in
            controller.observe(measuredFPS: 20, presetLocked: false, hasPresetPath: true)
        }

        XCTAssertEqual(decisions, [
            .reduceScale(to: 0.75),
            .reduceScale(to: 0.5),
            .reduceScale(to: 0.25)
        ])
        XCTAssertEqual(controller.adaptiveScale, 0.25)
    }

    func testMinimumScaleSkipsUnlockedPresetAfterTwoLowFPSWindows() {
        var controller = ProjectMAdaptiveFPS()
        _ = controller.observe(measuredFPS: 60, presetLocked: false, hasPresetPath: true)

        for _ in 0..<3 {
            _ = controller.observe(measuredFPS: 20, presetLocked: false, hasPresetPath: true)
        }

        XCTAssertEqual(controller.observe(measuredFPS: 20, presetLocked: false, hasPresetPath: true), .unchanged)
        XCTAssertEqual(controller.observe(measuredFPS: 20, presetLocked: false, hasPresetPath: true), .skipPreset)
    }

    func testLockedPresetNeverSkipsAndHealthyWindowClearsLowFPSCount() {
        var controller = ProjectMAdaptiveFPS()
        _ = controller.observe(measuredFPS: 60, presetLocked: false, hasPresetPath: true)

        for _ in 0..<3 {
            _ = controller.observe(measuredFPS: 20, presetLocked: false, hasPresetPath: true)
        }

        XCTAssertEqual(controller.observe(measuredFPS: 20, presetLocked: true, hasPresetPath: true), .unchanged)
        XCTAssertEqual(controller.observe(measuredFPS: 20, presetLocked: true, hasPresetPath: true), .unchanged)
        XCTAssertEqual(controller.observe(measuredFPS: 60, presetLocked: true, hasPresetPath: true), .unchanged)
        XCTAssertEqual(controller.observe(measuredFPS: 20, presetLocked: false, hasPresetPath: true), .unchanged)
        XCTAssertEqual(controller.observe(measuredFPS: 20, presetLocked: false, hasPresetPath: true), .skipPreset)
    }

    func testResetRestoresFullScaleAndWarmup() {
        var controller = ProjectMAdaptiveFPS()
        _ = controller.observe(measuredFPS: 60, presetLocked: false, hasPresetPath: true)
        _ = controller.observe(measuredFPS: 20, presetLocked: false, hasPresetPath: true)

        controller.reset()

        XCTAssertEqual(controller.adaptiveScale, 1.0)
        XCTAssertEqual(controller.observe(measuredFPS: 20, presetLocked: false, hasPresetPath: true), .warmup)
    }
}
