#!/usr/bin/env python3
import json
import os
from pathlib import Path
import re
import runpy
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


class ToolingPlatformTests(unittest.TestCase):
    def test_macos_runtime_suite_is_not_run_on_linux(self):
        root = Path(__file__).resolve().parent.parent
        main = runpy.run_path(str(root / "Scripts/verify_tooling.py"))["main"]
        for platform in ("linux", "darwin"):
            with self.subTest(platform=platform), patch("sys.platform", platform), patch("subprocess.run") as run:
                run.return_value.stdout = b""
                main()
                scripts = [call.args[0][1] for call in run.call_args_list if len(call.args[0]) > 1]
                self.assertEqual("Scripts/test_runtime_tools.py" in scripts, platform == "darwin")


class CoreAudioSetupTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix="systemeq-coreaudio-setup-")
        cls.addClassCleanup(cls.temp.cleanup)
        directory = Path(cls.temp.name)
        root = Path(__file__).resolve().parent.parent
        source = (root / "SystemEQ for Mac/Audio/CoreAudioEngine.swift").read_text()
        fixture = cls.fixture()
        for marker, signature in (
            ("__BUFFER_NEGOTIATION__", "enum AudioBufferSizeNegotiation {"),
            ("__SETUP_METHOD__", "    public func setup("),
            ("__CLEANUP_METHOD__", "    private func cleanup() -> Bool {"),
            ("__DISPOSE_UNIT_METHOD__", "    private func disposeAudioUnit(_ unit: AudioUnit) -> Bool {"),
        ):
            start = source.index(signature)
            cursor = source.index("{", start)
            depth = 1
            end = cursor + 1
            while depth:
                depth += (source[end] == "{") - (source[end] == "}")
                end += 1
            if fixture.count(marker) != 1:
                raise ValueError("Unexpected fixture marker: " + marker)
            fixture = fixture.replace(marker, source[start:end])
        path = directory / "setup.swift"
        path.write_text(fixture)
        cls.binary = directory / "setup-tests"
        result = subprocess.run(
            ["xcrun", "swiftc", "-module-cache-path", str(directory / "module-cache"),
             str(path), "-o", str(cls.binary)],
            capture_output=True, text=True, timeout=90,
        )
        if result.returncode:
            raise RuntimeError(result.stdout + result.stderr)

    def run_setup(self, status, stage):
        result = subprocess.run(
            [str(self.binary), str(status), stage],
            capture_output=True, text=True, timeout=15,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        observed = json.loads(result.stdout)
        self.assertEqual(observed["status"], status)
        self.assertEqual(observed["stage"], stage)
        return observed

    def test_input_callback_failure_aborts_setup_and_releases_input(self):
        for status in (-50, -10879, -666, 1):
            with self.subTest(status=status):
                observed = self.run_setup(status, "inputCallback")
                self.assertFalse(observed["isSetupComplete"])
                self.assertEqual(observed["cleanupCount"], 2)
                self.assertEqual(observed["restoreCount"], 1)
                self.assertEqual(observed["readyCount"], 0)
                self.assertIsNone(observed["inputUnit"])
                self.assertIsNone(observed["outputUnit"])

    def test_output_callback_failure_releases_both_units(self):
        observed = self.run_setup(-50, "outputRenderCallback")
        self.assertFalse(observed["isSetupComplete"])
        self.assertEqual(observed["failures"], ["outputRenderCallback"])
        self.assertEqual(observed["trace"].count("unit.dispose.2"), 1)

    def test_input_initialization_failure_releases_both_units(self):
        observed = self.run_setup(-50, "inputInitialize")
        self.assertFalse(observed["isSetupComplete"])
        self.assertEqual(observed["failures"], ["inputInitialize"])
        self.assertEqual(observed["trace"].count("unit.dispose.2"), 1)

    def test_successful_setup_keeps_units_and_reports_ready(self):
        observed = self.run_setup(0, "none")
        self.assertTrue(observed["isSetupComplete"])
        self.assertEqual(observed["readyCount"], 1)
        self.assertEqual(observed["failedCount"], 0)
        self.assertEqual(observed["restoreCount"], 0)

    @staticmethod
    def fixture():
        return r'''import Foundation

typealias AudioDeviceID = UInt32
__BUFFER_NEGOTIATION__
typealias AudioUnit = Int
let noErr: Int32 = 0
let kAudioFormatLinearPCM: UInt32 = 1
let kAudioFormatFlagIsFloat: UInt32 = 1
let kAudioFormatFlagIsPacked: UInt32 = 2
let kAudioFormatFlagIsNonInterleaved: UInt32 = 4
let kAudioUnitType_Output: UInt32 = 1
let kAudioUnitSubType_HALOutput: UInt32 = 2
let kAudioUnitManufacturer_Apple: UInt32 = 3
let kAudioOutputUnitProperty_EnableIO: UInt32 = 4
let kAudioOutputUnitProperty_CurrentDevice: UInt32 = 5
let kAudioOutputUnitProperty_SetInputCallback: UInt32 = 6
let kAudioUnitProperty_StreamFormat: UInt32 = 7
let kAudioUnitProperty_MaximumFramesPerSlice: UInt32 = 8
let kAudioUnitProperty_ShouldAllocateBuffer: UInt32 = 9
let kAudioUnitProperty_SetRenderCallback: UInt32 = 10
let kAudioUnitScope_Input: UInt32 = 11
let kAudioUnitScope_Output: UInt32 = 12
let kAudioUnitScope_Global: UInt32 = 13
let inputCaptureCallbackFunction = 1
let renderCallbackFunction = 2

struct AudioStreamBasicDescription {
    var mSampleRate: Double = 48000
    var mFormatID: UInt32 = 1
    var mFormatFlags: UInt32 = 7
    var mBytesPerPacket: UInt32 = 4
    var mFramesPerPacket: UInt32 = 1
    var mBytesPerFrame: UInt32 = 4
    var mChannelsPerFrame: UInt32 = 2
    var mBitsPerChannel: UInt32 = 32
    var mReserved: UInt32 = 0
}
struct AudioComponentDescription {
    var componentType: UInt32
    var componentSubType: UInt32
    var componentManufacturer: UInt32
    var componentFlags: UInt32
    var componentFlagsMask: UInt32
}
struct AURenderCallbackStruct {
    var inputProc: Int
    var inputProcRefCon: UnsafeMutableRawPointer?
}
enum Category { case engine }
enum Level { case error, debug }
func dlog(_ text: String, level: Level = .debug, category: Category) {}
var trace: [String] = []
var injectedStatus: Int32 = 0
var injectedStage = ""
var nextUnit = 0
func AudioComponentFindNext(_ prior: Int?, _ desc: inout AudioComponentDescription) -> Int? {
    trace.append("component.find")
    return 1
}
func AudioComponentInstanceNew(_ comp: Int, _ unit: inout AudioUnit?) -> Int32 {
    nextUnit += 1
    unit = nextUnit
    trace.append("unit.create.\(nextUnit)")
    return noErr
}
func AudioUnitSetProperty<T>(_ unit: AudioUnit, _ property: UInt32, _ scope: UInt32, _ element: UInt32, _ data: inout T, _ size: UInt32) -> Int32 {
    trace.append("property.\(unit).\(property)")
    if property == kAudioOutputUnitProperty_SetInputCallback && injectedStage == "inputCallback" { return injectedStatus }
    if property == kAudioUnitProperty_SetRenderCallback && injectedStage == "outputRenderCallback" { return injectedStatus }
    return noErr
}
func AudioUnitGetProperty(_ unit: AudioUnit, _ property: UInt32, _ scope: UInt32, _ element: UInt32, _ data: inout AudioStreamBasicDescription, _ size: inout UInt32) -> Int32 {
    data = AudioStreamBasicDescription()
    size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
    return noErr
}
func AudioUnitInitialize(_ unit: AudioUnit) -> Int32 {
    trace.append("unit.initialize.\(unit)")
    return unit == 1 && injectedStage == "inputInitialize" ? injectedStatus : noErr
}
@discardableResult func AudioOutputUnitStop(_ unit: AudioUnit) -> Int32 {
    trace.append("unit.stop.\(unit)")
    return noErr
}
@discardableResult func AudioUnitUninitialize(_ unit: AudioUnit) -> Int32 {
    trace.append("unit.uninitialize.\(unit)")
    return noErr
}
@discardableResult func AudioComponentInstanceDispose(_ unit: AudioUnit) -> Int32 {
    trace.append("unit.dispose.\(unit)")
    return noErr
}
class DiagnosticEventStore {
    static let shared = DiagnosticEventStore()
    var events: [String] = []
    func record(_ event: String, details: [String: String] = [:]) {
        events.append(event)
        trace.append(event)
    }
}
enum AudioClientFormatValidation {
    static func isValidHardwareFormat(_ format: AudioStreamBasicDescription, size: UInt32) -> Bool { true }
}
enum AudioSampleRateNegotiation {
    enum Result { case success(Double) }
    static func resolve(preferredRate: Double?, read: () -> (Double, Double), setInput: (Double) -> Bool, setOutput: (Double) -> Bool, pause: () -> Void) -> Result {
        trace.append("rates.negotiate")
        return .success(48000)
    }
    static func waitForRate(_ rate: Double, read: () -> (Double, Double), pause: () -> Void) -> Result { .success(rate) }
}
class Lock {
    func lock() { trace.append("cleanup") }
    func unlock() {}
}
struct AudioBuffer { var mData: UnsafeMutableRawPointer? }
class Buffers {
    var values: [AudioBuffer] = []
    var count: Int { values.count }
    subscript(index: Int) -> AudioBuffer {
        get { values[index] }
        set { values[index] = newValue }
    }
}
class RingBuffer {
    var isAllocated = false
    func deallocate() { isAllocated = false; trace.append("ring.deallocate") }
}
class Engine {
    var inputDeviceID: AudioDeviceID = 0
    var outputDeviceID: AudioDeviceID = 0
    var isRunning = false
    var isSetupComplete = false
    var currentSampleRate: Double = 0
    var channelCount: UInt32 = 0
    var inputUnit: AudioUnit?
    var outputUnit: AudioUnit?
    var inputBufferList: UnsafeMutablePointer<Int>?
    var outputBufferList: UnsafeMutablePointer<Int>?
    var inputABL: Buffers?
    var outputABL: Buffers?
    var outputScratchLeft: UnsafeMutablePointer<Float>?
    var outputScratchRight: UnsafeMutablePointer<Float>?
    var allocatedFrameCapacity: UInt32 = 0
    let cleanupLock = Lock()
    let ringBuffer = RingBuffer()
    var failures: [String] = []
    func stop() { isRunning = false }
    func restoreDeviceSampleRates() { trace.append("rates.restore") }
    func captureOriginalSampleRate(_ device: AudioDeviceID) -> Bool { trace.append("rates.capture.\(device)"); return true }
    func recordSetupFailure(_ stage: String, status: Int32? = nil) { failures.append(stage); trace.append("failure.\(stage)") }
    func deviceSampleRates() -> (Double, Double) { (48000, 48000) }
    func setDeviceSampleRate(_ device: AudioDeviceID, rate: Double) -> Bool { true }
    func rebuildActiveEQFilter(sampleRate: Double) {}
    func rebuildRoomFilter(sampleRate: Double) {}
    @discardableResult func setDeviceBufferFrameSize(_ device: AudioDeviceID, frames: UInt32) -> Bool { true }
    func deviceBufferFrameSize(_ device: AudioDeviceID) -> UInt32? { 256 }
    func logDeviceBufferInfo(_ device: AudioDeviceID, label: String) {}
    func setClientFormat(_ unit: AudioUnit, scope: UInt32, element: UInt32, format: AudioStreamBasicDescription) -> Bool { true }
    func verifyClientFormat(_ unit: AudioUnit, scope: UInt32, element: UInt32, expected: AudioStreamBasicDescription) -> Bool { true }
    func readMaximumFramesPerSlice(_ unit: AudioUnit?) -> UInt32? { 4096 }
    func allocateInputBuffer(maxFrames: UInt32, channels: UInt32) {
        inputBufferList = malloc(MemoryLayout<Int>.size)!.bindMemory(to: Int.self, capacity: 1)
        inputABL = Buffers()
        allocatedFrameCapacity = maxFrames
        trace.append("allocate.input")
    }
    func allocateOutputBuffer(maxFrames: UInt32, channels: UInt32) {
        outputBufferList = malloc(MemoryLayout<Int>.size)!.bindMemory(to: Int.self, capacity: 1)
        outputABL = Buffers()
        outputScratchLeft = .allocate(capacity: 1)
        outputScratchRight = .allocate(capacity: 1)
        trace.append("allocate.output")
    }
    func allocateRingBuffer(capacityFrames: Int, channels: UInt32) { ringBuffer.isAllocated = true; trace.append("allocate.ring") }
    func releaseFixture() { cleanup() }
__SETUP_METHOD__
__CLEANUP_METHOD__
__DISPOSE_UNIT_METHOD__
}
let status = Int32(CommandLine.arguments[1])!
injectedStatus = status
let stage = CommandLine.arguments[2]
injectedStage = stage
let engine = Engine()
engine.setup(inputDevice: 11, outputDevice: 22, preferredSampleRate: 48000)
let events = DiagnosticEventStore.shared.events
let observed: [String: Any] = [
    "status": status,
    "stage": stage,
    "isSetupComplete": engine.isSetupComplete,
    "inputUnit": engine.inputUnit as Any? ?? NSNull(),
    "outputUnit": engine.outputUnit as Any? ?? NSNull(),
    "failures": engine.failures,
    "events": events,
    "trace": trace,
    "cleanupCount": trace.filter { $0 == "cleanup" }.count,
    "restoreCount": trace.filter { $0 == "rates.restore" }.count,
    "readyCount": events.filter { $0 == "engine.setup.ready" }.count,
    "failedCount": events.filter { $0 == "engine.setup.failed" }.count
]
print(String(data: try! JSONSerialization.data(withJSONObject: observed, options: [.sortedKeys]), encoding: .utf8)!)
var errors: [String] = []
func require(_ condition: Bool, _ text: String) { if !condition { errors.append(text) } }
if status == noErr {
    require(engine.isSetupComplete, "healthy setup incomplete")
    require(engine.failures.isEmpty, "healthy failure reported")
    require(trace.filter { $0 == "cleanup" }.count == 1, "healthy unexpected cleanup")
    require(!trace.contains("rates.restore"), "healthy rates restored")
    require(events.filter { $0 == "engine.setup.ready" }.count == 1, "healthy ready count")
    require(!events.contains("engine.setup.failed"), "healthy failed event")
    require(trace.contains("unit.create.2"), "healthy output absent")
    require(trace.contains("unit.initialize.1") && trace.contains("unit.initialize.2"), "healthy initialization absent")
} else {
    require(!engine.isSetupComplete, "failed setup marked complete")
    require(engine.failures == [stage], "failure stage mismatch")
    require(engine.inputUnit == nil && engine.outputUnit == nil, "failed setup retains units")
    require(!events.contains("engine.setup.ready"), "failed setup ready event")
    require(events.filter { $0 == "engine.setup.failed" }.count == 1, "failed event count")
    require(trace.filter { $0 == "cleanup" }.count == 2, "deferred cleanup count")
    require(trace.filter { $0 == "rates.restore" }.count == 1, "rate restoration count")
    if stage == "inputCallback" {
        require(!trace.contains("unit.create.2"), "output created after callback failure")
        require(!trace.contains(where: { $0.hasPrefix("unit.initialize.") }), "unit initialized after callback failure")
    } else {
        require(trace.filter { $0 == "unit.dispose.2" }.count == 1, "output disposal count")
        require(trace.contains("unit.create.2"), "output creation missing")
        require(!trace.contains("unit.initialize.2"), "output initialized after failure")
        require(trace.contains("unit.initialize.1") == (stage == "inputInitialize"), "input initialize path mismatch")
    }
    require(!trace.contains(where: { $0.hasPrefix("allocate.") }), "buffers allocated after callback failure")
    require(trace.filter { $0 == "unit.dispose.1" }.count == 1, "input disposal count")
}
engine.releaseFixture()
if !errors.isEmpty {
    FileHandle.standardError.write(Data((errors.joined(separator: "\n") + "\n").utf8))
    exit(1)
}'''


class NativeSampleRateMetadataTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        root = Path(__file__).resolve().parent.parent
        source = (root / "SystemEQ for Mac/Audio/ProcessTapEngine.swift").read_text()
        methods = []
        for signature in (
            "    struct StartInfo {", "    enum StartError:", "    func start(",
            "    func stop() {", "    private func cleanup() {", "    private func cleanupTap() {",
            "    private func nominalSampleRate(", "    private func installSampleRateListener(",
            "    private func removeSampleRateListener() {",
        ):
            start = source.index(signature)
            end = source.index("{", start) + 1
            depth = 1
            while depth:
                depth += (source[end] == "{") - (source[end] == "}")
                end += 1
            methods.append(source[start:end])
        cls.temp = tempfile.TemporaryDirectory(prefix="systemeq-native-metadata-")
        cls.addClassCleanup(cls.temp.cleanup)
        probe = Path(cls.temp.name) / "native-metadata.swift"
        cls.binary = Path(cls.temp.name) / "native-metadata"
        probe.write_text(cls.TEMPLATE.replace("__NATIVE_METHODS__", "\n".join(methods)))
        result = subprocess.run(
            ["xcrun", "swiftc", "-module-cache-path", str(Path(cls.temp.name) / "module-cache"),
             str(probe), "-o", str(cls.binary)],
            cwd=root, capture_output=True, text=True, timeout=90,
        )
        if result.returncode:
            raise RuntimeError(result.stdout + result.stderr)

    def check_native_metadata(self, mode, scenario, rate=48000):
        result = subprocess.run(
            [str(self.binary), mode, scenario, str(rate)],
            capture_output=True, text=True, timeout=10,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        observed = json.loads(result.stdout)
        self.assertEqual(observed["mode"], mode)
        self.assertEqual(observed["scenario"], scenario)
        return observed

    def test_valid_native_rates_preserve_exact_values(self):
        for rate in (44100, 48000, 96000):
            with self.subTest(rate=rate):
                self.check_native_metadata("start", "valid", rate)

    def test_invalid_native_rate_metadata_aborts_before_processing(self):
        for scenario in ("status", "empty", "nan", "infinity", "negativeInfinity", "zero", "negative", "short", "oversized"):
            with self.subTest(scenario=scenario):
                self.check_native_metadata("start", scenario)

    def test_unchanged_native_rate_does_not_request_recovery(self):
        self.check_native_metadata("listener", "valid")

    def test_changed_or_invalid_native_rate_requests_recovery(self):
        for scenario in ("changed", "status", "empty", "nan", "zero", "short", "oversized"):
            with self.subTest(scenario=scenario):
                self.check_native_metadata("listener", scenario)

    TEMPLATE = r"""
import Foundation

typealias AudioObjectID = UInt32
typealias AudioDeviceID = UInt32
typealias OSStatus = Int32
typealias AudioDeviceIOProcID = Int
typealias AudioObjectPropertySelector = UInt32
typealias AudioObjectPropertyListenerBlock = (UInt32, UnsafePointer<AudioObjectPropertyAddress>?) -> Void
typealias CFDictionary = [String: Any]
let noErr: OSStatus = 0
let kAudioObjectUnknown: UInt32 = 0
let kAudioDevicePropertyDeviceUID: UInt32 = 1
let kAudioDevicePropertyBufferFrameSize: UInt32 = 2
let kAudioDevicePropertyNominalSampleRate: UInt32 = 3
let kAudioObjectPropertyScopeGlobal: UInt32 = 4
let kAudioObjectPropertyElementMain: UInt32 = 5
let kAudioTapPropertyFormat: UInt32 = 6
let processTapIOProc = 0
let kAudioAggregateDeviceNameKey = "name"
let kAudioAggregateDeviceUIDKey = "uid"
let kAudioAggregateDeviceIsPrivateKey = "private"
let kAudioAggregateDeviceIsStackedKey = "stacked"
let kAudioAggregateDeviceMainSubDeviceKey = "main"
let kAudioAggregateDeviceSubDeviceListKey = "subdevices"
let kAudioSubDeviceUIDKey = "deviceUID"
let kAudioSubDeviceInputChannelsKey = "inputchannels"
let kAudioAggregateDeviceTapListKey = "taps"
let kAudioSubTapUIDKey = "tapUID"
let kAudioSubTapDriftCompensationKey = "drift"
let kAudioAggregateDeviceTapAutoStartKey = "autostart"
struct AudioObjectPropertyAddress {
    var mSelector: UInt32
    var mScope: UInt32
    var mElement: UInt32
}
struct AudioStreamBasicDescription {}
enum Category { case engine }
enum Level { case error, debug }
func dlog(_ text: String, level: Level = .debug, category: Category) {}
class CATapDescription {
    enum MuteBehavior { case mutedWhenTapped }
    var name = ""
    var muteBehavior = MuteBehavior.mutedWhenTapped
    var isPrivate = false
    let uuid = UUID()
    init(stereoGlobalTapButExcludeProcesses: [AudioObjectID]) {}
}
struct ProcessTapInputSelection {
    let bufferIndex: Int
    static func select(tapFormat: AudioStreamBasicDescription, aggregateFormats: [AudioStreamBasicDescription], aggregateChannelCounts: [UInt32], aggregateStartingChannels: [UInt32], physicalInputChannelCount: UInt32?) -> ProcessTapInputSelection? {
        ProcessTapInputSelection(bufferIndex: 0)
    }
}
var trace: [String] = []
var reportedRate = 48000.0
var reportedSize = UInt32(MemoryLayout<Double>.size)
var metadataStatus: OSStatus = noErr
var metadataWritesValue = true
var installedListener: AudioObjectPropertyListenerBlock?
func AudioObjectGetPropertyData(_ device: AudioObjectID, _ address: inout AudioObjectPropertyAddress, _ qualifierSize: UInt32, _ qualifier: UnsafeRawPointer?, _ size: inout UInt32, _ value: inout Double) -> OSStatus {
    trace.append("metadata.read")
    size = reportedSize
    if metadataStatus == noErr && metadataWritesValue { value = reportedRate }
    return metadataStatus
}
func AudioObjectSetPropertyData(_ device: AudioObjectID, _ address: inout AudioObjectPropertyAddress, _ qualifierSize: UInt32, _ qualifier: UnsafeRawPointer?, _ size: UInt32, _ value: inout UInt32) -> OSStatus { noErr }
@discardableResult func AudioObjectAddPropertyListenerBlock(_ device: AudioObjectID, _ address: inout AudioObjectPropertyAddress, _ queue: DispatchQueue, _ block: @escaping AudioObjectPropertyListenerBlock) -> OSStatus {
    trace.append("listener.add")
    installedListener = block
    return noErr
}
@discardableResult func AudioObjectRemovePropertyListenerBlock(_ device: AudioObjectID, _ address: inout AudioObjectPropertyAddress, _ queue: DispatchQueue, _ block: AudioObjectPropertyListenerBlock) -> OSStatus {
    trace.append("listener.remove")
    installedListener = nil
    return noErr
}
func fakeCreateTap(_ description: CATapDescription, _ id: inout AudioObjectID) -> OSStatus {
    trace.append("tap.create")
    id = 10
    return noErr
}
func AudioHardwareCreateAggregateDevice(_ description: CFDictionary, _ id: inout AudioObjectID) -> OSStatus {
    trace.append("aggregate.create")
    id = 20
    return noErr
}
@discardableResult func AudioHardwareDestroyAggregateDevice(_ id: AudioObjectID) -> OSStatus {
    trace.append("aggregate.destroy")
    return noErr
}
@discardableResult func AudioHardwareDestroyProcessTap(_ id: AudioObjectID) -> OSStatus {
    trace.append("tap.destroy")
    return noErr
}
func AudioDeviceCreateIOProcID(_ device: AudioDeviceID, _ proc: Int, _ user: UnsafeMutableRawPointer, _ id: inout AudioDeviceIOProcID?) -> OSStatus {
    trace.append("ioproc.create")
    id = 30
    return noErr
}
func AudioDeviceStart(_ device: AudioDeviceID, _ id: AudioDeviceIOProcID) -> OSStatus {
    trace.append("device.start")
    return noErr
}
@discardableResult func AudioDeviceStop(_ device: AudioDeviceID, _ id: AudioDeviceIOProcID) -> OSStatus {
    trace.append("device.stop")
    return noErr
}
@discardableResult func AudioDeviceDestroyIOProcID(_ device: AudioDeviceID, _ id: AudioDeviceIOProcID) -> OSStatus {
    trace.append("ioproc.destroy")
    return noErr
}
class ProcessTapEngine {
    private let createTap = fakeCreateTap
    private let deviceUIDProvider: ((AudioDeviceID) -> String?)? = { _ in "fixture-device" }
    private var tapID: AudioObjectID = 0
    private var aggregateID: AudioObjectID = 0
    private var ioProcID: AudioDeviceIOProcID?
    private var outputDeviceID: AudioDeviceID = 0
    private var sampleRateListener: AudioObjectPropertyListenerBlock?
    private var inputSelection = ProcessTapInputSelection(bufferIndex: 0)
    var onSampleRateChange: (() -> Void)?
    var resourcesRemain: Bool { tapID != 0 || aggregateID != 0 || ioProcID != nil || sampleRateListener != nil || outputDeviceID != 0 }
    func stringProperty(_ objectID: AudioObjectID, selector: UInt32) -> String? { "fixture-device" }
    func ownProcessObject() -> AudioObjectID? { nil }
    func deviceBufferFrames(_ device: AudioDeviceID) -> UInt32 { 128 }
    func audioFormat(_ objectID: AudioObjectID, selector: UInt32) -> AudioStreamBasicDescription? { AudioStreamBasicDescription() }
    func inputStreams(_ device: AudioDeviceID) -> [AudioObjectID]? { [1] }
    func streamFormats(_ streams: [AudioObjectID]) -> [AudioStreamBasicDescription]? { [AudioStreamBasicDescription()] }
    func inputStreamChannelCounts(_ device: AudioDeviceID) -> [UInt32]? { [2] }
    func streamStartingChannels(_ streams: [AudioObjectID]) -> [UInt32]? { [1] }
    func inputChannelCount(_ device: AudioDeviceID) -> UInt32? { 0 }
__NATIVE_METHODS__
}
let mode = CommandLine.arguments[1]
let scenario = CommandLine.arguments[2]
let validRate = Double(CommandLine.arguments[3])!
func configure(_ scenario: String) {
    reportedRate = validRate
    reportedSize = UInt32(MemoryLayout<Double>.size)
    metadataStatus = noErr
    metadataWritesValue = true
    switch scenario {
    case "status": metadataStatus = -50
    case "empty": metadataWritesValue = false
    case "nan": reportedRate = .nan
    case "infinity": reportedRate = .infinity
    case "negativeInfinity": reportedRate = -.infinity
    case "zero": reportedRate = 0
    case "negative": reportedRate = -1
    case "short": reportedSize = 4
    case "oversized": reportedSize = 16
    case "changed": reportedRate = 96000
    default: break
    }
}
let engine = ProcessTapEngine()
var recoveryCount = 0
engine.onSampleRateChange = { recoveryCount += 1 }
var preparedRates: [Double] = []
func prepare(_ rate: Double, _ frames: UInt32) {
    trace.append("processor.prepare")
    preparedRates.append(rate)
}
var errors: [String] = []
func require(_ condition: Bool, _ text: String) { if !condition { errors.append(text) } }
if mode == "start" { configure(scenario) }
let result = engine.start(outputDeviceID: 77, prepareProcessing: prepare)
let succeeded: Bool
let sampleRate: String
let errorText: String
switch result {
case let .success(info):
    succeeded = true
    sampleRate = String(info.sampleRate)
    errorText = ""
case let .failure(error):
    succeeded = false
    sampleRate = ""
    errorText = String(describing: error)
}
if mode == "listener" {
    require(succeeded, "listener seed start failed")
    require(installedListener != nil, "sample rate listener absent")
    configure(scenario)
    installedListener?(0, nil)
    require(recoveryCount == (scenario == "valid" ? 0 : 1), "listener recovery count mismatch")
    require(trace.filter { $0 == "processor.prepare" }.count == 1, "listener rebuilt DSP inline")
    require(trace.filter { $0 == "device.start" }.count == 1, "listener started device inline")
} else if scenario == "valid" {
    require(succeeded, "valid rate start failed")
    require(sampleRate == String(validRate), "valid rate changed")
    require(preparedRates == [validRate], "valid DSP rate mismatch")
    require(trace.filter { $0 == "ioproc.create" }.count == 1, "valid IOProc count")
    require(trace.filter { $0 == "device.start" }.count == 1, "valid start count")
    require(trace.filter { $0 == "listener.add" }.count == 1, "valid listener count")
} else {
    require(!succeeded, "invalid metadata start succeeded")
    require(errorText == "sampleRate", "invalid metadata wrong failure")
    require(preparedRates.isEmpty, "invalid metadata prepared DSP")
    require(!trace.contains("ioproc.create"), "invalid metadata created IOProc")
    require(!trace.contains("device.start"), "invalid metadata started device")
    require(!trace.contains("listener.add"), "invalid metadata installed listener")
    require(trace.filter { $0 == "tap.create" }.count == 1, "tap creation count")
    require(trace.filter { $0 == "aggregate.create" }.count == 1, "aggregate creation count")
    require(trace.filter { $0 == "tap.destroy" }.count == 1, "tap destruction count")
    require(trace.filter { $0 == "aggregate.destroy" }.count == 1, "aggregate destruction count")
    require(!engine.resourcesRemain, "invalid metadata retains resources")
}
let beforeStop = trace
let resourcesBeforeStop = engine.resourcesRemain
engine.stop()
require(!engine.resourcesRemain, "stop retains resources")
require(installedListener == nil, "stop retains HAL listener")
require(trace.filter { $0 == "tap.destroy" }.count == 1, "stop double destroys tap")
require(trace.filter { $0 == "aggregate.destroy" }.count == 1, "stop double destroys aggregate")
if succeeded {
    require(trace.filter { $0 == "ioproc.destroy" }.count == 1, "stop IOProc destruction count")
    require(trace.filter { $0 == "device.stop" }.count == 1, "stop device count")
    require(trace.filter { $0 == "listener.remove" }.count == 1, "stop listener removal count")
}
let observed: [String: Any] = [
    "mode": mode, "scenario": scenario, "succeeded": succeeded,
    "sampleRate": sampleRate, "error": errorText, "preparedRates": preparedRates.map { String($0) },
    "recoveryCount": recoveryCount, "resourcesBeforeStop": resourcesBeforeStop,
    "traceBeforeStop": beforeStop, "trace": trace, "assertionErrors": errors
]
print(String(data: try! JSONSerialization.data(withJSONObject: observed, options: [.sortedKeys]), encoding: .utf8)!)
if !errors.isEmpty { exit(1) }
"""


class RoutingWakeLifecycleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix="systemeq-wake-lifecycle-")
        cls.addClassCleanup(cls.temp.cleanup)
        directory = Path(cls.temp.name)
        root = Path(__file__).resolve().parent.parent
        source = (root / "SystemEQ for Mac/Audio/AudioRouter.swift").read_text()

        def extract(signature):
            start = source.index(signature)
            cursor = source.index("{", start)
            end, depth = cursor + 1, 1
            while depth:
                depth += (source[end] == "{") - (source[end] == "}")
                end += 1
            return source[start:end]

        declarations = "\n".join(extract(signature) for signature in (
            "@MainActor\nfinal class RoutingWakeRecovery {",
            "enum RoutingRequestReason: String, CaseIterable {",
            "enum AudioRoutingRequestPolicy {",
        ))
        methods = "\n".join(extract(signature) for signature in (
            "    public var isRoutingOwned: Bool {",
            "    func enableEQRouting(",
            "    func disableEQRouting(persistEnabledState: Bool = true) {",
            "    func handleSystemEvent(_ event: SystemEvent) {",
            "    private func handleDefaultOutputChange() {",
            "    private func handleDeviceTopologyChange() {",
            "    private func suspendRoutingForSleep() {",
            "    private func resumeRoutingAfterWake() {",
        ))
        fixture = cls.TEMPLATE.replace("__DECLARATIONS__", declarations).replace("__METHODS__", methods)
        path = directory / "wake.swift"
        path.write_text(fixture)
        cls.binary = directory / "wake-tests"
        result = subprocess.run(
            ["xcrun", "swiftc", "-parse-as-library", "-module-cache-path", str(directory / "module-cache"),
             str(path), "-o", str(cls.binary)],
            capture_output=True, text=True, timeout=90,
        )
        if result.returncode:
            raise RuntimeError(result.stdout + result.stderr)

    def run_scenario(self, scenario):
        for backend in ("blackHole", "native"):
            with self.subTest(scenario=scenario, backend=backend):
                result = subprocess.run([str(self.binary), scenario, backend], capture_output=True, text=True, timeout=15)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(json.loads(result.stdout)["scenario"], scenario)

    def test_darkwake_defers_topology_default_output_and_all_automatic_requests(self):
        self.run_scenario("darkwake")

    def test_events_during_wake_delay_preserve_single_restart(self):
        self.run_scenario("wake-delay")

    def test_second_sleep_rejects_refresh_from_previous_wake(self):
        self.run_scenario("second-sleep")

    def test_manual_disable_during_refresh_cancels_restart(self):
        self.run_scenario("disable")

    def test_manual_enable_supersedes_pending_wake(self):
        self.run_scenario("enable")

    def test_sleep_cancels_inflight_device_and_default_output_refresh(self):
        for scenario in ("device-refresh", "output-refresh"):
            self.run_scenario(scenario)

    def test_awake_recovery_and_disabled_sleep_keep_existing_behavior(self):
        for scenario in ("awake", "inactive"):
            self.run_scenario(scenario)

    def test_actual_wake_start_failure_preserves_intent_without_false_running(self):
        self.run_scenario("wake-failure")

    def test_failed_resource_release_does_not_restore_device_rates(self):
        self.run_scenario("release-failure")

    TEMPLATE = r'''import Foundation

typealias AudioDeviceID = UInt32
struct AudioDevice {
    let id: AudioDeviceID
    let name: String
    let uid: String
}
enum ActiveAudioRoutingBackend: String { case none, native, blackHole }
enum LogLevel { case info, warning, error }
enum LogCategory { case routing }
func dlog(_ message: String, level: LogLevel = .info, category: LogCategory) {}
enum AppConstants { enum DeviceNames { static let blackHoleLowercase = "blackhole" } }
final class UserDefaults {
    static let standard = UserDefaults()
    var values: [String: Any] = ["eqWasEnabled": true]
    func set(_ value: Any, forKey key: String) { values[key] = value }
}
final class DiagnosticEventStore {
    static let shared = DiagnosticEventStore()
    var events: [String] = []
    func record(_ name: String, details: [String: String] = [:]) { events.append(name) }
}
final class CoreAudioEngine {
    static let shared = CoreAudioEngine()
    var isRunning = true
    var isEnabled = true
    var currentInputDeviceID: AudioDeviceID = 1
    var currentOutputDeviceID: AudioDeviceID = 2
    var rateRestores = 0
    var resourceReleaseSucceeds = true
    func stop() { isRunning = false }
    func releaseDeviceResources() -> Bool { stop(); return resourceReleaseSucceeds }
    func setEnabled(_ enabled: Bool) { isEnabled = enabled }
    func restoreDeviceSampleRates() { rateRestores += 1 }
}
final class ProcessTapEngine { func stop() {} }
__DECLARATIONS__
@MainActor final class Gate {
    var entered = false
    var continuation: CheckedContinuation<Void, Never>?
    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            entered = true
        }
    }
    func release() { continuation?.resume(); continuation = nil }
}
@MainActor final class AudioRouter {
    enum SystemEvent { case devicesChanged, defaultOutputChanged, willSleep, didWake }
    let isTestHost = false
    let eventHandler: ((SystemEvent) -> Void)? = nil
    let wakeRecovery = RoutingWakeRecovery()
    var deviceChangeDebounceTask: Task<Void, Never>?
    var defaultOutputChangeTask: Task<Void, Never>?
    var activeBackend = ActiveAudioRoutingBackend.blackHole
    var activeInputUID: String? = "blackhole"
    var activeOutputUID: String? = "physical"
    var preferredOutputUID: String? = "physical"
    let originalOutputUIDKey = "original"
    var originalSystemOutputDevice: AudioDevice? = AudioDevice(id: 2, name: "Scarlett", uid: "physical")
    var selectedOutputDevice: AudioDevice? = AudioDevice(id: 2, name: "Scarlett", uid: "physical")
    var inputDevices = [AudioDevice(id: 1, name: "BlackHole", uid: "blackhole")]
    var outputDevices = [AudioDevice(id: 2, name: "Scarlett", uid: "physical")]
    var processTapEngineStorage: AnyObject?
    var systemOutput = AudioDevice(id: 1, name: "BlackHole", uid: "blackhole")
    var hardwareReady = true
    var starts: [RoutingRequestReason] = []
    var refreshCount = 0
    var outputRestores = 0
    var gate: Gate?
    var virtualOutput: AudioDevice? { AudioDevice(id: 1, name: "BlackHole", uid: "blackhole") }
    func blackHoleOutputDevice() -> AudioDevice? { virtualOutput }
    func currentSystemOutputDevice() -> AudioDevice? { systemOutput }
    func findBestPhysicalOutputDevice() -> AudioDevice? { outputDevices.first }
    func removeBlackHoleVolumeListeners() {}
    func restoreOriginalSystemOutputDevice() { outputRestores += 1 }
    func refreshDevices() async { refreshCount += 1; if let gate { await gate.wait() } }
    func startEQRouting(forceRestart: Bool, persistEnabledStateOnFailure: Bool,
                        reason: RoutingRequestReason, blackHoleSampleRate: Double?) -> Bool {
        starts.append(reason)
        guard hardwareReady else { return false }
        CoreAudioEngine.shared.isRunning = true
        CoreAudioEngine.shared.isEnabled = true
        if activeBackend == .none { activeBackend = .blackHole }
        activeOutputUID = selectedOutputDevice?.uid
        return true
    }
    func topology() { handleDeviceTopologyChange() }
    func defaultChanged() { handleDefaultOutputChange() }
    __METHODS__
}
@main enum WakeTests {
    @MainActor static func expect(_ condition: Bool, _ message: String) {
        if !condition {
            FileHandle.standardError.write(Data((message + "\n").utf8))
            exit(1)
        }
    }
    @MainActor static func waitUntil(_ condition: () -> Bool) async throws {
        let started = Date()
        while !condition() {
            expect(Date().timeIntervalSince(started) < 6, "Timed out waiting for lifecycle transition")
            try await Task.sleep(nanoseconds: 1_000_000)
        }
    }
    @MainActor static func pendingWake(_ router: AudioRouter, _ gate: Gate) -> Task<Void, Never>? {
        router.wakeRecovery.resume(wait: {}, refresh: { await gate.wait() }, restart: {
            router.enableEQRouting(forceRestart: true, reason: .wake)
        })
    }
    @MainActor static func main() async throws {
        let scenario = CommandLine.arguments[1]
        let router = AudioRouter()
        let core = CoreAudioEngine.shared
        router.activeBackend = CommandLine.arguments[2] == "native" ? .native : .blackHole
        if router.activeBackend == .native { router.activeInputUID = nil }
        switch scenario {
        case "darkwake", "wake-delay":
            router.handleSystemEvent(.willSleep)
            expect(router.wakeRecovery.isSuspended && !core.isRunning, "Sleep failed to retain paused intent")
            if scenario == "wake-delay" { router.handleSystemEvent(.didWake) }
            router.hardwareReady = false
            router.inputDevices = []
            router.outputDevices = []
            router.systemOutput = AudioDevice(id: 3, name: "HDMI", uid: "fallback")
            router.defaultChanged()
            router.topology()
            for reason in RoutingRequestReason.allCases where reason != .request {
                expect(!router.enableEQRouting(forceRestart: true, reason: reason), "Premature restart reported success")
            }
            expect(router.starts.isEmpty, "Automatic event started engine before full wake")
            expect(router.wakeRecovery.isSuspended, "Automatic event erased wake intent")
            expect(router.preferredOutputUID == "physical", "DarkWake changed preferred output")
            expect(router.outputRestores == 0 && core.rateRestores == 0, "DarkWake triggered failure cleanup")
            expect(!DiagnosticEventStore.shared.events.contains("routing.disable.request"), "DarkWake disabled routing")
            router.hardwareReady = true
            router.inputDevices = [AudioDevice(id: 1, name: "BlackHole", uid: "blackhole")]
            router.outputDevices = [AudioDevice(id: 2, name: "Scarlett", uid: "physical")]
            router.handleSystemEvent(.didWake)
            try await waitUntil { !router.wakeRecovery.isSuspended }
            expect(router.starts == [.wake] && core.isRunning, "Full wake failed to restart exactly once")
        case "second-sleep", "disable", "enable":
            router.handleSystemEvent(.willSleep)
            let gate = Gate()
            let first = pendingWake(router, gate)
            try await waitUntil { gate.entered }
            if scenario == "second-sleep" { router.handleSystemEvent(.willSleep) }
            else if scenario == "disable" { router.disableEQRouting() }
            else { expect(router.enableEQRouting(), "Manual enable was blocked") }
            gate.release()
            await first?.value
            if scenario == "second-sleep" {
                expect(router.starts.isEmpty && router.wakeRecovery.shouldResume, "Stale refresh consumed second sleep")
                let second = router.wakeRecovery.resume(wait: {}, refresh: {}, restart: {
                    router.enableEQRouting(forceRestart: true, reason: .wake)
                })
                await second?.value
                expect(router.starts == [.wake] && core.isRunning, "Second wake did not restore routing")
            } else if scenario == "disable" {
                router.topology(); router.defaultChanged()
                expect(router.starts.isEmpty && !core.isRunning && !core.isEnabled, "Disabled EQ was restarted")
                expect(!router.wakeRecovery.isSuspended, "Disable retained restart ownership")
                expect(UserDefaults.standard.values["eqWasEnabled"] as? Bool == false, "Disable lost user intent")
            } else {
                expect(router.starts == [.request] && core.isRunning, "Stale wake duplicated manual enable")
                expect(!router.wakeRecovery.isSuspended, "Manual enable retained stale ownership")
            }
        case "device-refresh", "output-refresh":
            let gate = Gate()
            router.gate = gate
            router.handleSystemEvent(scenario == "device-refresh" ? .devicesChanged : .defaultOutputChanged)
            let task = scenario == "device-refresh" ? router.deviceChangeDebounceTask : router.defaultOutputChangeTask
            try await waitUntil { gate.entered }
            router.handleSystemEvent(.willSleep)
            expect(router.deviceChangeDebounceTask == nil && router.defaultOutputChangeTask == nil, "Sleep retained debounce tasks")
            gate.release()
            await task?.value
            expect(router.starts.isEmpty && router.wakeRecovery.shouldResume, "In-flight refresh restarted during sleep")
        case "awake":
            core.isRunning = false
            router.topology()
            expect(router.starts == [.deviceRecovery] && core.isRunning, "Normal awake recovery was suppressed")
            router.systemOutput = AudioDevice(id: 3, name: "HDMI", uid: "fallback")
            router.defaultChanged()
            expect(router.starts.last == .systemOutputChanged && router.preferredOutputUID == "fallback", "Awake output selection was suppressed")
        case "inactive":
            router.disableEQRouting()
            let baselineRestores = core.rateRestores
            router.handleSystemEvent(.willSleep)
            router.handleSystemEvent(.didWake)
            router.topology()
            expect(router.starts.isEmpty && !router.wakeRecovery.isSuspended, "Inactive sleep created restart intent")
            expect(core.rateRestores >= baselineRestores, "Unexpected sample-rate state")
        case "release-failure":
            core.resourceReleaseSucceeds = false
            router.disableEQRouting()
            expect(core.rateRestores == 0, "Failed resource release restored sample rates")
            expect(!core.isRunning && !core.isEnabled, "Disable retained active processing")
        case "wake-failure":
            router.handleSystemEvent(.willSleep)
            router.hardwareReady = false
            let pending = router.wakeRecovery.resume(wait: {}, refresh: {}, restart: {
                router.enableEQRouting(forceRestart: true, reason: .wake)
            })
            await pending?.value
            expect(router.starts == [.wake] && !core.isRunning && !core.isEnabled, "Failed wake was reported as running")
            expect(UserDefaults.standard.values["eqWasEnabled"] as? Bool == true, "Failed wake erased saved enabled intent")
            expect(!router.wakeRecovery.isSuspended, "Failed wake leaked pending task")
        default: fatalError("Unknown scenario")
        }
        let result: [String: Any] = ["scenario": scenario, "starts": router.starts.map(\.rawValue)]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class RoutingActivityStatusTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        root = Path(__file__).resolve().parent.parent
        source = (root / "SystemEQ for Mac/Audio/AudioRouter.swift").read_text()
        methods = []
        for signature in (
            "    init(\n        isTestHost: Bool,", "    private func bindRoutingStatus() {",
            "    private func updateStatus() {", "    public var isRoutingOwned: Bool {",
        ):
            start = source.index(signature)
            end = source.index("{", start) + 1
            depth = 1
            while depth:
                depth += (source[end] == "{") - (source[end] == "}")
                end += 1
            methods.append(source[start:end])
        cls.temp = tempfile.TemporaryDirectory(prefix="systemeq-routing-status-")
        cls.addClassCleanup(cls.temp.cleanup)
        probe = Path(cls.temp.name) / "routing-status.swift"
        cls.binary = Path(cls.temp.name) / "routing-status"
        probe.write_text(cls.TEMPLATE.replace("__ROUTING_METHODS__", "\n".join(methods)))
        result = subprocess.run(
            ["xcrun", "swiftc", "-module-cache-path", str(Path(cls.temp.name) / "module-cache"),
             str(probe), "-o", str(cls.binary)],
            cwd=root, capture_output=True, text=True, timeout=90,
        )
        if result.returncode:
            raise RuntimeError(result.stdout + result.stderr)

    def check_routing_status(self, scenario):
        result = subprocess.run(
            [str(self.binary), scenario],
            capture_output=True, text=True, timeout=10,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        observed = json.loads(result.stdout)
        self.assertEqual(observed["scenario"], scenario)
        self.assertEqual(observed["assertionErrors"], [])
        return observed

    def test_test_host_initializer_avoids_core_and_observers(self):
        self.check_routing_status("testHost")

    def test_initializer_binds_routing_status_before_observers(self):
        self.check_routing_status("initWiring")

    def test_readiness_refresh_preserves_runtime_activity(self):
        for scenario in ("readyOff", "refreshActive", "failedRestart"):
            with self.subTest(scenario=scenario):
                self.check_routing_status(scenario)

    def test_engine_and_backend_transitions_publish_current_activity(self):
        for scenario in ("blackHoleOrder", "nativeOrder", "runningNoBackend", "directEngineChanges", "sleepOwnership", "backendSwitch", "deduplication"):
            with self.subTest(scenario=scenario):
                self.check_routing_status(scenario)

    def test_routing_binding_releases_router(self):
        self.check_routing_status("lifecycle")

    TEMPLATE = r"""
import Combine
import Foundation

enum ActiveAudioRoutingBackend: String { case none, native, blackHole }
enum AudioRoutingBackendPreference { case automatic, native, blackHole }
struct AudioDevice {}
var singletonAccesses = 0
final class CoreAudioEngine: ObservableObject {
    static var shared: CoreAudioEngine {
        singletonAccesses += 1
        return fixtureCore
    }
    @Published var isRunning = false
    @Published var isEnabled = false
}
let fixtureCore = CoreAudioEngine()
public final class AudioRouter: ObservableObject {
    enum SystemEvent { case devicesChanged, defaultOutputChanged, willSleep, didWake }
    private let isTestHost: Bool
    private let eventHandler: ((SystemEvent) -> Void)?
    @Published var selectedInputDevice: AudioDevice?
    @Published var selectedOutputDevice: AudioDevice?
    @Published var blackHoleDetected = false
    @Published var statusMessage = "Checking devices..."
    @Published var isRoutingActive = false
    @Published private(set) var activeBackend: ActiveAudioRoutingBackend = .none
    var backendPreference: AudioRoutingBackendPreference = .automatic
    private var activeInputUID: String?
    func fixtureSetBackend(_ backend: ActiveAudioRoutingBackend) { activeBackend = backend }
    func fixtureRefresh() { updateStatus() }
    func fixtureBlackHoleReady() {
        backendPreference = .blackHole
        blackHoleDetected = true
        selectedInputDevice = AudioDevice()
        selectedOutputDevice = AudioDevice()
    }
    func fixtureNativeReady() {
        backendPreference = .native
        selectedOutputDevice = AudioDevice()
        selectedInputDevice = nil
        blackHoleDetected = false
    }
__ROUTING_METHODS__
}
let scenario = CommandLine.arguments[1]
let testHost = scenario == "testHost"
var observerCalls = 0
var accessesDuringObserver = -1
var activeDuringObserver = false
let router = AudioRouter(isTestHost: testHost, installObservers: { router in
    observerCalls += 1
    accessesDuringObserver = singletonAccesses
    if scenario == "initWiring" {
        router.fixtureSetBackend(.native)
        fixtureCore.isEnabled = true
        fixtureCore.isRunning = true
        activeDuringObserver = router.isRoutingActive
    }
})
var errors: [String] = []
var checkpoints: [[String: Any]] = []
var history: [Bool] = []
let subscription = router.$isRoutingActive.sink { history.append($0) }
func require(_ condition: Bool, _ text: String) { if !condition { errors.append(text) } }
func check(_ name: String, _ expected: Bool) {
    checkpoints.append(["name": name, "actual": router.isRoutingActive, "expected": expected])
    require(router.isRoutingActive == expected, name)
}
func activate(_ backend: ActiveAudioRoutingBackend) {
    router.fixtureSetBackend(backend)
    fixtureCore.isEnabled = true
    fixtureCore.isRunning = true
}
if testHost {
    require(singletonAccesses == 0, "test host accessed Core singleton")
    require(observerCalls == 0, "test host installed observers")
    fixtureCore.isRunning = true
    fixtureCore.isEnabled = true
    router.fixtureSetBackend(.native)
    check("test host has no routing subscription", false)
    require(!router.isRoutingOwned, "test host claims ownership")
    require(singletonAccesses == 0, "test host ownership accessed Core singleton")
} else {
    require(observerCalls == 1, "observer installation count")
    require(accessesDuringObserver > 0, "binding missing before observer installation")
    switch scenario {
    case "initWiring":
        require(activeDuringObserver, "observer cannot see initialized binding")
        check("init observer mutations publish active", true)
    case "readyOff":
        router.fixtureBlackHoleReady()
        router.fixtureRefresh()
        check("ready BlackHole while engine off", false)
        require(router.statusMessage == "✅ Ready for routing", "BlackHole readiness message changed")
        router.fixtureNativeReady()
        router.fixtureRefresh()
        check("ready native while engine off", false)
        if #available(macOS 14.4, *) {
            require(router.statusMessage == "✅ Ready for native routing", "native readiness message changed")
        } else {
            require(router.statusMessage == "⚠️ BlackHole not installed", "unsupported native readiness message changed")
        }
    case "blackHoleOrder":
        fixtureCore.isEnabled = true
        check("enabled with no engine/backend", false)
        fixtureCore.isRunning = true
        check("running with no backend", false)
        router.fixtureSetBackend(.blackHole)
        check("BlackHole running enabled backend", true)
    case "nativeOrder":
        router.fixtureSetBackend(.native)
        check("native backend only", false)
        fixtureCore.isRunning = true
        check("native running but disabled", false)
        fixtureCore.isEnabled = true
        check("native enabled last", true)
    case "runningNoBackend":
        fixtureCore.isEnabled = true
        fixtureCore.isRunning = true
        check("engine running with backend none", false)
    case "directEngineChanges":
        activate(.native)
        check("native activation", true)
        fixtureCore.isRunning = false
        check("runtime engine stop", false)
        fixtureCore.isRunning = true
        check("runtime engine restart", true)
        fixtureCore.isEnabled = false
        check("EQ disabled directly", false)
        fixtureCore.isEnabled = true
        check("EQ reenabled directly", true)
    case "sleepOwnership":
        activate(.blackHole)
        check("pre-sleep routing", true)
        fixtureCore.isRunning = false
        check("sleep stops audible routing", false)
        require(router.isRoutingOwned, "sleep lost retained BlackHole ownership")
        router.fixtureBlackHoleReady()
        router.fixtureRefresh()
        check("sleep readiness refresh", false)
        require(router.isRoutingOwned, "refresh lost retained ownership")
    case "failedRestart":
        activate(.native)
        check("before failed restart", true)
        fixtureCore.isRunning = false
        router.fixtureNativeReady()
        for index in 0..<3 {
            router.fixtureRefresh()
            check("failed restart refresh \(index)", false)
        }
        require(router.isRoutingOwned, "failed restart lost retained backend ownership")
    case "backendSwitch":
        activate(.native)
        check("native before switch", true)
        router.fixtureSetBackend(.none)
        check("backend removed while engine running", false)
        router.fixtureSetBackend(.blackHole)
        check("BlackHole backend adopted", true)
        fixtureCore.isRunning = false
        router.fixtureSetBackend(.native)
        check("native backend during stopped switch", false)
        fixtureCore.isRunning = true
        check("native switch restarts engine", true)
    case "refreshActive":
        activate(.blackHole)
        check("active routing before refresh", true)
        router.backendPreference = .blackHole
        router.blackHoleDetected = false
        router.fixtureRefresh()
        check("missing readiness metadata cannot clobber running routing", true)
        require(router.statusMessage == "⚠️ BlackHole not installed", "unavailable readiness message changed")
        router.blackHoleDetected = true
        router.selectedInputDevice = nil
        router.fixtureRefresh()
        check("missing selected input cannot clobber running routing", true)
        router.fixtureBlackHoleReady()
        let count = history.count
        for index in 0..<3 {
            router.fixtureRefresh()
            check("active readiness refresh \(index)", true)
        }
        require(history.count == count, "readiness refresh republishes routing flag")
    case "deduplication":
        activate(.native)
        check("active for deduplication", true)
        let count = history.count
        fixtureCore.isRunning = true
        fixtureCore.isEnabled = true
        router.fixtureSetBackend(.native)
        require(history.count == count, "identical routing state was republished")
        fixtureCore.isEnabled = false
        check("disable emits inactive", false)
        require(history.count == count + 1, "binding has duplicate subscriptions")
        fixtureCore.isEnabled = false
        require(history.count == count + 1, "duplicate inactive state was republished")
    case "lifecycle":
        weak var weakRouter: AudioRouter?
        func createTemporaryRouter() {
            let temporaryRouter = AudioRouter(isTestHost: false, installObservers: { _ in })
            weakRouter = temporaryRouter
            temporaryRouter.fixtureSetBackend(.native)
            fixtureCore.isEnabled = true
            fixtureCore.isRunning = true
            require(temporaryRouter.isRoutingActive, "temporary router was not bound")
        }
        createTemporaryRouter()
        require(weakRouter == nil, "routing subscription retained router")
    default: errors.append("unknown scenario")
    }
}
let observed: [String: Any] = [
    "scenario": scenario, "checkpoints": checkpoints, "history": history,
    "singletonAccesses": singletonAccesses, "observerCalls": observerCalls,
    "accessesDuringObserver": accessesDuringObserver, "activeDuringObserver": activeDuringObserver,
    "assertionErrors": errors
]
print(String(data: try! JSONSerialization.data(withJSONObject: observed, options: [.sortedKeys]), encoding: .utf8)!)
withExtendedLifetime(subscription) {}
if !errors.isEmpty { exit(1) }
"""


class CalibrationSessionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        root = Path(__file__).resolve().parent.parent
        view = (root / "SystemEQ for Mac/Features/CalibrationView.swift").read_text()
        engine = (root / "SystemEQ for Mac/Audio/CalibrationEngine.swift").read_text()
        room = (root / "SystemEQ for Mac/Features/SubjectiveRoomTuningView.swift").read_text()

        def block(source, signature):
            start = source.index(signature)
            opening = source.index("{", start)
            end, depth = opening + 1, 1
            while depth:
                depth += (source[end] == "{") - (source[end] == "}")
                end += 1
            return source[start:end], source[opening + 1:end - 1]

        fixture = cls.TEMPLATE
        for marker, text in (
            ("__PROFILE__", block(engine, "public struct CalibrationProfile:")[0]),
            ("__ROOM_SAVE__", block(room, "    private func saveProfile() {")[0]),
            ("__ENGINE_METHODS__", "\n".join(block(engine, signature)[0] for signature in (
                "    public func startCalibration(mode:", "    public func endCalibration(mode:",
                "    func equalLoudnessProfile(name:",
            ))),
            ("__VIEW_METHODS__", "\n".join(block(view, signature)[0] for signature in (
                "    private func finishCalibration()", "    private func saveProfile()",
            ))),
            ("__DISAPPEAR__", block(view, ".onDisappear {")[1]),
            ("__PREVIOUS__", block(view[view.index("// Navigation"):], "Button(action: {")[1]),
            ("__CONTINUE__", block(view[view.index("// Continue button"):], "Button(action: {")[1]),
            ("__CANCEL__", block(view[view.index("private var newProfileSheet:"):],
                                 "Button(localization.localized(.cancel)) {")[1]),
        ):
            if fixture.count(marker) != 1:
                raise ValueError("Unexpected calibration fixture marker: " + marker)
            fixture = fixture.replace(marker, text)
        cls.temp = tempfile.TemporaryDirectory(prefix="systemeq-calibration-session-")
        cls.addClassCleanup(cls.temp.cleanup)
        directory = Path(cls.temp.name)
        source = directory / "calibration.swift"
        source.write_text(fixture)
        cls.binary = directory / "calibration"
        result = subprocess.run(
            ["xcrun", "swiftc", "-module-cache-path", str(directory / "module-cache"),
             str(source), "-o", str(cls.binary)], capture_output=True, text=True, timeout=90,
        )
        if result.returncode:
            raise RuntimeError(result.stdout + result.stderr)

    def check_session(self, scenario):
        result = subprocess.run([str(self.binary), scenario], capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        observed = json.loads(result.stdout)
        self.assertEqual(observed["scenario"], scenario)
        self.assertEqual(observed["cases"], 4)
        self.assertEqual(observed["assertionErrors"], [])

    def test_save_restores_eq_without_activating_profile(self):
        self.check_session("save")

    def test_close_restores_eq_and_stops_playback(self):
        self.check_session("close")

    def test_previous_band_keeps_session_and_back_ends_it(self):
        self.check_session("back")

    def test_back_allows_a_different_calibration_mode(self):
        self.check_session("modeChange")

    def test_cancel_profile_sheet_keeps_session_until_close(self):
        self.check_session("cancel")

    def test_invalid_profile_keeps_progress_until_close(self):
        self.check_session("invalid")

    def test_repeated_close_is_idle_and_new_session_can_start(self):
        self.check_session("restart")

    def test_room_save_serializes_real_notch_parameters(self):
        self.check_session("roomSave")

    def test_room_save_rejects_invalid_notches_before_mutation(self):
        self.check_session("roomInvalid")

    TEMPLATE = r"""
import Foundation
enum LogCategory { case calibration }
func dlog(_ text: String, category: LogCategory) {}
public enum CalibrationType: String, Codable { case equalLoudness, roomCorrection }
public enum CalibrationMode { case clean, combined }
__PROFILE__
final class Core {
    var isEnabled = false
    var changes: [Bool] = []
    func setEnabled(_ value: Bool) { isEnabled = value; changes.append(value) }
}
final class AudioEngine { let coreAudioEngine = Core() }
final class CalibrationEngine {
    let eqEngine = AudioEngine()
    var savedEQEnabled = false
    var isCalibrating = false
    var isReferenceSet = false
    var profiles: [CalibrationProfile] = []
    let standardFrequencies: [Double] = [20, 25, 31.5, 40, 50, 63, 80, 100, 125, 160, 200,
        250, 315, 400, 500, 630, 800, 1000, 1250, 1600, 2000, 2500, 3150, 4000, 5000,
        6300, 8000, 10000, 12500, 16000, 20000]
    var tonePlaying = false
    var comparisonMode = false
    var updates = 0
    func stopTestTone() { tonePlaying = false }
    func stopComparisonMode() { comparisonMode = false }
    @discardableResult func updateProfile(_ profile: CalibrationProfile) -> Bool { updates += 1; return true }
    __ENGINE_METHODS__
}
enum Tab { case equalLoudness, profiles }
final class RoomWizard {
    let calibration: CalibrationEngine
    var profileName = "  Room  "
    var showSaveProfileSheet = true
    var appliedNotchFilters: [(frequency: Double, gain: Float, q: Float)] = [
        (frequency: 63.5, gain: -6, q: 3.5), (frequency: 201.25, gain: -4, q: 7)
    ]
    init(_ calibration: CalibrationEngine) { self.calibration = calibration }
    func save() { saveProfile() }
    __ROOM_SAVE__
}
final class Wizard {
    let calibration = CalibrationEngine()
    var selectedCalibrationMode = CalibrationMode.clean
    var profileName = "  Saved  "
    var profileNotes = "Notes"
    var testBands = [Float](repeating: 2, count: 31)
    var isReferenceStep = true
    var currentTestBandIndex = 0
    var showNewProfileSheet = false
    var selectedTab = Tab.equalLoudness
    func save() { saveProfile() }
    func disappear() { __DISAPPEAR__ }
    func previous() { __PREVIOUS__ }
    func begin() { __CONTINUE__ }
    func cancel() { __CANCEL__ }
    __VIEW_METHODS__
}
var errors: [String] = []
func require(_ value: Bool, _ message: String) { if !value { errors.append(message) } }
let scenario = CommandLine.arguments[1]
var cases = 0
for mode in [CalibrationMode.clean, .combined] {
    for enabled in [false, true] {
        cases += 1
        let wizard = Wizard()
        let engine = wizard.calibration
        let core = engine.eqEngine.coreAudioEngine
        core.isEnabled = enabled
        wizard.selectedCalibrationMode = mode
        wizard.begin()
        require(engine.isCalibrating && !wizard.isReferenceStep, "session did not start")
        require(core.isEnabled == (mode == .clean ? false : enabled), "wrong initial bypass")
        engine.tonePlaying = true
        engine.comparisonMode = true
        switch scenario {
        case "save", "restart":
            wizard.showNewProfileSheet = true
            wizard.save()
            require(!engine.isCalibrating && core.isEnabled == enabled, "save did not restore session")
            require(!engine.tonePlaying && !engine.comparisonMode, "save left playback active")
            require(wizard.isReferenceStep && wizard.currentTestBandIndex == 0, "save did not reset step")
            require(!wizard.showNewProfileSheet && wizard.selectedTab == .profiles, "save did not navigate")
            require(wizard.profileName.isEmpty && wizard.profileNotes.isEmpty, "save metadata not reset")
            require(wizard.testBands == [Float](repeating: 0, count: 31), "save gains not reset")
            require(engine.profiles.count == 1 && engine.updates == 1, "profile not saved exactly once")
            if let profile = engine.profiles.first {
                require(profile.name == "Saved" && profile.notes == "Notes", "saved metadata changed")
                require(profile.bands[17] == 0 && profile.bands[0] == 2, "saved gains changed")
            }
            if scenario == "restart" {
                core.isEnabled = !enabled
                let count = core.changes.count
                wizard.disappear()
                wizard.disappear()
                require(core.isEnabled == !enabled && core.changes.count == count, "idle exit restored stale state")
                wizard.begin()
                require(engine.isCalibrating, "second session blocked")
                wizard.disappear()
                require(!engine.isCalibrating && core.isEnabled == !enabled, "second session restoration failed")
            }
        case "back", "modeChange":
            wizard.currentTestBandIndex = 1
            wizard.previous()
            require(wizard.currentTestBandIndex == 0 && !wizard.isReferenceStep, "previous skipped step")
            require(engine.isCalibrating, "previous ended session early")
            wizard.previous()
            require(wizard.isReferenceStep && !engine.isCalibrating, "back left session active")
            require(core.isEnabled == enabled, "back did not restore bypass")
            if scenario == "modeChange" {
                wizard.selectedCalibrationMode = mode == .clean ? .combined : .clean
                wizard.begin()
                require(engine.isCalibrating, "mode change blocked next session")
                require(core.isEnabled == (wizard.selectedCalibrationMode == .clean ? false : enabled), "mode change bypass wrong")
                wizard.disappear()
                require(core.isEnabled == enabled, "mode change restored wrong state")
            }
        case "cancel":
            wizard.showNewProfileSheet = true
            wizard.cancel()
            require(!wizard.showNewProfileSheet && engine.isCalibrating && !wizard.isReferenceStep, "cancel ended session")
            require(engine.profiles.isEmpty && engine.updates == 0, "cancel saved profile")
            wizard.disappear()
            require(!engine.isCalibrating && core.isEnabled == enabled, "close after cancel did not restore")
        case "invalid":
            wizard.showNewProfileSheet = true
            for invalid in 0..<3 {
                wizard.profileName = invalid == 0 ? " " : "Saved"
                wizard.testBands = [Float](repeating: 2, count: invalid == 1 ? 30 : 31)
                if invalid == 2 { wizard.testBands[0] = .nan }
                wizard.save()
                require(engine.isCalibrating && !wizard.isReferenceStep && wizard.showNewProfileSheet, "invalid save discarded progress")
                require(engine.profiles.isEmpty && engine.updates == 0, "invalid profile saved")
            }
            wizard.disappear()
            require(!engine.isCalibrating && core.isEnabled == enabled, "invalid save close did not restore")
        case "close":
            for reference in [false, true] {
                wizard.isReferenceStep = reference
                wizard.disappear()
                require(!engine.isCalibrating && core.isEnabled == enabled, "close did not restore")
                require(!engine.tonePlaying && !engine.comparisonMode, "close left playback active")
                engine.tonePlaying = true
                engine.comparisonMode = true
            }
        case "roomSave":
            let room = RoomWizard(engine)
            room.save()
            require(engine.profiles.count == 1 && engine.updates == 1, "room profile not saved")
            if let profile = engine.profiles.first {
                require(profile.name == "Room" && profile.type == .roomCorrection, "room metadata changed")
                require(profile.bands == [Float](repeating: 0, count: 31), "room changed band gains")
                require(profile.notchFilters.count == 2, "room notches not saved")
                if profile.notchFilters.count == 2 {
                    require(profile.notchFilters[0].frequency == 63.5 && profile.notchFilters[0].gain == -6
                        && profile.notchFilters[0].q == 3.5, "first notch parameters lost")
                    require(profile.notchFilters[1].frequency == 201.25 && profile.notchFilters[1].gain == -4
                        && profile.notchFilters[1].q == 7, "second notch parameters lost")
                }
                do {
                    let data = try JSONEncoder().encode(profile)
                    let loaded = try JSONDecoder().decode(CalibrationProfile.self, from: data)
                    require(loaded == profile, "saved room JSON did not round trip")
                } catch { errors.append("room serialization failed: \(error)") }
            }
            require(!room.showSaveProfileSheet && room.profileName.isEmpty, "room save did not reset sheet")
        case "roomInvalid":
            for invalid in 0..<6 {
                let room = RoomWizard(engine)
                switch invalid {
                case 0: room.appliedNotchFilters[0].frequency = .nan
                case 1: room.appliedNotchFilters[0].frequency = Double.greatestFiniteMagnitude
                case 2: room.appliedNotchFilters[0].q = 0
                case 3: room.appliedNotchFilters[0].gain = .infinity
                case 4: room.appliedNotchFilters[0].frequency = -1
                default: room.profileName = " "
                }
                room.save()
                require(engine.profiles.isEmpty && engine.updates == 0, "invalid room save mutated profiles")
                require(room.showSaveProfileSheet && !room.profileName.isEmpty, "invalid room save discarded progress")
            }
        default:
            errors.append("unknown scenario")
        }
    }
}
print(String(data: try! JSONSerialization.data(withJSONObject: ["scenario": scenario, "cases": cases,
    "assertionErrors": errors], options: [.sortedKeys]), encoding: .utf8)!)
if !errors.isEmpty { exit(1) }
"""


class RoomComparisonTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        root = Path(__file__).resolve().parent.parent
        source = (root / "SystemEQ for Mac/Features/SubjectiveRoomTuningView.swift").read_text()

        def block(signature):
            start = source.index(signature)
            opening = source.index("{", start)
            end, depth = opening + 1, 1
            while depth:
                depth += (source[end] == "{") - (source[end] == "}")
                end += 1
            return source[start:end], source[opening + 1:end - 1]

        header, profile_change = block(".onChange(of: calibration.activeProfile)")[1].split(" in\n", 1)
        if header.strip() != "_":
            raise ValueError("Unexpected profile change callback arguments")
        fixture = cls.TEMPLATE
        for marker, value in (
            ("__METHODS__", "\n".join(block(signature)[0] for signature in (
                "    private func applyNotchFilters()", "    private func toggleComparison()",
                "    private func startABComparison()", "    private func stopABComparison(",
            ))),
            ("__DISAPPEAR__", block(".onDisappear {")[1]),
            ("__PROFILE_CHANGE__", profile_change),
        ):
            if fixture.count(marker) != 1:
                raise ValueError("Unexpected room comparison fixture marker: " + marker)
            fixture = fixture.replace(marker, value)
        cls.temp = tempfile.TemporaryDirectory(prefix="systemeq-room-comparison-")
        cls.addClassCleanup(cls.temp.cleanup)
        directory = Path(cls.temp.name)
        path = directory / "comparison.swift"
        path.write_text(fixture)
        cls.binary = directory / "comparison"
        result = subprocess.run(
            ["xcrun", "swiftc", "-module-cache-path", str(directory / "module-cache"),
             str(path), "-o", str(cls.binary)], capture_output=True, text=True, timeout=90,
        )
        if result.returncode:
            raise RuntimeError(result.stdout + result.stderr)

    def check_comparison(self, scenario):
        result = subprocess.run([str(self.binary), scenario], capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        observed = json.loads(result.stdout)
        self.assertEqual(observed["scenario"], scenario)
        self.assertEqual(observed["assertionErrors"], [])
        self.assertEqual(observed["validTimers"], 0)

    def test_close_stops_both_phases_and_late_callbacks(self):
        self.check_comparison("phasesClose")

    def test_idle_close_preserves_unrelated_profile_filters(self):
        self.check_comparison("idleClose")

    def test_empty_start_remains_idle(self):
        self.check_comparison("emptyStart")

    def test_repeated_start_rejects_previous_timer_callbacks(self):
        self.check_comparison("doubleStart")

    def test_last_filter_removal_ends_comparison(self):
        self.check_comparison("removeFilters")

    def test_comparison_restarts_after_stop_and_close(self):
        self.check_comparison("restart")

    def test_new_or_edited_profile_cancels_without_overwriting_dsp(self):
        self.check_comparison("profileEvent")

    def test_close_before_profile_notification_preserves_new_profile(self):
        self.check_comparison("profileRaceClose")

    def test_tick_before_profile_notification_preserves_new_profile(self):
        self.check_comparison("profileRaceTick")

    def test_delayed_profile_notification_preserves_restarted_comparison(self):
        self.check_comparison("profileNotificationAfterRestart")

    def test_foundation_runloop_has_no_writes_after_close(self):
        self.check_comparison("realRunLoop")

    def test_external_dsp_replacement_rejects_old_comparison(self):
        self.check_comparison("externalReplacement")

    def test_invalid_filters_do_not_start_comparison(self):
        self.check_comparison("invalidFilters")

    TEMPLATE = r"""
import Foundation
enum LogCategory { case calibration }
func dlog(_ text: String, category: LogCategory) {}
struct NotchFilterConfig: Equatable {
    var frequency: Double
    var gain: Float
    var q: Float
}
struct CalibrationProfile: Equatable {
    var id: Int
    var revision = 0
}
final class CalibrationEngine { var activeProfile: CalibrationProfile? }
final class Sweep {
    var stops = 0
    func stopSweep() { stops += 1 }
}
final class CoreAudioEngine {
    static let shared = CoreAudioEngine()
    var filters: [NotchFilterConfig] = []
    var writes = 0
    var bypassGain: Float = 0
    var comparison: (id: UUID, filters: [NotchFilterConfig])?
    func applyRoomNotchFilters(_ values: [(frequency: Float, gain: Float, q: Float)]) {
        comparison = nil
        bypassGain = 0
        filters = values.map { .init(frequency: Double($0.frequency), gain: $0.gain, q: $0.q) }
        writes += 1
    }
    func clearRoomNotchFilters() { applyRoomNotchFilters([]) }
    func beginRoomABComparison(_ values: [(frequency: Float, gain: Float, q: Float)]) -> UUID? {
        guard !values.isEmpty, values.allSatisfy({
            $0.frequency.isFinite && $0.frequency > 0 && $0.gain.isFinite && $0.gain <= 0
                && $0.q.isFinite && $0.q > 0
        }) else { return nil }
        applyRoomNotchFilters(values)
        let id = UUID()
        comparison = (id, filters)
        return id
    }
    func roomABGainMatchOffset(for id: UUID) -> Float? {
        comparison?.id == id ? -1 : nil
    }
    func setRoomABComparisonPhase(_ id: UUID, filtered: Bool) -> Bool {
        guard let active = comparison, active.id == id else { return false }
        filters = filtered ? active.filters : []
        bypassGain = filtered ? 0 : -1
        writes += 1
        return true
    }
    func endRoomABComparison(_ id: UUID, restoreFilters: Bool = true) {
        guard let active = comparison, active.id == id else { return }
        if restoreFilters { filters = active.filters }
        bypassGain = 0
        comparison = nil
        writes += 1
    }
}
@propertyWrapper struct State<Value> {
    final class Storage {
        var value: Value
        init(_ value: Value) { self.value = value }
    }
    let storage: Storage
    init(wrappedValue: Value) { storage = Storage(wrappedValue) }
    var wrappedValue: Value {
        get { storage.value }
        nonmutating set { storage.value = newValue }
    }
}
final class Timer {
    static var created: [Timer] = []
    let callback: (Timer) -> Void
    var native: Foundation.Timer?
    let requestedInterval: TimeInterval
    let repeats: Bool
    var isValid: Bool { native?.isValid ?? false }
    init(interval: TimeInterval, repeats: Bool, callback: @escaping (Timer) -> Void) {
        requestedInterval = interval
        self.repeats = repeats
        self.callback = callback
    }
    static func scheduledTimer(withTimeInterval interval: TimeInterval, repeats: Bool,
                               block: @escaping (Timer) -> Void) -> Timer {
        let timer = Timer(interval: interval, repeats: repeats, callback: block)
        timer.native = Foundation.Timer.scheduledTimer(withTimeInterval: 0.01, repeats: repeats) { [weak timer] _ in
            guard let timer else { return }
            timer.callback(timer)
        }
        created.append(timer)
        return timer
    }
    func invalidate() { native?.invalidate() }
    func fire() { native?.fire() }
    func deliverQueued() { callback(self) }
}
struct RoomView {
    let calibration = CalibrationEngine()
    let sineSweep = Sweep()
    @State var appliedNotchFilters: [NotchFilterConfig] = []
    @State var isComparing = false
    @State var gainMatchOffset: Float = 0
    @State var abIsFiltered = true
    @State var abTimer: Timer?
    @State var abComparisonProfile: CalibrationProfile?
    @State var abComparisonID: UUID?
    func start() { startABComparison() }
    func stop() { stopABComparison() }
    func toggle() { toggleComparison() }
    func disappear() { __DISAPPEAR__ }
    func profileChanged() { __PROFILE_CHANGE__ }
    func editFilters(_ filters: [NotchFilterConfig]) { appliedNotchFilters = filters; applyNotchFilters() }
    __METHODS__
}
let core = CoreAudioEngine.shared
let local: [NotchFilterConfig] = [.init(frequency: 63.5, gain: -6, q: 4), .init(frequency: 250, gain: -10, q: 7)]
let external: [NotchFilterConfig] = [.init(frequency: 125, gain: -3, q: 5)]
var errors: [String] = []
func require(_ value: Bool, _ message: String) { if !value { errors.append(message) } }
func begin(_ profile: CalibrationProfile? = nil) -> RoomView {
    let view = RoomView()
    view.calibration.activeProfile = profile
    view.appliedNotchFilters = local
    view.start()
    require(view.isComparing && view.abTimer?.isValid == true && view.gainMatchOffset < 0, "start not active")
    require(core.filters == local, "start did not apply local filters")
    return view
}
func requireIdle(_ view: RoomView) {
    require(!view.isComparing && view.abTimer == nil && view.abComparisonProfile == nil && view.abComparisonID == nil,
            "comparison still owns timer/profile")
    require(view.abIsFiltered && view.gainMatchOffset == 0 && core.bypassGain == 0, "idle flags stale")
}
func selectExternal(_ view: RoomView, _ profile: CalibrationProfile?) {
    core.applyRoomNotchFilters(external.map { (Float($0.frequency), $0.gain, $0.q) })
    view.calibration.activeProfile = profile
}
let scenario = CommandLine.arguments[1]
switch scenario {
case "phasesClose":
    for bypassed in [false, true] {
        let view = begin()
        let timer = view.abTimer!
        if bypassed { timer.fire(); require(core.filters.isEmpty && core.bypassGain < 0, "tick did not bypass with attenuation") }
        view.disappear()
        requireIdle(view)
        require(core.filters == local && !timer.isValid, "close did not settle filtered state")
        require(view.sineSweep.stops == 1, "sweep not stopped")
        let writes = core.writes
        timer.fire(); timer.deliverQueued(); view.disappear()
        require(core.writes == writes, "late callback or repeated close wrote DSP")
    }
case "idleClose":
    for filters in [[], local] {
        let view = RoomView()
        view.appliedNotchFilters = filters
        selectExternal(view, CalibrationProfile(id: 10))
        let writes = core.writes
        view.disappear()
        requireIdle(view)
        require(core.filters == external && core.writes == writes, "idle close overwrote external profile")
    }
case "emptyStart":
    let view = RoomView()
    selectExternal(view, CalibrationProfile(id: 10))
    let writes = core.writes
    view.toggle(); requireIdle(view)
    view.start(); view.stop(); view.disappear(); requireIdle(view)
    require(Timer.created.isEmpty && core.writes == writes && core.filters == external, "empty start wrote DSP/timer")
case "doubleStart":
    let view = begin()
    let first = view.abTimer!
    view.start()
    let second = view.abTimer!
    require(first !== second && !first.isValid && second.isValid, "duplicate timer remains active")
    let writes = core.writes
    first.deliverQueued()
    require(core.writes == writes && view.abIsFiltered, "old callback altered new comparison")
    second.fire()
    require(!view.abIsFiltered && core.filters.isEmpty, "new timer did not run")
    view.stop(); requireIdle(view)
    require(core.filters == local, "stop did not restore filters")
case "removeFilters":
    let view = begin()
    let timer = view.abTimer!
    timer.fire()
    view.editFilters([local[0]])
    require(view.isComparing && timer.isValid && core.filters == [local[0]], "partial removal ended comparison")
    view.editFilters([])
    requireIdle(view)
    require(core.filters.isEmpty && !timer.isValid, "last removal did not clear/stop")
    let writes = core.writes
    timer.deliverQueued()
    require(core.writes == writes, "late removal callback wrote DSP")
case "restart":
    let view = RoomView()
    view.appliedNotchFilters = local
    view.toggle(); require(view.isComparing, "toggle did not start")
    view.toggle(); requireIdle(view)
    view.toggle(); require(view.isComparing, "toggle did not restart")
    view.disappear(); requireIdle(view)
    view.start(); require(view.isComparing, "reopen did not restart")
    view.stop(); requireIdle(view)
case "profileEvent":
    for profile in [CalibrationProfile(id: 20), CalibrationProfile(id: 10, revision: 1), nil] {
        let view = begin(CalibrationProfile(id: 10))
        let timer = view.abTimer!
        selectExternal(view, profile)
        let writes = core.writes
        view.profileChanged(); requireIdle(view)
        timer.deliverQueued(); view.disappear()
        require(!timer.isValid && core.writes == writes && core.filters == external, "profile event overwrote DSP")
    }
case "profileRaceClose", "profileRaceTick":
    let view = begin()
    let timer = view.abTimer!
    selectExternal(view, CalibrationProfile(id: 10))
    let writes = core.writes
    if scenario == "profileRaceClose" { view.disappear() } else { timer.fire() }
    requireIdle(view)
    require(!timer.isValid && core.writes == writes && core.filters == external, "profile handoff race overwrote DSP")
case "profileNotificationAfterRestart":
    let view = begin(CalibrationProfile(id: 10))
    let previous = view.abTimer!
    selectExternal(view, CalibrationProfile(id: 20))
    previous.fire()
    requireIdle(view)
    view.start()
    let current = view.abTimer!
    let writes = core.writes
    view.profileChanged()
    require(view.isComparing && current.isValid && view.abTimer === current, "old notification cancelled new comparison")
    require(core.writes == writes && view.abIsFiltered, "old notification changed new DSP/state")
    current.fire()
    require(core.filters.isEmpty && !view.abIsFiltered, "new comparison did not keep running")
    view.stop(); requireIdle(view)
case "externalReplacement":
    let view = begin()
    let timer = view.abTimer!
    core.applyRoomNotchFilters(external.map { (Float($0.frequency), $0.gain, $0.q) })
    let writes = core.writes
    timer.fire(); requireIdle(view)
    timer.deliverQueued(); view.disappear()
    require(core.filters == external && core.writes == writes, "stale token changed replacement")
case "invalidFilters":
    for filter in [NotchFilterConfig(frequency: 125, gain: 1, q: 4),
                   NotchFilterConfig(frequency: .nan, gain: -6, q: 4),
                   NotchFilterConfig(frequency: 125, gain: -6, q: 0)] {
        let view = RoomView()
        selectExternal(view, CalibrationProfile(id: 10))
        view.appliedNotchFilters = [filter]
        let writes = core.writes
        view.start(); requireIdle(view)
        require(core.filters == external && core.writes == writes, "invalid start changed DSP")
    }
case "realRunLoop":
    let view = begin()
    let writes = core.writes
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.04))
    require(core.writes > writes, "Foundation timer did not fire")
    view.disappear()
    let stoppedWrites = core.writes
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    require(core.writes == stoppedWrites, "Foundation timer wrote after close")
    requireIdle(view)
default:
    errors.append("unknown scenario")
}
require(Timer.created.allSatisfy { $0.requestedInterval == 2 && $0.repeats }, "timer schedule changed")
let validTimers = Timer.created.filter(\.isValid).count
require(validTimers == 0, "orphan timers remain")
print(String(data: try! JSONSerialization.data(withJSONObject: ["scenario": scenario,
    "validTimers": validTimers, "assertionErrors": errors], options: [.sortedKeys]), encoding: .utf8)!)
if !errors.isEmpty { exit(1) }
"""


class TextureSamplerFixTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        root = Path(__file__).resolve().parent.parent
        source = (root / "Scripts/setup_projectm.sh").read_text()
        match = re.search(r"(?ms)^apply_texture_sampler_fix\(\) \{\n.*?^\}\n", source)
        if match is None:
            raise ValueError("apply_texture_sampler_fix function not found")
        cls.command = "set -euo pipefail\n" + match.group(0) + '\napply_texture_sampler_fix "$1"\n'

    def run_fix(self, source):
        with tempfile.TemporaryDirectory(prefix="systemeq texture sampler ") as directory:
            path = Path(directory) / "src/libprojectM/Renderer/TextureSamplerDescriptor.cpp"
            if source is not None:
                path.parent.mkdir(parents=True)
                path.write_text(source)
            result = subprocess.run(
                ["bash", "-c", self.command, "texture-sampler-test", directory],
                capture_output=True, text=True, timeout=10,
            )
            actual = path.read_text() if path.exists() else None
            return result, actual

    def test_texture_sampler_fix_changes_only_expected_line(self):
        original = "bool Empty() const\n{\n    return m_texture->Empty();\n}\n"
        result, actual = self.run_fix(original)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(actual, "bool Empty() const\n{\n    return !m_texture || m_texture->Empty();\n}\n")

    def test_texture_sampler_fix_rejects_missing_source(self):
        result, actual = self.run_fix(None)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("FileNotFoundError", result.stderr)
        self.assertIsNone(actual)

    def test_texture_sampler_fix_rejects_changed_source(self):
        original = "bool Empty() const { return texture.Empty(); }\n"
        result, actual = self.run_fix(original)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Unexpected TextureSamplerDescriptor source", result.stderr)
        self.assertEqual(actual, original)

    def test_texture_sampler_fix_rejects_duplicate_pattern(self):
        original = "    return m_texture->Empty();\n    return m_texture->Empty();\n"
        result, actual = self.run_fix(original)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Unexpected TextureSamplerDescriptor source", result.stderr)
        self.assertEqual(actual, original)


class ProjectMConfigureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        root = Path(__file__).resolve().parent.parent
        source = (root / "Scripts/setup_projectm.sh").read_text()
        match = re.search(r"(?ms)^configure_projectm\(\) \{\n.*?^\}\n", source)
        if match is None:
            raise ValueError("configure_projectm function not found")
        cls.command = (
            "set -euo pipefail\n"
            'cmake() { "$SYSTEMEQ_CMAKE_PYTHON" "$SYSTEMEQ_CMAKE_STUB" "$@"; }\n'
            + match.group(0) + '\nconfigure_projectm "$@"\n'
        )

    def run_configure(self, missing_source=False, cmake_exit=0):
        with tempfile.TemporaryDirectory(prefix="systemeq configure fixture ") as directory:
            fixture_root = Path(directory)
            source_root = fixture_root / "projectM source α"
            if not missing_source:
                source_root.mkdir()
            record = fixture_root / "cmake-call.json"
            stub = fixture_root / "fake-cmake.py"
            stub.write_text(
                "import json, os, sys\n"
                "from pathlib import Path\n"
                "Path(os.environ['SYSTEMEQ_CMAKE_RECORD']).write_text("
                "json.dumps({'cwd': os.getcwd(), 'arguments': sys.argv[1:]}))\n"
                "raise SystemExit(int(os.environ['SYSTEMEQ_CMAKE_EXIT']))\n"
            )
            environment = dict(os.environ)
            environment.update(
                SYSTEMEQ_CMAKE_PYTHON=sys.executable,
                SYSTEMEQ_CMAKE_STUB=str(stub),
                SYSTEMEQ_CMAKE_RECORD=str(record),
                SYSTEMEQ_CMAKE_EXIT=str(cmake_exit),
            )
            arguments = [
                "-S", str(source_root), "-B", str(fixture_root / "build output"),
                "-DCMAKE_OSX_ARCHITECTURES=arm64;x86_64", "-DVALUE=literal $HOME;`test`",
            ]
            result = subprocess.run(
                ["bash", "-c", self.command, "projectm-configure-test", str(source_root), *arguments],
                cwd=fixture_root, env=environment, capture_output=True, text=True, timeout=10,
            )
            actual = json.loads(record.read_text()) if record.exists() else None
            expected = {"cwd": str(source_root.resolve()), "arguments": arguments}
            return result, actual, expected

    def test_projectm_configure_uses_upstream_cwd_and_preserves_arguments(self):
        result, actual, expected = self.run_configure()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(actual, expected)

    def test_projectm_configure_rejects_missing_source_before_cmake(self):
        result, actual, _ = self.run_configure(missing_source=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(result.stderr)
        self.assertIsNone(actual)

    def test_projectm_configure_propagates_cmake_failure(self):
        result, actual, expected = self.run_configure(cmake_exit=77)
        self.assertEqual(result.returncode, 77, result.stderr)
        self.assertEqual(actual, expected)


class ProjectMAutomationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix="systemeq-projectm-automation-")
        cls.addClassCleanup(cls.temp.cleanup)
        directory = Path(cls.temp.name)
        root = Path(__file__).resolve().parent.parent
        renderer = (root / "ProjectMHelper/ProjectMHelperApp.swift").read_text()
        signatures = [
            "    func setShuffle(_ enabled: Bool) {",
            "    func setPresetLocked(_ locked: Bool) {",
            "    private func adaptRenderScale() {",
            "    private func resetAdaptiveScale() {",
            "    private func updateCurrentPresetName() {",
            "    private final class PlaylistCallbackContext {",
            "    private func enqueuePlaylistEvent(",
            "    private func resetPerformanceObservation() {",
            "    private func refreshPerformanceExclusions() -> Bool {",
            "    private func replacePlaylist(",
            "    private func populatePlaylist(with presets: [PresetInfo]) -> Bool {",
            "    private func playSelectedPreset(_ target: PresetInfo) {",
            "    private func reloadPlaylist(",
            "    func selectPreset(at index: Int) {",
            "    func setCategory(_ category: String) {",
            "    func setWeight(_ weight: String) {",
            "    func getPresetSnapshot() -> [PresetInfo] {",
            "    func nextPreset() {",
            "    func previousPreset() {",
            "    func randomPreset() {",
        ]
        permission = "    private var allowsAutomaticPresetTransitions: Bool {"
        if permission in renderer:
            signatures.append(permission)
        operation = "    private func performPresetOperation(_ operation: () -> Void) {"
        if operation in renderer:
            signatures.append(operation)
        methods = []
        for signature in signatures:
            start = renderer.index(signature)
            cursor = renderer.index("{", start)
            depth = 1
            end = cursor + 1
            while depth:
                depth += (renderer[end] == "{") - (renderer[end] == "}")
                end += 1
            methods.append(renderer[start:end])
        source = directory / "automation.swift"
        source.write_text(cls.fixture("\n".join(methods)))
        cls.binary = directory / "automation-tests"
        result = subprocess.run(
            ["xcrun", "swiftc", "-parse-as-library", "-module-cache-path", str(directory / "module-cache"),
             str(root / "SystemEQ for Mac/Audio/Visualizer/ProjectM/ProjectMAdaptiveFPS.swift"),
             str(root / "ProjectMHelper/ProjectMPresetPerformance.swift"),
             str(source), "-o", str(cls.binary)],
            capture_output=True, text=True, timeout=90,
        )
        if result.returncode:
            raise RuntimeError(result.stdout + result.stderr)

    @staticmethod
    def fixture(methods):
        return r'''import Foundation

final class PendingQueue {
    var callbacks: [() -> Void] = []
    func async(execute: @escaping () -> Void) { callbacks.append(execute) }
    func drain() {
        let pending = callbacks
        callbacks.removeAll()
        for callback in pending { callback() }
    }
}
enum DispatchQueue {
    enum QoS { case userInitiated }
    static let main = PendingQueue()
    static func global(qos: QoS) -> PendingQueue { main }
}
final class Engine { var locked = false }
enum PresetWeight: String { case all = "All", light = "Light", heavy = "Heavy" }
struct PresetInfo {
    let path: String
    var fingerprint = "v1"
    var category = "first"
    var weight = PresetWeight.light
}
final class Playlist: Equatable {
    static func == (lhs: Playlist, rhs: Playlist) -> Bool { lhs === rhs }
    var paths = ["/presets/first.milk", "/presets/second.milk"]
    var position: UInt32 = 0
    var switched: ((UInt32) -> Void)?
    var failed: ((String, String) -> Void)?
    var badPaths: Set<String> = []
    var calls: [String] = []
    var shuffle = true
}
func projectm_set_preset_locked(_ engine: Engine, _ locked: Bool) { engine.locked = locked }
func projectm_playlist_set_shuffle(_ playlist: Playlist, _ enabled: Bool) { playlist.shuffle = enabled }
func projectm_playlist_play_next(_ playlist: Playlist, _ hardCut: Bool) {
    playlist.calls.append("next:\(hardCut)")
    playlist.position = (playlist.position + 1) % UInt32(playlist.paths.count)
    playlist.switched?(playlist.position)
}
func projectm_playlist_play_previous(_ playlist: Playlist, _ hardCut: Bool) {
    playlist.calls.append("previous:\(hardCut)")
    playlist.position = (playlist.position + UInt32(playlist.paths.count) - 1) % UInt32(playlist.paths.count)
    playlist.switched?(playlist.position)
}
func projectm_playlist_set_position(_ playlist: Playlist, _ rawPosition: UInt32, _ hardCut: Bool) {
    let position = Int(rawPosition)
    playlist.calls.append("position:\(hardCut)")
    guard position < playlist.paths.count else { return }
    playlist.position = rawPosition
    if playlist.badPaths.contains(playlist.paths[position]) {
        if let fallback = playlist.paths.indices.first(where: { !playlist.badPaths.contains(playlist.paths[$0]) }) {
            playlist.position = UInt32(fallback)
            playlist.switched?(UInt32(fallback))
        } else {
            playlist.failed?(playlist.paths[position], "exhausted")
        }
    }
    playlist.switched?(rawPosition)
}
func projectm_playlist_get_position(_ playlist: Playlist) -> UInt32 { playlist.position }
func projectm_playlist_item(_ playlist: Playlist, _ position: UInt32) -> UnsafeMutablePointer<CChar>? {
    guard Int(position) < playlist.paths.count else { return nil }
    return strdup(playlist.paths[Int(position)])
}
func projectm_free_string(_ pointer: UnsafeMutablePointer<CChar>) { free(pointer) }
func CACurrentMediaTime() -> Double { 100 }
func dlog(_ message: String, category: String) {}
func projectm_playlist_clear(_ playlist: Playlist) { playlist.paths.removeAll() }
func projectm_playlist_add_preset(_ playlist: Playlist, _ path: String, _ duplicates: Bool) -> Bool {
    if !duplicates && playlist.paths.contains(path) { return false }
    playlist.paths.append(path)
    return true
}
typealias VisualizerController = Controller
final class Controller {
    var projectMHandle: Engine? = Engine()
    var playlistHandle: Playlist? = Playlist()
    private var playlistCallbackContext: PlaylistCallbackContext?
    var currentCategory = "All"
    var currentWeight = PresetWeight.all
    var availableCategories = ["All", "first", "second"]
    var filterGeneration: UInt64 = 0
    var performanceGeneration: UInt64 = 0
    var performanceObservationTime: TimeInterval?
    var performanceSampleActive = false
    var canRecordPresetPerformance = true
    var performanceContext: ProjectMPresetPerformance.Context?
    var performanceExcludedPaths: Set<String> = []
    var performanceExpiration: Date?
    var presetPerformance = ProjectMPresetPerformance(storageURL: URL(fileURLWithPath: CommandLine.arguments[2]))
    var brokenPresets: Set<String> = []
    var isShuffleEnabled = true
    var isPresetLocked = false
    var adaptiveFPS = ProjectMAdaptiveFPS()
    var measuredFPS = 10
    var currentPresetPath = "/presets/first.milk"
    var currentPresetName = "first"
    var needsBackingResize = false
    var fpsFrameCount = 7
    var fpsWindowStart = 0.0
    var presetCount = 2
    var filteredPresets = [PresetInfo(path: "/presets/first.milk"), PresetInfo(path: "/presets/second.milk")]
    var allPresets = [PresetInfo(path: "/presets/first.milk"), PresetInfo(path: "/presets/second.milk")]
    init() {
        playlistCallbackContext = PlaylistCallbackContext(self)
        playlistHandle?.switched = { [weak self] index in
            guard let self, let context = self.playlistCallbackContext else { return }
            self.enqueuePlaylistEvent(context, index: index, failure: nil)
        }
        playlistHandle?.failed = { [weak self] path, reason in
            guard let self, let context = self.playlistCallbackContext else { return }
            self.enqueuePlaylistEvent(context, index: nil, failure: (path, reason))
        }
    }
    func markPresetBroken(_ path: String, reason: String) { brokenPresets.insert(path) }
    func sample(_ fps: Int) { measuredFPS = fps; adaptRenderScale() }
    func observe(_ count: Int = 1) { for _ in 0..<count { sample(10) } }
    func resetObservation() { resetPerformanceObservation() }
    func manual(_ preset: PresetInfo) { playSelectedPreset(preset) }
    func select(_ index: Int) { selectPreset(at: index) }
    func configurePerformance() {
        performanceContext = ProjectMPresetPerformance.Context(
            hardware: "Mac1", renderer: "GPU1", quality: "High", width: 800, height: 600, version: "1"
        )
    }
''' + methods + r'''
}
@main enum AutomationTests {
    static func expect(_ condition: Bool, _ message: String) {
        if !condition {
            FileHandle.standardError.write(Data((message + "\n").utf8))
            exit(1)
        }
    }
    static func main() throws {
        let scenario = CommandLine.arguments[1]
        let controller = Controller()
        let playlist = controller.playlistHandle!
        switch scenario {
        case "flags":
            for auto in [false, true] {
                for locked in [false, true] {
                    for lockFirst in [false, true] {
                        if lockFirst {
                            controller.setPresetLocked(locked)
                            controller.setShuffle(auto)
                        } else {
                            controller.setShuffle(auto)
                            controller.setPresetLocked(locked)
                        }
                        expect(controller.projectMHandle!.locked == (!auto || locked), "Incorrect library lock")
                        expect(playlist.shuffle == auto, "Incorrect playlist shuffle")
                    }
                }
            }
            controller.setShuffle(false)
            controller.setPresetLocked(true)
            controller.setPresetLocked(false)
            expect(controller.projectMHandle!.locked, "Unlock bypassed Auto=false")
            controller.projectMHandle = nil
            controller.playlistHandle = nil
            controller.setShuffle(true)
            controller.setPresetLocked(true)
            expect(controller.isShuffleEnabled && controller.isPresetLocked, "Flags lost without handles")
        case "disabled", "locked":
            if scenario == "disabled" { controller.setShuffle(false) }
            else { controller.setPresetLocked(true) }
            controller.observe(20)
            expect(controller.adaptiveFPS.adaptiveScale == ProjectMAdaptiveFPS.minScale, "Scale did not adapt")
            expect(controller.needsBackingResize, "Missing backing resize")
            expect(DispatchQueue.main.callbacks.isEmpty, "Forbidden skip was queued")
            DispatchQueue.main.drain()
            expect(playlist.calls.isEmpty && controller.currentPresetName == "first", "Forbidden transition")
        case "queued-auto", "queued-lock", "queued-path", "queued-playlist", "queued-fps", "healthy", "teardown":
            var owner: Controller? = scenario == "teardown" ? Controller() : controller
            weak var weakOwner = owner
            let pendingPlaylist = owner!.playlistHandle!
            owner!.observe(6)
            expect(DispatchQueue.main.callbacks.count == 1, "Expected one queued skip")
            expect(pendingPlaylist.calls.isEmpty, "Skip ran before queue delivery")
            switch scenario {
            case "queued-auto": owner!.setShuffle(false)
            case "queued-lock": owner!.setPresetLocked(true)
            case "queued-path": owner!.currentPresetPath = "/presets/replaced.milk"
            case "queued-playlist": owner!.playlistHandle = nil
            case "queued-fps": owner!.measuredFPS = ProjectMAdaptiveFPS.targetMinFPS
            case "teardown": owner = nil
            default: break
            }
            if scenario == "teardown" { expect(weakOwner == nil, "Queued skip retained controller") }
            DispatchQueue.main.drain()
            if scenario == "healthy" {
                expect(pendingPlaylist.calls == ["next:false"], "Expected exactly one adaptive transition")
                expect(controller.currentPresetPath == pendingPlaylist.paths[1], "Preset path not updated")
                expect(controller.currentPresetName == "second", "Preset name not updated")
                expect(controller.adaptiveFPS.adaptiveScale == 1 && controller.measuredFPS == 0, "Adaptive state not reset")
            } else {
                expect(pendingPlaylist.calls.isEmpty, "Stale queued skip was executed")
            }
        case "manual":
            for auto in [false, true] {
                for locked in [false, true] {
                    controller.setShuffle(auto)
                    controller.setPresetLocked(locked)
                    playlist.calls.removeAll()
                    controller.nextPreset()
                    controller.previousPreset()
                    controller.randomPreset()
                    expect(playlist.calls == ["next:false", "previous:false", "position:true"], "Manual controls changed")
                    expect(controller.currentPresetPath == playlist.paths[Int(playlist.position)], "Manual identity stale")
                }
            }
            playlist.calls.removeAll()
            controller.presetCount = 0
            controller.filteredPresets = []
            controller.nextPreset()
            controller.previousPreset()
            controller.randomPreset()
            expect(playlist.calls.isEmpty, "Empty playlist accepted manual transition")
            controller.playlistHandle = nil
            controller.nextPreset()
            controller.previousPreset()
            controller.randomPreset()
        case "performance-cache", "performance-manual", "performance-empty":
            controller.configurePerformance()
            if scenario == "performance-empty" {
                controller.allPresets = [controller.allPresets[0]]
                controller.filteredPresets = controller.allPresets
                controller.presetCount = 1
                playlist.paths = ["/presets/first.milk"]
            }
            controller.observe(6)
            DispatchQueue.main.drain()
            expect(controller.performanceExcludedPaths == ["/presets/first.milk"], "Slow preset not quarantined")
            expect(!playlist.paths.contains("/presets/first.milk"), "Slow preset remains in automatic playlist")
            let now = Date()
            var loaded = ProjectMPresetPerformance(storageURL: URL(fileURLWithPath: CommandLine.arguments[2]))
            try loaded.load()
            expect(loaded.isExcluded(path: "/presets/first.milk", fingerprint: "v1", context: controller.performanceContext!, now: now), "Cache did not survive reload")
            expect(controller.allPresets.count == (scenario == "performance-empty" ? 1 : 2), "Manual catalog truncated")
            controller.manual(controller.allPresets[0])
            expect(controller.currentPresetPath == "/presets/first.milk", "Manual override did not load")
            expect(!playlist.paths.contains("/presets/first.milk"), "Manual override entered autorotation")
            DispatchQueue.main.drain()
            expect(controller.currentPresetPath == "/presets/first.milk", "Stale callback substituted manual identity")
            if scenario == "performance-empty" {
                controller.nextPreset(); controller.previousPreset(); controller.randomPreset()
                controller.setShuffle(false); controller.setShuffle(true)
                expect(playlist.paths.isEmpty && controller.projectMHandle!.locked, "Empty eligible pool was unlocked")
            } else {
                controller.nextPreset()
                expect(controller.currentPresetPath == "/presets/second.milk", "Next failed after transient manual override")
                controller.previousPreset(); controller.randomPreset()
                expect(!playlist.paths.contains("/presets/first.milk"), "Navigation reintroduced slow preset")
            }
        case "performance-pending-reload":
            controller.configurePerformance()
            controller.setCategory("All")
            controller.observe(6)
            for _ in 0..<4 { DispatchQueue.main.drain() }
            expect(playlist.paths == ["/presets/second.milk"], "Pending reload reintroduced quarantined preset")
        case "performance-reload", "performance-selection", "performance-fallback", "performance-exhaustion":
            controller.configurePerformance()
            try controller.presetPerformance.record(path: "/presets/first.milk", fingerprint: "v1", context: controller.performanceContext!, now: Date())
            controller.setCategory("All")
            for _ in 0..<4 { DispatchQueue.main.drain() }
            expect(playlist.paths == ["/presets/second.milk"], "Reload reintroduced excluded preset")
            expect(controller.getPresetSnapshot().count == 2, "Reload truncated manual catalog")
            if scenario == "performance-selection" {
                controller.currentCategory = "second"
                controller.select(0)
                for _ in 0..<4 { DispatchQueue.main.drain() }
                expect(controller.currentCategory == "All", "Out-of-filter manual selection did not restore All")
                expect(controller.currentPresetPath == "/presets/first.milk", "Global manual selection failed")
                expect(playlist.paths == ["/presets/second.milk"], "Global manual selection entered automatic pool")
            } else if scenario == "performance-fallback" || scenario == "performance-exhaustion" {
                playlist.calls.removeAll()
                playlist.badPaths = scenario == "performance-exhaustion" ? ["/presets/first.milk", "/presets/second.milk"] : ["/presets/first.milk"]
                controller.select(0)
                for _ in 0..<4 { DispatchQueue.main.drain() }
                expect(playlist.paths == ["/presets/second.milk"], "Failed manual preset remained in pool")
                expect(controller.currentPresetPath == "/presets/second.milk", "Manual failure overwrote confirmed identity")
                expect(playlist.calls.count == (scenario == "performance-fallback" ? 2 : 1), "Manual failure caused retry burst or lost position sync")
            } else {
                controller.setWeight("Light")
                for _ in 0..<4 { DispatchQueue.main.drain() }
                expect(playlist.paths == ["/presets/second.milk"], "Weight reload reintroduced exclusion")
            }
        case "performance-stale", "performance-context", "performance-gap", "performance-transient", "performance-inactive", "performance-hiding":
            controller.configurePerformance()
            if scenario == "performance-inactive" {
                controller.canRecordPresetPerformance = false
                controller.observe(20)
                DispatchQueue.main.drain()
            } else if scenario == "performance-hiding" {
                controller.observe(6)
                controller.canRecordPresetPerformance = false
                DispatchQueue.main.drain()
            } else if scenario == "performance-gap" {
                controller.observe(4)
                controller.performanceObservationTime = Date().timeIntervalSinceReferenceDate - 30
                controller.observe()
                expect(controller.adaptiveFPS.adaptiveScale == 1, "Long gap reused scale/evidence")
            } else if scenario == "performance-transient" {
                controller.observe(5)
                controller.sample(60)
                controller.observe()
                expect(DispatchQueue.main.callbacks.isEmpty, "Transient low FPS queued exclusion")
            } else {
                controller.observe(6)
                if scenario == "performance-context" { controller.performanceContext = nil }
                else { controller.setShuffle(false); controller.setShuffle(true) }
                DispatchQueue.main.drain()
            }
            expect(!FileManager.default.fileExists(atPath: CommandLine.arguments[2]), "Stale/transient evidence persisted")
            expect(playlist.paths.count == 2, "Stale/transient evidence changed eligibility")
        case "store-context-expiry", "store-corrupt", "store-write-failure", "store-read-failure", "store-invalid":
            controller.configurePerformance()
            let context = controller.performanceContext!
            let file = URL(fileURLWithPath: CommandLine.arguments[2])
            let now = Date(timeIntervalSince1970: 1700000000)
            var store = ProjectMPresetPerformance(storageURL: file)
            try store.load()
            try store.record(path: "preset", fingerprint: "original", context: context, now: now)
            let oldBytes = try Data(contentsOf: file)
            let oldTime = try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as! Date
            if scenario == "store-context-expiry" {
                expect(store.isExcluded(path: "preset", fingerprint: "original", context: context, now: now.addingTimeInterval(ProjectMPresetPerformance.lifetime - 1)), "Premature expiry")
                expect(!store.isExcluded(path: "preset", fingerprint: "original", context: context, now: now.addingTimeInterval(ProjectMPresetPerformance.lifetime)), "Expired quarantine remains")
                expect(!store.isExcluded(path: "preset", fingerprint: "original", context: context, now: now.addingTimeInterval(-1)), "Future evidence trusted")
                expect(!store.isExcluded(path: "preset", fingerprint: "changed", context: context, now: now), "Changed preset excluded")
                for changed in [
                    ProjectMPresetPerformance.Context(hardware: "Mac2", renderer: "GPU1", quality: "High", width: 800, height: 600, version: "1"),
                    ProjectMPresetPerformance.Context(hardware: "Mac1", renderer: "GPU2", quality: "High", width: 800, height: 600, version: "1"),
                    ProjectMPresetPerformance.Context(hardware: "Mac1", renderer: "GPU1", quality: "Low", width: 800, height: 600, version: "1"),
                    ProjectMPresetPerformance.Context(hardware: "Mac1", renderer: "GPU1", quality: "High", width: 1600, height: 1200, version: "1"),
                    ProjectMPresetPerformance.Context(hardware: "Mac1", renderer: "GPU1", quality: "High", width: 800, height: 600, version: "2")
                ] {
                    expect(!store.isExcluded(path: "preset", fingerprint: "original", context: changed, now: now), "Different context inherited quarantine")
                }
            } else if scenario == "store-corrupt" {
                for bytes in [Data("invalid json".utf8), Data("{\"version\":99,\"entries\":{}}".utf8)] {
                    try bytes.write(to: file)
                    let timestamp = try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as! Date
                    var rejected = false
                    do { try store.load() } catch { rejected = true }
                    expect(rejected, "Corrupt cache accepted")
                    var rejectedWrite = false
                    do { try store.record(path: "new", fingerprint: "v2", context: context, now: now) }
                    catch { rejectedWrite = true }
                    expect(rejectedWrite, "Record overwrote corrupt cache")
                    expect(try Data(contentsOf: file) == bytes, "Corrupt load rewrote input")
                    expect(try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as! Date == timestamp, "Corrupt load changed timestamp")
                    expect(store.isExcluded(path: "preset", fingerprint: "original", context: context, now: now), "Corrupt load erased valid in-memory records")
                }
            } else if scenario == "store-read-failure" {
                expect(geteuid() != 0, "Permission test requires an unprivileged process")
                try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: file.path)
                defer {
                    do { try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path) }
                    catch { expect(false, "Cannot restore cache permissions") }
                }
                var fresh = ProjectMPresetPerformance(storageURL: file)
                var rejectedLoad = false
                do { try fresh.load() } catch { rejectedLoad = true }
                var rejectedWrite = false
                do { try fresh.record(path: "new", fingerprint: "v2", context: context, now: now) }
                catch { rejectedWrite = true }
                expect(rejectedLoad && rejectedWrite, "Unreadable cache was replaced")
                try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
                expect(try Data(contentsOf: file) == oldBytes, "Read failure destroyed old cache")
                try fresh.record(path: "new", fingerprint: "v2", context: context, now: now)
                expect(fresh.isExcluded(path: "preset", fingerprint: "original", context: context, now: now), "Recovery erased old entries")
            } else if scenario == "store-write-failure" {
                expect(geteuid() != 0, "Permission test requires an unprivileged process")
                let directory = file.deletingLastPathComponent()
                try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
                defer {
                    do { try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path) }
                    catch { expect(false, "Cannot restore fixture permissions") }
                }
                var rejected = false
                do { try store.record(path: "new", fingerprint: "v2", context: context, now: now) } catch { rejected = true }
                expect(rejected, "Write failure hidden")
                expect(try Data(contentsOf: file) == oldBytes, "Write failure replaced cache bytes")
                expect(try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as! Date == oldTime, "Write failure changed cache timestamp")
                expect(!store.isExcluded(path: "new", fingerprint: "v2", context: context, now: now), "Failed write committed state")
            } else {
                var rejected = false
                do { try store.record(path: "new", fingerprint: "", context: context, now: now) } catch { rejected = true }
                let preserved = try Data(contentsOf: file)
                expect(rejected && preserved == oldBytes, "Invalid observation changed cache")
            }
        default: fatalError("Unknown scenario")
        }
        print("ProjectM automation: \(scenario) passed")
    }
}
'''

    def test_auto_and_lock_control_library_transitions(self):
        self.run_scenario("flags")

    def test_disabled_automation_keeps_scale_adaptation(self):
        for scenario in ("disabled", "locked"):
            with self.subTest(scenario=scenario):
                self.run_scenario(scenario)

    def test_queued_skip_rechecks_permission_and_preset(self):
        for scenario in ("queued-auto", "queued-lock", "queued-path", "queued-playlist", "queued-fps", "teardown"):
            with self.subTest(scenario=scenario):
                self.run_scenario(scenario)

    def test_enabled_automation_updates_identity_and_adaptive_state(self):
        self.run_scenario("healthy")

    def test_manual_transitions_remain_available(self):
        self.run_scenario("manual")

    def test_sustained_fps_exclusion_and_manual_override(self):
        for scenario in ("performance-cache", "performance-manual", "performance-empty"):
            with self.subTest(scenario=scenario):
                self.run_scenario(scenario)

    def test_reload_manual_selection_and_failure_identity(self):
        for scenario in ("performance-reload", "performance-selection", "performance-fallback", "performance-exhaustion"):
            with self.subTest(scenario=scenario):
                self.run_scenario(scenario)

    def test_pending_reload_keeps_new_exclusions(self):
        self.run_scenario("performance-pending-reload")

    def test_context_gaps_and_transients_do_not_persist(self):
        for scenario in ("performance-stale", "performance-context", "performance-gap", "performance-transient", "performance-inactive", "performance-hiding"):
            with self.subTest(scenario=scenario):
                self.run_scenario(scenario)

    def test_cache_context_fingerprint_and_seven_day_expiry(self):
        self.run_scenario("store-context-expiry")

    def test_corrupt_cache_preserves_previous_state(self):
        self.run_scenario("store-corrupt")

    def test_cache_write_failure_preserves_bytes_timestamp_and_state(self):
        self.run_scenario("store-write-failure")

    def test_cache_read_failure_blocks_replacement_and_recovers(self):
        self.run_scenario("store-read-failure")

    def test_invalid_observation_does_not_change_cache(self):
        self.run_scenario("store-invalid")

    def run_scenario(self, scenario):
        cache = Path(tempfile.mkdtemp(dir=self.temp.name)) / "performance.json"
        result = subprocess.run([str(self.binary), scenario, str(cache)], capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(f"ProjectM automation: {scenario} passed", result.stdout)


class ProjectMCallbackTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix="systemeq-projectm-callbacks-")
        cls.addClassCleanup(cls.temp.cleanup)
        directory = Path(cls.temp.name)
        root = Path(__file__).resolve().parent.parent
        renderer = (root / "ProjectMHelper/ProjectMHelperApp.swift").read_text()
        methods = []
        for signature in (
            "    private final class PlaylistCallbackContext {", "    deinit {",
            "    private func setupPlaylist(_ handle: OpaquePointer) {",
            "    private func enqueuePlaylistEvent(", "    private func unregisterPlaylistCallbacks() {",
            "    private func performPresetOperation(_ operation: () -> Void) {", "    func shutdown() {",
            "    private func updateCurrentPresetName() {", "    private func resetAdaptiveScale() {",
            "    func markPresetBroken(_ path: String, reason: String) {", "    func nextPreset() {",
            "    func getStatus() -> [String: Any] {",
        ):
            start = renderer.index(signature)
            cursor = renderer.index("{", start)
            depth = 1
            end = cursor + 1
            while depth:
                depth += (renderer[end] == "{") - (renderer[end] == "}")
                end += 1
            methods.append(renderer[start:end])
        source = directory / "callbacks.swift"
        source.write_text(cls.fixture("\n".join(methods)))
        cls.binary = directory / "callback-tests"
        result = subprocess.run(
            ["xcrun", "swiftc", "-parse-as-library", "-module-cache-path", str(directory / "module-cache"),
             str(root / "SystemEQ for Mac/Audio/Visualizer/ProjectM/ProjectMAdaptiveFPS.swift"),
             str(source), "-o", str(cls.binary)], capture_output=True, text=True, timeout=90,
        )
        if result.returncode:
            raise RuntimeError(result.stdout + result.stderr)

    @staticmethod
    def fixture(methods):
        return r'''import Foundation

func expect(_ condition: Bool, _ message: String) {
    if !condition {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(1)
    }
}
final class PendingQueue {
    var callbacks: [() -> Void] = []
    func async(execute: @escaping () -> Void) { callbacks.append(execute) }
    func drain() {
        var deliveries = 0
        while !callbacks.isEmpty {
            deliveries += 1
            expect(deliveries <= 20, "Unbounded callback delivery")
            callbacks.removeFirst()()
        }
    }
}
enum DispatchQueue { static let main = PendingQueue() }
typealias Switched = @convention(c) (Bool, UInt32, UnsafeMutableRawPointer?) -> Void
typealias Failed = @convention(c) (UnsafePointer<CChar>?, UnsafePointer<CChar>?, UnsafeMutableRawPointer?) -> Void
final class Playlist {
    let paths = ["/presets/first.milk", "/presets/second.milk", "/presets/third.milk", "/presets/fourth.milk"]
    var position: UInt32 = 0
    var switched: Switched?
    var failed: Failed?
    var switchedData: UnsafeMutableRawPointer?
    var failedData: UnsafeMutableRawPointer?
    var connected = true
    var bad: Set<UInt32> = []
    var attempts = 0
    var topLevelCalls = 0
    let retries = 5
    func attempt(_ index: UInt32, retry: Int = 0) {
        position = index
        attempts += 1
        if bad.contains(index) {
            if retry < retries { attempt((index + 1) % UInt32(paths.count), retry: retry + 1) }
            else { fail(paths[Int(index)], "exhausted") }
        }
        switched?(false, index, switchedData)
    }
    func fail(_ path: String, _ message: String) {
        let filename = strdup(path)!
        let reason = strdup(message)!
        failed?(UnsafePointer(filename), UnsafePointer(reason), failedData)
        memset(filename, 88, path.utf8.count)
        memset(reason, 89, message.utf8.count)
        free(filename)
        free(reason)
    }
}
var playlists: [OpaquePointer: Playlist] = [:]
var nextHandle = 100
var createFails = false
var destructionCount = 0
var deallocations = 0
func projectm_playlist_create(_ engine: OpaquePointer) -> OpaquePointer? {
    if createFails { return nil }
    nextHandle += 1
    let handle = OpaquePointer(bitPattern: nextHandle)!
    playlists[handle] = Playlist()
    return handle
}
func projectm_playlist_set_preset_switched_event_callback(_ handle: OpaquePointer, _ callback: Switched?, _ data: UnsafeMutableRawPointer?) {
    playlists[handle]!.switched = callback
    playlists[handle]!.switchedData = data
}
func projectm_playlist_set_preset_switch_failed_event_callback(_ handle: OpaquePointer, _ callback: Failed?, _ data: UnsafeMutableRawPointer?) {
    playlists[handle]!.failed = callback
    playlists[handle]!.failedData = data
}
func projectm_playlist_connect(_ handle: OpaquePointer, _ engine: OpaquePointer?) {
    playlists[handle]!.connected = engine != nil
}
func projectm_playlist_destroy(_ handle: OpaquePointer) {
    let playlist = playlists[handle]!
    expect(playlist.switched == nil && playlist.failed == nil && !playlist.connected, "Callbacks not disconnected before destroy")
    playlists.removeValue(forKey: handle)
    destructionCount += 1
}
func projectm_destroy(_ handle: OpaquePointer) {}
func projectm_playlist_get_position(_ handle: OpaquePointer) -> UInt32 { playlists[handle]!.position }
func projectm_playlist_item(_ handle: OpaquePointer, _ position: UInt32) -> UnsafeMutablePointer<CChar>? {
    let paths = playlists[handle]!.paths
    return Int(position) < paths.count ? strdup(paths[Int(position)]) : nil
}
func projectm_free_string(_ pointer: UnsafeMutablePointer<CChar>) { free(pointer) }
func projectm_playlist_play_next(_ handle: OpaquePointer, _ hardCut: Bool) {
    let playlist = playlists[handle]!
    playlist.topLevelCalls += 1
    playlist.attempt((playlist.position + 1) % UInt32(playlist.paths.count))
}
func CACurrentMediaTime() -> Double { 100 }
struct AudioBuffer { func deallocate() { deallocations += 1 } }
enum PresetWeight: String { case all }
final class VisualizerController {
    var projectMHandle: OpaquePointer? = OpaquePointer(bitPattern: 1)!
    var playlistHandle: OpaquePointer?
    private var playlistCallbackContext: PlaylistCallbackContext?
    var currentPresetName = "first"
    var currentPresetPath = "/presets/first.milk"
    var presetCount = 4
    var isShuffleEnabled = true
    var isPresetLocked = false
    var currentCategory = "All"
    var currentWeight = PresetWeight.all
    var availableCategories = ["All"]
    var performanceGeneration: UInt64 = 0
    var performanceObservationTime: TimeInterval?
    var adaptiveFPS = ProjectMAdaptiveFPS()
    var measuredFPS = 10
    var fpsFrameCount = 3
    var fpsWindowStart = 0.0
    var needsBackingResize = false
    var brokenPresets: Set<String> = []
    var saves = 0
    var activityToken: NSObjectProtocol?
    var audioBuffer = AudioBuffer()
    var audioScratch = AudioBuffer()
    func stopDisplayLink() {}
    func removePerformanceObservers() {}
    func saveBrokenPresets() { saves += 1 }
    func start() { setupPlaylist(projectMHandle!) }
    func automaticSwitch(_ index: UInt32) { performPresetOperation { playlists[playlistHandle!]!.attempt(index) } }
    func warmAdaptiveState() {
        for _ in 0..<4 { _ = adaptiveFPS.observe(measuredFPS: 10, presetLocked: false, hasPresetPath: true) }
    }
''' + methods + r'''
}
@main enum CallbackTests {
    static func main() {
        let scenario = CommandLine.arguments[1]
        var owner: VisualizerController? = VisualizerController()
        owner!.start()
        let originalHandle = owner!.playlistHandle!
        let playlist = playlists[originalHandle]!
        owner!.warmAdaptiveState()
        switch scenario {
        case "success", "retry-success", "stale-success":
            if scenario == "retry-success" { playlist.bad = [1] }
            owner!.automaticSwitch(1)
            if scenario == "stale-success" { owner!.automaticSwitch(3) }
            expect(owner!.currentPresetName == "first", "Callback changed state inline")
            DispatchQueue.main.drain()
            let expected = scenario == "retry-success" ? "third" : scenario == "stale-success" ? "fourth" : "second"
            expect(owner!.getStatus()["presetName"] as? String == expected, "Status/favorite identity stale")
            expect(owner!.adaptiveFPS.adaptiveScale == 1 && owner!.measuredFPS == 0, "Adaptive state stale")
            expect(owner!.brokenPresets.isEmpty, "Retry success blacklisted a preset")
        case "exhaustion", "manual-exhaustion", "recovery-before-delivery":
            playlist.bad = [0, 1, 2, 3]
            if scenario == "manual-exhaustion" { owner!.nextPreset() }
            else { owner!.automaticSwitch(1) }
            expect(playlist.attempts == 6, "Library retry count changed")
            expect(owner!.currentPresetName == "first", "Failure overwrote confirmed identity inline")
            if scenario == "recovery-before-delivery" {
                playlist.bad = []
                owner!.nextPreset()
            }
            DispatchQueue.main.drain()
            expect(owner!.brokenPresets == ["/presets/third.milk"] && owner!.saves == 1, "Failure strings not copied/persisted")
            if scenario == "recovery-before-delivery" {
                expect(owner!.currentPresetName == "fourth", "New healthy operation lost after exhaustion")
                expect(playlist.topLevelCalls == 1 && playlist.attempts == 7, "Failure restarted retries")
            } else {
                expect(owner!.currentPresetName == "first" && owner!.adaptiveFPS.adaptiveScale == 0.25, "Failure reset identity/adaptive state")
                expect(playlist.attempts == 6, "Exhaustion started another retry batch")
            }
        case "shutdown", "recreate", "deinit":
            owner!.automaticSwitch(1)
            weak var weakOwner = owner
            if scenario == "deinit" {
                owner = nil
                expect(weakOwner == nil && deallocations == 2, "Queued callback retained owner")
                expect(playlist.switched == nil && playlist.failed == nil && !playlist.connected, "Deinit left callbacks installed")
            } else {
                owner!.shutdown()
                owner!.shutdown()
                expect(destructionCount == 1, "Repeated shutdown destroyed twice")
                if scenario == "recreate" {
                    owner!.projectMHandle = OpaquePointer(bitPattern: 1)!
                    owner!.start()
                    owner!.automaticSwitch(3)
                }
            }
            DispatchQueue.main.drain()
            if let owner { expect(owner.currentPresetName == (scenario == "recreate" ? "fourth" : "first"), "Stale lifecycle callback applied") }
        case "null-failure":
            playlist.failed?(nil, nil, playlist.failedData)
            let path = "/presets/null-message.milk"
            path.withCString { playlist.failed?($0, nil, playlist.failedData) }
            DispatchQueue.main.drain()
            expect(owner!.brokenPresets == [path] && owner!.saves == 1, "Nullable failure arguments mishandled")
        case "create-failure":
            owner!.shutdown()
            owner!.projectMHandle = OpaquePointer(bitPattern: 1)!
            createFails = true
            owner!.start()
            expect(owner!.playlistHandle == nil, "Failed creation installed a playlist")
            owner!.nextPreset()
            owner!.shutdown()
            DispatchQueue.main.drain()
            expect(owner!.currentPresetName == "first", "Failed creation changed identity")
        default: fatalError("Unknown scenario")
        }
        print("ProjectM callbacks: \(scenario) passed")
    }
}
'''

    def test_playlist_bridging_matches_pinned_c_api(self):
        root = Path(__file__).resolve().parent.parent
        includes = root / "Vendor/projectM/include"
        self.assertEqual(includes.resolve(), includes, "Pinned include root contains a symlink")
        pending = [includes / "projectM-4" / f"{name}.h" for name in (
            "playlist_playback", "playlist_items", "playlist_callbacks", "playlist_core",
        )]
        checked = set()
        while pending:
            header = pending.pop()
            if header in checked:
                continue
            self.assertTrue(header.resolve().is_relative_to(includes), f"Unpinned header: {header}")
            text = header.read_text()
            checked.add(header)
            pending.extend(includes / name for name in re.findall(r'#include\s+"(projectM-4/[^\"]+)"', text))
        source = '\n'.join(f'#include "projectM-4/{name}.h"' for name in (
            "playlist_playback", "playlist_items", "playlist_callbacks",
        ))
        source += '\n_Static_assert(__builtin_types_compatible_p(__typeof__(&projectm_playlist_size), uint32_t (*)(projectm_playlist_handle)), "size ABI");'
        source += '\n_Static_assert(__builtin_types_compatible_p(__typeof__(&projectm_playlist_connect), void (*)(projectm_playlist_handle, projectm_handle)), "connect ABI");'
        result = subprocess.run(
            ["xcrun", "clang", "-fsyntax-only", "-x", "c", "-Werror=incompatible-pointer-types",
             "-I", str(root / "Vendor/projectM/include"),
             "-include", str(root / "ProjectMHelper/ProjectMHelper-Bridging-Header.h"), "-"],
            input=source, capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_success_updates_status_and_adaptive_state(self):
        self.run_scenario("success")

    def test_retry_unwind_and_stale_success_preserve_latest_identity(self):
        for scenario in ("retry-success", "stale-success"):
            with self.subTest(scenario=scenario):
                self.run_scenario(scenario)

    def test_exhaustion_preserves_confirmed_state_and_retry_boundary(self):
        for scenario in ("exhaustion", "manual-exhaustion", "recovery-before-delivery", "null-failure"):
            with self.subTest(scenario=scenario):
                self.run_scenario(scenario)

    def test_shutdown_and_deinit_discard_pending_callbacks(self):
        for scenario in ("shutdown", "recreate", "deinit", "create-failure"):
            with self.subTest(scenario=scenario):
                self.run_scenario(scenario)

    def run_scenario(self, scenario):
        result = subprocess.run([str(self.binary), scenario], capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(f"ProjectM callbacks: {scenario} passed", result.stdout)
        if scenario in ("exhaustion", "manual-exhaustion", "recovery-before-delivery"):
            self.assertIn(" — exhausted", result.stdout)


class RuntimeToolsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root = Path(__file__).resolve().parent.parent
        cls.temp = tempfile.TemporaryDirectory(prefix="systemeq-runtime-tools-")
        cls.addClassCleanup(cls.temp.cleanup)
        cls.cpu = Path(cls.temp.name) / "measure-process-cpu"
        cls.ipc = Path(cls.temp.name) / "ipc-server-tests"
        cls.presets = Path(cls.temp.name) / "preset-archive-tests"
        cls.shuffle = Path(cls.temp.name) / "preset-shuffle-tests"
        sanitizer = os.environ.get("SYSTEMEQ_TEST_SANITIZER", "")
        if sanitizer not in ("", "address", "thread"):
            raise ValueError("Unsupported SYSTEMEQ_TEST_SANITIZER")
        flags = [f"-sanitize={sanitizer}"] if sanitizer else []
        for sources, output in (
            (["Scripts/measure_process_cpu.swift"], cls.cpu),
            (["ProjectMHelper/IPCServer.swift", "Scripts/test_ipc_server.swift"], cls.ipc),
            (["ProjectMHelper/ProjectMPresetArchive.swift", "Scripts/test_preset_archive.swift"], cls.presets),
        ):
            subprocess.run(
                ["xcrun", "swiftc", "-parse-as-library", *flags, *sources, "-o", str(output)],
                cwd=cls.root, check=True, capture_output=True, text=True, timeout=90,
            )
        renderer = (cls.root / "ProjectMHelper/ProjectMHelperApp.swift").read_text()
        methods = []
        for signature in ("    func randomPreset() {",):
            start = renderer.index(signature)
            cursor = renderer.index("{", start)
            depth = 1
            end = cursor + 1
            while depth:
                depth += (renderer[end] == "{") - (renderer[end] == "}")
                end += 1
            methods.append(renderer[start:end])
        shuffle_source = Path(cls.temp.name) / "preset-shuffle-tests.swift"
        shuffle_source.write_text(cls.shuffle_fixture("\n".join(methods)))
        subprocess.run(
            ["xcrun", "swiftc", "-parse-as-library", *flags, str(shuffle_source), "-o", str(cls.shuffle)],
            cwd=cls.root, check=True, capture_output=True, text=True, timeout=90,
        )

    @staticmethod
    def shuffle_fixture(methods):
        return r'''import Foundation

enum PresetWeight: String { case all, light, heavy }
struct PresetInfo {
    let path: String
    let category: String
    let weight: PresetWeight
}
final class Playlist {
    var paths: [String]
    var positions: [(Int, Bool)] = []
    init(_ paths: [String]) { self.paths = paths }
}
func projectm_playlist_set_position(_ playlist: Playlist, _ rawPosition: UInt32, _ hardCut: Bool) {
    let position = Int(rawPosition)
    precondition(playlist.paths.indices.contains(position), "Position outside current playlist")
    playlist.positions.append((position, hardCut))
}
func projectm_playlist_clear(_ playlist: Playlist) { playlist.paths.removeAll() }
func projectm_playlist_add_preset(_ playlist: Playlist, _ path: String, _ duplicates: Bool) {
    playlist.paths.append(path)
}
func projectm_playlist_set_shuffle(_ playlist: Playlist, _ enabled: Bool) {}
final class Controller {
    var playlistHandle: Playlist?
    var allPresets: [PresetInfo]
    var filteredPresets: [PresetInfo]
    var presetCount: Int
    var currentCategory = "HeavyCategory"
    var currentWeight = PresetWeight.heavy
    var filterGeneration: UInt64 = 11
    var brokenPresets: Set<String> = []
    var isShuffleEnabled = true
    var nameUpdates = 0
    var currentPresetName = "None"
    init(all: [PresetInfo], filtered: [PresetInfo]) {
        allPresets = all
        filteredPresets = filtered
        presetCount = filtered.count
        playlistHandle = Playlist(filtered.map(\.path))
    }
    func updateCurrentPresetName() {
        nameUpdates += 1
        if let playlist = playlistHandle, let position = playlist.positions.last?.0 {
            currentPresetName = playlist.paths[position]
        }
    }
    func performPresetOperation(_ operation: () -> Void) { operation() }
''' + methods + r'''
}
@main enum ShuffleTests {
    static func main() {
        let all = (0..<8).map {
            PresetInfo(path: "preset-\($0)", category: $0.isMultiple(of: 2) ? "LightCategory" : "HeavyCategory",
                       weight: $0.isMultiple(of: 2) ? .light : .heavy)
        }
        let scenario = CommandLine.arguments[1]
        let controller: Controller
        switch scenario {
        case "singleton": controller = Controller(all: all, filtered: [all[5]])
        case "empty":
            controller = Controller(all: all, filtered: [])
            controller.presetCount = 1
        case "nil":
            controller = Controller(all: all, filtered: [all[5]])
            controller.playlistHandle = nil
        case "sparse": controller = Controller(all: all, filtered: [all[1], all[3], all[7]])
        case "pending":
            controller = Controller(all: all, filtered: [all[5]])
            controller.currentCategory = "LightCategory"
            controller.currentWeight = .light
            controller.filterGeneration = 42
        default: fatalError("Unknown scenario")
        }
        let category = controller.currentCategory
        let weight = controller.currentWeight
        let generation = controller.filterGeneration
        let paths = controller.filteredPresets.map(\.path)
        let count = controller.presetCount
        let iterations = scenario == "sparse" ? 256 : 1
        for iteration in 0..<iterations {
            controller.randomPreset()
            precondition(controller.currentCategory == category, "Shuffle reset category")
            precondition(controller.currentWeight == weight, "Shuffle reset weight")
            precondition(controller.filterGeneration == generation, "Shuffle invalidated pending filter reload")
            precondition(controller.filteredPresets.map(\.path) == paths, "Shuffle changed published filter")
            precondition(controller.presetCount == count, "Shuffle changed preset count")
            if let playlist = controller.playlistHandle, !paths.isEmpty {
                precondition(playlist.positions.count == iteration + 1, "Expected one playlist position update")
                precondition(playlist.positions.last!.1, "Shuffle must preserve hard-cut behavior")
                precondition(controller.nameUpdates == iteration + 1, "Expected one preset name update")
                precondition(paths.contains(controller.currentPresetName), "Selected preset outside active filter")
            } else {
                precondition(controller.nameUpdates == 0, "Unavailable playlist changed name")
                precondition(controller.playlistHandle?.positions.isEmpty ?? true, "Unavailable playlist selected preset")
            }
        }
        print("Preset shuffle: \(scenario) passed")
    }
}
'''

    def test_shuffle_preserves_filtered_playlist_and_pending_reload(self):
        for scenario in ("singleton", "empty", "nil", "sparse", "pending"):
            with self.subTest(scenario=scenario):
                result = subprocess.run(
                    [str(self.shuffle), scenario], capture_output=True, text=True, timeout=10,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn(f"Preset shuffle: {scenario} passed", result.stdout)

    def cpu_run(self, *arguments):
        return subprocess.run(
            [str(self.cpu), *map(str, arguments)], capture_output=True, text=True, timeout=10,
        )

    def test_cpu_identity_and_counter_boundaries(self):
        result = self.cpu_run("--self-test")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_cpu_rejects_invalid_arguments(self):
        for arguments in (
            (), ("0", "1"), ("-1", "1"), ("1", "nan"), ("1", "inf"),
            ("1", "301"), ("1", "1", "0"), ("1", "1", "2"),
            ("1", "1", "1", "x" * 257),
        ):
            with self.subTest(arguments=arguments):
                result = self.cpu_run(*arguments)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, "")

    def test_cpu_rejects_absent_process(self):
        result = self.cpu_run(2147483647, 1)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")

    def test_cpu_rejects_process_exit(self):
        with subprocess.Popen([sys.executable, "-c", "import time; time.sleep(0.25)"]) as child:
            result = self.cpu_run(child.pid, 1)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(result.stdout, "")

    def measure_child(self, code):
        child = subprocess.Popen(
            [sys.executable, "-c", "print('ready', flush=True)\n" + code],
            stdout=subprocess.PIPE, text=True,
        )
        try:
            self.assertEqual(child.stdout.readline().strip(), "ready")
            result = self.cpu_run(child.pid, 2, 0.5, "synthetic-fixture")
            self.assertEqual(result.returncode, 0, result.stderr)
            report = json.loads(result.stdout)
            self.assertEqual(report["pid"], child.pid)
            self.assertGreater(report["processStart"], 0)
            self.assertTrue(report["executable"])
            self.assertGreaterEqual(report["measuredSeconds"], 2)
            self.assertTrue(report["samples"])
            weighted = sum(
                sample["cpuPercentOfOneCore"] * sample["elapsedSeconds"]
                for sample in report["samples"]
            ) / report["measuredSeconds"]
            self.assertAlmostEqual(weighted, report["meanCPUPercentOfOneCore"], places=8)
            return report
        finally:
            child.terminate()
            child.wait(timeout=5)
            child.stdout.close()

    def test_cpu_distinguishes_idle_and_busy_processes(self):
        idle = self.measure_child("import time; time.sleep(20)")
        busy = self.measure_child("while True: pass")
        self.assertGreater(busy["meanCPUPercentOfOneCore"], idle["meanCPUPercentOfOneCore"] + 10)

    def test_ipc_descriptor_reuse_partial_write_and_shutdown(self):
        result = subprocess.run([str(self.ipc)], capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("IPC server: 4 tests passed", result.stdout)

    def test_preset_archive_rejects_http_metadata_and_hash_failures(self):
        result = subprocess.run(
            [str(self.presets), str(Path(self.temp.name) / "preset-fixtures")],
            capture_output=True, text=True, timeout=15,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Preset archive validation: tests passed", result.stdout)


if __name__ == "__main__":
    unittest.main()
