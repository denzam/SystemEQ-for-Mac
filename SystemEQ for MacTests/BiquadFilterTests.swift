//
//  BiquadFilterTests.swift
//  SystemEQ for MacTests
//
//  Unit tests for BiquadFilter and BiquadFilterChain
//

@testable import SystemEQ_for_Mac
import XCTest

final class BiquadFilterTests: XCTestCase {
    // MARK: - Peak Filter Coefficient Tests

    func testPeakFilterCoefficients_zeroGain_producesUnityFilter() {
        let filter = BiquadFilter()
        filter.configurePeak(frequency: 1000, gain: 0.0, q: 1.0, sampleRate: 48000)

        // Zero gain peak filter should be near-unity (passthrough)
        XCTAssertEqual(filter.b0, 1.0, accuracy: 0.001, "b0 should be ~1.0 for 0 dB gain")
        XCTAssertEqual(filter.b2, 1.0, accuracy: 0.1, "b2 should be near 1.0")
    }

    func testPeakFilterCoefficients_positiveGain() {
        let filter = BiquadFilter()
        filter.configurePeak(frequency: 1000, gain: 6.0, q: 1.0, sampleRate: 48000)

        // With positive gain, b0 should be > 1.0
        XCTAssertGreaterThan(filter.b0, 1.0, "b0 should be > 1 for positive gain")
    }

    func testPeakFilterCoefficients_negativeGain() {
        let filter = BiquadFilter()
        filter.configurePeak(frequency: 1000, gain: -6.0, q: 1.0, sampleRate: 48000)

        // With negative gain, b0 should be < 1.0
        XCTAssertLessThan(filter.b0, 1.0, "b0 should be < 1 for negative gain")
    }

    // MARK: - Shelf Filter Tests

    func testLowShelfFilterCoefficients_nonZero() {
        let filter = BiquadFilter()
        filter.configureLowShelf(frequency: 100, gain: 6.0, q: 0.7, sampleRate: 48000)

        // Coefficients should be non-zero and finite
        XCTAssertFalse(filter.b0.isNaN, "b0 should not be NaN")
        XCTAssertFalse(filter.b0.isInfinite, "b0 should not be infinite")
        XCTAssertNotEqual(filter.b0, 0.0, "b0 should not be zero")
    }

    func testHighShelfFilterCoefficients_nonZero() {
        let filter = BiquadFilter()
        filter.configureHighShelf(frequency: 8000, gain: -3.0, q: 0.7, sampleRate: 48000)

        XCTAssertFalse(filter.b0.isNaN, "b0 should not be NaN")
        XCTAssertFalse(filter.b0.isInfinite, "b0 should not be infinite")
        XCTAssertNotEqual(filter.b0, 0.0, "b0 should not be zero")
    }

    // MARK: - Signal Processing Tests

    func testProcessBuffer_zeroGain_passthrough() {
        let filter = BiquadFilter()
        filter.configurePeak(frequency: 1000, gain: 0.0, q: 1.0, sampleRate: 48000)

        // Create a simple test signal (DC offset of 1.0)
        let frameCount = 256
        var buffer = [Float](repeating: 1.0, count: frameCount)

        buffer.withUnsafeMutableBufferPointer { ptr in
            guard let baseAddress = ptr.baseAddress else { return }
            filter.processBuffer(baseAddress, frameCount: frameCount)
        }

        // After settling (first few samples may differ due to filter state),
        // output should be very close to input for 0 dB gain
        let lastSample = buffer[frameCount - 1]
        XCTAssertEqual(
            lastSample,
            1.0,
            accuracy: 0.01,
            "Zero gain filter should pass signal through unchanged"
        )
    }

    func testProcessBuffer_bypass_leavesSignalUnchanged() {
        let filter = BiquadFilter()
        filter.configurePeak(frequency: 1000, gain: 0.0, q: 1.0, sampleRate: 48000)
        filter.isBypass = true

        let frameCount = 64
        let original: [Float] = (0..<frameCount).map { Float($0) / Float(frameCount) }
        var buffer = original

        buffer.withUnsafeMutableBufferPointer { ptr in
            guard let baseAddress = ptr.baseAddress else { return }
            filter.processBuffer(baseAddress, frameCount: frameCount)
        }

        // Bypassed filter should not modify the buffer at all
        for i in 0..<frameCount {
            XCTAssertEqual(
                buffer[i],
                original[i],
                accuracy: Float.ulpOfOne,
                "Bypassed filter must not modify signal at index \(i)"
            )
        }
    }

    func testImpulseResponse_peakFilter_hasDecay() {
        let filter = BiquadFilter()
        filter.configurePeak(frequency: 1000, gain: 12.0, q: 2.0, sampleRate: 48000)

        // Process an impulse (1.0 followed by zeros)
        let frameCount = 128
        var buffer = [Float](repeating: 0.0, count: frameCount)
        buffer[0] = 1.0

        buffer.withUnsafeMutableBufferPointer { ptr in
            guard let baseAddress = ptr.baseAddress else { return }
            filter.processBuffer(baseAddress, frameCount: frameCount)
        }

        // The output should decay — last sample should be smaller than first non-zero
        let firstOutput = buffer[0]
        let lastOutput = abs(buffer[frameCount - 1])
        XCTAssertGreaterThan(abs(firstOutput), 0.0, "Filter should produce non-zero output")
        XCTAssertLessThan(
            lastOutput,
            abs(firstOutput),
            "Impulse response should decay over time"
        )
    }

    // MARK: - Stereo Processing Tests

    func testProcessStereoBuffers_matchesMono() {
        let filterMono = BiquadFilter()
        filterMono.configurePeak(frequency: 1000, gain: 6.0, q: 1.0, sampleRate: 48000)

        let filterStereo = BiquadFilter()
        filterStereo.configurePeak(frequency: 1000, gain: 6.0, q: 1.0, sampleRate: 48000)

        let frameCount = 64
        var monoBuffer = [Float](repeating: 0.5, count: frameCount)
        var stereoL = [Float](repeating: 0.5, count: frameCount)
        var stereoR = [Float](repeating: 0.5, count: frameCount)

        monoBuffer.withUnsafeMutableBufferPointer { ptr in
            guard let baseAddress = ptr.baseAddress else { return }
            filterMono.processBuffer(baseAddress, frameCount: frameCount)
        }

        stereoL.withUnsafeMutableBufferPointer { ptrL in
            stereoR.withUnsafeMutableBufferPointer { ptrR in
                guard let leftAddress = ptrL.baseAddress,
                      let rightAddress = ptrR.baseAddress else { return }
                filterStereo.processStereoBuffers(leftAddress, rightAddress, frameCount: frameCount)
            }
        }

        // Left channel of stereo should match mono processing
        for i in 0..<frameCount {
            XCTAssertEqual(
                stereoL[i],
                monoBuffer[i],
                accuracy: 0.0001,
                "Stereo L should match mono at index \(i)"
            )
        }
    }

    // MARK: - BiquadFilterChain Tests

    func testFilterChain_preampApplied() {
        let chain = BiquadFilterChain(filterCount: 1)
        chain.preamp = 6.0 // +6 dB ≈ 2x multiplier

        // Configure a zero-gain filter (passthrough)
        chain.configureBands(
            [1000],
            gains: [0.0],
            qs: [1.0],
            types: [.peak],
            sampleRate: 48000
        )

        let frameCount = 64
        var bufferL = [Float](repeating: 0.5, count: frameCount)
        var bufferR = [Float](repeating: 0.5, count: frameCount)

        bufferL.withUnsafeMutableBufferPointer { ptrL in
            bufferR.withUnsafeMutableBufferPointer { ptrR in
                guard let leftAddress = ptrL.baseAddress,
                      let rightAddress = ptrR.baseAddress else { return }
                chain.processStereoBuffers(leftAddress, rightAddress, frameCount: frameCount)
            }
        }

        // After preamp (+6 dB ≈ 1.995x), signal should be ~1.0
        let expected = 0.5 * pow(10.0, 6.0 / 20.0) // ≈ 0.997
        XCTAssertEqual(
            bufferL[frameCount - 1],
            Float(expected),
            accuracy: 0.05,
            "Preamp should amplify signal by ~6 dB"
        )
    }

    func testFilterChain_multipleFilters_allApplied() {
        let chain = BiquadFilterChain(filterCount: 3)
        chain.configureBands(
            [100, 1000, 10000],
            gains: [6.0, 6.0, 6.0],
            qs: [1.0, 1.0, 1.0],
            types: [.peak, .peak, .peak],
            sampleRate: 48000
        )

        // activeFilterCount should reflect non-bypassed filters
        XCTAssertEqual(
            chain.activeFilterCount,
            3,
            "All 3 filters with non-zero gain should be active"
        )
    }

    func testFilterChain_zeroGainFilters_areBypassed() {
        let chain = BiquadFilterChain(filterCount: 3)
        chain.configureBands(
            [100, 1000, 10000],
            gains: [0.0, 6.0, 0.0],
            qs: [1.0, 1.0, 1.0],
            types: [.peak, .peak, .peak],
            sampleRate: 48000
        )

        // Only 1 filter has non-zero gain
        XCTAssertEqual(
            chain.activeFilterCount,
            1,
            "Only filters with non-zero gain should be active"
        )
    }
}
