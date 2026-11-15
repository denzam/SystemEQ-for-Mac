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
    struct PreparedTimebase: Sendable, Equatable {
        let status: kern_return_t
        let ticksPerSec: Double

        init(status: kern_return_t, ticksPerSec: Double) {
            self.status = status
            self.ticksPerSec = ticksPerSec
        }
    }

    static func prepareTimebase() -> PreparedTimebase {
        var timebase = mach_timebase_info_data_t()
        let timebaseStatus = mach_timebase_info(&timebase)
        guard timebaseStatus == KERN_SUCCESS else {
            return PreparedTimebase(status: timebaseStatus, ticksPerSec: 0)
        }
        guard timebase.numer > 0, timebase.denom > 0 else {
            return PreparedTimebase(status: KERN_INVALID_ARGUMENT, ticksPerSec: 0)
        }
        let ticksPerSec = Double(timebase.denom) / Double(timebase.numer) * 1_000_000_000.0
        guard ticksPerSec.isFinite, ticksPerSec > 0 else {
            return PreparedTimebase(status: KERN_INVALID_ARGUMENT, ticksPerSec: 0)
        }
        return PreparedTimebase(status: KERN_SUCCESS, ticksPerSec: ticksPerSec)
    }

    @discardableResult
    static func promoteCurrentThread(
        timebase: PreparedTimebase,
        periodSec: Double,
        computationSec: Double,
        constraintSec: Double
    ) -> kern_return_t {
        guard timebase.status == KERN_SUCCESS else { return timebase.status }
        let ticksPerSec = timebase.ticksPerSec
        guard ticksPerSec > 0 else { return KERN_INVALID_ARGUMENT }
        guard let period = UInt32(exactly: (periodSec * ticksPerSec).rounded(.towardZero)),
              let computation = UInt32(exactly: (computationSec * ticksPerSec).rounded(.towardZero)),
              let constraint = UInt32(exactly: (constraintSec * ticksPerSec).rounded(.towardZero)),
              period > 0, computation > 0, constraint > 0
        else { return KERN_INVALID_ARGUMENT }

        var policy = thread_time_constraint_policy_data_t(
            period: period,
            computation: computation,
            constraint: constraint,
            preemptible: 0
        )

        let count = UInt32(MemoryLayout<thread_time_constraint_policy_data_t>.size / MemoryLayout<integer_t>.size)
        let thread = mach_thread_self()
        guard thread != 0, thread != mach_port_t.max else { return KERN_INVALID_NAME }

        let policyStatus = withUnsafeMutablePointer(to: &policy) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                thread_policy_set(
                    thread,
                    UInt32(THREAD_TIME_CONSTRAINT_POLICY),
                    intPtr,
                    count
                )
            }
        }
        let releaseStatus = mach_port_deallocate(mach_task_self_, thread)
        return policyStatus == KERN_SUCCESS ? releaseStatus : policyStatus
    }

    /// Promote the calling thread to time-constraint scheduling.
    /// Safe to call multiple times — the kernel simply overwrites the policy.
    /// - Parameters:
    ///   - periodSec: Expected callback period (e.g. 512 frames @ 48 kHz ≈ 0.0107 s).
    ///   - computationSec: Time we expect to spend processing per callback.
    ///   - constraintSec: Deadline after which the callback must complete.
    @discardableResult
    static func promoteCurrentThread(
        periodSec: Double,
        computationSec: Double,
        constraintSec: Double
    ) -> kern_return_t {
        let prepared = prepareTimebase()
        return promoteCurrentThread(
            timebase: prepared,
            periodSec: periodSec,
            computationSec: computationSec,
            constraintSec: constraintSec
        )
    }
}
