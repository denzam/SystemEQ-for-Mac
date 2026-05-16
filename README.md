# SystemEQ for Mac

**Professional system-wide equalizer for macOS 13+**

[![macOS](https://img.shields.io/badge/macOS-13%2B-blue)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange)](https://swift.org)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

> 🇬🇧 English | 🇺🇦 [Українська](README.ua.md) | 🇮🇹 [Italiano](README.it.md)

## ✨ Features

### Core Features

- **10/31-band Parametric EQ** — Professional-grade audio processing with biquad filters
- **AutoEQ Database** — 8,665 headphone models, 8,850 presets (SQLite, 18 MB)
- **Real-time Visualization** — Spectrum, Waveform, Particles, Psychedelic
- **Calibration Module** — Hearing test + custom profiles + A/B comparison
- **BlackHole Integration** — System-wide audio routing with automated Setup Assistant
- **Preset Management** — Save, load, and organize your EQ settings
- **Multi-language** — English, Italian, Ukrainian

### Audio Engine

- **CoreAudioEngine** — Low-latency processing (~5-10ms) via AudioUnit (AUHAL)
- **vDSP Biquad Filters** — Accelerate framework, 5-10× faster than scalar
- **Peak Meters** — Real-time audio level monitoring
- **Clipping Protection** — Automatic gain reduction and preamp control
- **Media Key Support** — Volume control via keyboard shortcuts

### AutoEQ Integration

- **SQLite Database** — Instant offline search (<10ms)
- **4-tier Fallback** — Python server → Database → Local files → GitHub
- **ParametricEQ & GraphicEQ** — Full format support

## 🚀 Quick Start

### Requirements

- macOS 13.0 (Ventura) or later
- Apple Silicon (M1/M2/M3) or Intel Mac
- [BlackHole 2ch](https://github.com/ExistentialAudio/BlackHole) (free virtual audio driver)
- 4GB RAM (8GB recommended)

### Installation

#### Option 1: Homebrew (easiest — bypasses Gatekeeper automatically)

```bash
brew install --cask denzam/systemeq/systemeq
```

The Cask removes the quarantine attribute on install, so the app opens
without a Gatekeeper prompt.

#### Option 2: Download DMG

1. Download the latest `.dmg` or `.zip` from [Releases](https://github.com/denzam/SystemEQ-for-Mac/releases)
2. Open the DMG and drag `SystemEQ for Mac.app` to `/Applications`
3. **First launch (one of):**
   - **Right-click the app → Open → Open** in the confirmation dialog, or
   - Try to launch, then open **System Settings → Privacy & Security → Open Anyway**, or
   - From Terminal:
     ```bash
     xattr -dr com.apple.quarantine "/Applications/SystemEQ for Mac.app"
     ```
4. Follow the **Setup Assistant** to install BlackHole

> The app is **ad-hoc signed** (free, self-signed) — not notarized with an
> Apple Developer ID. Gatekeeper therefore shows a warning on first launch.
> This is intentional: SystemEQ stays free and does not require the paid
> Apple Developer Program. The Gatekeeper steps above are one-time only.

#### Option 3: Build from Source

```bash
git clone https://github.com/denzam/SystemEQ-for-Mac.git
cd "SystemEQ for Mac"
open "SystemEQ for Mac.xcodeproj"
# Press Cmd+R to build and run
```

### Setup Guide

1. **Install BlackHole** (automated via Setup Assistant):
   - Download from [BlackHole website](https://existential.audio/blackhole/)
   - Install 2-channel version
   - Restart SystemEQ after installation

2. **Configure Audio Routing**:
   - Open SystemEQ → Routing tab
   - Select BlackHole as input, your speakers/headphones as output
   - Set System Output to BlackHole in macOS Sound Settings

3. **Apply EQ Preset**:
   - AutoEQ tab → Search your headphone model
   - Click "⚡ Quick Import"
   - Or manually adjust bands in the Equalizer tab

## 🛠️ Architecture

```text
System Output → BlackHole 2ch
                     ↓
              CoreAudioEngine (input)
                     ↓
           vDSP Biquad EQ Processing
                     ↓
              CoreAudioEngine (output)
                     ↓
         Physical Speakers/Headphones
```

**No Multi-Output Device needed.** CoreAudioEngine bridges BlackHole and your physical output directly.

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

1. Run hearing test (31 frequencies)
2. Adjust volume per frequency to match reference
3. Save profile for automatic application
4. Use A/B comparison to test profiles

### Visualizer

- Choose from 4 styles: Spectrum, Waveform, Particles, Psychedelic
- Adjust intensity (0–100%)
- Real-time FFT at 60 FPS

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

> This adds ~10-20ms extra latency vs direct monitoring. Architectural limitation of BlackHole (system-level driver). A future HAL Audio Plugin would solve this but requires a paid Apple Developer account.

## 📊 Project Status

- ✅ Phase 1: Core EQ + BlackHole routing
- ✅ Phase 2: Calibration + Visualizer
- ✅ Phase 3: AutoEQ database integration (8,665 models)
- ⏭️ Phase 4: HAL plugin (requires paid Apple Developer account)
- ⏭️ Phase 5: Liquid Glass visual polish

## ⚠️ Security Notice

- This app is **not sandboxed** (incompatible with CoreAudio/AUHAL virtual audio devices)
- **No telemetry, analytics, or data collection** — all data stays on your Mac
- Only install from official [GitHub Releases](https://github.com/denzam/SystemEQ-for-Mac/releases)
- Ad-hoc signed — right-click → Open on first launch to bypass Gatekeeper

## 🤝 Contributing

1. Fork the project
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## 📄 License

**GNU General Public License v3.0** — see [LICENSE](LICENSE).

SystemEQ is free software. You may use, modify, and redistribute it, but
any redistributed version (including forks and derivative works) must
also be released under GPLv3 with full source code available. Closed-source
or paid commercial forks are not permitted.

Third-party components and their licenses are listed in
[THIRDPARTY.md](THIRDPARTY.md).

## 🙏 Credits

- [AutoEQ](https://github.com/jaakkopasanen/AutoEq) by Jaakko Pasanen — EQ preset database
- [BlackHole](https://github.com/ExistentialAudio/BlackHole) by Existential Audio — Virtual audio driver
- [oratory1990](https://www.reddit.com/r/oratory1990/) — Headphone measurements and research

## 💖 Support Development

- ☕ [Ko-fi](https://ko-fi.com/denzam)
- 🍺 [Buy Me a Coffee](https://buymeacoffee.com/denzam)
- 💝 [GitHub Sponsors](https://github.com/sponsors/denzam)

## 📧 Contact

- **GitHub**: [@denzam](https://github.com/denzam)
- **Issues / Questions**: [GitHub Issues](https://github.com/denzam/SystemEQ-for-Mac/issues)

---

**Made with ❤️ for the audio community**
