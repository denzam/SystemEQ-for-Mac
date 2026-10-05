---
name: independent-review
description: Automatically review the final state of substantive behavior, configuration, agent instructions or tooling changes before completion; also use for explicit audits. Skip cosmetic edits and ordinary prose. Use an isolated reviewer and evidence from relevant failure scenarios.
---

# Independent Review

## Trigger and scope

Run before completing substantive work without waiting for "check yourself". Review the final state once, then recheck affected areas after fixes. For explicit audits, use the requested scope. Ordinary prose, cosmetic changes and read-only advice do not need a separate reviewer; instructions that change agent behavior do.

Record the task contract, affected paths and immutable commit range or snapshot with hashes. Include relevant untracked new source without copying unrelated user files, secrets, installed apps or build caches. A passing result applies only to that snapshot; subsequent behavior changes require rechecking. When global and project variants of this skill are present, use this shared workflow and add the project-specific checks.

## Independent reviewer

The parent delegates once to a separate subagent with a fresh context when available. An invoked reviewer performs the review itself and must not delegate again unless the task explicitly requests multiple independent reviewers. Supply the task contract, raw snapshot/diff, applicable rules, minimal dependencies and permitted temporary fixtures. Do not supply author reasoning, expected findings or desired verdict. With collaboration tools, use `fork_turns="none"`; inherit the current model unless the user or an applicable rule specifies otherwise. A custom `independent_reviewer` role may be used when the runtime supports it; otherwise use a normal isolated subagent with this procedure.

The reviewer must not edit the working repository, global settings or live external state. Run failure injection in temporary copies with local stubs and bounded execution. Do not overwrite live configuration, run real sudo/mount/install/Reminders commands, change audio routing or create defects in production source. Check fixture state before and after dry-run tests; exclude only declared harness output. Remove only temporary paths owned by the harness. If permissions prevent a necessary test, record INCOMPLETE instead of weakening the sandbox. If delegation is unavailable, explicitly report that independence was not established.

## Evidence and failure checks

Trace actual callers and contracts. A suspicious text pattern is a candidate, not a confirmed defect. Judge handled expected errors in context; error suppression is a defect when it loses required diagnostics or turns a failure into success. Never infer professional quality from a green suite or reviewer confidence.

For substantive changes execute at least three distinct relevant negative scenarios, chosen from the affected risks rather than a fixed unrelated checklist:

- Missing dependency, failing external command, timeout or empty response: ensure the failure is observable and cannot produce a clean result.
- Malformed inputs, unknown flags, missing values and boundary conditions: ensure rejection or the documented safe behavior.
- Dry-run/check purity when such a mode exists: compare files, metadata and mocked mutation calls, not just one directory timestamp.
- Replacement, cleanup and privilege failure: verify preserved old data, rollback, failed-unmount handling and noninteractive behavior.
- DSP, concurrency or lifecycle changes: use relevant boundary, invalid-value, ordering or ownership scenarios and distinguish simulation from hardware proof.

Record actual commands, exit codes, relevant stdout/stderr and state assertions. Syntax checking is not a negative behavioral test. A failed assertion must reach a nonzero process exit; do not hide it behind `|| true`, pipelines or reporting-only wrappers. Inspect whether tests can fail on a known bad isolated fixture. When changing a scanner or review harness, include known defects, healthy controls, its own dependency/read/parse errors and a read-only check. Mutation checks belong only in temporary copies and do not certify a model from one caught defect.

## Completion contract

Report actionable findings by severity with exact clickable absolute file links (`/absolute/path:line`), trigger, observed effect and supporting evidence. Separate confirmed defects, hypotheses and out-of-scope pre-existing issues. Include relevant tests and unresolved verification gaps without dumping full logs.

- PASS: no confirmed defects in the declared scope, required checks executed and evidence supports the stated acceptance criteria. Never claim universal correctness.
- FAIL: a confirmed defect remains, regardless of unrelated green tests; also report blocked checks.
- INCOMPLETE: no confirmed defect establishes FAIL, but necessary checks, independence or evidence are missing. No success claim, commit or release justified by this review.

The parent must inspect the evidence, fix confirmed defects within the user's approved scope, rerun affected tests and obtain a fresh review of substantive fixes. Do not repeat full audits after cosmetic corrections or invent findings to satisfy an adversarial role. If an essential check remains blocked, state what is missing and stop the dependent completion claim; never silently downgrade the requirement.

## SystemEQ checks

Run `python3 Scripts/test_audit_antipatterns.py` when changing this skill's scanner. For candidate discovery run `python3 .agents/skills/independent-review/scripts/audit_antipatterns.py . --check`: exit 1 means candidates need contextual review; exit 2 means scanning was incomplete. Neither exit 0 nor a clean pattern report replaces independent review. The shell checks are lexical heuristics; generated commands and nested executable expansions, including unquoted heredocs, require source review even when no candidate is printed. Syntax validation does not execute or prove the script’s behavior.

For Audio/DSP/IPC changes inspect:

- Ring-buffer 0/1-frame cases, `avail == requiredFrames`, producer-window bounds, wrap and fractional interpolation; avoid reading a neighbour at zero phase or propagating `NaN * 0`.
- Unequal hardware block sizes and all filter dependencies when sample rate changes across Native and BlackHole paths; preserve active EQ mode, gains, preamp and boost.
- Callback allocations, locks, logging/runtime calls, atomic publication and reclamation, and cancellation/deinit ownership.
- Test isolation: use an isolated instance or complete state restoration, including failure exits; avoid mutating the production singleton or user defaults.

Builds and isolated DSP tests do not prove physical routing, permissions, sleep/wake, unplug recovery or real audio quality. State the unverified hardware paths explicitly.
