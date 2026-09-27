# Repo Structure & Naming

## Current Structure (MVP Complete)

```
SystemEQ for Mac/
├── SystemEQ for Mac/           # Main Xcode target
│   ├── Audio/                  # Audio engines (CoreAudioEngine, AudioRouter, ProcessTapEngine)
│   ├── AutoEQ/                 # AutoEQ models & converters
│   ├── Data/                   # EQDatabase (SQLite FTS5), EQProcessor
│   ├── DesignSystem/           # UI components, design tokens, EQGraphView
│   ├── Features/               # Main views (AutoEQ, Routing, Settings, Visualizer, Calibration)
│   ├── Infra/                  # WindowCoordinator, observers
│   ├── SetupAssistant/         # BlackHole setup wizard
│   ├── UI/                     # Reusable components
│   ├── Config/                 # App configuration & features.json
│   └── Resources/              # Assets & EQDatabase.db
├── ProjectMHelper/             # Dedicated ProjectM visualizer process (IPC via Unix socket)
├── SystemEQ for MacTests/      # Unit test suite (141 tests)
├── Docs/                       # Documentation & archive/
├── Scripts/                    # Build scripts & database generators
└── Vendor/                     # External libraries (ProjectM dynamic libraries & headers)
```

## Future Additions (Phase 3+)
- `HALPlugin/` — CoreAudio HAL plugin for true system-wide processing (requires paid Apple Developer account)
- `DSP/` — Advanced DSP (convolution, room correction algorithms)
