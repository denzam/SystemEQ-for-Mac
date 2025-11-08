# Spec — Room Correction

Goal: derive correction from measured room/speaker response.

## Measurement
- Log sweep (e.g., 3–5 s), deconvolution → impulse response.
- Windowing of IR; optional minimum-phase transform.
- Mic selection; mono/stereo capture.

## Filter Design
- FIR convolution (partitioned FFT): head (short) + tail (long) to limit latency.
- FIR length targets: 1024–8192 taps per channel; partition 128–512.
- Alternative: parametric approximation if CPU/latency constrained.

## Latency & Headroom
- Show estimated latency; allow min/linear-phase switch.
- Auto preamp to avoid clipping.

## Output
- Correction curve + applied filter summary; enable/disable toggle.
