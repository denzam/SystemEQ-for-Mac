# Changelog

All notable changes to SystemEQ for Mac are documented in this file.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.5] — 2026-05-16

Critical hang fix and a rendering regression in AutoEQ.

### Fixed

- App froze on the main thread when switching language after opening and closing the Visualizer. `LocalizationManager.setLanguage(_:)` no longer dispatches the `@Published` write through a `queue.async(.barrier)` that could deadlock against SwiftUI layout-time reads of `localizedString(for:)`; the getter is now lock-free and the save runs on a background queue without a barrier
- AutoEQ window labels ("Type a model name to search", "Band Mode", "Favorites", "Mapped Preview") rendered upside-down after a language change. The animated `blur(radius:)` cycle in `ViewBlurModifier` left CALayer transforms in an inconsistent state for the affected Text views; the modifier is now a no-op

## [1.0.4] — 2026-05-16

Robustness improvements and Code Quality cleanup.

### Changed
- Repository-wide `swiftformat` pass to clear pre-existing violations and unblock the Code Quality CI workflow (#12)

### Fixed
- Preset archive root selection now requires the candidate entry to be a directory and short-circuits on filename, so a stray `README` / `LICENSE` at the archive top level cannot be picked as the presets root (#11, #12)

## [1.0.3] — 2026-05-16

Performance follow-up to v1.0.2.

### Changed
- `ProjectMHelper` scans ~9,800 preset files on a `.userInitiated` queue instead of the main thread, eliminating the UI hang seen on first run (#8)
- Preset archive extraction filters out macOS-generated metadata folders (`__MACOSX`, dotfiles) when locating the content root (#8)

## [1.0.2] — 2026-05-16

Bug-fix release.

### Fixed
- Visualizer launched with `0 presets` because `~/Library/Application Support/SystemEQ/presets/` was never provisioned by the installer or the Cask — only projectM's idle preset rendered and the category picker was empty. `ProjectMHelper` now downloads `presets-cream-of-the-crop` on first run when the directory is empty, then populates the playlist without a restart (#5)

## [1.0.1] — 2026-05-16

Installer UX improvements. No application code changes.

### Added
- DMG ships with a custom background image showing the drag-to-Applications arrow and Gatekeeper bypass instructions
- `README - HOW TO OPEN.txt` bundled inside the DMG window (English, Italian, Ukrainian) with first-launch steps and Privacy & Security guidance
- `dmg-assets/generate-background.swift` generator script invoked from the release workflow

### Changed
- Release workflow (`.github/workflows/release.yml`) copies the `README - HOW TO OPEN.txt` and renders the background before calling `create-dmg`

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
