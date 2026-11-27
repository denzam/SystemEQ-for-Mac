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

nonisolated public final class SPSCRingBuffer {
    // MARK: - Properties

    private(set) var left: UnsafeMutablePointer<Float>?
    private(set) var right: UnsafeMutablePointer<Float>?

    private(set) var capacity: Int = 0
    private(set) var mask: Int = 0

    private let writePtr: UnsafeMutablePointer<SEQAtomicInt64>
    private let readPtr: UnsafeMutablePointer<SEQAtomicInt64>

    private let underruns: UnsafeMutablePointer<SEQAtomicInt32>
    private let overruns: UnsafeMutablePointer<SEQAtomicInt32>
    private let totalUnderruns: UnsafeMutablePointer<SEQAtomicInt64>
    private let totalOverruns: UnsafeMutablePointer<SEQAtomicInt64>
    private let lastUnderrunHostTime: UnsafeMutablePointer<SEQAtomicInt64>
    private let lastOverrunHostTime: UnsafeMutablePointer<SEQAtomicInt64>
    private let readSnapshot: UnsafeMutablePointer<SEQAtomicInt64>
    private var diagnosticIntervalStart = ProcessInfo.processInfo.systemUptime
    private var resamplePhase = 0.0
    private var resampleCorrection = 0.0

    private var kernel: UnsafeMutablePointer<Float>?
    private var history: UnsafeMutablePointer<SIMD2<Float>>?
    private var historyCount: Int = 0
    private var historyEnd: Int = 0
    private var rampProgress: Float = 0

    #if DEBUG
        var prototypePhase: Double {
            resamplePhase
        }

        var prototypeCorrection: Double {
            resampleCorrection
        }

        func setInternalResamplePhase(_ phase: Double) {
            resamplePhase = phase
        }

        func setInternalResampleCorrection(_ correction: Double) {
            resampleCorrection = correction
        }
    #endif

    // MARK: - Init / Deinit

    public init() {
        writePtr = UnsafeMutablePointer<SEQAtomicInt64>.allocate(capacity: 1)
        readPtr = UnsafeMutablePointer<SEQAtomicInt64>.allocate(capacity: 1)
        seq_atomic_int64_init(writePtr, 0)
        seq_atomic_int64_init(readPtr, 0)
        underruns = .allocate(capacity: 1)
        overruns = .allocate(capacity: 1)
        totalUnderruns = .allocate(capacity: 1)
        totalOverruns = .allocate(capacity: 1)
        lastUnderrunHostTime = .allocate(capacity: 1)
        lastOverrunHostTime = .allocate(capacity: 1)
        readSnapshot = .allocate(capacity: 1)
        seq_atomic_int32_init(underruns, 0)
        seq_atomic_int32_init(overruns, 0)
        seq_atomic_int64_init(totalUnderruns, 0)
        seq_atomic_int64_init(totalOverruns, 0)
        seq_atomic_int64_init(lastUnderrunHostTime, 0)
        seq_atomic_int64_init(lastOverrunHostTime, 0)
        seq_atomic_int64_init(readSnapshot, 0)
    }

    deinit {
        deallocate()
        writePtr.deallocate()
        readPtr.deallocate()
        underruns.deallocate()
        overruns.deallocate()
        totalUnderruns.deallocate()
        totalOverruns.deallocate()
        lastUnderrunHostTime.deallocate()
        lastOverrunHostTime.deallocate()
        readSnapshot.deallocate()
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

        prepareKernel()
        history = .allocate(capacity: 32)
        history?.initialize(repeating: .zero, count: 32)

        reset()
    }

    public func deallocate() {
        left?.deallocate()
        right?.deallocate()
        left = nil
        right = nil
        kernel?.deallocate()
        kernel = nil
        history?.deallocate()
        history = nil
        capacity = 0
        mask = 0
        seq_atomic_int64_init(writePtr, 0)
        seq_atomic_int64_init(readPtr, 0)
        historyCount = 0
        historyEnd = 0
        rampProgress = 0
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
            seq_atomic_int32_fetch_add(overruns, 1)
            seq_atomic_int64_fetch_add(totalOverruns, 1)
            seq_atomic_int64_store_release(lastOverrunHostTime, Int64(bitPattern: mach_absolute_time()))
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

        publishReadSnapshot(available: avail, requested: framesRequested)
        if under > 0 {
            seq_atomic_int32_fetch_add(underruns, 1)
            seq_atomic_int64_fetch_add(totalUnderruns, 1)
            seq_atomic_int64_store_release(lastUnderrunHostTime, Int64(bitPattern: mach_absolute_time()))
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

        publishReadSnapshot(available: avail, requested: framesRequested)
        if under > 0 {
            seq_atomic_int32_fetch_add(underruns, 1)
            seq_atomic_int64_fetch_add(totalUnderruns, 1)
            seq_atomic_int64_store_release(lastUnderrunHostTime, Int64(bitPattern: mach_absolute_time()))
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

    @inline(__always)
    private func prepareKernel() {
        guard kernel == nil else { return }
        let table = UnsafeMutablePointer<Float>.allocate(capacity: 48 * 1025)
        func sinc(_ x: Double) -> Double {
            if abs(x) < 1e-12 { return 1 }
            return sin(.pi * x) / (.pi * x)
        }
        for phase in 0...1024 {
            let fraction = Double(phase) / 1024.0
            let offset = phase * 48
            var sum: Double = 0
            for tap in 0..<48 {
                let x = Double(tap - 23) - fraction
                let value = 0.96 * sinc(0.96 * x) * sinc(x / 24.0)
                table[offset + tap] = Float(value)
                sum += value
            }
            for tap in 0..<48 {
                table[offset + tap] /= Float(sum)
            }
        }
        kernel = table
    }

    @inline(__always)
    private func rememberConsumed(_ l: UnsafePointer<Float>, _ r: UnsafePointer<Float>, base: Int, count: Int) {
        guard let history, count > 0 else { return }
        if historyEnd != base { historyCount = 0 }
        for offset in max(0, count - 24)..<count {
            let absolute = base + offset
            let ring = absolute & mask
            history[absolute & 31] = SIMD2(l[ring], r[ring])
        }
        historyEnd = base + count
        historyCount = min(24, historyCount + count)
    }

    @inline(__always)
    private func interpolated(
        _ l: UnsafePointer<Float>, _ r: UnsafePointer<Float>,
        base: Int, offset: Int, fraction: Float, available: Int
    ) -> SIMD2<Float> {
        let center = (base + offset) & mask
        let next = (center + 1) & mask
        let rawAnchor = SIMD2(l[center], r[center])
        let anchor = SIMD2(
            rawAnchor.x.isFinite ? rawAnchor.x : 0,
            rawAnchor.y.isFinite ? rawAnchor.y : 0
        )
        let linear: SIMD2<Float>
        if fraction <= 1e-7 {
            linear = anchor
        } else {
            let rawNext = SIMD2(l[next], r[next])
            let nextPair = SIMD2(
                rawNext.x.isFinite ? rawNext.x : anchor.x,
                rawNext.y.isFinite ? rawNext.y : anchor.y
            )
            linear = anchor + (nextPair - anchor) * fraction
        }

        let first = offset - 23
        let future = available - offset - 25

        guard let kernel, let history, future >= 0,
              first >= 0 || (historyEnd == base && -first <= historyCount)
        else {
            rampProgress = 0
            return linear
        }

        let effectiveHeadroom = future - 48
        let target = min(1.0, max(0.0, Float(effectiveHeadroom) / 48.0))
        let maxStep: Float = 1.0 / 48.0
        if target > rampProgress {
            rampProgress = min(target, rampProgress + maxStep)
        } else if target < rampProgress {
            rampProgress = max(target, rampProgress - maxStep)
        }

        let wetMix = 0.5 - 0.5 * cos(.pi * rampProgress)

        if wetMix <= 1e-6 {
            return linear
        }

        let phase = Int((fraction * 1024.0).rounded()) * 48
        var accum = SIMD2<Float>.zero
        for tap in 0..<48 {
            let relative = first + tap
            let absolute = base + relative
            let ring = absolute & mask
            let pair = relative >= 0 ? SIMD2(l[ring], r[ring]) : history[absolute & 31]
            guard pair.x.isFinite, pair.y.isFinite else {
                rampProgress = 0
                return linear
            }
            accum += pair * kernel[phase + tap]
        }

        return linear + (accum - linear) * wetMix
    }

    @inline(__always)
    func readNonInterleavedResampled(
        outL: UnsafeMutablePointer<Float>,
        outR: UnsafeMutablePointer<Float>,
        framesRequested: Int,
        targetFillFrames: Int
    ) {
        guard framesRequested > 0, let l = left, let r = right else { return }

        let rIdxBase = loadReadRelaxed()
        let w = loadWriteAcquire()
        let avail = w - rIdxBase
        let target = max(targetFillFrames + framesRequested, framesRequested)
        let error = Double(avail - target)
        let requestedCorrection = min(max(error * 0.00001, -0.001), 0.001)
        resampleCorrection += (requestedCorrection - resampleCorrection) * 0.05
        let ratio = 1.0 + resampleCorrection

        publishReadSnapshot(available: avail, requested: framesRequested)

        var position = resamplePhase
        var renderedFrames = 0

        for frame in 0..<framesRequested {
            let sourceOffset = Int(position)
            let fraction = Float(position - Double(sourceOffset))
            let needed = fraction <= 1e-7 ? (sourceOffset + 1) : (sourceOffset + 2)

            guard needed <= avail else {
                break
            }

            let sample = interpolated(l, r, base: rIdxBase, offset: sourceOffset, fraction: fraction, available: avail)
            outL[frame] = sample.x
            outR[frame] = sample.y
            renderedFrames += 1
            position += ratio
        }

        let under = framesRequested - renderedFrames
        if under > 0 {
            vDSP_vclr(outL.advanced(by: renderedFrames), 1, vDSP_Length(under))
            vDSP_vclr(outR.advanced(by: renderedFrames), 1, vDSP_Length(under))
            seq_atomic_int32_fetch_add(underruns, 1)
            seq_atomic_int64_fetch_add(totalUnderruns, 1)
            seq_atomic_int64_store_release(lastUnderrunHostTime, Int64(bitPattern: mach_absolute_time()))
        }

        let consumed = min(avail, Int(position))
        resamplePhase = position - Double(consumed)
        rememberConsumed(l, r, base: rIdxBase, count: consumed)
        storeReadRelease(rIdxBase &+ consumed)
    }

    @inline(__always)
    func readInterleavedResampled(
        outPtr: UnsafeMutablePointer<Float>,
        framesRequested: Int,
        targetFillFrames: Int
    ) {
        guard framesRequested > 0, let l = left, let r = right else { return }

        let rIdxBase = loadReadRelaxed()
        let w = loadWriteAcquire()
        let avail = w - rIdxBase
        let target = max(targetFillFrames + framesRequested, framesRequested)
        let error = Double(avail - target)
        let requestedCorrection = min(max(error * 0.00001, -0.001), 0.001)
        resampleCorrection += (requestedCorrection - resampleCorrection) * 0.05
        let ratio = 1.0 + resampleCorrection

        publishReadSnapshot(available: avail, requested: framesRequested)

        var position = resamplePhase
        var renderedFrames = 0

        for frame in 0..<framesRequested {
            let sourceOffset = Int(position)
            let fraction = Float(position - Double(sourceOffset))
            let needed = fraction <= 1e-7 ? (sourceOffset + 1) : (sourceOffset + 2)

            guard needed <= avail else {
                break
            }

            let sample = interpolated(l, r, base: rIdxBase, offset: sourceOffset, fraction: fraction, available: avail)
            outPtr[frame * 2] = sample.x
            outPtr[frame * 2 + 1] = sample.y
            renderedFrames += 1
            position += ratio
        }

        let under = framesRequested - renderedFrames
        if under > 0 {
            let offset = renderedFrames * 2
            let underFloats = under * 2
            vDSP_vclr(outPtr.advanced(by: offset), 1, vDSP_Length(underFloats))
            seq_atomic_int32_fetch_add(underruns, 1)
            seq_atomic_int64_fetch_add(totalUnderruns, 1)
            seq_atomic_int64_store_release(lastUnderrunHostTime, Int64(bitPattern: mach_absolute_time()))
        }

        let consumed = min(avail, Int(position))
        resamplePhase = position - Double(consumed)
        rememberConsumed(l, r, base: rIdxBase, count: consumed)
        storeReadRelease(rIdxBase &+ consumed)
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
        seq_atomic_int32_store_release(underruns, 0)
        seq_atomic_int32_store_release(overruns, 0)
        seq_atomic_int64_store_release(readSnapshot, 0)
        resamplePhase = 0
        resampleCorrection = 0
        historyCount = 0
        historyEnd = 0
        rampProgress = 0
        diagnosticIntervalStart = ProcessInfo.processInfo.systemUptime
    }

    @inline(__always)
    private func publishReadSnapshot(available: Int, requested: Int) {
        let packed = UInt64(UInt32(truncatingIfNeeded: available)) << 32 |
            UInt64(UInt32(truncatingIfNeeded: requested))
        seq_atomic_int64_store_release(readSnapshot, Int64(bitPattern: packed))
    }

    func snapshotAndResetDiag() -> (
        underruns: Int32, overruns: Int32, fill: Int32, requested: UInt32, capacity: Int, intervalSeconds: Double
    ) {
        let u = seq_atomic_int32_exchange(underruns, 0)
        let o = seq_atomic_int32_exchange(overruns, 0)
        let packed = UInt64(bitPattern: seq_atomic_int64_load_acquire(readSnapshot))
        let now = ProcessInfo.processInfo.systemUptime
        let interval = max(0, now - diagnosticIntervalStart)
        diagnosticIntervalStart = now
        return (u, o, Int32(truncatingIfNeeded: packed >> 32), UInt32(truncatingIfNeeded: packed), capacity, interval)
    }

    func lifetimeDiagnostics() -> (underruns: Int64, overruns: Int64, lastUnderrun: UInt64, lastOverrun: UInt64) {
        (
            seq_atomic_int64_load_acquire(totalUnderruns),
            seq_atomic_int64_load_acquire(totalOverruns),
            UInt64(bitPattern: seq_atomic_int64_load_acquire(lastUnderrunHostTime)),
            UInt64(bitPattern: seq_atomic_int64_load_acquire(lastOverrunHostTime))
        )
    }
}

@inline(__always)
nonisolated private func interleaveStereo(
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
