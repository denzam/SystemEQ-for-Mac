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
