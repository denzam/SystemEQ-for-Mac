# Information Architecture & Flows

## Top-level
- Menu Bar Popover (quick controls)
- Main Window with tabs:
  - Dashboard
  - Equalizer
  - Calibration
  - Headphones
  - Routing
  - Presets
  - Settings

## Core Flows
- **First Run (MVP)**: Onboarding → Routing (BlackHole) → Apply demo preset → Hear changes.
- **AutoEQ Import**: Headphones → Import file → Map to 10/31 bands → Save as preset → Apply.
- **Calibration (later in MVP2)**: Wizard → Measure → Preview correction → Apply (FIR or parametric).

## State Model (blocks can run independently)
- Global ON/OFF controls processing.
- EQ ON/OFF and Calibration ON/OFF are independent sub-blocks.
- Headphones-only profiles can be applied conditionally.
