//
//  PeakMeter.swift
//  SystemEQ for Mac
//
//  Peak level metering for audio buffers
//  Extracted from CoreAudioEngine to improve modularity
//
//  Usage: sample from the audio thread; a main-thread timer publishes values.
//

import Accelerate
import Combine
import Foundation

nonisolated enum LimiterIndicatorState: Equatable {
    case normal
    case mild
    case heavy

    static func state(for gainReductionDB: Float) -> Self {
        if gainReductionDB >= 3 { return .heavy }
        if gainReductionDB > 0.05 { return .mild }
        return .normal
    }
}

/// Real-time peak level meter for audio buffers
/// Designed for use in audio render callbacks (lock-free, low overhead)
public final class PeakMeter: ObservableObject {
    // MARK: - Published Properties (Main Thread)

    @Published public var inputPeakLevel: Float = 0.0
    @Published public var outputPeakLevel: Float = 0.0
    @Published public private(set) var limiterGainReductionDB: Float = 0.0

    // MARK: - Real-Time Properties (Audio Thread)

    /// Current input peak (set from audio thread)
    var rtInputPeak: Float = 0.0
    /// Current output peak (set from audio thread)
    var rtOutputPeak: Float = 0.0
    private var rtMinimumLimiterGain: Float = 1.0

    /// Frame counter for throttled updates
    var updateCounter: Int = 0
    /// Update interval in frames (~85ms at 48kHz)
    var updateInterval: Int = 4096

    private let publishedLevels: UnsafeMutablePointer<SEQAtomicInt64> = {
        let p = UnsafeMutablePointer<SEQAtomicInt64>.allocate(capacity: 1)
        seq_atomic_int64_init(p, 0)
        return p
    }()

    private let publishedLimiterGain: UnsafeMutablePointer<SEQAtomicInt32> = {
        let p = UnsafeMutablePointer<SEQAtomicInt32>.allocate(capacity: 1)
        seq_atomic_int32_init(p, Int32(bitPattern: Float(1).bitPattern))
        return p
    }()

    private let publishGeneration: UnsafeMutablePointer<SEQAtomicInt32> = {
        let p = UnsafeMutablePointer<SEQAtomicInt32>.allocate(capacity: 1)
        seq_atomic_int32_init(p, 0)
        return p
    }()

    private let nonFiniteOutputPeakCount: UnsafeMutablePointer<SEQAtomicInt32> = {
        let p = UnsafeMutablePointer<SEQAtomicInt32>.allocate(capacity: 1)
        seq_atomic_int32_init(p, 0)
        return p
    }()

    private var reportedNonFiniteOutputPeak = false
    private var limiterClearWorkItem: DispatchWorkItem?
    private var lastPublishedGeneration: Int32 = 0
    private var publicationTimer: DispatchSourceTimer?

    init() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.08, repeating: 0.08, leeway: .milliseconds(20))
        timer.setEventHandler { [weak self] in
            self?.publishLatest()
        }
        publicationTimer = timer
        timer.resume()
    }

    deinit {
        publicationTimer?.setEventHandler {}
        publicationTimer?.cancel()
        publishedLevels.deallocate()
        publishedLimiterGain.deallocate()
        publishGeneration.deallocate()
        nonFiniteOutputPeakCount.deallocate()
    }

    // MARK: - Audio Thread API

    /// Whether this callback lands on a metering tick (~85 ms). Call once per
    /// callback, before EQ processing, so the input can be sampled pre-EQ and the
    /// output post-EQ from the same buffer.
    @inline(__always)
    func shouldSample(frameCount: Int) -> Bool {
        updateCounter += frameCount
        guard updateCounter >= updateInterval else { return false }
        updateCounter = 0
        return true
    }

    /// Pre-EQ level. Only call when `shouldSample` returned true.
    @inline(__always)
    func sampleInput(
        bufferL: UnsafePointer<Float>,
        bufferR: UnsafePointer<Float>?,
        frameCount: Int,
        channelCount: UInt32
    ) {
        rtInputPeak = PeakMeter.sanitizedPeak(PeakMeter.peak(
            bufferL: bufferL,
            bufferR: bufferR,
            frameCount: frameCount,
            channelCount: channelCount
        ))
    }

    /// Post-EQ level, and the trigger that publishes both values atomically.
    /// Only call when `shouldSample` returned true.
    @inline(__always)
    func sampleOutput(
        bufferL: UnsafePointer<Float>,
        bufferR: UnsafePointer<Float>?,
        frameCount: Int,
        channelCount: UInt32
    ) {
        let peak = PeakMeter.peak(
            bufferL: bufferL,
            bufferR: bufferR,
            frameCount: frameCount,
            channelCount: channelCount
        )
        if peak.isFinite {
            rtOutputPeak = max(peak, 0)
        } else {
            rtOutputPeak = 0
            _ = seq_atomic_int32_fetch_add(nonFiniteOutputPeakCount, 1)
        }
        publishSample()
    }

    @inline(__always)
    func recordLimiterGain(_ gain: Float) {
        guard gain.isFinite else { return }
        rtMinimumLimiterGain = min(rtMinimumLimiterGain, min(max(gain, 0), 1))
    }

    @inline(__always)
    static func sanitizedPeak(_ peak: Float) -> Float {
        guard peak.isFinite else { return 0 }
        return max(peak, 0)
    }

    @inline(__always)
    private static func peak(
        bufferL: UnsafePointer<Float>,
        bufferR: UnsafePointer<Float>?,
        frameCount: Int,
        channelCount: UInt32
    ) -> Float {
        var maxL: Float = 0
        vDSP_maxmgv(bufferL, 1, &maxL, vDSP_Length(frameCount))

        var maxR: Float = 0
        if channelCount > 1, let rPtr = bufferR {
            vDSP_maxmgv(rPtr, 1, &maxR, vDSP_Length(frameCount))
        }

        return max(maxL, maxR)
    }

    /// Reset meters to zero (call when stopping audio)
    func resetToZero() {
        rtInputPeak = 0.0
        rtOutputPeak = 0.0
        rtMinimumLimiterGain = 1.0
        seq_atomic_int64_store_release(publishedLevels, 0)
        seq_atomic_int32_store_release(publishedLimiterGain, Int32(bitPattern: Float(1).bitPattern))
        _ = seq_atomic_int32_fetch_add(publishGeneration, 1)
        DispatchQueue.main.async { [weak self] in
            self?.limiterClearWorkItem?.cancel()
            self?.limiterClearWorkItem = nil
            self?.inputPeakLevel = 0.0
            self?.outputPeakLevel = 0.0
            self?.limiterGainReductionDB = 0.0
        }
    }

    // MARK: - Private

    @inline(__always)
    private func publishSample() {
        let packedLevels = Self.packLevels(input: rtInputPeak, output: rtOutputPeak)
        let limiterBits = Int32(bitPattern: rtMinimumLimiterGain.bitPattern)
        rtMinimumLimiterGain = 1.0
        seq_atomic_int32_store_min(publishedLimiterGain, limiterBits)
        seq_atomic_int64_store_release(publishedLevels, Int64(bitPattern: packedLevels))
        _ = seq_atomic_int32_fetch_add(publishGeneration, 1)
    }

    private func publishLatest() {
        let generation = seq_atomic_int32_load(publishGeneration)
        guard generation != lastPublishedGeneration else { return }
        lastPublishedGeneration = generation

        let packedLevels = UInt64(bitPattern: seq_atomic_int64_load_acquire(publishedLevels))
        let levels = Self.unpackLevels(packedLevels)
        let limiterBits = UInt32(bitPattern: seq_atomic_int32_exchange(
            publishedLimiterGain,
            Int32(bitPattern: Float(1).bitPattern)
        ))
        let limiterGain = Float(bitPattern: limiterBits)

        inputPeakLevel = levels.input
        outputPeakLevel = levels.output
        if limiterGain < 0.999_9 {
            let reduction = max(0, -20 * log10(max(limiterGain, 0.000_001)))
            limiterGainReductionDB = reduction
            limiterClearWorkItem?.cancel()
            let clearWorkItem = DispatchWorkItem { [weak self] in
                self?.limiterGainReductionDB = 0.0
                self?.limiterClearWorkItem = nil
            }
            limiterClearWorkItem = clearWorkItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: clearWorkItem)
        }
        if !reportedNonFiniteOutputPeak,
           seq_atomic_int32_load(nonFiniteOutputPeakCount) > 0 {
            reportedNonFiniteOutputPeak = true
            dlog("Discarded a non-finite post-EQ peak value", level: .warning, category: .engine)
        }
    }

    @inline(__always)
    static func packLevels(input: Float, output: Float) -> UInt64 {
        UInt64(input.bitPattern) << 32 | UInt64(output.bitPattern)
    }

    static func unpackLevels(_ packed: UInt64) -> (input: Float, output: Float) {
        (
            Float(bitPattern: UInt32(truncatingIfNeeded: packed >> 32)),
            Float(bitPattern: UInt32(truncatingIfNeeded: packed))
        )
    }
}
