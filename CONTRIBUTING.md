# Contributing to SystemEQ for Mac

Thanks for your interest in improving SystemEQ. This is a small, focused
project — most contributions are welcome, but please read this before you
start so you do not waste effort.

## Ground rules

- **License:** SystemEQ is distributed under **GPLv3**. By contributing you
  agree your changes ship under the same license. Closed-source forks are
  not allowed.
- **No paid features.** The app is and will remain free. Donations are
  fine; paywalls, "pro" tiers, telemetry, or analytics will not be merged.
- **No Apple Developer ID requirement.** The project intentionally ships
  unsigned / ad-hoc signed. Do not introduce build steps that require a
  paid Apple Developer account, App Store entitlements, or notarization.

## Reporting issues

1. Search [existing issues](https://github.com/denzam/SystemEQ-for-Mac/issues) first.
2. Include: macOS version, Mac model (Apple Silicon / Intel), SystemEQ
   version, BlackHole version, exact steps to reproduce, and any console
   output (`Console.app` → filter `com.denzam.SystemEQ`).
3. For audio glitches, attach a 5–10 s recording or a description of the
   sample rate / buffer size in use.

## Development setup

- Xcode 16.2 or newer
- macOS 13 (Ventura) or newer
- BlackHole 2ch installed for runtime testing

```bash
git clone https://github.com/denzam/SystemEQ-for-Mac.git
cd "SystemEQ for Mac"
open "SystemEQ for Mac.xcodeproj"
```

There is no `Package.swift` — the project is a plain Xcode project.

## Coding conventions

Defined in [`AGENTS.md`](AGENTS.md). Highlights:

- Logging: `dlog(_:category:)` only — never `print`. **Never** log inside
  the audio render callback.
- Localization: `LocalizationManager.shared.text(for: .key)` — do not
  hardcode UI strings.
- Feature flags: check `FeatureRegistry` before adding a new feature.
- Section markers: `// MARK: - Name`.
- Performance markers: `// ⚡` for hot-path code, `// 🔧` for
  thread-safety-sensitive code.
- The audio render callback must remain RT-safe: no locks, no allocations,
  no Swift runtime calls that can block, no `dlog`.

`BiquadFilterVDSP` is the production filter (real vDSP, batch processing).
Do not replace it with the scalar `BiquadFilterChain` fallback.

`SPSCRingBuffer` is lock-free with C11 atomics. Do not change its size or
its memory ordering without a benchmark.

## Pull requests

1. Fork → branch (`feature/your-feature` or `fix/short-description`).
2. Keep PRs small and focused. One feature or one fix per PR.
3. Run SwiftLint and SwiftFormat locally (`./Scripts/code_quality_check.sh`).
4. Update `CHANGELOG.md` under an `## [Unreleased]` section.
5. If you change behaviour visible to users, update all three READMEs
   (`README.md`, `README.ua.md`, `README.it.md`).
6. Open the PR against `main`. Describe what changed and how you tested
   it.

## What is unlikely to be merged

- Telemetry, crash reporting, or any network call not strictly required by
  AutoEQ fetching.
- App Store / sandbox compatibility shims.
- Code obfuscation, licensing checks, or DRM.
- Large refactors without a prior issue discussing the motivation.

## Questions

Open a [Discussion](https://github.com/denzam/SystemEQ-for-Mac/discussions)
or an issue tagged `question`.
