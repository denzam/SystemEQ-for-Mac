//
//  BiquadFilterTests.swift
//  SystemEQ for MacTests
//
//  Unit tests for BiquadFilter and BiquadFilterChain
//

import Accelerate
import AudioToolbox
@testable import SystemEQ_for_Mac
import XCTest

final class BiquadFilterTests: XCTestCase {
    func testRoomAndEQCascadeProducesExpectedAudioAcrossSampleRates() {
        let engine = CoreAudioEngine()
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

    func testVDSPInvalidParametersBypassEveryFilterType() throws {
        let invalid: [(Float, Float, Float, Float)] = [
            (1000, 6, 2, 0), (1000, 6, 2, -48000),
            (1000, 6, 2, .nan), (1000, 6, 2, .infinity),
            (0, 6, 2, 48000), (-1000, 6, 2, 48000),
            (.nan, 6, 2, 48000), (.infinity, 6, 2, 48000),
            (24000, 6, 2, 48000), (Float(24000).nextUp, 6, 2, 48000),
            (1000, .nan, 2, 48000), (1000, .infinity, 2, 48000),
            (1000, 6, 0, 48000), (1000, 6, -1, 48000),
            (1000, 6, .nan, 48000), (1000, 6, .infinity, 48000)
        ]
        for type in FilterType.allCases {
            for (frequency, gain, q, rate) in invalid {
                let band = try decodedBand(frequency: frequency, gain: gain, q: q, type: type)
                let coefficients = BiquadResponseCalculator.coefficients(
                    frequency: frequency, gain: gain, q: q, type: type, sampleRate: rate
                )
                XCTAssertTrue(coefficients.isIdentity, "\(type), \(frequency), \(gain), \(q), \(rate)")
                XCTAssertEqual(BiquadResponseCalculator.maximumCombinedGainDB(bands: [band], sampleRate: rate), 0)
                let filter = BiquadFilterVDSP()
                filter.configure(bands: [band], preamp: -3, outputBoost: 3, sampleRate: rate)
                XCTAssertEqual(filter.activeFilterCount, 0)
                var left: [Float] = [2, 0.1, 0.1, .nan, .infinity]
                var right = left
                filter.processStereo(&left, &right, frameCount: left.count)
                XCTAssertTrue(left.allSatisfy(\.isFinite))
                XCTAssertEqual(left, right)
                XCTAssertGreaterThan(left[1], 0)
            }
        }
    }

    func testVDSPRejectsOverflowAndRoundedUnstableCoefficients() {
        for (frequency, gain, q) in [
            (Float(1000), Float.greatestFiniteMagnitude, Float(2)),
            (1000, 6, Float.leastNonzeroMagnitude),
            (Float.leastNonzeroMagnitude, 6, 2),
            (Float(24000).nextDown, 6, 2)
        ] {
            let coefficients = BiquadResponseCalculator.coefficients(
                frequency: frequency, gain: gain, q: q, type: .peak, sampleRate: 48000
            )
            XCTAssertTrue(coefficients.isIdentity || coefficients.isStable)
        }
        XCTAssertTrue(BiquadResponseCalculator.coefficients(
            frequency: 1000, gain: .greatestFiniteMagnitude, q: 2, type: .peak, sampleRate: 48000
        ).isIdentity)
        XCTAssertTrue(BiquadResponseCalculator.coefficients(
            frequency: .leastNonzeroMagnitude, gain: 6, q: 2, type: .peak, sampleRate: 48000
        ).isIdentity)
    }

    func testVDSPFixedBandsRemainQuietAcrossRatesAndMatchHeadroom() throws {
        for mode in EQBandMode.allCases {
            for rate: Float in [24000, 32000, 44100, 48000, 96000] {
                for gain: Float in [-6, 6] {
                    var gains = [Float](repeating: 0, count: mode.bandCount)
                    gains[gains.count - 1] = gain
                    let bands = FixedBandEQDefinition.bands(mode: mode, gains: gains)
                    let bypassed = try XCTUnwrap(bands.last?.frequency) >= rate / 2
                    let filter = BiquadFilterVDSP()
                    filter.configure(bands: bands, preamp: 0, sampleRate: rate)
                    XCTAssertEqual(filter.activeFilterCount, bypassed ? 0 : 1)
                    let headroom = BiquadResponseCalculator.maximumCombinedGainDB(bands: bands, sampleRate: rate)
                    let measured = measuredVDSPGain(filter: filter, frequency: 1000, rate: Double(rate))
                    XCTAssertTrue(headroom.isFinite)
                    XCTAssertLessThanOrEqual(measured, Double(headroom) + 1)
                    if bypassed {
                        XCTAssertEqual(headroom, 0)
                        XCTAssertEqual(measured, 0, accuracy: 0.001)
                    }
                }
            }
        }
    }

    func testVDSPNyquistBoundaryIsSafeForEveryFilterType() {
        for type in FilterType.allCases {
            for frequency: Float in [15968, Float(16000).nextDown, 16000, Float(16000).nextUp] {
                let band = ParametricBand(frequency: frequency, gain: 6, q: 2, filterType: type)
                let filter = BiquadFilterVDSP()
                filter.configure(bands: [band], preamp: 0, sampleRate: 32000)
                let coefficients = BiquadResponseCalculator.coefficients(
                    frequency: frequency, gain: 6, q: 2, type: type, sampleRate: 32000
                )
                XCTAssertTrue(coefficients.isStable)
                if frequency >= 16000 {
                    XCTAssertTrue(coefficients.isIdentity)
                    XCTAssertEqual(filter.activeFilterCount, 0)
                }
                let gain = measuredVDSPGain(filter: filter, frequency: 1000, rate: 32000)
                XCTAssertTrue(gain.isFinite)
                XCTAssertLessThan(gain, 12)
            }
        }
    }

    func testCoreAudioRateTransitionsRestoreEQRoomFiltersAndGainStaging() throws {
        for mode in EQBandMode.allCases {
            let engine = CoreAudioEngine()
            defer {
                engine.setEnabled(false)
                engine.clearRoomNotchFilters()
                engine.clearEQ()
            }
            var gains = [Float](repeating: 0, count: mode.bandCount)
            gains[gains.count - 1] = 6
            if mode == .tenBand {
                engine.applyFixedBandEQ(gains, preamp: -4.5, outputBoost: 1)
            } else {
                engine.applyGraphicEQ31(gains, preamp: -4.5, outputBoost: 1)
            }
            engine.applyRoomNotchFilters([(frequency: 16000, gain: -3, q: 4)])
            engine.setEnabled(true)
            let frequency: Double = mode == .tenBand ? 16000 : 20000
            let baseline = measuredGain(engine: engine, frequency: frequency, rate: 48000)
            for lowRate in [24000.0, 32000.0] {
                engine.prepareProcessTap(sampleRate: lowRate, outputDeviceID: 0, bufferFrames: 256)
                XCTAssertEqual(try XCTUnwrap(engine.vdspFilter).activeFilterCount, 0)
                XCTAssertEqual(try XCTUnwrap(engine.roomFilter).activeFilterCount, 0)
                XCTAssertEqual(measuredGain(engine: engine, frequency: 1000, rate: lowRate), -3.5, accuracy: 0.03)
                engine.prepareProcessTap(sampleRate: 48000, outputDeviceID: 0, bufferFrames: 256)
                XCTAssertEqual(try XCTUnwrap(engine.vdspFilter).activeFilterCount, 1)
                XCTAssertEqual(try XCTUnwrap(engine.roomFilter).activeFilterCount, 1)
                XCTAssertEqual(
                    measuredGain(engine: engine, frequency: frequency, rate: 48000),
                    baseline,
                    accuracy: 0.03
                )
            }
        }
    }

    func testVDSPBypassPreservesZeroOneFrameWindowsAndSkipsZeroGainInvalidBands() throws {
        let filter = BiquadFilterVDSP()
        let bands = try [decodedBand(frequency: .nan, gain: 0, q: .nan, type: .peak)]
        filter.configure(bands: bands, preamp: -3, sampleRate: 48000)
        XCTAssertEqual(filter.activeFilterCount, 0)
        XCTAssertEqual(BiquadResponseCalculator.maximumCombinedGainDB(bands: bands, sampleRate: 48000), 0)
        for count in [0, 1, 256] {
            var left = [Float](repeating: 0.001, count: count + 1)
            var right = left
            filter.processStereo(&left, &right, frameCount: count)
            XCTAssertEqual(left[count], 0.001)
            XCTAssertEqual(right[count], 0.001)
            for index in 0..<count {
                XCTAssertEqual(left[index], 0.001 * pow(10, -3 / 20), accuracy: 0.0000001)
                XCTAssertEqual(left[index], right[index])
            }
        }
    }

    private func decodedBand(frequency: Float, gain: Float, q: Float, type: FilterType) throws -> ParametricBand {
        struct UnvalidatedBand: Encodable {
            let frequency: Float
            let gain: Float
            let q: Float
            let filterType: FilterType
        }
        let encoder = JSONEncoder()
        encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN"
        )
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN"
        )
        let encoded = try encoder.encode(UnvalidatedBand(frequency: frequency, gain: gain, q: q, filterType: type))
        return try decoder.decode(ParametricBand.self, from: encoded)
    }

    private func measuredVDSPGain(filter: BiquadFilterVDSP, frequency: Double, rate: Double) -> Double {
        var inputEnergy = 0.0
        var outputEnergy = 0.0
        for block in 0..<160 {
            let source = (0..<256).map { index in
                Float(sin(2 * Double.pi * frequency * Double(block * 256 + index) / rate) * 0.001)
            }
            var left = source
            var right = source
            filter.processStereo(&left, &right, frameCount: left.count)
            XCTAssertTrue(left.allSatisfy(\.isFinite))
            XCTAssertEqual(left, right)
            if block >= 150 {
                inputEnergy += source.reduce(0) { $0 + Double($1) * Double($1) }
                outputEnergy += left.reduce(0) { $0 + Double($1) * Double($1) }
            }
        }
        return 10 * log10(outputEnergy / inputEnergy)
    }

    func testVDSPFilter_lowPassAndHighPass_retainedWhenZeroGain() {
        let filter = BiquadFilterVDSP(sampleRate: 48000)
        let bands = [
            ParametricBand(frequency: 100, gain: 0.0, q: 0.707, filterType: .highPass),
            ParametricBand(frequency: 10000, gain: 0.0, q: 0.707, filterType: .lowPass),
            ParametricBand(frequency: 1000, gain: 0.0, q: 1.0, filterType: .peak)
        ]
        filter.configure(bands: bands, preamp: 0.0, outputBoost: 0.0, sampleRate: 48000)
        XCTAssertEqual(filter.activeFilterCount, 2, "HighPass and LowPass should be active even with 0 gain")
    }

    func testCoreAudioEngine_roomNotchFilters_preservesActiveEQ() {
        let engine = CoreAudioEngine()
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

        let inL: [Float] = [0.5]
        let inR: [Float] = [0.5]
        _ = rb.write(inL: inL, inR: inR, frameCount: 1)

        var outL = [Float](repeating: -999.0, count: 1)
        var outR = [Float](repeating: -999.0, count: 1)

        rb.readNonInterleavedResampled(outL: &outL, outR: &outR, framesRequested: 1, targetFillFrames: 0)

        XCTAssertEqual(outL[0], 0.5, accuracy: 0.001)
        XCTAssertEqual(outR[0], 0.5, accuracy: 0.001)
        XCTAssertFalse(outL[0].isNaN)
        XCTAssertFalse(outR[0].isNaN)
        XCTAssertEqual(rb.readIndex, 1)

        rb.reset()
        _ = rb.write(inL: inL, inR: inR, frameCount: 1)
        rb.setInternalResamplePhase(0.5)

        outL[0] = -999.0
        outR[0] = -999.0
        rb.readNonInterleavedResampled(outL: &outL, outR: &outR, framesRequested: 1, targetFillFrames: 0)

        XCTAssertEqual(outL[0], 0.0, accuracy: 0.001)
        XCTAssertEqual(outR[0], 0.0, accuracy: 0.001)
        XCTAssertEqual(rb.readIndex, 0)
        XCTAssertEqual(rb.prototypePhase, 0.5, accuracy: 1e-7)
    }

    func testCoreAudioEngine_roomNotchFilters_rebuildsOnSampleRateChange() {
        let engine = CoreAudioEngine()
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

    func testMaximumCombinedGainDB_extremeTenBandHighShelfPeakMatchesDenseSweep() throws {
        let gains = [Float](repeating: 20, count: EQBandMode.tenBand.bandCount)
        let bands = FixedBandEQDefinition.bands(mode: .tenBand, gains: gains)
        let rate: Double = 48000
        let coefficients = BiquadResponseCalculator.preparedCoefficients(bands: bands, sampleRate: Float(rate))
        var densePeak = 0.0
        for index in 0...16384 {
            let frequency = Double(index) / 16384.0 * (rate / 2.0)
            let gain = try coefficients.reduce(0.0) {
                try $0 + EQConverter.response($1, frequency: frequency, rate: rate)
            }
            densePeak = max(densePeak, gain)
        }
        let estimated = Double(BiquadResponseCalculator.maximumCombinedGainDB(bands: bands, sampleRate: Float(rate)))
        XCTAssertGreaterThan(densePeak, 40.5)
        XCTAssertEqual(estimated, densePeak, accuracy: 0.05)
    }

    func testSPSCRingBuffer_activeResampler_planarAndInterleavedWraparoundAndNaNRecovery() {
        for interleaved in [false, true] {
            for excessFill in [true, false] {
                let rb = SPSCRingBuffer()
                rb.allocate(capacityFrames: 1024)
                let sampleRate = 48000.0
                let toneFreq = 1000.0
                let blockFrames = 128
                let targetFill = 256
                let initialFill = excessFill ? 640 : 200
                var writePhase = 0
                var collectedL: [Float] = []
                var collectedR: [Float] = []

                func feed(_ count: Int, injectNaNAt indexToPoison: Int? = nil) {
                    var inL = (0..<count).map { idx in
                        Float(0.25 * sin(2 * Double.pi * toneFreq * Double(writePhase + idx) / sampleRate))
                    }
                    var inR = inL
                    if let indexToPoison, indexToPoison < count {
                        inL[indexToPoison] = .nan
                        inR[indexToPoison] = .infinity
                    }
                    writePhase += count
                    _ = rb.write(inL: inL, inR: inR, frameCount: count)
                }

                feed(initialFill)

                for block in 0..<40 {
                    feed(blockFrames, injectNaNAt: block == 28 ? 16 : nil)
                    if interleaved {
                        var out = [Float](repeating: 0, count: blockFrames * 2)
                        rb.readInterleavedResampled(
                            outPtr: &out,
                            framesRequested: blockFrames,
                            targetFillFrames: targetFill
                        )
                        for idx in 0..<blockFrames {
                            collectedL.append(out[idx * 2])
                            collectedR.append(out[idx * 2 + 1])
                        }
                    } else {
                        var outL = [Float](repeating: 0, count: blockFrames)
                        var outR = [Float](repeating: 0, count: blockFrames)
                        rb.readNonInterleavedResampled(
                            outL: &outL,
                            outR: &outR,
                            framesRequested: blockFrames,
                            targetFillFrames: targetFill
                        )
                        collectedL.append(contentsOf: outL)
                        collectedR.append(contentsOf: outR)
                    }
                }

                XCTAssertEqual(collectedL.count, 40 * blockFrames)
                XCTAssertTrue(collectedL.allSatisfy(\.isFinite))
                XCTAssertTrue(collectedR.allSatisfy(\.isFinite))
                XCTAssertNotEqual(rb.prototypeCorrection, 0, "Resampler drift correction must stay active")
                if excessFill {
                    XCTAssertGreaterThan(rb.prototypeCorrection, 0)
                } else {
                    XCTAssertLessThan(rb.prototypeCorrection, 0)
                }

                // Check steady-state clean region before NaN injection (frames 512..3072) across wraparounds.
                let steady = collectedL[512..<3072]
                let rms = sqrt(steady.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(steady.count))
                XCTAssertEqual(rms, 0.25 / sqrt(2.0), accuracy: 0.01)
                let expectedMaxStep = Float(0.25 * 2 * Double.pi * toneFreq / sampleRate)
                for index in (steady.startIndex + 1)..<steady.endIndex {
                    XCTAssertLessThan(abs(collectedL[index] - collectedL[index - 1]), expectedMaxStep * 1.35)
                }

                // Check clean recovery after block 28 NaN injection.
                let tail = collectedL[(35 * blockFrames)..<(40 * blockFrames)]
                let tailRMS = sqrt(tail.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(tail.count))
                XCTAssertEqual(tailRMS, 0.25 / sqrt(2.0), accuracy: 0.01)
            }
        }
    }

    func testCoreAudioEngine_activeEQFilter_rebuildsOnSampleRateChange() {
        let engine = CoreAudioEngine()
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

    private final class ProductionTestRenderer {
        enum Layout: CaseIterable { case planar, interleaved, mono }
        let layout: Layout
        let ring: SPSCRingBuffer
        let left: UnsafeMutablePointer<Float>
        let right: UnsafeMutablePointer<Float>
        let output: UnsafeMutablePointer<Float>
        let list: UnsafeMutableAudioBufferListPointer
        let capacity: Int

        init(layout: Layout, capacity: Int = 2048) {
            self.layout = layout
            self.capacity = capacity
            self.ring = SPSCRingBuffer()
            ring.allocate(capacityFrames: capacity)
            left = .allocate(capacity: capacity)
            right = .allocate(capacity: capacity)
            output = .allocate(capacity: capacity * 2)
            left.initialize(repeating: 0, count: capacity)
            right.initialize(repeating: 0, count: capacity)
            output.initialize(repeating: 0, count: capacity * 2)
            list = AudioBufferList.allocate(maximumBuffers: layout == .planar ? 2 : 1)
        }

        deinit {
            ring.deallocate()
            left.deallocate()
            right.deallocate()
            output.deallocate()
            free(list.unsafeMutablePointer)
        }

        func feed(l: [Float], r: [Float]) -> Int {
            XCTAssertEqual(l.count, r.count)
            return ring.write(inL: l, inR: r, frameCount: l.count)
        }

        func render(frames: Int, targetFill: Int = 512, ceiling: Float = 1.0) -> OSStatus {
            let stride = MemoryLayout<Float>.stride
            if layout == .planar {
                list[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(frames * stride), mData: left)
                list[1] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(frames * stride), mData: right)
            } else {
                let channels: UInt32 = layout == .interleaved ? 2 : 1
                list[0] = AudioBuffer(
                    mNumberChannels: channels,
                    mDataByteSize: UInt32(frames * Int(channels) * stride),
                    mData: output
                )
            }
            return CoreAudioOutput.render(
                ring: ring, buffers: list, frames: frames, capacity: capacity,
                targetFill: targetFill, scratchLeft: left, scratchRight: right, ceiling: ceiling
            )
        }

        func values(_ i: Int) -> (Float, Float) {
            switch layout {
            case .planar:
                (left[i], right[i])
            case .interleaved:
                (output[i * 2], output[i * 2 + 1])
            case .mono:
                (output[i], output[i])
            }
        }
    }

    private final class ScalarReferenceOracle {
        let ratio: Double
        var resamplePhase: Double
        var inputHistoryL: [Float] = []
        var inputHistoryR: [Float] = []
        var consumedTotal: Int = 0

        init(ratio: Double = 1.0, initialPhase: Double = 0.0) {
            self.ratio = ratio
            self.resamplePhase = initialPhase
        }

        func feed(left: [Float], right: [Float]) {
            inputHistoryL.append(contentsOf: left)
            inputHistoryR.append(contentsOf: right)
        }

        func render(framesRequested: Int)
            -> (outL: [Float], outR: [Float], renderedCount: Int, consumed: Int, newPhase: Double) {
            var renderedL: [Float] = []
            var renderedR: [Float] = []
            let avail = inputHistoryL.count - consumedTotal
            var pos = resamplePhase

            for _ in 0..<framesRequested {
                let sourceOffset = Int(pos)
                let fraction = Float(pos - Double(sourceOffset))
                let needed = fraction <= 1e-7 ? (sourceOffset + 1) : (sourceOffset + 2)
                if needed > avail { break }
                let idx0 = consumedTotal + sourceOffset
                let s0L = inputHistoryL[idx0]
                let s0R = inputHistoryR[idx0]
                let s1L = fraction <= 1e-7 ? s0L : inputHistoryL[idx0 + 1]
                let s1R = fraction <= 1e-7 ? s0R : inputHistoryR[idx0 + 1]
                renderedL.append(s0L + (s1L - s0L) * fraction)
                renderedR.append(s0R + (s1R - s0R) * fraction)
                pos += ratio
            }

            let renderedCount = renderedL.count
            let consumed = min(avail, Int(pos))
            consumedTotal += consumed
            resamplePhase = pos - Double(consumed)

            let under = framesRequested - renderedCount
            if under > 0 {
                renderedL.append(contentsOf: [Float](repeating: 0.0, count: under))
                renderedR.append(contentsOf: [Float](repeating: 0.0, count: under))
            }
            return (renderedL, renderedR, renderedCount, consumed, resamplePhase)
        }
    }

    func testProductionCaller_CoreAudioOutput_render_layouts() {
        for layout in ProductionTestRenderer.Layout.allCases {
            let renderer = ProductionTestRenderer(layout: layout, capacity: 1024)
            let feedCount = 256
            let inL = (0..<feedCount).map { Float(sin(Double($0) * 0.05)) }
            let inR = (0..<feedCount).map { Float(cos(Double($0) * 0.05)) }
            let written = renderer.feed(l: inL, r: inR)
            XCTAssertEqual(written, feedCount)

            let renderFrames = 128
            let status = renderer.render(frames: renderFrames, targetFill: 512, ceiling: 1.0)
            XCTAssertEqual(status, noErr)

            for i in 0..<renderFrames {
                let (valL, valR) = renderer.values(i)
                XCTAssertFalse(valL.isNaN)
                XCTAssertFalse(valR.isNaN)
                XCTAssertLessThanOrEqual(abs(valL), 1.0001)
                XCTAssertLessThanOrEqual(abs(valR), 1.0001)
            }
        }

        let ring = SPSCRingBuffer()
        ring.allocate(capacityFrames: 512)
        defer { ring.deallocate() }

        var dummyBuffer = [Float](repeating: 0, count: 256)
        dummyBuffer.withUnsafeMutableBufferPointer { ptr in
            let listPtr = AudioBufferList.allocate(maximumBuffers: 1)
            defer { free(listPtr.unsafeMutablePointer) }
            listPtr[0] = AudioBuffer(mNumberChannels: 4, mDataByteSize: 1024, mData: ptr.baseAddress)
            let status = CoreAudioOutput.render(
                ring: ring, buffers: listPtr, frames: 64, capacity: 512,
                targetFill: 256, scratchLeft: nil, scratchRight: nil
            )
            XCTAssertEqual(status, kAudioUnitErr_FormatNotSupported)
        }

        dummyBuffer.withUnsafeMutableBufferPointer { ptr in
            let listPtr = AudioBufferList.allocate(maximumBuffers: 3)
            defer { free(listPtr.unsafeMutablePointer) }
            listPtr[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: 256, mData: ptr.baseAddress)
            listPtr[1] = AudioBuffer(mNumberChannels: 1, mDataByteSize: 256, mData: ptr.baseAddress)
            listPtr[2] = AudioBuffer(mNumberChannels: 1, mDataByteSize: 256, mData: ptr.baseAddress)
            let status = CoreAudioOutput.render(
                ring: ring, buffers: listPtr, frames: 64, capacity: 512,
                targetFill: 256, scratchLeft: nil, scratchRight: nil
            )
            XCTAssertEqual(status, kAudioUnitErr_FormatNotSupported)
        }

        dummyBuffer.withUnsafeMutableBufferPointer { ptr in
            let listPtr = AudioBufferList.allocate(maximumBuffers: 1)
            defer { free(listPtr.unsafeMutablePointer) }
            listPtr[0] = AudioBuffer(mNumberChannels: 2, mDataByteSize: 2048, mData: ptr.baseAddress)
            let status = CoreAudioOutput.render(
                ring: ring, buffers: listPtr, frames: 1024, capacity: 512,
                targetFill: 256, scratchLeft: nil, scratchRight: nil
            )
            XCTAssertEqual(status, kAudioUnitErr_TooManyFramesToProcess)
        }
    }

    func testProductionCaller_oracleAssertions_cursorAndPhase() {
        let ratios = [0.999, 1.0, 1.001]
        let initialPhases = [0.0, 0.25, 0.5, 0.75, 0.999]
        let framesRequested = 8
        let layouts = ProductionTestRenderer.Layout.allCases

        var cellCount = 0
        for ratio in ratios {
            let correction = ratio - 1.0
            for initialPhase in initialPhases {
                let lastPos = initialPhase + Double(framesRequested - 1) * ratio
                let reqFrames = Int(lastPos) + 2
                let availList = [0, 1, 2, reqFrames, max(0, reqFrames - 1)]

                for avail in availList {
                    for layout in layouts {
                        let renderer = ProductionTestRenderer(layout: layout, capacity: 2048)
                        renderer.ring.setInternalResamplePhase(initialPhase)
                        renderer.ring.setInternalResampleCorrection(correction)

                        let feedL = avail > 0 ? (0..<avail).map { Float(sin(Double($0) * 0.1) * 0.4) } : []
                        let feedR = avail > 0 ? (0..<avail).map { Float(cos(Double($0) * 0.1) * 0.4) } : []
                        if avail > 0 {
                            _ = renderer.feed(l: feedL, r: feedR)
                        }

                        let initialRead = renderer.ring.readIndex
                        let status = renderer.render(frames: framesRequested, targetFill: 512, ceiling: 1.0)
                        XCTAssertEqual(status, noErr)

                        let actualConsumed = renderer.ring.readIndex - initialRead
                        let effectiveRatio = 1.0 + renderer.ring.prototypeCorrection
                        let oracle = ScalarReferenceOracle(ratio: effectiveRatio, initialPhase: initialPhase)
                        if avail > 0 {
                            oracle.feed(left: feedL, right: feedR)
                        }
                        let oracleResult = oracle.render(framesRequested: framesRequested)

                        XCTAssertEqual(actualConsumed, oracleResult.consumed)
                        XCTAssertEqual(
                            renderer.ring.prototypePhase,
                            oracleResult.newPhase,
                            accuracy: 1e-7
                        )

                        var maxDiff = 0.0
                        var allFinite = true
                        for i in 0..<framesRequested {
                            let (valL, valR) = renderer.values(i)
                            if !valL.isFinite || !valR.isFinite {
                                allFinite = false
                            }
                            let expL = oracleResult.outL[i]
                            let expR = oracleResult.outR[i]
                            if layout != .mono {
                                let diffL = abs(Double(valL) - Double(expL))
                                let diffR = abs(Double(valR) - Double(expR))
                                maxDiff = max(maxDiff, diffL, diffR)
                            } else {
                                let expMono = (Double(expL) + Double(expR)) * 0.5
                                let diffMono = abs(Double(valL) - expMono)
                                maxDiff = max(maxDiff, diffMono)
                            }
                        }

                        XCTAssertTrue(allFinite)
                        XCTAssertLessThanOrEqual(maxDiff, 1e-4)

                        cellCount += 1
                    }
                }
            }
        }
        XCTAssertEqual(cellCount, 225)

        let corruptedRenderer = ProductionTestRenderer(layout: .planar, capacity: 512)
        corruptedRenderer.ring.setInternalResamplePhase(0.25)
        let feedSample: [Float] = [0.1, 0.2, 0.3, 0.4]
        _ = corruptedRenderer.feed(l: feedSample, r: feedSample)
        let initRead = corruptedRenderer.ring.readIndex
        _ = corruptedRenderer.render(frames: 4, targetFill: 512, ceiling: 1.0)
        let consumedCorr = corruptedRenderer.ring.readIndex - initRead
        let oracleGood = ScalarReferenceOracle(
            ratio: 1.0 + corruptedRenderer.ring.prototypeCorrection,
            initialPhase: 0.25
        )
        oracleGood.feed(left: feedSample, right: feedSample)
        let expectedGood = oracleGood.render(framesRequested: 4)

        XCTAssertEqual(consumedCorr, expectedGood.consumed)
        XCTAssertEqual(corruptedRenderer.ring.prototypePhase, expectedGood.newPhase, accuracy: 1e-7)

        let corruptOutputSample = corruptedRenderer.values(0).0 + 0.5
        let outputCorruptionDiff = abs(Double(corruptOutputSample) - Double(expectedGood.outL[0]))
        XCTAssertGreaterThan(outputCorruptionDiff, 1e-4)

        let firRenderer = ProductionTestRenderer(layout: .planar, capacity: 2048)
        let steadySine = (0..<128).map { Float(sin(Double($0) * 0.05)) }
        _ = firRenderer.feed(l: steadySine, r: steadySine)
        let firStatus = firRenderer.render(frames: 64, targetFill: 0, ceiling: 1.0)
        XCTAssertEqual(firStatus, noErr)
        XCTAssertEqual(firRenderer.ring.readIndex, 64)
        for i in 0..<64 {
            let (fl, fr) = firRenderer.values(i)
            XCTAssertTrue(fl.isFinite && fr.isFinite)
            XCTAssertEqual(fl, fr, accuracy: 1e-5)
        }
    }

    func testProductionCaller_refillPreservationAndStarvation() {
        let ring = SPSCRingBuffer()
        ring.allocate(capacityFrames: 256)
        defer { ring.deallocate() }

        let ramp1: [Float] = [10, 11, 12, 13, 14]
        _ = ring.write(inL: ramp1, inR: ramp1, frameCount: 5)
        var outL1 = [Float](repeating: 0, count: 8)
        var outR1 = [Float](repeating: 0, count: 8)
        ring.readNonInterleavedResampled(outL: &outL1, outR: &outR1, framesRequested: 8, targetFillFrames: 512)

        XCTAssertEqual(ring.readIndex, 4)
        XCTAssertEqual(ring.availableForReading, 1)

        let ramp2: [Float] = [20, 21, 22, 23, 24]
        _ = ring.write(inL: ramp2, inR: ramp2, frameCount: 5)
        var outL2 = [Float](repeating: 0, count: 4)
        var outR2 = [Float](repeating: 0, count: 4)
        ring.readNonInterleavedResampled(outL: &outL2, outR: &outR2, framesRequested: 4, targetFillFrames: 512)

        XCTAssertLessThan(outL2[0], 19.999)
        XCTAssertGreaterThan(outL2[0], 13.9)

        let ringPhase = SPSCRingBuffer()
        ringPhase.allocate(capacityFrames: 256)
        defer { ringPhase.deallocate() }
        ringPhase.setInternalResamplePhase(0.75)
        _ = ringPhase.write(inL: [0.1, 0.2], inR: [0.1, 0.2], frameCount: 2)
        var starveL = [Float](repeating: 0, count: 8)
        var starveR = [Float](repeating: 0, count: 8)
        ringPhase.readNonInterleavedResampled(outL: &starveL, outR: &starveR, framesRequested: 8, targetFillFrames: 512)
        XCTAssertGreaterThan(ringPhase.prototypePhase, 0.0)

        let invalidRenderer = ProductionTestRenderer(layout: .planar, capacity: 512)
        _ = invalidRenderer.render(frames: 64, targetFill: 256, ceiling: 1.0)
        let invalidStatus = invalidRenderer.list.unsafeMutablePointer.withMemoryRebound(
            to: AudioBufferList.self,
            capacity: 1
        ) { ablPtr in
            ablPtr.pointee.mBuffers.mData = nil
            return CoreAudioOutput.render(
                ring: invalidRenderer.ring, buffers: invalidRenderer.list, frames: 64, capacity: 512,
                targetFill: 256, scratchLeft: invalidRenderer.left, scratchRight: invalidRenderer.right
            )
        }
        XCTAssertEqual(invalidStatus, kAudio_ParamError)
    }

    func testProductionCaller_boundaryWrapAndHistoryAcrossBlocks() {
        let renderer = ProductionTestRenderer(layout: .planar, capacity: 1024)

        let blockSize = 256
        let prefill = [Float](repeating: 0.1, count: 256)
        _ = renderer.feed(l: prefill, r: prefill)

        var totalRead = 0
        for block in 0..<10 {
            let feedL = (0..<blockSize).map { Float($0 + block * blockSize) }
            let feedR = feedL
            let w = renderer.feed(l: feedL, r: feedR)
            XCTAssertEqual(w, blockSize)

            let status = renderer.render(frames: blockSize, targetFill: 256, ceiling: 10000.0)
            XCTAssertEqual(status, noErr)
            totalRead += blockSize
            XCTAssertEqual(renderer.ring.readIndex, totalRead)
        }

        renderer.ring.reset()
        let audioBlock1 = (0..<128).map { Float(sin(Double($0) * 0.2)) }
        _ = renderer.feed(l: audioBlock1, r: audioBlock1)
        let st1 = renderer.render(frames: 64, targetFill: 64, ceiling: 1.0)
        XCTAssertEqual(st1, noErr)
        XCTAssertEqual(renderer.ring.readIndex, 64)

        let audioBlock2 = (128..<192).map { Float(sin(Double($0) * 0.2)) }
        _ = renderer.feed(l: audioBlock2, r: audioBlock2)
        let st2 = renderer.render(frames: 64, targetFill: 64, ceiling: 1.0)
        XCTAssertEqual(st2, noErr)
        XCTAssertEqual(renderer.ring.readIndex, 128)

        for i in 0..<64 {
            let (l, r) = renderer.values(i)
            XCTAssertFalse(l.isNaN)
            XCTAssertFalse(r.isNaN)
            XCTAssertLessThanOrEqual(abs(l), 1.0001)
        }
    }

    func testProductionCaller_starvationRefillAndDriftTrajectory() {
        let renderer = ProductionTestRenderer(layout: .interleaved, capacity: 2048)

        for cycle in 0..<10 {
            let burstCount = 40
            let burstAudio = (0..<burstCount).map { Float(cos(Double($0) * 0.05 + Double(cycle))) }
            _ = renderer.feed(l: burstAudio, r: burstAudio)

            let status = renderer.render(frames: 80, targetFill: 40, ceiling: 1.0)
            XCTAssertEqual(status, noErr)

            for i in 40..<80 {
                let (valL, valR) = renderer.values(i)
                XCTAssertEqual(valL, 0.0, accuracy: 1e-6)
                XCTAssertEqual(valR, 0.0, accuracy: 1e-6)
            }
        }

        renderer.ring.reset()
        for step in 0..<50 {
            let driftRatio = sin(Double(step) * 0.1) * 0.001
            renderer.ring.setInternalResampleCorrection(driftRatio)
            let block = (0..<64).map { Float(sin(Double($0) * 0.1)) }
            _ = renderer.feed(l: block, r: block)
            let status = renderer.render(frames: 64, targetFill: 512, ceiling: 1.0)
            XCTAssertEqual(status, noErr)
        }
        XCTAssertTrue(renderer.ring.readIndex > 0)
    }

    func testOutputCeilingRetainsAppliedConfigurationAcrossDirectFallbackAndBypass() {
        let engine = CoreAudioEngine()
        defer { engine.clearEQ() }
        engine.rebuildActiveEQFilter(sampleRate: 48000)
        engine.applyFixedBandEQ([Float](repeating: 0, count: 10), outputBoost: 6)
        let filters = [AutoEQSourceFilter(frequency: 16000, gain: 0, q: 20, type: .notch)]
        XCTAssertNotNil(engine.applyDirectEQ(
            filters, preamp: 0, outputBoost: 6, calibrationBands: [], calibrationPreamp: 0
        ))
        XCTAssertEqual(engine.activeCeiling, 0.8912509, accuracy: 1e-6)

        engine.rebuildActiveEQFilter(sampleRate: 32000)
        XCTAssertFalse(engine.isDirectEQAvailable)
        XCTAssertEqual(engine.activeCeiling, 1, accuracy: 1e-6)
        engine.setEnabled(false)
        engine.setEnabled(true)
        XCTAssertEqual(engine.activeCeiling, 1, accuracy: 1e-6)

        engine.rebuildActiveEQFilter(sampleRate: 96000)
        XCTAssertTrue(engine.isDirectEQAvailable)
        XCTAssertEqual(engine.activeCeiling, 0.8912509, accuracy: 1e-6)
        engine.setEnabled(false)
        engine.applyFixedBandEQ([Float](repeating: 0, count: 10), outputBoost: 0)
        engine.setEnabled(true)
        XCTAssertEqual(engine.activeCeiling, 1, accuracy: 1e-6)

        engine.setEnabled(false)
        engine.applyGraphicEQ31([Float](repeating: 0, count: 31), outputBoost: 3)
        XCTAssertEqual(engine.activeCeiling, 1, accuracy: 1e-6)
        engine.setEnabled(true)
        XCTAssertEqual(engine.activeCeiling, 0.8912509, accuracy: 1e-6)
    }

    func testProductionCaller_outputCeiling_togglesAndDistortion() {
        let engine = CoreAudioEngine()

        let flat10 = [Float](repeating: 0, count: 10)
        engine.applyFixedBandEQ(flat10, preamp: 0.0, outputBoost: 0.0)
        XCTAssertEqual(engine.activeCeiling, 1.0, accuracy: 1e-5)

        engine.applyFixedBandEQ(flat10, preamp: 0.0, outputBoost: 3.0)
        XCTAssertEqual(engine.activeCeiling, 0.8912509, accuracy: 1e-5)

        engine.isEnabled = false
        XCTAssertEqual(engine.activeCeiling, 1.0, accuracy: 1e-5)

        let renderer = ProductionTestRenderer(layout: .planar, capacity: 512)
        let passThruAudio: [Float] = (0..<128).map { _ in 0.95 }
        _ = renderer.feed(l: passThruAudio, r: passThruAudio)
        _ = renderer.render(frames: 128, targetFill: 128, ceiling: engine.activeCeiling)
        for i in 0..<128 {
            let (l, r) = renderer.values(i)
            XCTAssertEqual(l, 0.95, accuracy: 1e-4)
            XCTAssertEqual(r, 0.95, accuracy: 1e-4)
        }

        engine.isEnabled = true
        XCTAssertEqual(engine.activeCeiling, 0.8912509, accuracy: 1e-5)

        renderer.ring.reset()
        _ = renderer.feed(l: passThruAudio, r: passThruAudio)
        _ = renderer.render(frames: 128, targetFill: 128, ceiling: engine.activeCeiling)
        for i in 0..<128 {
            let (l, r) = renderer.values(i)
            XCTAssertLessThanOrEqual(l, 0.8912509 + 1e-6)
            XCTAssertLessThanOrEqual(r, 0.8912509 + 1e-6)
        }

        let flat31 = [Float](repeating: 0, count: 31)
        engine.applyGraphicEQ31(flat31, preamp: 0.0, outputBoost: 6.0)
        XCTAssertEqual(engine.activeCeiling, 0.8912509, accuracy: 1e-5)

        engine.setEnabled(false)
        XCTAssertEqual(engine.activeCeiling, 1.0, accuracy: 1e-5)

        engine.setEnabled(true)
        XCTAssertEqual(engine.activeCeiling, 0.8912509, accuracy: 1e-5)

        let rejectedResult = engine.applyDirectEQ(
            [], preamp: Float.nan, outputBoost: 10.0,
            calibrationBands: [], calibrationPreamp: 0.0
        )
        XCTAssertNil(rejectedResult)
        XCTAssertEqual(engine.activeCeiling, 0.8912509, accuracy: 1e-5)

        engine.clearEQ()
        XCTAssertEqual(engine.activeCeiling, 1.0, accuracy: 1e-5)
        engine.rebuildActiveEQFilter(sampleRate: 48000)
        XCTAssertNil(engine.vdspFilter)
        engine.setEnabled(false)
        engine.setEnabled(true)
        XCTAssertEqual(engine.activeCeiling, 1.0, accuracy: 1e-5)
        engine.clearEQ()

        let subThresh: [Float] = (0..<128).map { _ in 0.5 }
        _ = renderer.feed(l: subThresh, r: subThresh)
        _ = renderer.render(frames: 128, targetFill: 0, ceiling: 0.8912509)
        for i in 0..<128 {
            let (l, r) = renderer.values(i)
            XCTAssertEqual(l, 0.5, accuracy: 0.01)
            XCTAssertEqual(r, 0.5, accuracy: 0.01)
        }

        renderer.ring.reset()
        let overThresh: [Float] = (0..<128).map { _ in 1.5 }
        _ = renderer.feed(l: overThresh, r: overThresh)
        _ = renderer.render(frames: 128, targetFill: 0, ceiling: 0.8912509)

        var totalClippingError: Float = 0
        for i in 0..<128 {
            let (l, r) = renderer.values(i)
            XCTAssertLessThanOrEqual(l, 0.8912509 + 1e-6)
            XCTAssertLessThanOrEqual(r, 0.8912509 + 1e-6)
            totalClippingError += abs(l - 0.8912509)
        }
        XCTAssertEqual(totalClippingError, 0.0, accuracy: 1e-4)

        let invalidCeilingRenderer = ProductionTestRenderer(layout: .planar, capacity: 512)
        let dummyAudio = [Float](repeating: 0.1, count: 64)
        _ = invalidCeilingRenderer.feed(l: dummyAudio, r: dummyAudio)

        let nanStatus = invalidCeilingRenderer.render(frames: 64, targetFill: 64, ceiling: Float.nan)
        XCTAssertEqual(nanStatus, kAudio_ParamError)

        let negStatus = invalidCeilingRenderer.render(frames: 64, targetFill: 64, ceiling: -1.0)
        XCTAssertEqual(negStatus, kAudio_ParamError)

        let zeroStatus = invalidCeilingRenderer.render(frames: 64, targetFill: 64, ceiling: 0.0)
        XCTAssertEqual(zeroStatus, kAudio_ParamError)
    }

    func testProductionCaller_lifecycleAndFailureInjection() {
        let ring = SPSCRingBuffer()

        ring.allocate(capacityFrames: 256)
        XCTAssertEqual(ring.capacity, 1024)
        ring.allocate(capacityFrames: 2048)
        XCTAssertEqual(ring.capacity, 2048)

        _ = ring.write(inL: [0.1, 0.2], inR: [0.1, 0.2], frameCount: 2)
        XCTAssertEqual(ring.availableForReading, 2)
        ring.reset()
        XCTAssertEqual(ring.availableForReading, 0)
        XCTAssertEqual(ring.readIndex, 0)
        XCTAssertEqual(ring.writeIndex, 0)
        ring.deallocate()

        let engine = CoreAudioEngine()
        engine.stop()
        XCTAssertFalse(engine.isRunning)
    }

    func testProductionCaller_acceptanceData_quantitativeBenchmarks() {
        let renderer = ProductionTestRenderer(layout: .planar, capacity: 2048)
        let blockSizes = [64, 128, 512]

        for blockSize in blockSizes {
            let iterations = 100
            let audio = (0..<blockSize).map { Float(sin(Double($0) * 0.05)) }
            var executionTimesNanos: [UInt64] = []

            for _ in 0..<iterations {
                _ = renderer.feed(l: audio, r: audio)
                let start = mach_absolute_time()
                _ = renderer.render(frames: blockSize, targetFill: 512, ceiling: 1.0)
                let end = mach_absolute_time()
                executionTimesNanos.append(end - start)
            }

            executionTimesNanos.sort()
            let p50Nanos = executionTimesNanos[iterations / 2]
            let p99Nanos = executionTimesNanos[Int(Double(iterations) * 0.99)]

            let deadlineNanos = UInt64(Double(blockSize) / 48000.0 * 1e9)
            let p99FractionOfDeadline = Double(p99Nanos) / Double(deadlineNanos)

            let env = ProcessInfo.processInfo.environment
            let isSanitizer = dlsym(dlopen(nil, RTLD_LAZY), "__tsan_init") != nil ||
                dlsym(dlopen(nil, RTLD_LAZY), "__asan_init") != nil ||
                env["SYSTEMEQ_TEST_SANITIZER"] != nil
            let isCI = env["CI"] != nil || env["GITHUB_ACTIONS"] != nil
            let maxFraction = isSanitizer ? 0.50 : (isCI ? 0.35 : 0.10)

            XCTAssertLessThan(p99FractionOfDeadline, maxFraction)
            XCTAssertGreaterThan(p50Nanos, 0)
        }

        renderer.ring.reset()
        XCTAssertEqual(renderer.ring.availableForReading, 0)
    }
}
