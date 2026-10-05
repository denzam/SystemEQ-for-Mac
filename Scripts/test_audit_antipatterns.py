#!/usr/bin/env python3

import argparse
import hashlib
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SCANNER = Path(__file__).resolve().parents[1] / ".agents/skills/independent-review/scripts/audit_antipatterns.py"


class AuditAntipatternTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="systemeq-antipattern-tests-", dir="/private/tmp")
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name)
        self.root = self.base / "repo"
        self.root.mkdir()
        self.environment = dict(os.environ)
        self.environment.update(PYTHONDONTWRITEBYTECODE="1", GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM="1")
        self.git("init", "--quiet")

    def git(self, *arguments):
        result = subprocess.run(
            ["git", "-C", str(self.root), *arguments],
            env=self.environment, capture_output=True, text=True, timeout=15,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        return result

    def write(self, relative, content, tracked=True):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        if isinstance(content, bytes):
            path.write_bytes(content)
        else:
            path.write_text(content, encoding="utf-8")
        if tracked:
            self.git("add", "--", relative)
        return path

    def scan(self, *arguments, root=None, environment=None, scanner=None):
        command = [sys.executable, str(scanner or SCANNER)]
        command.extend(arguments or (str(root or self.root), "--check"))
        result = subprocess.run(
            command, env=environment or self.environment, cwd=self.root,
            stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=15,
        )
        return result

    def assert_incomplete(self, result):
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        self.assertIn("INCOMPLETE", result.stderr)
        self.assertNotIn("No review candidates", result.stdout)

    def snapshot(self):
        return {
            str(path.relative_to(self.root)): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in self.root.rglob("*") if path.is_file()
        }

    def test_known_pipe_candidate_check(self):
        self.write("bad.sh", "false ||true\n")
        result = self.scan()
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("DEFENSIVE_THEATER_PIPE", result.stdout)

    def test_pipe_candidate_across_newline(self):
        self.write("bad.sh", "false ||\n    true\n")
        result = self.scan()
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("DEFENSIVE_THEATER_PIPE", result.stdout)

    def test_reporting_mode_is_explicitly_candidates(self):
        self.write("bad.sh", "false || true\n")
        result = self.scan(str(self.root))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Review candidates:", result.stdout)
        self.assertIn("not validated defects", result.stdout)

    def test_healthy_source(self):
        self.write("healthy.py", "value = 1\n")
        self.write("healthy.sh", "set -euo pipefail\nprintf '%s\\n' ok\nsudo -u root -n true\n")
        result = self.scan()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("Scanned 2", result.stdout)

    def test_comments_and_strings_do_not_create_candidates(self):
        self.write("strings.py", '# except Exception: pass\nvalue = "except: pass"\n')
        self.write("strings.sh", '# false || true\n# sudo anything\nprintf "%s\\n" "false || true" "sudo anything" "2>/dev/null"\necho \'local x=$(false)\'\n')
        result = self.scan()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_shell_heredoc_data_is_not_code(self):
        self.write("data.sh", "cat <<'EOF'\nsudo anything\nfalse || true\nEOF\n")
        result = self.scan()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_shell_here_string_is_not_a_heredoc(self):
        self.write("data.sh", 'read -r value <<< "sudo false || true"\n')
        result = self.scan()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_multiline_broad_and_bare_handlers(self):
        self.write("handlers.py", "try:\n    work()\nexcept (\n    Exception,\n    ValueError,\n):\n    pass\ntry:\n    work()\nexcept:\n    pass\n")
        result = self.scan()
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertEqual(result.stdout.count("EXCEPT_PASS_BROAD"), 2)

    def test_typed_empty_handler_requires_semantic_review(self):
        self.write("expected.py", "try:\n    work()\nexcept FileNotFoundError:\n    pass\n")
        result = self.scan()
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("EXCEPT_PASS_TYPED", result.stdout)

    def test_handled_exception_is_healthy(self):
        self.write("handled.py", "try:\n    work()\nexcept Exception:\n    raise\n")
        result = self.scan()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_local_substitution_unquoted_and_double_quoted(self):
        self.write("local.sh", 'local first=$(false)\nlocal second="$(false)"\nlocal literal=\'$(false)\'\n')
        result = self.scan()
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertEqual(result.stdout.count("LOCAL_MASKING"), 2)

    def test_local_backticks_versus_literal_backticks(self):
        self.write("local.sh", 'local first=`false`\nlocal second="`false`"\nlocal literal=\'`false`\'\n')
        result = self.scan()
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertEqual(result.stdout.count("LOCAL_MASKING"), 2)

    def test_status_control_is_contextual_candidate(self):
        self.write("conditional.sh", "if false 2>/dev/null; then\n    :\nfi\n")
        result = self.scan()
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("review status handling", result.stdout)

    def test_quoted_and_spaced_fd_arguments_are_not_stderr_redirects(self):
        self.write("stdout.sh", 'echo "2">/dev/null\necho 2 >/dev/null\n')
        result = self.scan()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_sudo_tty_guard_is_contextual_candidate(self):
        self.write("sudo.sh", "if [ -t 0 ]; then\n    sudo true\nfi\n")
        result = self.scan()
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("review surrounding TTY guard", result.stdout)

    def test_sudo_attached_values_do_not_enable_noninteractive(self):
        for options in ("-unobody", "-pEnterpassword", "-Dnothing", "--user=nobody"):
            with self.subTest(options=options):
                self.write("sudo.sh", f"sudo {options} true\n")
                result = self.scan()
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertIn("SUDO_HANG", result.stdout)

    def test_sudo_command_argument_is_not_a_sudo_option(self):
        self.write("sudo.sh", "sudo true -n\n")
        result = self.scan()
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("SUDO_HANG", result.stdout)

    def test_sudo_actual_noninteractive_option_after_attached_value(self):
        self.write("sudo.sh", "sudo -unobody -n true\nsudo -kn true\nsudo --user=nobody --non-interactive true\n")
        result = self.scan()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_missing_root(self):
        self.assert_incomplete(self.scan(str(self.base / "missing"), "--check"))

    def test_invalid_flag(self):
        self.write("healthy.py", "value = 1\n")
        result = self.scan(str(self.root), "--invalid-flag")
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        self.assertIn("unrecognized arguments", result.stderr)

    def test_abbreviated_flag_rejected(self):
        self.write("healthy.py", "value = 1\n")
        result = self.scan(str(self.root), "--chec")
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)

    def test_additional_root_rejected(self):
        self.write("healthy.py", "value = 1\n")
        result = self.scan(str(self.root), str(self.root), "--check")
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)

    def test_git_failure_has_no_walk_fallback(self):
        self.write("healthy.py", "value = 1\n")
        binary = self.base / "bin/git"
        binary.parent.mkdir()
        binary.write_text("#!/bin/sh\necho 'mock Git failure' >&2\nexit 73\n")
        binary.chmod(0o755)
        environment = dict(self.environment, PATH=str(binary.parent))
        result = self.scan(str(self.root), "--check", environment=environment)
        self.assert_incomplete(result)
        self.assertIn("73", result.stderr)

    def test_git_root_empty_or_relative_result(self):
        self.write("healthy.py", "value = 1\n")
        binary = self.base / "bin/git"
        binary.parent.mkdir()
        for output in ("\\n", "relative\\n", "\\n\\n"):
            with self.subTest(output=output):
                binary.write_text(f"#!/bin/sh\nprintf '{output}'\n")
                binary.chmod(0o755)
                self.assert_incomplete(self.scan(str(self.root), "--check", environment=dict(self.environment, PATH=str(binary.parent))))

    def test_missing_git_binary(self):
        self.write("healthy.py", "value = 1\n")
        binary_directory = self.base / "empty-bin"
        binary_directory.mkdir()
        self.assert_incomplete(self.scan(str(self.root), "--check", environment=dict(self.environment, PATH=str(binary_directory))))

    def test_missing_tracked_file(self):
        path = self.write("missing.sh", "set -e\n")
        path.unlink()
        self.assert_incomplete(self.scan())

    def test_unreadable_tracked_file(self):
        path = self.write("unreadable.py", "value = 1\n")
        path.chmod(0)
        self.assert_incomplete(self.scan())

    def test_symlink_escape(self):
        outside = self.base / "outside.sh"
        outside.write_text("set -e\n")
        (self.root / "escape.sh").symlink_to(outside)
        self.git("add", "--", "escape.sh")
        self.assert_incomplete(self.scan())

    def test_corrupt_python(self):
        self.write("corrupt.py", "def unfinished(\n")
        self.assert_incomplete(self.scan())

    def test_python_module_control_flow_is_invalid(self):
        for content in ("return 1\n", "continue\n"):
            with self.subTest(content=content):
                self.write("invalid.py", content)
                self.assert_incomplete(self.scan())

    def test_shell_missing_fi_and_unmatched_substitution(self):
        for content in ("if true; then\n    echo valid\n", "value=$(true\n"):
            with self.subTest(content=content):
                self.write("invalid.sh", content)
                self.assert_incomplete(self.scan())

    def test_missing_shell_validator(self):
        self.write("healthy.sh", "set -e\n")
        binary_directory = self.base / "bin"
        binary_directory.mkdir()
        (binary_directory / "git").symlink_to(shutil.which("git"))
        self.assert_incomplete(self.scan(str(self.root), "--check", environment=dict(self.environment, PATH=str(binary_directory))))

    def test_shell_validator_failure(self):
        self.write("healthy.sh", "set -e\n")
        binary = self.base / "bin/bash"
        binary.parent.mkdir()
        binary.write_text("#!/bin/sh\necho 'mock validator failure' >&2\nexit 75\n")
        binary.chmod(0o755)
        environment = dict(self.environment, PATH=str(binary.parent) + os.pathsep + self.environment["PATH"])
        result = self.scan(str(self.root), "--check", environment=environment)
        self.assert_incomplete(result)
        self.assertIn("75", result.stderr)

    def test_shell_validation_sanitizes_startup_environment(self):
        self.write("healthy.sh", "set -e\n")
        binary = self.base / "bin/bash"
        binary.parent.mkdir()
        binary.write_text('#!/bin/sh\nif [ "${BASH_ENV+x}" ] || [ "${ENV+x}" ] || [ "${ZDOTDIR+x}" ]; then exit 76; fi\nexit 0\n')
        binary.chmod(0o755)
        startup = self.base / "startup.sh"
        marker = self.base / "startup-executed"
        startup.write_text(f"echo changed > '{marker}'\n")
        environment = dict(self.environment, PATH=str(binary.parent) + os.pathsep + self.environment["PATH"], BASH_ENV=str(startup), ENV=str(startup), ZDOTDIR=str(self.base))
        result = self.scan(str(self.root), "--check", environment=environment)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(marker.exists())

    def test_zsh_syntax_validation(self):
        if not shutil.which("zsh"):
            self.skipTest("zsh is unavailable")
        self.write("healthy.zsh", '#!/bin/zsh\nfor item (one two) print -r -- "$item"\n')
        result = self.scan()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_corrupt_encoding(self):
        self.write("corrupt.sh", b"\xff\n")
        self.assert_incomplete(self.scan())

    def test_zero_applicable_files_is_incomplete(self):
        self.assert_incomplete(self.scan())

    def test_only_relevant_source_extensions(self):
        self.write("healthy.py", "value = 1\n")
        self.write("not_source.txt", "sudo true\nexcept: pass\n")
        self.write("also_not_source.swift", 'let value = "except: pass"\n')
        result = self.scan()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("Scanned 1", result.stdout)

    def test_untracked_sources_are_scanned(self):
        self.write("untracked.sh", "false ||true\n", tracked=False)
        result = self.scan()
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("untracked.sh", result.stdout)

    def test_ignore_standard_is_honored(self):
        self.write(".gitignore", "ignored.sh\n")
        self.write("healthy.py", "value = 1\n")
        self.write("ignored.sh", "sudo true\n", tracked=False)
        result = self.scan()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_newline_filename(self):
        self.write("odd\nname.sh", "false ||true\n")
        result = self.scan()
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("odd\\nname.sh", result.stdout)

    def test_check_before_or_after_root(self):
        self.write("bad.sh", "false ||true\n")
        before = self.scan("--check", str(self.root))
        after = self.scan(str(self.root), "--check")
        self.assertEqual(before.returncode, 1, before.stdout + before.stderr)
        self.assertEqual(after.returncode, 1, after.stdout + after.stderr)
        self.assertEqual(before.stdout, after.stdout)

    def test_same_basename_is_not_skipped(self):
        self.write("other/audit_antipatterns.py", "try:\n    work()\nexcept:\n    pass\n")
        result = self.scan()
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("other/audit_antipatterns.py", result.stdout)

    def test_known_hook_without_extension(self):
        self.write(".githooks/pre-commit", "#!/bin/bash\nfalse ||true\n")
        result = self.scan()
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn(".githooks/pre-commit", result.stdout)

    def test_check_does_not_mutate_file_contents(self):
        self.write("bad.sh", "false ||true\n")
        before = self.snapshot()
        result = self.scan()
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertEqual(self.snapshot(), before)

    def test_worktree_git_file_and_default_root(self):
        self.write("healthy.py", "value = 1\n")
        self.git("-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "-c", "core.hooksPath=/dev/null", "commit", "--quiet", "-m", "fixture")
        worktree = self.base / "worktree"
        self.git("worktree", "add", "--quiet", "--detach", str(worktree))
        self.assertTrue((worktree / ".git").is_file())
        result = self.scan(str(worktree), "--check")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        copied = worktree / ".agents/skills/independent-review/scripts/audit_antipatterns.py"
        copied.parent.mkdir(parents=True)
        shutil.copyfile(SCANNER, copied)
        result = self.scan("--check", scanner=copied)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("Scanned 1", result.stdout)


def main():
    global SCANNER
    parser = argparse.ArgumentParser(description="Isolated scanner regression tests")
    parser.add_argument("--scanner", type=Path, help="Alternate scanner for mutation/regression verification")
    arguments, remaining = parser.parse_known_args()
    if arguments.scanner:
        SCANNER = arguments.scanner.resolve(strict=True)
    unittest.main(argv=[sys.argv[0], *remaining])


if __name__ == "__main__":
    main()
