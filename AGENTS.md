# AGENTS.md — SystemEQ for Mac

Технічні інструкції для будь-якого AI-агента (Codex, Claude Code, інші). Єдине джерело правди для репозиторію.

## Проект

macOS-застосунок системного параметричного еквалайзера. Перехоплює системний звук через BlackHole 2ch, застосовує biquad-фільтри, виводить на фізичний пристрій. Візуалізатор — ProjectM в окремому helper-процесі (IPC через Unix-socket). MVP завершено (грудень 2025).

**Стек:** Swift 5.9 / SwiftUI, CoreAudio / AUHAL, vDSP, SQLite3 (FTS5), Combine, AppKit, BlackHole 2ch, ProjectM.
**Збірка:** Xcode 16.2+, чистий Xcode-проект (немає `Package.swift`). Локалізація EN/IT/UK у рантаймі.

```
xcodebuild test -project "SystemEQ for Mac.xcodeproj" -scheme "SystemEQ for Mac" -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO -quiet
```

**Дистрибуція:** open source, GPLv3. GitHub Releases (DMG + ZIP) + Homebrew tap `denzam/homebrew-systemeq` (авто-синк релізним workflow). **НЕ App Store** — AUHAL/BlackHole несумісні з sandbox. **Без Apple Developer ID** (свідоме рішення користувача, не пропонувати) — збірка ad-hoc signed без нотаризації; обхід Gatekeeper задокументовано в README і release notes. Донати ОК; платної версії не буде.

Користувач перевіряє UI сам на реальному Mac. Зміни мають бути малими й сфокусованими; не полірувати UI без окремого запиту.

## Ключові файли

| Файл | Роль |
|---|---|
| `SystemEQ_for_MacApp.swift` | Точка входу, ініціалізація синглтонів |
| `Audio/CoreAudioEngine.swift` | AUHAL dual I/O, render callback |
| `Audio/BiquadFilterVDSP.swift` | **Продакшн-фільтр** (справжній vDSP_biquad, hot path) — не замінювати на `BiquadFilter.swift` |
| `Audio/AudioRouter.swift` | Роутинг, sleep/wake, unplug, стейт-машина повернення виходу |
| `Audio/SPSCRingBuffer.swift` | Lock-free буфер між AUHAL-пристроями |
| `Audio/PeakMeter.swift` | Рівні pre/post-EQ, тротлінг публікацій в UI |
| `Data/EQDatabase.swift` | SQLite-клієнт, FTS5-пошук пресетів |
| `Data/AutoEQModels.swift` | `EQPreset`, `ParametricBand`, `FilterType` |
| `AutoEQ/EQConverter.swift` | Утиліта конвертації AutoEQ-пресетів (тестований backlog, не підключений до UI) |
| `ProjectMHelper/IPCServer.swift` | Серверна частина IPC helper-процесу |
| `Visualizer/ProjectM/ProjectMHelperClient.swift` | Клієнт IPC з боку застосунку |
| `Config/AppConstants.swift` | URL, sample rate, назви пристроїв |
| `DesignSystem/AppDesign.swift` | Дизайн-токени, glass-ефекти |
| `LocalizationManager.swift` | Перемикання мови EN/IT/UK в рантаймі |
| `Localization/` | Мовні словники (`Translations_EN/IT/UK.swift`) |
| `Infra/WindowCoordinator.swift` | Реєстрація вікон, управління фокусом |

## Конвенції

- **Логування:** тільки `dlog(_, category:)` — не `print()` (єдиний виняток — `Utils/DebugLogger.swift`, де `print` є термінальним стоком виводу в консоль; виклик `dlog` всередині `log()` створив би нескінченну рекурсію). Заборонено в audio render callback.
- **Локалізація:** тільки `LocalizationManager.shared.text(for: .ключ)` — не хардкодити рядки.
- **Атоміки:** тільки C11 `<stdatomic.h>` через bridging headers (`SEQAtomicInt32` / `PMAtomicInt32`). OSAtomic заборонено (deprecated).
- **Feature flags:** перевіряти `FeatureRegistry` перед реалізацією нових фіч.
- **Секції:** `// MARK: - Назва` у кожному файлі. Hot path позначати `// ⚡`, thread safety — `// 🔧`.
- **Роутер задач:** перед суттєвими змінами запустити `.agents/skills/task-router/scripts/route.py` для перевірки ризику (якщо `plan_required` — обов'язковий план).
- SwiftFormat перевіряється в CI (Code Quality workflow), конфіг — `.swiftformat`; прожени перед комітом.
- Pre-commit хук лежить у `.githooks/` і вмикається один раз на клон: `git config core.hooksPath .githooks`. Він форматує staged-файли й ганяє ті самі гейти, що CI. Шляхи проекту містять пробіли — у скриптах завжди лапки та `-z`/`read -d ''`, інакше цикл мовчки пропускає всі файли.

## Критично: реальний час і продуктивність

- Render callback: без алокацій, без локів, без логування, без Objective-C/Swift-runtime викликів.
- `BiquadFilterVDSP` — vDSP batch processing; параметри фільтрів міняються lock-free swap'ом з дебаунсом — не додавати синхронних оновлень з UI.
- `SPSCRingBuffer` — lock-free, без алокацій. Не змінювати розмір і семантику.
- `PeakMeter` публікує в UI з тротлінгом — по-семпловий republish колись створював CPU storm, не повертати.
- ProjectM: усі GL-виклики строго з одного потоку; єдиний реальний важіль продуктивності — render scale (не мікрооптимізації шейдерів); FPS обмежено свідомо.
- IPC: сокет доступний лише поточному користувачу; відповіді бувають великими — обробляти partial reads до кінця; Float-payload копіювати через `memcpy` (вирівнювання адрес).

## Верифікація та поглиблений аудит

- **Поглиблене рев'ю за тригером «перевір себе»:** щоб не витрачати зайві токени на кожній ітерації, повноцінне незалежне рев'ю (через сабагента `independent-review` або суворий ворожий аудит) запускається **за явною командою користувача «перевір себе»** (або коли користувач окремо просить провести рев'ю чи перевірку).
- **Не довіряти сліпо "тести пройшли":** проходження тестів (138/138) не симулює реальне аудіозалізо чи крайові математичні стани.
- **Обов'язковий чекліст для аудиту («перевір себе»):**
  - **Крайові семпли:** перевіряти 0 та 1 семпл у кільцевому буфері, граничні умови інтерполяції (`avail == requiredFrames`), читання за межами записаного вікна, захист від IEEE 754 `NaN`/`Inf` (`NaN * 0.0 == NaN`).
  - **Апаратні незбіги (Hardware variability):** ніколи не блокувати сетап (`return` / `abort`) через незбіг розмірів буферів входу і виходу (AirPods, USB-ЦАП, HDMI часто мають фіксовані розміри) — кільцевий буфер має толерувати різні розміри блоків.
  - **Каскадний вплив:** при зміні `sampleRate` або конфігурації перевіряти перерахунок УСІХ залежних фільтрів (кімнатні notch-фільтри, EQ пресети, дебаунси).
  - **Життєвий цикл:** перевіряти подвійні деалокації між таймерами, cancel-хендлерами та `deinit`.
- **Цільові тести:** при запиті перевірки або модифікації низькорівневого аудіо перевіряти чи писати тест на граничні умови.

## База EQ

- `SystemEQ for Mac/Resources/EQDatabase.db` — **єдина** копія в таргеті. Друга копія в іншому шляху = duplicate resource, CI падає.
- Оновлюється scheduled-workflow'ом (щомісячний PR від бота) — не редагувати вручну.
- Відкривати read-only; text-колонки можуть бути NULL; пунктуацію в FTS5-запитах екранувати.
- 18.8 MB blob бази в git-історії — відомо, не чистити (потребує переписування публічної історії).

## Git

- Коміти: `fix(scope): ...` / `feat:` / `chore:` / `perf:`, малі й тематичні. Subject описує видимий симптом, не внутрішню механіку.
- **Ніколи не змішувати** зміни логіки з реліз-комітом: бамп версії + CHANGELOG + workflow — окремий коміт без коду.
- `git push`, теги, релізи — **тільки після явного ОК користувача**.
- Новий `.swift`-файл: перевір, що він затрекан у git — локальна збірка проходить і без цього, CI ні.
- `.claude/`, `.agents/`, `Docs/internal/` — у `.gitignore`, не комітити. Виняток: `.agents/skills/` трекається — це джерельний код інструкцій, а не локальний стан.

## Реліз (порядок обовʼязковий)

1. Всі зміни закомічені тематично, тести зелені локально.
2. Окремий реліз-коміт: `MARKETING_VERSION` (обидва таргети) + `Config/ProjectMHelper/Info.plist` + `CHANGELOG.md`.
3. Push у `main`, дочекатися зеленого Code Quality CI.
4. Лише після зеленого CI — тег `vX.Y.Z`. Тег не пересувати.
5. Release workflow збирає DMG/ZIP у чистому середовищі (тести — gate перед публікацією) і авто-синкає Homebrew tap.
6. У тіло GitHub-релізу вручну вставити секцію з `CHANGELOG.md`: `generate_release_notes` бачить лише merged PR, прямі коміти в notes не потрапляють.
