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
            ("__SETUP_METHOD__", "    public func setup("),
            ("__CLEANUP_METHOD__", "    private func cleanup() {"),
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

    TEMPLATE = r"""
import Foundation
enum LogCategory { case calibration }
func dlog(_ text: String, category: LogCategory) {}
public enum CalibrationType: String, Codable { case equalLoudness }
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
        default:
            errors.append("unknown scenario")
        }
    }
}
print(String(data: try! JSONSerialization.data(withJSONObject: ["scenario": scenario, "cases": cases,
    "assertionErrors": errors], options: [.sortedKeys]), encoding: .utf8)!)
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
        for signature in ("    func randomPreset() {", "    func selectPreset(at index: Int) {"):
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
func projectm_playlist_set_position(_ playlist: Playlist, _ position: Int, _ hardCut: Bool) {
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
