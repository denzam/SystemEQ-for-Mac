import AudioToolbox
import CoreAudio
import Foundation

private struct Options {
    var outputMatch = "BlackHole 2ch"
    var inputMatch = "Scarlett"
    var trials = 10
    var intervalMilliseconds = 750.0
    var settleMilliseconds = 500.0
    var minimumLatencyMilliseconds = 1.0
    var maximumLatencyMilliseconds = 350.0
}

private struct DeviceInfo: Encodable {
    let id: AudioDeviceID
    let name: String
    let uid: String
    let sampleRate: Double
    let bufferFrames: UInt32
    let channels: UInt32
}

private struct TrialResult: Encodable {
    let trial: Int
    let latencyMilliseconds: Double
    let correlation: Double
    let inputChannel: Int
}

private struct Statistics: Encodable {
    let medianMilliseconds: Double
    let p95Milliseconds: Double
    let p99Milliseconds: Double
    let minimumMilliseconds: Double
    let maximumMilliseconds: Double
}

private struct CaptureDiagnostics: Encodable {
    let inputFrames: Int
    let inputSegments: Int
    let inputSegmentOverflows: Int
    let inputCallbackFrames: [Int]
    let outputCallbackFrames: [Int]
}

private struct Report: Encodable {
    let schemaVersion = 1
    let date: Date
    let operatingSystem: String
    let method: String
    let outputDevice: DeviceInfo
    let inputDevice: DeviceInfo
    let markerFrames: Int
    let markerAmplitude: Float
    let requestedTrials: Int
    let validTrials: Int
    let rejectedTrials: Int
    let minimumAcceptedCorrelation: Double
    let searchWindowMilliseconds: [Double]
    let capture: CaptureDiagnostics
    let trials: [TrialResult]
    let statistics: Statistics
}

private final class InputState {
    let capacityFrames: Int
    let capturedChannels: Int
    let samples: UnsafeMutablePointer<Float>
    let segmentCapacity: Int
    let segmentStartFrames: UnsafeMutablePointer<Int64>
    let segmentFrameCounts: UnsafeMutablePointer<Int32>
    let segmentHostTimes: UnsafeMutablePointer<UInt64>
    let segmentRateScalars: UnsafeMutablePointer<Double>
    var writtenFrames = 0
    var segmentCount = 0
    var segmentOverflowCount = 0
    var invalidTimestampCount = 0
    var minimumCallbackFrames = Int.max
    var maximumCallbackFrames = 0

    init(capacityFrames: Int, capturedChannels: Int, segmentCapacity: Int) {
        self.capacityFrames = capacityFrames
        self.capturedChannels = capturedChannels
        self.segmentCapacity = segmentCapacity
        samples = .allocate(capacity: capacityFrames * capturedChannels)
        samples.initialize(repeating: 0, count: capacityFrames * capturedChannels)
        segmentStartFrames = .allocate(capacity: segmentCapacity)
        segmentFrameCounts = .allocate(capacity: segmentCapacity)
        segmentHostTimes = .allocate(capacity: segmentCapacity)
        segmentRateScalars = .allocate(capacity: segmentCapacity)
    }

    deinit {
        samples.deallocate()
        segmentStartFrames.deallocate()
        segmentFrameCounts.deallocate()
        segmentHostTimes.deallocate()
        segmentRateScalars.deallocate()
    }
}

private final class OutputState {
    let marker: UnsafeMutablePointer<Float>
    let markerFrames: Int
    let intervalFrames: Int64
    let requestedTrials: Int
    let eventHostTimes: UnsafeMutablePointer<UInt64>
    let eventFrameOffsets: UnsafeMutablePointer<Int32>
    let eventRateScalars: UnsafeMutablePointer<Double>
    var totalFrames: Int64 = 0
    var nextEventFrame: Int64 = 0
    var markerPosition = -1
    var eventCount = 0
    var invalidTimestampCount = 0
    var minimumCallbackFrames = Int.max
    var maximumCallbackFrames = 0

    init(marker: [Float], intervalFrames: Int64, requestedTrials: Int) {
        markerFrames = marker.count
        self.intervalFrames = intervalFrames
        self.requestedTrials = requestedTrials
        self.marker = .allocate(capacity: marker.count)
        self.marker.initialize(from: marker, count: marker.count)
        eventHostTimes = .allocate(capacity: requestedTrials)
        eventFrameOffsets = .allocate(capacity: requestedTrials)
        eventRateScalars = .allocate(capacity: requestedTrials)
    }

    deinit {
        marker.deallocate()
        eventHostTimes.deallocate()
        eventFrameOffsets.deallocate()
        eventRateScalars.deallocate()
    }
}

private func inputIOProc(
    inDevice _: AudioObjectID,
    inNow _: UnsafePointer<AudioTimeStamp>,
    inInputData inputData: UnsafePointer<AudioBufferList>,
    inInputTime inputTime: UnsafePointer<AudioTimeStamp>,
    outOutputData _: UnsafeMutablePointer<AudioBufferList>,
    inOutputTime _: UnsafePointer<AudioTimeStamp>,
    inClientData clientData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let clientData else { return noErr }
    let state = Unmanaged<InputState>.fromOpaque(clientData).takeUnretainedValue()
    let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
    var callbackFrames = Int.max
    for buffer in buffers where buffer.mNumberChannels > 0 && buffer.mData != nil {
        callbackFrames = min(
            callbackFrames,
            Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * Int(buffer.mNumberChannels))
        )
    }
    guard callbackFrames != Int.max else { return noErr }
    let frames = min(callbackFrames, state.capacityFrames - state.writtenFrames)
    guard frames > 0 else { return noErr }
    state.minimumCallbackFrames = min(state.minimumCallbackFrames, callbackFrames)
    state.maximumCallbackFrames = max(state.maximumCallbackFrames, callbackFrames)

    if state.segmentCount < state.segmentCapacity {
        let index = state.segmentCount
        state.segmentStartFrames[index] = Int64(state.writtenFrames)
        state.segmentFrameCounts[index] = Int32(frames)
        if inputTime.pointee.mFlags.contains(.hostTimeValid) {
            state.segmentHostTimes[index] = inputTime.pointee.mHostTime
            state.segmentRateScalars[index] = inputTime.pointee.mFlags.contains(.rateScalarValid)
                ? inputTime.pointee.mRateScalar : 1
        } else {
            state.segmentHostTimes[index] = 0
            state.segmentRateScalars[index] = 1
            state.invalidTimestampCount += 1
        }
        state.segmentCount += 1
    } else {
        state.segmentOverflowCount += 1
    }

    var globalChannel = 0
    for buffer in buffers {
        let channels = Int(buffer.mNumberChannels)
        guard channels > 0, let data = buffer.mData?.assumingMemoryBound(to: Float.self) else {
            globalChannel += channels
            continue
        }
        for localChannel in 0..<channels where globalChannel + localChannel < state.capturedChannels {
            let destination = state.samples + (globalChannel + localChannel) * state.capacityFrames + state.writtenFrames
            for frame in 0..<frames {
                destination[frame] = data[frame * channels + localChannel]
            }
        }
        globalChannel += channels
    }
    state.writtenFrames += frames
    return noErr
}

private func outputIOProc(
    inDevice _: AudioObjectID,
    inNow _: UnsafePointer<AudioTimeStamp>,
    inInputData _: UnsafePointer<AudioBufferList>,
    inInputTime _: UnsafePointer<AudioTimeStamp>,
    outOutputData outputData: UnsafeMutablePointer<AudioBufferList>,
    inOutputTime outputTime: UnsafePointer<AudioTimeStamp>,
    inClientData clientData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let clientData else { return noErr }
    let state = Unmanaged<OutputState>.fromOpaque(clientData).takeUnretainedValue()
    let buffers = UnsafeMutableAudioBufferListPointer(outputData)
    var frames = Int.max
    for buffer in buffers where buffer.mNumberChannels > 0 && buffer.mData != nil {
        frames = min(
            frames,
            Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * Int(buffer.mNumberChannels))
        )
    }
    guard frames != Int.max, frames > 0 else { return noErr }
    state.minimumCallbackFrames = min(state.minimumCallbackFrames, frames)
    state.maximumCallbackFrames = max(state.maximumCallbackFrames, frames)

    for buffer in buffers {
        guard let data = buffer.mData else { continue }
        memset(data, 0, Int(buffer.mDataByteSize))
    }

    for frame in 0..<frames {
        let absoluteFrame = state.totalFrames + Int64(frame)
        if state.markerPosition < 0,
           state.eventCount < state.requestedTrials,
           absoluteFrame >= state.nextEventFrame {
            if outputTime.pointee.mFlags.contains(.hostTimeValid) {
                let event = state.eventCount
                state.eventHostTimes[event] = outputTime.pointee.mHostTime
                state.eventFrameOffsets[event] = Int32(frame)
                state.eventRateScalars[event] = outputTime.pointee.mFlags.contains(.rateScalarValid)
                    ? outputTime.pointee.mRateScalar : 1
                state.markerPosition = 0
                state.eventCount += 1
                state.nextEventFrame += state.intervalFrames
            } else {
                state.invalidTimestampCount += 1
            }
        }
        guard state.markerPosition >= 0 else { continue }
        let value = state.marker[state.markerPosition]
        for buffer in buffers {
            let channels = Int(buffer.mNumberChannels)
            guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            for channel in 0..<channels {
                data[frame * channels + channel] = value
            }
        }
        state.markerPosition += 1
        if state.markerPosition == state.markerFrames {
            state.markerPosition = -1
        }
    }
    state.totalFrames += Int64(frames)
    return noErr
}

@main
private struct LoopbackLatencyProbe {
    static func main() {
        do {
            try run()
        } catch {
            FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }

    private static func run() throws {
        let options = try parseOptions()
        let output = try findDevice(matching: options.outputMatch, scope: kAudioDevicePropertyScopeOutput)
        let input = try findDevice(matching: options.inputMatch, scope: kAudioDevicePropertyScopeInput)
        try validateFloat32Streams(deviceID: output.id, scope: kAudioDevicePropertyScopeOutput)
        try validateFloat32Streams(deviceID: input.id, scope: kAudioDevicePropertyScopeInput)
        guard abs(output.sampleRate - input.sampleRate) < 0.5 else {
            throw failure("Sample rates differ: \(output.name) \(output.sampleRate) Hz, \(input.name) \(input.sampleRate) Hz")
        }

        let sampleRate = output.sampleRate
        let markerAmplitude: Float = 0.1
        let marker = makeMarker(frames: 2047, amplitude: markerAmplitude)
        let intervalFrames = Int64((options.intervalMilliseconds * sampleRate / 1000).rounded())
        let runSeconds = Double(options.trials - 1) * options.intervalMilliseconds / 1000
            + Double(marker.count) / sampleRate + options.maximumLatencyMilliseconds / 1000 + 0.25
        let totalCaptureSeconds = options.settleMilliseconds / 1000 + runSeconds + 0.25
        let captureFrames = Int((totalCaptureSeconds * input.sampleRate).rounded(.up))
        let segmentCapacity = captureFrames / 16 + 2048
        let inputState = InputState(
            capacityFrames: captureFrames,
            capturedChannels: min(Int(input.channels), 2),
            segmentCapacity: segmentCapacity
        )
        let outputState = OutputState(marker: marker, intervalFrames: intervalFrames, requestedTrials: options.trials)

        var inputProcID: AudioDeviceIOProcID?
        var outputProcID: AudioDeviceIOProcID?
        var inputStarted = false
        var outputStarted = false
        defer {
            if outputStarted, let outputProcID { AudioDeviceStop(output.id, outputProcID) }
            if inputStarted, let inputProcID { AudioDeviceStop(input.id, inputProcID) }
            if let outputProcID { AudioDeviceDestroyIOProcID(output.id, outputProcID) }
            if let inputProcID { AudioDeviceDestroyIOProcID(input.id, inputProcID) }
        }

        var status = AudioDeviceCreateIOProcID(
            input.id,
            inputIOProc,
            Unmanaged.passUnretained(inputState).toOpaque(),
            &inputProcID
        )
        try require(status, operation: "create input IOProc")
        status = AudioDeviceCreateIOProcID(
            output.id,
            outputIOProc,
            Unmanaged.passUnretained(outputState).toOpaque(),
            &outputProcID
        )
        try require(status, operation: "create output IOProc")
        guard let inputProcID, let outputProcID else { throw failure("CoreAudio returned an empty IOProc") }

        status = AudioDeviceStart(input.id, inputProcID)
        try require(status, operation: "start input device")
        inputStarted = true
        Thread.sleep(forTimeInterval: options.settleMilliseconds / 1000)
        status = AudioDeviceStart(output.id, outputProcID)
        try require(status, operation: "start output device")
        outputStarted = true
        Thread.sleep(forTimeInterval: runSeconds)
        status = AudioDeviceStop(output.id, outputProcID)
        try require(status, operation: "stop output device")
        outputStarted = false
        Thread.sleep(forTimeInterval: options.maximumLatencyMilliseconds / 1000 + 0.1)
        status = AudioDeviceStop(input.id, inputProcID)
        try require(status, operation: "stop input device")
        inputStarted = false

        guard inputState.invalidTimestampCount == 0,
              outputState.invalidTimestampCount == 0,
              inputState.segmentOverflowCount == 0
        else {
            throw failure(
                "Capture integrity failure: input timestamps \(inputState.invalidTimestampCount), "
                    + "output timestamps \(outputState.invalidTimestampCount), segment overflows \(inputState.segmentOverflowCount)"
            )
        }
        guard outputState.eventCount == options.trials else {
            throw failure("Generated \(outputState.eventCount) of \(options.trials) markers")
        }

        let minimumCorrelation = 0.3
        let candidates = measureTrials(
            input: inputState,
            output: outputState,
            marker: marker,
            sampleRate: sampleRate,
            minimumLatencyMilliseconds: options.minimumLatencyMilliseconds,
            maximumLatencyMilliseconds: options.maximumLatencyMilliseconds,
            minimumCorrelation: 0
        )
        let results = candidates.filter { $0.correlation >= minimumCorrelation }
        guard !results.isEmpty else {
            let peaks = inputPeaks(inputState).map { String(format: "%.4f", $0) }.joined(separator: ", ")
            let best = candidates.map(\.correlation).max() ?? 0
            throw failure(
                "No loopback marker detected; input peaks [\(peaks)], best correlation \(String(format: "%.4f", best))"
            )
        }
        let latencies = results.map(\.latencyMilliseconds).sorted()
        let report = Report(
            date: Date(),
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            method: "CoreAudio device IOProc host timestamps with offline normalized cross-correlation",
            outputDevice: output,
            inputDevice: input,
            markerFrames: marker.count,
            markerAmplitude: markerAmplitude,
            requestedTrials: options.trials,
            validTrials: results.count,
            rejectedTrials: options.trials - results.count,
            minimumAcceptedCorrelation: minimumCorrelation,
            searchWindowMilliseconds: [options.minimumLatencyMilliseconds, options.maximumLatencyMilliseconds],
            capture: CaptureDiagnostics(
                inputFrames: inputState.writtenFrames,
                inputSegments: inputState.segmentCount,
                inputSegmentOverflows: inputState.segmentOverflowCount,
                inputCallbackFrames: [inputState.minimumCallbackFrames, inputState.maximumCallbackFrames],
                outputCallbackFrames: [outputState.minimumCallbackFrames, outputState.maximumCallbackFrames]
            ),
            trials: results,
            statistics: Statistics(
                medianMilliseconds: percentile(latencies, 0.5),
                p95Milliseconds: percentile(latencies, 0.95),
                p99Milliseconds: percentile(latencies, 0.99),
                minimumMilliseconds: latencies[0],
                maximumMilliseconds: latencies[latencies.count - 1]
            )
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        FileHandle.standardOutput.write(try encoder.encode(report))
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    private static func parseOptions() throws -> Options {
        var options = Options()
        var index = 1
        let arguments = CommandLine.arguments
        while index < arguments.count {
            let option = arguments[index]
            if option == "--help" {
                print("Usage: measure-loopback-latency [--output NAME] [--input NAME] [--trials 3...50] [--interval-ms 200...2000] [--settle-ms 100...5000] [--min-latency-ms 0...100] [--max-latency-ms 20...1000]")
                exit(EXIT_SUCCESS)
            }
            guard index + 1 < arguments.count else { throw failure("Missing value for \(option)") }
            let value = arguments[index + 1]
            switch option {
            case "--output": options.outputMatch = value
            case "--input": options.inputMatch = value
            case "--trials":
                guard let parsed = Int(value), (3...50).contains(parsed) else { throw failure("Invalid --trials") }
                options.trials = parsed
            case "--interval-ms":
                guard let parsed = Double(value), (200...2000).contains(parsed) else { throw failure("Invalid --interval-ms") }
                options.intervalMilliseconds = parsed
            case "--settle-ms":
                guard let parsed = Double(value), (100...5000).contains(parsed) else { throw failure("Invalid --settle-ms") }
                options.settleMilliseconds = parsed
            case "--min-latency-ms":
                guard let parsed = Double(value), (0...100).contains(parsed) else { throw failure("Invalid --min-latency-ms") }
                options.minimumLatencyMilliseconds = parsed
            case "--max-latency-ms":
                guard let parsed = Double(value), (20...1000).contains(parsed) else { throw failure("Invalid --max-latency-ms") }
                options.maximumLatencyMilliseconds = parsed
            default: throw failure("Unknown option \(option)")
            }
            index += 2
        }
        guard options.minimumLatencyMilliseconds < options.maximumLatencyMilliseconds else {
            throw failure("Minimum latency must be lower than maximum latency")
        }
        return options
    }

    private static func findDevice(matching query: String, scope: AudioObjectPropertyScope) throws -> DeviceInfo {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        try require(
            AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size),
            operation: "read audio device list size"
        )
        var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        try require(
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices),
            operation: "read audio device list"
        )
        let candidates = devices.compactMap { deviceInfo($0, scope: scope) }.filter { $0.channels > 0 }
        let exact = candidates.first { $0.name.caseInsensitiveCompare(query) == .orderedSame || $0.uid == query }
        if let exact { return exact }
        if let partial = candidates.first(where: { $0.name.localizedCaseInsensitiveContains(query) }) { return partial }
        let names = candidates.map(\.name).joined(separator: ", ")
        throw failure("No device matching '\(query)'. Available: \(names)")
    }

    private static func deviceInfo(_ id: AudioDeviceID, scope: AudioObjectPropertyScope) -> DeviceInfo? {
        guard let name = stringProperty(id, selector: kAudioObjectPropertyName),
              let uid = stringProperty(id, selector: kAudioDevicePropertyDeviceUID),
              let sampleRate: Double = scalarProperty(id, selector: kAudioDevicePropertyNominalSampleRate),
              let bufferFrames: UInt32 = scalarProperty(id, selector: kAudioDevicePropertyBufferFrameSize),
              let channels = channelCount(id, scope: scope)
        else { return nil }
        return DeviceInfo(
            id: id,
            name: name,
            uid: uid,
            sampleRate: sampleRate,
            bufferFrames: bufferFrames,
            channels: channels
        )
    }

    private static func stringProperty(_ id: AudioObjectID, selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    private static func scalarProperty<T>(_ id: AudioObjectID, selector: AudioObjectPropertySelector) -> T? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let pointer = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { pointer.deallocate() }
        var size = UInt32(MemoryLayout<T>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, pointer) == noErr else { return nil }
        return pointer.move()
    }

    private static func channelCount(_ id: AudioDeviceID, scope: AudioObjectPropertyScope) -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return nil }
        let storage = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { storage.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, storage) == noErr else { return nil }
        return UnsafeMutableAudioBufferListPointer(storage.assumingMemoryBound(to: AudioBufferList.self))
            .reduce(0) { $0 + $1.mNumberChannels }
    }

    private static func validateFloat32Streams(deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) throws {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        try require(AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size), operation: "read stream list size")
        var streams = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        try require(AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &streams), operation: "read stream list")
        guard !streams.isEmpty else { throw failure("Device has no streams in the requested scope") }
        for stream in streams {
            var formatAddress = AudioObjectPropertyAddress(
                mSelector: kAudioStreamPropertyVirtualFormat,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var format = AudioStreamBasicDescription()
            var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            try require(
                AudioObjectGetPropertyData(stream, &formatAddress, 0, nil, &formatSize, &format),
                operation: "read stream format"
            )
            guard format.mFormatID == kAudioFormatLinearPCM,
                  format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
                  format.mBitsPerChannel == 32
            else {
                throw failure("Device stream is not Float32 linear PCM")
            }
        }
    }

    private static func makeMarker(frames: Int, amplitude: Float) -> [Float] {
        var state: UInt32 = 0xA5A5_1F3D
        return (0..<frames).map { _ in
            state ^= state << 13
            state ^= state >> 17
            state ^= state << 5
            return state & 1 == 0 ? -amplitude : amplitude
        }
    }

    private static func inputPeaks(_ input: InputState) -> [Float] {
        (0..<input.capturedChannels).map { channel in
            let samples = input.samples + channel * input.capacityFrames
            var peak: Float = 0
            for frame in 0..<input.writtenFrames {
                peak = max(peak, abs(samples[frame]))
            }
            return peak
        }
    }

    private static func measureTrials(
        input: InputState,
        output: OutputState,
        marker: [Float],
        sampleRate: Double,
        minimumLatencyMilliseconds: Double,
        maximumLatencyMilliseconds: Double,
        minimumCorrelation: Double
    ) -> [TrialResult] {
        let markerEnergy = marker.reduce(0) { $0 + Double($1 * $1) }
        var results: [TrialResult] = []
        for trial in 0..<output.eventCount {
            let outputNanos = timestampNanos(
                hostTime: output.eventHostTimes[trial],
                frameOffset: Int(output.eventFrameOffsets[trial]),
                sampleRate: sampleRate,
                rateScalar: output.eventRateScalars[trial]
            )
            let startNanos = outputNanos + minimumLatencyMilliseconds * 1_000_000
            let endNanos = outputNanos + maximumLatencyMilliseconds * 1_000_000
            guard let firstFrame = frameIndex(atOrAfter: startNanos, input: input, sampleRate: sampleRate),
                  let lastFrame = frameIndex(atOrAfter: endNanos, input: input, sampleRate: sampleRate)
            else { continue }
            let upperBound = min(lastFrame, input.writtenFrames - marker.count)
            guard firstFrame <= upperBound else { continue }
            var bestCorrelation = 0.0
            var bestFrame = firstFrame
            var bestChannel = 0
            for channel in 0..<input.capturedChannels {
                let channelSamples = input.samples + channel * input.capacityFrames
                for frame in firstFrame...upperBound {
                    var dot = 0.0
                    var signalEnergy = 0.0
                    for markerFrame in marker.indices {
                        let sample = Double(channelSamples[frame + markerFrame])
                        dot += sample * Double(marker[markerFrame])
                        signalEnergy += sample * sample
                    }
                    guard signalEnergy > 0 else { continue }
                    let correlation = abs(dot) / sqrt(signalEnergy * markerEnergy)
                    if correlation > bestCorrelation {
                        bestCorrelation = correlation
                        bestFrame = frame
                        bestChannel = channel
                    }
                }
            }
            guard bestCorrelation >= minimumCorrelation,
                  let inputNanos = timestampNanos(forFrame: bestFrame, input: input, sampleRate: sampleRate)
            else { continue }
            results.append(TrialResult(
                trial: trial + 1,
                latencyMilliseconds: (inputNanos - outputNanos) / 1_000_000,
                correlation: bestCorrelation,
                inputChannel: bestChannel + 1
            ))
        }
        return results
    }

    private static func frameIndex(atOrAfter targetNanos: Double, input: InputState, sampleRate: Double) -> Int? {
        for segment in 0..<input.segmentCount {
            let hostTime = input.segmentHostTimes[segment]
            guard hostTime != 0 else { continue }
            let start = Double(AudioConvertHostTimeToNanos(hostTime))
            let frames = Int(input.segmentFrameCounts[segment])
            let nanosPerFrame = 1_000_000_000 * input.segmentRateScalars[segment] / sampleRate
            let end = start + Double(frames) * nanosPerFrame
            if targetNanos <= end {
                let offset = max(0, Int(floor((targetNanos - start) / nanosPerFrame)))
                return min(Int(input.segmentStartFrames[segment]) + offset, input.writtenFrames)
            }
        }
        return nil
    }

    private static func timestampNanos(forFrame frame: Int, input: InputState, sampleRate: Double) -> Double? {
        for segment in 0..<input.segmentCount {
            let startFrame = Int(input.segmentStartFrames[segment])
            let frameCount = Int(input.segmentFrameCounts[segment])
            if frame >= startFrame, frame < startFrame + frameCount {
                return timestampNanos(
                    hostTime: input.segmentHostTimes[segment],
                    frameOffset: frame - startFrame,
                    sampleRate: sampleRate,
                    rateScalar: input.segmentRateScalars[segment]
                )
            }
        }
        return nil
    }

    private static func timestampNanos(
        hostTime: UInt64,
        frameOffset: Int,
        sampleRate: Double,
        rateScalar: Double
    ) -> Double {
        Double(AudioConvertHostTimeToNanos(hostTime))
            + Double(frameOffset) * 1_000_000_000 * rateScalar / sampleRate
    }

    private static func percentile(_ sorted: [Double], _ fraction: Double) -> Double {
        guard sorted.count > 1 else { return sorted[0] }
        let position = fraction * Double(sorted.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = Int(position.rounded(.up))
        let weight = position - Double(lower)
        return sorted[lower] * (1 - weight) + sorted[upper] * weight
    }

    private static func require(_ status: OSStatus, operation: String) throws {
        guard status == noErr else { throw failure("Failed to \(operation), OSStatus \(status)") }
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "LoopbackLatencyProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
