# SystemEQ for Mac

**Free, open-source system-wide parametric equalizer for macOS 13+**

Tune every sound on your Mac — Spotify, YouTube, Apple Music, anything.
10/31-band parametric EQ with an 8,665-headphone AutoEQ database, hearing
calibration, room-tuning tools, and a real-time visualizer. No subscriptions,
no telemetry.

[![macOS](https://img.shields.io/badge/macOS-13%2B-blue)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange)](https://swift.org)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)
[![Download](https://img.shields.io/github/v/release/denzam/SystemEQ-for-Mac?label=download)](https://github.com/denzam/SystemEQ-for-Mac/releases/latest)
[![Website](https://img.shields.io/badge/website-denzam.github.io-black)](https://denzam.github.io/SystemEQ-for-Mac/)
[![XERJ Corpus Hub contributor](https://hub.xerj.org/contributors/denzam/badge.svg)](https://hub.xerj.org/contributors/denzam)

> 🇬🇧 English | 🇺🇦 [Українська](README.ua.md) | 🇮🇹 [Italiano](README.it.md)

![SystemEQ for Mac — main window](Docs/screenshots/01-main.jpeg)

## 📸 Screenshots

| Main Menu | AutoEQ Database | Calibration | Visualizer |
| :---: | :---: | :---: | :---: |
| [![Main menu](Docs/screenshots/01-main.jpeg)](Docs/screenshots/01-main.jpeg) | [![AutoEQ](Docs/screenshots/07-autoeq-library.png)](Docs/screenshots/07-autoeq-library.png) | [![Calibration](Docs/screenshots/02-calibration-mode.png)](Docs/screenshots/02-calibration-mode.png) | [![Visualizer](Docs/screenshots/15-visualizer-active.jpeg)](Docs/screenshots/15-visualizer-active.jpeg) |

| Subjective Room Tuning | Resonance Finder | Device-Aware Presets |
| :---: | :---: | :---: |
| [![Room Tuning](Docs/screenshots/04-room-tuning.png)](Docs/screenshots/04-room-tuning.png) | [![Resonance Finder](Docs/screenshots/05-resonance-sweep.png)](Docs/screenshots/05-resonance-sweep.png) | [![Settings](Docs/screenshots/10-settings-language.jpeg)](Docs/screenshots/10-settings-language.jpeg) |

## ✨ Features

### Core Features

- **10/31-band Parametric EQ** — Professional-grade audio processing with biquad filters
- **AutoEQ Database** — 8,665 headphone models, 8,850 presets (SQLite, 18 MB)
- **Real-time Visualization** — Spectrum, Waveform, Particles, Psychedelic
- **Calibration Module** — Hearing test + custom profiles + A/B comparison
- **Subjective Room Tuning** — Tune your room response by ear
- **Resonance Finder** — Sine sweep to identify boomy or ringing frequencies
- **Native System Audio Capture** — Process Tap on macOS 14.4+; BlackHole remains an automatic fallback
- **Preset Management** — Save, load, and organize your EQ settings
- **Auto-Switch Preset per Output** — Optionally re-apply the saved preset when you change physical output devices
- **Launch at Login** — Optional macOS login item
- **Menu Bar Mode** — Optionally hide the Dock icon while keeping the menu bar control
- **Multi-language** — English, Italian, Ukrainian

### Audio Engine

- **CoreAudioEngine** — Low-latency processing (~11ms Native, ~25ms BlackHole) via AudioUnit (AUHAL)
- **vDSP Biquad Filters** — Accelerate framework, 5-10× faster than scalar
- **Peak Meters** — Real-time audio level monitoring
- **Clipping Protection** — Automatic gain reduction and preamp control
- **Keyboard Volume** — Uses macOS volume control when the selected device supports it; SystemEQ does not intercept media keys

### AutoEQ Integration

- **SQLite Database** — Instant offline search (<10ms)
- **Offline SQLite + Network Fallback** — Instant local database search with GitHub fallback
- **ParametricEQ & GraphicEQ** — Full format support

## 🚀 Quick Start

### Requirements

- macOS 13.0 (Ventura) or later
- Apple Silicon or Intel Mac
- [BlackHole 2ch](https://github.com/ExistentialAudio/BlackHole) (optional fallback for macOS 13–14.3 or manual BlackHole mode)
- 4GB RAM (8GB recommended)

### Installation

#### ✅ Recommended: Homebrew — no manual Gatekeeper step

```bash
brew trust denzam/systemeq
brew install --cask denzam/systemeq/systemeq
```

The v1.4.5 release workflow requires Developer ID signing and notarization for
DMG and ZIP packages. Releases through v1.4.4 use ad-hoc signing; follow the
installation instructions for the version you download.

> **Why `brew trust`?** Since Homebrew 6.0, third-party taps must be trusted
> explicitly before Homebrew will load them, and there is no way for a tap
> owner to grant that on your behalf. Without it you get
> `Refusing to load cask ... from untrusted tap`. It is a one-time command per
> machine. On Homebrew 5 and older, skip it — the command does not exist there.

#### Option 2: Download DMG or ZIP

1. Download a DMG or ZIP from [Releases](https://github.com/denzam/SystemEQ-for-Mac/releases) and check that version’s signing and installation notes
2. Open the DMG and drag `SystemEQ for Mac.app` to `/Applications`, or unzip the ZIP and move the app there
3. For a Developer ID signed, notarized package, open the app normally and allow the requested audio permission; for older ad-hoc releases, follow their release-specific instructions
4. On macOS 14.4+, leave Audio Backend set to **Automatic**; install BlackHole if SystemEQ offers the fallback or you select BlackHole mode

Signing and notarization do not grant Microphone or System Audio Recording permission.
Local development builds may still use ad-hoc signing.

#### Option 3: Build from Source

```bash
git clone https://github.com/denzam/SystemEQ-for-Mac.git
cd "SystemEQ for Mac"
open "SystemEQ for Mac.xcodeproj"
# Press Cmd+R to build and run
```

### Updating

In Settings → **App Updates**, **Check for App Updates** checks GitHub for a
newer release. **Open GitHub Release** opens its download page; the current
updater does not install or restart the app.

For a Homebrew installation, run `brew upgrade --cask systemeq`. For a manual
installation, quit SystemEQ, download the new package, and replace the app in
`/Applications`. Moving from a version without an in-app installer requires
this manual update or Homebrew.

### Setup Guide

1. **Use Automatic routing** (recommended on macOS 14.4+):
   - Open SystemEQ → Settings → Audio Backend
   - Leave it set to **Automatic**
   - Select your speakers or headphones in Routing, then click **Enable EQ**
   - SystemEQ captures audio natively; do not change the macOS system output

2. **Use BlackHole only when needed** (macOS 13–14.3, fallback, or manual selection):
   - Install [BlackHole 2ch](https://existential.audio/blackhole/) and restart SystemEQ
   - In Routing, select BlackHole as input and your speakers/headphones as output
   - Set **BlackHole 2ch** as the macOS System Output, then click **Enable EQ**

3. **Apply EQ Preset**:
   - AutoEQ tab → Search your headphone model
   - Click "⚡ Quick Import"
   - Or manually adjust bands in the Equalizer tab

## 🛠️ Architecture

```text
macOS 14.4+: System Audio → Process Tap → vDSP Biquad EQ → Physical Output

Fallback:     System Audio → BlackHole 2ch → vDSP Biquad EQ → Physical Output
```

**No Multi-Output Device is needed.** Automatic routing uses the native macOS engine when available; BlackHole is retained for compatibility and fallback.

### Technical Details

- **CoreAudioEngine**: Low-level AUHAL dual I/O, lock-free ring buffer
- **BiquadFilterVDSP**: vDSP batch processing, 5-10× faster than scalar
- **SPSCRingBuffer**: Lock-free SPSC buffer with C11 atomics
- **EQDatabase**: SQLite, 18 MB, 8,665 headphone models

## 📁 Project Structure

```text
SystemEQ for Mac/
├── Audio/              # Core Audio processing
│   ├── CoreAudioEngine.swift
│   ├── AudioRouter.swift
│   ├── BiquadFilterVDSP.swift
│   ├── CalibrationEngine.swift
│   └── SPSCRingBuffer.swift
├── Data/               # Data models and database
│   ├── EQDatabase.swift
│   ├── AutoEQModels.swift
│   └── PresetPersistence.swift
├── Features/           # UI views
│   ├── EqualizerView.swift
│   ├── AutoEQView.swift
│   ├── CalibrationView.swift
│   ├── VisualizerView.swift
│   └── RoutingView.swift
├── DesignSystem/       # Design tokens and components
├── Resources/          # Assets and database
│   └── EQDatabase.db
└── Docs/               # Documentation
```

## 🎯 Usage

### Equalizer

- Adjust frequency bands with sliders
- Switch between 10-band and 31-band modes
- Save custom presets for quick recall
- Apply auto-preamp to prevent clipping

### AutoEQ Presets

1. Search for your headphone model (8,665 available)
2. Choose a preset (oratory1990, Crinacle, etc.)
3. Click "⚡ Quick Import"
4. Adjust bass boost if needed

### Calibration

1. Compare test frequencies against the fixed 1000 Hz reference
2. Adjust volume per frequency to match reference
3. Save the profile, open Profiles, and activate it
4. Use A/B comparison to test profiles

Profiles store 31 frequency adjustments. The active EQ mode determines which
frequencies are applied: 10-band mode uses matching frequencies, while 31-band
mode applies all 31 adjustments. Choose 31-band mode to use the full profile.

### Visualizer

- Choose from 4 styles: Spectrum, Waveform, Particles, Psychedelic
- Adjust intensity (0–100%)
- Real-time FFT at 60 FPS

### Room Tuning and Resonance Finder

- Use **Subjective Room Tuning** to tune your room response by ear
- Use **Resonance Finder** to sweep for boomy or ringing frequencies, then create a corrective notch filter

### Output-Specific Presets

In **Settings**, enable **Auto-Switch Preset per Output**. SystemEQ remembers
the preset applied on each physical output and re-applies it when you switch
outputs. You can also enable **Launch at Login** there.

## 🎚️ DAW Compatibility (Reaper, Logic, Ableton, etc.)

SystemEQ processes **system-wide audio output**. DAWs typically bypass the system output and talk directly to your audio interface — so EQ is **not applied** by default.

| Scenario | EQ applied? |
| --- | --- |
| Spotify, YouTube, Apple Music | ✅ Yes |
| DAW → System Output (manual config) | ✅ Yes |
| DAW → Audio Interface directly (typical) | ❌ No |
| DAW monitoring through Scarlett/Focusrite | ❌ No |

### How to use SystemEQ with your DAW

1. In your DAW, set **output device to BlackHole 2ch**
2. SystemEQ applies EQ and forwards audio to your physical output
3. To return to direct monitoring, set DAW output back to your interface

**Reaper:** Options → Preferences → Audio → Device → BlackHole 2ch

**Logic:** Preferences → Audio → Output Device → BlackHole 2ch

**Ableton:** Preferences → Audio → Output Device → BlackHole 2ch

> This adds ~10-20ms extra latency vs direct monitoring. This is an architectural limitation of routing through the BlackHole system driver.

## 📊 Project Status

SystemEQ ships its core EQ, routing, calibration, AutoEQ, output-specific preset, and visualizer features and is actively maintained.

## 🩺 Troubleshooting

### `Error: Refusing to load cask ... from untrusted tap`

Homebrew 6.0 will not load a third-party tap until you mark it as trusted, and a
tap owner cannot grant that for you. Run this once per Mac, then install or
upgrade as usual:

```bash
brew trust denzam/systemeq
brew upgrade --cask systemeq   # or: brew install --cask denzam/systemeq/systemeq
```

On Homebrew 5 and older the `trust` command does not exist — skip it.

### The app asks for microphone access again after an update

A first audio permission request is required even for a signed, notarized app.
Ad-hoc builds or a change of signing identity can cause another request; compatible
Developer ID signatures allow macOS to recognize updates as the same app.
See [Apple’s code identity explanation](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements).

### macOS says the app "cannot be opened"

Check the signing and installation notes for the version you downloaded.
Releases through v1.4.4 and local ad-hoc builds use a different signing policy
from the v1.4.5 Developer ID release workflow. For a signed, notarized package,
download it again from the official release page and report the exact macOS
message and app version if it is still blocked.

### No sound after setup

On macOS 14.4+, first choose **Automatic** in Settings → Audio Backend and enable EQ again. The system output should stay on your physical device. If Automatic falls back or cannot start, install BlackHole and follow the BlackHole setup below.

In **Routing**, select BlackHole as input and your speakers or headphones as
output. Set **BlackHole 2ch** as the macOS System Output, click **Enable EQ**,
and keep SystemEQ running.

### Sound is quieter after switching to BlackHole

macOS stores a separate volume level for each output device. After switching
to BlackHole, raise the system volume with the keyboard volume keys or in
macOS Sound settings.

## ⚠️ Security Notice

- This app is **not sandboxed** (incompatible with CoreAudio/AUHAL virtual audio devices)
- **No telemetry, analytics, or data collection** — all data stays on your Mac
- Only install from official [GitHub Releases](https://github.com/denzam/SystemEQ-for-Mac/releases)
- Distribution workflow requires Developer ID signing, notarization and Gatekeeper validation

### Security audits

The codebase is audited periodically with automated security scanning. Findings
and their resolution are tracked in [SECURITY.md](SECURITY.md); fixes ship in the
next release and are listed in [CHANGELOG.md](CHANGELOG.md).

Found something? See [SECURITY.md](SECURITY.md) for how to report it.

## 🤝 Contributing

1. Fork the project
2. Enable the pre-commit hook once per clone:
   ```bash
   git config core.hooksPath .githooks
   ```
   It formats staged Swift files and runs the same SwiftFormat and SwiftLint
   gates as CI, so a push does not fail on something catchable locally.
3. Create your feature branch (`git checkout -b feature/AmazingFeature`)
4. Commit your changes (`git commit -m 'Add AmazingFeature'`)
5. Push to the branch (`git push origin feature/AmazingFeature`)
6. Open a Pull Request

## 📄 License

**GNU General Public License v3.0** — see [LICENSE](LICENSE).

SystemEQ is free software. You may use, modify, and redistribute it, but
any redistributed version (including forks and derivative works) must
also be released under GPLv3 with full source code available. Closed-source
forks are not permitted; commercial distribution remains subject to GPLv3's
source-code and license obligations.

Third-party components and their licenses are listed in
[THIRDPARTY.md](THIRDPARTY.md).

## 🙏 Credits

- [AutoEQ](https://github.com/jaakkopasanen/AutoEq) by Jaakko Pasanen — EQ preset database
- [BlackHole](https://github.com/ExistentialAudio/BlackHole) by Existential Audio — Virtual audio driver
- [oratory1990](https://www.reddit.com/r/oratory1990/) — Headphone measurements and research

Also thanks to **Michel**, **Renato**, **David** and **Alberto** for their support and advice along the way.

## 💖 Support Development

- 🍺 [Buy Me a Coffee](https://buymeacoffee.com/denzam)
- 💝 [GitHub Sponsors](https://github.com/sponsors/denzam)

## 📧 Contact

- **GitHub**: [@denzam](https://github.com/denzam)
- **Issues / Questions**: [GitHub Issues](https://github.com/denzam/SystemEQ-for-Mac/issues)

---

**Made with ❤️ for the audio community**
