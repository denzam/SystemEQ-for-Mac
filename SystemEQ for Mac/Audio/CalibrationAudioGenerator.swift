//
//  CalibrationAudioGenerator.swift
//  SystemEQ for Mac
//
//  Generates calibration test signals:
//  - Pink Noise (full spectrum, equal energy per octave)
//  - Filtered Pink Noise (band-limited for per-frequency testing)
//  - Sweep Tones (frequency sweeps for analysis)
//  - Warble Tones (modulated tones for easier perception)
//

import Accelerate
import AVFoundation
import Foundation

public enum CalibrationSignalType: String, CaseIterable {
    case pinkNoise = "Pink Noise"
    case filteredPinkNoise = "Filtered Pink Noise"
    case sweepTone = "Sweep Tone"
    case warbleTone = "Warble Tone"
    case pureTone = "Pure Tone"

    var icon: String {
        switch self {
        case .pinkNoise:
            "waveform"
        case .filteredPinkNoise:
            "waveform.path"
        case .sweepTone:
            "arrow.right.to.line"
        case .warbleTone:
            "wave.3.right"
        case .pureTone:
            "waveform.path.ecg"
        }
    }

    var description: String {
        switch self {
        case .pinkNoise:
            "Full spectrum noise, equal energy per octave. Best for overall balance."
        case .filteredPinkNoise:
            "Pink noise filtered to specific frequency band. Best for per-band calibration."
        case .sweepTone:
            "Continuous frequency sweep. Good for finding problem frequencies."
        case .warbleTone:
            "Modulated tone. Easier to perceive and judge loudness."
        case .pureTone:
            "Single frequency sine wave. Classic method."
        }
    }
}

public final class CalibrationAudioGenerator {
    // MARK: - Properties

    private let sampleRate: Double = 48000
    private var pinkNoiseGenerator = PinkNoiseGenerator()

    // MARK: - Pink Noise Generation

    /// Generate continuous pink noise buffer
    /// - Parameters:
    ///   - duration: Duration in seconds
    ///   - amplitude: Amplitude (0.0 to 1.0)
    /// - Returns: Stereo audio buffer
    public func generatePinkNoise(duration: TimeInterval, amplitude: Float = 0.3) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(sampleRate * duration)

        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: 2
        ) else { return nil }

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: frameCount
        ) else { return nil }

        buffer.frameLength = frameCount

        // Generate pink noise samples
        let samples = pinkNoiseGenerator.generateSamples(frameCount: Int(frameCount))

        // Copy to stereo buffer
        guard let leftChannel = buffer.floatChannelData?[0],
              let rightChannel = buffer.floatChannelData?[1] else { return nil }

        for i in 0..<Int(frameCount) {
            let sample = samples[i] * amplitude
            leftChannel[i] = sample
            rightChannel[i] = sample
        }

        // Apply fade in/out
        applyFadeInOut(buffer: buffer, fadeDuration: 0.05)

        return buffer
    }

    // MARK: - Filtered Pink Noise (Band-Limited)

    /// Generate pink noise filtered to specific frequency band
    /// - Parameters:
    ///   - centerFrequency: Center frequency in Hz
    ///   - bandwidth: Bandwidth in octaves (default: 1/3 octave)
    ///   - duration: Duration in seconds
    ///   - amplitude: Amplitude (0.0 to 1.0)
    /// - Returns: Filtered stereo audio buffer
    public func generateFilteredPinkNoise(
        centerFrequency: Double,
        bandwidth: Double = 1.0 / 3.0, // 1/3 octave (standard for EQ)
        duration: TimeInterval,
        amplitude: Float = 0.3
    ) -> AVAudioPCMBuffer? {
        // First generate full spectrum pink noise
        guard let pinkBuffer = generatePinkNoise(duration: duration, amplitude: 1.0) else {
            return nil
        }

        // Apply band-pass filter
        let lowFreq = centerFrequency * pow(2.0, -bandwidth / 2.0)
        let highFreq = centerFrequency * pow(2.0, bandwidth / 2.0)

        guard let filtered = applyBandPassFilter(
            buffer: pinkBuffer,
            lowFrequency: lowFreq,
            highFrequency: highFreq
        ) else { return nil }

        // Scale amplitude
        scaleBuffer(filtered, amplitude: amplitude)

        return filtered
    }

    // MARK: - Sweep Tone

    /// Generate logarithmic frequency sweep
    /// - Parameters:
    ///   - startFrequency: Start frequency in Hz
    ///   - endFrequency: End frequency in Hz
    ///   - duration: Duration in seconds
    ///   - amplitude: Amplitude (0.0 to 1.0)
    /// - Returns: Stereo audio buffer
    public func generateSweepTone(
        startFrequency: Double = 20,
        endFrequency: Double = 20000,
        duration: TimeInterval,
        amplitude: Float = 0.3
    ) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(sampleRate * duration)

        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: 2
        ) else { return nil }

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: frameCount
        ) else { return nil }

        buffer.frameLength = frameCount

        guard let leftChannel = buffer.floatChannelData?[0],
              let rightChannel = buffer.floatChannelData?[1] else { return nil }

        // Logarithmic sweep (constant energy per octave)
        let k = pow(endFrequency / startFrequency, 1.0 / duration)

        var phase = 0.0

        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / sampleRate
            let frequency = startFrequency * pow(k, t)

            // Instantaneous phase
            let phaseIncrement = 2.0 * .pi * frequency / sampleRate
            phase += phaseIncrement

            let sample = Float(sin(phase)) * amplitude

            leftChannel[frame] = sample
            rightChannel[frame] = sample
        }

        // Apply fade in/out
        applyFadeInOut(buffer: buffer, fadeDuration: 0.1)

        return buffer
    }

    // MARK: - Warble Tone

    /// Generate warble tone (frequency-modulated sine wave)
    /// Easier to perceive and judge loudness than pure tone
    /// - Parameters:
    ///   - centerFrequency: Center frequency in Hz
    ///   - modulationRate: Modulation rate in Hz (default: 6 Hz)
    ///   - modulationDepth: Modulation depth in semitones (default: 1 semitone)
    ///   - duration: Duration in seconds
    ///   - amplitude: Amplitude (0.0 to 1.0)
    /// - Returns: Stereo audio buffer
    public func generateWarbleTone(
        centerFrequency: Double,
        modulationRate: Double = 6.0,
        modulationDepth: Double = 1.0, // semitones
        duration: TimeInterval,
        amplitude: Float = 0.3
    ) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(sampleRate * duration)

        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: 2
        ) else { return nil }

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: frameCount
        ) else { return nil }

        buffer.frameLength = frameCount

        guard let leftChannel = buffer.floatChannelData?[0],
              let rightChannel = buffer.floatChannelData?[1] else { return nil }

        // Convert semitones to frequency ratio
        let depthRatio = pow(2.0, modulationDepth / 12.0)

        var phase = 0.0

        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / sampleRate

            // Frequency modulation
            let modulation = sin(2.0 * .pi * modulationRate * t)
            let frequency = centerFrequency * pow(depthRatio, modulation)

            // Generate sample
            let phaseIncrement = 2.0 * .pi * frequency / sampleRate
            phase += phaseIncrement

            let sample = Float(sin(phase)) * amplitude

            leftChannel[frame] = sample
            rightChannel[frame] = sample
        }

        // Apply fade in/out
        applyFadeInOut(buffer: buffer, fadeDuration: 0.05)

        return buffer
    }

    // MARK: - Pure Tone (Sine Wave)

    /// Generate pure sine wave tone
    /// - Parameters:
    ///   - frequency: Frequency in Hz
    ///   - duration: Duration in seconds
    ///   - amplitude: Amplitude (0.0 to 1.0)
    /// - Returns: Stereo audio buffer
    public func generatePureTone(
        frequency: Double,
        duration: TimeInterval,
        amplitude: Float = 0.3
    ) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(sampleRate * duration)

        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: 2
        ) else { return nil }

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: frameCount
        ) else { return nil }

        buffer.frameLength = frameCount

        guard let leftChannel = buffer.floatChannelData?[0],
              let rightChannel = buffer.floatChannelData?[1] else { return nil }

        let angularFrequency = 2.0 * .pi * frequency / sampleRate

        for frame in 0..<Int(frameCount) {
            let sample = Float(sin(angularFrequency * Double(frame))) * amplitude
            leftChannel[frame] = sample
            rightChannel[frame] = sample
        }

        // Apply fade in/out
        applyFadeInOut(buffer: buffer, fadeDuration: 0.05)

        return buffer
    }

    // MARK: - DSP Helpers

    /// Apply band-pass filter to buffer using RBJ biquad (constant-skirt gain, peak at 0 dB)
    private func applyBandPassFilter(
        buffer: AVAudioPCMBuffer,
        lowFrequency: Double,
        highFrequency: Double
    ) -> AVAudioPCMBuffer? {
        guard let leftChannel = buffer.floatChannelData?[0] else { return nil }

        let frameCount = Int(buffer.frameLength)

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: buffer.format,
            frameCapacity: buffer.frameCapacity
        ) else { return nil }
        outputBuffer.frameLength = buffer.frameLength

        guard let outLeft = outputBuffer.floatChannelData?[0] else { return nil }

        // RBJ band-pass (constant 0 dB peak): f0 = geometric mean, Q from bandwidth
        let f0 = sqrt(lowFrequency * highFrequency)
        let bw = log2(highFrequency / lowFrequency) // octave bandwidth
        let omega = 2.0 * Double.pi * f0 / sampleRate
        let sinOmega = sin(omega)
        let cosOmega = cos(omega)
        // alpha from bandwidth: alpha = sin(w0)*sinh(ln(2)/2 * bw * w0/sin(w0))
        let alpha = sinOmega * sinh(log(2.0) / 2.0 * bw * omega / sinOmega)

        let b0 = Float(sinOmega / 2.0)
        let b1: Float = 0.0
        let b2 = Float(-sinOmega / 2.0)
        let a0 = Float(1.0 + alpha)
        let a1 = Float(-2.0 * cosOmega)
        let a2 = Float(1.0 - alpha)

        let nb0 = b0 / a0; let nb1 = b1 / a0; let nb2 = b2 / a0
        let na1 = a1 / a0; let na2 = a2 / a0

        var x1: Float = 0, x2: Float = 0, y1: Float = 0, y2: Float = 0

        for i in 0..<frameCount {
            let x0 = leftChannel[i]
            let y0 = nb0 * x0 + nb1 * x1 + nb2 * x2 - na1 * y1 - na2 * y2
            outLeft[i] = y0
            x2 = x1; x1 = x0; y2 = y1; y1 = y0
        }

        if let outRight = outputBuffer.floatChannelData?[1] {
            vDSP_mmov(outLeft, outRight, vDSP_Length(frameCount), 1, 1, 1)
        }

        return outputBuffer
    }

    /// Apply fade in/out to buffer to avoid clicks
    private func applyFadeInOut(buffer: AVAudioPCMBuffer, fadeDuration: TimeInterval) {
        guard let channelData = buffer.floatChannelData else { return }

        let sampleRate = buffer.format.sampleRate
        let fadeSamples = Int(fadeDuration * sampleRate)
        let frameCount = Int(buffer.frameLength)

        for channel in 0..<Int(buffer.format.channelCount) {
            // Fade in
            for i in 0..<min(fadeSamples, frameCount) {
                let gain = Float(i) / Float(fadeSamples)
                channelData[channel][i] *= gain
            }

            // Fade out
            for i in 0..<min(fadeSamples, frameCount) {
                let index = frameCount - 1 - i
                let gain = Float(i) / Float(fadeSamples)
                channelData[channel][index] *= gain
            }
        }
    }

    /// Scale buffer amplitude
    private func scaleBuffer(_ buffer: AVAudioPCMBuffer, amplitude: Float) {
        guard let channelData = buffer.floatChannelData else { return }
        let frameCount = Int(buffer.frameLength)

        for channel in 0..<Int(buffer.format.channelCount) {
            let channelPtr = channelData[channel]
            vDSP_vsmul(channelPtr, 1, [amplitude], channelPtr, 1, vDSP_Length(frameCount))
        }
    }
}
