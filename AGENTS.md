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
| `AutoEQ/EQConverter.swift` | Конвертація AutoEQ-пресетів |
| `ProjectMHelper/IPCServer.swift` | Серверна частина IPC helper-процесу |
| `Visualizer/ProjectM/ProjectMHelperClient.swift` | Клієнт IPC з боку застосунку |
| `Config/AppConstants.swift` | URL, sample rate, назви пристроїв |
| `DesignSystem/AppDesign.swift` | Дизайн-токени, glass-ефекти |
| `LocalizationManager.swift` | Перемикання мови EN/IT/UK в рантаймі |
| `Infra/WindowCoordinator.swift` | Реєстрація вікон, управління фокусом |

## Конвенції

- **Логування:** тільки `dlog(_, category:)` — не `print()`. Заборонено в audio render callback.
- **Локалізація:** тільки `LocalizationManager.shared.text(for: .ключ)` — не хардкодити рядки.
- **Атоміки:** тільки C11 `<stdatomic.h>` через bridging headers (`SEQAtomicInt32` / `PMAtomicInt32`). OSAtomic заборонено (deprecated).
- **Feature flags:** перевіряти `FeatureRegistry` перед реалізацією нових фіч.
- **Секції:** `// MARK: - Назва` у кожному файлі. Hot path позначати `// ⚡`, thread safety — `// 🔧`.
- SwiftFormat перевіряється в CI (Code Quality workflow), конфіг — `.swiftformat`; прожени перед комітом.

## Критично: реальний час і продуктивність

- Render callback: без алокацій, без локів, без логування, без Objective-C/Swift-runtime викликів.
- `BiquadFilterVDSP` — vDSP batch processing; параметри фільтрів міняються lock-free swap'ом з дебаунсом — не додавати синхронних оновлень з UI.
- `SPSCRingBuffer` — lock-free, без алокацій. Не змінювати розмір і семантику.
- `PeakMeter` публікує в UI з тротлінгом — по-семпловий republish колись створював CPU storm, не повертати.
- ProjectM: усі GL-виклики строго з одного потоку; єдиний реальний важіль продуктивності — render scale (не мікрооптимізації шейдерів); FPS обмежено свідомо.
- IPC: сокет доступний лише поточному користувачу; відповіді бувають великими — обробляти partial reads до кінця; Float-payload копіювати через `memcpy` (вирівнювання адрес).

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
- `.claude/`, `Docs/internal/` — у `.gitignore`, не комітити.

## Реліз (порядок обовʼязковий)

1. Всі зміни закомічені тематично, тести зелені локально.
2. Окремий реліз-коміт: `MARKETING_VERSION` (обидва таргети) + `Config/ProjectMHelper/Info.plist` + `CHANGELOG.md`.
3. Push у `main`, дочекатися зеленого Code Quality CI.
4. Лише після зеленого CI — тег `vX.Y.Z`. Тег не пересувати.
5. Release workflow збирає DMG/ZIP у чистому середовищі (тести — gate перед публікацією) і авто-синкає Homebrew tap.
6. У тіло GitHub-релізу вручну вставити секцію з `CHANGELOG.md`: `generate_release_notes` бачить лише merged PR, прямі коміти в notes не потрапляють.
