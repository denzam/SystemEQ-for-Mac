#!/usr/bin/env python3
import json
import os
from pathlib import Path
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


class RuntimeToolsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root = Path(__file__).resolve().parent.parent
        cls.temp = tempfile.TemporaryDirectory(prefix="systemeq-runtime-tools-")
        cls.addClassCleanup(cls.temp.cleanup)
        cls.cpu = Path(cls.temp.name) / "measure-process-cpu"
        cls.ipc = Path(cls.temp.name) / "ipc-server-tests"
        cls.presets = Path(cls.temp.name) / "preset-archive-tests"
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
