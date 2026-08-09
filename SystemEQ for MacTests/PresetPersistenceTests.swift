//
//  PresetPersistenceTests.swift
//  SystemEQ for MacTests
//
//  Unit tests for PresetPersistence (UserDefaults-based EQ preset storage)
//

@testable import SystemEQ_for_Mac
import XCTest

final class PresetPersistenceTests: XCTestCase {
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
        PresetPersistence.save(mode: .tenBand, gains: [1, 2, 3], preamp: 1.0)
        XCTAssertTrue(PresetPersistence.hasSavedPreset, "Should have preset after save")

        PresetPersistence.clear()
        XCTAssertFalse(PresetPersistence.hasSavedPreset, "Should not have preset after clear")
    }

    func testLoad_afterClear_returnsNil() {
        PresetPersistence.save(mode: .tenBand, gains: [1], preamp: 0)
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
        PresetPersistence.save(mode: .tenBand, gains: [0], preamp: 0)
        XCTAssertTrue(
            PresetPersistence.hasSavedPreset,
            "Should be true after saving"
        )
    }

    // MARK: - Overwrite

    func testSave_overwritesPrevious() {
        PresetPersistence.save(mode: .tenBand, gains: [1, 2, 3], preamp: 1.0)
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
        PresetPersistence.save(mode: .tenBand, gains: [0], preamp: 0)

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
}
