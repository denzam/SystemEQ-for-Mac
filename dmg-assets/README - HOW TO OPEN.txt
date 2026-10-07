════════════════════════════════════════════════════════════════
  SystemEQ for Mac — How to open on first launch
════════════════════════════════════════════════════════════════

This app is open-source and NOT signed with an Apple Developer ID
(the project does not pay Apple's $99/year fee). macOS will block
the first launch with a "cannot be opened" or "damaged" message.
This is normal. Follow the steps below.

────────────────────────────────────────────────────────────────
  ENGLISH
────────────────────────────────────────────────────────────────

STEP 1. Drag "SystemEQ for Mac" to the Applications folder.

STEP 2. Open Applications, RIGHT-CLICK on "SystemEQ for Mac",
        choose "Open", then click "Open" again in the dialog.

  If you only see "Move to Trash" / "cannot be opened":
    -> Open System Settings -> Privacy & Security
    -> Scroll down to the Security section
    -> You will see: "SystemEQ for Mac was blocked..."
    -> Click "Open Anyway"
    -> Confirm with your Mac password / Touch ID

STEP 3. (Optional, fastest) Open Terminal and paste:
    xattr -dr com.apple.quarantine "/Applications/SystemEQ for Mac.app"
    Then double-click the app normally.

STEP 4. Follow the Welcome screen and allow the requested audio permission.
        On macOS 14.4+, Automatic tries Native capture without BlackHole.
        Native capture needs System Audio Recording permission.
        BlackHole is needed on macOS 13-14.3 or when Native cannot start
        in Automatic mode; its virtual audio input needs Microphone permission.
        Settings -> Audio Engine lets you choose the backend.

────────────────────────────────────────────────────────────────
  ITALIANO
────────────────────────────────────────────────────────────────

PASSO 1. Trascina "SystemEQ for Mac" nella cartella Applicazioni.

PASSO 2. Apri Applicazioni, CLIC DESTRO su "SystemEQ for Mac",
         scegli "Apri", poi clicca di nuovo "Apri" nella finestra.

  Se vedi solo "Sposta nel Cestino" / "non puo' essere aperto":
    -> Apri Impostazioni di Sistema -> Privacy e Sicurezza
    -> Scorri fino alla sezione Sicurezza
    -> Vedrai: "SystemEQ for Mac e' stato bloccato..."
    -> Clicca "Apri comunque"
    -> Conferma con password / Touch ID

PASSO 3. (Opzionale, piu' veloce) Apri Terminale e incolla:
    xattr -dr com.apple.quarantine "/Applications/SystemEQ for Mac.app"
    Poi fai doppio clic sull'app normalmente.

PASSO 4. Segui la schermata di benvenuto e consenti il permesso audio richiesto.
         Su macOS 14.4+, Automatico prova l'acquisizione nativa senza BlackHole.
         L'acquisizione nativa richiede il permesso di registrare l'audio di sistema.
         BlackHole serve su macOS 13-14.3 o se il motore nativo non si avvia
         in modalita' Automatico; il suo ingresso virtuale richiede il permesso Microfono.
         Impostazioni -> Motore audio permette di scegliere il backend.

────────────────────────────────────────────────────────────────
  УКРАЇНСЬКА
────────────────────────────────────────────────────────────────

КРОК 1. Перетягни "SystemEQ for Mac" у папку Програми (Applications).

КРОК 2. Відкрий Програми, ПРАВИЙ КЛІК на "SystemEQ for Mac",
        обери "Відкрити", потім ще раз "Відкрити" у вікні.

  Якщо бачиш тільки "Перенести в Кошик" / "не може бути відкрито":
    -> Відкрий Системні параметри -> Конфіденційність і безпека
    -> Прокрути до секції Безпека
    -> Побачиш: "SystemEQ for Mac було заблоковано..."
    -> Натисни "Відкрити все одно"
    -> Підтверди паролем / Touch ID

КРОК 3. (Опціонально, найшвидше) Відкрий Termінал і встав:
    xattr -dr com.apple.quarantine "/Applications/SystemEQ for Mac.app"
    Потім подвійний клік як зазвичай.

КРОК 4. Пройди екран привітання та надай запитаний дозвіл на аудіо.
        На macOS 14.4+ Автоматично спершу пробує нативне захоплення без BlackHole.
        Нативному захопленню потрібен дозвіл на запис системного аудіо.
        BlackHole потрібен на macOS 13-14.3 або якщо нативний рушій не запускається
        в автоматичному режимі; його віртуальний вхід потребує доступу до мікрофона.
        Налаштування -> Аудіорушій дозволяють вибрати backend.

════════════════════════════════════════════════════════════════
  Why is this needed?
════════════════════════════════════════════════════════════════

Apple requires a paid Developer ID ($99/year) to skip this dialog.
SystemEQ for Mac is free and open-source — the source code is on
GitHub: https://github.com/denzam/SystemEQ-for-Mac

You only need to do this ONCE. After the first successful launch,
macOS remembers your choice and the app opens normally.

For installation via Homebrew (which handles quarantine automatically):
    brew install --cask denzam/systemeq/systemeq
