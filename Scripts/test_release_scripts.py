#!/usr/bin/env python3
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class ReleaseScriptTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="systemeq-script-tests-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo = self.root / "repo with spaces"
        self.scripts = self.repo / "Scripts"
        self.scripts.mkdir(parents=True)
        source = Path(__file__).resolve().parent
        self.names = (
            "build_dmg.sh", "build_release.sh", "check_blackhole_updates.sh",
            "setup_projectm.sh", "setup_reminders.sh",
        )
        for name in self.names:
            shutil.copyfile(source / name, self.scripts / name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.log = self.root / "calls"
        self.env = dict(os.environ, PATH=f"{self.bin}:/usr/bin:/bin", CALL_LOG=str(self.log))
        for name in ("xcodebuild", "codesign", "hdiutil", "osascript", "sudo", "curl", "cmake", "git"):
            self.stub(name, 'echo "unexpected mutation" >&2\nexit 99')

    def stub(self, name, body):
        path = self.bin / name
        path.write_text(f'#!/bin/bash\nset -eu\nprintf "{name} %s\\n" "$*" >> "$CALL_LOG"\n{body}\n')
        path.chmod(0o755)

    def run_script(self, name, *args, **env):
        return subprocess.run(
            ["/bin/bash", str(self.scripts / name), *args], cwd=self.repo,
            env=dict(self.env, **env), stdin=subprocess.DEVNULL,
            capture_output=True, text=True, timeout=20,
        )

    def snapshot(self):
        return {
            str(path.relative_to(self.repo)): (
                "link", os.readlink(path)
            ) if path.is_symlink() else (
                "dir", path.stat().st_mode, path.stat().st_mtime_ns
            ) if path.is_dir() else (
                "file", path.read_bytes(), path.stat().st_mode, path.stat().st_mtime_ns
            )
            for path in self.repo.rglob("*")
        }

    def test_unsupported_arguments_are_rejected_without_mutation(self):
        for name in self.names:
            for args in (("--dry-run",), ("--unknown",), ("--help", "--dry-run")):
                with self.subTest(name=name, args=args):
                    before = self.snapshot()
                    result = self.run_script(name, *args)
                    self.assertNotEqual(result.returncode, 0, result.stdout)
                    self.assertEqual(self.snapshot(), before)
                    self.assertFalse(self.log.exists())
        for name, args in (
            ("build_dmg.sh", ("1.4.4", "--dry-run")),
            ("check_blackhole_updates.sh", ("--update", "--dry-run")),
            ("setup_projectm.sh", ("--build", "--dry-run")),
        ):
            before = self.snapshot()
            result = self.run_script(name, *args)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(self.snapshot(), before)
            self.assertFalse(self.log.exists())

    def test_help_is_read_only(self):
        for name in self.names:
            before = self.snapshot()
            result = self.run_script(name, "--help")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(self.snapshot(), before)
        self.assertFalse(self.log.exists())

    def prepare_dmg(self):
        build = self.repo / "build"
        build.mkdir()
        (build / "manual-work").write_bytes(b"preserve work")
        previous = build / "SystemEQ-v1.4.4.dmg"
        previous.write_bytes(b"previous dmg")
        self.stub("xcodebuild", '''
if [[ "${FAIL_STAGE:-}" == archive ]]; then exit 7; fi
while [[ $# -gt 0 ]]; do
    if [[ "$1" == -archivePath ]]; then
        mkdir -p "$2/Products/Applications/SystemEQ for Mac.app/Contents/Resources"
        break
    fi
    shift
done''')
        self.stub("codesign", 'if [[ "${FAIL_STAGE:-}" == sign ]]; then exit 8; fi')
        self.stub("hdiutil", '''
case "$1" in
create)
    printf 'new dmg' > "${@: -1}"
    if [[ "${FAIL_STAGE:-}" == create ]]; then exit 9; fi ;;
verify)
    if [[ "${FAIL_STAGE:-}" == verify ]]; then exit 10; fi ;;
*) exit 99 ;;
esac''')
        self.stub("mv", '''
if [[ "${FAIL_STAGE:-}" == publish && "$1" == *systemeq-dmg*/SystemEQ-v1.4.4.dmg ]]; then exit 11; fi
/bin/mv "$@"''')
        return build, previous

    def test_failed_dmg_build_retains_prior_artifacts(self):
        build, previous = self.prepare_dmg()
        for stage in ("archive", "sign", "create", "verify", "publish"):
            with self.subTest(stage=stage):
                result = self.run_script("build_dmg.sh", "1.4.4", FAIL_STAGE=stage)
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertEqual(previous.read_bytes(), b"previous dmg")
                self.assertEqual((build / "manual-work").read_bytes(), b"preserve work")
                self.assertFalse((build / ".systemeq-dmg.lock").exists())
                self.assertIn("Build artifacts preserved", result.stderr)

    def test_successful_dmg_publish_retains_backup_and_build_intermediates(self):
        build, previous = self.prepare_dmg()
        result = self.run_script("build_dmg.sh", "1.4.4")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(previous.read_bytes(), b"new dmg")
        stages = list(build.glob(".systemeq-dmg.*"))
        self.assertEqual(len(stages), 1)
        self.assertEqual((stages[0] / "previous.dmg").read_bytes(), b"previous dmg")
        self.assertTrue((stages[0] / "SystemEQ for Mac.xcarchive").is_dir())
        self.assertEqual((build / "manual-work").read_bytes(), b"preserve work")
        self.assertFalse((build / ".systemeq-dmg.lock").exists())

    def test_symlink_and_existing_lock_leave_target_untouched(self):
        build, previous = self.prepare_dmg()
        target = self.root / "outside.dmg"
        target.write_bytes(b"outside")
        previous.unlink()
        previous.symlink_to(target)
        result = self.run_script("build_dmg.sh", "1.4.4")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(target.read_bytes(), b"outside")
        self.assertFalse(self.log.exists())
        (build / ".systemeq-dmg.lock").mkdir()
        before = self.snapshot()
        result = self.run_script("build_dmg.sh", "1.4.4")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.snapshot(), before)

    def test_reminders_failure_preserves_diagnostics_and_failure_exit(self):
        self.stub("osascript", 'cat >/dev/null\necho "automation denied fixture" >&2\nexit 7')
        result = self.run_script("setup_reminders.sh")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stderr.count("automation denied fixture"), 3)
        self.assertNotIn("успішно створені", result.stdout)

    def test_noninteractive_install_always_uses_sudo_n(self):
        self.stub("git", '''
case "$1" in
clone)
    source_root="${@: -1}"
    mkdir -p "$source_root/src/libprojectM/Renderer"
    printf '    return m_texture->Empty();\\n' > "$source_root/src/libprojectM/Renderer/TextureSamplerDescriptor.cpp" ;;
-C)
    [[ "$3" == rev-parse && "$4" == HEAD ]] || exit 99
    echo 3158ee615eaafd93a8912b5f6dd84a9c47b2e00a ;;
*) exit 99 ;;
esac''')
        self.stub("cmake", "exit 0")
        self.stub("sysctl", "echo 1")
        self.stub("sudo", 'echo "privilege denied fixture" >&2\nexit 7')
        for mode in ("--build", "--build-universal"):
            with self.subTest(mode=mode):
                self.log.write_text("")
                result = self.run_script("setup_projectm.sh", mode)
                self.assertEqual(result.returncode, 7, result.stdout + result.stderr)
                calls = self.log.read_text().splitlines()
                sudo = [call for call in calls if call.startswith("sudo ")]
                self.assertEqual(len(sudo), 1)
                self.assertTrue(sudo[0].startswith("sudo -n cmake --install "), sudo)
                self.assertIn("privilege denied fixture", result.stderr)


if __name__ == "__main__":
    unittest.main()
