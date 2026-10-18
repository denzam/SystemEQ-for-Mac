//
//  DevicePresetManagerTests.swift
//  SystemEQ for MacTests
//
//  Storage roundtrip for the per-output preset map (issue #31)
//

import Combine
@testable import SystemEQ_for_Mac
import XCTest

@MainActor
final class DevicePresetManagerTests: XCTestCase {
    private static let suiteName = "DevicePresetManagerTests"
    private var manager: DevicePresetManager!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let suite = try XCTUnwrap(UserDefaults(suiteName: Self.suiteName))
        suite.removePersistentDomain(forName: Self.suiteName)
        DevicePresetManager.defaults = suite
        PresetPersistence.defaults = suite
        manager = DevicePresetManager()
    }

    override func tearDown() {
        UserDefaults(suiteName: Self.suiteName)?.removePersistentDomain(forName: Self.suiteName)
        manager = nil
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
        let scarlett = makeRecord(name: "HE400se")
        let speakers = makeRecord(name: "eris")

        manager.recordApply(scarlett, outputUID: "scarlett-uid")
        manager.recordApply(speakers, outputUID: "speakers-uid")

        XCTAssertEqual(manager.record(for: "scarlett-uid"), scarlett)
        XCTAssertEqual(manager.record(for: "speakers-uid"), speakers)
        XCTAssertNil(manager.record(for: "unknown-uid"))
    }

    func testRecordApply_overwritesSameDevice() {
        manager.recordApply(makeRecord(name: "old"), outputUID: "uid")
        let newer = makeRecord(name: "new")
        manager.recordApply(newer, outputUID: "uid")

        XCTAssertEqual(manager.record(for: "uid"), newer)
    }

    func testSuiteIsolation_standardDefaultsUntouched() {
        let before = UserDefaults.standard.data(forKey: "devicePresets.v1")

        manager.recordApply(makeRecord(name: "x"), outputUID: "uid")

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

        manager.outputChanged(to: "unmapped-uid", engine: engine)

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
        manager.recordApply(record, outputUID: "mapped-uid")
        let engine = AudioEngine(
            defaults: defaults,
            enableRouting: { _ in true },
            disableRouting: { _ in }
        )
        engine.bandMode = .thirtyOneBand
        engine.syncBandsToMode()
        engine.resetAllBands()

        manager.outputChanged(to: "mapped-uid", engine: engine)

        XCTAssertEqual(engine.bands.map(\.gain), record.appliedGains)
        XCTAssertEqual(engine.preampGain, record.preamp)
    }

    func testOutputChanged_mappedDeviceSwitchesBandModeBeforeApplyingValues() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: Self.suiteName))
        defaults.set(true, forKey: DevicePresetManager.autoSwitchKey)
        let record = makeRecord(name: "thirty-one-band")
        manager.recordApply(record, outputUID: "mapped-uid")
        let engine = AudioEngine(
            defaults: defaults,
            enableRouting: { _ in true },
            disableRouting: { _ in }
        )
        XCTAssertEqual(engine.bandMode, .tenBand)
        XCTAssertEqual(engine.bands.count, 10)

        manager.outputChanged(to: "mapped-uid", engine: engine)

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

        manager.outputChanged(to: "unmapped-uid", engine: engine)

        XCTAssertEqual(engine.bands.map(\.gain), gains)
    }

    func testOutputChanged_publishesCompletedSnapshotForSameModeAndDescriptor() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: Self.suiteName))
        defaults.set(true, forKey: DevicePresetManager.autoSwitchKey)
        let engine = AudioEngine(defaults: defaults, enableRouting: { _ in true }, disableRouting: { _ in })
        for mode in EQBandMode.allCases {
            engine.bandMode = mode
            var received: [DevicePresetManager.AppliedPreset] = []
            let observation = manager.$appliedPreset.compactMap(\.self).sink { event in
                guard event.context.outputUID.hasPrefix(mode.rawValue) else { return }
                received.append(event)
                XCTAssertEqual(engine.bandMode, mode)
                XCTAssertEqual(engine.bands.map(\.gain), event.record?.appliedGains)
                XCTAssertEqual(engine.preampGain, event.record?.preamp)
                XCTAssertEqual(PresetPersistence.load()?.gains, event.record?.cleanGains)
                XCTAssertEqual(defaults.string(forKey: "lastAppliedPresetJSON"), event.record?.descriptorJSON)
            }
            for (index, value) in [Float(1), Float(3)].enumerated() {
                let uid = mode.rawValue + "-" + String(index)
                let record = DevicePresetRecord(
                    mode: mode.rawValue,
                    appliedGains: [Float](repeating: value, count: mode.bandCount),
                    cleanGains: [Float](repeating: value - 0.5, count: mode.bandCount),
                    preamp: -value,
                    bassBoost: 0.5,
                    descriptorJSON: "{\"name\":\"same\"}"
                )
                manager.recordApply(record, outputUID: uid)
                manager.outputChanged(to: uid, engine: engine)
            }
            XCTAssertEqual(received.count, 2)
            XCTAssertNotEqual(received.first?.context.revision, received.last?.context.revision)
            XCTAssertNotEqual(received.first?.record?.appliedGains, received.last?.record?.appliedGains)
            observation.cancel()
        }
    }

    func testOutputChanged_flatPublicationFollowsEngineAndPersistenceReset() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: Self.suiteName))
        defaults.set(true, forKey: DevicePresetManager.autoSwitchKey)
        let engine = AudioEngine(defaults: defaults, enableRouting: { _ in true }, disableRouting: { _ in })
        engine.applyEQValues([Float](repeating: 3, count: 10))
        engine.setPreampGain(-4)
        defaults.set("old", forKey: "lastAppliedPresetJSON")
        var received = false
        let observation = manager.$appliedPreset.compactMap(\.self).sink { event in
            received = true
            XCTAssertNil(event.record)
            XCTAssertEqual(event.context.outputUID, "unmapped")
            XCTAssertEqual(engine.bands.map(\.gain), [Float](repeating: 0, count: 10))
            XCTAssertEqual(engine.preampGain, 0)
            XCTAssertEqual(PresetPersistence.load()?.bassBoost, 0)
            XCTAssertNil(defaults.string(forKey: "lastAppliedPresetJSON"))
        }
        manager.outputChanged(to: "unmapped", engine: engine)
        XCTAssertTrue(received)
        observation.cancel()
    }

    func testOutputChanged_disabledPublishesOnlyNewContext() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: Self.suiteName))
        let engine = AudioEngine(defaults: defaults, enableRouting: { _ in true }, disableRouting: { _ in })
        engine.applyEQValues([Float](repeating: 2, count: 10))
        var contexts: [DevicePresetManager.OutputContext] = []
        var appliedCount = 0
        let contextObservation = manager.$outputContext.compactMap(\.self).sink { contexts.append($0) }
        let appliedObservation = manager.$appliedPreset.compactMap(\.self).sink { _ in appliedCount += 1 }
        manager.outputChanged(to: "A", engine: engine)
        manager.outputChanged(to: "B", engine: engine)
        XCTAssertEqual(contexts.map(\.outputUID), ["A", "B"])
        XCTAssertEqual(contexts.map(\.revision), [1, 2])
        XCTAssertEqual(appliedCount, 0)
        XCTAssertEqual(engine.bands.map(\.gain), [Float](repeating: 2, count: 10))
        contextObservation.cancel()
        appliedObservation.cancel()
    }

    func testRecordApply_doesNotPublishADeviceSwitch() {
        manager.recordApply(makeRecord(name: "save"), outputUID: "A")
        XCTAssertNil(manager.outputContext)
        XCTAssertNil(manager.appliedPreset)
    }

    func testOutputChanged_refreshesBoundAutoEQStateWithoutReapplying() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: Self.suiteName))
        defaults.set(true, forKey: DevicePresetManager.autoSwitchKey)
        for mode in EQBandMode.allCases {
            let engine = AudioEngine(defaults: defaults, enableRouting: { _ in true }, disableRouting: { _ in })
            engine.bandMode = mode
            engine.syncBandsToMode()
            var uid: String? = mode.rawValue + "-A"
            var ownerApplies = 0
            var ownerSaves = 0
            let state = AutoEQState(
                engine: AutoEQState.Engine(
                    mode: { engine.bandMode },
                    setMode: { engine.bandMode = $0 },
                    gains: { engine.getCurrentEQValues() },
                    preamp: { engine.preampGain },
                    setPreamp: { engine.setPreampGain($0) },
                    headroom: { engine.importPreampLimit(mode: $0, gains: $1) },
                    apply: { ownerApplies += 1; engine.applyEQValues($0) },
                    enabled: { engine.isEnabled },
                    enable: { XCTFail("Refresh must not enable routing") }
                ),
                defaults: defaults,
                outputUID: { uid },
                sampleRate: { 48000 },
                persist: { _, _, _, _ in ownerSaves += 1 },
                recordApply: { _, _ in XCTFail("Refresh must not record another apply") }
            )
            state.bind(to: manager)
            for suffix in ["A", "B"] {
                uid = mode.rawValue + "-" + suffix
                let value: Float = suffix == "A" ? 1 : 3
                let record = DevicePresetRecord(
                    mode: mode.rawValue,
                    appliedGains: [Float](repeating: value, count: mode.bandCount),
                    cleanGains: [Float](repeating: value, count: mode.bandCount),
                    preamp: -value,
                    bassBoost: value,
                    descriptorJSON: "{\"name\":\"\(suffix)\"}"
                )
                manager.recordApply(record, outputUID: uid)
                try manager.outputChanged(to: XCTUnwrap(uid), engine: engine)
                XCTAssertEqual(state.activePresetName, suffix)
                XCTAssertEqual(state.bandMode.audioEngineMode, mode)
                XCTAssertEqual(state.preampDB, Double(-value))
                XCTAssertEqual(state.bassBoost, Double(value))
                XCTAssertEqual(state.mapped.count, mode.bandCount)
                for (band, actual) in zip(state.mapped, engine.getCurrentEQValues()) {
                    XCTAssertEqual(
                        band.gain + BassBoostCurve.gain(at: band.center, amount: state.bassBoost),
                        Double(actual),
                        accuracy: 0.0001
                    )
                }
            }
            uid = mode.rawValue + "-unmapped"
            try manager.outputChanged(to: XCTUnwrap(uid), engine: engine)
            XCTAssertNil(state.appliedIdentity)
            XCTAssertEqual(state.bassBoost, 0)
            XCTAssertEqual(state.mapped.map(\.gain), [Double](repeating: 0, count: mode.bandCount))
            XCTAssertEqual(ownerApplies, 0)
            XCTAssertEqual(ownerSaves, 0)
        }
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
        manager.recordApply(invalid, outputUID: "invalid-uid")
        let engine = AudioEngine(
            defaults: defaults,
            enableRouting: { _ in true },
            disableRouting: { _ in }
        )
        engine.applyEQValues([Float](repeating: 3, count: 10))

        manager.outputChanged(to: "invalid-uid", engine: engine)

        XCTAssertEqual(engine.bands.map(\.gain), [Float](repeating: 0, count: 10))
        XCTAssertEqual(engine.preampGain, 0)
        XCTAssertEqual(manager.appliedPreset?.context.outputUID, "invalid-uid")
        XCTAssertNil(manager.appliedPreset?.record)
    }
}
