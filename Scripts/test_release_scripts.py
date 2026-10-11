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


if __name__ == "__main__":
    unittest.main()
