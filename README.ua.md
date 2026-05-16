# SystemEQ for Mac

Професійний системний еквалайзер для macOS 13+

[![macOS](https://img.shields.io/badge/macOS-13%2B-blue)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange)](https://swift.org)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

> 🇺🇦 Українська | 🇬🇧 [English](README.md) | 🇮🇹 [Italiano](README.it.md)

## ✨ Можливості

### Основні функції

- **10/31-смуговий параметричний EQ** — Професійна обробка звуку з biquad-фільтрами
- **База даних AutoEQ** — 8 665 моделей навушників, 8 850 пресетів (SQLite, 18 МБ)
- **Візуалізація в реальному часі** — Спектр, Хвиля, Частинки, Психоделічний
- **Модуль калібрації** — Тест слуху + власні профілі + порівняння A/B
- **Інтеграція з BlackHole** — Системне маршрутизування аудіо з автоматичним Setup Assistant
- **Управління пресетами** — Зберігай, завантажуй та організовуй налаштування EQ
- **Багатомовність** — Англійська, Італійська, Українська

### Аудіодвигун

- **CoreAudioEngine** — Мала затримка (~5-10ms) через AudioUnit (AUHAL)
- **vDSP Biquad-фільтри** — Фреймворк Accelerate, у 5-10× швидше за скалярний режим
- **Пік-метри** — Моніторинг рівня звуку в реальному часі
- **Захист від кліпінгу** — Автоматичне зменшення підсилення та контроль преампу
- **Підтримка медіаклавіш** — Керування гучністю з клавіатури

### Інтеграція з AutoEQ

- **SQLite-база даних** — Миттєвий офлайн-пошук (<10ms)
- **4-рівневий fallback** — Python-сервер → База → Локальні файли → GitHub
- **ParametricEQ та GraphicEQ** — Повна підтримка форматів

## 🚀 Швидкий старт

### Вимоги

- macOS 13.0 (Ventura) або новіша
- Apple Silicon (M1/M2/M3) або Intel Mac
- [BlackHole 2ch](https://github.com/ExistentialAudio/BlackHole) (безкоштовний віртуальний аудіодрайвер)
- 4 ГБ RAM (рекомендовано 8 ГБ)

### Встановлення

#### Варіант 1: Homebrew (найпростіше — обходить Gatekeeper автоматично)

```bash
brew install --cask denzam/systemeq/systemeq
```

Cask автоматично знімає quarantine-атрибут при встановленні, тому
застосунок запуститься без попередження Gatekeeper.

#### Варіант 2: Завантажити DMG

1. Завантаж останній `.dmg` або `.zip` з [Releases](https://github.com/denzam/SystemEQ-for-Mac/releases)
2. Відкрий DMG і перетягни `SystemEQ for Mac.app` до `/Applications`
3. **Перший запуск (один зі способів):**
   - **Права кнопка → Відкрити → Відкрити** у діалозі підтвердження, або
   - Спробуй запустити, потім **Системні налаштування → Конфіденційність і безпека → Усе одно відкрити**, або
   - В терміналі:
     ```bash
     xattr -dr com.apple.quarantine "/Applications/SystemEQ for Mac.app"
     ```
4. Слідуй **Setup Assistant** для встановлення BlackHole

> Застосунок **ad-hoc підписаний** (безкоштовно, самопідпис) — не нотаризований
> через Apple Developer ID. Тому Gatekeeper показує попередження при першому
> запуску. Це свідомий вибір: SystemEQ безкоштовний і не потребує платної
> Apple Developer програми. Кроки вище — одноразові.

#### Варіант 3: Зібрати з вихідного коду

```bash
git clone https://github.com/denzam/SystemEQ-for-Mac.git
cd "SystemEQ for Mac"
open "SystemEQ for Mac.xcodeproj"
# Натисни Cmd+R для збірки та запуску
```

### Налаштування

1. **Встанови BlackHole** (автоматично через Setup Assistant):
   - Завантаж з [сайту BlackHole](https://existential.audio/blackhole/)
   - Встанови 2-канальну версію
   - Перезапусти SystemEQ після встановлення

2. **Налаштуй маршрутизацію аудіо**:
   - Відкрий SystemEQ → вкладка Routing
   - Обери BlackHole як вхід, твої навушники/колонки як вихід
   - Встанови системний вихід на BlackHole в macOS Sound Settings

3. **Застосуй пресет EQ**:
   - Вкладка AutoEQ → Пошук моделі навушників
   - Натисни "⚡ Quick Import"
   - Або вручну налаштуй смуги у вкладці Equalizer

## 🛠️ Архітектура

```text
Системний вихід → BlackHole 2ch
                       ↓
               CoreAudioEngine (вхід)
                       ↓
            vDSP Biquad EQ обробка
                       ↓
               CoreAudioEngine (вихід)
                       ↓
           Фізичні навушники/колонки
```

**Multi-Output Device не потрібен.** CoreAudioEngine виступає мостом між BlackHole і фізичним виходом.

### Технічні деталі

- **CoreAudioEngine**: Низькорівневий AUHAL dual I/O, lock-free ring buffer
- **BiquadFilterVDSP**: vDSP batch processing, у 5-10× швидше за скалярний
- **SPSCRingBuffer**: Lock-free SPSC буфер з C11 атомарними операціями
- **EQDatabase**: SQLite, 18 МБ, 8 665 моделей навушників

## 📁 Структура проєкту

```text
SystemEQ for Mac/
├── Audio/              # Обробка Core Audio
│   ├── CoreAudioEngine.swift
│   ├── AudioRouter.swift
│   ├── BiquadFilterVDSP.swift
│   ├── CalibrationEngine.swift
│   └── SPSCRingBuffer.swift
├── Data/               # Моделі даних та база
│   ├── EQDatabase.swift
│   ├── AutoEQModels.swift
│   └── PresetPersistence.swift
├── Features/           # UI-вікна
│   ├── EqualizerView.swift
│   ├── AutoEQView.swift
│   ├── CalibrationView.swift
│   ├── VisualizerView.swift
│   └── RoutingView.swift
├── DesignSystem/       # Дизайн-токени та компоненти
├── Resources/          # Ресурси та база даних
│   └── EQDatabase.db
└── Docs/               # Документація
```

## 🎯 Використання

### Еквалайзер

- Регулюй частотні смуги слайдерами
- Перемикайся між 10-смуговим і 31-смуговим режимом
- Зберігай власні пресети для швидкого виклику
- Застосовуй авто-преамп для захисту від кліпінгу

### Пресети AutoEQ

1. Знайди модель своїх навушників (доступно 8 665)
2. Обери пресет (oratory1990, Crinacle тощо)
3. Натисни "⚡ Quick Import"
4. За потреби скорегуй підсилення басів

### Калібрація

1. Запусти тест слуху (31 частота)
2. Відрегулюй гучність для кожної частоти відносно еталону
3. Збережи профіль для автоматичного застосування
4. Використовуй порівняння A/B для оцінки профілів

### Візуалізатор

- Обери один з 4 стилів: Spectrum, Waveform, Particles, Psychedelic
- Налаштуй інтенсивність (0–100%)
- FFT в реальному часі при 60 FPS

## 🎚️ Сумісність з DAW (Reaper, Logic, Ableton та інші)

SystemEQ обробляє **системний аудіовихід**. DAW зазвичай обходять системний вихід і звертаються напряму до аудіоінтерфейсу — тому EQ **не застосовується** за замовчуванням.

| Сценарій | EQ застосовується? |
| --- | --- |
| Spotify, YouTube, Apple Music | ✅ Так |
| DAW → Системний вихід (ручне налаштування) | ✅ Так |
| DAW → Аудіоінтерфейс напряму (типово) | ❌ Ні |
| Моніторинг через Scarlett/Focusrite | ❌ Ні |

### Як використовувати SystemEQ разом з DAW

1. У DAW встанови **вихідний пристрій на BlackHole 2ch**
2. SystemEQ застосує EQ і передасть аудіо на фізичний вихід
3. Щоб повернутися до прямого моніторингу — встанови вихід DAW назад на інтерфейс

**Reaper:** Options → Preferences → Audio → Device → BlackHole 2ch

**Logic:** Preferences → Audio → Output Device → BlackHole 2ch

**Ableton:** Preferences → Audio → Output Device → BlackHole 2ch

> Це додає ~10-20ms затримки порівняно з прямим моніторингом. Архітектурне обмеження BlackHole (системний драйвер). Майбутня версія як HAL Audio Plugin вирішила б цю проблему, але потребує платного Apple Developer акаунту.

## 📊 Статус проєкту

- ✅ Фаза 1: Core EQ + маршрутизація BlackHole
- ✅ Фаза 2: Калібрація + Візуалізатор
- ✅ Фаза 3: Інтеграція бази AutoEQ (8 665 моделей)
- ⏭️ Фаза 4: HAL плагін (потребує платного Apple Developer акаунту)
- ⏭️ Фаза 5: Liquid Glass візуальне оформлення

## ⚠️ Безпека

- Застосунок **не sandboxed** (несумісно з CoreAudio/AUHAL віртуальними пристроями)
- **Без телеметрії, аналітики та збору даних** — всі дані залишаються на твоєму Mac
- Встановлюй лише з офіційних [GitHub Releases](https://github.com/denzam/SystemEQ-for-Mac/releases)
- Ad-hoc підпис — права кнопка → Відкрити при першому запуску для обходу Gatekeeper

## 🤝 Внесок у проєкт

1. Зроби fork проєкту
2. Створи гілку для функції (`git checkout -b feature/AmazingFeature`)
3. Збережи зміни (`git commit -m 'Add AmazingFeature'`)
4. Надішли гілку (`git push origin feature/AmazingFeature`)
5. Відкрий Pull Request

## 📄 Ліцензія

**GNU General Public License v3.0** — див. [LICENSE](LICENSE).

SystemEQ — вільне програмне забезпечення. Ти можеш використовувати,
змінювати та розповсюджувати його, але **будь-який форк чи похідна
робота** мусить бути випущена під GPLv3 з відкритим вихідним кодом.
Закриті чи платні комерційні форки заборонені.

Сторонні компоненти та їхні ліцензії — у [THIRDPARTY.md](THIRDPARTY.md).

## 🙏 Подяки

- [AutoEQ](https://github.com/jaakkopasanen/AutoEq) від Jaakko Pasanen — база даних пресетів EQ
- [BlackHole](https://github.com/ExistentialAudio/BlackHole) від Existential Audio — віртуальний аудіодрайвер
- [oratory1990](https://www.reddit.com/r/oratory1990/) — вимірювання навушників та дослідження

## 💖 Підтримати розробку

- ☕ [Ko-fi](https://ko-fi.com/denzam)
- 🍺 [Buy Me a Coffee](https://buymeacoffee.com/denzam)
- 💝 [GitHub Sponsors](https://github.com/sponsors/denzam)

## 📧 Контакти

- **GitHub**: [@denzam](https://github.com/denzam)
- **Issues / Питання**: [GitHub Issues](https://github.com/denzam/SystemEQ-for-Mac/issues)

---

Зроблено з ❤️ для аудіоспільноти
