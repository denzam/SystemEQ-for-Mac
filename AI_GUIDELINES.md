# AI Guidelines — SystemEQ for Mac

## Правила поведінки (економія токенів)
- Відповіді короткі, без вступів і підтверджень типу "Зрозумів!", "Звичайно!"
- Не повторюй умову задачі назад
- Не пиши коментарі в коді якщо я явно не прошу
- Читай тільки ті файли, які безпосередньо потрібні для задачі
- Не переписуй код що не стосується задачі
- Перед змінами що торкаються 3+ файлів одночасно — покажи план і чекай моє ОК
- Якщо потрібна інформація — задай одне питання, не кілька одразу

---

## Проект

macOS-застосунок параметричного еквалайзера. Перехоплює системний звук через BlackHole 2ch, застосовує biquad-фільтри, виводить на фізичний пристрій. MVP завершено (грудень 2025).

**Стек:** Swift 5.9 / SwiftUI, CoreAudio / AUHAL, vDSP, SQLite3, Combine, AppKit, BlackHole 2ch, ProjectM.  
**Збірка:** Xcode 16.2+, чистий Xcode-проект (немає `Package.swift`).

---

## Ключові файли

| Файл | Роль |
|---|---|
| `SystemEQ_for_MacApp.swift` | Точка входу, ініціалізація синглтонів |
| `Audio/CoreAudioEngine.swift` | AUHAL dual I/O, render callback |
| `Audio/BiquadFilterVDSP.swift` | **Продакшн-фільтр** (vDSP, hot path) — не замінювати на `BiquadFilter.swift` |
| `Audio/AudioRouter.swift` | Перелік пристроїв, виявлення BlackHole |
| `Audio/SPSCRingBuffer.swift` | Lock-free буфер між AUHAL-пристроями |
| `Data/EQDatabase.swift` | SQLite-клієнт, пошук пресетів |
| `Data/AutoEQModels.swift` | `EQPreset`, `ParametricBand`, `FilterType` |
| `Config/AppConstants.swift` | URL, sample rate, назви пристроїв |
| `DesignSystem/AppDesign.swift` | Дизайн-токени, glass-ефекти |
| `LocalizationManager.swift` | Перемикання мови EN/IT/UK в рантаймі |
| `Infra/WindowCoordinator.swift` | Реєстрація вікон, управління фокусом |

---

## Конвенції

- **Логування:** тільки `dlog(_, category:)` — не `print()`. Заборонено в audio render callback.
- **Локалізація:** тільки `LocalizationManager.shared.text(for: .ключ)` — не хардкодити рядки.
- **Feature flags:** перевіряти `FeatureRegistry` перед реалізацією нових фіч.
- **Секції:** `// MARK: - Назва` у кожному файлі.
- **Performance annotations:** `// ⚡` для hot path, `// 🔧` для thread safety.

---

## Критично для продуктивності

- `BiquadFilterVDSP` — vDSP batch processing, 5–10× швидше. Не замінювати.
- `SPSCRingBuffer` — lock-free, без алокацій. Не змінювати розмір.
- Hot path: без логування, без алокацій, без блокувань.
