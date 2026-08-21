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

        // At 0 dB the RBJ peaking numerator equals its denominator, so the filter is
        // a passthrough — but b2 is (1-alpha)/(1+alpha), not 1.0. The coefficients
        // cancel against a1/a2 rather than each being unity on its own.
        XCTAssertEqual(filter.b0, 1.0, accuracy: 0.001, "b0 should be ~1.0 for 0 dB gain")
        XCTAssertEqual(filter.b1, filter.a1, accuracy: 0.000_01, "b1 must cancel a1 at 0 dB")
        XCTAssertEqual(filter.b2, filter.a2, accuracy: 0.000_01, "b2 must cancel a2 at 0 dB")

        // The audible property the coefficients are supposed to guarantee.
        for sample in [Float(0.0), 0.5, -0.5, 0.25, 1.0, -1.0] {
            XCTAssertEqual(filter.process(sample), sample, accuracy: 0.000_1, "0 dB peak must pass through")
        }
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

    func testOutputBoostRaisesQuietSignalAndLimitsStereoPeaks() {
        let filter = BiquadFilterVDSP()
        filter.configure(bands: [], preamp: 0, outputBoost: 3, sampleRate: 48000)

        var quietL = [Float](repeating: 0.25, count: 64)
        var quietR = [Float](repeating: 0.25, count: 64)
        let frameCount = quietL.count
        var quietLimiterGain: Float = 0
        quietL.withUnsafeMutableBufferPointer { left in
            quietR.withUnsafeMutableBufferPointer { right in
                guard let leftAddress = left.baseAddress,
                      let rightAddress = right.baseAddress else { return }
                quietLimiterGain = filter.processStereo(leftAddress, rightAddress, frameCount: frameCount)
            }
        }

        let boostedQuietSignal = Float(0.25 * pow(10.0, 3.0 / 20.0))
        XCTAssertEqual(quietL[0], boostedQuietSignal, accuracy: 0.0001)
        XCTAssertEqual(quietR[0], boostedQuietSignal, accuracy: 0.0001)
        XCTAssertEqual(quietLimiterGain, 1)

        filter.configure(bands: [], preamp: 0, outputBoost: 3, sampleRate: 48000)
        var loudL = [Float](repeating: 0.9, count: 64)
        var loudR = [Float](repeating: 0.4, count: 64)
        var loudLimiterGain: Float = 1
        loudL.withUnsafeMutableBufferPointer { left in
            loudR.withUnsafeMutableBufferPointer { right in
                guard let leftAddress = left.baseAddress,
                      let rightAddress = right.baseAddress else { return }
                loudLimiterGain = filter.processStereo(leftAddress, rightAddress, frameCount: frameCount)
            }
        }

        XCTAssertLessThanOrEqual(abs(loudL[0]), 0.891_251)
        XCTAssertLessThanOrEqual(abs(loudR[0]), 0.891_251)
        XCTAssertEqual(loudL[0] / loudR[0], 0.9 / 0.4, accuracy: 0.0001)
        XCTAssertLessThan(loudLimiterGain, 1)
        XCTAssertGreaterThan(-20 * log10(loudLimiterGain), 3)
    }

    func testOutputBoostSupportsTwelveDBForQuietSignals() {
        let filter = BiquadFilterVDSP()
        filter.configure(bands: [], preamp: 0, outputBoost: 12, sampleRate: 48000)
        var left = [Float](repeating: 0.1, count: 64)
        var right = [Float](repeating: 0.1, count: 64)
        let frameCount = left.count

        left.withUnsafeMutableBufferPointer { leftBuffer in
            right.withUnsafeMutableBufferPointer { rightBuffer in
                guard let leftAddress = leftBuffer.baseAddress,
                      let rightAddress = rightBuffer.baseAddress else { return }
                filter.processStereo(leftAddress, rightAddress, frameCount: frameCount)
            }
        }

        let expected = Float(0.1 * pow(10.0, 12.0 / 20.0))
        XCTAssertEqual(left[0], expected, accuracy: 0.0001)
        XCTAssertEqual(right[0], expected, accuracy: 0.0001)
    }

    func testSafetyAtZeroBoostPreservesUnityAndLimitsPositivePreamp() {
        let passthrough = BiquadFilterVDSP()
        passthrough.configure(bands: [], preamp: 0, outputBoost: 0, sampleRate: 48000)
        var unityL = [Float](repeating: 1, count: 64)
        var unityR = [Float](repeating: 0.5, count: 64)
        let unityFrameCount = unityL.count

        unityL.withUnsafeMutableBufferPointer { leftBuffer in
            unityR.withUnsafeMutableBufferPointer { rightBuffer in
                guard let leftAddress = leftBuffer.baseAddress,
                      let rightAddress = rightBuffer.baseAddress else { return }
                passthrough.processStereo(leftAddress, rightAddress, frameCount: unityFrameCount)
            }
        }

        XCTAssertEqual(unityL[0], 1)
        XCTAssertEqual(unityR[0], 0.5)

        let protected = BiquadFilterVDSP()
        protected.configure(bands: [], preamp: 6, outputBoost: 0, sampleRate: 48000)
        var loudL = [Float](repeating: 0.75, count: 64)
        var loudR = [Float](repeating: 0.375, count: 64)
        let loudFrameCount = loudL.count

        loudL.withUnsafeMutableBufferPointer { leftBuffer in
            loudR.withUnsafeMutableBufferPointer { rightBuffer in
                guard let leftAddress = leftBuffer.baseAddress,
                      let rightAddress = rightBuffer.baseAddress else { return }
                protected.processStereo(leftAddress, rightAddress, frameCount: loudFrameCount)
            }
        }

        XCTAssertLessThanOrEqual(abs(loudL[0]), 1)
        XCTAssertLessThanOrEqual(abs(loudR[0]), 1)
        XCTAssertEqual(loudL[0] / loudR[0], 2, accuracy: 0.0001)
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
