# SystemEQ for Mac — Planning & Wireframes (MVP)

System-wide equalizer for macOS 13+ with:
- 10- or 31-band EQ, presets, clipping guard.
- AutoEQ import (ParametricEQ.txt & GraphicEQ).
- Calibration: room correction + hearing test.
- MVP routing via BlackHole + Multi-Output; later: HAL plug-in.

See `Docs/` for wireframes, specs, and onboarding.

## Roadmap (summary)
- Phase 0: IA, wireframes, specs, design tokens.
- Phase 1: MVP app (SwiftUI + AVAudioEngine) with BlackHole routing.
- Phase 2: Calibration module (room correction + hearing test).
- Phase 3: HAL plug-in, installer, notarization.
- Phase 4: Visual polish (Liquid Glass).

## Minimum
- macOS: 13+
- Architectures: arm64, x86_64 (Universal)

## Folder map (planned)
- `SystemEQ for Mac/` — SwiftUI app (Xcode project already here)
- `Docs/` — planning artifacts (wireframes, specs, design)
- `DSP/` — future C/C++ DSPCore and Convolution engine
- `HALPlugin/` — future CoreAudio HAL plugin (Phase 3)

## Links
- AutoEQ: https://github.com/jaakkopasanen/AutoEq
- BlackHole: https://github.com/ExistentialAudio/BlackHole
