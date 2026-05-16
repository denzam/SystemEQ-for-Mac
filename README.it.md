# SystemEQ for Mac

Equalizzatore professionale a livello di sistema per macOS 13+

[![macOS](https://img.shields.io/badge/macOS-13%2B-blue)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange)](https://swift.org)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

> 🇮🇹 Italiano | 🇬🇧 [English](README.md) | 🇺🇦 [Українська](README.ua.md)

## ✨ Funzionalità

### Funzioni principali

- **EQ Parametrico 10/31 bande** — Elaborazione audio professionale con filtri biquad
- **Database AutoEQ** — 8.665 modelli di cuffie, 8.850 preset (SQLite, 18 MB)
- **Visualizzazione in tempo reale** — Spettro, Forma d'onda, Particelle, Psichedelico
- **Modulo di calibrazione** — Test dell'udito + profili personalizzati + confronto A/B
- **Integrazione BlackHole** — Routing audio di sistema con Setup Assistant automatico
- **Gestione preset** — Salva, carica e organizza le impostazioni EQ
- **Multilingua** — Inglese, Italiano, Ucraino

### Motore audio

- **CoreAudioEngine** — Bassa latenza (~5-10ms) tramite AudioUnit (AUHAL)
- **Filtri Biquad vDSP** — Framework Accelerate, 5-10× più veloce dello scalare
- **Peak Meter** — Monitoraggio del livello audio in tempo reale
- **Protezione dal clipping** — Riduzione automatica del guadagno e controllo del preamplificatore
- **Supporto tasti multimediali** — Controllo volume da tastiera

### Integrazione AutoEQ

- **Database SQLite** — Ricerca offline istantanea (<10ms)
- **Fallback a 4 livelli** — Server Python → Database → File locali → GitHub
- **ParametricEQ e GraphicEQ** — Supporto completo dei formati

## 🚀 Avvio rapido

### Requisiti

- macOS 13.0 (Ventura) o successivo
- Apple Silicon (M1/M2/M3) o Mac Intel
- [BlackHole 2ch](https://github.com/ExistentialAudio/BlackHole) (driver audio virtuale gratuito)
- 4 GB RAM (8 GB consigliati)

### Installazione

#### Opzione 1: Homebrew (più semplice — aggira Gatekeeper automaticamente)

```bash
brew install --cask denzam/systemeq/systemeq
```

Il Cask rimuove l'attributo di quarantena durante l'installazione, quindi
l'app si avvia senza avvisi di Gatekeeper.

#### Opzione 2: Scarica il DMG

1. Scarica l'ultimo `.dmg` o `.zip` dalle [Releases](https://github.com/denzam/SystemEQ-for-Mac/releases)
2. Apri il DMG e trascina `SystemEQ for Mac.app` in `/Applicazioni`
3. **Al primo avvio (una di queste opzioni):**
   - **Clic destro sull'app → Apri → Apri** nella finestra di conferma, oppure
   - Prova ad avviarla, poi apri **Impostazioni di Sistema → Privacy e Sicurezza → Apri comunque**, oppure
   - Da Terminale:
     ```bash
     xattr -dr com.apple.quarantine "/Applications/SystemEQ for Mac.app"
     ```
4. Segui il **Setup Assistant** per installare BlackHole

> L'app è **firmata ad-hoc** (gratis, autofirmata) — non notarizzata con un
> Apple Developer ID. Per questo Gatekeeper mostra un avviso al primo avvio.
> È una scelta intenzionale: SystemEQ resta gratuito e non richiede il
> programma Apple Developer a pagamento. I passaggi sopra vanno fatti una
> sola volta.

#### Opzione 3: Compilare dal sorgente

```bash
git clone https://github.com/denzam/SystemEQ-for-Mac.git
cd "SystemEQ for Mac"
open "SystemEQ for Mac.xcodeproj"
# Premi Cmd+R per compilare ed eseguire
```

### Guida alla configurazione

1. **Installa BlackHole** (automatico tramite Setup Assistant):
   - Scarica dal [sito BlackHole](https://existential.audio/blackhole/)
   - Installa la versione a 2 canali
   - Riavvia SystemEQ dopo l'installazione

2. **Configura il routing audio**:
   - Apri SystemEQ → scheda Routing
   - Seleziona BlackHole come ingresso, le tue cuffie/altoparlanti come uscita
   - Imposta l'uscita di sistema su BlackHole nelle Impostazioni audio di macOS

3. **Applica un preset EQ**:
   - Scheda AutoEQ → cerca il modello delle tue cuffie
   - Clicca "⚡ Quick Import"
   - Oppure regola manualmente le bande nella scheda Equalizer

## 🛠️ Architettura

```text
Uscita di sistema → BlackHole 2ch
                         ↓
                 CoreAudioEngine (input)
                         ↓
              Elaborazione EQ Biquad vDSP
                         ↓
                 CoreAudioEngine (output)
                         ↓
             Cuffie/Altoparlanti fisici
```

**Nessun Multi-Output Device necessario.** CoreAudioEngine fa da ponte tra BlackHole e l'uscita fisica.

### Dettagli tecnici

- **CoreAudioEngine**: AUHAL dual I/O di basso livello, ring buffer lock-free
- **BiquadFilterVDSP**: elaborazione batch vDSP, 5-10× più veloce dello scalare
- **SPSCRingBuffer**: buffer SPSC lock-free con atomiche C11
- **EQDatabase**: SQLite, 18 MB, 8.665 modelli di cuffie

## 📁 Struttura del progetto

```text
SystemEQ for Mac/
├── Audio/              # Elaborazione Core Audio
│   ├── CoreAudioEngine.swift
│   ├── AudioRouter.swift
│   ├── BiquadFilterVDSP.swift
│   ├── CalibrationEngine.swift
│   └── SPSCRingBuffer.swift
├── Data/               # Modelli dati e database
│   ├── EQDatabase.swift
│   ├── AutoEQModels.swift
│   └── PresetPersistence.swift
├── Features/           # Viste UI
│   ├── EqualizerView.swift
│   ├── AutoEQView.swift
│   ├── CalibrationView.swift
│   ├── VisualizerView.swift
│   └── RoutingView.swift
├── DesignSystem/       # Token di design e componenti
├── Resources/          # Asset e database
│   └── EQDatabase.db
└── Docs/               # Documentazione
```

## 🎯 Utilizzo

### Equalizzatore

- Regola le bande di frequenza con i cursori
- Passa dalla modalità 10 bande a 31 bande
- Salva preset personalizzati per un richiamo rapido
- Applica il pre-amplificatore automatico per prevenire il clipping

### Preset AutoEQ

1. Cerca il modello delle tue cuffie (8.665 disponibili)
2. Scegli un preset (oratory1990, Crinacle, ecc.)
3. Clicca "⚡ Quick Import"
4. Regola il boost dei bassi se necessario

### Calibrazione

1. Esegui il test dell'udito (31 frequenze)
2. Regola il volume per ogni frequenza rispetto al riferimento
3. Salva il profilo per l'applicazione automatica
4. Usa il confronto A/B per valutare i profili

### Visualizzatore

- Scegli tra 4 stili: Spectrum, Waveform, Particles, Psychedelic
- Regola l'intensità (0–100%)
- FFT in tempo reale a 60 FPS

## 🎚️ Compatibilità con DAW (Reaper, Logic, Ableton, ecc.)

SystemEQ elabora **l'uscita audio di sistema**. I DAW di solito bypassano l'uscita di sistema e comunicano direttamente con l'interfaccia audio — quindi l'EQ **non viene applicato** di default.

| Scenario | EQ applicato? |
| --- | --- |
| Spotify, YouTube, Apple Music | ✅ Sì |
| DAW → Uscita di sistema (config. manuale) | ✅ Sì |
| DAW → Interfaccia audio direttamente (tipico) | ❌ No |
| Monitoraggio DAW tramite Scarlett/Focusrite | ❌ No |

### Come usare SystemEQ con il tuo DAW

1. Nel tuo DAW, imposta il **dispositivo di uscita su BlackHole 2ch**
2. SystemEQ applica l'EQ e inoltra l'audio all'uscita fisica
3. Per tornare al monitoraggio diretto, reimposta l'uscita DAW sulla tua interfaccia

**Reaper:** Options → Preferences → Audio → Device → BlackHole 2ch

**Logic:** Preferenze → Audio → Dispositivo di uscita → BlackHole 2ch

**Ableton:** Preferenze → Audio → Dispositivo di uscita → BlackHole 2ch

> Questo aggiunge ~10-20ms di latenza extra rispetto al monitoraggio diretto. Limitazione architetturale di BlackHole (driver di sistema). Un futuro HAL Audio Plugin risolverebbe il problema, ma richiede un account Apple Developer a pagamento.

## 📊 Stato del progetto

- ✅ Fase 1: Core EQ + routing BlackHole
- ✅ Fase 2: Calibrazione + Visualizzatore
- ✅ Fase 3: Integrazione database AutoEQ (8.665 modelli)
- ⏭️ Fase 4: HAL plugin (richiede account Apple Developer a pagamento)
- ⏭️ Fase 5: Rifinitura visiva Liquid Glass

## ⚠️ Nota sulla sicurezza

- L'app **non è in sandbox** (incompatibile con i dispositivi audio virtuali CoreAudio/AUHAL)
- **Nessuna telemetria, analisi o raccolta dati** — tutti i dati rimangono sul tuo Mac
- Installa solo dalle [GitHub Releases](https://github.com/denzam/SystemEQ-for-Mac/releases) ufficiali
- Firmata ad-hoc — clic destro → Apri al primo avvio per bypassare il Gatekeeper

## 🤝 Contribuire

1. Fai il fork del progetto
2. Crea il tuo branch (`git checkout -b feature/FunzionalitàStupenda`)
3. Esegui il commit delle modifiche (`git commit -m 'Aggiungi FunzionalitàStupenda'`)
4. Fai il push del branch (`git push origin feature/FunzionalitàStupenda`)
5. Apri una Pull Request

## 📄 Licenza

**GNU General Public License v3.0** — vedi [LICENSE](LICENSE).

SystemEQ è software libero. Puoi usarlo, modificarlo e ridistribuirlo, ma
**qualsiasi fork o opera derivata** deve essere rilasciato sotto GPLv3 con
il codice sorgente completo. Fork chiusi o commerciali a pagamento non
sono permessi.

I componenti di terze parti e le rispettive licenze sono elencati in
[THIRDPARTY.md](THIRDPARTY.md).

## 🙏 Ringraziamenti

- [AutoEQ](https://github.com/jaakkopasanen/AutoEq) di Jaakko Pasanen — database preset EQ
- [BlackHole](https://github.com/ExistentialAudio/BlackHole) di Existential Audio — driver audio virtuale
- [oratory1990](https://www.reddit.com/r/oratory1990/) — misurazioni cuffie e ricerca

## 💖 Supporta lo sviluppo

- ☕ [Ko-fi](https://ko-fi.com/denzam)
- 🍺 [Buy Me a Coffee](https://buymeacoffee.com/denzam)
- 💝 [GitHub Sponsors](https://github.com/sponsors/denzam)

## 📧 Contatti

- **GitHub**: [@denzam](https://github.com/denzam)
- **Issues / Domande**: [GitHub Issues](https://github.com/denzam/SystemEQ-for-Mac/issues)

---

Fatto con ❤️ per la comunità audio
