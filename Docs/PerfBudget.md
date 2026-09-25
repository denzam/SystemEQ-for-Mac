# Performance & Latency Budget

Updated: 2026-09-25.

## Targets

- Apple Silicon, stereo 48 kHz:
  - 10-band EQ: < 2% CPU.
  - 31-band EQ: < 4% CPU.
  - Future partitioned FIR, 4096 taps: < 6% CPU.
- Desired end-to-end latency: < 10–15 ms. The 2026-09-25 Scarlett loopback measured 11.38 ms in Native mode and about 28 ms through BlackHole on the Debug build at `adb979d`.
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

## Runtime diagnostics

Diagnostic report format 3 includes the executable Mach-O UUID, bundle build number, and Debug/Release configuration. The UUID identifies the actual binary even when multiple local builds share a marketing version; compare it with `dwarfdump --uuid` for the executable being profiled.

Diagnostic history is held only in memory, capped at 100 events. Each entry is limited to 16 fields, 128 UTF-8 bytes for names/keys, and 512 bytes per value. Old entries are discarded, and the report states the discarded count and diagnostic session start. The app creates no automatic diagnostic log files. Exported reports are written only after the user selects a save destination and remain user-owned files; SystemEQ does not delete them automatically.

BlackHole reports distinguish processing-buffer capacity, ring-buffer capacity, and the last fill level before a read, paired with the number of frames requested by that read. The fill is not an end-to-end latency measurement. Underrun/overrun counters use C11 atomic increments and exchanges; export resets these interval counters and reports elapsed monotonic time since the previous sample or buffer reset. The corresponding 100000-read concurrent sampling test passed under Thread Sanitizer; this only covers that tested scenario. Native/inactive routes mark BlackHole ring statistics as not applicable. Callback timing remains Debug-only; Release events label it unavailable.

Routing requests now include a trigger for backend selection, output selection, sample-rate changes, system-output changes, device recovery, output removal/return, and wake. Sleep and scheduled wake recovery are retained as separate bounded events. Generic enable requests remain labelled `request`.

## Physical loopback latency, 2026-09-25

`Scripts/measure_loopback_latency.swift` writes a 2047-frame marker through a CoreAudio device IOProc, captures the Scarlett input, and uses output/input host timestamps plus offline cross-correlation. The previous AVAudioPlayerNode probe included player scheduling and is not an absolute latency measurement. A Scarlett output-to-input cable was connected; direct Scarlett loopback and BlackHole self-loopback were used as controls. The reported path includes the physical interface, and all runs below used 48 kHz, the same Scarlett, the same cable, the same EQ preset, and 10 accepted markers out of 10 with no capture-segment overflows.

| Binary and route | Median | p95 | Internal buffer |
|---|---:|---:|---:|
| Installed binary from 2026-09-19, BlackHole | 99.10 ms | 99.15 ms | 512 output frames |
| Debug binary at `adb979d`, BlackHole | 27.94 ms | 27.98 ms | 256 output frames |
| Installed binary from 2026-09-19, Native | 27.40 ms | 27.40 ms | Not recorded in this run |
| Debug binary at `adb979d`, Native | 11.38 ms | 11.38 ms | 128 aggregate frames |

The Debug BlackHole run measured 27.99 ms median and 28.02 ms p95 after another 7 minutes 44 seconds, a 0.05 ms change from its initial run. The probe still accepted 10/10 markers. A short Debug diagnostic interval of 15.9 seconds showed zero ring underruns and overruns; the long-run counters were not captured because the save dialog became inaccessible. Earlier 256-frame prototype measurements rose from 13.80 to 32.28 ms over roughly nine minutes, which motivated the bounded resampling correction in `adb979d`.

These are end-to-end binary/configuration comparisons, not an isolated measurement of one code change: the internal buffer sizes differ. The separate probe IOProcs reported 512-frame Scarlett and BlackHole device buffers in every run; those values are not the app's internal callback sizes. The EQ was in 31-band mode with 30 active bands and -1.5 dB preamp. Raw local probe results and diagnostic exports are in ignored `LocalArtifacts/LoopbackLatency/`.

To repeat the measurement, compile the checked-in probe and run it while SystemEQ is active in the matching backend. Confirm the exact device UIDs and buffer sizes in each JSON report, and keep the same physical cable and EQ state:

```bash
mkdir -p LocalArtifacts/LoopbackLatency
xcrun swiftc -parse-as-library -O -warnings-as-errors \
  Scripts/measure_loopback_latency.swift \
  -o LocalArtifacts/LoopbackLatency/measure-loopback-latency
LocalArtifacts/LoopbackLatency/measure-loopback-latency \
  --output 'BlackHole 2ch' --input 'Scarlett 2i2 USB' \
  --trials 10 --min-latency-ms 1 --max-latency-ms 200
LocalArtifacts/LoopbackLatency/measure-loopback-latency \
  --output 'Scarlett 2i2 USB' --input 'Scarlett 2i2 USB' \
  --trials 10 --min-latency-ms 1 --max-latency-ms 200
```

## Measurements still required

- Record process CPU for flat, 10-band, and 31-band states after warm-up. Keep ProjectM disabled during the EQ baseline, then profile it separately by render scale.
- Export ring underrun/overrun counters after a long BlackHole run and listen for glitches. The seven-minute correlation test validates timing stability for that run, not uninterrupted playback quality.
