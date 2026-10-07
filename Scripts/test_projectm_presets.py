#!/usr/bin/env python3
import hashlib
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import tempfile
import unittest


class PresetArchiveTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="systemeq-preset-tests-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.archive = self.root / "presets.zip"
        self.archive.write_bytes(b"abc")
        self.manifest = self.root / "Info.plist"
        self.info = {
            "ProjectMPresetCommit": "1" * 40,
            "ProjectMPresetSHA256": hashlib.sha256(b"abc").hexdigest(),
        }
        self.script = Path(__file__).with_name("verify_projectm_presets.py")
        self.write_manifest(self.info)

    def write_manifest(self, info):
        self.manifest.write_bytes(plistlib.dumps(info))

    def run_cli(self, *args):
        return subprocess.run(
            [sys.executable, str(self.script), "--manifest", str(self.manifest), *map(str, args)],
            stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=10,
        )

    def test_valid_pin_and_archive(self):
        result = self.run_cli("--url")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "https://codeload.github.com/projectM-visualizer/presets-cream-of-the-crop/zip/" + "1" * 40)
        result = self.run_cli(self.archive)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_corrupt_empty_or_missing_archive_is_rejected_without_changes(self):
        sentinel = self.root / "user-presets.milk"
        sentinel.write_bytes(b"user data")
        for payload in (b"corrupt", b""):
            self.archive.write_bytes(payload)
            result = self.run_cli(self.archive)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(result.stdout, "")
            self.assertEqual(self.archive.read_bytes(), payload)
            self.assertEqual(sentinel.read_bytes(), b"user data")
        result = self.run_cli(self.root / "missing.zip")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")

    def test_invalid_metadata_or_missing_manifest_is_rejected(self):
        for info in ({}, [], dict(self.info, ProjectMPresetCommit="master"), dict(self.info, ProjectMPresetSHA256="")):
            self.write_manifest(info)
            result = self.run_cli("--url")
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(result.stdout, "")
        self.manifest.unlink()
        result = self.run_cli("--url")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")

    def test_symlink_and_ambiguous_arguments_are_rejected(self):
        link = self.root / "linked.zip"
        link.symlink_to(self.archive)
        for args in ((link,), (), ("--url", self.archive), ("--unknown",)):
            result = self.run_cli(*args)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(result.stdout, "")
        self.assertEqual(self.archive.read_bytes(), b"abc")

    def test_setup_preserves_collisions_and_propagates_copy_failure(self):
        setup = Path(__file__).with_name("setup_projectm.sh").read_text()
        match = re.search(r"(?ms)^copy_missing_presets\(\) \{.*?^\}", setup)
        self.assertIsNotNone(match)
        source = self.root / "source with spaces"
        destination = self.root / "user presets"
        source.mkdir()
        destination.mkdir()
        (source / "README.md").write_bytes(b"upstream")
        (source / "new preset.milk").write_bytes(b"preset")
        old = destination / "README.md"
        old.write_bytes(b"user data")
        old_mtime = old.stat().st_mtime_ns
        harness = "set -euo pipefail\n" + match.group(0) + '\ncopy_missing_presets "$1" "$2" "$3"\n'
        command = ["/bin/bash", "-c", harness, "fixture", str(source), str(destination), str(self.root / "files")]
        result = subprocess.run(command, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(old.read_bytes(), b"user data")
        self.assertEqual(old.stat().st_mtime_ns, old_mtime)
        self.assertEqual((destination / "new preset.milk").read_bytes(), b"preset")
        (source / "second preset.milk").write_bytes(b"new")
        bin_directory = self.root / "bin"
        bin_directory.mkdir()
        cp = bin_directory / "cp"
        cp.write_text("#!/bin/bash\necho 'injected copy failure' >&2\nexit 77\n")
        cp.chmod(0o755)
        result = subprocess.run(command, env=dict(os.environ, PATH=f"{bin_directory}:/usr/bin:/bin"), capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 77)
        self.assertIn("injected copy failure", result.stderr)
        self.assertEqual(old.read_bytes(), b"user data")


if __name__ == "__main__":
    unittest.main()
