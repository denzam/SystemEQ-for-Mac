//
//  BiquadFilterVDSP.swift
//  SystemEQ for Mac
//
//  Real vDSP-backed cascaded biquad filter chain using vDSP_biquad API.
//  Apple's accelerate framework runs the cascade fully SIMD-vectorized.
//

import Accelerate
import Foundation

nonisolated struct OutputSafetyProcessor {
    static let maximumBoostDB: Float = 12.0
    private static let boostedCeiling: Float = 0.891_250_9

    private var boostLinear: Float = 1.0
    private var ceiling: Float = 1.0
    private var releaseCoefficient: Float = 0.0
    private var limiterGain: Float = 1.0

    mutating func configure(boostDB: Float, sampleRate: Float) {
        let sanitizedBoost = boostDB.isFinite ? min(max(boostDB, 0), Self.maximumBoostDB) : 0
        boostLinear = pow(10.0, sanitizedBoost / 20.0)
        ceiling = sanitizedBoost > 0 ? Self.boostedCeiling : 1.0
        let safeSampleRate = max(sampleRate, 1)
        releaseCoefficient = 1 - exp(-1 / (safeSampleRate * 0.1))
        limiterGain = 1.0
    }

    mutating func reset() {
        limiterGain = 1.0
    }

    @inline(__always)
    @discardableResult
    mutating func processMono(_ buffer: UnsafeMutablePointer<Float>, frameCount: Int) -> Float {
        guard frameCount > 0 else { return 1 }

        var peak: Float = 0
        vDSP_maxmgv(buffer, 1, &peak, vDSP_Length(frameCount))
        if limiterGain == 1.0, peak.isFinite, peak * boostLinear <= ceiling {
            if boostLinear != 1.0 {
                var scalar = boostLinear
                vDSP_vsmul(buffer, 1, &scalar, buffer, 1, vDSP_Length(frameCount))
            }
            return 1
        }

        var currentGain = limiterGain
        var minimumGain = currentGain
        for index in 0..<frameCount {
            let boosted = buffer[index] * boostLinear
            guard boosted.isFinite else {
                buffer[index] = 0
                currentGain = 1.0
                continue
            }

            let peak = abs(boosted)
            let targetGain = peak > ceiling ? ceiling / peak : 1.0
            if targetGain < currentGain {
                currentGain = targetGain
            } else {
                currentGain += (targetGain - currentGain) * releaseCoefficient
            }
            minimumGain = min(minimumGain, currentGain)
            buffer[index] = boosted * currentGain
        }
        if currentGain > 0.999_9 { currentGain = 1.0 }
        limiterGain = currentGain
        return min(max(minimumGain, 0), 1)
    }

    @inline(__always)
    @discardableResult
    mutating func processStereo(
        _ bufferL: UnsafeMutablePointer<Float>,
        _ bufferR: UnsafeMutablePointer<Float>,
        frameCount: Int
    ) -> Float {
        guard frameCount > 0 else { return 1 }

        var peakL: Float = 0
        var peakR: Float = 0
        vDSP_maxmgv(bufferL, 1, &peakL, vDSP_Length(frameCount))
        vDSP_maxmgv(bufferR, 1, &peakR, vDSP_Length(frameCount))
        let peak = peakL > peakR ? peakL : peakR
        if limiterGain == 1.0,
           peakL.isFinite,
           peakR.isFinite,
           peak * boostLinear <= ceiling {
            if boostLinear != 1.0 {
                var scalar = boostLinear
                vDSP_vsmul(bufferL, 1, &scalar, bufferL, 1, vDSP_Length(frameCount))
                vDSP_vsmul(bufferR, 1, &scalar, bufferR, 1, vDSP_Length(frameCount))
            }
            return 1
        }

        var currentGain = limiterGain
        var minimumGain = currentGain
        for index in 0..<frameCount {
            let boostedL = bufferL[index] * boostLinear
            let boostedR = bufferR[index] * boostLinear
            guard boostedL.isFinite, boostedR.isFinite else {
                bufferL[index] = 0
                bufferR[index] = 0
                currentGain = 1.0
                continue
            }

            let peakL = abs(boostedL)
            let peakR = abs(boostedR)
            let peak = peakL > peakR ? peakL : peakR
            let targetGain = peak > ceiling ? ceiling / peak : 1.0
            if targetGain < currentGain {
                currentGain = targetGain
            } else {
                currentGain += (targetGain - currentGain) * releaseCoefficient
            }
            minimumGain = min(minimumGain, currentGain)
            bufferL[index] = boostedL * currentGain
            bufferR[index] = boostedR * currentGain
        }
        if currentGain > 0.999_9 { currentGain = 1.0 }
        limiterGain = currentGain
        return min(max(minimumGain, 0), 1)
    }
}

struct BiquadCoefficients {
    let b0: Float
    let b1: Float
    let b2: Float
    let a1: Float
    let a2: Float
}

enum BiquadResponseCalculator {
    static func maximumCombinedGainDB(
        bands: [ParametricBand],
        sampleRate: Float,
        pointCount: Int = 512
    ) -> Float {
        let activeBands = bands.filter { abs($0.gain) >= 0.01 }
        guard !activeBands.isEmpty, sampleRate > 0, pointCount > 1 else { return 0 }
        let filterCoefficients = activeBands.map {
            Self.coefficients(
                frequency: $0.frequency,
                gain: $0.gain,
                q: $0.q,
                type: $0.filterType,
                sampleRate: sampleRate
            )
        }
        let minimumFrequency: Float = 20
        let maximumFrequency = min(20000, sampleRate * 0.49)
        let logMinimum = log(minimumFrequency)
        let logRange = log(maximumFrequency) - logMinimum
        var maximumGain: Float = 0

        for index in 0..<pointCount {
            let fraction = Float(index) / Float(pointCount - 1)
            let frequency = exp(logMinimum + logRange * fraction)
            let omega = 2 * Float.pi * frequency / sampleRate
            let cos1 = cos(omega)
            let sin1 = sin(omega)
            let cos2 = cos(2 * omega)
            let sin2 = sin(2 * omega)
            var combinedGain: Float = 0

            for coefficient in filterCoefficients {
                let numeratorReal = coefficient.b0 + coefficient.b1 * cos1 + coefficient.b2 * cos2
                let numeratorImaginary = -(coefficient.b1 * sin1 + coefficient.b2 * sin2)
                let denominatorReal = 1 + coefficient.a1 * cos1 + coefficient.a2 * cos2
                let denominatorImaginary = -(coefficient.a1 * sin1 + coefficient.a2 * sin2)
                let numeratorPower = numeratorReal * numeratorReal + numeratorImaginary * numeratorImaginary
                let denominatorPower = denominatorReal * denominatorReal + denominatorImaginary * denominatorImaginary
                guard numeratorPower > 0, denominatorPower > 0 else { continue }
                combinedGain += 10 * log10(numeratorPower / denominatorPower)
            }
            if combinedGain.isFinite, combinedGain > maximumGain {
                maximumGain = combinedGain
            }
        }

        return maximumGain
    }

    static func coefficients(
        frequency: Float,
        gain: Float,
        q: Float,
        type: FilterType,
        sampleRate: Float
    ) -> BiquadCoefficients {
        let A = pow(10.0, gain / 40.0)
        let omega = 2.0 * Float.pi * frequency / sampleRate
        let sinW = sin(omega)
        let cosW = cos(omega)

        var b0: Float
        var b1: Float
        var b2: Float
        var a0: Float
        var a1: Float
        var a2: Float

        switch type {
        case .peak:
            let alpha = sinW / (2.0 * q)
            b0 = 1.0 + alpha * A
            b1 = -2.0 * cosW
            b2 = 1.0 - alpha * A
            a0 = 1.0 + alpha / A
            a1 = -2.0 * cosW
            a2 = 1.0 - alpha / A
        case .lowShelf:
            let alpha = sinW / (2.0 * q)
            let twoSqrtAAlpha = 2.0 * sqrt(A) * alpha
            b0 = A * ((A + 1) - (A - 1) * cosW + twoSqrtAAlpha)
            b1 = 2.0 * A * ((A - 1) - (A + 1) * cosW)
            b2 = A * ((A + 1) - (A - 1) * cosW - twoSqrtAAlpha)
            a0 = (A + 1) + (A - 1) * cosW + twoSqrtAAlpha
            a1 = -2.0 * ((A - 1) + (A + 1) * cosW)
            a2 = (A + 1) + (A - 1) * cosW - twoSqrtAAlpha
        case .highShelf:
            let alpha = sinW / (2.0 * q)
            let twoSqrtAAlpha = 2.0 * sqrt(A) * alpha
            b0 = A * ((A + 1) + (A - 1) * cosW + twoSqrtAAlpha)
            b1 = -2.0 * A * ((A - 1) + (A + 1) * cosW)
            b2 = A * ((A + 1) + (A - 1) * cosW - twoSqrtAAlpha)
            a0 = (A + 1) - (A - 1) * cosW + twoSqrtAAlpha
            a1 = 2.0 * ((A - 1) - (A + 1) * cosW)
            a2 = (A + 1) - (A - 1) * cosW - twoSqrtAAlpha
        default:
            let alpha = sinW / (2.0 * q)
            b0 = 1.0 + alpha * A
            b1 = -2.0 * cosW
            b2 = 1.0 - alpha * A
            a0 = 1.0 + alpha / A
            a1 = -2.0 * cosW
            a2 = 1.0 - alpha / A
        }

        return BiquadCoefficients(
            b0: b0 / a0,
            b1: b1 / a0,
            b2: b2 / a0,
            a1: a1 / a0,
            a2: a2 / a0
        )
    }
}

/// Cascaded biquad filter using Apple's vDSP_biquad (single-precision).
/// Processes N filters as one SIMD cascade per buffer — ~20-50x faster
/// than a scalar per-sample loop.
public final class BiquadFilterVDSP {
    // MARK: - Properties

    private var filterCount: Int = 0
    private var sampleRate: Float

    /// vDSP biquad setup handle (nil when filterCount == 0 / bypass mode).
    /// Per section, coefficients laid out as [b0, b1, b2, a1, a2] — 5 doubles.
    /// vDSP_biquad_CreateSetup is single-precision Float despite the name suffix.
    private var setupL: vDSP_biquad_Setup?
    private var setupR: vDSP_biquad_Setup?
    /// Delays buffer layout: 2*numSections + 2 floats, initialized to zero.
    private var delaysL: [Float] = []
    private var delaysR: [Float] = []

    /// Preamp gain (linear)
    private var preampLinear: Float = 1.0
    private var outputSafety = OutputSafetyProcessor()

    // MARK: - Initialization

    public init(sampleRate: Float = 48000.0) {
        self.sampleRate = sampleRate
    }

    deinit {
        if let s = setupL { vDSP_biquad_DestroySetup(s) }
        if let s = setupR { vDSP_biquad_DestroySetup(s) }
    }

    // MARK: - Configuration

    /// Configure filter chain from parametric bands (skips zero-gain bands automatically).
    /// Allocates new vDSP setup; previous state is destroyed.
    public func configure(
        bands: [ParametricBand],
        preamp: Float,
        outputBoost: Float = 0.0,
        sampleRate: Float
    ) {
        self.sampleRate = sampleRate
        self.preampLinear = pow(10.0, preamp / 20.0)
        outputSafety.configure(boostDB: outputBoost, sampleRate: sampleRate)

        let activeBands = bands.filter { abs($0.gain) >= 0.01 }
        let newCount = activeBands.count

        // Destroy previous setup before rebuilding.
        if let s = setupL { vDSP_biquad_DestroySetup(s); setupL = nil }
        if let s = setupR { vDSP_biquad_DestroySetup(s); setupR = nil }
        filterCount = newCount

        guard newCount > 0 else {
            delaysL = []
            delaysR = []
            return
        }

        // vDSP_biquad wants Double coefficients laid out per section: b0 b1 b2 a1 a2.
        var coeffs = [Double](repeating: 0, count: newCount * 5)
        for (i, band) in activeBands.enumerated() {
            let c = BiquadResponseCalculator.coefficients(
                frequency: band.frequency,
                gain: band.gain,
                q: band.q,
                type: band.filterType,
                sampleRate: sampleRate
            )
            let base = i * 5
            coeffs[base + 0] = Double(c.b0)
            coeffs[base + 1] = Double(c.b1)
            coeffs[base + 2] = Double(c.b2)
            coeffs[base + 3] = Double(c.a1)
            coeffs[base + 4] = Double(c.a2)
        }

        setupL = vDSP_biquad_CreateSetup(coeffs, vDSP_Length(newCount))
        setupR = vDSP_biquad_CreateSetup(coeffs, vDSP_Length(newCount))
        // Delay buffer size per Apple docs: 2*numSections + 2 Float values, zero-init.
        delaysL = [Float](repeating: 0, count: 2 * newCount + 2)
        delaysR = [Float](repeating: 0, count: 2 * newCount + 2)
    }

    // MARK: - Processing

    /// Process stereo buffer (real vDSP cascade).
    @inline(__always)
    @discardableResult
    public func processStereo(
        _ bufferL: UnsafeMutablePointer<Float>,
        _ bufferR: UnsafeMutablePointer<Float>,
        frameCount: Int
    ) -> Float {
        // Apply preamp first (vDSP scalar multiply — SIMD).
        if preampLinear != 1.0 {
            var scalar = preampLinear
            vDSP_vsmul(bufferL, 1, &scalar, bufferL, 1, vDSP_Length(frameCount))
            vDSP_vsmul(bufferR, 1, &scalar, bufferR, 1, vDSP_Length(frameCount))
        }

        if filterCount > 0, let sL = setupL, let sR = setupR {
            delaysL.withUnsafeMutableBufferPointer { dL in
                guard let addressL = dL.baseAddress else { return }
                vDSP_biquad(sL, addressL, bufferL, 1, bufferL, 1, vDSP_Length(frameCount))
            }
            delaysR.withUnsafeMutableBufferPointer { dR in
                guard let addressR = dR.baseAddress else { return }
                vDSP_biquad(sR, addressR, bufferR, 1, bufferR, 1, vDSP_Length(frameCount))
            }
        }

        return outputSafety.processStereo(bufferL, bufferR, frameCount: frameCount)
    }

    /// Reset filter states (clears delay lines).
    public func reset() {
        for i in delaysL.indices {
            delaysL[i] = 0
        }
        for i in delaysR.indices {
            delaysR[i] = 0
        }
        outputSafety.reset()
    }
}
