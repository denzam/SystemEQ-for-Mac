# Performance & Latency Budget

- Target CPU (Apple Silicon, stereo 48 kHz):
  - Parametric EQ (10 bands): < 2%
  - Parametric EQ (31 bands): < 4%
  - Convolution (FIR 4096 taps, partitioned): < 6%
- Latency: keep < 10–15 ms end-to-end in MVP routing.
- Metering/update rate: 30–60 Hz UI.
