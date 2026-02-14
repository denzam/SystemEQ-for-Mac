//
//  AudioAnalyzer.swift
//  SystemEQ for Mac
//
//  Professional Audio Analysis Engine for VisualizerEngine v2
//  Provides FFT, beat detection, and advanced audio features
//

import Accelerate
import Foundation
import QuartzCore

// MARK: - Audio Features

struct AudioFeatures {
    // Spectrum data
    var spectrum: [Float] // 64-256 bins
    var smoothedSpectrum: [Float] // Smoothed version

    // Frequency bands
    var subBass: Float // 20-60 Hz
    var bass: Float // 60-250 Hz
    var lowMid: Float // 250-500 Hz
    var mid: Float // 500-2000 Hz
    var highMid: Float // 2000-4000 Hz
    var presence: Float // 4000-6000 Hz
    var brilliance: Float // 6000-20000 Hz

    // Beat detection
    var beatDetected: Bool
    var beatStrength: Float
    var bpm: Float?

    // Peak levels
    var peakLevel: Float
    var rmsLevel: Float

    /// Time
    var timestamp: TimeInterval
}

// MARK: - Audio Analyzer

final class AudioAnalyzer {
    // FFT Configuration
    private let fftSize: Int
    private let fftSetup: FFTSetup
    private let windowSize: Int
    private let hopSize: Int
    private let log2n: vDSP_Length

    // Buffers
    private var inputBuffer: [Float]
    private var windowedBuffer: [Float]
    private var fftMagnitudes: [Float]
    private var previousMagnitudes: [Float]

    // Smoothing
    private var smoothedSpectrum: [Float]
    private let smoothingFactor: Float = 0.75 // 75% old, 25% new

    // Beat Detection
    private var beatHistory: [Float] = []
    private var lastBeatTime: TimeInterval = 0
    private let beatCooldown: TimeInterval = 0.1 // 100ms minimum between beats

    /// Frequency bands cache
    private var cachedBands: (
        subBass: Float,
        bass: Float,
        lowMid: Float,
        mid: Float,
        highMid: Float,
        presence: Float,
        brilliance: Float
    )?

    // MARK: - Initialization

    init(fftSize: Int = 2048, hopSize: Int = 512) {
        self.fftSize = fftSize
        self.hopSize = hopSize
        self.windowSize = fftSize

        // Create FFT setup
        self.log2n = vDSP_Length(log2(Float(fftSize)))
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            fatalError("Failed to create FFT setup")
        }
        self.fftSetup = setup

        // Initialize buffers
        self.inputBuffer = Array(repeating: 0, count: fftSize)
        self.windowedBuffer = Array(repeating: 0, count: fftSize)
        self.fftMagnitudes = Array(repeating: 0, count: fftSize / 2)
        self.previousMagnitudes = Array(repeating: 0, count: fftSize / 2)
        self.smoothedSpectrum = Array(repeating: 0, count: fftSize / 2)
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }

    // MARK: - Analysis

    func analyze(samples: [Float], sampleRate: Float = 44100.0) -> AudioFeatures {
        let timestamp = CACurrentMediaTime()

        // Update input buffer
        updateInputBuffer(samples)

        // Apply window function (Hann window)
        applyHannWindow()

        // Perform FFT
        let spectrum = performFFT()

        // Smooth spectrum
        smoothSpectrum(spectrum)

        // Calculate frequency bands
        let bands = calculateFrequencyBands(spectrum, sampleRate: sampleRate)

        // Detect beats
        let (beatDetected, beatStrength) = detectBeat(bands: bands, timestamp: timestamp)

        // Calculate peak and RMS
        let peakLevel = calculatePeak(samples)
        let rmsLevel = calculateRMS(samples)

        return AudioFeatures(
            spectrum: spectrum,
            smoothedSpectrum: smoothedSpectrum,
            subBass: bands.subBass,
            bass: bands.bass,
            lowMid: bands.lowMid,
            mid: bands.mid,
            highMid: bands.highMid,
            presence: bands.presence,
            brilliance: bands.brilliance,
            beatDetected: beatDetected,
            beatStrength: beatStrength,
            bpm: nil, // TODO: Implement BPM detection
            peakLevel: peakLevel,
            rmsLevel: rmsLevel,
            timestamp: timestamp
        )
    }

    // MARK: - Private Methods

    private func updateInputBuffer(_ samples: [Float]) {
        // Shift old samples
        let shift = min(samples.count, inputBuffer.count)
        inputBuffer.removeFirst(shift)

        // Add new samples
        let samplesToAdd = samples.suffix(shift)
        inputBuffer.append(contentsOf: samplesToAdd)

        // Pad if needed
        while inputBuffer.count < fftSize {
            inputBuffer.append(0)
        }
    }

    private func applyHannWindow() {
        // Hann window: 0.5 * (1 - cos(2π * n / N))
        for i in 0..<windowSize {
            let window = 0.5 * (1.0 - cos(2.0 * .pi * Float(i) / Float(windowSize)))
            windowedBuffer[i] = inputBuffer[i] * window
        }
    }

    private func performFFT() -> [Float] {
        // Split complex buffer
        var realPart = [Float](repeating: 0, count: fftSize / 2)
        var imagPart = [Float](repeating: 0, count: fftSize / 2)

        // Deinterleave
        for i in 0..<fftSize / 2 {
            realPart[i] = windowedBuffer[i * 2]
            imagPart[i] = windowedBuffer[i * 2 + 1]
        }

        // Perform FFT
        realPart.withUnsafeMutableBufferPointer { realPtr in
            imagPart.withUnsafeMutableBufferPointer { imagPtr in
                guard let realBase = realPtr.baseAddress, let imagBase = imagPtr.baseAddress else { return }
                var splitComplex = DSPSplitComplex(realp: realBase, imagp: imagBase)
                vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))
            }
        }

        // Calculate magnitudes
        var magnitudes = [Float](repeating: 0, count: fftSize / 2)
        realPart.withUnsafeMutableBufferPointer { realPtr in
            imagPart.withUnsafeMutableBufferPointer { imagPtr in
                guard let realBase = realPtr.baseAddress, let imagBase = imagPtr.baseAddress else { return }
                var splitComplex = DSPSplitComplex(realp: realBase, imagp: imagBase)
                vDSP_zvabs(&splitComplex, 1, &magnitudes, 1, vDSP_Length(fftSize / 2))
            }
        }

        // Normalize
        var scale = Float(2.0 / Float(fftSize))
        vDSP_vsmul(magnitudes, 1, &scale, &magnitudes, 1, vDSP_Length(fftSize / 2))

        return magnitudes
    }

    private func smoothSpectrum(_ spectrum: [Float]) {
        // Exponential smoothing: smoothed = α * new + (1 - α) * old
        for i in 0..<min(spectrum.count, smoothedSpectrum.count) {
            smoothedSpectrum[i] = smoothingFactor * smoothedSpectrum[i] +
                (1.0 - smoothingFactor) * spectrum[i]
        }
    }

    private func calculateFrequencyBands(
        _ spectrum: [Float],
        sampleRate: Float
    ) -> (
        subBass: Float,
        bass: Float,
        lowMid: Float,
        mid: Float,
        highMid: Float,
        presence: Float,
        brilliance: Float
    ) {
        let binWidth = sampleRate / Float(fftSize)

        func averageBand(startFreq: Float, endFreq: Float) -> Float {
            let startBin = Int(startFreq / binWidth)
            let endBin = Int(endFreq / binWidth)
            let range = startBin..<min(endBin, spectrum.count)

            guard !range.isEmpty else { return 0 }

            let sum = spectrum[range].reduce(0, +)
            return sum / Float(range.count)
        }

        return (
            subBass: averageBand(startFreq: 20, endFreq: 60),
            bass: averageBand(startFreq: 60, endFreq: 250),
            lowMid: averageBand(startFreq: 250, endFreq: 500),
            mid: averageBand(startFreq: 500, endFreq: 2000),
            highMid: averageBand(startFreq: 2000, endFreq: 4000),
            presence: averageBand(startFreq: 4000, endFreq: 6000),
            brilliance: averageBand(startFreq: 6000, endFreq: 20000)
        )
    }

    private func detectBeat(
        bands: (
            subBass: Float,
            bass: Float,
            lowMid: Float,
            mid: Float,
            highMid: Float,
            presence: Float,
            brilliance: Float
        ),
        timestamp: TimeInterval
    ) -> (detected: Bool, strength: Float) {
        // Focus on bass and low-mid for beat detection
        let energy = bands.bass * 2.0 + bands.lowMid * 1.5 + bands.subBass * 1.0

        // Add to history
        beatHistory.append(energy)
        if beatHistory.count > 43 { // ~1 second at 43 FPS
            beatHistory.removeFirst()
        }

        // Calculate average energy
        let avgEnergy = beatHistory.reduce(0, +) / Float(beatHistory.count)

        // Beat threshold (1.5x average)
        let threshold = avgEnergy * 1.5

        // Check cooldown
        let timeSinceLastBeat = timestamp - lastBeatTime
        guard timeSinceLastBeat > beatCooldown else {
            return (false, 0)
        }

        // Detect beat
        if energy > threshold, energy > 0.1 {
            lastBeatTime = timestamp
            let strength = min((energy - threshold) / threshold, 1.0)
            return (true, strength)
        }

        return (false, 0)
    }

    private func calculatePeak(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var peak: Float = 0
        vDSP_maxv(samples, 1, &peak, vDSP_Length(samples.count))
        return peak
    }

    private func calculateRMS(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))
        return rms
    }
}
