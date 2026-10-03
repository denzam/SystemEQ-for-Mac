//
//  PresetPersistenceTests.swift
//  SystemEQ for MacTests
//
//  Unit tests for PresetPersistence (UserDefaults-based EQ preset storage)
//

@testable import SystemEQ_for_Mac
import XCTest

final class PresetPersistenceTests: XCTestCase {
    func testInvalidSavePreservesCompletePreviousPreset() {
        let gains = [Float](repeating: 2, count: 10)
        PresetPersistence.save(mode: .tenBand, gains: gains, preamp: -3, bassBoost: 1)
        for invalid in [[Float](repeating: 1, count: 9), [Float](repeating: .nan, count: 31)] {
            PresetPersistence.save(mode: .thirtyOneBand, gains: invalid, preamp: 4, bassBoost: 5)
        }
        PresetPersistence.save(mode: .tenBand, gains: gains, preamp: .infinity)
        PresetPersistence.save(mode: .tenBand, gains: gains, preamp: 0, bassBoost: .nan)
        let loaded = PresetPersistence.load()
        XCTAssertEqual(loaded?.mode, .tenBand)
        XCTAssertEqual(loaded?.gains, gains)
        XCTAssertEqual(loaded?.preamp, -3)
        XCTAssertEqual(loaded?.bassBoost, 1)
    }

    func testInvalidPlaybackSavePreservesPreviousState() {
        let gains = [Float](repeating: 1, count: 31)
        PresetPersistence.savePlaybackState(mode: .thirtyOneBand, gains: gains, preamp: -2)
        PresetPersistence.savePlaybackState(mode: .tenBand, gains: [1], preamp: 0)
        PresetPersistence.savePlaybackState(mode: .thirtyOneBand, gains: gains, preamp: .infinity)
        XCTAssertEqual(PresetPersistence.loadPlaybackState()?.gains, gains)
        XCTAssertEqual(PresetPersistence.loadPlaybackState()?.preamp, -2)
    }

    func testLegacyKeysRemainReadableAndNewSnapshotTakesPrecedence() throws {
        let target = PresetPersistence.defaults
        target.set(EQBandMode.tenBand.rawValue, forKey: "lastPreset.mode")
        try target.set(JSONEncoder().encode([Float](repeating: 1, count: 10)), forKey: "lastPreset.gains")
        target.set(-4.0, forKey: "lastPreset.preamp")
        target.set(2.0, forKey: "lastPreset.bassBoost")
        XCTAssertEqual(PresetPersistence.load()?.preamp, -4)
        XCTAssertEqual(PresetPersistence.loadPlaybackState()?.preamp, -4)
        PresetPersistence.save(mode: .thirtyOneBand, gains: [Float](repeating: 3, count: 31), preamp: -1)
        XCTAssertEqual(PresetPersistence.load()?.mode, .thirtyOneBand)
        XCTAssertEqual(PresetPersistence.loadPlaybackState()?.mode, .thirtyOneBand)
        target.set(EQBandMode.tenBand.rawValue, forKey: "lastPlayback.mode")
        try target.set(JSONEncoder().encode([Float](repeating: 2, count: 10)), forKey: "lastPlayback.gains")
        target.set(-5.0, forKey: "lastPlayback.preamp")
        XCTAssertEqual(PresetPersistence.loadPlaybackState()?.preamp, -5)
        PresetPersistence.savePlaybackState(mode: .thirtyOneBand, gains: [Float](repeating: 4, count: 31), preamp: -6)
        XCTAssertEqual(PresetPersistence.loadPlaybackState()?.preamp, -6)
    }

    // Ізольований suite: тест-хост — реальний застосунок, і запис у .standard
    // стирав би справжній збережений пресет користувача.
    private static let suiteName = "PresetPersistenceTests"

    override func setUpWithError() throws {
        try super.setUpWithError()
        let suite = try XCTUnwrap(UserDefaults(suiteName: Self.suiteName))
        suite.removePersistentDomain(forName: Self.suiteName)
        PresetPersistence.defaults = suite
    }

    override func tearDown() {
        UserDefaults(suiteName: Self.suiteName)?.removePersistentDomain(forName: Self.suiteName)
        PresetPersistence.defaults = .standard
        super.tearDown()
    }

    // MARK: - Suite Isolation

    // Тест-хост — реальний застосунок: запис повз ізольований suite стирав би
    // справжній збережений пресет користувача при кожному прогоні тестів.
    func testSuiteIsolation_standardDefaultsUntouched() {
        let standard = UserDefaults.standard
        let before = standard.dictionaryRepresentation()
            .filter { $0.key.hasPrefix("lastPreset.") || $0.key.hasPrefix("lastPlayback.") }

        PresetPersistence.save(mode: .thirtyOneBand, gains: Array(repeating: 1, count: 31), preamp: -3)
        XCTAssertNotNil(PresetPersistence.defaults.data(forKey: "lastPreset.snapshot"))
        PresetPersistence.clear()

        let after = standard.dictionaryRepresentation()
            .filter { $0.key.hasPrefix("lastPreset.") || $0.key.hasPrefix("lastPlayback.") }
        XCTAssertEqual(before as NSDictionary, after as NSDictionary)
    }

    // MARK: - Save & Load Roundtrip

    func testSaveAndLoad_tenBandMode_roundtrip() {
        let mode = EQBandMode.tenBand
        let gains: [Float] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
        let preamp: Float = 3.5
        let bassBoost: Float = 2.0

        PresetPersistence.save(mode: mode, gains: gains, preamp: preamp, bassBoost: bassBoost)

        guard let loaded = PresetPersistence.load() else {
            XCTFail("Should load saved preset")
            return
        }

        XCTAssertEqual(loaded.mode, mode, "Mode should match")
        XCTAssertEqual(loaded.gains.count, gains.count, "Gains count should match")
        XCTAssertEqual(loaded.preamp, preamp, accuracy: 0.001, "Preamp should match")
        XCTAssertEqual(loaded.bassBoost, bassBoost, accuracy: 0.001, "Bass boost should match")

        // Check individual gains
        for (i, gain) in gains.enumerated() {
            XCTAssertEqual(
                loaded.gains[i],
                gain,
                accuracy: 0.001,
                "Gain at index \(i) should match"
            )
        }
    }

    func testSaveAndLoad_thirtyOneBandMode() {
        let mode = EQBandMode.thirtyOneBand
        let gains: [Float] = Array(repeating: -3.0, count: 31)
        let preamp: Float = -1.5

        PresetPersistence.save(mode: mode, gains: gains, preamp: preamp)

        let loaded = PresetPersistence.load()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.mode, mode)
        XCTAssertEqual(loaded?.gains.count, 31)
    }

    func testSaveAndLoad_zeroGains() {
        let gains: [Float] = Array(repeating: 0.0, count: 10)
        PresetPersistence.save(mode: .tenBand, gains: gains, preamp: 0.0)

        guard let loaded = PresetPersistence.load() else {
            XCTFail("Should load saved preset")
            return
        }
        XCTAssertEqual(loaded.preamp, 0.0, accuracy: 0.001)
    }

    func testSaveAndLoad_negativeValues() {
        let gains: [Float] = [-12.0, -6.0, -3.0, 0.0, 3.0, 6.0, 12.0, -1.0, 0.5, -0.5]
        let preamp: Float = -5.0
        PresetPersistence.save(mode: .tenBand, gains: gains, preamp: preamp)

        guard let loaded = PresetPersistence.load() else {
            XCTFail("Should load saved preset")
            return
        }
        for (i, gain) in gains.enumerated() {
            XCTAssertEqual(
                loaded.gains[i],
                gain,
                accuracy: 0.001,
                "Negative gain at index \(i) should round-trip correctly"
            )
        }
    }

    // MARK: - Clear

    func testClear_removesData() {
        PresetPersistence.save(mode: .tenBand, gains: Array(repeating: 1, count: 10), preamp: 1.0)
        XCTAssertTrue(PresetPersistence.hasSavedPreset, "Should have preset after save")

        PresetPersistence.clear()
        XCTAssertFalse(PresetPersistence.hasSavedPreset, "Should not have preset after clear")
    }

    func testLoad_afterClear_returnsNil() {
        PresetPersistence.save(mode: .tenBand, gains: Array(repeating: 1, count: 10), preamp: 0)
        PresetPersistence.clear()

        let loaded = PresetPersistence.load()
        XCTAssertNil(loaded, "Load after clear should return nil")
    }

    // MARK: - hasSavedPreset

    func testHasSavedPreset_initiallyFalse() {
        XCTAssertFalse(
            PresetPersistence.hasSavedPreset,
            "Should be false with no saved data"
        )
    }

    func testHasSavedPreset_trueAfterSave() {
        PresetPersistence.save(mode: .tenBand, gains: Array(repeating: 0, count: 10), preamp: 0)
        XCTAssertTrue(
            PresetPersistence.hasSavedPreset,
            "Should be true after saving"
        )
    }

    // MARK: - Overwrite

    func testSave_overwritesPrevious() {
        PresetPersistence.save(mode: .tenBand, gains: Array(repeating: 1, count: 10), preamp: 1.0)
        PresetPersistence.save(mode: .thirtyOneBand, gains: Array(repeating: 5.0, count: 31), preamp: 2.0)

        guard let loaded = PresetPersistence.load() else {
            XCTFail("Should load saved preset")
            return
        }
        XCTAssertEqual(loaded.mode, .thirtyOneBand, "Latest save should overwrite")
        XCTAssertEqual(loaded.gains.count, 31, "Latest gains should be stored")
        XCTAssertEqual(loaded.preamp, 2.0, accuracy: 0.001)
    }

    // MARK: - Default Bass Boost

    func testSave_defaultBassBoost_isZero() {
        PresetPersistence.save(mode: .tenBand, gains: Array(repeating: 0, count: 10), preamp: 0)

        guard let loaded = PresetPersistence.load() else {
            XCTFail("Should load saved preset")
            return
        }
        XCTAssertEqual(
            loaded.bassBoost,
            0.0,
            accuracy: 0.001,
            "Default bass boost should be 0.0"
        )
    }

    // MARK: - Playback State

    func testPlaybackState_roundtrip() {
        let gains: [Float] = [1, -2, 3, -4, 5, -6, 7, -8, 9, -10]

        PresetPersistence.savePlaybackState(mode: .tenBand, gains: gains, preamp: -4.5)

        let playback = PresetPersistence.loadPlaybackState()
        XCTAssertEqual(playback?.mode, .tenBand)
        XCTAssertEqual(playback?.gains, gains)
        XCTAssertEqual(playback?.preamp, -4.5)
    }

    func testPlaybackState_fallsBackToLegacyPreset() {
        let gains: [Float] = Array(repeating: 1.5, count: 31)
        PresetPersistence.save(mode: .thirtyOneBand, gains: gains, preamp: -2)

        let playback = PresetPersistence.loadPlaybackState()
        XCTAssertEqual(playback?.mode, .thirtyOneBand)
        XCTAssertEqual(playback?.gains, gains)
        XCTAssertEqual(playback?.preamp, -2)
    }

    func testClear_removesPlaybackState() {
        PresetPersistence.savePlaybackState(mode: .tenBand, gains: Array(repeating: 1, count: 10), preamp: 0)

        PresetPersistence.clear()

        XCTAssertNil(PresetPersistence.loadPlaybackState())
    }
}
