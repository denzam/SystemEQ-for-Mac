import Accelerate
import CoreAudio
import Foundation

enum AudioRoutingBackendPreference: String, CaseIterable {
    case automatic
    case native
    case blackHole
}

enum ActiveAudioRoutingBackend: String {
    case none
    case native
    case blackHole
}

struct ProcessTapInputSelection: Equatable {
    let bufferIndex: Int

    static func select(
        tapFormat: AudioStreamBasicDescription,
        aggregateFormats: [AudioStreamBasicDescription],
        aggregateChannelCounts: [UInt32],
        aggregateStartingChannels: [UInt32],
        physicalInputChannelCount: UInt32?
    ) -> ProcessTapInputSelection? {
        guard isSupported(tapFormat),
              aggregateFormats.count == aggregateChannelCounts.count else { return nil }

        let matches = aggregateFormats.indices.filter {
            aggregateChannelCounts[$0] == 2 && formatsMatch(aggregateFormats[$0], tapFormat)
        }
        if matches.count == 1 {
            return ProcessTapInputSelection(bufferIndex: matches[0])
        }

        guard aggregateStartingChannels.count == aggregateFormats.count,
              let physicalInputChannelCount else { return nil }
        let tapStartingChannel = physicalInputChannelCount + 1
        let boundaryMatches = matches.filter {
            aggregateStartingChannels[$0] == tapStartingChannel
        }
        guard boundaryMatches.count == 1 else { return nil }
        return ProcessTapInputSelection(bufferIndex: boundaryMatches[0])
    }

    private static func isSupported(_ format: AudioStreamBasicDescription) -> Bool {
        format.mFormatID == kAudioFormatLinearPCM &&
            format.mFormatFlags & kAudioFormatFlagIsFloat != 0 &&
            format.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0 &&
            format.mBitsPerChannel == 32 &&
            format.mChannelsPerFrame == 2
    }

    private static func formatsMatch(
        _ lhs: AudioStreamBasicDescription,
        _ rhs: AudioStreamBasicDescription
    ) -> Bool {
        lhs.mSampleRate == rhs.mSampleRate &&
            lhs.mFormatID == rhs.mFormatID &&
            lhs.mFormatFlags == rhs.mFormatFlags &&
            lhs.mBytesPerPacket == rhs.mBytesPerPacket &&
            lhs.mFramesPerPacket == rhs.mFramesPerPacket &&
            lhs.mBytesPerFrame == rhs.mBytesPerFrame &&
            lhs.mChannelsPerFrame == rhs.mChannelsPerFrame &&
            lhs.mBitsPerChannel == rhs.mBitsPerChannel
    }
}

@available(macOS 14.4, *)
final class ProcessTapEngine {
    struct StartInfo {
        let sampleRate: Double
        let bufferFrames: UInt32
    }

    enum StartError: Error {
        case deviceUID
        case createTap(OSStatus)
        case createAggregate(OSStatus)
        case unsupportedTopology
        case createIOProc(OSStatus)
        case startDevice(OSStatus)
    }

    private let processor: CoreAudioEngine
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var outputDeviceID = AudioDeviceID(kAudioObjectUnknown)
    private var sampleRateListener: AudioObjectPropertyListenerBlock?
    private var inputSelection = ProcessTapInputSelection(bufferIndex: 0)
    private let scratchLeft = UnsafeMutablePointer<Float>.allocate(capacity: 4096)
    private let scratchRight = UnsafeMutablePointer<Float>.allocate(capacity: 4096)
    private let scratchCapacity = 4096
    var onSampleRateChange: (() -> Void)?

    init(processor: CoreAudioEngine = .shared) {
        self.processor = processor
    }

    deinit {
        stop()
        scratchLeft.deallocate()
        scratchRight.deallocate()
    }

    func start(
        outputDeviceID: AudioDeviceID,
        prepareProcessing: (Double, UInt32) -> Void
    ) -> Result<StartInfo, StartError> {
        stop()
        self.outputDeviceID = outputDeviceID

        guard let deviceUID = stringProperty(outputDeviceID, selector: kAudioDevicePropertyDeviceUID) else {
            return .failure(.deviceUID)
        }

        let description = CATapDescription(
            stereoGlobalTapButExcludeProcesses: ownProcessObject().map { [$0] } ?? []
        )
        description.name = "SystemEQ Native Tap"
        description.muteBehavior = .mutedWhenTapped
        description.isPrivate = true

        var newTapID = AudioObjectID(kAudioObjectUnknown)
        var status = AudioHardwareCreateProcessTap(description, &newTapID)
        guard status == noErr, newTapID != kAudioObjectUnknown else {
            return .failure(.createTap(status))
        }
        tapID = newTapID

        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "SystemEQ Native",
            kAudioAggregateDeviceUIDKey: "com.denzam.SystemEQ.native.\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceMainSubDeviceKey: deviceUID,
            kAudioAggregateDeviceSubDeviceListKey: [[
                kAudioSubDeviceUIDKey: deviceUID,
                kAudioSubDeviceInputChannelsKey: 0
            ]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: description.uuid.uuidString,
                kAudioSubTapDriftCompensationKey: true
            ]],
            kAudioAggregateDeviceTapAutoStartKey: true
        ]

        var newAggregateID = AudioObjectID(kAudioObjectUnknown)
        status = AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &newAggregateID)
        guard status == noErr, newAggregateID != kAudioObjectUnknown else {
            cleanupTap()
            return .failure(.createAggregate(status))
        }
        aggregateID = newAggregateID

        guard let tapFormat = audioFormat(tapID, selector: kAudioTapPropertyFormat),
              let streams = inputStreams(aggregateID),
              let formats = streamFormats(streams),
              let channelCounts = inputStreamChannelCounts(aggregateID),
              let startingChannels = streamStartingChannels(streams),
              let selection = ProcessTapInputSelection.select(
                  tapFormat: tapFormat,
                  aggregateFormats: formats,
                  aggregateChannelCounts: channelCounts,
                  aggregateStartingChannels: startingChannels,
                  physicalInputChannelCount: inputChannelCount(outputDeviceID)
              ) else {
            cleanup()
            return .failure(.unsupportedTopology)
        }
        inputSelection = selection

        let sampleRate = nominalSampleRate(outputDeviceID)
        let bufferFrames = deviceBufferFrames(aggregateID)
        prepareProcessing(sampleRate, bufferFrames)

        status = AudioDeviceCreateIOProcID(
            aggregateID,
            processTapIOProc,
            Unmanaged.passUnretained(self).toOpaque(),
            &ioProcID
        )
        guard status == noErr, let ioProcID else {
            cleanup()
            return .failure(.createIOProc(status))
        }

        status = AudioDeviceStart(aggregateID, ioProcID)
        guard status == noErr else {
            cleanup()
            return .failure(.startDevice(status))
        }
        installSampleRateListener(sampleRate: sampleRate)
        return .success(StartInfo(sampleRate: sampleRate, bufferFrames: bufferFrames))
    }

    func stop() {
        cleanup()
    }

    private func cleanup() {
        removeSampleRateListener()
        if let ioProcID, aggregateID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
        }
        ioProcID = nil
        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        cleanupTap()
        outputDeviceID = AudioDeviceID(kAudioObjectUnknown)
    }

    private func installSampleRateListener(sampleRate: Double) {
        let deviceID = outputDeviceID
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self, self.nominalSampleRate(deviceID) != sampleRate else { return }
            self.onSampleRateChange?()
        }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectAddPropertyListenerBlock(deviceID, &address, .main, block) == noErr {
            sampleRateListener = block
        }
    }

    private func removeSampleRateListener() {
        guard let sampleRateListener, outputDeviceID != kAudioObjectUnknown else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(outputDeviceID, &address, .main, sampleRateListener)
        self.sampleRateListener = nil
    }

    private func cleanupTap() {
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    @inline(__always)
    fileprivate func render(
        input: UnsafePointer<AudioBufferList>,
        output: UnsafeMutablePointer<AudioBufferList>
    ) {
        let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let outputs = UnsafeMutableAudioBufferListPointer(output)
        guard inputSelection.bufferIndex < inputs.count else {
            zero(outputs)
            return
        }

        let tapBuffer = inputs[inputSelection.bufferIndex]
        guard tapBuffer.mNumberChannels == 2, let inputData = tapBuffer.mData else {
            zero(outputs)
            return
        }
        let frameCount = Int(tapBuffer.mDataByteSize) / (2 * MemoryLayout<Float>.size)
        guard frameCount > 0, frameCount <= scratchCapacity else {
            zero(outputs)
            return
        }

        let interleaved = inputData.assumingMemoryBound(to: Float.self)
        var zeroValue: Float = 0
        vDSP_vsadd(interleaved, 2, &zeroValue, scratchLeft, 1, vDSP_Length(frameCount))
        vDSP_vsadd(interleaved + 1, 2, &zeroValue, scratchRight, 1, vDSP_Length(frameCount))
        processor.generateProcessTapTestToneIfNeeded(
            left: scratchLeft,
            right: scratchRight,
            frameCount: frameCount
        )
        processor.processStereoInPlace(left: scratchLeft, right: scratchRight, frameCount: frameCount)

        var sourceChannel = 0
        for buffer in outputs {
            guard let outputData = buffer.mData else { continue }
            let channels = max(Int(buffer.mNumberChannels), 1)
            let outputFrames = Int(buffer.mDataByteSize) / (channels * MemoryLayout<Float>.size)
            let framesToCopy = min(frameCount, outputFrames)
            let destination = outputData.assumingMemoryBound(to: Float.self)
            for channel in 0..<channels {
                let source = sourceChannel.isMultiple(of: 2) ? scratchLeft : scratchRight
                vDSP_vsadd(
                    source,
                    1,
                    &zeroValue,
                    destination + channel,
                    vDSP_Stride(channels),
                    vDSP_Length(framesToCopy)
                )
                sourceChannel += 1
            }
            if outputFrames > framesToCopy {
                vDSP_vclr(
                    destination + framesToCopy * channels,
                    1,
                    vDSP_Length((outputFrames - framesToCopy) * channels)
                )
            }
        }
    }

    @inline(__always)
    private func zero(_ buffers: UnsafeMutableAudioBufferListPointer) {
        for buffer in buffers {
            guard let data = buffer.mData else { continue }
            memset(data, 0, Int(buffer.mDataByteSize))
        }
    }

    private func ownProcessObject() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var pid = getpid()
        var processObject = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            UInt32(MemoryLayout<pid_t>.size),
            &pid,
            &size,
            &processObject
        )
        return status == noErr && processObject != kAudioObjectUnknown ? processObject : nil
    }

    private func stringProperty(
        _ objectID: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &value) == noErr,
              let value else { return nil }
        return value.takeRetainedValue() as String
    }

    private func nominalSampleRate(_ deviceID: AudioDeviceID) -> Double {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var sampleRate = 48000.0
        var size = UInt32(MemoryLayout<Double>.size)
        _ = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &sampleRate)
        return sampleRate
    }

    private func deviceBufferFrames(_ deviceID: AudioDeviceID) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyBufferFrameSize,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var frames: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        _ = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &frames)
        return frames
    }

    private func audioFormat(
        _ objectID: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) -> AudioStreamBasicDescription? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &format) == noErr else { return nil }
        return format
    }

    private func inputStreams(_ deviceID: AudioDeviceID) -> [AudioObjectID]? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr else { return nil }
        var streams = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &streams) == noErr else { return nil }
        return streams
    }

    private func streamFormats(_ streams: [AudioObjectID]) -> [AudioStreamBasicDescription]? {
        var formats: [AudioStreamBasicDescription] = []
        formats.reserveCapacity(streams.count)
        for stream in streams {
            guard let format = audioFormat(stream, selector: kAudioStreamPropertyVirtualFormat) else { return nil }
            formats.append(format)
        }
        return formats
    }

    private func streamStartingChannels(_ streams: [AudioObjectID]) -> [UInt32]? {
        var channels: [UInt32] = []
        channels.reserveCapacity(streams.count)
        for stream in streams {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioStreamPropertyStartingChannel,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var channel: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            guard AudioObjectGetPropertyData(stream, &address, 0, nil, &size, &channel) == noErr else { return nil }
            channels.append(channel)
        }
        return channels
    }

    private func inputStreamChannelCounts(_ deviceID: AudioDeviceID) -> [UInt32]? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr, size > 0 else { return nil }
        let storage = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { storage.deallocate() }
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, storage) == noErr else { return nil }
        return UnsafeMutableAudioBufferListPointer(
            storage.assumingMemoryBound(to: AudioBufferList.self)
        ).map(\.mNumberChannels)
    }

    private func inputChannelCount(_ deviceID: AudioDeviceID) -> UInt32? {
        inputStreamChannelCounts(deviceID)?.reduce(0, +)
    }
}

@available(macOS 14.4, *)
private func processTapIOProc(
    inDevice: AudioObjectID,
    inNow: UnsafePointer<AudioTimeStamp>,
    inInputData: UnsafePointer<AudioBufferList>,
    inInputTime: UnsafePointer<AudioTimeStamp>,
    outOutputData: UnsafeMutablePointer<AudioBufferList>,
    inOutputTime: UnsafePointer<AudioTimeStamp>,
    inClientData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let inClientData else { return kAudioHardwareUnspecifiedError }
    let engine = Unmanaged<ProcessTapEngine>.fromOpaque(inClientData).takeUnretainedValue()
    engine.render(input: inInputData, output: outOutputData)
    return noErr
}
