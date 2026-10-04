---
name: independent-review
description: Performs an evidence-based independent review of a completed diff or commit range. Triggered when the user asks "перевір себе" or requests an audit, avoiding unnecessary token usage on routine iterative steps.
---

# Independent Review

Review the implementation independently from the authoring rationale with a presumption of defectiveness («код містить баги, доки не доведено зворотне»).

## Method

- **Author Isolation:** When subagents or `/boost` are available, delegate the review to an isolated reviewer agent without supplying author rationale, expected findings, or defending the implementation.
- **Fail-Closed & Negative Verification:** Never rely solely on successful compilation or "all tests passed". The reviewer must formulate and execute concrete negative scenarios in the terminal.
- **Zero Defensive Theater:** Directly expose masked errors, silent fallbacks, or misdiagnosed failures.
- **Preserve Read-Only Audit:** Keep the review read-only unless the user separately asks for fixes.

## Review Checklists

### 1. Fail-Closed & Defensive Theater Checklist
Apply to all shell scripts, Python tools, CI workflows, and system interactions:
1. **Fail-Closed («порожньо != актуально»):** Network, CLI, API, or system command failures, timeouts, or empty responses must never be treated as success or a clean state.
2. **Defensive Theater Prohibition:**
   - Detect and flag `2>/dev/null || true`, `|| true`, or redirecting `2>/dev/null` without explicit `$?` checking.
   - Flag empty `except Exception: pass` or broad exception swallowing.
   - Detect exit code masking in shell scripts (e.g., `local var=$(cmd)` where `local` resets `$?` to 0).
   - Flag misleading diagnostics where real tool failure messages are hidden and replaced with assumptions.
3. **Dry-Run & Check Idempotency:**
   - Verify that `--dry-run`, `--check`, or default inspection/check modes perform strictly read-only actions.
   - They must never mutate files, caches, directories, download assets, or restart daemons.
4. **Data Safety & Atomicity:**
   - Forbid blind `rm -rf` on working or build directories before replacement staging or verified backup is complete.
5. **CLI Parsers & Non-Interactivity:**
   - Check argument parsing robustness: unexpected flags must be rejected (`exit != 0`), not silently ignored.
   - Check privileged commands: `sudo` must not be invoked without non-interactive guards (`sudo -n` or `[ -t 0 ]`) to prevent hanging in headless or background environments.

### 2. Critical Audio & Concurrency Checklist
When inspecting changes in `Audio/`, DSP, or IPC:
1. **Ring Buffer & Resampler Boundaries:**
   - Does linear interpolation read index `+ 1` when `avail == requiredFrames`?
   - Does it handle `fraction == 0` without reading uncommitted producer slots or multiplying `(next - cur) * 0.0` (IEEE 754 `NaN` propagation: `(NaN - cur) * 0.0 == NaN`)?
2. **Hardware & Buffer Mismatches:**
   - Never abort setup (`return` / `abort`) purely due to mismatched input and output buffer frame sizes (e.g. AirPods, USB DACs). Ring buffers must adapt.
3. **Cascade / Dependent State:**
   - When `sampleRate` or device configuration changes, are ALL dependent filters rebuilt (both main graphic/parametric EQ and room correction notch filters) across all audio backends (Native and AUHAL/BlackHole)?
4. **Lifecycle & Deallocations:**
   - Are heap buffers deallocated both in timer cancel handlers and in `deinit` (double-free hazard)? Are singletons assumed immortal?
5. **Real-Time Constraints:**
   - Absolute real-time safety: no locks, heap allocations, Objective-C/Swift runtime calls, or logging in render callbacks (`// ⚡`).

## Mandatory Negative Terminal Tests

For every substantial review or audit, the reviewer **must execute at least 3 real negative scenarios** in the terminal:
1. Broken environment or missing dependency (e.g., missing tool in `$PATH`).
2. Corrupted input, malformed configuration, or missing mandatory arguments.
3. Dry-run / check mode state-mutation verification.

Record the literal commands executed, stdout/stderr snippets, and actual exit codes.

## Output Format & Verdict

Report findings in a standardized structure:
1. **Defects Table:**
   | Level | Category | File & Lines | Description |
   - Severity levels: **[Critical]** (audio dropouts, data corruption, crashes), **[High]** (silent failure masking, defensive theater, broken CLI contracts), **[Medium]** (non-interactive hangs, incomplete resource cleanup, dry-run side-effects), **[Low]** (minor argument handling, missing timeouts).
   - Use exact clickable file links (`file:///absolute/path#L10-L20`).
2. **Tested Negative Scenarios:** literal terminal logs and exit codes.
3. **Final Verdict:** Strictly **PASS** or **FAIL**.
