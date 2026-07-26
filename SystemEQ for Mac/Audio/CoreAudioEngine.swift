//
//  CoreAudioEngine.swift
//  SystemEQ for Mac
//
//  Core Audio (AudioUnit/AUHAL) based audio processing
//  Direct buffer access for lower latency and better control
//  Updated: CoreAudioEngine + AVAudioUnitEQ hybrid approach
//

import Accelerate
import AudioToolbox
import AVFoundation
import Combine
import CoreAudio
import Foundation

/// Core Audio based audio processing engine
/// Uses AudioUnit (AUHAL) for direct hardware access
public final class CoreAudioEngine: ObservableObject {
    // MARK: - Published Properties

    @Published public var isRunning: Bool = false
    @Published public var isEnabled: Bool = true

    /// Peak meter (extracted for modularity)
    let peakMeter = PeakMeter()

    /// Convenience accessors for SwiftUI bindings (delegates to peakMeter)
    public var inputPeakLevel: Float {
        get { peakMeter.inputPeakLevel }
        set { peakMeter.inputPeakLevel = newValue }
    }

    public var outputPeakLevel: Float {
        get { peakMeter.outputPeakLevel }
        set { peakMeter.outputPeakLevel = newValue }
    }

    // MARK: - Private Properties

    // Two-device I/O
    fileprivate var inputUnit: AudioUnit?
    fileprivate var outputUnit: AudioUnit?
    private var isSetupComplete = false
    private var inputDeviceID: AudioDeviceID = 0
    private var outputDeviceID: AudioDeviceID = 0

    private var originalDeviceSampleRates: [String: Double] = [:]
    private let originalDeviceSampleRatesKey = "originalDeviceSampleRates"

    /// Public read-only accessors for device IDs (used by AudioRouter to skip redundant restarts)
    public var currentInputDeviceID: AudioDeviceID {
        inputDeviceID
    }

    public var currentOutputDeviceID: AudioDeviceID {
        outputDeviceID
    }

    // EQ processing — lock-free filter swap via C11 atomic pointer.
    // Audio thread: acquire-load published pointer, use it for one callback.
    // UI thread: release-store new pointer; retire old filter on the next
    // main-queue tick so ARC never frees a reference the audio thread holds.

    private var _filterChain: BiquadFilterChain?
    var filterChain: BiquadFilterChain? {
        get { _filterChain }
        set { _filterChain = newValue }
    }

    private var useVDSPFilter: Bool = true

    private var _vdspFilterStrong: BiquadFilterVDSP?
    private var retiredVDSPFilters: [BiquadFilterVDSP] = []

    private let _vdspFilterAtomic: UnsafeMutablePointer<SEQAtomicPtr> = {
        let p = UnsafeMutablePointer<SEQAtomicPtr>.allocate(capacity: 1)
        seq_atomic_ptr_init(p, nil)
        return p
    }()
    private let _vdspFilterReaders: UnsafeMutablePointer<SEQAtomicInt32> = {
        let p = UnsafeMutablePointer<SEQAtomicInt32>.allocate(capacity: 1)
        seq_atomic_int32_init(p, 0)
        return p
    }()

    @inline(__always)
    fileprivate func currentVDSPFilter() -> BiquadFilterVDSP? {
        guard let p = seq_atomic_ptr_load_seq_cst(_vdspFilterAtomic) else { return nil }
        return Unmanaged<BiquadFilterVDSP>.fromOpaque(p).takeUnretainedValue()
    }

    @inline(__always)
    fileprivate func beginVDSPFilterRead() {
        _ = seq_atomic_int32_fetch_add_seq_cst(_vdspFilterReaders, 1)
    }

    @inline(__always)
    fileprivate func endVDSPFilterRead() {
        _ = seq_atomic_int32_fetch_add_seq_cst(_vdspFilterReaders, -1)
    }

    var vdspFilter: BiquadFilterVDSP? {
        get { _vdspFilterStrong }
        set { setVDSPFilter(newValue) }
    }

    private func setVDSPFilter(_ filter: BiquadFilterVDSP?) {
        let previous = _vdspFilterStrong
        _vdspFilterStrong = filter
        let newPtr: UnsafeMutableRawPointer? = filter.map {
            Unmanaged.passUnretained($0).toOpaque()
        }
        seq_atomic_ptr_store_seq_cst(_vdspFilterAtomic, newPtr)
        if let previous {
            retiredVDSPFilters.append(previous)
            scheduleRetiredObjectReclamation()
        }
    }

    fileprivate var currentSampleRate: Double = 48000.0
    fileprivate var channelCount: UInt32 = 2

    // EQ parameters (10-band)
    fileprivate var eqGains: [Float] = Array(repeating: 0.0, count: 10)
    private let eqFrequencies: [Float] = [31.5, 63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]

    fileprivate var preampGain: Float = 0.0

    // Reusable buffer to avoid allocation in render callback
    fileprivate var inputBufferList: UnsafeMutablePointer<AudioBufferList>?
    fileprivate var inputABL: UnsafeMutableAudioBufferListPointer?
    fileprivate var bufferCapacity: UInt32 = 0 // bytes per buffer
    fileprivate var allocatedFrameCapacity: UInt32 = 0 // frames; input/output ABL завжди алокуються з одним maxFrames
    fileprivate var outputBufferList: UnsafeMutablePointer<AudioBufferList>?
    fileprivate var outputABL: UnsafeMutableAudioBufferListPointer?

    fileprivate var renderFramesAccum: UInt64 = 0

    /// Visualizer callback — published to the audio thread with the same
    /// lock-free pattern as the vDSP filter: acquire-load of an atomic box
    /// pointer, release-store on swap, 100 ms grace period before release.
    fileprivate final class VisualizerCallbackBox {
        let callback: (UnsafePointer<Float>, UnsafePointer<Float>, Int) -> Void
        init(_ callback: @escaping (UnsafePointer<Float>, UnsafePointer<Float>, Int) -> Void) {
            self.callback = callback
        }
    }

    private var _visualizerCallbackStrong: VisualizerCallbackBox?
    private var retiredVisualizerCallbacks: [VisualizerCallbackBox] = []

    private let _visualizerCallbackAtomic: UnsafeMutablePointer<SEQAtomicPtr> = {
        let p = UnsafeMutablePointer<SEQAtomicPtr>.allocate(capacity: 1)
        seq_atomic_ptr_init(p, nil)
        return p
    }()
    private let _visualizerCallbackReaders: UnsafeMutablePointer<SEQAtomicInt32> = {
        let p = UnsafeMutablePointer<SEQAtomicInt32>.allocate(capacity: 1)
        seq_atomic_int32_init(p, 0)
        return p
    }()
    private var reclamationScheduled = false

    @inline(__always)
    fileprivate func currentVisualizerCallback() -> VisualizerCallbackBox? {
        guard let p = seq_atomic_ptr_load_seq_cst(_visualizerCallbackAtomic) else { return nil }
        return Unmanaged<VisualizerCallbackBox>.fromOpaque(p).takeUnretainedValue()
    }

    @inline(__always)
    fileprivate func beginVisualizerCallbackRead() {
        _ = seq_atomic_int32_fetch_add_seq_cst(_visualizerCallbackReaders, 1)
    }

    @inline(__always)
    fileprivate func endVisualizerCallbackRead() {
        _ = seq_atomic_int32_fetch_add_seq_cst(_visualizerCallbackReaders, -1)
    }

    public var visualizerCallback: ((UnsafePointer<Float>, UnsafePointer<Float>, Int) -> Void)? {
        get { _visualizerCallbackStrong?.callback }
        set { setVisualizerCallback(newValue) }
    }

    private func setVisualizerCallback(_ callback: ((UnsafePointer<Float>, UnsafePointer<Float>, Int) -> Void)?) {
        let previous = _visualizerCallbackStrong
        let box = callback.map { VisualizerCallbackBox($0) }
        _visualizerCallbackStrong = box
        let newPtr: UnsafeMutableRawPointer? = box.map { Unmanaged.passUnretained($0).toOpaque() }
        seq_atomic_ptr_store_seq_cst(_visualizerCallbackAtomic, newPtr)
        if let previous {
            retiredVisualizerCallbacks.append(previous)
            scheduleRetiredObjectReclamation()
        }
    }

    private func scheduleRetiredObjectReclamation() {
        guard !reclamationScheduled else { return }
        reclamationScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(10)) { [weak self] in
            self?.reclaimRetiredObjects()
        }
    }

    private func reclaimRetiredObjects() {
        if seq_atomic_int32_load_seq_cst(_vdspFilterReaders) == 0 {
            retiredVDSPFilters.removeAll()
        }
        if seq_atomic_int32_load_seq_cst(_visualizerCallbackReaders) == 0 {
            retiredVisualizerCallbacks.removeAll()
        }
        if retiredVDSPFilters.isEmpty, retiredVisualizerCallbacks.isEmpty {
            reclamationScheduled = false
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(10)) { [weak self] in
                self?.reclaimRetiredObjects()
            }
        }
    }

    fileprivate var visualizerCounter: Int = 0
    fileprivate var visualizerInterval: Int =
        1024 // ⚡ Update visualizer every ~21ms (48kHz) - halved frequency to reduce CPU

    // Test tone
    fileprivate var testToneEnabled: Bool = false
    fileprivate var testTonePhase: Float = 0.0
    fileprivate var testToneFrequency: Float = 440.0
    fileprivate var didLogInputInfo: Bool = false
    fileprivate var didLogToneWrite: Bool = false
    fileprivate var diagEvery: UInt64 = 480_000 // ⚡ OPTIMIZED: Log every ~10 seconds (48x less CPU overhead)

    // Ring buffer (extracted into SPSCRingBuffer for modularity)
    let ringBuffer = SPSCRingBuffer()
    fileprivate var inputCallbackCounter: UInt64 = 0
    fileprivate var lastOutSampleTimes: [Double] = []
    fileprivate var lastInSampleTimes: [Double] = []

    fileprivate var lastInputBufferFrames: UInt32 = 0
    #if DEBUG
        fileprivate var maxInputCallbackNanos: UInt64 = 0
        fileprivate var sumInputCallbackNanos: UInt64 = 0
        fileprivate var countInputCallbacks: UInt64 = 0
        fileprivate static let machTimebase: mach_timebase_info_data_t = {
            var tb = mach_timebase_info_data_t()
            mach_timebase_info(&tb)
            return tb
        }()

        private var diagStatsTimer: DispatchSourceTimer?
    #endif

    // Promote each audio callback thread to time-constraint scheduling on its
    // first invocation. Flags are read/written only from their own callback
    // thread, so non-atomic Bool is safe.
    fileprivate var didPromoteInputThread: Bool = false
    fileprivate var didPromoteOutputThread: Bool = false

    // MARK: - Singleton

    public static let shared = CoreAudioEngine()

    // MARK: - Initialization

    private init() {
        if let saved = UserDefaults.standard.dictionary(forKey: originalDeviceSampleRatesKey) {
            originalDeviceSampleRates = saved.compactMapValues {
                ($0 as? NSNumber)?.doubleValue
            }
        }
        dlog("🎛️ CoreAudioEngine initialized", category: .engine)
    }

    private func allocateRingBuffer(capacityFrames: Int, channels: UInt32) {
        ringBuffer.allocate(capacityFrames: capacityFrames)
    }

    // MARK: - Device Sample Rate Helpers

    private func getDeviceSampleRate(_ deviceID: AudioDeviceID) -> Double? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var rate: Double = 0
        var size = UInt32(MemoryLayout<Double>.size)
        let status = AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &rate)
        if status != noErr {
            dlog("⚠️ Failed to get device sample rate (\(deviceID)): \(status)", category: .engine)
            return nil
        }
        return rate
    }

    private func getDeviceUID(_ deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uid: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>>.size)
        let status = withUnsafeMutablePointer(to: &uid) { pointer in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let uid else { return nil }
        return uid.takeUnretainedValue() as String
    }

    private func findDeviceID(uid: String) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size
        ) == noErr else { return nil }

        var deviceIDs = [AudioDeviceID](
            repeating: 0,
            count: Int(size) / MemoryLayout<AudioDeviceID>.size
        )
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceIDs
        ) == noErr else { return nil }
        return deviceIDs.first { getDeviceUID($0) == uid }
    }

    /// One-shot log of buffer frame size + allowed range at setup.
    /// Useful in bug reports to understand actual device latency.
    private func logDeviceBufferInfo(_ deviceID: AudioDeviceID, label: String) {
        var rangeAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyBufferFrameSizeRange,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var range = AudioValueRange()
        var rSize = UInt32(MemoryLayout<AudioValueRange>.size)
        let rangeStatus = AudioObjectGetPropertyData(deviceID, &rangeAddr, 0, nil, &rSize, &range)

        var sizeAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyBufferFrameSize,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var current: UInt32 = 0
        var cSize = UInt32(MemoryLayout<UInt32>.size)
        let currentStatus = AudioObjectGetPropertyData(deviceID, &sizeAddr, 0, nil, &cSize, &current)

        let rangeStr = rangeStatus == noErr
            ? "\(Int(range.mMinimum))..\(Int(range.mMaximum))"
            : "err=\(rangeStatus)"
        let currentStr = currentStatus == noErr ? "\(current)" : "err=\(currentStatus)"
        dlog(
            "\(label) (\(deviceID)) buffer frames: current=\(currentStr), range=\(rangeStr)",
            category: .engine
        )
    }

    /// Set I/O buffer frame size on a device. Mismatched sizes between input
    /// and output units are a common cause of HALC overload warnings in dual-I/O
    /// AUHAL setups because the scheduler can't align their deadlines.
    @discardableResult
    private func setDeviceBufferFrameSize(_ deviceID: AudioDeviceID, frames: UInt32) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyBufferFrameSize,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var f = frames
        let size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectSetPropertyData(deviceID, &addr, 0, nil, size, &f)
        if status != noErr {
            dlog("⚠️ Failed to set buffer frame size (\(deviceID)) to \(frames): \(status)", category: .engine)
            return false
        }
        dlog("✅ Set device (\(deviceID)) buffer frame size to \(frames)", category: .engine)
        return true
    }

    private func setDeviceSampleRate(_ deviceID: AudioDeviceID, rate: Double) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var r = rate
        let size = UInt32(MemoryLayout<Double>.size)
        let status = AudioObjectSetPropertyData(deviceID, &addr, 0, nil, size, &r)
        if status != noErr {
            dlog("⚠️ Failed to set device sample rate (\(deviceID)) to \(rate): \(status)", category: .engine)
            return false
        }
        dlog("✅ Set device (\(deviceID)) sample rate to \(rate)", category: .engine)
        return true
    }

    /// Records a device's current nominal sample rate once, before we override it,
    /// so restoreDeviceSampleRates() can put it back when routing stops.
    private func captureOriginalSampleRate(_ deviceID: AudioDeviceID) {
        guard let uid = getDeviceUID(deviceID),
              originalDeviceSampleRates[uid] == nil,
              let rate = getDeviceSampleRate(deviceID) else { return }
        originalDeviceSampleRates[uid] = rate
        persistOriginalDeviceSampleRates()
    }

    /// Restores every device we changed back to its captured nominal rate. Call
    /// when EQ routing is disabled so devices aren't left permanently forced to 48k.
    /// Safe to call when the engine is stopped (no active stream to glitch).
    ///
    /// Main-thread only: `originalDeviceSampleRates` is an unsynchronized dictionary
    /// shared with `setup()`/`captureOriginalSampleRate`, which also run on main.
    /// Limitation: a crash/force-quit skips this, leaving devices at 48k; the next
    /// launch would then capture 48k as the "original". Acceptable — no persisted state.
    public func restoreDeviceSampleRates() {
        var restoredUIDs: [String] = []
        for (uid, rate) in originalDeviceSampleRates {
            guard let deviceID = findDeviceID(uid: uid),
                  setDeviceSampleRate(deviceID, rate: rate) else { continue }
            restoredUIDs.append(uid)
        }
        for uid in restoredUIDs {
            originalDeviceSampleRates.removeValue(forKey: uid)
        }
        persistOriginalDeviceSampleRates()
    }

    private func persistOriginalDeviceSampleRates() {
        if originalDeviceSampleRates.isEmpty {
            UserDefaults.standard.removeObject(forKey: originalDeviceSampleRatesKey)
        } else {
            UserDefaults.standard.set(originalDeviceSampleRates, forKey: originalDeviceSampleRatesKey)
        }
    }

    deinit {
        cleanup()
        _vdspFilterAtomic.deallocate()
        _vdspFilterReaders.deallocate()
        _visualizerCallbackAtomic.deallocate()
        _visualizerCallbackReaders.deallocate()
    }

    // MARK: - Setup

    public func setup(inputDevice: AudioDeviceID, outputDevice: AudioDeviceID) {
        dlog("🔧 Setting up Core Audio Engine...", category: .engine)
        dlog("   Input device: \(inputDevice)", category: .engine)
        dlog("   Output device: \(outputDevice)", category: .engine)

        self.inputDeviceID = inputDevice
        self.outputDeviceID = outputDevice

        // Stop old units before tearing them down so their callbacks can't
        // touch buffers that cleanup() is about to free.
        if isRunning {
            stop()
        }

        // Cleanup any existing units/buffers
        cleanup()
        var setupSucceeded = false
        defer {
            if !setupSucceeded {
                cleanup()
            }
        }

        // Remember each device's nominal rate the first time we touch it, so we can
        // put it back when EQ is turned off (we force 48k below).
        captureOriginalSampleRate(outputDevice)
        captureOriginalSampleRate(inputDevice)

        // Align hardware sample rates (prefer 48k, fallback to 44.1k)
        let preferred = 48000.0
        _ = setDeviceSampleRate(outputDevice, rate: preferred)
        _ = setDeviceSampleRate(inputDevice, rate: preferred)
        let inRate = getDeviceSampleRate(inputDevice) ?? preferred
        let outRate = getDeviceSampleRate(outputDevice) ?? preferred
        dlog("📊 Initial sample rates: input=\(inRate)Hz, output=\(outRate)Hz", category: .engine)

        if abs(inRate - outRate) >= 1.0 {
            dlog("⚠️ Sample rate mismatch detected! Attempting to align...", category: .engine)
            if !setDeviceSampleRate(outputDevice, rate: inRate) {
                _ = setDeviceSampleRate(inputDevice, rate: outRate)
            }
        }
        let finalInRate = getDeviceSampleRate(inputDevice) ?? preferred
        let finalOutRate = getDeviceSampleRate(outputDevice) ?? preferred
        self.currentSampleRate = finalOutRate
        dlog("📡 Final sample rates: input=\(finalInRate)Hz, output=\(finalOutRate)Hz", category: .engine)

        // Force identical buffer sizes on both devices so their I/O deadlines
        // align. Without this, HALC can report "skipping cycle due to overload"
        // during startup until the two IOProcs converge on matching sizes.
        setDeviceBufferFrameSize(inputDevice, frames: 512)
        setDeviceBufferFrameSize(outputDevice, frames: 512)

        logDeviceBufferInfo(inputDevice, label: "INPUT")
        logDeviceBufferInfo(outputDevice, label: "OUTPUT")

        if abs(finalInRate - finalOutRate) >= 1.0 {
            dlog("⚠️ WARNING: Sample rate mismatch! This will cause audio quality degradation!", category: .engine)
            dlog("   Input: \(finalInRate)Hz, Output: \(finalOutRate)Hz", category: .engine)
            dlog("   Please set both devices to the same sample rate in Audio MIDI Setup", category: .engine)
        }

        // Desired client format (Float32, non-interleaved, up to 2ch)
        let targetSampleRate: Double = self.currentSampleRate
        var clientFormat = AudioStreamBasicDescription(
            mSampleRate: targetSampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 2,
            mBitsPerChannel: 32,
            mReserved: 0
        )
        let asbdSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var maxFramesPerSlice: UInt32 = 4096
        let mfsSize = UInt32(MemoryLayout<UInt32>.size)

        // MARK: Create INPUT unit (HAL, attached to virtual audio device)

        do {
            var desc = AudioComponentDescription(
                componentType: kAudioUnitType_Output,
                componentSubType: kAudioUnitSubType_HALOutput,
                componentManufacturer: kAudioUnitManufacturer_Apple,
                componentFlags: 0,
                componentFlagsMask: 0
            )
            guard let comp = AudioComponentFindNext(nil, &desc) else {
                dlog("❌ Failed to find HAL Output Audio Component (input)", category: .engine)
                return
            }
            var unit: AudioUnit?
            var status = AudioComponentInstanceNew(comp, &unit)
            guard status == noErr, let iu = unit else {
                dlog("❌ Failed to create INPUT unit: \(status)", category: .engine)
                return
            }
            inputUnit = iu

            var enable: UInt32 = 1
            var disable: UInt32 = 0

            // Enable input on element 1, disable output on element 0
            status = AudioUnitSetProperty(
                iu,
                kAudioOutputUnitProperty_EnableIO,
                kAudioUnitScope_Input,
                1,
                &enable,
                UInt32(MemoryLayout<UInt32>.size)
            )
            if status != noErr { dlog("❌ Failed to enable INPUT on inputUnit: \(status)", category: .engine); return }
            status = AudioUnitSetProperty(
                iu,
                kAudioOutputUnitProperty_EnableIO,
                kAudioUnitScope_Output,
                0,
                &disable,
                UInt32(MemoryLayout<UInt32>.size)
            )
            if status != noErr { dlog("❌ Failed to disable OUTPUT on inputUnit: \(status)", category: .engine); return }

            // Attach to virtual audio input device
            var inDev = inputDevice
            status = AudioUnitSetProperty(
                iu,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &inDev,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )
            if status != noErr { dlog("❌ Failed to set INPUT device: \(status)", category: .engine); return }

            // Query actual input format to derive channel count
            var inFormat = AudioStreamBasicDescription()
            var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            status = AudioUnitGetProperty(
                iu,
                kAudioUnitProperty_StreamFormat,
                kAudioUnitScope_Input,
                1,
                &inFormat,
                &size
            )
            if status == noErr {
                let isFloat = (inFormat.mFormatFlags & kAudioFormatFlagIsFloat) != 0
                let bitsPerChannel = inFormat.mBitsPerChannel
                dlog(
                    "📊 Input device format: \(inFormat.mChannelsPerFrame)ch, \(inFormat.mSampleRate)Hz, \(bitsPerChannel)bit, float=\(isFloat)",
                    category: .engine
                )
                self.channelCount = max(1, min(2, inFormat.mChannelsPerFrame))
            } else {
                self.channelCount = 2
            }
            clientFormat.mChannelsPerFrame = self.channelCount

            dlog(
                "🎯 Forcing client sample rate: \(targetSampleRate)Hz (set devices to 48k in Audio MIDI Setup)",
                category: .engine
            )

            // Configure client stream format on INPUT unit's output (element 1)
            _ = AudioUnitSetProperty(
                iu,
                kAudioUnitProperty_StreamFormat,
                kAudioUnitScope_Output,
                1,
                &clientFormat,
                asbdSize
            )
            var sr = self.currentSampleRate
            _ = AudioUnitSetProperty(
                iu,
                kAudioUnitProperty_SampleRate,
                kAudioUnitScope_Output,
                1,
                &sr,
                UInt32(MemoryLayout<Double>.size)
            )
            _ = AudioUnitSetProperty(
                iu,
                kAudioUnitProperty_MaximumFramesPerSlice,
                kAudioUnitScope_Global,
                0,
                &maxFramesPerSlice,
                mfsSize
            )
            // Log INPUT client format (what AudioUnitRender will produce)
            var clientFmtCheck = AudioStreamBasicDescription()
            var cfSz = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            if AudioUnitGetProperty(
                iu,
                kAudioUnitProperty_StreamFormat,
                kAudioUnitScope_Output,
                1,
                &clientFmtCheck,
                &cfSz
            ) == noErr {
                let interleaved = (clientFmtCheck.mFormatFlags & kAudioFormatFlagIsNonInterleaved) == 0
                dlog(
                    "📊 INPUT client format: \(clientFmtCheck.mChannelsPerFrame)ch, \(clientFmtCheck.mSampleRate)Hz, interleaved=\(interleaved)",
                    category: .engine
                )
            }

            // Register INPUT callback (push) — we will call AudioUnitRender inside it and write to ring buffer
            let selfPointer = Unmanaged.passUnretained(self).toOpaque()
            var inputCB = AURenderCallbackStruct(inputProc: inputCaptureCallbackFunction, inputProcRefCon: selfPointer)
            let statusCB = AudioUnitSetProperty(
                iu,
                kAudioOutputUnitProperty_SetInputCallback,
                kAudioUnitScope_Global,
                0,
                &inputCB,
                UInt32(MemoryLayout<AURenderCallbackStruct>.size)
            )
            if statusCB == noErr {
                dlog("✅ INPUT: SetInputCallback registered", category: .engine)
            } else {
                dlog("❌ INPUT: SetInputCallback failed — status=\(statusCB)", category: .engine)
            }
        }

        // MARK: Create OUTPUT unit (HAL, attached to physical output)

        do {
            var desc = AudioComponentDescription(
                componentType: kAudioUnitType_Output,
                componentSubType: kAudioUnitSubType_HALOutput,
                componentManufacturer: kAudioUnitManufacturer_Apple,
                componentFlags: 0,
                componentFlagsMask: 0
            )
            guard let comp = AudioComponentFindNext(nil, &desc) else {
                dlog("❌ Failed to find HAL Output Audio Component (output)", category: .engine)
                return
            }
            var unit: AudioUnit?
            var status = AudioComponentInstanceNew(comp, &unit)
            guard status == noErr, let ou = unit else {
                dlog("❌ Failed to create OUTPUT unit: \(status)", category: .engine)
                return
            }
            outputUnit = ou

            var enable: UInt32 = 1
            var disable: UInt32 = 0

            // Enable output on element 0, disable input on element 1
            status = AudioUnitSetProperty(
                ou,
                kAudioOutputUnitProperty_EnableIO,
                kAudioUnitScope_Output,
                0,
                &enable,
                UInt32(MemoryLayout<UInt32>.size)
            )
            if status != noErr { dlog("❌ Failed to enable OUTPUT on outputUnit: \(status)", category: .engine); return }
            status = AudioUnitSetProperty(
                ou,
                kAudioOutputUnitProperty_EnableIO,
                kAudioUnitScope_Input,
                1,
                &disable,
                UInt32(MemoryLayout<UInt32>.size)
            )
            if status != noErr { dlog("❌ Failed to disable INPUT on outputUnit: \(status)", category: .engine); return }

            // Attach to physical output device
            var outDev = outputDevice
            status = AudioUnitSetProperty(
                ou,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &outDev,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )
            if status != noErr { dlog("❌ Failed to set OUTPUT device: \(status)", category: .engine); return }

            // Configure client stream format on OUTPUT unit's input (element 0)
            // Match device interleaving to avoid conversion issues
            var deviceFmt = AudioStreamBasicDescription()
            var deviceFmtSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            if AudioUnitGetProperty(
                ou,
                kAudioUnitProperty_StreamFormat,
                kAudioUnitScope_Output,
                0,
                &deviceFmt,
                &deviceFmtSize
            ) == noErr {
                let deviceInterleaved = (deviceFmt.mFormatFlags & kAudioFormatFlagIsNonInterleaved) == 0
                let ch = max(UInt32(1), min(UInt32(2), deviceFmt.mChannelsPerFrame))
                var clientOutFormat = AudioStreamBasicDescription(
                    mSampleRate: targetSampleRate,
                    mFormatID: kAudioFormatLinearPCM,
                    mFormatFlags: deviceInterleaved ? (kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked) :
                        (kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved),
                    mBytesPerPacket: deviceInterleaved ? (4 * ch) : 4,
                    mFramesPerPacket: 1,
                    mBytesPerFrame: deviceInterleaved ? (4 * ch) : 4,
                    mChannelsPerFrame: ch,
                    mBitsPerChannel: 32,
                    mReserved: 0
                )
                _ = AudioUnitSetProperty(
                    ou,
                    kAudioUnitProperty_StreamFormat,
                    kAudioUnitScope_Input,
                    0,
                    &clientOutFormat,
                    asbdSize
                )
                var sr = self.currentSampleRate
                _ = AudioUnitSetProperty(
                    ou,
                    kAudioUnitProperty_SampleRate,
                    kAudioUnitScope_Input,
                    0,
                    &sr,
                    UInt32(MemoryLayout<Double>.size)
                )
            } else {
                _ = AudioUnitSetProperty(
                    ou,
                    kAudioUnitProperty_StreamFormat,
                    kAudioUnitScope_Input,
                    0,
                    &clientFormat,
                    asbdSize
                )
                var sr = self.currentSampleRate
                _ = AudioUnitSetProperty(
                    ou,
                    kAudioUnitProperty_SampleRate,
                    kAudioUnitScope_Input,
                    0,
                    &sr,
                    UInt32(MemoryLayout<Double>.size)
                )
            }
            _ = AudioUnitSetProperty(
                ou,
                kAudioUnitProperty_MaximumFramesPerSlice,
                kAudioUnitScope_Global,
                0,
                &maxFramesPerSlice,
                mfsSize
            )

            // Ensure output unit allocates its own render buffers (so ioData is non-nil)
            var shouldAllocate: UInt32 = 1
            status = AudioUnitSetProperty(
                ou,
                kAudioUnitProperty_ShouldAllocateBuffer,
                kAudioUnitScope_Input,
                0,
                &shouldAllocate,
                UInt32(MemoryLayout<UInt32>.size)
            )
            if status !=
                noErr { dlog("⚠️ Failed to set ShouldAllocateBuffer on outputUnit: \(status)", category: .engine) }

            // Set render callback on OUTPUT unit (scope Input, element 0)
            let selfPointer = Unmanaged.passUnretained(self).toOpaque()
            var renderCallback = AURenderCallbackStruct(
                inputProc: renderCallbackFunction,
                inputProcRefCon: selfPointer
            )
            status = AudioUnitSetProperty(
                ou,
                kAudioUnitProperty_SetRenderCallback,
                kAudioUnitScope_Input,
                0,
                &renderCallback,
                UInt32(MemoryLayout<AURenderCallbackStruct>.size)
            )
            if status != noErr { dlog("❌ Failed to set render callback: \(status)", category: .engine); return }
        }

        // Initialize both units
        if let iu = inputUnit {
            let s = AudioUnitInitialize(iu)
            if s != noErr { dlog("❌ Failed to initialize INPUT unit: \(s)", category: .engine); return }
        }
        if let ou = outputUnit {
            let s = AudioUnitInitialize(ou)
            if s != noErr { dlog("❌ Failed to initialize OUTPUT unit: \(s)", category: .engine); return }
        }

        // Diagnostic: Inspect output unit stream formats
        if let ou = outputUnit {
            var fmt = AudioStreamBasicDescription()
            var sz = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            if AudioUnitGetProperty(ou, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &fmt, &sz) == noErr {
                let interleaved = (fmt.mFormatFlags & kAudioFormatFlagIsNonInterleaved) == 0
                dlog(
                    "📊 Output unit input format: \(fmt.mChannelsPerFrame)ch, \(fmt.mSampleRate)Hz, interleaved=\(interleaved)",
                    category: .engine
                )
            }
            if AudioUnitGetProperty(ou, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &fmt, &sz) ==
                noErr {
                let interleaved = (fmt.mFormatFlags & kAudioFormatFlagIsNonInterleaved) == 0
                dlog(
                    "📊 Output unit device format: \(fmt.mChannelsPerFrame)ch, \(fmt.mSampleRate)Hz, interleaved=\(interleaved)",
                    category: .engine
                )
            }
        }

        // Pre-allocate buffers for render callback (after channelCount is known)
        allocateInputBuffer(maxFrames: maxFramesPerSlice, channels: self.channelCount)
        allocateOutputBuffer(maxFrames: maxFramesPerSlice, channels: self.channelCount)
        allocateRingBuffer(capacityFrames: Int(maxFramesPerSlice) * 16, channels: self.channelCount)
        guard inputBufferList != nil,
              outputBufferList != nil,
              ringBuffer.isAllocated else {
            dlog("❌ Failed to allocate audio buffers", level: .error, category: .engine)
            return
        }
        isSetupComplete = true
        setupSucceeded = true

        dlog("✅ Core Audio Units initialized successfully", category: .engine)
        dlog("🎤 Ready for real-time audio processing", category: .engine)
        dlog("🎛️ Biquad filter system ready (EQ not applied yet)", category: .engine)
    }

    // MARK: - EQ Application

    // 🔧 Пресети приходять і з зовнішніх файлів — NaN/Inf/екстремальні dB не мають дійти до фільтрів
    private nonisolated static func sanitizedDB(_ value: Float) -> Float {
        value.isFinite ? max(-20.0, min(20.0, value)) : 0.0
    }

    /// Apply fixed-band EQ (10 bands)
    public func applyFixedBandEQ(_ gains: [Float], preamp: Float = 0.0) {
        let preamp = Self.sanitizedDB(preamp)
        let gains = gains.map(Self.sanitizedDB)
        self.preampGain = preamp
        self.eqGains = gains

        // Convert to parametric bands
        let frequencies = AutoEQConstants.tenBandFrequencies
        var bands: [ParametricBand] = []

        for (index, gain) in gains.enumerated() {
            let freq = frequencies[index]
            let type: FilterType
            let q: Float

            if freq <= 63 {
                type = .lowShelf
                q = 0.9
            } else if freq >= 8000 {
                type = .highShelf
                q = 0.9
            } else {
                type = .peak
                q = 1.4
            }

            let band = ParametricBand(
                frequency: Float(freq),
                gain: gain,
                q: q,
                filterType: type
            )
            bands.append(band)
        }

        // ⚡ Use vDSP optimized filter (5-10x faster, ~5-10% CPU)
        if useVDSPFilter {
            let filter = BiquadFilterVDSP(sampleRate: Float(currentSampleRate))
            filter.configure(bands: bands, preamp: preamp, sampleRate: Float(currentSampleRate))
            self.vdspFilter = filter
            self.filterChain = nil // Clear old filter chain
        } else {
            // Fallback to standard filter chain
            self.filterChain = BiquadFilterChain(filterCount: bands.count)
            self.filterChain?.preamp = preamp
            let bandFrequencies = bands.map(\.frequency)
            let bandGains = bands.map(\.gain)
            let bandQs = bands.map(\.q)
            let bandTypes = bands.map(\.filterType)
            self.filterChain?.configureBands(
                bandFrequencies,
                gains: bandGains.map { Float($0) },
                qs: bandQs.map { Float($0) },
                types: bandTypes,
                sampleRate: Float(currentSampleRate)
            )
            self.vdspFilter = nil
            dlog("🎛️ Applied 10-band EQ with standard filters", category: .engine)
        }
    }

    /// Apply 31-band graphic EQ using parametric peaks
    public func applyGraphicEQ31(_ gains: [Float], preamp: Float = 0.0) {
        let preamp = Self.sanitizedDB(preamp)
        let gains = gains.map(Self.sanitizedDB)
        self.preampGain = preamp

        var bands: [ParametricBand] = []
        let centers = AutoEQConstants.thirtyOneCenters
        let count = min(gains.count, centers.count)

        // Create bands for all frequencies (vDSP filter will skip zero-gain automatically)
        for i in 0..<count {
            let band = ParametricBand(
                frequency: centers[i],
                gain: gains[i],
                q: 2.0,
                filterType: .peak
            )
            bands.append(band)
        }

        // ⚡ Use vDSP optimized filter (5-10x faster, ~5-10% CPU even with 31 bands)
        if useVDSPFilter {
            let filter = BiquadFilterVDSP(sampleRate: Float(currentSampleRate))
            filter.configure(bands: bands, preamp: preamp, sampleRate: Float(currentSampleRate))
            self.vdspFilter = filter
            self.filterChain = nil // Clear old filter chain
        } else {
            // Fallback to standard filter chain (only non-zero bands)
            var activeBands: [ParametricBand] = []
            for i in 0..<count {
                let g = gains[i]
                if abs(g) > 0.5 {
                    activeBands.append(ParametricBand(
                        frequency: centers[i],
                        gain: g,
                        q: 2.0,
                        filterType: .peak
                    ))
                }
            }

            self.filterChain = BiquadFilterChain(filterCount: activeBands.count)
            self.filterChain?.preamp = preamp
            let bandFrequencies31 = activeBands.map(\.frequency)
            let bandGains31 = activeBands.map(\.gain)
            let bandQs31 = activeBands.map(\.q)
            let bandTypes31 = activeBands.map(\.filterType)
            self.filterChain?.configureBands(
                bandFrequencies31,
                gains: bandGains31.map { Float($0) },
                qs: bandQs31.map { Float($0) },
                types: bandTypes31,
                sampleRate: Float(currentSampleRate)
            )
            self.vdspFilter = nil
            dlog(
                "🎛️ Applied 31-band EQ with \(activeBands.count) active filters (skipped \(count - activeBands.count) zero-gain bands)",
                category: .engine
            )
        }
    }

    /// Clear EQ
    public func clearEQ() {
        self.filterChain = nil
        self.vdspFilter = nil
        self.preampGain = 0.0
        self.eqGains = Array(repeating: 0.0, count: 10)
        dlog("🎛️ EQ cleared", category: .engine)
    }

    // MARK: - Control

    @discardableResult
    public func start() -> Bool {
        guard let iu = inputUnit, let ou = outputUnit, isSetupComplete, !isRunning else {
            dlog("⚠️ Core Audio Engine already running or not set up", category: .engine)
            return false
        }
        // Seed ring with ~2 IO cycles of silence so the first output callbacks
        // have data to read while the input side is still spinning up.
        ringBuffer.primeSilence(frames: 1024)
        let s1 = AudioOutputUnitStart(iu)
        guard s1 == noErr else {
            dlog("❌ Failed to start Core Audio Engine input: \(s1)", level: .error, category: .engine)
            return false
        }
        let s2 = AudioOutputUnitStart(ou)
        guard s2 == noErr else {
            AudioOutputUnitStop(iu)
            dlog("❌ Failed to start Core Audio Engine output: \(s2)", level: .error, category: .engine)
            return false
        }

        isRunning = true
        dlog("✅ Core Audio Engine started", category: .engine)
        dlog("   Audio flows: Input → EQ Processing → Output", category: .engine)
        #if DEBUG
            startDiagStatsTimer()
        #endif
        return true
    }

    /// Audio-thread health timer. Flushes every 30s on main queue; only logs
    /// when something interesting happens (high max, underrun, overrun) so we
    /// don't pollute the console during normal operation.
    private func startDiagStatsTimer() {
        #if DEBUG
            diagStatsTimer?.cancel()
            let t = DispatchSource.makeTimerSource(queue: .main)
            t.schedule(deadline: .now() + 30.0, repeating: 30.0)
            t.setEventHandler { [weak self] in
                guard let self else { return }
                let maxNs = self.maxInputCallbackNanos
                let sumNs = self.sumInputCallbackNanos
                let count = self.countInputCallbacks
                self.maxInputCallbackNanos = 0
                self.sumInputCallbackNanos = 0
                self.countInputCallbacks = 0
                let avgNs = count > 0 ? sumNs / count : 0
                let diag = self.ringBuffer.snapshotAndResetDiag()

                let bufFrames = self.lastInputBufferFrames
                let deadlineNs: UInt64 = bufFrames > 0
                    ? UInt64(Double(bufFrames) / self.currentSampleRate * 1_000_000_000)
                    : 0
                let nearDeadline = deadlineNs > 0 && maxNs > deadlineNs / 2
                if nearDeadline || diag.underruns > 0 || diag.overruns > 0 {
                    dlog(
                        "⚠️ Audio health: max=\(maxNs / 1000)µs avg=\(avgNs / 1000)µs " +
                            "(deadline=\(deadlineNs / 1000)µs) under=\(diag.underruns) over=\(diag.overruns)",
                        level: .warning,
                        category: .engine
                    )
                }
            }
            t.resume()
            diagStatsTimer = t
        #endif
    }

    private func stopDiagStatsTimer() {
        #if DEBUG
            diagStatsTimer?.cancel()
            diagStatsTimer = nil
        #endif
    }

    public func stop() {
        // Stop test tone if running
        if testToneEnabled {
            testToneEnabled = false
            dlog("🔕 Test tone auto-stopped (engine stopping)", category: .engine)
        }

        if let iu = inputUnit { AudioOutputUnitStop(iu) }
        if let ou = outputUnit { AudioOutputUnitStop(ou) }
        isRunning = false

        // Re-promote callback threads on next start (they may be new threads).
        didPromoteInputThread = false
        didPromoteOutputThread = false

        // Reset peak meters and ring buffer
        peakMeter.resetToZero()
        ringBuffer.reset()

        #if DEBUG
            stopDiagStatsTimer()
        #endif

        dlog("🛑 Core Audio Engine stopped", category: .engine)
    }

    // MARK: - Diagnostics API

    public func printAudioUnitDiagnostics() {
        dlog("===== CoreAudioEngine Diagnostics =====", category: .engine)
        dlog("Devices: input=\(inputDeviceID), output=\(outputDeviceID)", category: .engine)
        if let inSR = getDeviceSampleRate(inputDeviceID) { dlog("Input device SR: \(inSR)", category: .engine) }
        if let outSR = getDeviceSampleRate(outputDeviceID) { dlog("Output device SR: \(outSR)", category: .engine) }
        dlog("Client sampleRate: \(currentSampleRate), channels: \(channelCount)", category: .engine)

        if let iu = inputUnit {
            var fmt = AudioStreamBasicDescription(); var sz = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            if AudioUnitGetProperty(iu, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &fmt, &sz) ==
                noErr {
                let interleaved = (fmt.mFormatFlags & kAudioFormatFlagIsNonInterleaved) == 0
                dlog(
                    "INPUT client fmt: \(fmt.mChannelsPerFrame)ch, \(fmt.mSampleRate)Hz, interleaved=\(interleaved)",
                    category: .engine
                )
            }
        }
        if let ou = outputUnit {
            var fmt = AudioStreamBasicDescription(); var sz = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            if AudioUnitGetProperty(ou, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &fmt, &sz) == noErr {
                let interleaved = (fmt.mFormatFlags & kAudioFormatFlagIsNonInterleaved) == 0
                dlog(
                    "OUTPUT client fmt: \(fmt.mChannelsPerFrame)ch, \(fmt.mSampleRate)Hz, interleaved=\(interleaved)",
                    category: .engine
                )
            }
            if AudioUnitGetProperty(ou, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &fmt, &sz) ==
                noErr {
                let interleaved = (fmt.mFormatFlags & kAudioFormatFlagIsNonInterleaved) == 0
                dlog(
                    "OUTPUT device fmt: \(fmt.mChannelsPerFrame)ch, \(fmt.mSampleRate)Hz, interleaved=\(interleaved)",
                    category: .engine
                )
            }
        }
        dlog(
            "Buffers: inputABL capBytes=\(bufferCapacity), ring=\(ringBuffer.capacity) frames, rbRead=\(ringBuffer.readIndex), rbWrite=\(ringBuffer.writeIndex), avail=\(ringBuffer.availableForReading)",
            category: .engine
        )
        dlog("Engine running: \(isRunning)", category: .engine)
        dlog("Last OUT timestamps: \(lastOutSampleTimes.suffix(5))", category: .engine)
        dlog("Last IN timestamps: \(lastInSampleTimes.suffix(5))", category: .engine)
        dlog("=======================================", category: .engine)
    }

    fileprivate func appendOutTs(_ s: Double) {
        lastOutSampleTimes.append(s)
        if lastOutSampleTimes.count > 32 { lastOutSampleTimes.removeFirst(lastOutSampleTimes.count - 32) }
    }

    fileprivate func appendInTs(_ s: Double) {
        lastInSampleTimes.append(s)
        if lastInSampleTimes.count > 32 { lastInSampleTimes.removeFirst(lastInSampleTimes.count - 32) }
    }

    // MARK: - Meter Publishing (delegated to PeakMeter)

    /// 🔧 Thread safety: lock serializes cleanup between deinit and setup().
    /// The body is idempotent (every handle is nil-ed after release), so it is
    /// safe to call again on every device re-setup.
    private let cleanupLock = NSLock()

    private func cleanup() {
        cleanupLock.lock()
        defer { cleanupLock.unlock() }
        isSetupComplete = false

        if let iu = inputUnit {
            AudioOutputUnitStop(iu)
            AudioUnitUninitialize(iu)
            AudioComponentInstanceDispose(iu)
            inputUnit = nil
        }
        if let ou = outputUnit {
            AudioOutputUnitStop(ou)
            AudioUnitUninitialize(ou)
            AudioComponentInstanceDispose(ou)
            outputUnit = nil
        }
        if let abl = inputABL, let ablPtr = inputBufferList {
            for i in 0..<abl.count where abl[i].mData != nil {
                free(abl[i].mData)
                abl[i].mData = nil
            }
            free(UnsafeMutableRawPointer(ablPtr))
            inputABL = nil
            inputBufferList = nil
        }
        if let abl = outputABL, let ablPtr = outputBufferList {
            for i in 0..<abl.count where abl[i].mData != nil {
                free(abl[i].mData)
                abl[i].mData = nil
            }
            free(UnsafeMutableRawPointer(ablPtr))
            outputABL = nil
            outputBufferList = nil
        }

        // Deallocate ring buffer (safe to call multiple times)
        ringBuffer.deallocate()

        dlog("✅ CoreAudioEngine: Cleanup complete (including ring buffers)", category: .engine)
    }

    // MARK: - Buffer Management

    private func allocateInputBuffer(maxFrames: UInt32, channels: UInt32) {
        if let abl = inputABL, let ablPtr = inputBufferList {
            for i in 0..<abl.count where abl[i].mData != nil {
                free(abl[i].mData)
                abl[i].mData = nil
            }
            free(UnsafeMutableRawPointer(ablPtr))
            inputABL = nil
            inputBufferList = nil
        }
        let bytesPerFrame: UInt32 = 4
        bufferCapacity = maxFrames * bytesPerFrame
        allocatedFrameCapacity = maxFrames
        let totalSize = MemoryLayout<AudioBufferList>.size + (Int(channels) - 1) * MemoryLayout<AudioBuffer>.stride
        guard let rawPtr = malloc(totalSize) else { return }
        let ablPtr = rawPtr.bindMemory(to: AudioBufferList.self, capacity: 1)
        ablPtr.pointee.mNumberBuffers = channels
        let abl = UnsafeMutableAudioBufferListPointer(ablPtr)
        for i in 0..<Int(channels) {
            abl[i].mNumberChannels = 1
            abl[i].mDataByteSize = bufferCapacity
            abl[i].mData = malloc(Int(bufferCapacity))
        }
        inputABL = abl
        inputBufferList = ablPtr
        dlog("🎛️ Pre-allocated input buffer: \(maxFrames) frames, \(channels) channels", category: .engine)
    }

    private func allocateOutputBuffer(maxFrames: UInt32, channels: UInt32) {
        if let abl = outputABL, let ablPtr = outputBufferList {
            for i in 0..<abl.count where abl[i].mData != nil {
                free(abl[i].mData)
                abl[i].mData = nil
            }
            free(UnsafeMutableRawPointer(ablPtr))
            outputABL = nil
            outputBufferList = nil
        }
        let bytesPerFrame: UInt32 = 4
        let capacity = maxFrames * bytesPerFrame
        let totalSize = MemoryLayout<AudioBufferList>.size + (Int(channels) - 1) * MemoryLayout<AudioBuffer>.stride
        guard let rawPtr = malloc(totalSize) else { return }
        let ablPtr = rawPtr.bindMemory(to: AudioBufferList.self, capacity: 1)
        ablPtr.pointee.mNumberBuffers = channels
        let abl = UnsafeMutableAudioBufferListPointer(ablPtr)
        for i in 0..<Int(channels) {
            abl[i].mNumberChannels = 1
            abl[i].mDataByteSize = capacity
            abl[i].mData = malloc(Int(capacity))
        }
        outputABL = abl
        outputBufferList = ablPtr
        dlog("🎛️ Pre-allocated output buffer: \(maxFrames) frames, \(channels) channels", category: .engine)
    }

    // MARK: - EQ Control

    /// Set single EQ band (rebuilds filter chain)
    public func setEQBand(index: Int, gain: Float) {
        guard index < eqGains.count else { return }
        eqGains[index] = max(-20.0, min(20.0, gain))

        // Rebuild filter chain with new gains
        applyFixedBandEQ(eqGains, preamp: preampGain)
    }

    /// Get current band gain
    public func getBandGain(index: Int) -> Float {
        guard index < eqGains.count else { return 0.0 }
        return eqGains[index]
    }

    /// Set preamp gain
    public func setPreampGain(_ gain: Float) {
        preampGain = Self.sanitizedDB(gain)
    }

    /// Enable/disable EQ processing (bypass)
    public func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        dlog("🎛️ CoreAudioEngine EQ \(enabled ? "enabled" : "bypassed")", category: .engine)
    }

    public func startTestTone(_ freq: Float = 440.0) {
        guard isRunning else {
            dlog("⚠️ Cannot start test tone: CoreAudioEngine not running", category: .engine)
            dlog("   Please enable EQ first", category: .engine)
            return
        }

        testToneFrequency = freq
        testTonePhase = 0.0
        testToneEnabled = true
        dlog("🔔 Test tone enabled: \(freq) Hz", category: .engine)
    }

    public func stopTestTone() {
        testToneEnabled = false
        dlog("🔕 Test tone disabled", category: .engine)
    }

    /// Set all bands at once
    public func setAllBands(_ gains: [Float]) {
        for (index, gain) in gains.prefix(eqGains.count).enumerated() {
            eqGains[index] = max(-20.0, min(20.0, gain))
        }

        // Rebuild filter chain
        applyFixedBandEQ(eqGains, preamp: preampGain)
    }

    // MARK: - Room Correction

    /// Apply notch filters on top of the current EQ preset (room correction).
    /// Each filter uses a peak biquad with negative gain (notch effect).
    public func applyRoomNotchFilters(_ notchFilters: [(frequency: Float, gain: Float, q: Float)]) {
        guard !notchFilters.isEmpty else { return }

        let bands = notchFilters.map { f in
            ParametricBand(frequency: f.frequency, gain: f.gain, q: f.q, filterType: .peak)
        }

        let filter = BiquadFilterVDSP(sampleRate: Float(currentSampleRate))
        filter.configure(bands: bands, preamp: 0.0, sampleRate: Float(currentSampleRate))
        self.vdspFilter = filter
        self.filterChain = nil

        dlog("🏠 Applied \(bands.count) room correction notch filter(s)", category: .engine)
    }

    /// Clear room correction notch filters (restore previous EQ state).
    public func clearRoomNotchFilters() {
        self.vdspFilter = nil
        self.filterChain = nil
        dlog("🏠 Room correction filters cleared", category: .engine)
    }
}

// MARK: - Render Callback

private func renderCallbackFunction(
    inRefCon: UnsafeMutableRawPointer,
    ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
    inTimeStamp: UnsafePointer<AudioTimeStamp>,
    inBusNumber: UInt32,
    inNumberFrames: UInt32,
    ioData: UnsafeMutablePointer<AudioBufferList>?
) -> OSStatus {
    // Get reference to CoreAudioEngine
    let engine = Unmanaged<CoreAudioEngine>.fromOpaque(inRefCon).takeUnretainedValue()

    // One-shot real-time priority promotion for the output render thread.
    if !engine.didPromoteOutputThread {
        engine.didPromoteOutputThread = true
        let period = Double(inNumberFrames) / engine.currentSampleRate
        RealtimeThread.promoteCurrentThread(
            periodSec: period,
            computationSec: period * 0.5,
            constraintSec: period * 0.85
        )
    }

    // Ensure ioData buffers have valid memory (fallback to preallocated buffers)
    if let ioData {
        let out = UnsafeMutableAudioBufferListPointer(ioData)
        if let fallback = engine.outputABL {
            let count = min(out.count, fallback.count)
            for i in 0..<count where out[i].mData == nil {
                out[i].mData = fallback[i].mData
                out[i].mDataByteSize = min(out[i].mDataByteSize, fallback[i].mDataByteSize)
                out[i].mNumberChannels = fallback[i].mNumberChannels
            }
        }
    }

    // Diagnostics about output buffers and callback cadence
    engine.renderFramesAccum &+= 1
    // ⚡ No logging in render callback — real-time safety.

    // Note: test tone now generated in input callback and passes through ring buffer

    // RING READ: consume audio frames from ring buffer and feed to output
    guard let ioData else { return noErr }
    let outputBuffers = UnsafeMutableAudioBufferListPointer(ioData)
    let outBufferCount = outputBuffers.count
    let framesRequested = Int(inNumberFrames)
    let rb = engine.ringBuffer
    // 🔧 Fallback-буфери з outputABL мають ємність allocatedFrameCapacity — не писати більше
    guard inNumberFrames <= engine.allocatedFrameCapacity else {
        return kAudioUnitErr_TooManyFramesToProcess
    }

    if outBufferCount == 1, outputBuffers[0].mNumberChannels >= 2 {
        guard let outPtr = outputBuffers[0].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
        rb.readInterleaved(outPtr: outPtr, framesRequested: framesRequested)
        outputBuffers[0].mDataByteSize = UInt32(framesRequested * 2 * MemoryLayout<Float>.size)
    } else if outBufferCount >= 2 {
        guard let outL = outputBuffers[0].mData?.assumingMemoryBound(to: Float.self),
              let outR = outputBuffers[1].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
        rb.readNonInterleaved(outL: outL, outR: outR, framesRequested: framesRequested)
        outputBuffers[0].mDataByteSize = UInt32(framesRequested * MemoryLayout<Float>.size)
        outputBuffers[1].mDataByteSize = UInt32(framesRequested * MemoryLayout<Float>.size)
    }
    return noErr
}

#if DEBUG
    @inline(__always)
    private func machNanosSince(_ start: UInt64) -> UInt64 {
        let end = mach_absolute_time()
        let tb = CoreAudioEngine.machTimebase
        return (end &- start) &* UInt64(tb.numer) / UInt64(tb.denom)
    }
#endif

private func inputCaptureCallbackFunction(
    inRefCon: UnsafeMutableRawPointer,
    ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
    inTimeStamp: UnsafePointer<AudioTimeStamp>,
    inBusNumber: UInt32,
    inNumberFrames: UInt32,
    ioData: UnsafeMutablePointer<AudioBufferList>?
) -> OSStatus {
    #if DEBUG
        let diagStart = mach_absolute_time()
    #endif

    let engine = Unmanaged<CoreAudioEngine>.fromOpaque(inRefCon).takeUnretainedValue()
    engine.inputCallbackCounter &+= 1
    engine.lastInputBufferFrames = inNumberFrames

    // One-shot real-time priority promotion for the input capture thread.
    if !engine.didPromoteInputThread {
        engine.didPromoteInputThread = true
        let period = Double(inNumberFrames) / engine.currentSampleRate
        RealtimeThread.promoteCurrentThread(
            periodSec: period,
            computationSec: period * 0.5,
            constraintSec: period * 0.85
        )
    }
    let tsIn = inTimeStamp.pointee

    // Prepare scratch input ABL (deinterleaved)
    guard let iu = engine.inputUnit,
          let inputBufferList = engine.inputBufferList else { return kAudioUnitErr_Uninitialized }
    let bytesPerFrame: UInt32 = 4
    let frames = Int(inNumberFrames)
    let bufferSize = inNumberFrames * bytesPerFrame
    // 🔧 Пристрій, що порушує MaximumFramesPerSlice, не має писати за межі преалокованих буферів
    guard inNumberFrames > 0, inNumberFrames <= engine.allocatedFrameCapacity else {
        return kAudioUnitErr_TooManyFramesToProcess
    }
    let inABL = UnsafeMutableAudioBufferListPointer(inputBufferList)
    for i in 0..<Int(engine.channelCount) {
        inABL[i].mDataByteSize = bufferSize
    }

    // If test tone enabled, synthesize into inABL and bypass AudioUnitRender
    if engine.testToneEnabled {
        let sr = Float(engine.currentSampleRate)
        let twoPi = Float.pi * 2.0
        let freq = engine.testToneFrequency
        var phase = engine.testTonePhase
        let inc = twoPi * freq / sr
        if let lPtr = inABL[0].mData?.assumingMemoryBound(to: Float.self) {
            for i in 0..<frames {
                let s = sinf(phase) * 0.2; lPtr[i] = s; phase += inc; if phase > twoPi { phase -= twoPi }
            }
            if engine.channelCount > 1, let rPtr = inABL[1].mData?.assumingMemoryBound(to: Float.self) {
                memcpy(rPtr, lPtr, frames * MemoryLayout<Float>.size)
            }
        }
        engine.testTonePhase = phase
    } else {
        // Pull from virtual audio input into inABL
        var ts = tsIn // safe to pass input timeline timestamp
        let status = AudioUnitRender(iu, ioActionFlags, &ts, 1, inNumberFrames, inputBufferList)
        if status != noErr {
            return status
        }
    }
    // ⚡ Metering tick is decided once per callback so the input level is taken
    // before EQ and the output level after it, from the same buffer.
    let meterTick = engine.peakMeter.shouldSample(frameCount: frames)
    if meterTick, let inL = inABL[0].mData?.assumingMemoryBound(to: Float.self) {
        let inR = engine.channelCount > 1 ? inABL[1].mData?.assumingMemoryBound(to: Float.self) : nil
        engine.peakMeter.sampleInput(
            bufferL: inL,
            bufferR: inR,
            frameCount: frames,
            channelCount: engine.channelCount
        )
    }

    // ⚡ Lock-free filter read: single atomic pointer load, no retain/release.
    if engine.isEnabled, engine.channelCount >= 1, let lPtr = inABL[0].mData?.assumingMemoryBound(to: Float.self) {
        engine.beginVDSPFilterRead()
        if let vdsp = engine.currentVDSPFilter() {
            if engine.channelCount > 1, let rPtr = inABL[1].mData?.assumingMemoryBound(to: Float.self) {
                vdsp.processStereo(lPtr, rPtr, frameCount: frames)
            } else {
                vdsp.processStereo(lPtr, lPtr, frameCount: frames)
            }
        } else if let fc = engine.filterChain {
            if engine.channelCount > 1, let rPtr = inABL[1].mData?.assumingMemoryBound(to: Float.self) {
                fc.processStereoBuffers(lPtr, rPtr, frameCount: frames)
            } else {
                fc.processBuffer(lPtr, frameCount: frames)
            }
        }
        engine.endVDSPFilterRead()
        // Nil filter = bypass.
    }

    // Write to ring buffer (deinterleaved) — delegated to SPSCRingBuffer
    if let inL = inABL[0].mData?.assumingMemoryBound(to: Float.self) {
        let inR = engine.channelCount > 1 ? inABL[1].mData?.assumingMemoryBound(to: Float.self) : nil
        engine.ringBuffer.write(inL: inL, inR: inR, frameCount: frames)
    }
    // ⚡ OPTIMIZED: Update peak meters — delegated to PeakMeter
    if meterTick, let inL = inABL[0].mData?.assumingMemoryBound(to: Float.self) {
        let inR = engine.channelCount > 1 ? inABL[1].mData?.assumingMemoryBound(to: Float.self) : nil
        engine.peakMeter.sampleOutput(
            bufferL: inL,
            bufferR: inR,
            frameCount: frames,
            channelCount: engine.channelCount
        )
    }

    // ⚡ OPTIMIZED: Send audio data to visualizer less frequently to reduce CPU overhead
    engine.visualizerCounter += frames
    if engine.visualizerCounter >= engine.visualizerInterval {
        engine.visualizerCounter = 0

        // ⚡ Lock-free callback read: single atomic pointer load, no retain/release.
        engine.beginVisualizerCallbackRead()
        if let box = engine.currentVisualizerCallback(),
           let inL = inABL[0].mData?.assumingMemoryBound(to: Float.self) {
            let inR = engine.channelCount > 1 ? inABL[1].mData?.assumingMemoryBound(to: Float.self) : inL
            if let rightPtr = inR {
                box.callback(inL, rightPtr, frames)
            }
        }
        engine.endVisualizerCallbackRead()
    }
    #if DEBUG
        let nanos = machNanosSince(diagStart)
        if nanos > engine.maxInputCallbackNanos { engine.maxInputCallbackNanos = nanos }
        engine.sumInputCallbackNanos &+= nanos
        engine.countInputCallbacks &+= 1
    #endif

    return noErr
}
