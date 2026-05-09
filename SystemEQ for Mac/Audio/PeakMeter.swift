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

    /// Measure peak level from audio buffers
    /// Call from audio render callback
    /// - Parameters:
    ///   - bufferL: Left channel buffer
    ///   - bufferR: Right channel buffer (optional, uses left if nil)
    ///   - frameCount: Number of frames in buffers
    ///   - channelCount: Number of channels (1 or 2)
    @inline(__always)
    func update(
        bufferL: UnsafePointer<Float>,
        bufferR: UnsafePointer<Float>?,
        frameCount: Int,
        channelCount: UInt32
    ) {
        updateCounter += frameCount
        guard updateCounter >= updateInterval else { return }
        updateCounter = 0

        var maxL: Float = 0
        vDSP_maxmgv(bufferL, 1, &maxL, vDSP_Length(frameCount))

        var maxR: Float = 0
        if channelCount > 1, let rPtr = bufferR {
            vDSP_maxmgv(rPtr, 1, &maxR, vDSP_Length(frameCount))
        }

        let peak = max(maxL, maxR)
        rtInputPeak = peak
        rtOutputPeak = peak
        schedulePublish()
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
