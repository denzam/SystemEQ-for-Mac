---
name: verify-change
description: Verifies code, scripts, documentation examples, and configuration changes before completion. Use after modifying files, before claiming a fix is complete, or before committing or releasing.
---

# Verify Change

Validate the actual changed scope, including auxiliary files that primary project CI may ignore.

## Workflow

1. Inspect `git status --short` and the final diff; exclude unrelated user changes from conclusions.
2. Run `git diff --check` and `git diff --cached --check` when staged changes exist.
3. Select checks for every changed file type:
   - Swift: targeted formatting/lint plus the smallest relevant build or test command; for changes in `Audio/`, DSP, or buffers, **always write or run targeted boundary/edge-case tests** (0, 1 sample, interpolation limits, buffer size mismatches) rather than relying on the general test suite alone; use the full project test command for releases or cross-cutting behavior.
   - Python: compile changed scripts with a temporary `PYTHONPYCACHEPREFIX`, run relevant tests, and execute every new or changed documented example literally.
   - JSON or plist: parse or lint with an appropriate local tool.
   - Markdown and agent instructions: verify referenced paths, commands, model names, and observable examples instead of checking prose alone.
4. Review the diff again after automated formatting or fixes.
5. Report what passed, what failed, and what still requires manual or end-to-end verification.

Do not claim runtime, visual, audio, or integration correctness from compilation alone. Do not commit, push, tag, publish, or alter external state unless the user explicitly authorized it.
