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

/// Real-time peak level meter for audio buffers
/// Designed for use in audio render callbacks (lock-free, low overhead)
public final class PeakMeter: ObservableObject {
    // MARK: - Published Properties (Main Thread)

    @Published public var inputPeakLevel: Float = 0.0
    @Published public var outputPeakLevel: Float = 0.0

    // MARK: - Real-Time Properties (Audio Thread)

    /// Current input peak (set from audio thread)
    var rtInputPeak: Float = 0.0
    /// Current output peak (set from audio thread)
    var rtOutputPeak: Float = 0.0

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

    deinit {
        pendingPublishFlag.deallocate()
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
        rtInputPeak = PeakMeter.peak(
            bufferL: bufferL,
            bufferR: bufferR,
            frameCount: frameCount,
            channelCount: channelCount
        )
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
        rtOutputPeak = PeakMeter.peak(
            bufferL: bufferL,
            bufferR: bufferR,
            frameCount: frameCount,
            channelCount: channelCount
        )
        schedulePublish()
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
        DispatchQueue.main.async { [weak self] in
            self?.inputPeakLevel = 0.0
            self?.outputPeakLevel = 0.0
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
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.inputPeakLevel = inVal
            self.outputPeakLevel = outVal
            seq_atomic_flag_clear(self.pendingPublishFlag)
        }
    }
}
