# Performance & Latency Budget

Updated: 2026-09-07.

## Targets

- Apple Silicon, stereo 48 kHz:
  - 10-band EQ: < 2% CPU.
  - 31-band EQ: < 4% CPU.
  - Future partitioned FIR, 4096 taps: < 6% CPU.
- Desired end-to-end latency: < 10–15 ms. This remains a target, not a confirmed measurement.
- Peak-meter UI publication: 12.5 Hz. Audio metering remains throttled to approximately one buffer pass per 4096 accumulated frames.

## Current safeguards

- Production EQ uses batched `vDSP_biquad`; filter changes use an atomic pointer swap outside the render callback.
- The render callback does not allocate, lock, log, or schedule main-queue work for peak metering.
- `PeakMeter` writes an atomic input/output snapshot; a main-thread timer publishes it to SwiftUI.
- Limiter gain reduction is aggregated with an atomic minimum so short limiter events are retained between UI ticks.
- The concurrent filter-swap stress test runs 2000 render iterations while replacing the vDSP filter 250 times. It passes with Thread Sanitizer enabled.

## Measurements still required

- Do not use the previous AVAudioPlayerNode loopback probe as an absolute latency number: it included player scheduling, and Native capture could observe the direct Scarlett signal.
- Measure Native and BlackHole under identical sample rate, buffer size, output device, EQ mode, and audio material.
- Derive latency from CoreAudio host timestamps at the output boundary, then report median and high-percentile results separately for Native and BlackHole.
- Record process CPU for flat, 10-band, and 31-band states after warm-up. Keep ProjectM disabled during the EQ baseline, then profile it separately by render scale.
