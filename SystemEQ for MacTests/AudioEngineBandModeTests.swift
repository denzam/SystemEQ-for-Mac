//
//  AudioEngineBandModeTests.swift
//  SystemEQ for MacTests
//
//  Regression tests for applying EQ values right after a band-mode switch:
//  bandMode's didSet rebuilds `bands` only on the next main-loop turn, so a
//  same-turn applyEQValues used to see the stale array and bail out.
//

@testable import SystemEQ_for_Mac
import XCTest

final class AudioEngineBandModeTests: XCTestCase {
    override func tearDown() {
        let engine = AudioEngine.shared
        engine.bandMode = .tenBand
        engine.syncBandsToMode()
        engine.resetAllBands()
        CoreAudioEngine.shared.setEnabled(false)
        super.tearDown()
    }

    // MARK: - Same-turn mode switch + apply

    func testApplyEQValues_rightAfterSwitchTo31Band_appliesAll31() {
        let engine = AudioEngine.shared
        engine.bandMode = .tenBand
        engine.syncBandsToMode()

        let values = (0..<31).map { Float($0 % 5) - 2 }

        // Same main-loop turn as the mode switch — the didSet rebuild has not run yet
        engine.bandMode = .thirtyOneBand
        engine.applyEQValues(values)

        XCTAssertEqual(engine.bands.count, 31, "bands must be rebuilt before applying")
        XCTAssertEqual(engine.bands.map(\.gain), values, "all 31 gains must be applied")
    }

    func testApplyEQValues_rightAfterSwitchBackTo10Band_appliesAll10() {
        let engine = AudioEngine.shared
        engine.bandMode = .thirtyOneBand
        engine.syncBandsToMode()

        let values: [Float] = [1, -1, 2, -2, 3, -3, 4, -4, 5, -5]

        engine.bandMode = .tenBand
        engine.applyEQValues(values)

        XCTAssertEqual(engine.bands.count, 10, "bands must be rebuilt before applying")
        XCTAssertEqual(engine.bands.map(\.gain), values, "all 10 gains must be applied")
    }

    func testApplyEQValues_countMismatch_stillRejected() {
        let engine = AudioEngine.shared
        engine.bandMode = .tenBand
        engine.syncBandsToMode()
        engine.resetAllBands()

        engine.applyEQValues([1, 2, 3])

        XCTAssertEqual(engine.bands.map(\.gain), Array(repeating: Float(0), count: 10))
    }

    // MARK: - CoreAudioEngine guard rails

    // Раніше frequencies[index] за масивом з 31 значення падав out-of-bounds.
    func testApplyFixedBandEQ_oversizedGains_doesNotCrash() {
        let gains = [Float](repeating: 1.0, count: 31)

        CoreAudioEngine.shared.applyFixedBandEQ(gains, preamp: 0)

        // Повернути конфіг у чистий 10-band стан
        CoreAudioEngine.shared.applyFixedBandEQ([Float](repeating: 0, count: 10), preamp: 0)
    }

    // MARK: - Startup state persistence

    func testSetEnabled_routingFailureWithoutPersistence_preservesIntent() throws {
        let suiteName = "AudioEngineBandModeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: "eqWasEnabled")
        var routerPersistence: Bool?
        let engine = AudioEngine(
            defaults: defaults,
            enableRouting: {
                routerPersistence = $0
                return false
            },
            disableRouting: { _ in }
        )

        let succeeded = engine.setEnabled(true, persistState: false)

        XCTAssertFalse(succeeded)
        XCTAssertEqual(routerPersistence, false)
        XCTAssertTrue(defaults.bool(forKey: "eqWasEnabled"))
        XCTAssertFalse(CoreAudioEngine.shared.isEnabled)
    }

    func testSetEnabled_routingFailureFromUserAction_disablesFutureRestore() throws {
        let suiteName = "AudioEngineBandModeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: "eqWasEnabled")
        let engine = AudioEngine(
            defaults: defaults,
            enableRouting: { _ in false },
            disableRouting: { _ in }
        )

        let succeeded = engine.setEnabled(true, persistState: true)

        XCTAssertFalse(succeeded)
        XCTAssertFalse(defaults.bool(forKey: "eqWasEnabled"))
        XCTAssertFalse(CoreAudioEngine.shared.isEnabled)
    }

    func testSetEnabled_routingSuccessFromUserAction_persistsEnabledState() throws {
        let suiteName = "AudioEngineBandModeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(false, forKey: "eqWasEnabled")
        var routerPersistence: Bool?
        let engine = AudioEngine(
            defaults: defaults,
            enableRouting: {
                routerPersistence = $0
                return true
            },
            disableRouting: { _ in }
        )

        let succeeded = engine.setEnabled(true, persistState: true)

        XCTAssertTrue(succeeded)
        XCTAssertEqual(routerPersistence, false)
        XCTAssertTrue(defaults.bool(forKey: "eqWasEnabled"))
        XCTAssertTrue(CoreAudioEngine.shared.isEnabled)
    }

    func testSetEnabled_startupDisable_preservesSavedIntent() throws {
        let suiteName = "AudioEngineBandModeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: "eqWasEnabled")
        var routerPersistence: Bool?
        let engine = AudioEngine(
            defaults: defaults,
            enableRouting: { _ in true },
            disableRouting: { routerPersistence = $0 }
        )

        let succeeded = engine.setEnabled(false, persistState: false)

        XCTAssertTrue(succeeded)
        XCTAssertEqual(routerPersistence, false)
        XCTAssertTrue(defaults.bool(forKey: "eqWasEnabled"))
        XCTAssertFalse(CoreAudioEngine.shared.isEnabled)
    }
}
