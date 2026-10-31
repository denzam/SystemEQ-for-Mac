#!/usr/bin/env python3
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch


class FixtureRunnerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec = importlib.util.spec_from_file_location("fixture_runner", Path(__file__).with_name("run_fixture.py"))
        cls.runner = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.runner)

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="systemeq runner test ")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name).resolve()
        self.scratch = self.root / "scratch"
        self.scratch.mkdir()
        self.results = self.root / "results"

    def run_fixture(self, source="", options=(), command=None):
        arguments = ["--results", str(self.results), *options, "--", *(command or [sys.executable, "-c", source])]
        diagnostics = io.StringIO()
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(diagnostics), patch.object(tempfile, "tempdir", str(self.scratch)):
            status = self.runner.main(arguments)
        self.last_diagnostics = diagnostics.getvalue()
        reports = list(self.results.glob("*/run.json"))
        report = json.loads(reports[-1].read_text()) if reports else None
        return status, report

    def test_success_preserves_verified_evidence_and_removes_only_owned_fixture(self):
        sentinel = self.scratch / "unrelated"
        sentinel.mkdir()
        (sentinel / "keep").write_text("user data")
        status, report = self.run_fixture(
            "from pathlib import Path; import os; Path('evidence').mkdir(); Path('evidence/result.json').write_text('{\"ok\":true}'); print(os.getcwd())",
            options=("--keep", "evidence"),
        )
        self.assertEqual(status, 0)
        self.assertEqual(report["cleanup"], "removed")
        self.assertFalse(Path(report["work"]).exists())
        self.assertEqual((sentinel / "keep").read_text(), "user data")
        result = Path(report["results"]) / "artifacts/evidence/result.json"
        self.assertEqual(json.loads(result.read_text()), {"ok": True})
        self.assertEqual(report["artifacts"]["evidence"]["result.json"]["sha256"], self.runner.digest(result))
        self.assertIn(report["work"], (Path(report["results"]) / "stdout.log").read_text())

    def test_nonzero_command_preserves_fixture_and_exit_status(self):
        status, report = self.run_fixture("from pathlib import Path; import sys; Path('failure.txt').write_text('evidence'); sys.exit(7)")
        self.assertEqual(status, 7)
        self.assertEqual(report["cleanup"], "preserved")
        self.assertEqual((Path(report["work"]) / "failure.txt").read_text(), "evidence")

    def test_missing_executable_is_not_success(self):
        status, report = self.run_fixture(command=[str(self.root / "missing-command")])
        self.assertEqual(status, 125)
        self.assertTrue(Path(report["work"]).is_dir())

    def test_missing_required_evidence_prevents_cleanup(self):
        status, report = self.run_fixture(options=("--keep", "missing.json"))
        self.assertEqual(status, 125)
        self.assertTrue(Path(report["work"]).is_dir())

    def test_evidence_symlink_does_not_copy_external_data(self):
        external = self.root / "external.txt"
        external.write_text("external data")
        status, report = self.run_fixture(
            f"from pathlib import Path; Path('evidence').symlink_to({str(external)!r})",
            options=("--keep", "evidence"),
        )
        self.assertEqual(status, 125)
        self.assertEqual(external.read_text(), "external data")
        self.assertFalse((Path(report["results"]) / "artifacts").exists())

    def test_changed_owner_marker_prevents_cleanup(self):
        status, report = self.run_fixture("from pathlib import Path; Path('.owner.json').write_text('{}')")
        self.assertEqual(status, 125)
        self.assertTrue(Path(report["work"]).is_dir())

    def test_owner_marker_wrong_json_type_is_reported(self):
        for value in ("[]", "null", '"text"'):
            with self.subTest(value=value):
                status, report = self.run_fixture(f"from pathlib import Path; Path('.owner.json').write_text({value!r})")
                self.assertEqual(status, 125)
                self.assertTrue(report["completed"])
                self.assertTrue(Path(report["work"]).is_dir())

    def test_owner_marker_fifo_is_rejected_without_blocking(self):
        status, report = self.run_fixture("from pathlib import Path; import os; Path('.owner.json').unlink(); os.mkfifo('.owner.json')")
        self.assertEqual(status, 125)
        self.assertIn("regular file", report["error"])
        self.assertTrue(Path(report["work"]).is_dir())

    def test_replaced_fixture_root_does_not_touch_external_directory(self):
        external = self.root / "external"
        external.mkdir()
        (external / "keep").write_text("external data")
        status, report = self.run_fixture(
            f"from pathlib import Path; p=Path.cwd(); p.rename(p.with_name(p.name+'-moved')); p.symlink_to({str(external)!r}, target_is_directory=True)",
        )
        self.assertEqual(status, 125)
        self.assertEqual((external / "keep").read_text(), "external data")
        self.assertTrue(Path(report["work"]).is_symlink())

    def test_timeout_preserves_partial_evidence(self):
        status, report = self.run_fixture(
            "from pathlib import Path; import time; Path('partial.txt').write_text('partial'); time.sleep(10)",
            options=("--timeout", "0.3"),
        )
        self.assertEqual(status, 124)
        self.assertEqual((Path(report["work"]) / "partial.txt").read_text(), "partial")

    def test_runner_interrupt_stops_child_and_preserves_manifest(self):
        for number in (signal.SIGTERM, signal.SIGINT):
            with self.subTest(signal=number):
                results = self.root / f"signal-results-{number}"
                command = [sys.executable, str(Path(__file__).with_name("run_fixture.py")), "--results", str(results), "--", sys.executable, "-c", "from pathlib import Path; import os,time; Path('child.pid').write_text(str(os.getpid())); time.sleep(30)"]
                env = dict(os.environ, TMPDIR=str(self.scratch), PYTHONDONTWRITEBYTECODE="1")
                prior_pid_files = set(self.scratch.glob("systemeq-fixture-*/child.pid"))
                process = subprocess.Popen(command, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
                child_pid = None
                try:
                    deadline = time.monotonic() + 5
                    pid_files = []
                    while not pid_files and time.monotonic() < deadline:
                        pid_files = list(set(self.scratch.glob("systemeq-fixture-*/child.pid")) - prior_pid_files)
                        if not pid_files:
                            time.sleep(0.01)
                    self.assertTrue(pid_files, "Fixture child did not start")
                    pid_file = max(pid_files, key=lambda p: p.stat().st_mtime_ns)
                    child_pid = int(pid_file.read_text())
                    process.send_signal(number)
                    stdout, stderr = process.communicate(timeout=5)
                    self.assertEqual(process.returncode, 128 + number, (stdout, stderr))
                    with self.assertRaises(ProcessLookupError):
                        os.kill(child_pid, 0)
                    report = json.loads(next(results.glob("*/run.json")).read_text())
                    self.assertEqual(report["exit_code"], 128 + number)
                    self.assertEqual(report["cleanup"], "preserved")
                    self.assertTrue(Path(report["work"]).is_dir())
                finally:
                    if process.poll() is None:
                        os.killpg(process.pid, signal.SIGKILL)
                        process.wait(timeout=5)
                    if child_pid is not None:
                        try:
                            os.killpg(child_pid, signal.SIGKILL)
                        except ProcessLookupError:
                            self.assertFalse(self.runner.group_exists(child_pid))

    def test_background_process_prevents_success_and_cleanup(self):
        status, report = self.run_fixture("import subprocess,sys; subprocess.Popen([sys.executable,'-c','import time; time.sleep(10)'])")
        self.assertEqual(status, 125)
        self.assertIn("background", report["error"])
        self.assertTrue(Path(report["work"]).is_dir())

    def test_export_corruption_prevents_cleanup(self):
        def corrupt_copy(source, target, **kwargs):
            Path(target).write_text("corrupt")
        with patch.object(self.runner.shutil, "copy2", side_effect=corrupt_copy):
            status, report = self.run_fixture("from pathlib import Path; Path('result').write_text('original')", options=("--keep", "result"))
        self.assertEqual(status, 125)
        self.assertIn("verification failed", report["error"])
        self.assertEqual((Path(report["work"]) / "result").read_text(), "original")

    def test_manifest_write_failure_preserves_fixture(self):
        with patch.object(self.runner, "save_manifest", side_effect=OSError("disk full")):
            status, report = self.run_fixture()
        self.assertEqual(status, 125)
        self.assertIsNone(report)
        self.assertEqual(len(list(self.scratch.glob("systemeq-fixture-*"))), 1)

    def test_signal_during_cleanup_is_not_success(self):
        original_remove = self.runner.shutil.rmtree
        def interrupt_cleanup(path):
            os.kill(os.getpid(), signal.SIGTERM)
            original_remove(path)
        with patch.object(self.runner.shutil, "rmtree", side_effect=interrupt_cleanup):
            status, report = self.run_fixture()
        self.assertEqual(status, 143)
        self.assertEqual(report["exit_code"], 143)
        self.assertEqual(report["cleanup"], "removed")
        self.assertFalse(Path(report["work"]).exists())
        self.assertIn("fixture path is absent", self.last_diagnostics)

    def test_final_manifest_failure_does_not_claim_fixture_retained(self):
        original_save = self.runner.save_manifest
        calls = []
        def fail_once(destination, manifest):
            calls.append(1)
            if len(calls) == 2:
                raise OSError("disk full during final manifest")
            original_save(destination, manifest)
        with patch.object(self.runner, "save_manifest", side_effect=fail_once):
            status, report = self.run_fixture()
        self.assertEqual(status, 125)
        self.assertEqual(report["cleanup"], "removed")
        self.assertFalse(Path(report["work"]).exists())
        self.assertIn("fixture path is absent", self.last_diagnostics)
        self.assertNotIn("remains at", self.last_diagnostics)

    def test_persistent_final_manifest_failure_leaves_incomplete_record(self):
        original_save = self.runner.save_manifest
        calls = []
        def fail_after_pending(destination, manifest):
            calls.append(1)
            if len(calls) > 1:
                raise OSError("disk full")
            original_save(destination, manifest)
        with patch.object(self.runner, "save_manifest", side_effect=fail_after_pending):
            status, report = self.run_fixture()
        self.assertEqual(status, 125)
        self.assertFalse(report["completed"])
        self.assertEqual(report["cleanup"], "pending")
        self.assertFalse(Path(report["work"]).exists())
        self.assertIn("Could not save manifest", self.last_diagnostics)

    def test_check_does_not_write_or_launch_command(self):
        status, report = self.run_fixture("raise RuntimeError('must not run')", options=("--check",))
        self.assertEqual(status, 0)
        self.assertIsNone(report)
        self.assertFalse(self.results.exists())
        self.assertEqual(list(self.scratch.iterdir()), [])

    def test_invalid_arguments_leave_files_untouched(self):
        for options in (("--keep", "../outside"), ("--keep", "/absolute"), ("--keep", "a", "--keep", "a/b"), ("--timeout", "nan"), ("--unknown",)):
            with self.subTest(options=options), self.assertRaises(SystemExit) as error:
                self.run_fixture(options=options)
            self.assertEqual(error.exception.code, 2)
            self.assertFalse(self.results.exists())
            self.assertEqual(list(self.scratch.iterdir()), [])

    def test_symlink_results_directory_is_rejected_before_launch(self):
        external = self.root / "external"
        external.mkdir()
        self.results.symlink_to(external, target_is_directory=True)
        with self.assertRaises(SystemExit) as error:
            self.run_fixture()
        self.assertEqual(error.exception.code, 2)
        self.assertEqual(list(external.iterdir()), [])
        self.assertEqual(list(self.scratch.iterdir()), [])


class QualityGateTests(unittest.TestCase):
    def run_gate(self, lint_status, missing_tools=()):
        source = Path(__file__).with_name("code_quality_check.sh").read_text()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "Scripts").mkdir()
            (root / "Scripts" / "verify_tooling.py").write_text("pass\n")
            script = root / "Scripts" / "code_quality_check.sh"
            script.write_text(source)
            binaries = root / "bin"
            binaries.mkdir()
            for name in ("bash", "dirname", "grep", "cut", "mktemp", "tail", "rm", "python3"):
                (binaries / name).symlink_to(shutil.which(name))
            for name, body in {
                "git": "exit 0",
                "swiftformat": "exit 0",
                "swiftlint": f"echo 'initialization diagnostic' >&2\nexit {lint_status}",
                "xcodebuild": "exit 0",
            }.items():
                if name in missing_tools:
                    continue
                path = binaries / name
                path.write_text("#!/bin/bash\n" + body + "\n")
                path.chmod(0o755)
            env = dict(os.environ, PATH=str(binaries))
            return subprocess.run(
                ["bash", str(script), "--full"], env=env, text=True,
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30,
            )

    def test_linter_initialization_failure_is_not_success(self):
        result = self.run_gate(42)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("initialization diagnostic", result.stdout)
        self.assertNotIn("All checks passed", result.stdout)

    def test_successful_tools_pass(self):
        result = self.run_gate(0)
        self.assertEqual(result.returncode, 0, result.stdout)

    def test_full_gate_rejects_missing_linters(self):
        for tool in ("swiftformat", "swiftlint"):
            with self.subTest(tool=tool):
                result = self.run_gate(0, missing_tools=(tool,))
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("not installed", result.stdout)
                self.assertNotIn("All checks passed", result.stdout)


class PinnedSwiftFormatTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="systemeq formatter fixture ")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.paths = self.root / "github-path"
        self.calls = self.root / "calls"
        workflow = (Path(__file__).resolve().parent.parent / ".github/workflows/code-quality.yml").read_text()
        section = workflow.split("      - name: Install SwiftFormat\n", 1)[1].split("\n      - name:", 1)[0]
        lines = section.split("        run: |\n", 1)[1].splitlines()
        self.command = "\n".join(line[10:] for line in lines) + "\n"
        stub = r'''import os,sys
from pathlib import Path
name=Path(sys.argv[0]).name
with Path(os.environ['CALLS']).open('a') as stream: stream.write(name+'\n')
mode=os.environ['MODE']
if mode==name: sys.exit(17)
if name=='curl':
    Path(sys.argv[sys.argv.index('--output')+1]).write_bytes(b'fixture')
elif name=='shasum':
    sys.stdin.read()
elif name=='unzip':
    folder=Path(sys.argv[sys.argv.index('-d')+1])
    folder.mkdir()
    binary=folder/'swiftformat'
    value='0.64.3' if mode=='version' else '0.63.1'
    ending='exit 17\n' if mode=='version-error' else ''
    binary.write_text('#!/bin/sh\necho '+value+'\n'+ending)
    binary.chmod(0o755)
'''
        for name in ("curl", "shasum", "unzip"):
            tool = self.bin / name
            tool.write_text(f"#!{sys.executable}\n" + stub)
            tool.chmod(0o755)

    def invoke(self, mode="healthy"):
        env = dict(os.environ, PATH=str(self.bin) + ":/usr/bin:/bin", RUNNER_TEMP=str(self.root),
                   GITHUB_PATH=str(self.paths), CALLS=str(self.calls), MODE=mode)
        return subprocess.run(["/bin/bash", "-c", self.command], env=env, capture_output=True, text=True, timeout=20)

    def test_verified_formatter_is_published_to_job_path(self):
        result = self.invoke()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.paths.read_text(), str(self.root / "systemeq-swiftformat-0.63.1/bin") + "\n")
        self.assertEqual(self.calls.read_text().splitlines(), ["curl", "shasum", "unzip"])

    def test_download_failure_never_reaches_checksum_or_path(self):
        self.assertNotEqual(self.invoke("curl").returncode, 0)
        self.assertEqual(self.calls.read_text().splitlines(), ["curl"])
        self.assertFalse(self.paths.exists())

    def test_checksum_failure_never_extracts_or_publishes(self):
        self.assertNotEqual(self.invoke("shasum").returncode, 0)
        self.assertEqual(self.calls.read_text().splitlines(), ["curl", "shasum"])
        self.assertFalse(self.paths.exists())

    def test_extraction_failure_never_publishes(self):
        self.assertNotEqual(self.invoke("unzip").returncode, 0)
        self.assertFalse(self.paths.exists())

    def test_unexpected_binary_version_never_publishes(self):
        self.assertNotEqual(self.invoke("version").returncode, 0)
        self.assertFalse(self.paths.exists())

    def test_failed_version_command_with_valid_output_never_publishes(self):
        self.assertNotEqual(self.invoke("version-error").returncode, 0)
        self.assertFalse(self.paths.exists())


if __name__ == "__main__":
    unittest.main()
