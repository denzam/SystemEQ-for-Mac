# Performance & Latency Budget

Updated: 2026-09-11.

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

## Reproducible offline DSP benchmark

`Scripts/benchmark_dsp.swift` compiles with the production filter and model sources. It neither starts the app nor opens audio devices. Run from the repository root with the configured Xcode toolchain:

```bash
mkdir -p LocalArtifacts/DSPBenchmark
xcrun swiftc -O -whole-module-optimization -warnings-as-errors \
  -module-cache-path LocalArtifacts/DSPBenchmark/ModuleCache \
  'SystemEQ for Mac/Data/AutoEQConstants.swift' \
  'SystemEQ for Mac/Data/AutoEQModels.swift' \
  'SystemEQ for Mac/Audio/BiquadFilterVDSP.swift' \
  Scripts/benchmark_dsp.swift \
  -o LocalArtifacts/DSPBenchmark/benchmark-dsp
xcrun swiftc --version
git rev-parse HEAD
LocalArtifacts/DSPBenchmark/benchmark-dsp 10000 3 > LocalArtifacts/DSPBenchmark/baseline.json
```

The arguments are measured blocks per trial and trials per workload/buffer size. The benchmark uses stereo 48 kHz, buffers of 128/256/512 frames, and 512 warm-up blocks per trial. Each measured block receives fresh deterministic input; processed output is never recycled as input. It rotates workload order between trials and reports flat, 10/31 active peak filters, an active-limiter workload, and a copy/timing baseline. The 10-filter workload is synthetic: it does not reproduce the app's mixed shelf/peak policy. Filter construction and input generation are outside the measured interval.

`threadCPUPercentOfOneCore` is thread CPU time divided by the simulated audio duration, multiplied by 100. It includes input copies, clocks, and checksum overhead. It is an estimated processing cost at real-time throughput, not measured whole-process CPU during playback. Wall-clock p50/p95/p99/max cover each DSP call and clock overhead; the copy-only workload exposes the timing floor. Results near that floor should not be interpreted as precise DSP timings. Neither clock measures audio transport latency. The loop runs without real-time pacing and does not include the engine, metering, UI, or ProjectM.

### Local baseline, 2026-09-11

Apple M1, 8 GB RAM; Swift 6.3.3; production sources at `456f0b9`; optimized build. Two runs, three trials each, 10000 measured blocks per trial. At 256 frames (5.333 ms of audio per block):

| Workload | CPU cost, % of one core (range over 6 trials) | Largest trial p99, µs |
|---|---:|---:|
| Copy/timing baseline | 0.00075–0.00093 | 0.042 |
| Flat | 0.00132–0.00149 | 0.084 |
| 10 active peaks | 0.0780–0.0787 | 4.583 |
| 31 active peaks | 0.2380–0.2507 | 19.667 |
| 31 active peaks + limiter | 0.2541–0.2689 | 21.709 |

No measured DSP-call interval exceeded the buffer duration across these runs and buffer sizes. This is not proof of glitch-free playback: device scheduling and routing were absent. The short 128-frame trials showed more CPU variability, so retain repeated measurements rather than relying on a single value. These results do not currently justify changing the production vDSP implementation for speed.

Raw local results are in `LocalArtifacts/DSPBenchmark/baseline-2026-09-11.json` and `baseline-repeat-2026-09-11.json`. `LocalArtifacts/` is ignored by Git; use the command above to reproduce them on another checkout.

## Measurements still required

- Do not use the previous AVAudioPlayerNode loopback probe as an absolute latency number: it included player scheduling, and Native capture could observe the direct Scarlett signal.
- Measure Native and BlackHole under identical sample rate, buffer size, output device, EQ mode, and audio material.
- Derive latency from CoreAudio host timestamps at the output boundary, then report median and high-percentile results separately for Native and BlackHole.
- Record process CPU for flat, 10-band, and 31-band states after warm-up. Keep ProjectM disabled during the EQ baseline, then profile it separately by render scale.
