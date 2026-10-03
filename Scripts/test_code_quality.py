#!/usr/bin/env python3
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


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


if __name__ == "__main__":
    unittest.main()
