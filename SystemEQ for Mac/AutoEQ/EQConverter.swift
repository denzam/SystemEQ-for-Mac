//
//  EQConverter.swift
//  SystemEQ for Mac
//
//  Converts parametric EQ to Fixed Band (10) or Graphic (31) using biquad response calculation
//

import Accelerate
import Foundation

/// Converts parametric EQ presets to fixed-band formats
///
/// Usage:
///   - `EQConverter.shared` for standard 48 kHz (backward-compatible singleton)
///   - `EQConverter(sampleRate: 44100)` for custom sample rates or testing
class EQConverter {
    static let shared = EQConverter()

    let sampleRate: Double

    /// Create a converter for the specified sample rate
    /// - Parameter sampleRate: Sample rate in Hz (default: 48000)
    init(sampleRate: Double = 48000.0) {
        self.sampleRate = sampleRate
    }

    /// Convert parametric bands to 10-band fixed EQ
    func convertToFixedBand(_ parametricBands: [ParametricBand], preampGain: Float = 0) -> [Float] {
        let isoFrequencies = AutoEQConstants.tenBandFrequencies
        var gains = [Float](repeating: 0, count: 10)

        for (index, frequency) in isoFrequencies.enumerated() {
            var totalGain: Float = 0

            // Calculate contribution from each parametric band
            for band in parametricBands {
                let response = calculateBandResponse(band: band, atFrequency: Double(frequency))
                totalGain += response
            }

            gains[index] = totalGain + preampGain
        }

        return gains
    }

    /// Convert parametric bands to 31-band graphic EQ
    func convertToGraphicEQ(_ parametricBands: [ParametricBand], preampGain: Float = 0) -> [Float] {
        let frequencies = AutoEQConstants.thirtyOneCenters
        var gains = [Float](repeating: 0, count: 31)

        for (index, frequency) in frequencies.enumerated() {
            var totalGain: Float = 0

            // Calculate contribution from each parametric band
            for band in parametricBands {
                let response = calculateBandResponse(band: band, atFrequency: Double(frequency))
                totalGain += response
            }

            gains[index] = totalGain + preampGain
        }

        return gains
    }

    /// Calculate frequency response at a specific frequency for a single band
    private func calculateBandResponse(band: ParametricBand, atFrequency testFreq: Double) -> Float {
        let fc = band.frequency
        let gain = band.gain
        let q = band.q

        switch band.filterType {
        case .peak:
            return calculatePeakResponse(fc: Double(fc), gain: gain, q: q, testFreq: testFreq)

        case .lowShelf:
            return calculateLowShelfResponse(fc: Double(fc), gain: gain, q: q, testFreq: testFreq)

        case .highShelf:
            return calculateHighShelfResponse(fc: Double(fc), gain: gain, q: q, testFreq: testFreq)

        case .lowPass:
            // Note: slope handling depends on FilterType enum definition
            let slope = 12 // Default slope
            return calculateLowPassResponse(fc: Double(fc), testFreq: testFreq, slope: slope)

        case .highPass:
            // Note: slope handling depends on FilterType enum definition
            let slope = 12 // Default slope
            return calculateHighPassResponse(fc: Double(fc), testFreq: testFreq, slope: slope)

        case .allPass,
             .allPassPEQ,
             .bandPass,
             .notch:
            // Not commonly used in headphone EQ
            return 0
        }
    }

    // MARK: - Biquad Response Calculations

    /// Peak/Dip (Bell) filter response
    private func calculatePeakResponse(fc: Double, gain: Float, q: Float, testFreq: Double) -> Float {
        let A = pow(10.0, Double(gain) / 40.0) // Amplitude
        let omega = 2.0 * .pi * fc / sampleRate
        let alpha = sin(omega) / (2.0 * Double(q))

        // Biquad coefficients for peaking EQ
        let b0 = 1.0 + alpha * A
        let b1 = -2.0 * cos(omega)
        let b2 = 1.0 - alpha * A
        let a0 = 1.0 + alpha / A
        let a1 = -2.0 * cos(omega)
        let a2 = 1.0 - alpha / A

        return calculateMagnitudeResponse(b0: b0, b1: b1, b2: b2, a0: a0, a1: a1, a2: a2, testFreq: testFreq)
    }

    /// Low shelf filter response
    private func calculateLowShelfResponse(fc: Double, gain: Float, q: Float, testFreq: Double) -> Float {
        let A = pow(10.0, Double(gain) / 40.0)
        let omega = 2.0 * .pi * fc / sampleRate
        let beta = sqrt(A) / Double(q)

        let b0 = A * ((A + 1.0) - (A - 1.0) * cos(omega) + beta * sin(omega))
        let b1 = 2.0 * A * ((A - 1.0) - (A + 1.0) * cos(omega))
        let b2 = A * ((A + 1.0) - (A - 1.0) * cos(omega) - beta * sin(omega))
        let a0 = (A + 1.0) + (A - 1.0) * cos(omega) + beta * sin(omega)
        let a1 = -2.0 * ((A - 1.0) + (A + 1.0) * cos(omega))
        let a2 = (A + 1.0) + (A - 1.0) * cos(omega) - beta * sin(omega)

        return calculateMagnitudeResponse(b0: b0, b1: b1, b2: b2, a0: a0, a1: a1, a2: a2, testFreq: testFreq)
    }

    /// High shelf filter response
    private func calculateHighShelfResponse(fc: Double, gain: Float, q: Float, testFreq: Double) -> Float {
        let A = pow(10.0, Double(gain) / 40.0)
        let omega = 2.0 * .pi * fc / sampleRate
        let beta = sqrt(A) / Double(q)

        let b0 = A * ((A + 1.0) + (A - 1.0) * cos(omega) + beta * sin(omega))
        let b1 = -2.0 * A * ((A - 1.0) + (A + 1.0) * cos(omega))
        let b2 = A * ((A + 1.0) + (A - 1.0) * cos(omega) - beta * sin(omega))
        let a0 = (A + 1.0) - (A - 1.0) * cos(omega) + beta * sin(omega)
        let a1 = 2.0 * ((A - 1.0) - (A + 1.0) * cos(omega))
        let a2 = (A + 1.0) - (A - 1.0) * cos(omega) - beta * sin(omega)

        return calculateMagnitudeResponse(b0: b0, b1: b1, b2: b2, a0: a0, a1: a1, a2: a2, testFreq: testFreq)
    }

    /// Low pass filter response
    private func calculateLowPassResponse(fc: Double, testFreq: Double, slope: Int) -> Float {
        // Simplified approximation: -slope dB/octave
        if testFreq <= fc {
            return 0
        }

        let octaves = log2(testFreq / fc)
        return Float(-Double(slope) * octaves)
    }

    /// High pass filter response
    private func calculateHighPassResponse(fc: Double, testFreq: Double, slope: Int) -> Float {
        // Simplified approximation: -slope dB/octave
        if testFreq >= fc {
            return 0
        }

        let octaves = log2(fc / testFreq)
        return Float(-Double(slope) * octaves)
    }

    /// Calculate magnitude response in dB from biquad coefficients
    private func calculateMagnitudeResponse(
        b0: Double,
        b1: Double,
        b2: Double,
        a0: Double,
        a1: Double,
        a2: Double,
        testFreq: Double
    ) -> Float {
        let omega = 2.0 * .pi * testFreq / sampleRate

        // Complex number calculations for frequency response
        let cosOmega = cos(omega)
        let cos2Omega = cos(2.0 * omega)
        let sinOmega = sin(omega)
        let sin2Omega = sin(2.0 * omega)

        // Numerator (real and imaginary parts)
        let numReal = b0 + b1 * cosOmega + b2 * cos2Omega
        let numImag = b1 * sinOmega + b2 * sin2Omega

        // Denominator (real and imaginary parts)
        let denReal = a0 + a1 * cosOmega + a2 * cos2Omega
        let denImag = a1 * sinOmega + a2 * sin2Omega

        // Magnitude squared
        let numMagSq = numReal * numReal + numImag * numImag
        let denMagSq = denReal * denReal + denImag * denImag

        // Magnitude in dB
        let magSq = numMagSq / denMagSq
        let magnitudeDB = 10.0 * log10(magSq)

        return Float(magnitudeDB)
    }
}
