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
}
