# Spec — AutoEQ Import

Supports two formats: ParametricEQ.txt and GraphicEQ.

## ParametricEQ.txt
Example lines:
- `Preamp: -6.0 dB`
- `Filter 1: ON PK Fc 1000 Hz Gain +3.0 dB Q 1.41`
- Types: PK (peaking), LS (low-shelf), HS (high-shelf). Others ignore with warning.
- Parse all filters, respect `Preamp`.

Validation:
- Fc within [20, 20000] Hz, Q within [0.2, 10], |Gain| ≤ 24 dB (clamp with notice).
- Unknown tokens → soft error (skip line, show toast).

## GraphicEQ
Example:
- `GraphicEQ: 31.5 0; 40 0; 50 -1.2; 63 -1.8; ...` (freq gain pairs)
- Interpolate to internal target grid (10 or 31 centers).

## Mapping to 10/31 bands
- Least-squares fit of source response onto fixed centers.
- Preserve overall preamp; enforce per-band gain limits (e.g., ±12 dB default).
- Smoothing (1/3 octave) optional.

## Output
- Internal preset with: band gains, preamp, metadata (source, file name, date).
- Show summary: max positive/negative gain, suggested headroom.

## Errors
- Missing/unknown format → prompt user.
- Too many filters for 10-band → reduce via fitting; show delta (approximation).
