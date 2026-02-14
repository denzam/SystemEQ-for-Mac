//
//  PinkNoiseGenerator.swift
//  SystemEQ for Mac
//
//  Pink Noise Generator using Voss-McCartney algorithm
//  Based on research from Paul Kellet and James McCartney
//

import Accelerate
import Foundation

/// High-quality Pink Noise generator using Voss-McCartney algorithm
/// Pink noise has equal energy per octave (-3dB/octave rolloff)
/// Perfect for audio calibration and hearing tests
public final class PinkNoiseGenerator {
    // MARK: - Voss-McCartney State

    /// Number of octave generators (determines quality)
    private let numGenerators: Int = 16

    /// State for each octave generator
    private var generators: [Float]

    /// Counter for determining which generator to update
    private var counter: UInt32 = 0

    /// Running sum of all generators
    private var runningSum: Float = 0.0

    /// White noise amplitude (top octave)
    private let whiteAmplitude: Float = 0.5

    /// Pink noise amplitude scaling
    private let pinkAmplitude: Float = 0.1

    // MARK: - Initialization

    public init() {
        // Initialize all generators with random values
        self.generators = (0..<numGenerators).map { _ in
            Float.random(in: -1.0...1.0)
        }

        // Calculate initial sum
        self.runningSum = generators.reduce(0, +)
    }

    // MARK: - Generation Methods

    /// Generate next pink noise sample
    /// - Returns: Pink noise sample in range [-1.0, 1.0]
    public func nextSample() -> Float {
        // Add white noise for top octave (fills in high frequencies)
        let white = Float.random(in: -1.0...1.0) * whiteAmplitude

        // Determine which generator to update by counting trailing zeros
        let index = counter.trailingZeroBitCount

        if index < numGenerators {
            // Subtract old value
            runningSum -= generators[index]

            // Generate new random value
            let newValue = Float.random(in: -1.0...1.0)
            generators[index] = newValue

            // Add new value
            runningSum += newValue
        }

        // Increment counter
        counter = counter &+ 1

        // Combine pink and white noise
        let pink = (runningSum + white) * pinkAmplitude

        // Clamp to [-1.0, 1.0]
        return max(-1.0, min(1.0, pink))
    }

    /// Generate buffer of pink noise samples
    /// - Parameter frameCount: Number of samples to generate
    /// - Returns: Array of pink noise samples
    public func generateSamples(frameCount: Int) -> [Float] {
        var samples = [Float](repeating: 0.0, count: frameCount)

        for i in 0..<frameCount {
            samples[i] = nextSample()
        }

        return samples
    }

    /// Reset generator state
    public func reset() {
        counter = 0
        generators = (0..<numGenerators).map { _ in
            Float.random(in: -1.0...1.0)
        }
        runningSum = generators.reduce(0, +)
    }
}

/// Alternative: Paul Kellet's "Instrumentation Grade" Pink Noise Filter
/// This filters white noise through carefully tuned poles
/// Accuracy: ±0.05dB from 20Hz to 20kHz
public final class PaulKelletPinkFilter {
    // Filter state variables
    private var b0: Float = 0.0
    private var b1: Float = 0.0
    private var b2: Float = 0.0
    private var b3: Float = 0.0
    private var b4: Float = 0.0
    private var b5: Float = 0.0
    private var b6: Float = 0.0

    public init() {}

    /// Process white noise sample through pink filter
    /// - Parameter white: White noise input sample
    /// - Returns: Pink noise output sample
    public func process(white: Float) -> Float {
        b0 = 0.99886 * b0 + white * 0.0555179
        b1 = 0.99332 * b1 + white * 0.0750759
        b2 = 0.96900 * b2 + white * 0.1538520
        b3 = 0.86650 * b3 + white * 0.3104856
        b4 = 0.55000 * b4 + white * 0.5329522
        b5 = -0.7616 * b5 - white * 0.0168980

        let pink = b0 + b1 + b2 + b3 + b4 + b5 + b6 + white * 0.5362
        b6 = white * 0.115926

        return pink * 0.11 // Scale to [-1.0, 1.0]
    }

    /// Generate buffer of pink noise samples
    /// - Parameter frameCount: Number of samples to generate
    /// - Returns: Array of pink noise samples
    public func generateSamples(frameCount: Int) -> [Float] {
        var samples = [Float](repeating: 0.0, count: frameCount)

        for i in 0..<frameCount {
            let white = Float.random(in: -1.0...1.0)
            samples[i] = process(white: white)
        }

        return samples
    }

    /// Reset filter state
    public func reset() {
        b0 = 0.0
        b1 = 0.0
        b2 = 0.0
        b3 = 0.0
        b4 = 0.0
        b5 = 0.0
        b6 = 0.0
    }
}

/// Economy version of Paul Kellet's filter
/// Accuracy: ±0.5dB (good enough for most applications)
/// Faster than instrumentation grade
public final class PaulKelletEconomyFilter {
    private var b0: Float = 0.0
    private var b1: Float = 0.0
    private var b2: Float = 0.0

    public init() {}

    public func process(white: Float) -> Float {
        b0 = 0.99765 * b0 + white * 0.0990460
        b1 = 0.96300 * b1 + white * 0.2965164
        b2 = 0.57000 * b2 + white * 1.0526913

        return (b0 + b1 + b2 + white * 0.1848) * 0.11
    }

    public func generateSamples(frameCount: Int) -> [Float] {
        var samples = [Float](repeating: 0.0, count: frameCount)

        for i in 0..<frameCount {
            let white = Float.random(in: -1.0...1.0)
            samples[i] = process(white: white)
        }

        return samples
    }

    public func reset() {
        b0 = 0.0
        b1 = 0.0
        b2 = 0.0
    }
}
