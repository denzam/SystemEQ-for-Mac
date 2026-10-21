SystemEQ for Mac — Installation

Packages distributed by the signed release workflow require Developer ID
signatures, Apple notarization and Gatekeeper validation before publication.
Older releases and local development builds may use ad-hoc signing.

ENGLISH

1. Drag “SystemEQ for Mac” to Applications.
2. Open the app normally.
3. Follow the Welcome screen and allow the requested audio permission.
   Signing and notarization do not grant this permission automatically.
   On macOS 14.4+, Automatic tries Native capture, which needs System Audio
   Recording permission. BlackHole is used on macOS 13–14.3 or as a fallback;
   its virtual audio input requires Microphone permission.
4. If a signed release is blocked, download it again from the official release
   page and report the exact macOS message and app version.

ITALIANO

1. Trascina “SystemEQ for Mac” nella cartella Applicazioni.
2. Apri normalmente l’app.
3. Segui la schermata di benvenuto e concedi il permesso audio richiesto.
   Firma e notarizzazione non concedono questo permesso automaticamente.
   Su macOS 14.4+, Automatico prova il motore nativo, che richiede il permesso
   di registrare l’audio di sistema. BlackHole serve su macOS 13–14.3 o come
   fallback; il suo ingresso virtuale richiede il permesso Microfono.
4. Se una versione firmata è bloccata, scaricala di nuovo dalla pagina ufficiale
   e segnala il messaggio esatto di macOS e la versione dell’app.

УКРАЇНСЬКА

1. Перетягни “SystemEQ for Mac” у папку Програми (Applications).
2. Відкрий застосунок звичайним способом.
3. Пройди екран привітання та надай запитаний дозвіл на аудіо.
   Підпис і нотаризація не надають цього дозволу автоматично.
   На macOS 14.4+ Автоматично пробує нативне захоплення, якому потрібен дозвіл
   на запис системного аудіо. BlackHole потрібен на macOS 13–14.3 або як
   резервний маршрут; його віртуальний вхід потребує доступу до мікрофона.
4. Якщо підписаний реліз заблоковано, завантаж його повторно з офіційної
   сторінки та повідом точний текст попередження macOS і версію застосунку.

Official releases: https://github.com/denzam/SystemEQ-for-Mac/releases
Homebrew: brew install --cask denzam/systemeq/systemeq
