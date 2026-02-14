# Onboarding — MVP (BlackHole Routing)

## Automated Setup (Recommended)
SystemEQ includes a **Setup Assistant** that guides you through the entire process:
1) Launch SystemEQ for Mac
2) Follow the Setup Assistant wizard (appears on first run)
3) Click "Download BlackHole" when prompted
4) Install BlackHole 2ch (requires admin password)
5) Set BlackHole 2ch as System Output in Sound settings
6) Return to Setup Assistant and click "Continue"
7) Done! SystemEQ will automatically route audio through BlackHole

## Manual Setup (Advanced)
If you prefer manual setup or need to troubleshoot:
1) Install BlackHole 2ch from: https://github.com/ExistentialAudio/BlackHole
2) Open System Settings → Sound → Output
3) Select "BlackHole 2ch" as output device
4) Launch SystemEQ for Mac
5) In Routing tab: select BlackHole as input, your speakers/headphones as output
6) Enable EQ and play audio

**Note:** Multi-Output Device is NOT required. SystemEQ's CoreAudioEngine acts as the bridge between BlackHole and your physical output.

## Permissions
- **Audio Input:** Required for audio processing and calibration
- **Microphone:** Required for calibration wizard (hearing test)
- **Accessibility:** Optional, only for media key control
