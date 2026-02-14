//
//  CalibrationEngine.swift
//  SystemEQ for Mac
//
//  Calibration Engine - Equal Loudness (Neutralizer-style) + Room Correction
//

import Accelerate
import AVFoundation
import Combine
import Foundation

/// Calibration profile for equal loudness calibration or room correction
public struct CalibrationProfile: Codable, Identifiable, Hashable {
    public let id: UUID
    public var name: String
    public var createdAt: Date
    public var type: CalibrationType

    /// Frequency adjustments (31 bands)
    public var bands: [Float] // dB adjustments per band

    /// Metadata
    public var notes: String

    public init(
        id: UUID = UUID(),
        name: String,
        type: CalibrationType,
        bands: [Float] = Array(repeating: 0.0, count: 31),
        notes: String = ""
    ) {
        self.id = id
        self.name = name
        self.createdAt = Date()
        self.type = type
        self.bands = bands
        self.notes = notes
    }
}

public enum CalibrationType: String, Codable, CaseIterable {
    case equalLoudness = "Equal Loudness"
    case roomCorrection = "Room Correction"
    case custom = "Custom"
}

/// Calibration mode - determines whether to disable EQ during calibration
public enum CalibrationMode: String, CaseIterable {
    case clean = "Clean Calibration"
    case combined = "Combined Calibration"

    var description: String {
        switch self {
        case .clean:
            "Calibrate pure speakers/headphones (EQ will be disabled)"
        case .combined:
            "Calibrate with current EQ preset active"
        }
    }

    var icon: String {
        switch self {
        case .clean:
            "waveform.path"
        case .combined:
            "waveform.path.badge.plus"
        }
    }
}

/// Calibration Engine - manages equal loudness calibration and profiles
public final class CalibrationEngine: ObservableObject {
    public static let shared = CalibrationEngine()

    // MARK: - Published Properties

    @Published public var profiles: [CalibrationProfile] = []
    @Published public var activeProfile: CalibrationProfile?
    @Published public var isTestTonePlaying: Bool = false
    @Published public var currentTestFrequency: Double = 1000.0

    // MARK: - Equal Loudness Properties

    @Published public var referenceFrequency: Double = 1000.0
    @Published public var referenceLevel: Float = -20.0 // dB
    @Published public var isReferenceSet: Bool = false
    @Published public var isPlayingReference: Bool = false
    @Published public var comparisonMode: Bool = false // Alternating reference/test
    @Published public var currentTestLevel: Float = -20.0 // Current test level for comparison

    // MARK: - Calibration Mode State

    private var savedEQEnabled: Bool = false
    private var isCalibrating: Bool = false
    private var comparisonWorkItem: DispatchWorkItem?

    // MARK: - Test Tone Generator

    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var testToneBuffer: AVAudioPCMBuffer?
    private var isAudioEngineSetup: Bool = false

    // MARK: - Calibration Signal Type

    @Published public var useFilteredNoise: Bool = true // true = filtered pink noise, false = pure tone
    @Published public var isPlayingLoop: Bool = false // For continuous test tone playback

    // MARK: - Standard Frequencies (31-band)

    public let standardFrequencies: [Double] = [
        20, 25, 31.5, 40, 50, 63, 80, 100, 125, 160,
        200, 250, 315, 400, 500, 630, 800, 1000, 1250, 1600,
        2000, 2500, 3150, 4000, 5000, 6300, 8000, 10000, 12500, 16000, 20000
    ]

    // MARK: - Initialization

    private init() {
        loadProfiles()
        // ⚡ OPTIMIZATION: Lazy initialization - setup audio engine only when needed
        // setupAudioEngine() - moved to ensureAudioEngineSetup()
    }

    // MARK: - Audio Engine Setup

    /// ⚡ OPTIMIZATION: Lazy setup - only initialize when first needed
    private func ensureAudioEngineSetup() {
        guard !isAudioEngineSetup else { return }

        audioEngine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()

        guard let engine = audioEngine, let player = playerNode else { return }

        engine.attach(player)

        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: 48000,
            channels: 2
        ) else { return }

        engine.connect(player, to: engine.mainMixerNode, format: format)

        do {
            try engine.start()
            isAudioEngineSetup = true
            dlog("✅ CalibrationEngine: Audio engine started (lazy init)", category: .calibration)
        } catch {
            dlog("❌ CalibrationEngine: Failed to start audio engine: \(error)", category: .calibration)
        }
    }

    /// ⚡ OPTIMIZATION: Stop audio engine when not in use to save CPU
    private func stopAudioEngineIfNeeded() {
        guard isAudioEngineSetup else { return }
        guard !isTestTonePlaying, !isPlayingReference, !isPlayingLoop, !comparisonMode else { return }

        audioEngine?.stop()
        isAudioEngineSetup = false
        dlog("💤 CalibrationEngine: Audio engine stopped (not in use)", category: .calibration)
    }

    // MARK: - Test Tone Generation

    /// Play calibration signal (pink noise or tone) at specific frequency
    public func playCalibrationSignal(
        frequency: Double,
        duration: TimeInterval = 2.0,
        amplitude: Float = 0.3,
        isReference: Bool = false
    ) {
        if useFilteredNoise {
            playFilteredPinkNoise(
                frequency: frequency,
                duration: duration,
                amplitude: amplitude,
                isReference: isReference
            )
        } else {
            playTestTone(frequency: frequency, duration: duration, amplitude: amplitude, isReference: isReference)
        }
    }

    /// Play test tone at specific frequency
    public func playTestTone(
        frequency: Double,
        duration: TimeInterval = 2.0,
        amplitude: Float = 0.3,
        isReference: Bool = false
    ) {
        ensureAudioEngineSetup()
        guard let player = playerNode else { return }

        currentTestFrequency = frequency

        let sampleRate: Double = 48000
        let frameCount = AVAudioFrameCount(sampleRate * duration)

        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: 2
        ) else { return }

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: frameCount
        ) else { return }

        buffer.frameLength = frameCount

        // Generate sine wave
        let angularFrequency = 2.0 * .pi * frequency / sampleRate

        for frame in 0..<Int(frameCount) {
            let sample = Float(sin(angularFrequency * Double(frame))) * amplitude

            // Stereo
            buffer.floatChannelData?[0][frame] = sample
            buffer.floatChannelData?[1][frame] = sample
        }

        // Apply fade in/out to avoid clicks
        applyFadeInOut(buffer: buffer, fadeDuration: 0.05)

        testToneBuffer = buffer

        player.stop()
        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: { [weak self] in
            DispatchQueue.main.async {
                self?.isTestTonePlaying = false
                if isReference {
                    self?.isPlayingReference = false
                }
            }
        })

        player.play()
        isTestTonePlaying = true

        dlog("🔊 Playing test tone: \(Int(frequency)) Hz", category: .calibration)
    }

    /// Play test tone in continuous loop (for real-time adjustment)
    public func playTestToneLoop(frequency: Double, amplitude: Float = 0.3) {
        ensureAudioEngineSetup()
        guard let player = playerNode else { return }

        currentTestFrequency = frequency

        let sampleRate: Double = 48000
        let duration: TimeInterval = 2.0
        let frameCount = AVAudioFrameCount(sampleRate * duration)

        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: 2
        ) else { return }

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: frameCount
        ) else { return }

        buffer.frameLength = frameCount

        // Generate sine wave
        let angularFrequency = 2.0 * .pi * frequency / sampleRate

        for frame in 0..<Int(frameCount) {
            let sample = Float(sin(angularFrequency * Double(frame))) * amplitude

            // Stereo
            buffer.floatChannelData?[0][frame] = sample
            buffer.floatChannelData?[1][frame] = sample
        }

        // Apply fade in/out to avoid clicks
        applyFadeInOut(buffer: buffer, fadeDuration: 0.05)

        testToneBuffer = buffer

        player.stop()

        // Schedule buffer with looping
        player.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)

        player.play()
        isTestTonePlaying = true
        isPlayingLoop = true

        dlog("🔊 Playing test tone loop: \(Int(frequency)) Hz", category: .calibration)
    }

    /// Update amplitude of currently playing loop
    public func updateLoopAmplitude(_ newAmplitude: Float) {
        ensureAudioEngineSetup()
        guard isPlayingLoop, let player = playerNode else { return }

        // Regenerate buffer with new amplitude
        let sampleRate: Double = 48000
        let duration: TimeInterval = 2.0
        let frameCount = AVAudioFrameCount(sampleRate * duration)

        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: 2
        ) else { return }

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: frameCount
        ) else { return }

        buffer.frameLength = frameCount

        // Generate sine wave with new amplitude
        let angularFrequency = 2.0 * .pi * currentTestFrequency / sampleRate

        for frame in 0..<Int(frameCount) {
            let sample = Float(sin(angularFrequency * Double(frame))) * newAmplitude

            // Stereo
            buffer.floatChannelData?[0][frame] = sample
            buffer.floatChannelData?[1][frame] = sample
        }

        // Apply fade in/out to avoid clicks
        applyFadeInOut(buffer: buffer, fadeDuration: 0.05)

        testToneBuffer = buffer

        // Schedule new buffer (will take effect after current buffer finishes)
        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
    }

    /// Update amplitude for filtered pink noise loop
    public func updatePinkNoiseLoopAmplitude(_ newAmplitude: Float) {
        ensureAudioEngineSetup()
        guard isPlayingLoop, let player = playerNode else { return }

        let duration: TimeInterval = 2.0

        // Generate pink noise buffer
        guard let pinkBuffer = generatePinkNoiseBuffer(duration: duration) else { return }

        // Apply band-pass filter around target frequency
        guard let filtered = applyBandPassFilterToBuffer(
            buffer: pinkBuffer,
            centerFrequency: currentTestFrequency,
            bandwidth: 1.0 / 3.0
        ) else { return }

        // Scale amplitude
        scaleBufferAmplitude(filtered, amplitude: newAmplitude)

        testToneBuffer = filtered

        // Schedule new buffer
        player.scheduleBuffer(filtered, at: nil, options: [], completionHandler: nil)
    }

    /// Play filtered pink noise at specific frequency band
    public func playFilteredPinkNoise(
        frequency: Double,
        duration: TimeInterval = 2.0,
        amplitude: Float = 0.3,
        isReference: Bool = false
    ) {
        ensureAudioEngineSetup()
        guard let player = playerNode else { return }

        currentTestFrequency = frequency

        // Generate pink noise buffer
        guard let pinkBuffer = generatePinkNoiseBuffer(duration: duration) else { return }

        // Apply band-pass filter around target frequency
        guard let filtered = applyBandPassFilterToBuffer(
            buffer: pinkBuffer,
            centerFrequency: frequency,
            bandwidth: 1.0 / 3.0 // 1/3 octave
        ) else { return }

        // Scale amplitude
        scaleBufferAmplitude(filtered, amplitude: amplitude)

        testToneBuffer = filtered

        player.stop()
        player.scheduleBuffer(filtered, at: nil, options: [], completionHandler: { [weak self] in
            DispatchQueue.main.async {
                self?.isTestTonePlaying = false
                if isReference {
                    self?.isPlayingReference = false
                }
            }
        })

        player.play()
        isTestTonePlaying = true

        dlog("🔊 Playing filtered pink noise: \(Int(frequency)) Hz", category: .calibration)
    }

    /// Generate pink noise buffer using Voss-McCartney algorithm
    private func generatePinkNoiseBuffer(duration: TimeInterval) -> AVAudioPCMBuffer? {
        let sampleRate: Double = 48000
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

        // Simple pink noise generation (Voss-McCartney inspired)
        var generators: [Float] = (0..<16).map { _ in Float.random(in: -1.0...1.0) }
        var counter: UInt32 = 0
        var runningSum = generators.reduce(0, +)

        for frame in 0..<Int(frameCount) {
            // White noise for top octave
            let white = Float.random(in: -1.0...1.0) * 0.5

            // Update one generator based on trailing zeros
            let index = counter.trailingZeroBitCount
            if index < 16 {
                runningSum -= generators[index]
                let newValue = Float.random(in: -1.0...1.0)
                generators[index] = newValue
                runningSum += newValue
            }

            counter = counter &+ 1

            // Combine pink and white
            let pink = (runningSum + white) * 0.1
            let sample = max(-1.0, min(1.0, pink))

            // Stereo
            buffer.floatChannelData?[0][frame] = sample
            buffer.floatChannelData?[1][frame] = sample
        }

        return buffer
    }

    /// Apply band-pass filter to isolate frequency band
    private func applyBandPassFilterToBuffer(
        buffer: AVAudioPCMBuffer,
        centerFrequency: Double,
        bandwidth: Double
    ) -> AVAudioPCMBuffer? {
        guard let inputLeft = buffer.floatChannelData?[0] else { return nil }
        let frameCount = Int(buffer.frameLength)

        // Create output buffer
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: buffer.format,
            frameCapacity: buffer.frameCapacity
        ) else { return nil }

        outputBuffer.frameLength = buffer.frameLength

        guard let outLeft = outputBuffer.floatChannelData?[0],
              let outRight = outputBuffer.floatChannelData?[1] else { return nil }

        // Calculate filter frequencies
        let lowFreq = centerFrequency * pow(2.0, -bandwidth / 2.0)
        let highFreq = centerFrequency * pow(2.0, bandwidth / 2.0)

        // Simple high-pass filter
        let hpAlpha = Float(1.0 / (1.0 + 2.0 * .pi * lowFreq / 48000))
        var hpPrevIn: Float = 0.0
        var hpPrevOut: Float = 0.0

        for i in 0..<frameCount {
            let input = inputLeft[i]
            let output = hpAlpha * (hpPrevOut + input - hpPrevIn)
            outLeft[i] = output
            hpPrevIn = input
            hpPrevOut = output
        }

        // Simple low-pass filter
        let lpAlpha = Float(2.0 * .pi * highFreq / 48000 / (1.0 + 2.0 * .pi * highFreq / 48000))
        var lpPrevOut: Float = 0.0

        for i in 0..<frameCount {
            let input = outLeft[i]
            let output = lpAlpha * input + (1.0 - lpAlpha) * lpPrevOut
            outLeft[i] = output
            lpPrevOut = output
        }

        // Copy to right channel
        for i in 0..<frameCount {
            outRight[i] = outLeft[i]
        }

        // Compensate for filter attenuation
        scaleBufferAmplitude(outputBuffer, amplitude: 3.0)

        return outputBuffer
    }

    /// Scale buffer amplitude
    private func scaleBufferAmplitude(_ buffer: AVAudioPCMBuffer, amplitude: Float) {
        guard let channelData = buffer.floatChannelData else { return }
        let frameCount = Int(buffer.frameLength)

        for channel in 0..<Int(buffer.format.channelCount) {
            for i in 0..<frameCount {
                channelData[channel][i] *= amplitude
            }
        }
    }

    /// Stop test tone
    public func stopTestTone() {
        dlog(
            "🔇 stopTestTone() called - isPlayingLoop: \(isPlayingLoop), isPlayingReference: \(isPlayingReference)",
            category: .calibration
        )
        playerNode?.stop()
        isTestTonePlaying = false
        isPlayingReference = false
        isPlayingLoop = false
        dlog("🔇 Test tone stopped - flags reset", category: .calibration)

        // ⚡ OPTIMIZATION: Stop audio engine after delay if nothing is playing
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.stopAudioEngineIfNeeded()
        }
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

    // MARK: - Profile Management

    /// Create new profile
    public func createProfile(name: String, type: CalibrationType) -> CalibrationProfile {
        let profile = CalibrationProfile(name: name, type: type)
        profiles.append(profile)
        saveProfiles()
        dlog("✅ Created calibration profile: \(name)", category: .calibration)
        return profile
    }

    /// Update profile
    public func updateProfile(_ profile: CalibrationProfile) {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
            saveProfiles()
            dlog("✅ Updated calibration profile: \(profile.name)", category: .calibration)
        }
    }

    /// Delete profile
    public func deleteProfile(_ profile: CalibrationProfile) {
        profiles.removeAll { $0.id == profile.id }
        if activeProfile?.id == profile.id {
            activeProfile = nil
        }
        saveProfiles()
        dlog("🗑️ Deleted calibration profile: \(profile.name)", category: .calibration)
    }

    /// Activate profile
    public func activateProfile(_ profile: CalibrationProfile) {
        activeProfile = profile
        applyCalibrationToEQ(profile)

        // Auto-enable EQ routing when activating a calibration profile
        // Check both routing state and actual CoreAudioEngine status
        if !AudioRouter.shared.isRoutingActive || !CoreAudioEngine.shared.isRunning {
            AudioRouter.shared.enableEQRouting()
        }

        // ✅ AUTO-ENABLE: Automatically enable EQ processing when activating calibration
        // This ensures calibration filters are actually applied to audio
        if !CoreAudioEngine.shared.isEnabled {
            dlog("🔧 Auto-enabling EQ processing for calibration profile", category: .calibration)
            CoreAudioEngine.shared.setEnabled(true)

            // Sync UI state via notification
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: NSNotification.Name("EQStateChanged"),
                    object: nil,
                    userInfo: ["enabled": true]
                )
            }
        }

        dlog("✅ Activated calibration profile: \(profile.name)", category: .calibration)
    }

    /// Deactivate profile
    public func deactivateProfile() {
        activeProfile = nil
        clearCalibrationFromEQ()
        dlog("🔄 Deactivated calibration profile", category: .calibration)
    }

    // MARK: - Apply Calibration to EQ

    /// Apply calibration adjustments to CoreAudioEngine
    private func applyCalibrationToEQ(_ profile: CalibrationProfile) {
        // Get current EQ mode from AudioEngine
        let currentMode = AudioEngine.shared.bandMode
        let indices10 = get10BandIndices()

        // Apply calibration adjustments based on current EQ mode
        switch currentMode {
        case .tenBand:
            // Apply only 10 bands (subset of 31)
            for (bandIndex, calibIndex) in indices10.enumerated() where calibIndex < profile.bands.count {
                let adjustment = profile.bands[calibIndex]
                CoreAudioEngine.shared.setEQBand(index: bandIndex, gain: adjustment)
            }
            dlog("🎚️ Applied calibration to EQ: 10 bands", category: .calibration)

        case .thirtyOneBand:
            // Apply all 31 bands
            for (index, adjustment) in profile.bands.enumerated() where index < 31 {
                CoreAudioEngine.shared.setEQBand(index: index, gain: adjustment)
            }
            dlog("🎚️ Applied calibration to EQ: 31 bands", category: .calibration)
        }
    }

    /// Clear calibration from EQ
    private func clearCalibrationFromEQ() {
        // Get current EQ mode from AudioEngine
        let currentMode = AudioEngine.shared.bandMode

        // Reset all EQ bands to 0 dB based on current mode
        switch currentMode {
        case .tenBand:
            // Reset 10 bands
            for bandIndex in 0..<10 {
                CoreAudioEngine.shared.setEQBand(index: bandIndex, gain: 0.0)
            }
            dlog("🔄 Calibration cleared from EQ: 10 bands reset to 0 dB", category: .calibration)

        case .thirtyOneBand:
            // Reset all 31 bands
            for bandIndex in 0..<31 {
                CoreAudioEngine.shared.setEQBand(index: bandIndex, gain: 0.0)
            }
            dlog("🔄 Calibration cleared from EQ: 31 bands reset to 0 dB", category: .calibration)
        }
    }

    // MARK: - Persistence

    private var profilesURL: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("CalibrationProfiles.json")
    }

    private func saveProfiles() {
        do {
            let data = try JSONEncoder().encode(profiles)
            try data.write(to: profilesURL)
            dlog("💾 Saved \(profiles.count) calibration profiles", category: .calibration)
        } catch {
            dlog("❌ Failed to save profiles: \(error)", category: .calibration)
        }
    }

    private func loadProfiles() {
        guard FileManager.default.fileExists(atPath: profilesURL.path) else {
            dlog("ℹ️ No saved calibration profiles found", category: .calibration)
            return
        }

        do {
            let data = try Data(contentsOf: profilesURL)
            profiles = try JSONDecoder().decode([CalibrationProfile].self, from: data)
            dlog("✅ Loaded \(profiles.count) calibration profiles", category: .calibration)
        } catch {
            dlog("❌ Failed to load profiles: \(error)", category: .calibration)
        }
    }

    // MARK: - Equal Loudness Helpers

    /// Play reference tone for comparison
    /// - Parameter duration: If nil, plays in loop. If specified, plays for that duration.
    public func playReferenceTone(duration: TimeInterval? = nil) {
        let amplitude = dbToLinear(referenceLevel)

        if let duration {
            // Play for specific duration
            if useFilteredNoise {
                playFilteredPinkNoise(
                    frequency: referenceFrequency,
                    duration: duration,
                    amplitude: amplitude,
                    isReference: true
                )
            } else {
                playTestTone(frequency: referenceFrequency, duration: duration, amplitude: amplitude, isReference: true)
            }
            isPlayingReference = true
        } else {
            // Play in loop
            if useFilteredNoise {
                playFilteredPinkNoiseLoop(frequency: referenceFrequency, amplitude: amplitude)
            } else {
                playReferenceToneLoop(amplitude: amplitude)
            }
            isPlayingReference = true
        }

        // Mark reference as set when user plays the tone
        isReferenceSet = true

        dlog(
            "🔊 Playing reference: \(useFilteredNoise ? "filtered pink noise" : "sine tone") at \(Int(referenceFrequency)) Hz at \(referenceLevel) dB",
            category: .calibration
        )
    }

    /// Play filtered pink noise in continuous loop
    public func playFilteredPinkNoiseLoop(frequency: Double, amplitude: Float) {
        ensureAudioEngineSetup()
        guard let player = playerNode else { return }

        let duration: TimeInterval = 2.0

        // Generate pink noise buffer
        guard let pinkBuffer = generatePinkNoiseBuffer(duration: duration) else { return }

        // Apply band-pass filter around target frequency
        guard let filtered = applyBandPassFilterToBuffer(
            buffer: pinkBuffer,
            centerFrequency: frequency,
            bandwidth: 1.0 / 3.0
        ) else { return }

        // Scale amplitude
        scaleBufferAmplitude(filtered, amplitude: amplitude)

        player.stop()

        // Schedule buffer with looping
        player.scheduleBuffer(filtered, at: nil, options: .loops, completionHandler: nil)

        player.play()
        isTestTonePlaying = true
        isPlayingLoop = true

        dlog("🔊 Playing filtered pink noise loop: \(Int(frequency)) Hz", category: .calibration)
    }

    /// Play reference tone in a loop
    private func playReferenceToneLoop(amplitude: Float) {
        ensureAudioEngineSetup()
        guard let player = playerNode else { return }

        let sampleRate: Double = 48000
        let duration: TimeInterval = 2.0
        let frameCount = AVAudioFrameCount(sampleRate * duration)

        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: 2
        ) else { return }

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: frameCount
        ) else { return }

        buffer.frameLength = frameCount

        // Generate sine wave
        let angularFrequency = 2.0 * .pi * referenceFrequency / sampleRate

        for frame in 0..<Int(frameCount) {
            let sample = Float(sin(angularFrequency * Double(frame))) * amplitude

            // Stereo
            buffer.floatChannelData?[0][frame] = sample
            buffer.floatChannelData?[1][frame] = sample
        }

        // Apply fade in/out to avoid clicks
        applyFadeInOut(buffer: buffer, fadeDuration: 0.05)

        player.stop()

        // Schedule buffer with looping
        player.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)

        player.play()
        isTestTonePlaying = true
    }

    /// Play test tone at specific level
    public func playTestToneAtLevel(frequency: Double, level: Float, duration: TimeInterval = 2.0) {
        let amplitude = dbToLinear(level)
        playTestTone(frequency: frequency, duration: duration, amplitude: amplitude)
        isPlayingReference = false
    }

    /// Start comparison mode (alternating reference and test)
    public func startComparisonMode(testFrequency: Double, testLevel: Float) {
        dlog(
            "🔄 Starting comparison mode: reference=\(referenceFrequency)Hz, test=\(testFrequency)Hz",
            category: .calibration
        )
        currentTestLevel = testLevel
        comparisonMode = true
        playComparisonSequence(testFrequency: testFrequency)
    }

    /// Stop comparison mode
    public func stopComparisonMode() {
        dlog("🔇 stopComparisonMode() called - comparisonMode: \(comparisonMode)", category: .calibration)
        comparisonMode = false
        comparisonWorkItem?.cancel()
        comparisonWorkItem = nil

        // Force stop and clear all scheduled buffers
        if let player = playerNode {
            player.stop()
            player.reset() // Clear all scheduled buffers
        }

        isTestTonePlaying = false
        isPlayingReference = false
        isPlayingLoop = false
        dlog("🔇 Comparison mode stopped - all audio cleared", category: .calibration)

        // ⚡ OPTIMIZATION: Stop audio engine after delay if nothing is playing
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.stopAudioEngineIfNeeded()
        }
    }

    /// Play alternating reference and test tones
    private func playComparisonSequence(testFrequency: Double) {
        guard comparisonMode else { return }

        dlog("🔄 Playing comparison sequence: reference → test (level: \(currentTestLevel) dB)", category: .calibration)

        // Play reference for 2s
        if useFilteredNoise {
            playFilteredPinkNoise(
                frequency: referenceFrequency,
                duration: 2.0,
                amplitude: dbToLinear(referenceLevel),
                isReference: true
            )
        } else {
            playReferenceTone(duration: 2.0)
        }

        // Create work item for next signal
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.comparisonMode else { return }

            dlog("🔄 Playing test signal...", category: .calibration)
            // Play test for 2s using currentTestLevel
            if self.useFilteredNoise {
                self.playFilteredPinkNoise(
                    frequency: testFrequency,
                    duration: 2.0,
                    amplitude: self.dbToLinear(self.currentTestLevel),
                    isReference: false
                )
            } else {
                self.playTestToneAtLevel(frequency: testFrequency, level: self.currentTestLevel, duration: 2.0)
            }

            // ⚡ FIX: Check comparisonMode before scheduling next iteration to prevent infinite loop
            if self.comparisonMode {
                self.comparisonWorkItem = DispatchWorkItem { [weak self] in
                    guard let self, self.comparisonMode else {
                        dlog("🔇 Comparison sequence cancelled - mode disabled", category: .calibration)
                        return
                    }
                    self.playComparisonSequence(testFrequency: testFrequency)
                }
                if let workItem = self.comparisonWorkItem {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.2, execute: workItem)
                }
            } else {
                dlog("🔇 Comparison sequence ended - mode disabled", category: .calibration)
            }
        }

        comparisonWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2, execute: workItem)
    }

    /// Update test level in real-time during comparison
    public func updateComparisonTestLevel(_ newLevel: Float) {
        guard comparisonMode else { return }

        // Update the current test level - will be used in next cycle
        currentTestLevel = newLevel
    }

    /// Convert dB to linear amplitude
    private func dbToLinear(_ db: Float) -> Float {
        pow(10.0, db / 20.0) * 0.3 // Scale to safe range
    }

    /// Get 10-band frequencies (subset of 31-band)
    public func get10BandFrequencies() -> [Double] {
        [31.5, 63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    }

    /// Get frequency indices for 10-band mode
    public func get10BandIndices() -> [Int] {
        let freq10 = get10BandFrequencies()
        return freq10.compactMap { standardFrequencies.firstIndex(of: $0) }
    }

    // MARK: - Frequency Helpers

    /// Get frequency label for display
    public func frequencyLabel(_ frequency: Double) -> String {
        if frequency >= 1000 {
            String(format: "%.1fk", frequency / 1000)
        } else {
            String(format: "%.0f", frequency)
        }
    }

    /// Get frequency index in standard 31-band array
    public func frequencyIndex(_ frequency: Double) -> Int? {
        standardFrequencies.firstIndex(of: frequency)
    }

    // MARK: - Calibration Mode Management

    /// Start calibration with specified mode
    public func startCalibration(mode: CalibrationMode) {
        guard !isCalibrating else { return }
        isCalibrating = true

        if mode == .clean {
            // Save current EQ state and disable EQ
            savedEQEnabled = CoreAudioEngine.shared.isEnabled
            CoreAudioEngine.shared.isEnabled = false

            dlog("🎚️ Calibration started in CLEAN mode (EQ disabled)", category: .calibration)
        } else {
            dlog("🎚️ Calibration started in COMBINED mode (EQ active)", category: .calibration)
        }
    }

    /// End calibration and restore EQ state
    public func endCalibration(mode: CalibrationMode) {
        guard isCalibrating else { return }
        isCalibrating = false

        if mode == .clean {
            // Restore EQ state
            CoreAudioEngine.shared.isEnabled = savedEQEnabled

            dlog(
                "🎚️ Calibration ended - EQ state restored (\(savedEQEnabled ? "enabled" : "disabled"))",
                category: .calibration
            )
        } else {
            dlog("🎚️ Calibration ended", category: .calibration)
        }
    }
}
