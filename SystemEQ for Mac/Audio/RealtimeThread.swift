//
//  RealtimeThread.swift
//  SystemEQ for Mac
//
//  Promotes the current thread to Mach time-constraint scheduling policy.
//  Dual-I/O AUHAL callbacks don't always inherit real-time priority on
//  third-party devices (BlackHole → Scarlett), which causes HALC
//  "skipping cycle due to overload" warnings. Calling `promoteCurrentThread`
//  from the first callback invocation fixes this.
//

import Darwin
import Foundation

enum RealtimeThread {
    /// Promote the calling thread to time-constraint scheduling.
    /// Safe to call multiple times — the kernel simply overwrites the policy.
    /// - Parameters:
    ///   - periodSec: Expected callback period (e.g. 512 frames @ 48 kHz ≈ 0.0107 s).
    ///   - computationSec: Time we expect to spend processing per callback.
    ///   - constraintSec: Deadline after which the callback must complete.
    static func promoteCurrentThread(
        periodSec: Double,
        computationSec: Double,
        constraintSec: Double
    ) {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        // Convert seconds → mach absolute units (ticks).
        let ticksPerSec = Double(timebase.denom) / Double(timebase.numer) * 1_000_000_000.0

        var policy = thread_time_constraint_policy_data_t(
            period: UInt32(periodSec * ticksPerSec),
            computation: UInt32(computationSec * ticksPerSec),
            constraint: UInt32(constraintSec * ticksPerSec),
            preemptible: 0
        )

        let count = UInt32(MemoryLayout<thread_time_constraint_policy_data_t>.size / MemoryLayout<integer_t>.size)

        withUnsafeMutablePointer(to: &policy) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                _ = thread_policy_set(
                    mach_thread_self(),
                    UInt32(THREAD_TIME_CONSTRAINT_POLICY),
                    intPtr,
                    count
                )
            }
        }
    }
}
