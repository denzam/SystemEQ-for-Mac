# Question about JM-1 target calculation parameters in autoeq.app

Hi Jaakko,

First, thank you for the incredible work on AutoEQ! It's an invaluable resource for the audio community.

## What we're building

I'm developing **SystemEQ** - a native macOS application that provides system-wide audio equalization using Apple's Core Audio. The app integrates AutoEQ presets to allow users to easily apply professional headphone equalization profiles directly at the system level without additional software.

## Our implementation

We've implemented a 4-tier fallback system:
- **Tier 0:** Local Python server using the AutoEQ library (for JM-1 targets)
- **Tier 1:** Direct parsing of local `.txt` files (FixedBandEQ.txt, GraphicEQ.txt)
- **Tier 2:** Cached README content
- **Tier 3:** GitHub README fetching

## The issue

When calculating JM-1 target values using the AutoEQ Python library, we're getting close but not identical results compared to autoeq.app. Here's an example for **HIFIMAN HE400se (non-stealth magnet)** from Filk:

```
autoeq.app (JM-1 with Harman filters):
  31 Hz: 10.7 dB
  63 Hz: 1.3 dB
  125 Hz: 0.5 dB
  250 Hz: -1.2 dB
  500 Hz: -1.1 dB
  1000 Hz: -0.7 dB
  2000 Hz: 3.6 dB
  4000 Hz: -1.2 dB
  8000 Hz: 0.4 dB
  16000 Hz: 3.0 dB
  Preamp: -11.2 dB

Our calculation (using AutoEQ library):
  31 Hz: 8.7 dB
  63 Hz: 4.7 dB
  125 Hz: 0.7 dB
  250 Hz: -1.1 dB
  500 Hz: -0.6 dB
  1000 Hz: -0.3 dB
  2000 Hz: 3.4 dB
  4000 Hz: -0.5 dB
  8000 Hz: -0.7 dB
  16000 Hz: 3.0 dB
  Preamp: -9.2 dB
```

## What we've tried

```python
# Our current approach
fr = FrequencyResponse(name=measurement_name, frequency=freq, raw=raw)
fr.interpolate()

target = FrequencyResponse(name=target_name, frequency=target_freq, raw=target_spl)
target.interpolate()
target.center()

fr.process(
    target=target,
    min_mean_error=True,
    max_gain=30.0,
    max_slope=50.0,
    window_size=1/12,
    treble_window_size=2.0,
    treble_f_lower=6000.0,
    treble_f_upper=8000.0,
    treble_gain_k=1.0
)

# Then extracting equalization values at ISO center frequencies (31.5, 63, 125, etc.)
```

We've also experimented with:
- Using `raw` vs `smoothed` data from CSV
- Different `max_gain` (6.0, 20.0, 30.0) and `max_slope` (18.0, 50.0) values
- Various processing parameters
- Different measurement sources (Filk, oratory1990, etc.)
- Using `compensate()` + `equalize()` separately vs `process()`

## Research Done

Before creating this issue, we researched the [Wiki page "How Does AutoEq Work?"](https://github.com/jaakkopasanen/AutoEq/wiki/How-Does-AutoEq-Work%3F) and found:
- The general process: error = raw - target, equalizer = -error
- Smoothing is applied to avoid measurement noise
- Maximum gain limits boost (default 6.0 dB for CLI)
- Slope limiting to avoid ringing
- Graphic EQ uses the same optimizer as Parametric EQ

We also noticed in `constants.py`:
```python
DEFAULT_FIXED_BAND_FILTER_MAX_GAIN = 12.0
```

However, even when we increased `max_gain=30.0` in `process()`, the results still don't match autoeq.app for JM-1 targets.

**Community feedback:** Multiple Reddit discussions mention differences between AutoEQ GitHub results and autoeq.app, but we couldn't find official documentation explaining these differences.

## Questions

1. Does autoeq.app use different processing parameters than the default library settings for JM-1 targets?
2. Are there specific smoothing or interpolation steps that we're missing?
3. Does the web app use a modified version of the processing pipeline?
4. Should we be using `optimize_fixed_band_eq()` instead of extracting values from `equalization` after `process()`?
5. Are there different gain limits or other constraints for JM-1 vs Harman targets in the web app?
6. Would you be willing to share the exact parameters/workflow used by autoeq.app for JM-1 calculations?

## Goal

We want to provide users with results that match autoeq.app exactly, so they get the same professional-quality equalization whether they use the web app or our native macOS application.

Any guidance would be greatly appreciated!

## Additional context

- AutoEQ version: 4.1.2 (from current repo)
- Python: 3.12
- Using local repository clone for measurements and targets
- Target file: `targets/JM-1 with Harman filters.csv`
- Measurement: `results/Filk/over-ear/HIFIMAN HE400se (non-stealth magnet)/HIFIMAN HE400se (non-stealth magnet).csv`

Thank you for your time and for maintaining this excellent project!
