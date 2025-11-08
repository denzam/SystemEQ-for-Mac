# Wireframes (Textual) — SystemEQ for Mac

Minimum macOS: 13. Modes: 10-band or 31-band EQ. Visual polish (Liquid Glass) later.

## Menu Bar Popover
- **[Header]**: App name, global **ON/OFF** toggle.
- **[Preset Row]**: Preset dropdown (Factory/User) + Save/Update.
- **[Quick Controls]**: Output Gain slider (−12 … +12 dB), Clip indicator.
- **[Actions]**: Buttons: "Open Main Window", "Routing Help".

## Main Window — Navigation
Tabs (top): **Dashboard | Equalizer | Calibration | Headphones | Routing | Presets | Settings**

## Dashboard
- **[Status]**: Global ON/OFF, device in use, sample rate.
- **[Meters]**: Input/Output peak+RMS.
- **[Blocks]** (expand/collapse): Equalizer, Calibration, Headphones, Routing.
- **[Recent Presets]**: List with apply buttons.

## Equalizer
- **[Block Header]**: EQ ON/OFF; **Band Mode** switch: 10 / 31; **Show Visualization** toggle.
- **[Graph Panel]** (collapsible): Combined EQ curve; grid; clip margin.
- **[Bands Panel]**: For each band: Frequency, Gain, Q (for parametric), or fixed centers (for graphic).
- **[Preamp/Output]**: Preamp gain; Clip guard (auto headroom).
- **[Presets Subpanel]**: Load/Save, Import/Export (supports AutoEQ mapping output).

## Calibration
- **[Block Header]**: Calibration ON/OFF; Mode: Room Correction / Hearing Test / Combined.
- **[Wizard Steps]**: Device select → Level check → Measurement (sweeps or tones) → Result preview → Apply.
- **[Result Panel]**: Correction curve; latency estimate; safety preamp.
- **[Advanced]**: FIR length (if convolution), min/linear phase, smoothing.

## Headphones
- **[Device Select]**: Current headphones/output.
- **[Profiles]**: Assign AutoEQ profile per device; ON/OFF for headphones-only processing.
- **[Import]**: Dropzone for AutoEQ `.txt` (ParametricEQ.txt or GraphicEQ). Shows parsed filters & preamp.

## Routing
- **[Guide]**: Steps for BlackHole + Multi-Output creation in Audio MIDI Setup.
- **[Checks]**: Detect BlackHole installed? Multi-Output active? Sample rate match? Provide fix tips.
- **[Actions]**: Open Audio MIDI Setup.

## Presets
- **[Lists]**: Factory vs User. Search, tags.
- **[Details]**: Preview curve, apply, duplicate, export.

## Settings
- **[General]**: Auto-launch, language (EN/UKR), theme.
- **[Links]**: AutoEQ repo link, Support.
- **[Advanced]**: Buffer size (if exposed), logging.
