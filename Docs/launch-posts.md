# Launch posts — SystemEQ for Mac (draft, not for publishing in repo)

Official links:
- Source/Releases: https://github.com/denzam/SystemEQ-for-Mac
- Releases (download): https://github.com/denzam/SystemEQ-for-Mac/releases/latest
- Site: https://denzam.github.io/SystemEQ-for-Mac/
- Homebrew: `brew install --cask denzam/systemeq/systemeq`

---

## r/macapps — RULES CHECKLIST (from subreddit, read 2026-06-01)

- [ ] **10 LOCAL karma required** — comment in r/macapps FIRST to earn it before posting (Rule 1).
- [ ] Choose flair **App Devs** (Rule 1).
- [ ] Open source → prefix title with **[OS]** (Rule 1).
- [ ] Use the **PCP post template** (Rule 1) — check sub for current template.
- [ ] **Download links must be OFFICIAL source only** — use GitHub Releases, NOT shortened/redirect URLs (Rule 2 + Rule 5). github.io site is fine as info link, but the *download* link = GitHub Releases.
- [ ] **No redirect / shortened URLs at all** (Rule 5).
- [ ] **Disclose I'm the developer** in the post (Rule 3).
- [ ] Self-promo max once per 30 days (Rule 3).
- [ ] If not "trust/transparency" qualified → post in the **monthly megathread**, not main feed (Rule 8). Check eligibility link in rules before main-feed post.
- [ ] No affiliate/referral/invite links (Rule 6).

### Title
```
[OS] SystemEQ — free, open-source system-wide parametric equalizer for macOS (AutoEQ database for 8,665 headphones)
```

### Body
```
Hi r/macapps — I'm the developer of SystemEQ.

It's a free and open-source (GPLv3) system-wide parametric equalizer for
macOS 13+. It applies EQ to *all* your system audio — Spotify, YouTube,
Apple Music, browsers, anything.

What it does:
- 10/31-band parametric EQ with biquad filters (vDSP/Accelerate, low latency)
- Built-in AutoEQ database: 8,665 headphone models, one-click preset import
  (oratory1990, Crinacle, etc.)
- Hearing-calibration module with A/B comparison
- Real-time visualizer (spectrum, waveform, particles)
- No subscriptions, no ads, no telemetry — everything stays on your Mac

How it works: routing is handled via the free BlackHole driver (the app has a
guided Setup Assistant for it).

Honest caveats:
- Ad-hoc signed, NOT notarized (I don't pay the $99 Apple Developer fee — that's
  what keeps it free). Gatekeeper warns on first launch; right-click → Open
  once and you're done. Homebrew install bypasses this automatically.
- Needs BlackHole installed (free, guided).
- Adds ~10-20ms latency vs direct output (architectural limit of the routing).

Download (official GitHub Releases):
https://github.com/denzam/SystemEQ-for-Mac/releases/latest
Source: https://github.com/denzam/SystemEQ-for-Mac
Install: brew install --cask denzam/systemeq/systemeq

It's my project and I'd genuinely love feedback — what's missing, what's
confusing, what would make you actually use it. Happy to answer anything.
```

---

## r/headphones — STRICT, check megathread/self-promo thread first; do NOT post a standalone topic without checking sidebar.

### Body (for an allowed self-promo thread)
```
I made a free, open-source macOS app (SystemEQ) that imports AutoEQ presets
directly — it ships with a local database of 8,665 headphone models, so you
search your model and apply oratory1990/Crinacle presets system-wide in one
click, no manual GraphicEQ copy-paste. Also has a hearing-calibration module.
GPLv3, no telemetry. Would love feedback from people who actually live in AutoEQ.

https://github.com/denzam/SystemEQ-for-Mac
```

---

## Hacker News — Show HN

### Title
```
Show HN: SystemEQ – Open-source system-wide parametric EQ for macOS
```

### First comment (post immediately after submitting)
```
Hi HN, I'm the author. SystemEQ is a free, open-source (GPLv3) system-wide
parametric equalizer for macOS 13+.

Technical bits that might interest this crowd:
- Audio engine is low-level AUHAL dual I/O with a lock-free SPSC ring buffer
  (C11 atomics), biquad filtering via vDSP/Accelerate (~5-10x faster than a
  scalar loop), running on a real-time thread.
- System audio is captured through the BlackHole virtual driver and bridged
  directly to the physical output — no macOS Multi-Output Device needed.
- Ships a local SQLite AutoEQ database (8,665 headphone models, ~18MB) so
  preset search is fully offline and <10ms.
- Also has a hearing-calibration module and a real-time visualizer.

Honest tradeoffs: it's ad-hoc signed rather than notarized (no $99 Apple
Developer fee — keeps it free), so Gatekeeper warns on first launch. And
routing through BlackHole adds ~10-20ms latency. A proper HAL plugin would
fix both but also requires the paid Apple account.

Source: https://github.com/denzam/SystemEQ-for-Mac
Would appreciate feedback, especially on the audio architecture.
```

### Timing
- Post weekdays ~9-11am US Eastern. Be online to answer comments.

---

## Order
1. r/macapps first (after earning 10 karma). Watch reaction.
2. Hacker News Show HN.
3. r/headphones only via allowed thread.
