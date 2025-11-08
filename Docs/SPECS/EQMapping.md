# Spec — Mapping to 10/31 Band EQ

## Grids
- 10-band ISO centers: 31.5, 63, 125, 250, 500, 1k, 2k, 4k, 8k, 16k Hz.
- 31-band (1/3 octave) centers from 20 Hz to 20 kHz.

## Fitting
- Sample source response (from AutoEQ or measurement) on dense log-f grid.
- Solve least-squares for band gains with constraints (±12 dB default).
- Apply smoothing (e.g., 1/3 octave) before fitting to avoid overfitting.

## Preamp
- Compute required headroom from max positive gain; adjust preamp.

## Validation
- Report approximation error (RMS/Max). If high, suggest 31-band mode.
