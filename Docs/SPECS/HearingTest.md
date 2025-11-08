# Spec — Hearing Test (Combined with Calibration)

Goal: estimate per-frequency audibility and generate a compensation curve.

## Protocol
- Frequencies: 125, 250, 500, 1k, 2k, 4k, 8k, 12k Hz (extendable to 31-band grid).
- Stimulus: warble or pure tones, 500 ms bursts with 200 ms gaps.
- Method: adaptive 2-down/1-up (Hughson-Westlake). Step 5 dB → 2 dB near threshold.
- Ear selection: both/left/right (for headphones).

## Safety & UX
- Start at low level; level check with pink noise.
- Hard cap (e.g., 85 dB SPL equivalent) with pre-calibrated output or relative scaling.
- Clear guidance and ability to abort immediately.

## Output
- Thresholds per frequency → smoothing → compensation curve (limit ±12 dB).
- Combine with room correction (if enabled) with headroom preamp.
