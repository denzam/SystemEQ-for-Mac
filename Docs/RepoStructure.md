# Repo Structure & Naming

## Current Structure (MVP Complete)

```
SystemEQ for Mac/
├── SystemEQ for Mac/           # Main Xcode target
│   ├── Audio/                  # ✅ Audio engines (CoreAudioEngine, AudioRouter, CalibrationEngine, VisualizerEngine)
│   ├── AutoEQ/                 # ✅ AutoEQ integration (models, parsers, Python server)
│   ├── Data/                   # ✅ Preset persistence, EQ database
│   ├── Database/               # ✅ SQLite database (2,347 headphones, 8,850 presets)
│   ├── DesignSystem/           # ✅ UI components, design tokens
│   ├── Features/               # ✅ Main views (Equalizer, Calibration, Visualizer, AutoEQ, Routing, Settings)
│   ├── Infra/                  # ✅ Media keys, window management
│   ├── SetupAssistant/         # ✅ BlackHole setup wizard
│   ├── UI/                     # ✅ Reusable components (meters, sliders, toggles)
│   ├── Config/                 # ✅ App configuration
│   └── Resources/              # ✅ Assets, localization
├── Docs/                       # 📝 Documentation, specs, wireframes
├── Scripts/                    # 🔧 Build scripts, Python server
├── archive/                    # 📦 Historical docs and migration guides
└── AutoEq/                     # 📂 AutoEQ data (optional, fallback)
```

## Future Additions (Phase 3+)
- `HALPlugin/` — CoreAudio HAL plugin for true system-wide processing (requires paid Apple Developer account)
- `DSP/` — Advanced DSP (convolution, room correction algorithms)
