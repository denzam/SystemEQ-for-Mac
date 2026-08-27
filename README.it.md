# SystemEQ for Mac

Equalizzatore parametrico gratuito e open source a livello di sistema per macOS 13+

Regola ogni suono del Mac — Spotify, YouTube, Apple Music e altro.
EQ a 10/31 bande, database AutoEQ per 8.665 modelli di cuffie, calibrazione
dell'udito, strumenti per l'ambiente e visualizzatore in tempo reale. Nessun abbonamento o telemetria.

[![macOS](https://img.shields.io/badge/macOS-13%2B-blue)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange)](https://swift.org)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)
[![Download](https://img.shields.io/github/v/release/denzam/SystemEQ-for-Mac?label=download)](https://github.com/denzam/SystemEQ-for-Mac/releases/latest)
[![Website](https://img.shields.io/badge/website-denzam.github.io-black)](https://denzam.github.io/SystemEQ-for-Mac/)

> 🇮🇹 Italiano | 🇬🇧 [English](README.md) | 🇺🇦 [Українська](README.ua.md)

![SystemEQ for Mac — finestra principale](Docs/screenshots/01-main.jpeg)

## 📸 Schermate

| Menu principale | Database AutoEQ | Calibrazione | Visualizzatore |
| :---: | :---: | :---: | :---: |
| [![Menu principale](Docs/screenshots/01-main.jpeg)](Docs/screenshots/01-main.jpeg) | [![AutoEQ](Docs/screenshots/07-autoeq-library.png)](Docs/screenshots/07-autoeq-library.png) | [![Calibrazione](Docs/screenshots/02-calibration-mode.png)](Docs/screenshots/02-calibration-mode.png) | [![Visualizzatore](Docs/screenshots/15-visualizer-active.jpeg)](Docs/screenshots/15-visualizer-active.jpeg) |

| Regolazione Soggettiva Stanza | Trova Risonanze | Preset per uscita |
| :---: | :---: | :---: |
| [![Regolazione ambiente](Docs/screenshots/04-room-tuning.png)](Docs/screenshots/04-room-tuning.png) | [![Ricerca risonanze](Docs/screenshots/05-resonance-sweep.png)](Docs/screenshots/05-resonance-sweep.png) | [![Impostazioni](Docs/screenshots/10-settings-language.jpeg)](Docs/screenshots/10-settings-language.jpeg) |

## ✨ Funzionalità

### Funzioni principali

- **EQ Parametrico 10/31 bande** — Elaborazione audio professionale con filtri biquad
- **Database AutoEQ** — 8.665 modelli di cuffie, 8.850 preset (SQLite, 18 MB)
- **Visualizzazione in tempo reale** — Spettro, Forma d'onda, Particelle, Psichedelico
- **Modulo di calibrazione** — Test dell'udito + profili personalizzati + confronto A/B
- **Regolazione Soggettiva Stanza** — Regola la risposta della stanza a orecchio
- **Trova Risonanze** — Sweep sinusoidale per trovare frequenze rimbombanti o squillanti
- **Integrazione BlackHole** — Routing audio di sistema con Setup Assistant automatico
- **Gestione preset** — Salva, carica e organizza le impostazioni EQ
- **Cambio preset automatico per uscita** — Facoltativamente riapplica il preset salvato quando cambi uscita fisica
- **Avvia al login** — Login Item opzionale di macOS
- **Nascondi icona dal Dock** — Mantiene il controllo nella barra dei menu
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
- Apple Silicon o Mac Intel
- [BlackHole 2ch](https://github.com/ExistentialAudio/BlackHole) (driver audio virtuale gratuito)
- 4 GB RAM (8 GB consigliati)

### Installazione

#### ✅ Consigliato: Homebrew — nessun passaggio manuale con Gatekeeper

```bash
brew trust denzam/systemeq
brew install --cask denzam/systemeq/systemeq
```

Il Cask rimuove l'attributo macOS di quarantena durante l'installazione, quindi
l'app si avvia senza la conferma manuale di Gatekeeper richiesta dal DMG.
L'app resta firmata ad-hoc e non è notarizzata.

> **Perché `brew trust`?** Da Homebrew 6.0 i tap di terze parti devono essere
> considerati attendibili in modo esplicito, altrimenti Homebrew si rifiuta di
> caricarli (`Refusing to load cask ... from untrusted tap`). Il proprietario
> del tap non può farlo al posto tuo. Il comando va eseguito una sola volta per
> Mac. Su Homebrew 5 e precedenti saltalo: quel comando non esiste.

#### Opzione 2: Scarica DMG o ZIP — serve la conferma manuale di Gatekeeper

1. Scarica l'ultimo `.dmg` o `.zip` dalle [Releases](https://github.com/denzam/SystemEQ-for-Mac/releases)
2. Apri il DMG e trascina `SystemEQ for Mac.app` nella cartella Applicazioni (`/Applications`)
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
   - Fai clic su **Abilita EQ** e mantieni SystemEQ in esecuzione

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

### Regolazione Soggettiva Stanza e Trova Risonanze

- Usa **Regolazione Soggettiva Stanza** per impostare la risposta della stanza a orecchio
- Usa **Trova Risonanze** per trovare frequenze rimbombanti o squillanti e creare un filtro notch correttivo

### Preset per uscita

In **Impostazioni**, abilita **Cambio automatico del preset per uscita**.
SystemEQ ricorda il preset applicato a ogni uscita fisica e lo riapplica quando
cambi dispositivo. Qui puoi anche abilitare **Avvia al login**.

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

> Questo aggiunge ~10-20ms di latenza extra rispetto al monitoraggio diretto. È un limite architetturale del routing tramite il driver di sistema BlackHole.

## 📊 Stato del progetto

SystemEQ include e mantiene attivamente le funzioni principali di EQ, routing,
calibrazione, AutoEQ, preset per uscita e visualizzatore.

## 🩺 Risoluzione dei problemi

### `Error: Refusing to load cask ... from untrusted tap`

Homebrew 6.0 non carica i tap di terze parti finché non li contrassegni come
attendibili, e il proprietario del tap non può farlo al posto tuo. Esegui questo
comando una volta per Mac, poi installa o aggiorna come sempre:

```bash
brew trust denzam/systemeq
brew upgrade --cask systemeq   # oppure: brew install --cask denzam/systemeq/systemeq
```

Su Homebrew 5 e precedenti il comando `trust` non esiste: saltalo.

### Dopo un aggiornamento l'app chiede di nuovo l'accesso al microfono

È normale. SystemEQ è firmata ad-hoc, quindi la firma cambia a ogni build e macOS
considera ogni aggiornamento come una nuova app. Concedi di nuovo il permesso in
**Impostazioni di Sistema → Privacy e sicurezza → Microfono**.

### macOS dice che l'app "non può essere aperta"

L'app non è notarizzata — vedi la sezione «Nota sulla sicurezza» più sotto.
Fai clic destro sull'app → **Apri** → conferma, oppure esegui:

```bash
xattr -dr com.apple.quarantine "/Applications/SystemEQ for Mac.app"
```

Installando tramite Homebrew questo passaggio non serve: il Cask rimuove il flag.

### Nessun suono dopo la configurazione

In **Routing**, seleziona BlackHole come ingresso e cuffie o altoparlanti come
uscita. Imposta **BlackHole 2ch** come uscita di sistema macOS, fai clic su
**Abilita EQ** e mantieni SystemEQ in esecuzione.

### Il suono è più basso dopo aver selezionato BlackHole

macOS conserva un livello di volume separato per ogni dispositivo di uscita.
Dopo il passaggio a BlackHole, alza il volume di sistema con i tasti della tastiera o nelle Impostazioni audio di macOS.

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
il codice sorgente completo. I fork chiusi non sono permessi; la distribuzione
commerciale resta soggetta agli obblighi GPLv3 sul codice sorgente e sulla licenza.

I componenti di terze parti e le rispettive licenze sono elencati in
[THIRDPARTY.md](THIRDPARTY.md).

## 🙏 Ringraziamenti

- [AutoEQ](https://github.com/jaakkopasanen/AutoEq) di Jaakko Pasanen — database preset EQ
- [BlackHole](https://github.com/ExistentialAudio/BlackHole) di Existential Audio — driver audio virtuale
- [oratory1990](https://www.reddit.com/r/oratory1990/) — misurazioni cuffie e ricerca

Un grazie anche a **Michel**, **Renato**, **David** e **Alberto** per il supporto e i consigli lungo il percorso.

## 💖 Supporta lo sviluppo

- 🍺 [Buy Me a Coffee](https://buymeacoffee.com/denzam)
- 💝 [GitHub Sponsors](https://github.com/sponsors/denzam)

## 📧 Contatti

- **GitHub**: [@denzam](https://github.com/denzam)
- **Issues / Domande**: [GitHub Issues](https://github.com/denzam/SystemEQ-for-Mac/issues)

---

Fatto con ❤️ per la comunità audio
