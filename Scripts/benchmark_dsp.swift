import Darwin
import Foundation

// MARK: - Offline DSP Benchmark

@main
struct DSPBenchmark {
    struct Measurement: Encodable {
        let workload: String
        let activeBands: Int
        let bufferFrames: Int
        let trial: Int
        let threadCPUPercentOfOneCore: Double
        let processingMicrosecondsP50: Double
        let processingMicrosecondsP95: Double
        let processingMicrosecondsP99: Double
        let processingMicrosecondsMax: Double
        let bufferDeadlineMicroseconds: Double
        let blocksOverDeadline: Int
        let minimumLimiterGain: Float
        let outputChecksum: Double
    }

    struct Report: Encodable {
        let schemaVersion = 1
        let date: Date
        let operatingSystem: String
        let processorCount: Int
        let sampleRate: Int
        let iterationsPerTrial: Int
        let warmupIterations: Int
        let trials: Int
        let scope: String
        let measurements: [Measurement]
    }

    enum Workload: String, CaseIterable {
        case copyOnly = "copy-only-baseline"
        case flat
        case tenBands = "10-active-peaks"
        case thirtyOneBands = "31-active-peaks"
        case limiter = "31-active-peaks-limiter"

        var frequencies: [Float] {
            switch self {
            case .copyOnly,
                 .flat: []
            case .tenBands: AutoEQConstants.tenBandFrequencies
            case .limiter,
                 .thirtyOneBands: AutoEQConstants.thirtyOneBandFrequencies
            }
        }

        var bands: [ParametricBand] {
            frequencies.enumerated().map { index, frequency in
                ParametricBand(
                    frequency: frequency,
                    gain: index.isMultiple(of: 2) ? 3 : -3,
                    q: self == .tenBands ? 1.4 : 2
                )
            }
        }
    }

    static func main() {
        do {
            try run()
        } catch {
            try? FileHandle.standardError.write(contentsOf: Data("\(error.localizedDescription)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }

    static func run() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments == ["--help"] {
            try write("Usage: benchmark-dsp [iterations-per-trial: 100...100000] [trials: 1...10]\n")
            return
        }
        guard arguments.count <= 2,
              let iterations = Int(arguments.first ?? "10000"), (100...100_000).contains(iterations),
              let trials = Int(arguments.dropFirst().first ?? "3"), (1...10).contains(trials)
        else {
            throw NSError(domain: "DSPBenchmark", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Invalid arguments; use --help."
            ])
        }

        let sampleRate = 48000
        let warmupIterations = 512
        var measurements: [Measurement] = []
        for frames in [128, 256, 512] {
            for trial in 1...trials {
                let workloads = Array(Workload.allCases.dropFirst(trial % Workload.allCases.count)) +
                    Array(Workload.allCases.prefix(trial % Workload.allCases.count))
                for workload in workloads {
                    try measurements.append(measure(
                        workload: workload,
                        frameCount: frames,
                        sampleRate: sampleRate,
                        iterations: iterations,
                        warmupIterations: warmupIterations,
                        trial: trial
                    ))
                }
            }
        }

        let report = Report(
            date: Date(),
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            processorCount: ProcessInfo.processInfo.processorCount,
            sampleRate: sampleRate,
            iterationsPerTrial: iterations,
            warmupIterations: warmupIterations,
            trials: trials,
            scope: "Offline synthetic stereo workload using production BiquadFilterVDSP. CPU is thread time / " +
                "simulated audio duration, including input copies and timing overhead. Wall percentiles cover " +
                "only processStereo plus clock overhead. No pacing, routing, meter, UI or ProjectM. " +
                "Peak-only workloads do not reproduce the app's mixed shelf/peak 10-band policy. " +
                "These are processing costs, not end-to-end audio latency or whole-app CPU.",
            measurements: measurements
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try FileHandle.standardOutput.write(contentsOf: encoder.encode(report))
        try write("\n")
    }

    static func measure(
        workload: Workload,
        frameCount: Int,
        sampleRate: Int,
        iterations: Int,
        warmupIterations: Int,
        trial: Int
    ) throws -> Measurement {
        let filter = BiquadFilterVDSP(sampleRate: Float(sampleRate))
        let bands = workload.bands
        filter.configure(
            bands: bands,
            preamp: 0,
            outputBoost: workload == .limiter ? 12 : 0,
            sampleRate: Float(sampleRate)
        )
        let sourceCount = frameCount * 64
        let source = UnsafeMutablePointer<Float>.allocate(capacity: sourceCount)
        let left = UnsafeMutablePointer<Float>.allocate(capacity: frameCount)
        let right = UnsafeMutablePointer<Float>.allocate(capacity: frameCount)
        defer {
            source.deallocate()
            left.deallocate()
            right.deallocate()
        }
        var seed: UInt32 = 42
        for index in 0..<sourceCount {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            let value = (Float(seed >> 8) / Float(0x00FF_FFFF) * 2 - 1) * 0.05
            source[index] = workload == .limiter ? value * 15 : value
        }
        let byteCount = frameCount * MemoryLayout<Float>.stride
        for index in 0..<warmupIterations {
            let offset = (index % 64) * frameCount
            memcpy(left, source.advanced(by: offset), byteCount)
            memcpy(right, source.advanced(by: offset), byteCount)
            if workload != .copyOnly {
                filter.processStereo(left, right, frameCount: frameCount)
            }
        }

        var durations = [UInt64](repeating: 0, count: iterations)
        var minimumLimiterGain: Float = 1
        var checksum = 0.0
        let cpuStart = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
        for index in 0..<iterations {
            let offset = ((warmupIterations + index) % 64) * frameCount
            memcpy(left, source.advanced(by: offset), byteCount)
            memcpy(right, source.advanced(by: offset), byteCount)
            let start = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
            let limiterGain = workload == .copyOnly ? 1 : filter.processStereo(left, right, frameCount: frameCount)
            durations[index] = clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - start
            minimumLimiterGain = min(minimumLimiterGain, limiterGain)
            checksum += Double(left[0]) + Double(right[frameCount - 1])
        }
        let cpuNanoseconds = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - cpuStart
        guard checksum.isFinite, cpuNanoseconds > 0,
              workload != .limiter || minimumLimiterGain < 0.9999
        else {
            throw NSError(domain: "DSPBenchmark", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Invalid output or inactive limiter for \(workload.rawValue)."
            ])
        }
        durations.sort()
        let deadline = Double(frameCount) / Double(sampleRate) * 1_000_000
        func percentile(_ fraction: Double) -> Double {
            Double(durations[Int(ceil(Double(iterations) * fraction)) - 1]) / 1000
        }

        return Measurement(
            workload: workload.rawValue,
            activeBands: bands.count,
            bufferFrames: frameCount,
            trial: trial,
            threadCPUPercentOfOneCore: Double(cpuNanoseconds) / 1_000_000_000 /
                (Double(frameCount) * Double(iterations) / Double(sampleRate)) * 100,
            processingMicrosecondsP50: percentile(0.50),
            processingMicrosecondsP95: percentile(0.95),
            processingMicrosecondsP99: percentile(0.99),
            processingMicrosecondsMax: Double(durations.last ?? 0) / 1000,
            bufferDeadlineMicroseconds: deadline,
            blocksOverDeadline: durations.filter { Double($0) / 1000 > deadline }.count,
            minimumLimiterGain: minimumLimiterGain,
            outputChecksum: checksum
        )
    }

    static func write(_ value: String) throws {
        try FileHandle.standardOutput.write(contentsOf: Data(value.utf8))
    }
}
