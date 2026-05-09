//
//  EQConverterTests.swift
//  SystemEQ for MacTests
//
//  Unit tests for EQConverter
//

@testable import SystemEQ_for_Mac
import XCTest

final class EQConverterTests: XCTestCase {
    let converter = EQConverter.shared

    // MARK: - 10-Band Fixed EQ Conversion

    func testConvertToFixedBand_emptyBands_returnsAllZeros() {
        let result = converter.convertToFixedBand([], preampGain: 0)

        XCTAssertEqual(result.count, 10, "Should return 10 bands")
        for (i, gain) in result.enumerated() {
            XCTAssertEqual(
                gain,
                0.0,
                accuracy: 0.001,
                "Empty bands with zero preamp should produce zero gain at index \(i)"
            )
        }
    }

    func testConvertToFixedBand_withPreamp_addsOffset() {
        let preamp: Float = 3.0
        let result = converter.convertToFixedBand([], preampGain: preamp)

        XCTAssertEqual(result.count, 10)
        for (i, gain) in result.enumerated() {
            XCTAssertEqual(
                gain,
                preamp,
                accuracy: 0.001,
                "Empty bands with preamp should equal preamp at index \(i)"
            )
        }
    }

    func testConvertToFixedBand_singlePeakBand_maxAtCenter() {
        // Create a peak filter at 1000 Hz with +6 dB gain
        let band = ParametricBand(frequency: 1000, gain: 6.0, q: 1.0, filterType: .peak)
        let result = converter.convertToFixedBand([band], preampGain: 0)

        XCTAssertEqual(result.count, 10)

        // Find index closest to 1000 Hz in 10-band (index 5 = 1000 Hz)
        let centerIndex = 5
        let centerGain = result[centerIndex]

        // Center frequency should have the highest gain
        XCTAssertGreaterThan(
            centerGain,
            5.0,
            "Peak at 1000 Hz should produce significant gain at 1000 Hz band"
        )

        // Distant frequencies should have much less gain
        let lowGain = result[0] // 31.5 Hz
        XCTAssertLessThan(
            abs(lowGain),
            centerGain,
            "Band at 31.5 Hz should have less effect than center"
        )
    }

    func testConvertToFixedBand_lowShelfBand() {
        let band = ParametricBand(frequency: 100, gain: 6.0, q: 0.7, filterType: .lowShelf)
        let result = converter.convertToFixedBand([band], preampGain: 0)

        // Low frequencies should be boosted
        XCTAssertGreaterThan(
            result[0],
            0.0,
            "Low shelf should boost 31.5 Hz"
        )
        XCTAssertGreaterThan(
            result[1],
            0.0,
            "Low shelf should boost 63 Hz"
        )

        // High frequencies should be mostly unaffected
        let highFreqGain = result[9] // 16 kHz
        XCTAssertLessThan(
            abs(highFreqGain),
            1.0,
            "Low shelf should not affect 16 kHz significantly"
        )
    }

    func testConvertToFixedBand_highShelfBand() {
        let band = ParametricBand(frequency: 8000, gain: -6.0, q: 0.7, filterType: .highShelf)
        let result = converter.convertToFixedBand([band], preampGain: 0)

        // High frequencies should be cut
        XCTAssertLessThan(
            result[9],
            -1.0,
            "High shelf cut should reduce 16 kHz"
        )

        // Low frequencies should be mostly unaffected
        let lowFreqGain = result[0] // 31.5 Hz
        XCTAssertLessThan(
            abs(lowFreqGain),
            1.0,
            "High shelf should not affect 31.5 Hz significantly"
        )
    }

    // MARK: - 31-Band Graphic EQ Conversion

    func testConvertToGraphicEQ_emptyBands_returnsAllZeros() {
        let result = converter.convertToGraphicEQ([], preampGain: 0)

        XCTAssertEqual(result.count, 31, "Should return 31 bands")
        for gain in result {
            XCTAssertEqual(gain, 0.0, accuracy: 0.001)
        }
    }

    func testConvertToGraphicEQ_singleBand_has31Values() {
        let band = ParametricBand(frequency: 1000, gain: 6.0, q: 1.0, filterType: .peak)
        let result = converter.convertToGraphicEQ([band], preampGain: 0)

        XCTAssertEqual(result.count, 31, "Should always return 31 values")
    }

    func testConvertToGraphicEQ_withPreamp() {
        let preamp: Float = -2.5
        let result = converter.convertToGraphicEQ([], preampGain: preamp)

        for gain in result {
            XCTAssertEqual(
                gain,
                preamp,
                accuracy: 0.001,
                "Empty bands should have gain equal to preamp"
            )
        }
    }

    // MARK: - Multiple Bands

    func testConvertToFixedBand_multipleBands_accumulates() {
        // Two peaks at the same frequency should accumulate
        let band1 = ParametricBand(frequency: 1000, gain: 3.0, q: 1.0, filterType: .peak)
        let band2 = ParametricBand(frequency: 1000, gain: 3.0, q: 1.0, filterType: .peak)

        let singleResult = converter.convertToFixedBand([band1], preampGain: 0)
        let doubleResult = converter.convertToFixedBand([band1, band2], preampGain: 0)

        // Double bands should produce roughly double the gain at center
        let singleGain = singleResult[5]
        let doubleGain = doubleResult[5]
        XCTAssertGreaterThan(
            doubleGain,
            singleGain,
            "Two identical bands should produce more gain than one"
        )
    }

    // MARK: - Edge Cases

    func testConvertToFixedBand_extremeGain() {
        let band = ParametricBand(frequency: 1000, gain: 30.0, q: 1.0, filterType: .peak)
        let result = converter.convertToFixedBand([band], preampGain: 0)

        // Should not produce NaN or Inf
        for gain in result {
            XCTAssertFalse(gain.isNaN, "Result should not be NaN")
            XCTAssertFalse(gain.isInfinite, "Result should not be infinite")
        }
    }

    func testConvertToFixedBand_extremeQ() {
        let band = ParametricBand(frequency: 1000, gain: 6.0, q: 0.01, filterType: .peak)
        let result = converter.convertToFixedBand([band], preampGain: 0)

        for gain in result {
            XCTAssertFalse(gain.isNaN, "Very low Q should not produce NaN")
            XCTAssertFalse(gain.isInfinite, "Very low Q should not produce Inf")
        }
    }

    func testConvertToFixedBand_veryHighQ_narrowPeak() {
        let band = ParametricBand(frequency: 1000, gain: 6.0, q: 10.0, filterType: .peak)
        let result = converter.convertToFixedBand([band], preampGain: 0)

        // Very high Q should create a very narrow peak — neighboring bands should have less gain
        let centerGain = result[5] // 1000 Hz
        let neighborGain = result[4] // 500 Hz

        XCTAssertGreaterThan(
            centerGain,
            neighborGain,
            "High Q peak at 1000 Hz should have less effect at 500 Hz"
        )
    }
}
