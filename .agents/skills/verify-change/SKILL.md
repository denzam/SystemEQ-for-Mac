---
name: verify-change
description: Verifies code, scripts, documentation examples, and configuration changes before completion. Triggered on any modifications to code, scripts, or configurations; do not run on pure read-only questions or prose-only answers.
---

# Verify Change

Validate the actual changed scope, including auxiliary files that primary project CI may ignore.

## When to Run (Triggers)
- **Always run** after editing, creating, or deleting code, shell scripts, configurations, or runnable examples.
- **Do not run** for purely advisory answers, documentation lookups, or read-only analysis without filesystem modifications.

## Workflow

1. Inspect `git status --short` (or directory changes if outside git) and the final diff; exclude unrelated user changes from conclusions.
2. Run `git diff --check` and `git diff --cached --check` when staged changes exist in a git repository.
3. Select checks for every changed file type:
   - **Shell / Zsh / Bash scripts:**
     - Syntax validation: `zsh -n <file>` or `bash -n <file>`. Run `shellcheck` when available.
     - Argument parsing: test positional argument handling (`shift`), empty/missing parameter values, and unknown flags.
     - Return code preservation: ensure `local var; var=$(cmd)` is used instead of `local var=$(cmd)` so `$?` is not swallowed.
     - Fail-Closed validation: ensure network/CLI command failures (e.g. `brew info`, `npm view`, `pip list`) do not silently evaluate to empty strings and trigger false-success branches.
     - Defensive theater ban: disallow unhandled `cmd 2>/dev/null || true` and empty exception blocks that swallow failures without inspecting `$?`.
     - Dry-run purity: verify that `--dry-run` / `--check` flags execute zero system mutations (no package updates, no cache cleanups, no flush/restart commands).
     - Atomic filesystem changes: ensure file/app replacements stage new assets first and never delete targets prior to verified copying.
     - Non-interactive safety: ensure automated flags (`-y` / `--yes`) fail immediately on missing privileges rather than blocking on interactive prompts (`sudo -v`).
   - **Swift:** targeted formatting/lint plus the smallest relevant build or test command; for Audio/DSP/buffers, use targeted 0/1-frame, interpolation/window and unequal-block edge tests; use the full project test command for releases or cross-cutting behavior.
   - **Python:** compile changed scripts with a temporary `PYTHONPYCACHEPREFIX`, run relevant tests, and execute every new or changed documented example literally. Verify absence of empty `except: pass` blocks.
   - **JSON or plist:** parse or lint with an appropriate local tool (e.g. `plutil -lint`, `python3 -m json.tool`).
   - **Markdown and agent instructions:** verify referenced paths, commands, model names, and observable examples instead of checking prose alone.
4. Review the diff again after automated formatting or fixes.
5. For substantive behavior, configuration or agent-workflow changes, automatically apply `independent-review` to the final snapshot before claiming completion; do not ask the user whether to verify. After fixing findings, rerun affected checks and review substantive fixes. If global and project variants exist, apply the shared workflow plus the project-specific checks.
6. Preserve actual exit codes and distinguish failed checks from blocked or skipped checks. Inspect assertions and state comparisons, not test counts or scanner prose. Use at least three relevant negative scenarios for substantive changes; run potentially mutating scenarios in temporary fixtures with stubs. For review tooling include healthy controls, known defective fixtures and scanner/harness failure paths; verify that the checks reject the defective versions.
7. For instruction or skill changes validate frontmatter, referenced commands and paths, consistent triggers, scope and approval boundaries. Run an isolated realistic forward test when the procedure changes agent behavior; distinguish deterministic tool tests from observed agent behavior and from future reliability.
8. Report the checked snapshot, what passed, what failed and what remains unverified. Missing required evidence is INCOMPLETE, not PASS.

Do not claim runtime, visual, audio, or integration correctness from compilation alone. Do not commit, push, tag, publish, or alter external state unless the user explicitly authorized it.
