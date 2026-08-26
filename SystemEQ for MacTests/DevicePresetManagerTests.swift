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
        PresetPersistence.defaults = suite
    }

    override func tearDown() {
        UserDefaults(suiteName: Self.suiteName)?.removePersistentDomain(forName: Self.suiteName)
        DevicePresetManager.defaults = .standard
        PresetPersistence.defaults = .standard
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

    func testOutputChanged_unmappedDeviceAppliesFlatEQ() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: Self.suiteName))
        defaults.set(true, forKey: DevicePresetManager.autoSwitchKey)
        defaults.set("{\"name\":\"headphones\"}", forKey: "lastAppliedPresetJSON")
        let engine = AudioEngine(
            defaults: defaults,
            enableRouting: { _ in true },
            disableRouting: { _ in }
        )
        engine.bandMode = .thirtyOneBand
        engine.syncBandsToMode()
        engine.applyEQValues([Float](repeating: 4, count: 31))
        engine.setPreampGain(-6)

        DevicePresetManager.shared.outputChanged(to: "unmapped-uid", engine: engine)

        XCTAssertEqual(engine.bands.map(\.gain), [Float](repeating: 0, count: 31))
        XCTAssertEqual(engine.preampGain, 0)
        XCTAssertNil(defaults.string(forKey: "lastAppliedPresetJSON"))
        let saved = try XCTUnwrap(PresetPersistence.load())
        XCTAssertEqual(saved.mode, .thirtyOneBand)
        XCTAssertEqual(saved.gains, [Float](repeating: 0, count: 31))
        XCTAssertEqual(saved.preamp, 0)
        XCTAssertEqual(saved.bassBoost, 0)
    }

    func testOutputChanged_sameDescriptorStillAppliesDeviceValues() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: Self.suiteName))
        defaults.set(true, forKey: DevicePresetManager.autoSwitchKey)
        let record = makeRecord(name: "same")
        defaults.set(record.descriptorJSON, forKey: "lastAppliedPresetJSON")
        DevicePresetManager.shared.recordApply(record, outputUID: "mapped-uid")
        let engine = AudioEngine(
            defaults: defaults,
            enableRouting: { _ in true },
            disableRouting: { _ in }
        )
        engine.bandMode = .thirtyOneBand
        engine.syncBandsToMode()
        engine.resetAllBands()

        DevicePresetManager.shared.outputChanged(to: "mapped-uid", engine: engine)

        XCTAssertEqual(engine.bands.map(\.gain), record.appliedGains)
        XCTAssertEqual(engine.preampGain, record.preamp)
    }

    func testOutputChanged_mappedDeviceSwitchesBandModeBeforeApplyingValues() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: Self.suiteName))
        defaults.set(true, forKey: DevicePresetManager.autoSwitchKey)
        let record = makeRecord(name: "thirty-one-band")
        DevicePresetManager.shared.recordApply(record, outputUID: "mapped-uid")
        let engine = AudioEngine(
            defaults: defaults,
            enableRouting: { _ in true },
            disableRouting: { _ in }
        )
        XCTAssertEqual(engine.bandMode, .tenBand)
        XCTAssertEqual(engine.bands.count, 10)

        DevicePresetManager.shared.outputChanged(to: "mapped-uid", engine: engine)

        XCTAssertEqual(engine.bandMode, .thirtyOneBand)
        XCTAssertEqual(engine.bands.map(\.gain), record.appliedGains)
        XCTAssertEqual(engine.preampGain, record.preamp)
    }

    func testOutputChanged_autoSwitchDisabledLeavesCurrentEQUntouched() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: Self.suiteName))
        let engine = AudioEngine(
            defaults: defaults,
            enableRouting: { _ in true },
            disableRouting: { _ in }
        )
        let gains = [Float](repeating: 2, count: 10)
        engine.applyEQValues(gains)

        DevicePresetManager.shared.outputChanged(to: "unmapped-uid", engine: engine)

        XCTAssertEqual(engine.bands.map(\.gain), gains)
    }

    func testOutputChanged_invalidDeviceRecordAppliesFlatEQ() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: Self.suiteName))
        defaults.set(true, forKey: DevicePresetManager.autoSwitchKey)
        let invalid = DevicePresetRecord(
            mode: EQBandMode.tenBand.rawValue,
            appliedGains: [1, 2],
            cleanGains: [1, 2],
            preamp: -2,
            bassBoost: 0,
            descriptorJSON: "{\"name\":\"invalid\"}"
        )
        DevicePresetManager.shared.recordApply(invalid, outputUID: "invalid-uid")
        let engine = AudioEngine(
            defaults: defaults,
            enableRouting: { _ in true },
            disableRouting: { _ in }
        )
        engine.applyEQValues([Float](repeating: 3, count: 10))

        DevicePresetManager.shared.outputChanged(to: "invalid-uid", engine: engine)

        XCTAssertEqual(engine.bands.map(\.gain), [Float](repeating: 0, count: 10))
        XCTAssertEqual(engine.preampGain, 0)
    }
}
