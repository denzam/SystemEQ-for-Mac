//
//  DevicePresetManagerTests.swift
//  SystemEQ for MacTests
//
//  Storage roundtrip for the per-output preset map (issue #31)
//

@testable import SystemEQ_for_Mac
import XCTest

@MainActor
final class DevicePresetManagerTests: XCTestCase {
    private static let suiteName = "DevicePresetManagerTests"

    override func setUpWithError() throws {
        try super.setUpWithError()
        let suite = try XCTUnwrap(UserDefaults(suiteName: Self.suiteName))
        suite.removePersistentDomain(forName: Self.suiteName)
        DevicePresetManager.defaults = suite
    }

    override func tearDown() {
        UserDefaults(suiteName: Self.suiteName)?.removePersistentDomain(forName: Self.suiteName)
        DevicePresetManager.defaults = .standard
        super.tearDown()
    }

    private func makeRecord(name: String) -> DevicePresetRecord {
        DevicePresetRecord(
            mode: EQBandMode.thirtyOneBand.rawValue,
            appliedGains: [Float](repeating: 1.5, count: 31),
            cleanGains: [Float](repeating: 1.0, count: 31),
            preamp: -3.5,
            bassBoost: 2.0,
            descriptorJSON: "{\"name\":\"\(name)\"}"
        )
    }

    func testRecordApply_roundtripPerDevice() {
        let manager = DevicePresetManager.shared
        let scarlett = makeRecord(name: "HE400se")
        let speakers = makeRecord(name: "eris")

        manager.recordApply(scarlett, outputUID: "scarlett-uid")
        manager.recordApply(speakers, outputUID: "speakers-uid")

        XCTAssertEqual(manager.record(for: "scarlett-uid"), scarlett)
        XCTAssertEqual(manager.record(for: "speakers-uid"), speakers)
        XCTAssertNil(manager.record(for: "unknown-uid"))
    }

    func testRecordApply_overwritesSameDevice() {
        let manager = DevicePresetManager.shared

        manager.recordApply(makeRecord(name: "old"), outputUID: "uid")
        let newer = makeRecord(name: "new")
        manager.recordApply(newer, outputUID: "uid")

        XCTAssertEqual(manager.record(for: "uid"), newer)
    }

    func testSuiteIsolation_standardDefaultsUntouched() {
        let before = UserDefaults.standard.data(forKey: "devicePresets.v1")

        DevicePresetManager.shared.recordApply(makeRecord(name: "x"), outputUID: "uid")

        XCTAssertEqual(UserDefaults.standard.data(forKey: "devicePresets.v1"), before)
    }
}
