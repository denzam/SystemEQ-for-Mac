# Onboarding — Native and BlackHole

SystemEQ supports macOS 13 and later. Native capture requires macOS 14.4 or later.
The default **Automatic** backend tries Native first and falls back to BlackHole
if Native cannot start. The fallback requires BlackHole to be installed.

## Native setup (macOS 14.4 and later)

1) Launch SystemEQ for Mac and follow the welcome screen.
2) In Settings → Audio Engine, keep Automatic or choose Native (Process Tap).
3) In Routing → Devices, choose your speakers or headphones as Output Device.
4) Enable EQ and allow System Audio Recording when macOS requests it.
5) Play audio. Native capture does not require BlackHole or changing System Output to BlackHole.

If Native access was denied, allow SystemEQ to record system audio in
System Settings → Privacy & Security, then try enabling EQ again.

## BlackHole setup (macOS 13 and later)

Use BlackHole on macOS 13–14.3, or when you select it as an alternative backend.

1) Install BlackHole 2ch through the Setup Assistant or from
   https://github.com/ExistentialAudio/BlackHole.
2) In Settings → Audio Engine, choose BlackHole.
3) Allow Microphone access when macOS requests permission for the virtual audio input.
4) In Routing → Devices, choose BlackHole 2ch as Input Device and your speakers or
   headphones as Output Device.
5) Enable EQ and play audio. SystemEQ routes System Output through BlackHole while EQ is active.

A Multi-Output Device is not required. SystemEQ bridges BlackHole to the selected
physical output. Keep SystemEQ running while EQ is active.

## Permissions

- **Native:** System Audio Recording permission for system-audio capture.
- **BlackHole:** Microphone permission for the virtual audio input.
- **Calibration:** test tones and subjective calibration play audio; they do not
  record a physical microphone. Active EQ still requires its backend's permission.
- **Accessibility:** SystemEQ does not request it or use it to intercept media keys.
