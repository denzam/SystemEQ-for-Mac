//
//  PeakMeter.swift
//  SystemEQ for Mac
//
//  Peak level metering for audio buffers
//  Extracted from CoreAudioEngine to improve modularity
//
//  Usage: Call update() from the audio thread, then publishToMainThread()
//  to push values to @Published properties on the main thread.
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

    /// Coalesces redundant main-thread dispatches when one is already in flight.
    /// Set from audio thread (test-and-set), cleared from main thread.
    private let pendingPublishFlag: UnsafeMutablePointer<SEQAtomicFlag> = {
        let p = UnsafeMutablePointer<SEQAtomicFlag>.allocate(capacity: 1)
        seq_atomic_flag_clear(p)
        return p
    }()

    private let nonFiniteOutputPeakCount: UnsafeMutablePointer<SEQAtomicInt32> = {
        let p = UnsafeMutablePointer<SEQAtomicInt32>.allocate(capacity: 1)
        seq_atomic_int32_init(p, 0)
        return p
    }()

    private var reportedNonFiniteOutputPeak = false
    private var limiterClearWorkItem: DispatchWorkItem?

    deinit {
        pendingPublishFlag.deallocate()
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

    /// Post-EQ level, and the trigger that pushes both values to the UI.
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
        schedulePublish()
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
        DispatchQueue.main.async { [weak self] in
            self?.limiterClearWorkItem?.cancel()
            self?.limiterClearWorkItem = nil
            self?.inputPeakLevel = 0.0
            self?.outputPeakLevel = 0.0
            self?.limiterGainReductionDB = 0.0
        }
    }

    // MARK: - Private

    /// Schedule a main-thread update (coalesced via atomic flag).
    private func schedulePublish() {
        // test-and-set: returns true only if we transitioned clear → set,
        // so exactly one dispatch is in flight at a time.
        guard seq_atomic_flag_test_and_set(pendingPublishFlag) else { return }
        let inVal = rtInputPeak
        let outVal = rtOutputPeak
        let limiterGain = rtMinimumLimiterGain
        rtMinimumLimiterGain = 1.0
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.inputPeakLevel = inVal
            self.outputPeakLevel = outVal
            if limiterGain < 0.999_9 {
                let reduction = max(0, -20 * log10(max(limiterGain, 0.000_001)))
                self.limiterGainReductionDB = reduction
                self.limiterClearWorkItem?.cancel()
                let clearWorkItem = DispatchWorkItem { [weak self] in
                    self?.limiterGainReductionDB = 0.0
                    self?.limiterClearWorkItem = nil
                }
                self.limiterClearWorkItem = clearWorkItem
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: clearWorkItem)
            }
            if !self.reportedNonFiniteOutputPeak,
               seq_atomic_int32_load(self.nonFiniteOutputPeakCount) > 0 {
                self.reportedNonFiniteOutputPeak = true
                dlog("Discarded a non-finite post-EQ peak value", level: .warning, category: .engine)
            }
            seq_atomic_flag_clear(self.pendingPublishFlag)
        }
    }
}
