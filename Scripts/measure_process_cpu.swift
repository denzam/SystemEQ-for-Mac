import Darwin
import Foundation

@main
struct ProcessCPUMeasurement {
    struct Snapshot {
        let pid: Int32
        let start: UInt64
        let path: String
        let monotonicNS: UInt64
        let userTicks: UInt64
        let systemTicks: UInt64
        let residentBytes: UInt64
    }

    struct Sample: Encodable {
        let elapsedSeconds: Double
        let userCPUPercent: Double
        let systemCPUPercent: Double
        let cpuPercentOfOneCore: Double
        let residentBytes: UInt64
    }

    struct Report: Encodable {
        let schemaVersion = 1
        let method = "proc_pid_rusage CPU-time deltas / monotonic wall-time; percent of one core"
        let pid: Int32
        let executable: String
        let processStart: UInt64
        let label: String
        let inputConditions = "Caller must control audio input and UI state for comparisons."
        let measuredSeconds: Double
        let meanCPUPercentOfOneCore: Double
        let samples: [Sample]
    }

    struct Failure: LocalizedError {
        let errorDescription: String?
        init(_ description: String) {
            errorDescription = description
        }
    }

    static func main() {
        do {
            try run(Array(CommandLine.arguments.dropFirst()))
        } catch {
            try? FileHandle.standardError.write(contentsOf: Data("\(error.localizedDescription)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }

    static func run(_ arguments: [String]) throws {
        if arguments == ["--help"] {
            try FileHandle.standardOutput.write(contentsOf: Data(
                "Usage: measure-process-cpu PID seconds [interval-seconds] [label]\n".utf8
            ))
            return
        }
        if arguments == ["--self-test"] {
            try selfTest()
            return
        }
        guard (2...4).contains(arguments.count),
              let pid = Int32(arguments[0]), pid > 0,
              let seconds = Double(arguments[1]), seconds.isFinite, (1...300).contains(seconds),
              let interval = Double(arguments.count > 2 ? arguments[2] : "1"),
              interval.isFinite, (0.1...60).contains(interval), interval <= seconds
        else { throw Failure("Invalid arguments; use --help.") }
        let label = arguments.count > 3 ? arguments[3] : "unspecified"
        guard label.utf8.count <= 256 else { throw Failure("Label exceeds 256 bytes.") }

        var timebase = mach_timebase_info_data_t()
        guard mach_timebase_info(&timebase) == KERN_SUCCESS, timebase.denom > 0 else {
            throw Failure("Cannot determine Mach clock scale.")
        }
        let nanosecondsPerTick = Double(timebase.numer) / Double(timebase.denom)

        let initial = try snapshot(pid: pid)
        var previous = initial
        var samples: [Sample] = []
        let deadline = initial.monotonicNS + UInt64(seconds * 1_000_000_000)
        while previous.monotonicNS < deadline {
            let remaining = Double(deadline - previous.monotonicNS) / 1_000_000_000
            Thread.sleep(forTimeInterval: min(interval, remaining))
            let current = try snapshot(pid: pid)
            try samples.append(sample(from: previous, to: current, nanosecondsPerTick: nanosecondsPerTick))
            previous = current
        }
        let total = try sample(from: initial, to: previous, nanosecondsPerTick: nanosecondsPerTick)
        let report = Report(
            pid: pid, executable: initial.path, processStart: initial.start,
            label: label, measuredSeconds: total.elapsedSeconds,
            meanCPUPercentOfOneCore: total.cpuPercentOfOneCore, samples: samples
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var output = try encoder.encode(report)
        output.append(0x0A)
        try FileHandle.standardOutput.write(contentsOf: output)
    }

    static func snapshot(pid: Int32) throws -> Snapshot {
        var usage = rusage_info_v2()
        let result = withUnsafeMutablePointer(to: &usage) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V2, $0)
            }
        }
        guard result == 0 else { throw Failure("Cannot read CPU counters for PID \(pid): errno \(errno).") }
        var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let pathResult = path.withUnsafeMutableBytes {
            proc_pidpath(pid, $0.baseAddress, UInt32($0.count))
        }
        guard pathResult > 0 else { throw Failure("Cannot verify executable for PID \(pid): errno \(errno).") }
        var verified = rusage_info_v2()
        let verifiedResult = withUnsafeMutablePointer(to: &verified) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V2, $0)
            }
        }
        guard verifiedResult == 0, usage.ri_proc_start_abstime == verified.ri_proc_start_abstime else {
            throw Failure("Process exited or PID was reused during sampling.")
        }
        return Snapshot(
            pid: pid, start: verified.ri_proc_start_abstime,
            path: String(decoding: path.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self),
            monotonicNS: DispatchTime.now().uptimeNanoseconds,
            userTicks: verified.ri_user_time, systemTicks: verified.ri_system_time,
            residentBytes: verified.ri_resident_size
        )
    }

    static func sample(from previous: Snapshot, to current: Snapshot, nanosecondsPerTick: Double) throws -> Sample {
        guard previous.pid == current.pid, previous.start == current.start, previous.path == current.path else {
            throw Failure("Process identity changed; comparison rejected.")
        }
        guard nanosecondsPerTick.isFinite, nanosecondsPerTick > 0,
              current.monotonicNS > previous.monotonicNS,
              current.userTicks >= previous.userTicks, current.systemTicks >= previous.systemTicks
        else { throw Failure("Invalid elapsed time or decreasing CPU counter; comparison rejected.") }
        let wallNS = Double(current.monotonicNS - previous.monotonicNS)
        let user = Double(current.userTicks - previous.userTicks) * nanosecondsPerTick / wallNS * 100
        let system = Double(current.systemTicks - previous.systemTicks) * nanosecondsPerTick / wallNS * 100
        return Sample(
            elapsedSeconds: wallNS / 1_000_000_000,
            userCPUPercent: user, systemCPUPercent: system,
            cpuPercentOfOneCore: user + system, residentBytes: current.residentBytes
        )
    }

    static func selfTest() throws {
        let initial = Snapshot(
            pid: 1,
            start: 9,
            path: "/fixture",
            monotonicNS: 10,
            userTicks: 0,
            systemTicks: 0,
            residentBytes: 0
        )
        let loaded = Snapshot(
            pid: 1,
            start: 9,
            path: "/fixture",
            monotonicNS: 110,
            userTicks: 150,
            systemTicks: 50,
            residentBytes: 8
        )
        let measured = try sample(from: initial, to: loaded, nanosecondsPerTick: 1)
        guard measured.cpuPercentOfOneCore == 200, measured.userCPUPercent == 150,
              measured.systemCPUPercent == 50, measured.residentBytes == 8
        else { throw Failure("CPU delta calculation failed.") }
        guard try sample(from: initial, to: loaded, nanosecondsPerTick: 2.5).cpuPercentOfOneCore == 500 else {
            throw Failure("Mach clock scale conversion failed.")
        }
        let idle = Snapshot(
            pid: 1,
            start: 9,
            path: "/fixture",
            monotonicNS: 110,
            userTicks: 0,
            systemTicks: 0,
            residentBytes: 0
        )
        guard try sample(from: initial, to: idle, nanosecondsPerTick: 1).cpuPercentOfOneCore == 0 else {
            throw Failure("Idle calculation failed.")
        }
        let invalid = [
            Snapshot(
                pid: 2,
                start: 9,
                path: "/fixture",
                monotonicNS: 110,
                userTicks: 0,
                systemTicks: 0,
                residentBytes: 0
            ),
            Snapshot(
                pid: 1,
                start: 10,
                path: "/fixture",
                monotonicNS: 110,
                userTicks: 0,
                systemTicks: 0,
                residentBytes: 0
            ),
            Snapshot(
                pid: 1,
                start: 9,
                path: "/changed",
                monotonicNS: 110,
                userTicks: 0,
                systemTicks: 0,
                residentBytes: 0
            ),
            initial,
            Snapshot(pid: 1, start: 9, path: "/fixture", monotonicNS: 9, userTicks: 0, systemTicks: 0, residentBytes: 0)
        ]
        for snapshot in invalid {
            do {
                _ = try sample(from: initial, to: snapshot, nanosecondsPerTick: 1)
            } catch {
                continue
            }
            throw Failure("Invalid snapshot was accepted.")
        }
        do {
            _ = try sample(from: loaded, to: idle, nanosecondsPerTick: 1)
        } catch {
            return
        }
        throw Failure("Decreasing CPU counters were accepted.")
    }
}
