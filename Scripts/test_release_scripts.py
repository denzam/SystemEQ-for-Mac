#!/usr/bin/env python3
import os
import json
import re
from pathlib import Path
import shutil
import subprocess
import sys
import textwrap
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
            "setup_projectm.sh", "setup_reminders.sh", "prepare_signed_release.sh",
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


class SignedReleaseTests(unittest.TestCase):
    identity = "A" * 40
    team = "1234567890"

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="systemeq-signed-tests-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.repo = self.root / "repo with spaces"
        self.scripts = self.repo / "Scripts"
        self.scripts.mkdir(parents=True)
        source = Path(__file__).resolve().parent.parent
        shutil.copyfile(source / "Scripts/prepare_signed_release.sh", self.scripts / "prepare_signed_release.sh")
        (self.repo / "Config").mkdir()
        shutil.copyfile(source / "Config/SystemEQ.entitlements", self.repo / "Config/SystemEQ.entitlements")
        (self.scripts / "verify_release_artifacts.sh").write_text(
            '#!/bin/bash\n[[ "${FAIL_MODE:-}" != bundle ]]\n'
        )
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.log = self.root / "calls.jsonl"
        body = '''#!/usr/bin/python3
import hashlib, json, os, pathlib, plistlib, shutil, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
mode = os.environ.get("FAIL_MODE", "")
with open(os.environ["CALL_LOG"], "a") as stream:
    stream.write(json.dumps([name, *args]) + "\\n")
if name == "security":
    if mode == "identity-command": sys.exit(7)
    if mode != "identity-empty":
        print('  1) ' + 'A' * 40 + ' "Developer ID Application: Fixture (1234567890)"')
elif name == "xcodebuild":
    if mode == "archive": sys.exit(7)
    archive = pathlib.Path(args[args.index("-archivePath") + 1])
    app = archive / "Products/Applications/SystemEQ for Mac.app"
    components = [(app, "SystemEQ for Mac"), (app / "Contents/Helpers/ProjectMHelper.app", "ProjectMHelper")]
    for base, executable in components:
        (base / "Contents/MacOS").mkdir(parents=True)
        (base / "Contents/Frameworks").mkdir()
        (base / "Contents/Resources").mkdir()
        (base / "Contents/Resources/Assets.car").write_bytes(b"assets")
        (base / "Contents/Resources/EQDatabase.db").write_bytes(b"database")
        (base / "Contents/Info.plist").write_bytes(plistlib.dumps({"CFBundleShortVersionString": "1.4.4", "CFBundleExecutable": executable}))
        for target in [base / "Contents/MacOS" / executable, *(base / "Contents/Frameworks" / lib for lib in ("libprojectM-4.4.dylib", "libprojectM-4-playlist.4.dylib"))]:
            target.write_bytes(bytes.fromhex("cafebabe") + b"fixture")
    if mode == "extra-code": (app / "Contents/MacOS/Unexpected").write_bytes(bytes.fromhex("cafebabe"))
    if mode == "escaping-link": (app / "Contents/escape").symlink_to(os.environ["OUTSIDE"])
elif name == "codesign":
    if "-R" in args and not args[args.index("-R") + 1].startswith("="): sys.stderr.write("literal requirement must start with ="); sys.exit(7)
    if "--force" in args and mode == "sign": sys.exit(7)
    if "--force" in args and args[-1].endswith(".dmg"):
        if mode == "dmg-sign": sys.exit(7)
        path = pathlib.Path(args[-1])
        path.write_bytes(path.read_bytes() + b"|signed")
    if "--verify" in args and mode == "verify": sys.stderr.write("verification failure fixture"); sys.exit(7)
    if "--verify" in args and mode == "distribution-signature" and "DistributionCheck" in args[-1]: sys.exit(7)
    if "--display" in args:
        if mode == "display": sys.exit(7)
        team = "OTHERTEAM0" if mode == "wrong-team" else "1234567890"
        flags = "0x0(none)" if mode == "no-runtime" else "0x10000(runtime)"
        sys.stderr.write(f"TeamIdentifier={team}\\nAuthority=Developer ID Application: Fixture\\nCodeDirectory v=20500 flags={flags}\\n")
        if mode == "adhoc": sys.stderr.write("Signature=adhoc\\n")
        if mode != "no-timestamp": sys.stderr.write("Timestamp=fixture timestamp\\n")
        entitlements = {}
        if args[-1].endswith("SystemEQ for Mac.app"):
            entitlements = {"com.apple.security.device.audio-input": True, "com.apple.security.automation.apple-events": True}
        if mode == "debug-entitlement": entitlements["com.apple.security.get-task-allow"] = True
        if entitlements: sys.stdout.buffer.write(plistlib.dumps(entitlements) if "--xml" in args else b"[Dict] fixture entitlements")
elif name == "lipo":
    print("arm64" if mode == "thin" else "arm64 x86_64")
elif name == "otool":
    print(args[-1] + ":\\n\\t/usr/lib/libSystem.B.dylib (compatibility version 1.0.0, current version 1.0.0)")
elif name == "hdiutil":
    if args[0] == "attach":
        if mode == "mount": sys.exit(7)
        mount = pathlib.Path(args[args.index("-mountpoint") + 1])
        source = pathlib.Path(os.environ["DISTRIBUTION_APP"])
        shutil.copytree(source, mount / source.name)
        if mode == "dmg-mismatch": (mount / source.name / "Contents/mismatch").write_bytes(b"different")
    elif args[0] == "detach":
        if mode == "detach": sys.exit(7)
    else: sys.exit(99)
elif name == "ditto":
    if "-x" in args:
        if mode == "extract": sys.exit(7)
        source = pathlib.Path(args[-2]).parent / "SystemEQ for Mac.app"
        target = pathlib.Path(args[-1]) / source.name
        shutil.copytree(source, target, symlinks=True)
        if mode == "package-corrupt": (target / "Contents/Info.plist").write_bytes(b"changed")
    elif "-c" in args:
        pathlib.Path(args[-1]).write_bytes(b"fixture zip")
    else:
        shutil.copytree(args[-2], args[-1], symlinks=True)
    if mode == "zip": sys.exit(7)
elif name == "xcrun":
    if args[:2] == ["notarytool", "submit"]:
        if mode == "notary-command": sys.exit(7)
        pathlib.Path(os.environ["SUBMITTED_PATH"]).write_text(args[2])
        if mode == "notary-empty": sys.exit(0)
        if mode == "notary-malformed": print("broken JSON"); sys.exit(0)
        print(json.dumps({"id": "12345678-1234-1234-1234-123456789abc", "status": "Uploaded"}))
    elif args[:2] == ["notarytool", "info"]:
        if mode == "info-command": sys.exit(7)
        if mode == "info-empty": sys.exit(0)
        identifier = "87654321-1234-1234-1234-123456789abc" if mode == "info-mismatch" else args[2]
        status = "In Progress" if mode == "wait-timeout" else "Invalid" if mode == "notary-rejected" else "Accepted"
        print(json.dumps({"id": identifier, "status": status}))
    elif args[:2] == ["notarytool", "wait"]:
        if mode == "wait-timeout": sys.stderr.write("wait timeout fixture"); sys.exit(7)
        print(json.dumps({"id": args[2], "status": "Accepted"}))
    elif args[:2] == ["notarytool", "log"]:
        if mode == "log-command": sys.exit(7)
        if mode == "log-malformed": print("broken JSON"); sys.exit(0)
        digest = "0" * 64 if mode == "log-wrong-archive" else hashlib.sha256(pathlib.Path(pathlib.Path(os.environ["SUBMITTED_PATH"]).read_text()).read_bytes()).hexdigest()
        print(json.dumps({"jobId": args[2], "status": "Invalid" if mode in ("notary-rejected", "log-rejected") else "Accepted", "sha256": digest, "issues": None}))
    elif args[:2] == ["stapler", "staple"]:
        if mode == "staple": sys.exit(7)
        path = pathlib.Path(args[-1])
        if path.suffix == ".dmg":
            if mode == "dmg-staple": sys.exit(7)
            path.write_bytes(path.read_bytes() + b"|ticket")
        else:
            (path / "Contents/notary-ticket.fixture").write_bytes(b"notary ticket")
    elif args[:2] == ["stapler", "validate"]:
        if mode == "staple-validate": sys.exit(7)
        if mode == "distribution-ticket" and "DistributionCheck" in args[-1]: sys.exit(7)
        path = pathlib.Path(args[-1])
        if path.suffix == ".dmg":
            if mode == "dmg-ticket" or not path.read_bytes().endswith(b"|ticket"): sys.exit(8)
        elif not (path / "Contents/notary-ticket.fixture").is_file(): sys.exit(8)
    else: sys.exit(99)
elif name == "spctl":
    if mode == "dmg-gatekeeper" and "open" in args: sys.exit(7)
    if mode == "gatekeeper": sys.exit(7)
    if mode == "distribution-gatekeeper" and "DistributionCheck" in args[-1]: sys.exit(7)
else: sys.exit(99)
'''
        for name in ("security", "xcodebuild", "codesign", "lipo", "ditto", "xcrun", "spctl", "otool", "hdiutil"):
            target = self.bin / name
            target.write_text(body)
            target.chmod(0o755)
        self.outside = self.root / "user-data"
        self.outside.write_bytes(b"preserve user data")
        self.env = dict(os.environ, PATH=f"{self.bin}:/usr/bin:/bin", CALL_LOG=str(self.log), OUTSIDE=str(self.outside), SUBMITTED_PATH=str(self.root / "submitted-path"))

    def invoke(self, *args, mode=""):
        return subprocess.run(
            ["bash", str(self.scripts / "prepare_signed_release.sh"), *map(str, args)],
            cwd=self.repo, env=dict(self.env, FAIL_MODE=mode),
            capture_output=True, text=True, timeout=30,
        )

    def build(self, mode=""):
        return self.invoke("--build", "--identity", self.identity, "--team", self.team, mode=mode)

    def prepared(self):
        base = self.repo / "LocalArtifacts/SignedReleases"
        before = set(base.iterdir()) if base.exists() else set()
        result = self.build()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        directory, = set(base.iterdir()) - before
        return directory

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []

    def test_check_is_read_only_and_uses_no_signing_or_upload(self):
        before = {str(path): path.read_bytes() for path in self.repo.rglob("*") if path.is_file()}
        result = self.invoke("--check", "--identity", self.identity, "--team", self.team)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(before, {str(path): path.read_bytes() for path in self.repo.rglob("*") if path.is_file()})
        self.assertEqual([call[0] for call in self.calls()], ["security"])

    def test_bad_arguments_and_identity_cannot_create_artifacts(self):
        for args in (("--build",), ("--check", "--identity"), ("--check", "--identity", "bad", "--team", self.team), ("--notarize", "outside", "--profile", "bad/profile"), ("--resume", "outside"), ("--staple", "outside", "--submission-id", "bad"), ("--resume", "outside", "--profile", "fixture", "--submission-id", "bad")):
            result = self.invoke(*args)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse((self.repo / "LocalArtifacts").exists())
            self.assertFalse(self.calls())
        for mode in ("identity-empty", "identity-command"):
            result = self.build(mode)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse((self.repo / "LocalArtifacts").exists())

    def test_signing_order_and_archive_options(self):
        directory = self.prepared()
        calls = self.calls()
        archive = next(call for call in calls if call[0] == "xcodebuild")
        self.assertIn("ARCHS=arm64 x86_64", archive)
        self.assertIn("ONLY_ACTIVE_ARCH=NO", archive)
        self.assertIn("CODE_SIGNING_ALLOWED=NO", archive)
        signed = [call for call in calls if call[0] == "codesign" and "--force" in call]
        self.assertEqual(len(signed), 6)
        self.assertTrue(all(call[-1].endswith(".dylib") for call in signed[:4]))
        self.assertTrue(signed[4][-1].endswith("ProjectMHelper.app"))
        self.assertTrue(signed[5][-1].endswith("SystemEQ for Mac.app"))
        self.assertTrue(all("--deep" not in call for call in signed))
        self.assertTrue(all("--entitlements" not in call for call in signed[:5]))
        self.assertIn("--entitlements", signed[5])
        self.assertTrue((directory / "manifest.json").is_file())
        self.assertFalse((directory / "completed.json").exists())
        self.assertFalse(any(call[0] == "xcrun" for call in calls))

    def test_build_failures_preserve_evidence_and_never_report_signed_success(self):
        for mode in ("archive", "extra-code", "escaping-link", "sign", "verify", "display", "wrong-team", "no-runtime", "no-timestamp", "debug-entitlement", "thin", "bundle", "zip"):
            with self.subTest(mode=mode):
                before = set((self.repo / "LocalArtifacts/SignedReleases").iterdir()) if (self.repo / "LocalArtifacts/SignedReleases").exists() else set()
                result = self.build(mode)
                self.assertNotEqual(result.returncode, 0, result.stdout)
                directory, = set((self.repo / "LocalArtifacts/SignedReleases").iterdir()) - before
                self.assertFalse((directory / "manifest.json").exists())
                self.assertIn("Artifacts preserved", result.stderr)
                self.assertNotIn("Signed universal app verified", result.stdout)
                self.assertEqual(self.outside.read_bytes(), b"preserve user data")

    def test_rejects_artifacts_directory_symlink(self):
        (self.repo / "LocalArtifacts").symlink_to(self.root)
        result = self.build()
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.root / "SignedReleases").exists())

    def test_modified_app_or_zip_cannot_be_submitted(self):
        directory = self.prepared()
        (directory / "SystemEQ-signed.zip").write_bytes(b"changed")
        result = self.invoke("--notarize", directory, "--profile", "fixture")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(call[0] == "xcrun" for call in self.calls()))
        (directory / "SystemEQ-signed.zip").write_bytes(b"fixture zip")
        (directory / "SystemEQ for Mac.app/Contents/Info.plist").write_bytes(b"changed")
        result = self.invoke("--notarize", directory, "--profile", "fixture")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(call[0] == "xcrun" for call in self.calls()))

    def test_notary_failures_never_staple_or_complete(self):
        for mode in ("notary-command", "notary-empty", "notary-malformed", "notary-rejected", "info-command", "info-empty", "info-mismatch", "wait-timeout", "log-command", "log-rejected", "log-malformed", "log-wrong-archive"):
            with self.subTest(mode=mode):
                directory = self.prepared()
                self.log.write_text("")
                result = self.invoke("--notarize", directory, "--profile", "fixture", mode=mode)
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertFalse((directory / "completed.json").exists())
                self.assertFalse((directory / "SystemEQ-notarized.zip").exists())
                self.assertFalse(any(call[:3] == ["xcrun", "stapler", "staple"] for call in self.calls()))
                self.assertTrue((directory / "submission-output.log").exists())
                self.log.write_text("")
                result = self.invoke("--notarize", directory, "--profile", "fixture")
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(any(call[0] == "xcrun" for call in self.calls()))

    def test_stapler_and_gatekeeper_failures_never_complete(self):
        for mode in ("staple", "staple-validate", "gatekeeper", "package-corrupt", "extract", "distribution-ticket", "distribution-signature", "distribution-gatekeeper"):
            with self.subTest(mode=mode):
                self.log.write_text("")
                directory = self.prepared()
                result = self.invoke("--notarize", directory, "--profile", "fixture", mode=mode)
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertFalse((directory / "completed.json").exists())
                if mode != "package-corrupt":
                    self.assertFalse((directory / "SystemEQ-notarized.zip").exists())
                source = directory / "SystemEQ for Mac.app"
                self.assertFalse((source / "Contents/notary-ticket.fixture").exists())
                attempts = {path: {p.relative_to(path): p.read_bytes() for p in path.rglob("*") if p.is_file()} for path in directory.glob("finalize-*")}
                result = self.invoke("--staple", directory)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                complete = json.loads((directory / "completed.json").read_text())
                self.assertTrue((directory / complete["zip"]).is_file())
                self.assertTrue((directory / complete["app"] / "Contents/notary-ticket.fixture").is_file())
                self.assertFalse((source / "Contents/notary-ticket.fixture").exists())
                self.assertEqual(sum(call[:3] == ["xcrun", "notarytool", "submit"] for call in self.calls()), 1)
                for path, before in attempts.items():
                    self.assertEqual({p.relative_to(path): p.read_bytes() for p in path.rglob("*") if p.is_file()}, before)

    def test_resume_fetches_status_and_log_without_uploading_again(self):
        for mode in ("log-command", "log-malformed", "info-command", "wait-timeout"):
            with self.subTest(mode=mode):
                directory = self.prepared()
                result = self.invoke("--notarize", directory, "--profile", "fixture", mode=mode)
                self.assertNotEqual(result.returncode, 0)
                self.assertTrue((directory / "submission.json").is_file())
                logs = {path: path.read_bytes() for path in directory.rglob("*.log")}
                self.log.write_text("")
                result = self.invoke("--resume", directory, "--profile", "fixture")
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertTrue((directory / "completed.json").is_file())
                self.assertFalse(any(call[:3] == ["xcrun", "notarytool", "submit"] for call in self.calls()))
                for path, before in logs.items():
                    self.assertTrue(path.read_bytes().startswith(before))

    def test_unknown_upload_requires_explicit_submission_id_and_matching_archive(self):
        directory = self.prepared()
        result = self.invoke("--notarize", directory, "--profile", "fixture", mode="notary-empty")
        self.assertNotEqual(result.returncode, 0)
        self.log.write_text("")
        result = self.invoke("--resume", directory, "--profile", "fixture")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(call[0] == "xcrun" for call in self.calls()))
        identifier = "12345678-1234-1234-1234-123456789abc"
        result = self.invoke("--resume", directory, "--profile", "fixture", "--submission-id", identifier, mode="log-wrong-archive")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((directory / "completed.json").exists())
        self.assertFalse(any(call[:3] == ["xcrun", "notarytool", "submit"] for call in self.calls()))
        self.log.write_text("")
        result = self.invoke("--resume", directory, "--profile", "fixture", "--submission-id", "87654321-1234-1234-1234-123456789abc")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(call[0] == "xcrun" for call in self.calls()))
        result = self.invoke("--resume", directory, "--profile", "fixture")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_staple_requires_matching_accepted_submission_and_log(self):
        directory = self.prepared()
        result = self.invoke("--staple", directory)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(call[0] == "xcrun" for call in self.calls()))
        result = self.invoke("--notarize", directory, "--profile", "fixture", mode="notary-rejected")
        self.assertNotEqual(result.returncode, 0)
        self.log.write_text("")
        result = self.invoke("--staple", directory)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(call[0] == "xcrun" for call in self.calls()))
        self.assertFalse((directory / "completed.json").exists())

    def test_failed_retry_preserves_original_verification_diagnostics(self):
        directory = self.prepared()
        result = self.invoke("--staple", directory, mode="verify")
        self.assertNotEqual(result.returncode, 0)
        log = directory / "preflight-0-verify.log"
        original = log.read_bytes()
        self.assertIn(b"verification failure fixture", original)
        result = self.invoke("--staple", directory)
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(log.read_bytes().startswith(original))

    def test_accepted_submission_requires_all_validation_before_completion(self):
        directory = self.prepared()
        result = self.invoke("--notarize", directory, "--profile", "fixture")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue((directory / "completed.json").is_file())
        self.assertTrue((directory / "notary-log.json").is_file())
        complete = json.loads((directory / "completed.json").read_text())
        self.assertTrue((directory / complete["zip"]).is_file())
        calls = self.calls()
        self.assertIn(["xcrun", "stapler", "validate", str(directory / complete["app"])], calls)
        self.assertTrue(any(call[0] == "spctl" for call in calls))
        result = self.invoke("--notarize", directory, "--profile", "fixture")
        self.assertNotEqual(result.returncode, 0)

    def distribution_fixture(self):
        directory = self.prepared()
        result = self.invoke("--notarize", directory, "--profile", "fixture")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        complete = json.loads((directory / "completed.json").read_text())
        self.env["DISTRIBUTION_APP"] = str(directory / complete["app"])
        source = Path(__file__).resolve().parent / "verify_release_artifacts.sh"
        shutil.copyfile(source, self.scripts / source.name)
        dmg = self.root / "input.dmg"
        dmg.write_bytes(b"fixture dmg")
        return directory, directory / complete["zip"], dmg

    def test_machine_record_is_written_only_after_success(self):
        record = self.root / "signed.json"
        result = self.invoke("--build", "--identity", self.identity, "--team", self.team, "--record", record)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        state = json.loads(record.read_text())
        self.assertEqual(state["phase"], "signed")
        directory = Path(state["run"])
        complete_record = self.root / "notarized.json"
        result = self.invoke("--notarize", directory, "--profile", "fixture", "--record", complete_record, mode="info-command")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(complete_record.exists())
        result = self.invoke("--resume", directory, "--profile", "fixture", "--keychain", "fixture.keychain", "--record", complete_record)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(json.loads(complete_record.read_text())["phase"], "notarized")
        self.assertTrue(any("--keychain" in call for call in self.calls() if call[:2] == ["xcrun", "notarytool"]))
        before = record.read_bytes()
        self.log.write_text("")
        result = self.invoke("--build", "--identity", self.identity, "--team", self.team, "--record", record)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(record.read_bytes(), before)
        self.assertEqual(self.calls(), [])

    def test_dmg_finalization_preserves_source_and_never_rebuilds_app(self):
        directory, package, dmg = self.distribution_fixture()
        before = dmg.read_bytes(), package.read_bytes()
        record = self.root / "dmg.json"
        self.log.write_text("")
        result = self.invoke("--notarize-dmg", directory, "--dmg", dmg, "--profile", "fixture", "--record", record)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        complete = json.loads((directory / "dmg/completed.json").read_text())
        final = directory / complete["dmg"]
        self.assertEqual(json.loads(record.read_text())["phase"], "dmg")
        self.assertTrue(final.read_bytes().endswith(b"|signed|ticket"))
        self.assertEqual((dmg.read_bytes(), package.read_bytes()), before)
        self.assertEqual((directory / "dmg/SystemEQ-signed.dmg").read_bytes(), b"fixture dmg|signed")
        calls = self.calls()
        self.assertFalse(any(call[0] == "xcodebuild" for call in calls))
        signed = [call for call in calls if call[0] == "codesign" and "--force" in call]
        self.assertEqual(len(signed), 1)
        self.assertTrue(signed[0][-1].endswith(".dmg"))
        self.assertEqual(sum(call[:3] == ["xcrun", "notarytool", "submit"] for call in calls), 1)

    def test_dmg_notary_failure_and_resume_use_one_immutable_upload(self):
        directory, _, dmg = self.distribution_fixture()
        self.log.write_text("")
        result = self.invoke("--notarize-dmg", directory, "--dmg", dmg, "--profile", "fixture", mode="log-command")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((directory / "dmg/completed.json").exists())
        signed = (directory / "dmg/SystemEQ-signed.dmg").read_bytes()
        result = self.invoke("--resume-dmg", directory, "--profile", "fixture")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((directory / "dmg/SystemEQ-signed.dmg").read_bytes(), signed)
        self.assertEqual(sum(call[:3] == ["xcrun", "notarytool", "submit"] for call in self.calls()), 1)

    def test_dmg_failures_never_complete_and_keep_signed_source(self):
        for mode in ("notary-empty", "notary-malformed", "notary-rejected", "info-mismatch", "log-wrong-archive", "dmg-staple", "dmg-ticket", "dmg-gatekeeper", "mount", "detach", "dmg-mismatch"):
            with self.subTest(mode=mode):
                directory, package, dmg = self.distribution_fixture()
                before = dmg.read_bytes(), package.read_bytes()
                result = self.invoke("--notarize-dmg", directory, "--dmg", dmg, "--profile", "fixture", mode=mode)
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertFalse((directory / "dmg/completed.json").exists())
                self.assertEqual((dmg.read_bytes(), package.read_bytes()), before)
                signed = directory / "dmg/SystemEQ-signed.dmg"
                if (directory / "dmg/manifest.json").exists():
                    self.assertEqual(signed.read_bytes(), b"fixture dmg|signed")

    def test_distribution_verifier_rejects_identity_runtime_timestamp_ticket_and_mismatch(self):
        directory, package, dmg = self.distribution_fixture()
        dmg.write_bytes(b"fixture dmg|ticket")
        command = ["bash", str(self.scripts / "verify_release_artifacts.sh"), "--distribution", self.team, str(package), str(dmg), "1.4.4"]
        for mode in ("", "wrong-team", "no-runtime", "no-timestamp", "debug-entitlement", "adhoc", "thin", "dmg-ticket", "dmg-mismatch", "mount", "detach"):
            with self.subTest(mode=mode):
                result = subprocess.run(command, env=dict(self.env, FAIL_MODE=mode), capture_output=True, text=True, timeout=30)
                if mode:
                    self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                else:
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        app = Path(self.env["DISTRIBUTION_APP"])
        extra = app / "Contents/MacOS/extra"
        extra.write_bytes(bytes.fromhex("cafebabe"))
        result = subprocess.run(command, env=self.env, capture_output=True, text=True, timeout=30)
        self.assertNotEqual(result.returncode, 0)
        extra.unlink()
        (app / "Contents/notary-ticket.fixture").unlink()
        result = subprocess.run(command, env=self.env, capture_output=True, text=True, timeout=30)
        self.assertNotEqual(result.returncode, 0)


class ReleaseGateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="systemeq-release-gate-")
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.repo = self.home / "repo with spaces"
        self.repo.mkdir()
        source = Path(__file__).resolve().parent.parent
        for name in ("SystemEQ for Mac.xcodeproj/project.pbxproj", "Config/Info.plist", "Config/ProjectMHelper/Info.plist", "CHANGELOG.md", "Scripts/check_release.py"):
            target = self.repo / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source / name, target)
        self.version = "1.4.4"
        project = self.repo / "SystemEQ for Mac.xcodeproj/project.pbxproj"
        project.write_text(re.sub(r"MARKETING_VERSION = [^;]+;", "MARKETING_VERSION = 1.4.4;", project.read_text()))
        (self.repo / "CHANGELOG.md").write_text("## [1.4.4] — 2026-10-10\n\n### Fixed\n- Fixture correction\n\n## [1.4.3] — 2026-10-01\n\n- Prior fix\n")
        self.git("init", "-b", "main")
        self.git("config", "user.name", "Fixture")
        self.git("config", "user.email", "fixture@example.invalid")
        self.git("remote", "add", "origin", "https://github.com/owner/project.git")
        self.commit()
        self.sha = self.git("rev-parse", "HEAD").strip()
        self.bin = self.home / "bin"
        self.bin.mkdir()
        self.responses = self.home / "responses.json"
        self.calls = self.home / "calls.jsonl"
        executable = self.bin / "gh"
        executable.write_text(f'''#!{sys.executable}
import json, os, sys
from pathlib import Path
with Path(os.environ["CALLS"]).open("a") as stream:
    stream.write(json.dumps(sys.argv[1:])+"\\n")
if sys.argv[1:4] != ["api", "--method", "GET"]:
    sys.exit(98)
responses=json.loads(Path(os.environ["RESPONSES"]).read_text())
response=responses.get(sys.argv[-1], {{"error":"unexpected endpoint"}})
if "sequence" in response:
    calls=[json.loads(line) for line in Path(os.environ["CALLS"]).read_text().splitlines()]
    index=sum(call[-1]==sys.argv[-1] for call in calls)-1
    response=response["sequence"][min(index,len(response["sequence"])-1)]
if "error" in response:
    print(response["error"], file=sys.stderr)
    sys.exit(7)
print(response.get("raw", json.dumps(response["json"])) if "raw" not in response else response["raw"])
''')
        executable.chmod(0o755)
        self.env = dict(os.environ, PATH=f"{self.bin}:{os.environ['PATH']}", RESPONSES=str(self.responses), CALLS=str(self.calls), PYTHONDONTWRITEBYTECODE="1")
        self.script = source / "Scripts/check_release.py"
        self.workflow = (source / ".github/workflows/release.yml").read_text()
        self.run = {"id": 10, "head_sha": self.sha, "event": "push", "head_branch": "main", "workflow_id": 2, "name": "Code Quality", "path": ".github/workflows/code-quality.yml", "repository": {"full_name": "owner/project"}, "status": "completed", "conclusion": "success", "run_attempt": 1}
        self.jobs = [{"id": i + 1, "name": name, "head_sha": self.sha, "run_id": 10, "run_attempt": 1, "status": "completed", "conclusion": "success"} for i, name in enumerate(("Tooling Check", "SwiftLint", "SwiftFormat Check", "Sanitizer (address)", "Sanitizer (thread)", "Test Check"))]
        self.data = {
            "repos/owner/project/git/matching-refs/tags/v1.4.4": {"json": []},
            "repos/owner/project/actions/workflows/code-quality.yml": {"json": {"id": 2, "path": ".github/workflows/code-quality.yml", "name": "Code Quality", "state": "active"}},
            f"repos/owner/project/actions/workflows/code-quality.yml/runs?head_sha={self.sha}&event=push&branch=main&per_page=100": {"json": [{"total_count": 1, "workflow_runs": [self.run]}]},
            "repos/owner/project/actions/runs/10/attempts/1/jobs?per_page=100": {"json": [{"total_count": 6, "jobs": self.jobs}]},
            "repos/owner/project/actions/runs/10": {"json": self.run},
        }

    def git(self, *args):
        return subprocess.run(["git", *args], cwd=self.repo, check=True, capture_output=True, text=True).stdout

    def commit(self):
        self.git("add", ".")
        self.git("commit", "-m", "fixture")

    def synchronize_ci(self):
        old = next(key for key in self.data if "/runs?" in key)
        self.sha = self.git("rev-parse", "HEAD").strip()
        self.run["head_sha"] = self.sha
        for job in self.jobs:
            job["head_sha"] = self.sha
        new = f"repos/owner/project/actions/workflows/code-quality.yml/runs?head_sha={self.sha}&event=push&branch=main&per_page=100"
        self.data[new] = self.data.pop(old)

    def invoke(self, *args):
        self.responses.write_text(json.dumps(self.data))
        return subprocess.run([sys.executable, "-B", str(self.script), "--check", "--version", self.version, "--sha", "HEAD", "--repo", "owner/project", *args], cwd=self.repo, env=self.env, capture_output=True, text=True, timeout=20)

    def snapshot(self):
        return {str(p.relative_to(self.repo)): (p.stat().st_mode, p.stat().st_mtime_ns, None if p.is_dir() else p.read_bytes()) for p in self.repo.rglob("*")}

    def assert_refused(self, *args):
        before = self.snapshot()
        result = self.invoke(*args)
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("Release check failed", result.stderr)
        self.assertEqual(before, self.snapshot())
        return result

    def test_healthy_check_is_read_only_and_returns_committed_metadata(self):
        before = self.snapshot()
        result = self.invoke()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(before, self.snapshot())
        output = json.loads(result.stdout)
        self.assertEqual(output["sha"], self.sha)
        self.assertEqual(output["release_notes"], "### Fixed\n- Fixture correction")
        self.assertEqual(output["tag_message"], "SystemEQ for Mac v1.4.4")
        self.assertEqual(len(output["ci"]["jobs"]), 6)

    def test_bad_api_and_incomplete_pagination_are_refused(self):
        endpoint = next(key for key in self.data if "/runs?" in key)
        for value in ({"error": "permission denied"}, {"raw": ""}, {"raw": "null"}, {"raw": "{}"}, {"json": [{"total_count": 0, "workflow_runs": []}]}, {"json": [{"total_count": 2, "workflow_runs": [self.run]}]}):
            with self.subTest(value=value):
                self.data[endpoint] = value
                self.assert_refused()

    def test_wrong_sha_branch_event_and_workflow_are_refused(self):
        for key, value in (("head_sha", "0" * 40), ("head_branch", "develop"), ("event", "pull_request"), ("workflow_id", 9), ("path", ".github/workflows/other.yml"), ("repository", {"full_name": "other/project"})):
            original = self.run[key]
            self.run[key] = value
            with self.subTest(key=key):
                self.assert_refused()
            self.run[key] = original

    def test_latest_failed_or_pending_run_does_not_reuse_old_success(self):
        endpoint = next(key for key in self.data if "/runs?" in key)
        for status, conclusion in (("queued", None), ("in_progress", None), ("completed", "failure"), ("completed", "cancelled")):
            latest = dict(self.run, id=11, status=status, conclusion=conclusion)
            self.data[endpoint] = {"json": [{"total_count": 2, "workflow_runs": [self.run, latest]}]}
            self.assert_refused()

    def test_missing_skipped_and_wrong_attempt_jobs_are_refused(self):
        key = "repos/owner/project/actions/runs/10/attempts/1/jobs?per_page=100"
        original = self.data[key]
        self.data[key] = {"json": [{"total_count": 5, "jobs": self.jobs[:-1]}]}
        self.assert_refused()
        self.data[key] = original
        for field, value in (("conclusion", "skipped"), ("run_attempt", 2), ("run_id", 11), ("head_sha", "0" * 40)):
            old = self.jobs[0][field]
            self.jobs[0][field] = value
            self.assert_refused()
            self.jobs[0][field] = old

    def test_ci_attempt_change_during_validation_is_refused(self):
        self.data["repos/owner/project/actions/runs/10"] = {"json": dict(self.run, run_attempt=2)}
        self.assert_refused()

    def test_new_ci_run_appearing_during_validation_is_refused(self):
        endpoint = next(key for key in self.data if "/runs?" in key)
        initial = self.data[endpoint]
        latest = dict(self.run, id=11, status="queued", conclusion=None)
        self.data[endpoint] = {"sequence": [initial, {"json": [{"total_count": 2, "workflow_runs": [self.run, latest]}]}]}
        self.assert_refused()

    def test_project_and_plist_version_mismatch_are_refused(self):
        initial = self.sha
        path = self.repo / "SystemEQ for Mac.xcodeproj/project.pbxproj"
        path.write_text(path.read_text().replace("MARKETING_VERSION = 1.4.4;", "MARKETING_VERSION = 1.4.5;", 1))
        self.commit()
        self.synchronize_ci()
        self.assert_refused()
        self.git("reset", "--hard", initial)
        self.synchronize_ci()
        path = self.repo / "Config/ProjectMHelper/Info.plist"
        path.write_text(path.read_text().replace("$(MARKETING_VERSION)", "1.4.5"))
        self.commit()
        self.synchronize_ci()
        self.assert_refused()

    def test_missing_duplicate_empty_and_old_changelog_sections_are_refused(self):
        path = self.repo / "CHANGELOG.md"
        original = path.read_text()
        for content in ("## [1.4.3] — 2026-10-01\n- Old", original + original, "## [1.4.4] — 2026-10-10\n", "## [1.4.5] — 2026-10-11\n- New\n" + original):
            path.write_text(content)
            self.commit()
            self.synchronize_ci()
            self.assert_refused()

    def test_dirty_tree_and_shell_sensitive_version_are_refused(self):
        (self.repo / "work.txt").write_text("preserve")
        self.assert_refused()
        (self.repo / "work.txt").unlink()
        self.version = "1.4.4; touch injected"
        self.assert_refused()
        self.assertFalse((self.repo / "injected").exists())

    def tag(self, message="SystemEQ for Mac v1.4.4"):
        self.git("tag", "-a", "v1.4.4", "-m", message)
        self.data["repos/owner/project/git/ref/tags/v1.4.4"] = {"json": {"ref": "refs/tags/v1.4.4", "object": {"type": "tag", "sha": self.git("rev-parse", "refs/tags/v1.4.4").strip()}}}

    def test_matching_annotated_remote_tag_is_accepted(self):
        self.tag()
        result = self.invoke("--require-tag")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_missing_lightweight_contaminated_or_moved_tags_are_refused(self):
        self.assert_refused("--require-tag")
        self.git("tag", "v1.4.4")
        self.assert_refused("--require-tag")
        self.git("tag", "-d", "v1.4.4")
        self.tag("For implementation tasks, use verify-change")
        self.assert_refused("--require-tag")
        self.git("tag", "-d", "v1.4.4")
        self.tag()
        self.data["repos/owner/project/git/ref/tags/v1.4.4"]["json"]["object"]["sha"] = "0" * 40
        self.assert_refused("--require-tag")

    def test_missing_target_and_target_setting_are_refused(self):
        path = self.repo / "SystemEQ for Mac.xcodeproj/project.pbxproj"
        original = path.read_text()
        for text in (original.replace("com.apple.product-type.application", "com.apple.product-type.tool", 1), original.replace("MARKETING_VERSION = 1.4.4;", "", 1)):
            path.write_text(text)
            self.commit()
            self.synchronize_ci()
            self.assert_refused()

    def test_pre_tag_check_refuses_existing_local_or_remote_tag(self):
        self.git("tag", "v1.4.4")
        self.assert_refused()
        self.git("tag", "-d", "v1.4.4")
        self.data["repos/owner/project/git/matching-refs/tags/v1.4.4"] = {"json": [{"ref": "refs/tags/v1.4.4"}]}
        self.assert_refused()

    def workflow_command(self, step):
        section = self.workflow.split(f"      - name: {step}\n", 1)[1].split("\n      - name:", 1)[0]
        return textwrap.dedent(section.split("        run: |\n", 1)[1])

    def workflow_check(self, **overrides):
        self.responses.write_text(json.dumps(self.data))
        output = self.home / "outputs"
        env = dict(self.env, GITHUB_REF_TYPE="tag", GITHUB_REF_NAME="v1.4.4", GITHUB_EVENT_NAME="push", GITHUB_SHA=self.sha, GITHUB_REPOSITORY="owner/project", GITHUB_OUTPUT=str(output), RUNNER_TEMP=str(self.home), INPUT_VERSION="")
        env.update(overrides)
        return subprocess.run(["bash", "-e", "-o", "pipefail", "-c", self.workflow_command("Check exact release commit, CI and metadata")], cwd=self.repo, env=env, capture_output=True, text=True, timeout=20)

    def test_workflow_preflight_publishes_only_validated_metadata(self):
        self.tag()
        result = self.workflow_check()
        self.assertEqual(result.returncode, 0, result.stderr)
        output = (self.home / "outputs").read_text()
        self.assertIn("version=1.4.4\n", output)
        self.assertIn("### Fixed\n- Fixture correction", output)
        self.assertNotIn("Prior fix", output)
        before = self.snapshot()
        self.data["repos/owner/project/actions/runs/10"]["json"]["conclusion"] = "failure"
        self.responses.write_text(json.dumps(self.data))
        result = subprocess.run(["bash", "-e", "-o", "pipefail", "-c", self.workflow_command("Recheck release eligibility before publication")], cwd=self.repo, env=dict(self.env, GITHUB_SHA=self.sha, GITHUB_REPOSITORY="owner/project", VERSION="1.4.4", RUNNER_TEMP=str(self.home)), capture_output=True, text=True, timeout=20)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(before, self.snapshot())

    def test_dispatch_branch_and_shell_sensitive_input_are_refused(self):
        for values in ({"GITHUB_REF_TYPE": "branch", "GITHUB_EVENT_NAME": "workflow_dispatch", "INPUT_VERSION": "1.4.4"}, {"GITHUB_EVENT_NAME": "workflow_dispatch", "INPUT_VERSION": "1.4.4; touch injected"}):
            before = self.snapshot()
            result = self.workflow_check(**values)
            self.assertNotEqual(result.returncode, 0, result.stdout)
            self.assertEqual(before, self.snapshot())
            self.assertFalse(self.calls.exists())


class ReleaseWorkflowCredentialTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="systemeq-workflow-tests-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.repo = self.root / "repo with spaces"
        (self.repo / "Scripts").mkdir(parents=True)
        (self.repo / "Scripts/prepare_signed_release.sh").write_text("#!/bin/bash\nexit 0\n")
        self.runner = self.root / "runner"
        self.runner.mkdir()
        self.output = self.root / "output"
        self.output.write_text("preserve\n")
        self.calls = self.root / "calls.jsonl"
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.workflow = (Path(__file__).resolve().parent.parent / ".github/workflows/release.yml").read_text()
        self.env = dict(os.environ, PATH=f"{self.bin}:/usr/bin:/bin", RUNNER_TEMP=str(self.runner), GITHUB_OUTPUT=str(self.output), CALLS=str(self.calls), CERTIFICATE_P12="Zml4dHVyZSBjZXJ0aWZpY2F0ZQ==", CERTIFICATE_PASSWORD="fixture-p12-password", SIGNING_IDENTITY="A" * 40, SIGNING_TEAM="ABCDE12345", NOTARY_APPLE_ID="fixture@example.invalid", NOTARY_PASSWORD="fixture-notary-password", VERSION="1.4.4")
        stub = r"""#!/usr/bin/python3
import json, os, sys
from pathlib import Path
args = sys.argv[1:]
name = Path(sys.argv[0]).name
with Path(os.environ['CALLS']).open('a') as stream:
    stream.write(json.dumps([name, *args]) + '\n')
mode = os.environ.get('MODE', '')
if name == 'security' and args == ['list-keychains', '-d', 'user']:
    if mode == 'search-fail':
        sys.exit(9)
    if mode == 'relative-search':
        print('"relative.keychain-db"')
        sys.exit(0)
    if mode == 'newline-search':
        print('"/fixture/broken\nkeychain-db"')
        sys.exit(0)
    print('' if mode == 'empty-search' else '\"/fixture/login.keychain-db\"')
    sys.exit(0)
failure = (mode == 'import' and args[0] == 'import') or (mode == 'store' and name == 'xcrun') or (mode == 'restore' and args[0] == 'list-keychains') or (mode == 'delete' and args[0] == 'delete-keychain')
if failure:
    print(' '.join(os.environ[key] for key in ('CERTIFICATE_PASSWORD', 'NOTARY_PASSWORD', 'SIGNING_IDENTITY')), file=sys.stderr)
    sys.exit(9)
if name == 'security' and args[0] == 'create-keychain':
    Path(args[-1]).write_bytes(b'fixture keychain')
if name == 'security' and args[0] == 'delete-keychain':
    Path(args[-1]).unlink()
"""
        for name in ("security", "xcrun"):
            path = self.bin / name
            path.write_text(stub)
            path.chmod(0o755)
        self.state = self.runner / "systemeq-keychain-state.json"
        self.unrelated = self.runner / "unrelated"
        self.unrelated.write_bytes(b"preserve user data")

    def command(self, step):
        section = self.workflow.split(f"      - name: {step}\n", 1)[1].split("\n      - name:", 1)[0]
        return textwrap.dedent(section.split("        run: |\n", 1)[1])

    def invoke(self, step, **values):
        return subprocess.run(["/bin/bash", "-e", "-o", "pipefail", "-c", self.command(step)], cwd=self.repo, env=dict(self.env, **values), capture_output=True, text=True, timeout=20)

    def setup_credentials(self, **values):
        return self.invoke("Configure temporary signing credentials", **values)

    def cleanup_credentials(self, **values):
        return self.invoke("Remove temporary signing credentials", **values)

    def test_setup_and_cleanup_restore_search_list_and_preserve_unrelated_data(self):
        result = self.setup_credentials()
        self.assertEqual(result.returncode, 0, result.stderr)
        state = json.loads(self.state.read_text())
        keychain = Path(state['keychain'])
        self.assertTrue(keychain.is_file())
        self.assertEqual(keychain.stat().st_mode & 0o777, 0o600)
        self.assertIn(f"keychain={keychain}\n", self.output.read_text())
        self.assertEqual(self.cleanup_credentials().returncode, 0)
        self.assertFalse(self.state.exists())
        self.assertFalse(Path(state['owned']).exists())
        calls = [json.loads(line) for line in self.calls.read_text().splitlines()]
        self.assertIn(['security', 'list-keychains', '-d', 'user', '-s', '/fixture/login.keychain-db'], calls)
        self.assertTrue(all('submit' not in call for call in calls))
        self.assertEqual(self.unrelated.read_bytes(), b"preserve user data")

    def test_invalid_secrets_and_search_fail_before_outputs_or_owned_state(self):
        for values in ({'CERTIFICATE_PASSWORD': ''}, {'SIGNING_IDENTITY': 'invalid'}, {'SIGNING_TEAM': 'bad'}, {'MODE': 'empty-search'}, {'MODE': 'search-fail'}, {'MODE': 'relative-search'}, {'MODE': 'newline-search'}):
            with self.subTest(values=values):
                result = self.setup_credentials(**values)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(self.state.exists())
                self.assertEqual(self.output.read_text(), 'preserve\n')
                self.assertEqual(list(self.runner.glob('systemeq-signing-*')), [])

    def test_partial_setup_failure_redacts_secrets_and_can_be_cleaned(self):
        for mode in ('import', 'store'):
            with self.subTest(mode=mode):
                result = self.setup_credentials(MODE=mode)
                self.assertNotEqual(result.returncode, 0)
                for key in ('CERTIFICATE_PASSWORD', 'NOTARY_PASSWORD', 'SIGNING_IDENTITY'):
                    self.assertNotIn(self.env[key], result.stderr + result.stdout)
                self.assertEqual(self.output.read_text(), 'preserve\n')
                self.assertTrue(self.state.exists())
                self.assertEqual(self.cleanup_credentials().returncode, 0)
                self.assertEqual(self.unrelated.read_bytes(), b"preserve user data")

    def test_cleanup_command_failures_keep_evidence_and_report_failure(self):
        for mode in ('restore', 'delete'):
            with self.subTest(mode=mode):
                self.assertEqual(self.setup_credentials().returncode, 0)
                state = json.loads(self.state.read_text())
                result = self.cleanup_credentials(MODE=mode)
                self.assertNotEqual(result.returncode, 0)
                self.assertTrue(self.state.exists())
                self.assertTrue(Path(state['owned']).is_dir())
                self.assertEqual(self.cleanup_credentials().returncode, 0)

    def test_cleanup_rejects_malformed_symlinked_or_unowned_state_without_calls(self):
        self.assertEqual(self.cleanup_credentials().returncode, 0)
        self.state.symlink_to(self.runner / 'missing')
        self.assertNotEqual(self.cleanup_credentials().returncode, 0)
        self.assertFalse(self.calls.exists())
        self.state.unlink()
        self.state.write_text('{}')
        self.assertNotEqual(self.cleanup_credentials().returncode, 0)
        self.assertFalse(self.calls.exists())
        self.state.unlink()
        self.assertEqual(self.setup_credentials().returncode, 0)
        state = json.loads(self.state.read_text())
        original = self.state.read_bytes()
        calls = self.calls.read_bytes()
        for field, value in [('owned', str(self.root)), ('keychain', str(self.unrelated)), ('search', []), ('search', 'invalid')]:
            changed = dict(state, **{field: value})
            self.state.write_text(json.dumps(changed))
            self.assertNotEqual(self.cleanup_credentials().returncode, 0)
            self.assertEqual(self.calls.read_bytes(), calls)
        self.state.write_bytes(original)
        keychain = Path(state['keychain'])
        keychain.unlink()
        keychain.symlink_to(self.unrelated)
        self.assertNotEqual(self.cleanup_credentials().returncode, 0)
        self.assertEqual(self.calls.read_bytes(), calls)
        self.assertEqual(self.unrelated.read_bytes(), b"preserve user data")
        keychain.unlink()
        self.assertEqual(self.cleanup_credentials().returncode, 0)

    def record_fixture(self, phase):
        run = self.repo / 'LocalArtifacts/SignedReleases/release-fixture'
        run.mkdir(parents=True, exist_ok=True)
        app = run / 'final/SystemEQ for Mac.app'
        app.mkdir(parents=True, exist_ok=True)
        package = run / 'final/SystemEQ.zip'
        package.write_bytes(b'fixture zip')
        import hashlib
        complete = {'version': '1.4.4', 'team': self.env['SIGNING_TEAM'], 'app': str(app.relative_to(run)), 'zip': str(package.relative_to(run)), 'zip_sha256': hashlib.sha256(package.read_bytes()).hexdigest()}
        (run / 'completed.json').write_text(json.dumps(complete))
        (run / 'manifest.json').write_text(json.dumps(complete))
        (self.repo / 'build').mkdir(exist_ok=True)
        (run / 'dmg').mkdir(exist_ok=True)
        dmg = run / 'dmg/SystemEQ.dmg'
        dmg.write_bytes(b'fixture dmg')
        dmg_complete = dict(complete, dmg=str(dmg.relative_to(run)), dmg_sha256=hashlib.sha256(dmg.read_bytes()).hexdigest())
        (run / 'dmg/completed.json').write_text(json.dumps(dmg_complete))
        record = {'phase': phase, 'run': str(run), 'manifest': str(run / 'manifest.json'), 'completed': str(run / ('dmg/completed.json' if phase == 'dmg' else 'completed.json'))}
        name = {'signed': 'signed', 'notarized': 'notarized', 'dmg': 'dmg'}[phase]
        path = self.runner / f'systemeq-{name}.json'
        path.write_text(json.dumps(record))
        self.env.update(SIGNED_RUN=str(run), NOTARY_KEYCHAIN='/fixture/keychain', NOTARIZED_ZIP=str(package))
        return run, path, record

    def test_record_consumers_accept_healthy_and_reject_bad_metadata_before_outputs(self):
        steps = {'signed': 'Build signed universal app', 'notarized': 'Notarize and staple app', 'dmg': 'Finalize signed distribution packages'}
        for phase, step in steps.items():
            with self.subTest(phase=phase):
                run, path, record = self.record_fixture(phase)
                result = self.invoke(step)
                self.assertEqual(result.returncode, 0, result.stderr)
                for malformed in ('', '{}', json.dumps(dict(record, phase='wrong'))):
                    path.write_text(malformed)
                    before = self.output.read_bytes()
                    self.assertNotEqual(self.invoke(step).returncode, 0)
                    self.assertEqual(self.output.read_bytes(), before)
                path.write_text(json.dumps(record))
                manifest = run / {'signed': 'manifest.json', 'notarized': 'completed.json', 'dmg': 'dmg/completed.json'}[phase]
                original = json.loads(manifest.read_text())
                for key, value in [('version', '9.9.9'), ('team', 'BADTEAM000'), *([] if phase == 'signed' else [('zip_sha256' if phase == 'notarized' else 'dmg_sha256', '0' * 64)])]:
                    manifest.write_text(json.dumps(dict(original, **{key: value})))
                    before = self.output.read_bytes()
                    self.assertNotEqual(self.invoke(step).returncode, 0)
                    self.assertEqual(self.output.read_bytes(), before)
                manifest.write_text(json.dumps(original))


if __name__ == "__main__":
    unittest.main()
