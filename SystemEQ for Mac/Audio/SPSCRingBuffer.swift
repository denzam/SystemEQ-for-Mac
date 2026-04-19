//
//  SPSCRingBuffer.swift
//  SystemEQ for Mac
//
//  Single-Producer Single-Consumer (SPSC) ring buffer for real-time audio
//  Extracted from CoreAudioEngine to improve modularity and testability
//
//  Thread safety: Producer (input callback) and Consumer (output callback)
//  access separate indices — no locks needed for SPSC pattern.
//

import Accelerate
import Foundation

/// Lock-free SPSC ring buffer for bridging audio input → output
/// Stores deinterleaved stereo (left + right channels separately)
public final class SPSCRingBuffer {

    // MARK: - Properties

    /// Left channel buffer
    private(set) var left: UnsafeMutablePointer<Float>?
    /// Right channel buffer
    private(set) var right: UnsafeMutablePointer<Float>?

    /// Capacity in frames (always power of two)
    private(set) var capacity: Int = 0
    /// Bitmask for fast modulo (capacity - 1)
    private(set) var mask: Int = 0

    /// Write index (producer / input callback)
    var writeIndex: Int = 0
    /// Read index (consumer / output callback)
    var readIndex: Int = 0

    // Health counters incremented from audio threads, read from main.
    // Each counter is written by exactly one thread (overrun: input callback;
    // underrun+fill: output callback) so non-atomic writes are safe; main
    // thread reads are eventually-consistent which is fine for telemetry.
    var underrunCount: Int32 = 0
    var overrunCount: Int32 = 0
    var lastFillLevelFrames: Int32 = 0

    // MARK: - Init / Deinit

    public init() {}

    deinit {
        deallocate()
    }

    // MARK: - Allocation

    /// Allocate ring buffer with given capacity (rounded up to power of two)
    public func allocate(capacityFrames: Int) {
        deallocate()

        let capPow2 = 1 << Int(ceil(log2(Double(max(capacityFrames, 1024)))))
        capacity = capPow2
        mask = capPow2 - 1

        left = UnsafeMutablePointer<Float>.allocate(capacity: capacity)
        right = UnsafeMutablePointer<Float>.allocate(capacity: capacity)
        left?.initialize(repeating: 0, count: capacity)
        right?.initialize(repeating: 0, count: capacity)

        writeIndex = 0
        readIndex = 0

        dlog("🧱 SPSCRingBuffer allocated: \(capacity) frames", category: .engine)
    }

    /// Deallocate buffers
    public func deallocate() {
        left?.deallocate()
        right?.deallocate()
        left = nil
        right = nil
        capacity = 0
        mask = 0
        writeIndex = 0
        readIndex = 0
    }

    // MARK: - Computed Properties

    /// Number of frames available for reading
    var availableForReading: Int {
        writeIndex - readIndex
    }

    /// Number of frames available for writing
    var availableForWriting: Int {
        capacity - (writeIndex - readIndex)
    }

    /// Whether the buffer has been allocated
    var isAllocated: Bool {
        left != nil && right != nil && capacity > 0
    }

    // MARK: - Write (Producer / Input Callback)

    /// Write deinterleaved stereo frames into ring buffer
    /// - Parameters:
    ///   - inL: Left channel source pointer
    ///   - inR: Right channel source pointer (if nil, copies left to right)
    ///   - frameCount: Number of frames to write
    /// - Returns: Number of frames actually written
    @discardableResult
    @inline(__always)
    func write(
        inL: UnsafePointer<Float>,
        inR: UnsafePointer<Float>?,
        frameCount: Int
    ) -> Int {
        guard let l = left, let r = right else { return 0 }

        let avail = availableForWriting
        let toWrite = min(frameCount, max(0, avail))
        // Overrun: producer couldn't write all requested frames (buffer full).
        if toWrite < frameCount {
            overrunCount &+= 1
        }
        guard toWrite > 0 else { return 0 }

        let wIdx = writeIndex & mask
        let first = min(toWrite, capacity - wIdx)

        // Copy left channel
        memcpy(l.advanced(by: wIdx), inL, first * MemoryLayout<Float>.size)
        // Copy right channel (or duplicate left)
        if let inR {
            memcpy(r.advanced(by: wIdx), inR, first * MemoryLayout<Float>.size)
        } else {
            memcpy(r.advanced(by: wIdx), inL, first * MemoryLayout<Float>.size)
        }

        // Handle wrap-around
        if toWrite > first {
            let rem = toWrite - first
            memcpy(l, inL.advanced(by: first), rem * MemoryLayout<Float>.size)
            if let inR {
                memcpy(r, inR.advanced(by: first), rem * MemoryLayout<Float>.size)
            } else {
                memcpy(r, inL.advanced(by: first), rem * MemoryLayout<Float>.size)
            }
        }

        writeIndex &+= toWrite
        return toWrite
    }

    // MARK: - Read (Consumer / Output Callback)

    /// Read deinterleaved stereo frames into non-interleaved output buffers
    /// Zeros any underrun frames at the end
    @inline(__always)
    func readNonInterleaved(
        outL: UnsafeMutablePointer<Float>,
        outR: UnsafeMutablePointer<Float>,
        framesRequested: Int
    ) {
        guard let l = left, let r = right else { return }

        let avail = availableForReading
        let toRead = min(framesRequested, max(0, avail))
        let under = framesRequested - toRead

        // Sample fill level; underrun: consumer asked for more than available.
        lastFillLevelFrames = Int32(truncatingIfNeeded: avail)
        if under > 0 {
            underrunCount &+= 1
        }

        if toRead > 0 {
            let rIdx = readIndex & mask
            let first = min(toRead, capacity - rIdx)

            memcpy(outL, l.advanced(by: rIdx), first * MemoryLayout<Float>.size)
            memcpy(outR, r.advanced(by: rIdx), first * MemoryLayout<Float>.size)

            if toRead > first {
                let rem = toRead - first
                memcpy(outL.advanced(by: first), l, rem * MemoryLayout<Float>.size)
                memcpy(outR.advanced(by: first), r, rem * MemoryLayout<Float>.size)
            }

            readIndex &+= toRead
        }

        // Zero underrun
        if under > 0 {
            vDSP_vclr(outL.advanced(by: toRead), 1, vDSP_Length(under))
            vDSP_vclr(outR.advanced(by: toRead), 1, vDSP_Length(under))
        }
    }

    /// Read deinterleaved stereo frames into interleaved output buffer (LRLRLR...)
    /// Zeros any underrun frames at the end
    @inline(__always)
    func readInterleaved(
        outPtr: UnsafeMutablePointer<Float>,
        framesRequested: Int
    ) {
        guard let l = left, let r = right else { return }

        let avail = availableForReading
        let toRead = min(framesRequested, max(0, avail))
        let under = framesRequested - toRead

        // Sample fill level; underrun: consumer asked for more than available.
        lastFillLevelFrames = Int32(truncatingIfNeeded: avail)
        if under > 0 {
            underrunCount &+= 1
        }

        if toRead > 0 {
            let rIdx = readIndex & mask
            let first = min(toRead, capacity - rIdx)

            for i in 0..<first {
                outPtr[i * 2] = l[rIdx + i]
                outPtr[i * 2 + 1] = r[rIdx + i]
            }
            if toRead > first {
                let rem = toRead - first
                for i in 0..<rem {
                    outPtr[(first + i) * 2] = l[i]
                    outPtr[(first + i) * 2 + 1] = r[i]
                }
            }

            readIndex &+= toRead
        }

        if under > 0 {
            let off = toRead * 2
            vDSP_vclr(outPtr.advanced(by: off), 1, vDSP_Length(under * 2))
        }
    }

    /// Reset read/write indices (call when stopping audio)
    func reset() {
        writeIndex = 0
        readIndex = 0
        underrunCount = 0
        overrunCount = 0
        lastFillLevelFrames = 0
    }

    // Snapshot + reset health counters, called from main thread. Races with
    // audio threads are benign — counts may be off by 1-2 per tick.
    func snapshotAndResetDiag() -> (underruns: Int32, overruns: Int32, fill: Int32, capacity: Int) {
        let u = underrunCount
        let o = overrunCount
        let f = lastFillLevelFrames
        underrunCount = 0
        overrunCount = 0
        return (u, o, f, capacity)
    }
}
