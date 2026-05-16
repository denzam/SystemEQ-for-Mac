# Changelog

All notable changes to SystemEQ for Mac are documented in this file.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.1] — 2026-05-16

Installer UX improvements. No application code changes.

### Added
- DMG ships with a custom background image showing the drag-to-Applications arrow and Gatekeeper bypass instructions
- `README - HOW TO OPEN.txt` bundled inside the DMG window (English, Italian, Ukrainian) with first-launch steps and Privacy & Security guidance
- `dmg-assets/generate-background.swift` generator script invoked from the release workflow

### Changed
- Release workflow (`.github/workflows/release.yml`) copies the README and renders the background before calling `create-dmg`

## [1.0.0] — 2026-05-10

First public release.

### Added
- 10/31-band parametric equalizer with `BiquadFilterVDSP` (vDSP_biquad fast path)
- AutoEQ database integration: 8 665 headphone models, 8 850 presets (SQLite, 18 MB)
- Calibration module: hearing test, custom profiles, A/B comparison
- BlackHole 2ch integration with automated Setup Assistant
- Real-time visualizer: Spectrum, Waveform, Particles, Psychedelic (ProjectM helper)
- Multi-language UI: English, Italian, Ukrainian
- AppKit `NSStatusItem` menu bar controller
- GitHub Actions release workflow producing unsigned `.dmg` and `.zip`
- Homebrew Cask formula with automatic quarantine flag removal

### Changed
- Audio engine: real `vDSP_biquad` replaces scalar implementation (~29× faster callback)
- Filter swap is lock-free via `std::atomic<Filter*>` exchange
- `SPSCRingBuffer`, `BiquadFilterVDSP`, `PeakMeter` migrated to C11 atomics
- `ProjectMHelper` / `ProjectMHelperClient` migrated off deprecated `OSAtomic`
- Welcome window placement now uses the active `NSScreen`, not `NSScreen.main`
- Idle CPU usage reduced from ~30 % to ~16 % after switching to `NSStatusItem`

### Fixed
- Audio callback overload caused by debouncing + lock-free filter swap
- Visualizer freeze on fullscreen toggle (Metal configuration)
- Buffer-size mismatch between input and output AUHAL units
- Real-time thread policy now applied to the audio callback thread

[1.0.1]: https://github.com/denzam/SystemEQ-for-Mac/releases/tag/v1.0.1
[1.0.0]: https://github.com/denzam/SystemEQ-for-Mac/releases/tag/v1.0.0
