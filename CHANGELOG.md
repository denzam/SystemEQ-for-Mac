# Changelog

All notable changes to SystemEQ for Mac are documented in this file.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.4.1] — 2026-08-28

Small UI polish and documentation aligned with the native audio route.

### Fixed
- Main window height now follows its content, removing unused space below the feature list

### Changed
- Installation and setup guidance now describes Automatic native routing on macOS 14.4+ and BlackHole as its fallback

## [1.4.0] — 2026-08-26

Native system-audio capture, unified EQ controls, and safer output switching.

### Added
- A native Process Tap routing backend on macOS 14.4 and later; Automatic mode prefers it and falls back to BlackHole when unavailable
- A manual update checker in Settings that opens the latest GitHub release when a newer version is available
- A live limiter gain-reduction indicator for evaluating output gain without guessing when dynamics are being compressed

### Changed
- Output gain now supports up to +12 dB, with linked-stereo limiting at boosted levels and safety limiting for positive preamp gain
- Auto preamp uses the combined filter response instead of only the largest individual band gain
- EQ controls are consolidated in the AutoEQ window; manual band editing remains available without loading a preset
- AutoEQ favorites use a compact browser while keeping existing saved favorites compatible

### Fixed
- BlackHole routing uses a single effective volume stage, recovers unexpected virtual-device volume changes, and avoids quiet physical output after routing starts
- Audio routing no longer interrupts system streams while the native Process Tap starts
- Restored the selected 10/31-band mode correctly when the app launches
- Outputs without an assigned preset now receive a flat EQ with 0 dB preamp instead of keeping the previous device's curve
- Per-output presets are reapplied even when two devices use the same base preset with different settings; invalid saved mappings fall back to flat EQ
- Automatic native-to-BlackHole fallback no longer shows a stale manual-setup warning
- Restored manual EQ band editing after removing the redundant standalone Equalizer window

## [1.3.0] — 2026-08-16

Audio reliability, safer output control, and privacy-safe diagnostics.

### Added
- Output Boost from +0 to +3 dB, protected by a linked-stereo safety limiter to prevent clipping
- A diagnostic report export in Settings that contains only SystemEQ state and recent app events; it excludes audio, media, device names, identifiers, file paths, and raw macOS logs

### Changed
- SystemEQ now restores the exact last playback configuration — including manual band edits, preamp, and the active preset — after an EQ toggle or app relaunch

### Fixed
- Kept the physical output's volume when routing starts through BlackHole, preventing unexpectedly quiet audio after login launch or restart
- Preamp values now rebuild and affect the live vDSP filter chain
- Turning EQ off and on from the routing screen no longer loses the active preset
- Preserved the intended EQ state when startup routing temporarily fails because an output device is unavailable
- Audio meters show silence as −∞ dB instead of non-finite or implausibly low values

## [1.2.0] — 2026-08-09

Launch reliability overhaul and two community-requested features
([#30](https://github.com/denzam/SystemEQ-for-Mac/issues/30),
[#31](https://github.com/denzam/SystemEQ-for-Mac/issues/31)).

### Added
- Auto-switch preset per output device (opt-in): the preset applied on each output is remembered and re-applied when you switch outputs, and launch restore follows the connected output (#31)
- "Hide Dock Icon" setting: run the app from the menu bar only; the two icon toggles guard each other so the app always stays reachable (#30)
- The AutoEQ window now remembers the last applied preset of any origin — database presets included — and shows it on open without touching the running EQ

### Fixed
- "Launch at login" never actually registered a login item; the toggle now uses the system service, reflects the real registration status, and reverts when the system refuses
- The saved preset was not restored on launch in 31-band mode (band array rebuilt one run-loop turn too late)
- EQ state was not restored at all when the app auto-started at login without opening a window
- Opening the AutoEQ window could silently replace the active preset with a stale custom import or a flat all-zero EQ
- A failed startup restore (device not yet available, permission not yet granted) permanently disabled future restores
- Oversized gain arrays could crash the 10-band apply path
- Database update checks no longer report success without checking; buffer sizes follow the actual `MaximumFramesPerSlice` the audio units accept
- Running the test suite no longer erases the developer's saved preset

## [1.1.2] — 2026-07-26

Security audit follow-up. See [SECURITY.md](SECURITY.md) for the full audit
report, including findings accepted as known risk.

### Security
- Pinned all GitHub Actions to full commit SHAs so a retargeted version tag cannot alter the workflow that builds and publishes releases
- Audio render callbacks now validate the frame count supplied by CoreAudio against the preallocated buffer capacity instead of trusting it
- Imported `.txt` presets are bounded in size and filter count, and every gain and preamp value is checked for range before it reaches the audio engine

### Added
- `SECURITY.md` with the vulnerability reporting process, security model, and audit history

## [1.1.1] — 2026-07-25

Reliability, security, and release-readiness update.

### Fixed
- Prevented high idle CPU usage caused by app-wide UI updates from the peak meter
- Restored EQ routing safely after sleep/wake, output-device disconnects, and device replugging
- Preserved the real system output and original device sample rates when routing stops or the app quits
- Hardened ProjectM IPC against stale connections, descriptor reuse, partial writes, and cross-session responses
- Fixed FTS5 searches for headphone names containing punctuation
- Restored warnings and errors to Release-build logging

### Changed
- Updated BlackHole integration to 0.7.1 and made its update checker fail safely
- Added release tests and version verification to the GitHub Actions release workflow
- Standardized contributor instructions for any AI-assisted or manual workflow

## [1.1.0] — 2026-06-13

Preset persistence, app-wide tooltips, and a major visualizer overhaul.

### Added
- Imported `.txt` AutoEQ presets now persist across app and Mac restarts (stored as raw text + preamp) and can be saved to favorites — no need to re-import after a reboot
- App-wide native tooltips: hovering truncated text shows the full value after a short delay, without shifting any layout
- Visualizer quality picker (Low / Medium / High) that live-adjusts render resolution, plus a visible FPS counter in the status bar
- Full preset browser: every visualizer preset grouped by category with search and visualizer-specific favorites; picking a preset outside the current filter switches to "All" automatically

### Changed
- Visualizer "Auto" toggle now also stops timer-based preset switching when off, so a chosen preset stays put
- Heavy presets adaptively lower render resolution to hold a high framerate; presets that stay below 30 FPS for a couple of seconds are blacklisted and auto-skipped (only while Auto is on and Lock is off)

### Fixed
- Removed the redundant Show/Hide favorites button in AutoEQ (the bookmark counter is the single toggle)
- Visualizer preset list could come back empty: the large list response shared the audio IPC queue and overflowed the socket buffer — reads now run on a dedicated queue and both sides drain/write fully
- Quality changes are no longer queued behind render frames on the main runloop, so the picker responds immediately even on slow presets

## [1.0.7] — 2026-05-30

New AutoEQ import feature plus localization fixes.

### Added
- AutoEQ window now supports importing user-supplied `.txt` presets via a new "Import .txt" button. Auto-detects four formats: AutoEQ Parametric, AutoEQ GraphicEQ, AutoEQ FixedBandEQ, and EqualizerAPO (incl. Peak / Low Shelf / High Shelf / Low Pass / High Pass filters). Parametric bands are expanded to the current 10/31-band grid via the existing biquad-response math in `EQConverter`, so the audio hot path (`BiquadFilterVDSP`, `SPSCRingBuffer`, `CoreAudioEngine`) is unchanged
- Four new localized strings (EN/IT/UK) for the import button, tooltip, success and error messages

### Fixed
- AutoEQ window no longer kept stale English text in the index-status label ("Index: N (updated X weeks ago)") after switching language while the window was open. The status is now derived from raw `(count, timestamp)` state and reformatted on every redraw, so a language change is reflected immediately
- AutoEQ window now refreshes its localized labels live when the language is changed from the Settings window. `LocalizationManager` and `AudioEngine` are held via `@StateObject` instead of `@ObservedObject`, which guarantees the `@Published` subscription survives container-driven view rebuilds
- Switching band mode (10 ↔ 31) right after importing a custom parametric preset now re-maps and re-applies bands even when the cached `parsed10` and `parsed31` arrays share the same instance

### Changed
- CI: bumped `softprops/action-gh-release` from `v2` to `v3` to move the release workflow off the deprecated Node.js 20 runtime ahead of GitHub's mid-2026 cutoff

## [1.0.6] — 2026-05-16

Follow-up to v1.0.5.

### Fixed

- `LocalizationManager.setLanguage(_:)` no longer issues a redundant `queue.async { saveLanguage() }`. The `@Published currentLanguage` already persists via its `didSet`; the extra write could race ahead of the main-thread update on background-thread callers and store a stale value to `UserDefaults` (#21)

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
- Release workflow (`.github/workflows/release.yml`) copies the `dmg-assets/README - HOW TO OPEN.txt` and renders the background before calling `create-dmg`

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

[1.4.1]: https://github.com/denzam/SystemEQ-for-Mac/releases/tag/v1.4.1
[1.4.0]: https://github.com/denzam/SystemEQ-for-Mac/releases/tag/v1.4.0
[1.3.0]: https://github.com/denzam/SystemEQ-for-Mac/releases/tag/v1.3.0
[1.2.0]: https://github.com/denzam/SystemEQ-for-Mac/releases/tag/v1.2.0
[1.1.2]: https://github.com/denzam/SystemEQ-for-Mac/releases/tag/v1.1.2
[1.1.1]: https://github.com/denzam/SystemEQ-for-Mac/releases/tag/v1.1.1
[1.1.0]: https://github.com/denzam/SystemEQ-for-Mac/releases/tag/v1.1.0
[1.0.7]: https://github.com/denzam/SystemEQ-for-Mac/releases/tag/v1.0.7
[1.0.6]: https://github.com/denzam/SystemEQ-for-Mac/releases/tag/v1.0.6
[1.0.5]: https://github.com/denzam/SystemEQ-for-Mac/releases/tag/v1.0.5
[1.0.4]: https://github.com/denzam/SystemEQ-for-Mac/releases/tag/v1.0.4
[1.0.3]: https://github.com/denzam/SystemEQ-for-Mac/releases/tag/v1.0.3
[1.0.2]: https://github.com/denzam/SystemEQ-for-Mac/releases/tag/v1.0.2
[1.0.1]: https://github.com/denzam/SystemEQ-for-Mac/releases/tag/v1.0.1
[1.0.0]: https://github.com/denzam/SystemEQ-for-Mac/releases/tag/v1.0.0
