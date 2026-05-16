//
//  SPSCRingBuffer.swift
//  SystemEQ for Mac
//
//  Single-Producer Single-Consumer (SPSC) ring buffer for real-time audio.
//  Producer = input callback, Consumer = output callback.
//
//  Indices use C11 atomics with acquire/release semantics so memory writes
//  to the backing buffers are visible to the reader before it observes the
//  published writeIndex, and vice versa.
//

import Accelerate
import Foundation

public final class SPSCRingBuffer {
    // MARK: - Properties

    private(set) var left: UnsafeMutablePointer<Float>?
    private(set) var right: UnsafeMutablePointer<Float>?

    private(set) var capacity: Int = 0
    private(set) var mask: Int = 0

    private let writePtr: UnsafeMutablePointer<SEQAtomicInt64>
    private let readPtr: UnsafeMutablePointer<SEQAtomicInt64>

    // Health counters — each written by exactly one thread, read from main.
    // Non-atomic is fine for eventual-consistency telemetry.
    var underrunCount: Int32 = 0
    var overrunCount: Int32 = 0
    var lastFillLevelFrames: Int32 = 0

    // MARK: - Init / Deinit

    public init() {
        writePtr = UnsafeMutablePointer<SEQAtomicInt64>.allocate(capacity: 1)
        readPtr = UnsafeMutablePointer<SEQAtomicInt64>.allocate(capacity: 1)
        seq_atomic_int64_init(writePtr, 0)
        seq_atomic_int64_init(readPtr, 0)
    }

    deinit {
        deallocate()
        writePtr.deallocate()
        readPtr.deallocate()
    }

    // MARK: - Index accessors

    @inline(__always)
    private func loadWriteAcquire() -> Int {
        Int(seq_atomic_int64_load_acquire(writePtr))
    }

    @inline(__always)
    private func loadWriteRelaxed() -> Int {
        Int(seq_atomic_int64_load_relaxed(writePtr))
    }

    @inline(__always)
    private func storeWriteRelease(_ v: Int) {
        seq_atomic_int64_store_release(writePtr, Int64(v))
    }

    @inline(__always)
    private func loadReadAcquire() -> Int {
        Int(seq_atomic_int64_load_acquire(readPtr))
    }

    @inline(__always)
    private func loadReadRelaxed() -> Int {
        Int(seq_atomic_int64_load_relaxed(readPtr))
    }

    @inline(__always)
    private func storeReadRelease(_ v: Int) {
        seq_atomic_int64_store_release(readPtr, Int64(v))
    }

    // MARK: - Allocation

    public func allocate(capacityFrames: Int) {
        deallocate()

        let capPow2 = 1 << Int(ceil(log2(Double(max(capacityFrames, 1024)))))
        capacity = capPow2
        mask = capPow2 - 1

        left = UnsafeMutablePointer<Float>.allocate(capacity: capacity)
        right = UnsafeMutablePointer<Float>.allocate(capacity: capacity)
        left?.initialize(repeating: 0, count: capacity)
        right?.initialize(repeating: 0, count: capacity)

        seq_atomic_int64_init(writePtr, 0)
        seq_atomic_int64_init(readPtr, 0)

        dlog("🧱 SPSCRingBuffer allocated: \(capacity) frames", category: .engine)
    }

    public func deallocate() {
        left?.deallocate()
        right?.deallocate()
        left = nil
        right = nil
        capacity = 0
        mask = 0
        seq_atomic_int64_init(writePtr, 0)
        seq_atomic_int64_init(readPtr, 0)
    }

    // MARK: - Computed Properties

    /// Frames available for reading (main thread / diagnostic use — relaxed).
    var availableForReading: Int {
        loadWriteRelaxed() - loadReadRelaxed()
    }

    /// Frames available for writing (main thread / diagnostic use — relaxed).
    var availableForWriting: Int {
        capacity - (loadWriteRelaxed() - loadReadRelaxed())
    }

    var isAllocated: Bool {
        left != nil && right != nil && capacity > 0
    }

    /// Diagnostic-only relaxed reads (main thread).
    var writeIndex: Int {
        loadWriteRelaxed()
    }

    var readIndex: Int {
        loadReadRelaxed()
    }

    // MARK: - Write (Producer / Input Callback)

    @discardableResult
    @inline(__always)
    func write(
        inL: UnsafePointer<Float>,
        inR: UnsafePointer<Float>?,
        frameCount: Int
    ) -> Int {
        guard let l = left, let r = right else { return 0 }

        // Producer owns writeIndex (relaxed), acquires readIndex from consumer.
        let w = loadWriteRelaxed()
        let rIdx = loadReadAcquire()
        let avail = capacity - (w - rIdx)
        let toWrite = min(frameCount, max(0, avail))
        if toWrite < frameCount {
            overrunCount &+= 1
        }
        guard toWrite > 0 else { return 0 }

        let wIdx = w & mask
        let first = min(toWrite, capacity - wIdx)

        memcpy(l.advanced(by: wIdx), inL, first * MemoryLayout<Float>.size)
        if let inR {
            memcpy(r.advanced(by: wIdx), inR, first * MemoryLayout<Float>.size)
        } else {
            memcpy(r.advanced(by: wIdx), inL, first * MemoryLayout<Float>.size)
        }

        if toWrite > first {
            let rem = toWrite - first
            memcpy(l, inL.advanced(by: first), rem * MemoryLayout<Float>.size)
            if let inR {
                memcpy(r, inR.advanced(by: first), rem * MemoryLayout<Float>.size)
            } else {
                memcpy(r, inL.advanced(by: first), rem * MemoryLayout<Float>.size)
            }
        }

        // Release: memcpys above must be visible before the reader sees new writeIndex.
        storeWriteRelease(w &+ toWrite)
        return toWrite
    }

    // MARK: - Read (Consumer / Output Callback)

    @inline(__always)
    func readNonInterleaved(
        outL: UnsafeMutablePointer<Float>,
        outR: UnsafeMutablePointer<Float>,
        framesRequested: Int
    ) {
        guard let l = left, let r = right else { return }

        // Consumer owns readIndex (relaxed), acquires writeIndex from producer.
        let rIdxBase = loadReadRelaxed()
        let w = loadWriteAcquire()
        let avail = w - rIdxBase
        let toRead = min(framesRequested, max(0, avail))
        let under = framesRequested - toRead

        lastFillLevelFrames = Int32(truncatingIfNeeded: avail)
        if under > 0 {
            underrunCount &+= 1
        }

        if toRead > 0 {
            let rIdx = rIdxBase & mask
            let first = min(toRead, capacity - rIdx)

            memcpy(outL, l.advanced(by: rIdx), first * MemoryLayout<Float>.size)
            memcpy(outR, r.advanced(by: rIdx), first * MemoryLayout<Float>.size)

            if toRead > first {
                let rem = toRead - first
                memcpy(outL.advanced(by: first), l, rem * MemoryLayout<Float>.size)
                memcpy(outR.advanced(by: first), r, rem * MemoryLayout<Float>.size)
            }

            storeReadRelease(rIdxBase &+ toRead)
        }

        if under > 0 {
            vDSP_vclr(outL.advanced(by: toRead), 1, vDSP_Length(under))
            vDSP_vclr(outR.advanced(by: toRead), 1, vDSP_Length(under))
        }
    }

    @inline(__always)
    func readInterleaved(
        outPtr: UnsafeMutablePointer<Float>,
        framesRequested: Int
    ) {
        guard let l = left, let r = right else { return }

        let rIdxBase = loadReadRelaxed()
        let w = loadWriteAcquire()
        let avail = w - rIdxBase
        let toRead = min(framesRequested, max(0, avail))
        let under = framesRequested - toRead

        lastFillLevelFrames = Int32(truncatingIfNeeded: avail)
        if under > 0 {
            underrunCount &+= 1
        }

        if toRead > 0 {
            let rIdx = rIdxBase & mask
            let first = min(toRead, capacity - rIdx)

            interleaveStereo(l: l.advanced(by: rIdx), r: r.advanced(by: rIdx), out: outPtr, count: first)
            if toRead > first {
                let rem = toRead - first
                interleaveStereo(l: l, r: r, out: outPtr.advanced(by: first * 2), count: rem)
            }

            storeReadRelease(rIdxBase &+ toRead)
        }

        if under > 0 {
            let off = toRead * 2
            vDSP_vclr(outPtr.advanced(by: off), 1, vDSP_Length(under * 2))
        }
    }

    /// Advance the write index by `frames` without writing audio (buffers are
    /// zero-initialized on allocate). Used at startup to seed the consumer so
    /// the first output callbacks don't see an empty ring while the producer
    /// is still warming up — prevents underrun spikes and HALC overload.
    /// Call from UI thread BEFORE starting the audio units.
    func primeSilence(frames: Int) {
        guard isAllocated else { return }
        let target = min(frames, capacity / 2)
        // Indices at this point are 0/0; plain write is race-free because
        // neither audio callback is running yet. Use release-store so the
        // consumer sees the zeroed buffers when it does start.
        seq_atomic_int64_store_release(writePtr, Int64(target))
    }

    func reset() {
        seq_atomic_int64_init(writePtr, 0)
        seq_atomic_int64_init(readPtr, 0)
        underrunCount = 0
        overrunCount = 0
        lastFillLevelFrames = 0
    }

    func snapshotAndResetDiag() -> (underruns: Int32, overruns: Int32, fill: Int32, capacity: Int) {
        let u = underrunCount
        let o = overrunCount
        let f = lastFillLevelFrames
        underrunCount = 0
        overrunCount = 0
        return (u, o, f, capacity)
    }
}

@inline(__always)
private func interleaveStereo(
    l: UnsafePointer<Float>,
    r: UnsafePointer<Float>,
    out: UnsafeMutablePointer<Float>,
    count: Int
) {
    for i in 0..<count {
        out[i &* 2] = l[i]
        out[i &* 2 &+ 1] = r[i]
    }
}
