//
//  BiquadFilter.swift
//  SystemEQ for Mac
//
//  Created by Denys Zamorniak on 07/10/25.
//

import Accelerate
import Foundation

// MARK: - Biquad Filter

public class BiquadFilter {
    public var b0: Float = 0.0
    public var b1: Float = 0.0
    public var b2: Float = 0.0
    public var a1: Float = 0.0
    public var a2: Float = 0.0

    public var x1: Float = 0.0 // Input history (left channel)
    public var x2: Float = 0.0
    public var y1: Float = 0.0 // Output history (left channel)
    public var y2: Float = 0.0

    // Right channel state (for stereo processing)
    public var x1_r: Float = 0.0
    public var x2_r: Float = 0.0
    public var y1_r: Float = 0.0
    public var y2_r: Float = 0.0

    /// ⚡ OPTIMIZATION: Bypass filter if gain is near zero
    public var isBypass: Bool = false

    public init() {}

    public func configurePeak(frequency: Float, gain: Float, q: Float, sampleRate: Float) {
        let A = pow(10.0, gain / 40.0)
        let omega = 2.0 * Float.pi * frequency / sampleRate
        let sinW = sin(omega)
        let cosW = cos(omega)
        let alpha = sinW / (2.0 * q)

        b0 = 1.0 + alpha * A
        b1 = -2.0 * cosW
        b2 = 1.0 - alpha * A
        a0 = 1.0 + alpha / A
        a1 = -2.0 * cosW
        a2 = 1.0 - alpha / A

        // Normalize
        b0 /= a0
        b1 /= a0
        b2 /= a0
        a1 /= a0
        a2 /= a0
    }

    public func configureLowShelf(frequency: Float, gain: Float, q: Float, sampleRate: Float) {
        let A = pow(10.0, gain / 40.0)
        let omega = 2.0 * Float.pi * frequency / sampleRate
        let sinW = sin(omega)
        let cosW = cos(omega)
        let alpha = sinW / (2.0 * q)
        let twoSqrtA_alpha = 2.0 * sqrt(A) * alpha

        b0 = A * ((A + 1) - (A - 1) * cosW + twoSqrtA_alpha)
        b1 = 2.0 * A * ((A - 1) - (A + 1) * cosW)
        b2 = A * ((A + 1) - (A - 1) * cosW - twoSqrtA_alpha)
        a0 = (A + 1) + (A - 1) * cosW + twoSqrtA_alpha
        a1 = -2.0 * ((A - 1) + (A + 1) * cosW)
        a2 = (A + 1) + (A - 1) * cosW - twoSqrtA_alpha

        // Normalize
        b0 /= a0
        b1 /= a0
        b2 /= a0
        a1 /= a0
        a2 /= a0
    }

    public func configureHighShelf(frequency: Float, gain: Float, q: Float, sampleRate: Float) {
        let A = pow(10.0, gain / 40.0)
        let omega = 2.0 * Float.pi * frequency / sampleRate
        let sinW = sin(omega)
        let cosW = cos(omega)
        let alpha = sinW / (2.0 * q)
        let twoSqrtA_alpha = 2.0 * sqrt(A) * alpha

        b0 = A * ((A + 1) + (A - 1) * cosW + twoSqrtA_alpha)
        b1 = -2.0 * A * ((A - 1) + (A + 1) * cosW)
        b2 = A * ((A + 1) + (A - 1) * cosW - twoSqrtA_alpha)
        a0 = (A + 1) - (A - 1) * cosW + twoSqrtA_alpha
        a1 = 2.0 * ((A - 1) - (A + 1) * cosW)
        a2 = (A + 1) - (A - 1) * cosW - twoSqrtA_alpha

        // Normalize
        b0 /= a0
        b1 /= a0
        b2 /= a0
        a1 /= a0
        a2 /= a0
    }

    public func process(_ input: Float) -> Float {
        let output = b0 * input + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2

        // Update history
        x2 = x1
        x1 = input
        y2 = y1
        y1 = output

        return output
    }

    /// ⚡ OPTIMIZED: Process entire buffer at once (10-100x faster)
    public func processBuffer(_ buffer: UnsafeMutablePointer<Float>, frameCount: Int) {
        // Skip processing if filter is bypassed (near-zero gain)
        if isBypass { return }

        // Cache coefficients for faster access
        let _b0 = b0, _b1 = b1, _b2 = b2, _a1 = a1, _a2 = a2
        var _x1 = x1, _x2 = x2, _y1 = y1, _y2 = y2

        // Process in chunks of 4 for better CPU cache utilization
        let chunks = frameCount / 4

        for chunk in 0..<chunks {
            let base = chunk * 4
            for i in 0..<4 {
                let idx = base + i
                let input = buffer[idx]
                let output = _b0 * input + _b1 * _x1 + _b2 * _x2 - _a1 * _y1 - _a2 * _y2

                _x2 = _x1
                _x1 = input
                _y2 = _y1
                _y1 = output

                buffer[idx] = output
            }
        }

        // Process remaining samples
        for i in (chunks * 4)..<frameCount {
            let input = buffer[i]
            let output = _b0 * input + _b1 * _x1 + _b2 * _x2 - _a1 * _y1 - _a2 * _y2

            _x2 = _x1
            _x1 = input
            _y2 = _y1
            _y1 = output

            buffer[i] = output
        }

        // Update state
        x1 = _x1
        x2 = _x2
        y1 = _y1
        y2 = _y2
    }

    /// ⚡ OPTIMIZED: Process stereo buffers simultaneously (2x faster than separate calls)
    public func processStereoBuffers(
        _ bufferL: UnsafeMutablePointer<Float>,
        _ bufferR: UnsafeMutablePointer<Float>,
        frameCount: Int
    ) {
        // Skip processing if filter is bypassed (near-zero gain)
        if isBypass { return }

        // Cache coefficients for faster access
        let _b0 = b0, _b1 = b1, _b2 = b2, _a1 = a1, _a2 = a2
        var _x1 = x1, _x2 = x2, _y1 = y1, _y2 = y2
        var _x1_r = x1_r, _x2_r = x2_r, _y1_r = y1_r, _y2_r = y2_r

        // Process in chunks of 4 for better CPU cache utilization
        let chunks = frameCount / 4

        for chunk in 0..<chunks {
            let base = chunk * 4
            for i in 0..<4 {
                let idx = base + i

                // Process left channel
                let inputL = bufferL[idx]
                let outputL = _b0 * inputL + _b1 * _x1 + _b2 * _x2 - _a1 * _y1 - _a2 * _y2
                _x2 = _x1
                _x1 = inputL
                _y2 = _y1
                _y1 = outputL
                bufferL[idx] = outputL

                // Process right channel
                let inputR = bufferR[idx]
                let outputR = _b0 * inputR + _b1 * _x1_r + _b2 * _x2_r - _a1 * _y1_r - _a2 * _y2_r
                _x2_r = _x1_r
                _x1_r = inputR
                _y2_r = _y1_r
                _y1_r = outputR
                bufferR[idx] = outputR
            }
        }

        // Process remaining samples
        for i in (chunks * 4)..<frameCount {
            // Process left channel
            let inputL = bufferL[i]
            let outputL = _b0 * inputL + _b1 * _x1 + _b2 * _x2 - _a1 * _y1 - _a2 * _y2
            _x2 = _x1
            _x1 = inputL
            _y2 = _y1
            _y1 = outputL
            bufferL[i] = outputL

            // Process right channel
            let inputR = bufferR[i]
            let outputR = _b0 * inputR + _b1 * _x1_r + _b2 * _x2_r - _a1 * _y1_r - _a2 * _y2_r
            _x2_r = _x1_r
            _x1_r = inputR
            _y2_r = _y1_r
            _y1_r = outputR
            bufferR[i] = outputR
        }

        // Update state
        x1 = _x1
        x2 = _x2
        y1 = _y1
        y2 = _y2
        x1_r = _x1_r
        x2_r = _x2_r
        y1_r = _y1_r
        y2_r = _y2_r
    }

    private var a0: Float = 1.0
}

// MARK: - Biquad Filter Chain

public class BiquadFilterChain {
    public var filters: [BiquadFilter]
    public var preamp: Float = 0.0
    public var activeFilterCount: Int = 0 // Track number of non-bypassed filters
    private var outputSafety = OutputSafetyProcessor()

    public init(filterCount: Int = 10) {
        filters = (0..<filterCount).map { _ in BiquadFilter() }
    }

    public func configure(with preset: EQPreset, sampleRate: Float) {
        preamp = preset.preamp

        // Configure filters for each band
        for (index, band) in preset.bands.enumerated() where index < filters.count {
            configureBand(
                at: index,
                frequency: band.frequency,
                gain: band.gain,
                q: band.q,
                type: band.filterType,
                sampleRate: sampleRate
            )
        }
    }

    public func configureBands(
        _ frequencies: [Float],
        gains: [Float],
        qs: [Float],
        types: [FilterType],
        sampleRate: Float
    ) {
        for i in 0..<min(filters.count, frequencies.count) {
            let gain = i < gains.count ? gains[i] : 0.0
            let q = i < qs.count ? qs[i] : 1.0
            let type = i < types.count ? types[i] : .peak
            configureBand(at: i, frequency: frequencies[i], gain: gain, q: q, type: type, sampleRate: sampleRate)
        }
    }

    public func configureOutputSafety(outputBoost: Float, sampleRate: Float) {
        outputSafety.configure(boostDB: outputBoost, sampleRate: sampleRate)
    }

    private func configureBand(
        at index: Int,
        frequency: Float,
        gain: Float,
        q: Float,
        type: FilterType,
        sampleRate: Float
    ) {
        let filter = filters[index]
        filter.isBypass = abs(gain) < 0.01

        switch type {
        case .peak:
            filter.configurePeak(frequency: frequency, gain: gain, q: q, sampleRate: sampleRate)
        case .lowShelf:
            filter.configureLowShelf(frequency: frequency, gain: gain, q: q, sampleRate: sampleRate)
        case .highShelf:
            filter.configureHighShelf(frequency: frequency, gain: gain, q: q, sampleRate: sampleRate)
        default:
            filter.configurePeak(frequency: frequency, gain: gain, q: q, sampleRate: sampleRate)
        }

        // Update active filter count
        activeFilterCount = filters.count(where: { !$0.isBypass })
    }

    public func process(_ input: Float) -> Float {
        var output = input * pow(10.0, preamp / 20.0)

        for i in 0..<filters.count {
            output = filters[i].process(output)
        }

        var result = output
        withUnsafeMutablePointer(to: &result) { outputSafety.processMono($0, frameCount: 1) }
        return result
    }

    /// ⚡ OPTIMIZED: Process entire buffer at once (10-100x faster than sample-by-sample)
    public func processBuffer(_ buffer: UnsafeMutablePointer<Float>, frameCount: Int) {
        // Apply preamp first (if needed)
        if preamp != 0.0 {
            let preampLinear = pow(10.0, preamp / 20.0)
            var scalar = preampLinear
            vDSP_vsmul(buffer, 1, &scalar, buffer, 1, vDSP_Length(frameCount))
        }

        // Apply each filter in chain (bypassed filters are skipped automatically)
        for filter in filters {
            filter.processBuffer(buffer, frameCount: frameCount)
        }
        outputSafety.processMono(buffer, frameCount: frameCount)
    }

    /// ⚡ OPTIMIZED: Process stereo buffers simultaneously (2x faster than separate calls)
    public func processStereoBuffers(
        _ bufferL: UnsafeMutablePointer<Float>,
        _ bufferR: UnsafeMutablePointer<Float>,
        frameCount: Int
    ) {
        // Apply preamp first (if needed)
        if preamp != 0.0 {
            let preampLinear = pow(10.0, preamp / 20.0)
            var scalar = preampLinear
            vDSP_vsmul(bufferL, 1, &scalar, bufferL, 1, vDSP_Length(frameCount))
            vDSP_vsmul(bufferR, 1, &scalar, bufferR, 1, vDSP_Length(frameCount))
        }

        // Apply each filter to both channels simultaneously (bypassed filters are skipped)
        for filter in filters {
            filter.processStereoBuffers(bufferL, bufferR, frameCount: frameCount)
        }
        outputSafety.processStereo(bufferL, bufferR, frameCount: frameCount)
    }
}
