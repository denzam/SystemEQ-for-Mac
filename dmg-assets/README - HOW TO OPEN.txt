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

STEP 4. Grant microphone / audio permissions when asked.
        The app needs BlackHole 2ch installed (free, open-source).
        On first launch you will see a Welcome screen explaining setup.

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

PASSO 4. Concedi i permessi microfono / audio quando richiesti.
         L'app richiede BlackHole 2ch (gratuito, open-source).
         Al primo avvio vedrai una schermata di benvenuto.

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

КРОК 4. Дозволь доступ до мікрофона / звуку коли запитає.
        Потрібен BlackHole 2ch (безкоштовно, open-source).
        При першому запуску побачиш екран привітання.

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
