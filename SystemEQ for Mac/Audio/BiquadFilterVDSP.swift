//
//  BiquadFilterVDSP.swift
//  SystemEQ for Mac
//
//  Real vDSP-backed cascaded biquad filter chain using vDSP_biquad API.
//  Apple's accelerate framework runs the cascade fully SIMD-vectorized.
//

import Accelerate
import Foundation

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
    public func configure(bands: [ParametricBand], preamp: Float, sampleRate: Float) {
        self.sampleRate = sampleRate
        self.preampLinear = pow(10.0, preamp / 20.0)

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
            let c = calculateCoefficients(
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
    public func processStereo(
        _ bufferL: UnsafeMutablePointer<Float>,
        _ bufferR: UnsafeMutablePointer<Float>,
        frameCount: Int
    ) {
        // Apply preamp first (vDSP scalar multiply — SIMD).
        if preampLinear != 1.0 {
            var scalar = preampLinear
            vDSP_vsmul(bufferL, 1, &scalar, bufferL, 1, vDSP_Length(frameCount))
            vDSP_vsmul(bufferR, 1, &scalar, bufferR, 1, vDSP_Length(frameCount))
        }

        guard filterCount > 0, let sL = setupL, let sR = setupR else { return }

        delaysL.withUnsafeMutableBufferPointer { dL in
            guard let addressL = dL.baseAddress else { return }
            vDSP_biquad(sL, addressL, bufferL, 1, bufferL, 1, vDSP_Length(frameCount))
        }
        delaysR.withUnsafeMutableBufferPointer { dR in
            guard let addressR = dR.baseAddress else { return }
            vDSP_biquad(sR, addressR, bufferR, 1, bufferR, 1, vDSP_Length(frameCount))
        }
    }

    // MARK: - Coefficient calculation (RBJ audio EQ cookbook)

    private func calculateCoefficients(
        frequency: Float,
        gain: Float,
        q: Float,
        type: FilterType,
        sampleRate: Float
    ) -> (b0: Float, b1: Float, b2: Float, a1: Float, a2: Float) {
        let A = pow(10.0, gain / 40.0)
        let omega = 2.0 * Float.pi * frequency / sampleRate
        let sinW = sin(omega)
        let cosW = cos(omega)

        var b0: Float, b1: Float, b2: Float, a0: Float, a1: Float, a2: Float

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
            let twoSqrtA_alpha = 2.0 * sqrt(A) * alpha
            b0 = A * ((A + 1) - (A - 1) * cosW + twoSqrtA_alpha)
            b1 = 2.0 * A * ((A - 1) - (A + 1) * cosW)
            b2 = A * ((A + 1) - (A - 1) * cosW - twoSqrtA_alpha)
            a0 = (A + 1) + (A - 1) * cosW + twoSqrtA_alpha
            a1 = -2.0 * ((A - 1) + (A + 1) * cosW)
            a2 = (A + 1) + (A - 1) * cosW - twoSqrtA_alpha

        case .highShelf:
            let alpha = sinW / (2.0 * q)
            let twoSqrtA_alpha = 2.0 * sqrt(A) * alpha
            b0 = A * ((A + 1) + (A - 1) * cosW + twoSqrtA_alpha)
            b1 = -2.0 * A * ((A - 1) + (A + 1) * cosW)
            b2 = A * ((A + 1) + (A - 1) * cosW - twoSqrtA_alpha)
            a0 = (A + 1) - (A - 1) * cosW + twoSqrtA_alpha
            a1 = 2.0 * ((A - 1) - (A + 1) * cosW)
            a2 = (A + 1) - (A - 1) * cosW - twoSqrtA_alpha

        default:
            let alpha = sinW / (2.0 * q)
            b0 = 1.0 + alpha * A
            b1 = -2.0 * cosW
            b2 = 1.0 - alpha * A
            a0 = 1.0 + alpha / A
            a1 = -2.0 * cosW
            a2 = 1.0 - alpha / A
        }

        // vDSP_biquad uses subtractive feedback convention: y = b0*x + b1*x[-1] + b2*x[-2]
        //                                                     - a1*y[-1] - a2*y[-2]
        // RBJ cookbook gives a1, a2 already in this sign convention after normalization.
        return (
            b0: b0 / a0,
            b1: b1 / a0,
            b2: b2 / a0,
            a1: a1 / a0,
            a2: a2 / a0
        )
    }

    /// Reset filter states (clears delay lines).
    public func reset() {
        for i in delaysL.indices { delaysL[i] = 0 }
        for i in delaysR.indices { delaysR[i] = 0 }
    }
}
