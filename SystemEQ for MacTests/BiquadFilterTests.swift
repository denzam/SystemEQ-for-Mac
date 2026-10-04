//
//  BiquadFilterTests.swift
//  SystemEQ for MacTests
//
//  Unit tests for BiquadFilter and BiquadFilterChain
//

@testable import SystemEQ_for_Mac
import XCTest

final class BiquadFilterTests: XCTestCase {
    func testRoomAndEQCascadeProducesExpectedAudioAcrossSampleRates() {
        let engine = CoreAudioEngine.shared
        defer {
            engine.setEnabled(false)
            engine.clearRoomNotchFilters()
            engine.clearEQ()
            engine.prepareProcessTap(sampleRate: 48000, outputDeviceID: 0, bufferFrames: 256)
        }
        for rate in [44100.0, 48000.0, 96000.0] {
            for (band, frequency) in [(2, 125.0), (5, 1000.0), (8, 8000.0)] {
                engine.prepareProcessTap(sampleRate: rate, outputDeviceID: 0, bufferFrames: 256)
                var gains = [Float](repeating: 0, count: 10)
                gains[band] = 3
                engine.applyFixedBandEQ(gains, preamp: 0, outputBoost: 0)
                engine.applyRoomNotchFilters([(frequency: Float(frequency), gain: -6, q: 8)])
                engine.setEnabled(true)
                let expectedEQGain = band == 8 ? 1.5 : 3.0
                XCTAssertEqual(
                    measuredGain(engine: engine, frequency: frequency, rate: rate),
                    expectedEQGain - 6,
                    accuracy: 0.12
                )
                engine.clearRoomNotchFilters()
                XCTAssertEqual(
                    measuredGain(engine: engine, frequency: frequency, rate: rate),
                    expectedEQGain,
                    accuracy: 0.12
                )
                engine.setEnabled(false)
                XCTAssertEqual(measuredGain(engine: engine, frequency: frequency, rate: rate), 0, accuracy: 0.001)
            }
        }
    }

    private func measuredGain(engine: CoreAudioEngine, frequency: Double, rate: Double) -> Double {
        var inputEnergy = 0.0
        var outputEnergy = 0.0
        for block in 0..<96 {
            let source = (0..<256).map { index in
                Float(sin(2 * Double.pi * frequency * Double(block * 256 + index) / rate) * 0.01)
            }
            var left = source
            var right = source
            left.withUnsafeMutableBufferPointer { l in
                right.withUnsafeMutableBufferPointer { r in
                    guard let left = l.baseAddress, let right = r.baseAddress else {
                        XCTFail("Missing audio buffer")
                        return
                    }
                    engine.processStereoInPlace(left: left, right: right, frameCount: 256)
                }
            }
            XCTAssertTrue(left.allSatisfy(\.isFinite))
            XCTAssertEqual(left, right)
            if block >= 32 {
                inputEnergy += source.reduce(0) { $0 + Double($1) * Double($1) }
                outputEnergy += left.reduce(0) { $0 + Double($1) * Double($1) }
            }
        }
        return 10 * log10(outputEnergy / inputEnergy)
    }

    func testResamplerLayoutsAgreeAcrossBoundaryAndWraparound() {
        for available in [0, 1, 2, 17, 65, 128] {
            for requested in [0, 1, 16, 64] {
                let planar = SPSCRingBuffer()
                let interleaved = SPSCRingBuffer()
                planar.allocate(capacityFrames: 256)
                interleaved.allocate(capacityFrames: 256)
                let poison = [Float](repeating: .nan, count: planar.capacity)
                for ring in [planar, interleaved] {
                    _ = ring.write(inL: poison, inR: poison, frameCount: poison.count)
                    var discardedL = [Float](repeating: 0, count: poison.count)
                    var discardedR = discardedL
                    ring.readNonInterleaved(outL: &discardedL, outR: &discardedR, framesRequested: poison.count)
                }
                let padding = [Float](repeating: .nan, count: planar.capacity - 6)
                for ring in [planar, interleaved] {
                    _ = ring.write(inL: padding, inR: padding, frameCount: padding.count)
                    var discardedL = [Float](repeating: 0, count: padding.count)
                    var discardedR = discardedL
                    ring.readNonInterleaved(outL: &discardedL, outR: &discardedR, framesRequested: padding.count)
                }
                let input = (0..<available).map { Float($0) * 0.001 }
                for ring in [planar, interleaved] {
                    _ = ring.write(inL: input, inR: input, frameCount: available)
                }
                var left = [Float](repeating: -999, count: max(1, requested))
                var right = left
                var stereo = [Float](repeating: -999, count: max(1, requested * 2))
                planar.readNonInterleavedResampled(
                    outL: &left,
                    outR: &right,
                    framesRequested: requested,
                    targetFillFrames: 0
                )
                interleaved.readInterleavedResampled(outPtr: &stereo, framesRequested: requested, targetFillFrames: 0)
                for index in 0..<requested {
                    XCTAssertEqual(left[index], stereo[index * 2], accuracy: 0.000001)
                    XCTAssertEqual(right[index], stereo[index * 2 + 1], accuracy: 0.000001)
                    XCTAssertTrue(left[index].isFinite)
                }
                if requested == 0 {
                    XCTAssertEqual(left[0], -999)
                    XCTAssertEqual(stereo[0], -999)
                } else if available == 0 {
                    XCTAssertEqual(Array(left.prefix(requested)), [Float](repeating: 0, count: requested))
                }
            }
        }
    }

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

    // MARK: - VDSP Filter Type Tests

    func testVDSPCoefficients_allFilterTypesFiniteAndValid() {
        let types: [FilterType] = [
            .peak,
            .lowShelf,
            .highShelf,
            .lowPass,
            .highPass,
            .notch,
            .bandPass,
            .allPass,
            .allPassPEQ
        ]
        for type in types {
            let c = BiquadResponseCalculator.coefficients(
                frequency: 1000,
                gain: type == .notch ? 0.0 : 6.0,
                q: 1.0,
                type: type,
                sampleRate: 48000
            )
            XCTAssertFalse(c.b0.isNaN, "\(type) b0 should not be NaN")
            XCTAssertFalse(c.b1.isNaN, "\(type) b1 should not be NaN")
            XCTAssertFalse(c.b2.isNaN, "\(type) b2 should not be NaN")
            XCTAssertFalse(c.a1.isNaN, "\(type) a1 should not be NaN")
            XCTAssertFalse(c.a2.isNaN, "\(type) a2 should not be NaN")
            XCTAssertFalse(c.b0.isInfinite, "\(type) b0 should not be infinite")
        }
    }

    func testVDSPFilter_lowPassAndHighPass_retainedWhenZeroGain() {
        let filter = BiquadFilterVDSP(sampleRate: 48000)
        let bands = [
            ParametricBand(frequency: 100, gain: 0.0, q: 0.707, filterType: .highPass),
            ParametricBand(frequency: 10000, gain: 0.0, q: 0.707, filterType: .lowPass),
            ParametricBand(frequency: 1000, gain: 0.0, q: 1.0, filterType: .peak),
        ]
        filter.configure(bands: bands, preamp: 0.0, outputBoost: 0.0, sampleRate: 48000)
        XCTAssertEqual(filter.activeFilterCount, 2, "HighPass and LowPass should be active even with 0 gain")
    }

    func testCoreAudioEngine_roomNotchFilters_preservesActiveEQ() {
        let engine = CoreAudioEngine.shared
        // Set a 10-band EQ
        engine.applyFixedBandEQ([3.0, 3.0, 0, 0, 0, 0, 0, 0, 0, 0], preamp: 0.0, outputBoost: 0.0)
        let originalVDSP = engine.vdspFilter
        XCTAssertNotNil(originalVDSP)

        // Apply room notch filters
        engine.applyRoomNotchFilters([(frequency: 250, gain: -6.0, q: 8.0)])
        XCTAssertNotNil(engine.roomFilter, "roomFilter should be configured")
        XCTAssertTrue(engine.vdspFilter === originalVDSP, "Original vdspFilter must remain intact")

        // Clear room notch filters
        engine.clearRoomNotchFilters()
        XCTAssertNil(engine.roomFilter, "roomFilter should be nil after clear")
        XCTAssertTrue(engine.vdspFilter === originalVDSP, "Original vdspFilter must still remain intact")
    }

    func testBiquadFilterVDSP_recoversFromTransientNaN() {
        let filter = BiquadFilterVDSP(sampleRate: 48000)
        let bands = [ParametricBand(frequency: 1000, gain: 6.0, q: 1.0, filterType: .peak)]
        filter.configure(bands: bands, preamp: 0.0, outputBoost: 0.0, sampleRate: 48000)

        let count = 64
        var bufferL = [Float](repeating: 0.5, count: count)
        var bufferR = [Float](repeating: 0.5, count: count)
        // Inject NaN in the first frame
        bufferL[0] = Float.nan
        bufferR[0] = Float.nan

        // Process block with NaN
        filter.processStereo(&bufferL, &bufferR, frameCount: count)

        // All output samples must be finite (sanitized, no NaN leak)
        for i in 0..<count {
            XCTAssertFalse(bufferL[i].isNaN, "Output sample L[\(i)] must not be NaN")
            XCTAssertFalse(bufferR[i].isNaN, "Output sample R[\(i)] must not be NaN")
        }

        // Process subsequent completely clean block
        var cleanL = [Float](repeating: 0.5, count: count)
        var cleanR = [Float](repeating: 0.5, count: count)
        filter.processStereo(&cleanL, &cleanR, frameCount: count)

        // Filter must not be stuck in silence (must produce non-zero output for non-zero input)
        var sumL: Float = 0
        for sample in cleanL {
            XCTAssertFalse(sample.isNaN, "Clean sample must not become NaN")
            sumL += abs(sample)
        }
        XCTAssertGreaterThan(sumL, 0.01, "Filter delay lines must recover and not produce permanent silence")
    }

    func testSPSCRingBuffer_resampler_boundarySafety() {
        let rb = SPSCRingBuffer()
        rb.allocate(capacityFrames: 256)

        // Write exactly 1 frame of data
        let inL: [Float] = [0.5]
        let inR: [Float] = [0.5]
        _ = rb.write(inL: inL, inR: inR, frameCount: 1)

        var outL = [Float](repeating: -999.0, count: 1)
        var outR = [Float](repeating: -999.0, count: 1)

        // Requesting 1 frame when available == 1:
        // requiredFrames is lastOffset + 2 == 2. avail (1) < requiredFrames (2).
        // Resampler must safely fall back to readNonInterleaved instead of reading past the boundary!
        rb.readNonInterleavedResampled(outL: &outL, outR: &outR, framesRequested: 1, targetFillFrames: 0)

        XCTAssertEqual(outL[0], 0.5, accuracy: 0.001)
        XCTAssertEqual(outR[0], 0.5, accuracy: 0.001)
        XCTAssertFalse(outL[0].isNaN)
        XCTAssertFalse(outR[0].isNaN)
    }

    func testCoreAudioEngine_roomNotchFilters_rebuildsOnSampleRateChange() {
        let engine = CoreAudioEngine.shared
        engine.applyRoomNotchFilters([(frequency: 250, gain: -6.0, q: 8.0)])
        guard let initialRoomFilter = engine.roomFilter else {
            XCTFail("roomFilter should be initialized")
            return
        }
        XCTAssertEqual(initialRoomFilter.sampleRate, 48000, accuracy: 1.0)

        // Simulate sample rate change to 96kHz
        engine.rebuildRoomFilter(sampleRate: 96000)
        guard let updatedRoomFilter = engine.roomFilter else {
            XCTFail("roomFilter should be rebuilt")
            return
        }
        XCTAssertEqual(updatedRoomFilter.sampleRate, 96000, accuracy: 1.0)

        // Clean up
        engine.clearRoomNotchFilters()
    }

    func testSPSCRingBuffer_resampler_nanProtection_whenFractionIsZero() {
        let rb = SPSCRingBuffer()
        rb.allocate(capacityFrames: 256)

        // Write frame 0 with valid audio, and frame 1 with NaN / Inf
        let inL: [Float] = [0.75, Float.nan, 0.0]
        let inR: [Float] = [0.75, Float.infinity, 0.0]
        _ = rb.write(inL: inL, inR: inR, frameCount: 3)

        // Test planar resampler at fraction == 0
        var outL = [Float](repeating: -999.0, count: 1)
        var outR = [Float](repeating: -999.0, count: 1)
        rb.readNonInterleavedResampled(outL: &outL, outR: &outR, framesRequested: 1, targetFillFrames: 0)

        XCTAssertEqual(outL[0], 0.75, accuracy: 0.001, "Valid sample must not be poisoned by NaN in next index")
        XCTAssertEqual(outR[0], 0.75, accuracy: 0.001, "Valid sample must not be poisoned by Inf in next index")
        XCTAssertFalse(outL[0].isNaN, "outL must not be NaN")
        XCTAssertFalse(outR[0].isNaN, "outR must not be NaN")

        // Test interleaved resampler
        let rbInterleaved = SPSCRingBuffer()
        rbInterleaved.allocate(capacityFrames: 256)
        _ = rbInterleaved.write(inL: inL, inR: inR, frameCount: 3)

        var outInterleaved = [Float](repeating: -999.0, count: 2)
        rbInterleaved.readInterleavedResampled(outPtr: &outInterleaved, framesRequested: 1, targetFillFrames: 0)

        XCTAssertEqual(outInterleaved[0], 0.75, accuracy: 0.001)
        XCTAssertEqual(outInterleaved[1], 0.75, accuracy: 0.001)
        XCTAssertFalse(outInterleaved[0].isNaN)
        XCTAssertFalse(outInterleaved[1].isNaN)
    }

    func testCoreAudioEngine_activeEQFilter_rebuildsOnSampleRateChange() {
        let engine = CoreAudioEngine.shared
        let testGains: [Float] = [1, 2, 3, 4, 5, -1, -2, -3, -4, -5]
        engine.applyFixedBandEQ(testGains, preamp: 1.0, outputBoost: 0.5)

        XCTAssertNotNil(engine.vdspFilter)

        // Rebuild for 96kHz
        engine.rebuildActiveEQFilter(sampleRate: 96000)

        guard let filter96 = engine.vdspFilter else {
            XCTFail("vdspFilter must be rebuilt")
            return
        }
        XCTAssertEqual(filter96.sampleRate, 96000, accuracy: 1.0)

        // Test 31-band rebuild
        let gains31 = [Float](repeating: 2.0, count: 31)
        engine.applyGraphicEQ31(gains31, preamp: -2.0, outputBoost: 1.0)

        engine.rebuildActiveEQFilter(sampleRate: 192_000)
        guard let filter192 = engine.vdspFilter else {
            XCTFail("vdspFilter 31-band must be rebuilt")
            return
        }
        XCTAssertEqual(filter192.sampleRate, 192_000, accuracy: 1.0)

        // Clean up
        engine.clearEQ()
        engine.rebuildActiveEQFilter(sampleRate: 48000)
    }
}
