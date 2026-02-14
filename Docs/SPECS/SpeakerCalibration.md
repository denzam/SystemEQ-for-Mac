# Spec — Speaker Calibration (Equal Loudness)

**Goal:** Compensate for room acoustics + speaker response + hearing using subjective equal loudness matching (Neutralizer-style).

---

## Protocol

### Reference Setup
- **Reference frequency:** 1000 Hz (most sensitive for human hearing)
- **Reference level:** User-adjustable (-40 dB to 0 dB, default -20 dB)
- **Method:** User sets comfortable listening level

### Frequency Calibration
- **Test frequencies:** 
  - 10-band mode: 31.5, 63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000 Hz
  - 31-band mode: Full ISO 1/3-octave grid (20 Hz - 20 kHz)
- **Method:** User adjusts each frequency until it sounds as loud as reference
- **Range:** ±20 dB per band
- **Playback modes:**
  - Single tone (reference or test)
  - Alternating comparison (reference → test → reference)

---

## UX Flow

### Step 1: Band Count Selection
User chooses between:
- **10 bands** (~5 minutes) — Recommended ⚡️
- **31 bands** (~15 minutes) — For perfectionists 🐌

**31-band warnings:**
- Warning 1: "⏰ Це буде ДУЖЕ довго!" (with humorous message)
- Warning 2: "🤔 Ти точно впевнений?" (last chance to switch to 10-band)

### Step 2: Reference Level Setup
1. Play 1000 Hz tone
2. Adjust level slider to comfortable listening volume
3. Click "Continue to Calibration"

### Step 3: Frequency Calibration
For each frequency:
1. Display current frequency (e.g., "63 Hz")
2. Show adjustment slider (-20 dB to +20 dB)
3. Playback controls:
   - "Play Reference" — Hear 1000 Hz reference
   - "Play Test" — Hear current frequency
   - "Compare (Alternating)" — Automatic A/B comparison
4. User adjusts until test sounds as loud as reference
5. Click "Next" to proceed

### Step 4: Save Profile
1. Enter profile name (e.g., "Living Room Speakers")
2. Optional notes
3. Save to profiles list

---

## Output

### Calibration Profile
- **Type:** Equal Loudness
- **Bands:** 31 adjustments (dB per frequency)
- **Metadata:** Name, creation date, notes
- **Storage:** JSON in Application Support

### Application
- Profile can be activated/deactivated
- Applied on top of existing EQ settings
- A/B comparison between profiles

---

## Advantages

✅ **No microphone required** — Pure subjective calibration  
✅ **Compensates everything** — Room + speakers + hearing  
✅ **Room-independent** — Works in any environment  
✅ **Simple UX** — Play tone → adjust → next  
✅ **Flexible** — 10-band (fast) or 31-band (precise)

---

## Comparison with Other Methods

| Method | Neutralizer/Equal Loudness | Room Correction | Hearing Test |
|--------|---------------------------|-----------------|--------------|
| **Input** | User's ears | Microphone | Threshold detection |
| **Compensates** | Room + speakers + hearing | Room + speakers only | Hearing loss only |
| **Equipment** | None | Calibrated mic | None |
| **Time** | 5-15 min | 2-5 min | 10-20 min |
| **Accuracy** | Subjective | Objective | Medical |
| **Use case** | Everyday listening | Studio monitoring | Diagnosis |

---

## Implementation Notes

### Audio Engine
- Uses `CalibrationEngine.swift` for tone generation
- Test tones: Pure sine waves with fade in/out (50ms)
- Sample rate: 48 kHz
- Channels: Stereo (identical L/R)

### Comparison Mode
- Alternating playback: Reference (1.5s) → Test (1.5s) → repeat
- Automatic stop when user navigates away
- Visual feedback (button state changes)

### Profile Storage
- Format: JSON
- Location: `~/Library/Application Support/SystemEQ for Mac/CalibrationProfiles.json`
- Fields: `id`, `name`, `type`, `bands[31]`, `notes`, `createdAt`

---

## Future Enhancements

- [ ] Pink noise option (instead of pure tones)
- [ ] Warble tones (frequency modulation)
- [ ] Auto-save progress (resume interrupted calibration)
- [ ] Export/import profiles (share with other users)
- [ ] Frequency response visualization
- [ ] Integration with AutoEQ presets

---

**Last Updated:** December 7, 2025  
**Status:** ✅ Implemented
