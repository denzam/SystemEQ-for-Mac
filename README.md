# SystemEQ for Mac

**Professional system-wide equalizer for macOS 13+**

[![macOS](https://img.shields.io/badge/macOS-13%2B-blue)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange)](https://swift.org)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)

> 🇺🇦 [Українська версія](README.ua.md) | 🇬🇧 English

## ✨ Features

### Core Features (✅ Complete)
- **10/31-band Parametric EQ** — Professional-grade audio processing with biquad filters
- **AutoEQ Database** — 2,347 headphone models, 8,850 presets (SQLite, 17 MB)
- **Real-time Visualization** — 4 styles: Spectrum, Waveform, Particles, Psychedelic
- **Calibration Module** — Hearing test + custom profiles + A/B comparison
- **BlackHole Integration** — System-wide audio routing with automated Setup Assistant
- **Preset Management** — Save, load, and organize your EQ settings
- **Multi-language** — English, Italian, Ukrainian

### Audio Engine
- **CoreAudioEngine** — Low-latency processing (~5-10ms) via AudioUnit (AUHAL)
- **Biquad Filters** — Direct Form II Transposed implementation
- **Peak Meters** — Real-time audio level monitoring (60 FPS)
- **Clipping Protection** — Automatic gain reduction and preamp control
- **Media Key Support** — Volume control via keyboard shortcuts

### AutoEQ Integration
- **Python Server** — JM-1 target curve calculation (optional)
- **SQLite Database** — Instant offline search (<10ms)
- **4-tier Fallback** — Python → Database → Local files → GitHub
- **ParametricEQ.txt & GraphicEQ** — Full format support

## 🚀 Quick Start

### Requirements
- macOS 13.0 (Ventura) or later
- Apple Silicon (M1/M2/M3) or Intel Mac
- [BlackHole 2ch](https://github.com/ExistentialAudio/BlackHole) (free virtual audio driver)
- 4GB RAM (8GB recommended)

### Installation

#### Option 1: Download Release (Recommended)
1. Download latest release from [Releases](https://github.com/denyszamorniak/SystemEQ-for-Mac/releases)
2. Open the `.dmg` file
3. Drag `SystemEQ for Mac.app` to Applications
4. Launch the app
5. Follow the **Setup Assistant** to install BlackHole
6. Enjoy system-wide EQ! 🎉

#### Option 2: Build from Source
```bash
git clone https://github.com/denyszamorniak/SystemEQ-for-Mac.git
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
   - Select BlackHole as input device
   - Select your speakers/headphones as output device
   - Set System Output to BlackHole in macOS Sound Settings

3. **Apply EQ Preset**:
   - AutoEQ tab → Search your headphone model
   - Click "⚡ Quick Import" for instant preset load
   - Or manually adjust 10/31 bands in Equalizer tab

See [Docs/Onboarding.md](Docs/Onboarding.md) for detailed instructions.

## 📊 Project Status

**MVP Complete!** ✅ (December 2025)

- ✅ Phase 1: Core EQ + BlackHole routing
- ✅ Phase 2: Calibration + Visualizer
- ✅ Phase 3: AutoEQ database integration
- ⏭️ Phase 4: HAL plugin (requires paid Apple Developer account)
- ⏭️ Phase 5: Visual polish (Liquid Glass design)

## 🛠️ Architecture

```
System Output → BlackHole 2ch
                     ↓
              CoreAudioEngine (input)
                     ↓
              Biquad EQ Processing
                     ↓
              CoreAudioEngine (output)
                     ↓
              Physical Speakers/Headphones
```

**No Multi-Output Device needed!** CoreAudioEngine acts as the bridge between BlackHole and your physical output.

### Technical Details

- **CoreAudioEngine**: Low-level processing via AudioUnit (AUHAL)
- **BiquadFilterChain**: DSP filter chain with vDSP optimization for Apple Silicon
- **AudioEngine**: Facade pattern for SwiftUI integration
- **EQDatabase**: SQLite for offline preset storage (17 MB, 2,347 models)

## 📁 Project Structure

```
SystemEQ for Mac/
├── Audio/              # Core Audio processing
│   ├── CoreAudioEngine.swift
│   ├── AudioRouter.swift
│   ├── BiquadFilter.swift
│   ├── CalibrationEngine.swift
│   └── VisualizerEngine.swift
├── Data/               # Data models and database
│   ├── EQDatabase.swift
│   ├── AutoEQModels.swift
│   └── PresetPersistence.swift
├── Features/           # UI views
│   ├── EqualizerView.swift
│   ├── AutoEQView.swift
│   ├── CalibrationView.swift
│   ├── VisualizerView.swift
│   ├── RoutingView.swift
│   └── SettingsView.swift
├── DesignSystem/       # Design tokens and components
├── Resources/          # Assets and database
│   └── EQDatabase.db   # SQLite database (17 MB)
└── Docs/               # Documentation
```

See [Docs/RepoStructure.md](Docs/RepoStructure.md) for detailed folder structure.

## 🎯 Usage

### Equalizer
- Use sliders to adjust frequency bands
- Switch between 10-band and 31-band modes
- Save custom presets for quick recall
- Apply auto-preamp to prevent clipping

### AutoEQ Presets
1. Search for your headphone model
2. Choose desired preset (oratory1990, Crinacle, etc.)
3. Click "⚡ Quick Import" for instant load
4. Adjust bass boost if needed (low-shelf filter)

### Calibration
1. Run hearing test (31 frequencies)
2. Adjust volume for each frequency to match reference
3. Save profile for automatic application
4. Use A/B comparison to test different profiles

### Visualizer
- Choose from 4 styles: Spectrum, Waveform, Particles, Psychedelic
- Adjust intensity slider (0-100%)
- Real-time FFT analysis at 60 FPS

## 🤝 Contributing

Contributions are welcome! Please:

1. Fork the project
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## 📄 License

MIT License — See [LICENSE](LICENSE) for details.

## 🙏 Credits

- [AutoEQ](https://github.com/jaakkopasanen/AutoEq) by Jaakko Pasanen — EQ preset database
- [BlackHole](https://github.com/ExistentialAudio/BlackHole) by Existential Audio — Virtual audio driver
- [oratory1990](https://www.reddit.com/r/oratory1990/) — Headphone measurements and research

## 💖 Support Development

If you find SystemEQ useful, consider supporting development:

- ☕ [Ko-fi](https://ko-fi.com/denyszamorniak)
- 🍺 [Buy Me a Coffee](https://buymeacoffee.com/denyszamorniak)
- 💝 [GitHub Sponsors](https://github.com/sponsors/denyszamorniak)

## 📧 Contact

- **GitHub**: [@denyszamorniak](https://github.com/denyszamorniak)
- **Email**: denys.zamorniak@gmail.com

---

**Made with ❤️ for the audio community**
