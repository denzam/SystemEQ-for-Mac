# Launch posts — SystemEQ for Mac (draft, not for publishing in repo)

Official links:
- Source/Releases: https://github.com/denzam/SystemEQ-for-Mac
- Releases (download): https://github.com/denzam/SystemEQ-for-Mac/releases/latest
- Site: https://denzam.github.io/SystemEQ-for-Mac/
- Homebrew: `brew install --cask denzam/systemeq/systemeq`

---

## Reddit — Personal profile (u/Im-from-ua)

No subreddit rules, no karma gate — post freely on your own profile. Same story
as the LinkedIn post but in a more honest, less corporate Reddit tone.

### Title
```
I assemble medical devices for a living. In my spare time I built a system-wide audio EQ for macOS.
```

### Body
```
Not a pro developer, no CS degree — just curiosity and a lot of evenings after work.

I built **SystemEQ**: a free, open-source system-wide parametric equalizer for macOS. It EQs *everything* your Mac plays — Spotify, YouTube, browsers, any app — not just one player. The audio engine is written from scratch on CoreAudio + Apple's Accelerate framework.

What it does:

- 10/31-band parametric EQ (biquad filters via vDSP)
- Built-in AutoEQ database — **8,665 headphone models**, apply an expert preset in one click
- Hearing-calibration module with A/B comparison
- Real-time visualizer
- No telemetry, no subscriptions, no ads — everything stays local

It's GPLv3 and completely free. I didn't pay Apple's $99 developer fee, which is exactly what keeps it free and open.

GitHub: https://github.com/denzam/SystemEQ-for-Mac

Happy to answer anything about the audio architecture or how the BlackHole routing works.
```

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

## LinkedIn — Personal post (your own profile)

### Post
```
🇬🇧 By day I assemble medical devices. In my free time I built an audio engine for macOS.

I'm not a professional developer. No computer science degree — just curiosity
and a lot of late evenings.

SystemEQ is a free and open-source equalizer for macOS. It lets you fine-tune
the sound of everything your Mac plays — Spotify, YouTube, Apple Music, any
browser — not just one app. Under the hood it's a low-latency audio engine I
wrote from scratch on Apple's CoreAudio and Accelerate frameworks.

What it does:
→ 10/31-band parametric EQ (the kind audio engineers use)
→ Built-in database of 8,665 headphone models — pick yours and apply a
  tuned-by-experts preset in one click
→ Hearing-calibration module with A/B comparison
→ Real-time audio visualizer
→ No tracking, no subscriptions, no ads — everything stays on your Mac

It's completely free. I chose not to pay Apple's $99 developer fee, and that's
exactly what lets me keep it free and open for everyone.

You don't need the right job title to build something real. You just need to start.

GitHub: https://github.com/denzam/SystemEQ-for-Mac
Site: https://denzam.github.io/SystemEQ-for-Mac/

—

🇮🇹 Di lavoro assemblo dispositivi medicali. Nel tempo libero ho creato un'app audio per Mac.

Non sono uno sviluppatore di professione, non ho una laurea in informatica.
Solo curiosità e tante serate passate a programmare.

SystemEQ è un equalizzatore gratuito e open source per macOS. Ti permette di
regolare il suono di tutto ciò che riproduci sul Mac — Spotify, YouTube, Apple
Music, qualsiasi browser — e non di una singola app. Dietro le quinte c'è un
motore audio a bassa latenza che ho scritto da zero usando i framework
CoreAudio e Accelerate di Apple.

Cosa fa:
→ Equalizzatore parametrico a 10/31 bande (quello che usano i tecnici del suono)
→ Database integrato con 8.665 modelli di cuffie — scegli il tuo e applichi un
  preset ottimizzato dagli esperti con un clic
→ Modulo per la calibrazione dell'udito con confronto A/B
→ Visualizzatore audio in tempo reale
→ Nessun tracciamento, nessun abbonamento, nessuna pubblicità — tutto resta sul tuo Mac

È completamente gratuita. Ho scelto di non pagare la quota sviluppatore di Apple
da 99 $, ed è proprio questo che mi permette di tenerla gratuita e aperta a tutti.

Non serve avere il titolo giusto per costruire qualcosa di reale. Basta iniziare.

GitHub: https://github.com/denzam/SystemEQ-for-Mac
Sito: https://denzam.github.io/SystemEQ-for-Mac/

#OpenSource #Swift #macOS #SideProject #AudioEngineering
```

### Notes

- Tag it as a personal project post, not a company post.
- First comment: add the Homebrew one-liner for quick install.
- Engage with comments within the first hour — LinkedIn algorithm rewards early engagement.

---

## Order
1. r/macapps first (after earning 10 karma). Watch reaction.
2. Hacker News Show HN.
3. r/headphones only via allowed thread.
4. LinkedIn — anytime, independent of the rest.
