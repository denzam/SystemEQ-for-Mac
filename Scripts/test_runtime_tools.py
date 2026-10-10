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
