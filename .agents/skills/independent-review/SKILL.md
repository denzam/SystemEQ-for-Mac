---
name: independent-review
description: Performs an evidence-based independent review of a completed diff or commit range. Triggered when the user asks "перевір себе" or requests an audit, avoiding unnecessary token usage on routine iterative steps.
---

# Independent Review

Review the implementation independently from the authoring rationale.

## Method

- Start from the immutable commit range or current diff and applicable project rules.
- When subagents or `/boost` are available, give the reviewer the task, raw diff, and necessary context without supplying expected findings or defending the implementation.
- Check correctness, edge cases, regressions, scope containment, platform assumptions, and whether validation covers every changed file type.
- Reproduce important examples and inspect test commands rather than trusting success claims or step names.
- Keep the review read-only unless the user separately asks for fixes.

## Critical Audio & Concurrency Checklist

When inspecting changes in `Audio/`, DSP, or IPC:
1. **Ring Buffer & Resampler Boundaries:** Does linear interpolation read index `+ 1` when `avail == requiredFrames`? Does it handle `fraction == 0` without reading uncommitted producer slots? Does it propagate `NaN` (`NaN * 0.0 == NaN`)?
2. **Hardware & Buffer Mismatches:** Does the code abort setup (`return`) if input and output buffer frame sizes differ? Devices like AirPods or USB DACs often reject requested buffer sizes — ring buffers must tolerate mismatched block sizes.
3. **Cascade / Dependent State:** When `sampleRate` or device configuration changes, are all filters rebuilt (both main EQ and room correction notch filters)?
4. **Lifecycle & Deallocations:** Are heap buffers deallocated both in timer cancel handlers and in `deinit` (double-free hazard)? Are singletons assumed immortal?
5. **Real-time constraints:** No locks, allocations, or logging in render callbacks (`// ⚡`).

Report actionable findings first, ordered by severity, with exact file and line evidence. If there are no findings, say so and list residual risks or manual verification that remains.
