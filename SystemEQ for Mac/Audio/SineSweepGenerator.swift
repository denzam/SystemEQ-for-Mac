//
//  SineSweepGenerator.swift
//  SystemEQ for Mac
//
//  Sine Sweep generator for room resonance detection
//

import Accelerate
import AVFoundation
import Combine
import Foundation

/// Sine Sweep generator for finding room resonances
public class SineSweepGenerator: ObservableObject {
    // MARK: - Published Properties

    @Published public var isPlaying: Bool = false
    @Published public var currentFrequency: Double = 1000.0
    @Published public var sweepSpeed: SweepSpeed = .medium

    // MARK: - Sweep Speed

    public enum SweepSpeed: String, CaseIterable {
        case slow = "Slow (30s)"
        case medium = "Medium (15s)"
        case fast = "Fast (8s)"

        var duration: TimeInterval {
            switch self {
            case .slow: 30.0
            case .medium: 15.0
            case .fast: 8.0
            }
        }

        var logRate: Double {
            switch self {
            case .slow: 3.0
            case .medium: 4.0
            case .fast: 5.0
            }
        }
    }

    // MARK: - Private Properties

    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var timer: Timer?

    // MARK: - Public Methods

    public func startSweep(from startFreq: Double = 20.0, to endFreq: Double = 20000.0) {
        stopSweep()

        setupAudioEngine()
        guard let playerNode else { return }

        let duration = sweepSpeed.duration
        let sampleRate = 48000.0
        let frameCount = AVAudioFrameCount(duration * sampleRate)

        // Generate sine sweep buffer
        let buffer = generateSineSweep(
            startFreq: startFreq,
            endFreq: endFreq,
            duration: duration,
            sampleRate: sampleRate,
            frameCount: frameCount
        )

        playerNode.scheduleBuffer(buffer, at: nil, options: .loops) {
            DispatchQueue.main.async {
                self.stopSweep()
            }
        }

        try? audioEngine?.start()
        playerNode.play()

        isPlaying = true

        // Start frequency tracking timer
        startFrequencyTracking(startFreq: startFreq, endFreq: endFreq, duration: duration)
    }

    public func stopSweep() {
        playerNode?.stop()
        audioEngine?.stop()
        timer?.invalidate()
        timer = nil

        isPlaying = false
        currentFrequency = 1000.0
    }

    public func playFixedFrequency(_ frequency: Double, duration: TimeInterval = 2.0) {
        stopSweep()

        setupAudioEngine()
        guard let playerNode else { return }

        let sampleRate = 48000.0
        let frameCount = AVAudioFrameCount(duration * sampleRate)

        let buffer = generateFixedTone(
            frequency: frequency,
            duration: duration,
            sampleRate: sampleRate,
            frameCount: frameCount
        )

        playerNode.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)

        try? audioEngine?.start()
        playerNode.play()

        isPlaying = true
        currentFrequency = frequency

        // Auto-stop after duration
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            self.stopSweep()
        }
    }

    /// Play continuous tone (loops until stopped)
    public func playContinuousTone(_ frequency: Double) {
        stopSweep()

        setupAudioEngine()
        guard let playerNode else { return }

        let sampleRate = 48000.0
        let duration: TimeInterval = 2.0 // Buffer length (will loop)
        let frameCount = AVAudioFrameCount(duration * sampleRate)

        let buffer = generateContinuousTone(
            frequency: frequency,
            sampleRate: sampleRate,
            frameCount: frameCount
        )

        // Schedule with looping
        playerNode.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)

        try? audioEngine?.start()
        playerNode.play()

        isPlaying = true
        currentFrequency = frequency
    }

    /// Update frequency of currently playing continuous tone
    public func updateContinuousFrequency(_ frequency: Double) {
        guard isPlaying else {
            playContinuousTone(frequency)
            return
        }

        currentFrequency = frequency

        // Restart with new frequency
        playContinuousTone(frequency)
    }

    // MARK: - Private Methods

    private var outputFormat: AVAudioFormat?

    private func setupAudioEngine() {
        audioEngine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()

        guard let audioEngine,
              let playerNode else { return }

        // Get the output format from the output node
        let outputNode = audioEngine.outputNode
        outputFormat = outputNode.outputFormat(forBus: 0)

        audioEngine.attach(playerNode)

        // Connect with the correct format
        if let format = outputFormat {
            audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: format)
        } else {
            audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: nil)
        }
    }

    private func generateSineSweep(
        startFreq: Double,
        endFreq: Double,
        duration: TimeInterval,
        sampleRate: Double,
        frameCount: AVAudioFrameCount
    ) -> AVAudioPCMBuffer {
        // Use the output format's channel count (typically stereo)
        let channelCount = outputFormat?.channelCount ?? 2
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channelCount),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return AVAudioPCMBuffer()
        }
        buffer.frameLength = frameCount

        guard let channelData = buffer.floatChannelData else { return buffer }

        // Logarithmic sweep: f(t) = f_start * (f_end/f_start)^(t/T)
        let freqRatio = endFreq / startFreq
        let logFreqRatio = log(freqRatio)

        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / sampleRate
            let phase = 2.0 * Double.pi * startFreq * duration * (pow(freqRatio, t / duration) - 1.0) / logFreqRatio

            // Apply slight fade-in/fade-out to avoid clicks
            let fadeSamples = Int(0.01 * sampleRate) // 10ms fade
            var amplitude = 0.3

            if frame < fadeSamples {
                amplitude *= Double(frame) / Double(fadeSamples)
            } else if frame > Int(frameCount) - fadeSamples {
                amplitude *= Double(Int(frameCount) - frame) / Double(fadeSamples)
            }

            let sample = Float(amplitude * sin(phase))

            // Write to all channels (stereo: same signal on L and R)
            for channel in 0..<Int(channelCount) {
                channelData[channel][frame] = sample
            }
        }

        return buffer
    }

    private func generateFixedTone(
        frequency: Double,
        duration: TimeInterval,
        sampleRate: Double,
        frameCount: AVAudioFrameCount
    ) -> AVAudioPCMBuffer {
        // Use the output format's channel count (typically stereo)
        let channelCount = outputFormat?.channelCount ?? 2
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channelCount),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return AVAudioPCMBuffer()
        }
        buffer.frameLength = frameCount

        guard let channelData = buffer.floatChannelData else { return buffer }

        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / sampleRate
            let phase = 2.0 * Double.pi * frequency * t

            // Apply fade-in/fade-out
            let fadeSamples = Int(0.01 * sampleRate)
            var amplitude = 0.3

            if frame < fadeSamples {
                amplitude *= Double(frame) / Double(fadeSamples)
            } else if frame > Int(frameCount) - fadeSamples {
                amplitude *= Double(Int(frameCount) - frame) / Double(fadeSamples)
            }

            let sample = Float(amplitude * sin(phase))

            // Write to all channels (stereo: same signal on L and R)
            for channel in 0..<Int(channelCount) {
                channelData[channel][frame] = sample
            }
        }

        return buffer
    }

    private func generateContinuousTone(
        frequency: Double,
        sampleRate: Double,
        frameCount: AVAudioFrameCount
    ) -> AVAudioPCMBuffer {
        // Use the output format's channel count (typically stereo)
        let channelCount = outputFormat?.channelCount ?? 2
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channelCount),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return AVAudioPCMBuffer()
        }
        buffer.frameLength = frameCount

        guard let channelData = buffer.floatChannelData else { return buffer }

        // Calculate phase increment for seamless looping
        // Ensure buffer contains exact number of cycles for click-free looping
        let cyclesPerBuffer = round(frequency * Double(frameCount) / sampleRate)
        let adjustedFrequency = cyclesPerBuffer * sampleRate / Double(frameCount)

        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / sampleRate
            let phase = 2.0 * Double.pi * adjustedFrequency * t

            let amplitude = 0.3
            let sample = Float(amplitude * sin(phase))

            // Write to all channels (stereo: same signal on L and R)
            for channel in 0..<Int(channelCount) {
                channelData[channel][frame] = sample
            }
        }

        return buffer
    }

    private func startFrequencyTracking(startFreq: Double, endFreq: Double, duration: TimeInterval) {
        let startTime = Date()
        let updateInterval: TimeInterval = 0.1 // Update 10 times per second

        timer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { _ in
            let elapsed = Date().timeIntervalSince(startTime)
            let progress = min(elapsed / duration, 1.0)

            // Logarithmic frequency calculation
            let freqRatio = endFreq / startFreq
            self.currentFrequency = startFreq * pow(freqRatio, progress)

            if progress >= 1.0 {
                self.timer?.invalidate()
                self.timer = nil
            }
        }
    }
}

// MARK: - Resonance Detection Helper

public struct ResonancePoint: Identifiable {
    public let id = UUID()
    public let frequency: Double
    public let severity: Severity // 1-10 scale
    public let description: String

    public enum Severity {
        case mild
        case moderate
        case severe
        case extreme

        var rating: Int {
            switch self {
            case .mild: 3
            case .moderate: 5
            case .severe: 7
            case .extreme: 10
            }
        }

        var color: String {
            switch self {
            case .mild: "yellow"
            case .moderate: "orange"
            case .severe: "red"
            case .extreme: "purple"
            }
        }
    }

    public init(frequency: Double, severity: Severity, description: String) {
        self.frequency = frequency
        self.severity = severity
        self.description = description
    }
}

/// Helper for room resonance detection guidance
public class ResonanceDetector {
    /// Common room resonance frequencies and their descriptions
    public static let commonResonances: [ResonancePoint] = [
        ResonancePoint(frequency: 40, severity: .moderate, description: "Room mode - standing wave"),
        ResonancePoint(frequency: 63, severity: .moderate, description: "Bass buildup in corners"),
        ResonancePoint(frequency: 80, severity: .mild, description: "Low-mid mud"),
        ResonancePoint(frequency: 100, severity: .moderate, description: "Room length mode"),
        ResonancePoint(frequency: 125, severity: .mild, description: "Low-mid boxiness"),
        ResonancePoint(frequency: 160, severity: .mild, description: "Lower vocal range"),
        ResonancePoint(frequency: 200, severity: .moderate, description: "Low-mid mud"),
        ResonancePoint(frequency: 250, severity: .mild, description: "Lower vocal presence"),
        ResonancePoint(frequency: 315, severity: .mild, description: "Vocal body"),
        ResonancePoint(frequency: 400, severity: .moderate, description: "Cardioid pattern null"),
        ResonancePoint(frequency: 500, severity: .mild, description: "Lower vocal clarity"),
        ResonancePoint(frequency: 630, severity: .moderate, description: "Nasal range"),
        ResonancePoint(frequency: 800, severity: .mild, description: "Upper vocal body"),
        ResonancePoint(frequency: 1000, severity: .mild, description: "Vocal presence"),
        ResonancePoint(frequency: 1250, severity: .mild, description: "Vocal intelligibility"),
        ResonancePoint(frequency: 1600, severity: .moderate, description: "Upper vocal intelligibility"),
        ResonancePoint(frequency: 2000, severity: .mild, description: "Speech clarity"),
        ResonancePoint(frequency: 2500, severity: .moderate, description: "Presence boost"),
        ResonancePoint(frequency: 3150, severity: .moderate, description: "Intelligibility peak"),
        ResonancePoint(frequency: 4000, severity: .moderate, description: "Sibilance range"),
        ResonancePoint(frequency: 5000, severity: .mild, description: "Air and brilliance"),
        ResonancePoint(frequency: 6300, severity: .moderate, description: "Upper air"),
        ResonancePoint(frequency: 8000, severity: .mild, description: "Sparkle and detail"),
        ResonancePoint(frequency: 10000, severity: .mild, description: "Upper air"),
        ResonancePoint(frequency: 12500, severity: .mild, description: "Brilliance"),
        ResonancePoint(frequency: 16000, severity: .mild, description: "Air and sparkle"),
        ResonancePoint(frequency: 20000, severity: .mild, description: "Upper hearing limit")
    ]

    /// Get notch filter recommendation for a resonance
    public static func getNotchFilterRecommendation(
        for frequency: Double,
        severity: ResonancePoint.Severity
    ) -> NotchFilterConfig {
        let gain: Float
        let q: Float

        switch severity {
        case .mild:
            gain = -2.0
            q = 4.0
        case .moderate:
            gain = -4.0
            q = 6.0
        case .severe:
            gain = -6.0
            q = 8.0
        case .extreme:
            gain = -8.0
            q = 10.0
        }

        return NotchFilterConfig(
            frequency: frequency,
            gain: gain,
            q: q,
            description: "Notch filter for \(Int(frequency)) Hz resonance"
        )
    }
}

/// Notch filter configuration for resonance suppression
public struct NotchFilterConfig: Identifiable {
    public let id = UUID()
    public let frequency: Double
    public let gain: Float
    public let q: Float
    public let description: String

    public init(frequency: Double, gain: Float, q: Float, description: String) {
        self.frequency = frequency
        self.gain = gain
        self.q = q
        self.description = description
    }
}
