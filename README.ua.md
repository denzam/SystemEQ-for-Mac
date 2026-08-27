# SystemEQ for Mac

Безкоштовний open-source системний параметричний еквалайзер для macOS 13+

Налаштовуй будь-який звук на Mac — Spotify, YouTube, Apple Music та інше.
10/31-смуговий EQ, база AutoEQ для 8 665 моделей навушників, калібрація слуху,
інструменти для кімнати й візуалізатор у реальному часі. Без підписок і телеметрії.

[![macOS](https://img.shields.io/badge/macOS-13%2B-blue)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange)](https://swift.org)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)
[![Download](https://img.shields.io/github/v/release/denzam/SystemEQ-for-Mac?label=download)](https://github.com/denzam/SystemEQ-for-Mac/releases/latest)
[![Website](https://img.shields.io/badge/website-denzam.github.io-black)](https://denzam.github.io/SystemEQ-for-Mac/)

> 🇺🇦 Українська | 🇬🇧 [English](README.md) | 🇮🇹 [Italiano](README.it.md)

![SystemEQ for Mac — головне вікно](Docs/screenshots/01-main.jpeg)

## 📸 Скріншоти

| Головне меню | База AutoEQ | Калібрація | Візуалізатор |
| :---: | :---: | :---: | :---: |
| [![Головне меню](Docs/screenshots/01-main.jpeg)](Docs/screenshots/01-main.jpeg) | [![AutoEQ](Docs/screenshots/07-autoeq-library.png)](Docs/screenshots/07-autoeq-library.png) | [![Калібрація](Docs/screenshots/02-calibration-mode.png)](Docs/screenshots/02-calibration-mode.png) | [![Візуалізатор](Docs/screenshots/15-visualizer-active.jpeg)](Docs/screenshots/15-visualizer-active.jpeg) |

| Суб’єктивне налаштування кімнати | Пошук резонансів | Пресети для кожного виводу |
| :---: | :---: | :---: |
| [![Налаштування кімнати](Docs/screenshots/04-room-tuning.png)](Docs/screenshots/04-room-tuning.png) | [![Пошук резонансів](Docs/screenshots/05-resonance-sweep.png)](Docs/screenshots/05-resonance-sweep.png) | [![Налаштування](Docs/screenshots/10-settings-language.jpeg)](Docs/screenshots/10-settings-language.jpeg) |

## ✨ Можливості

### Основні функції

- **10/31-смуговий параметричний EQ** — Професійна обробка звуку з biquad-фільтрами
- **База даних AutoEQ** — 8 665 моделей навушників, 8 850 пресетів (SQLite, 18 МБ)
- **Візуалізація в реальному часі** — Спектр, Хвиля, Частинки, Психоделічний
- **Модуль калібрації** — Тест слуху + власні профілі + порівняння A/B
- **Суб'єктивне налаштування кімнати** — Налаштовуй звучання кімнати на слух
- **Пошук резонансів** — Синусоїдальний sweep для пошуку гудіння чи дзвону
- **Інтеграція з BlackHole** — Системне маршрутизування аудіо з автоматичним Setup Assistant
- **Управління пресетами** — Зберігай, завантажуй та організовуй налаштування EQ
- **Авто-пресет для кожного виводу** — За бажанням застосовує збережений пресет після зміни фізичного виходу
- **Запускати при вході** — Необов’язковий Login Item macOS
- **Ховати іконку з Dock** — За бажанням залишає керування лише в меню-барі
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
- Apple Silicon або Intel Mac
- [BlackHole 2ch](https://github.com/ExistentialAudio/BlackHole) (безкоштовний віртуальний аудіодрайвер)
- 4 ГБ RAM (рекомендовано 8 ГБ)

### Встановлення

#### ✅ Рекомендовано: Homebrew — без ручних дій із Gatekeeper

```bash
brew trust denzam/systemeq
brew install --cask denzam/systemeq/systemeq
```

Cask автоматично знімає macOS quarantine-атрибут при встановленні, тому
застосунок запуститься без ручного підтвердження Gatekeeper, потрібного для DMG.
Застосунок усе одно підписаний ad-hoc і не нотаризований.

> **Навіщо `brew trust`?** Починаючи з Homebrew 6.0, сторонні тапи треба
> явно позначити довіреними, інакше Homebrew відмовиться їх завантажувати
> (`Refusing to load cask ... from untrusted tap`). Власник тапу зробити це
> за вас не може. Команда виконується один раз на кожному Mac. На Homebrew 5
> і старіших її пропустіть — там такої команди немає.

#### Варіант 2: Завантажити DMG або ZIP — потрібне ручне підтвердження Gatekeeper

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
   - Натисни **Увімкнути EQ** і тримай SystemEQ запущеним

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

### Налаштування кімнати та пошук резонансів

- **Суб’єктивне налаштування кімнати** допомагає налаштувати звучання кімнати на слух
- **Пошук резонансів** знаходить гудіння чи дзвін, щоб потім створити коригувальний notch-фільтр

### Пресети для різних виходів

У **Налаштуваннях** увімкни **Авто-пресет для кожного виводу**.
SystemEQ запам’ятає пресет для кожного фізичного виходу й застосує його після
перемикання. Там само можна ввімкнути **Запускати при вході**.

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

> Це додає ~10-20ms затримки порівняно з прямим моніторингом. Це архітектурне обмеження маршрутизації через системний драйвер BlackHole.

## 📊 Статус проєкту

SystemEQ має й активно підтримує основні можливості: EQ, маршрутизацію,
калібрацію, AutoEQ, пресети для різних виходів і візуалізатор.

## 🩺 Усунення несправностей

### `Error: Refusing to load cask ... from untrusted tap`

Homebrew 6.0 не завантажує сторонні тапи, поки ви не позначите їх довіреними, і
власник тапу зробити це за вас не може. Виконайте один раз на кожному Mac, а далі
встановлюйте чи оновлюйте як завжди:

```bash
brew trust denzam/systemeq
brew upgrade --cask systemeq   # або: brew install --cask denzam/systemeq/systemeq
```

У Homebrew 5 і старіших команди `trust` не існує — пропустіть її.

### Після оновлення застосунок знову просить доступ до мікрофона

Так і має бути. SystemEQ підписаний ad-hoc, тому підпис змінюється при кожній
збірці і macOS вважає оновлення новим застосунком. Видайте дозвіл ще раз у
**Системних налаштуваннях → Конфіденційність і безпека → Мікрофон**.

### macOS пише, що застосунок «неможливо відкрити»

Застосунок не нотаризований — див. розділ «Безпека» нижче.
Клацніть на ньому правою кнопкою → **Відкрити** → підтвердьте, або виконайте:

```bash
xattr -dr com.apple.quarantine "/Applications/SystemEQ for Mac.app"
```

Встановлення через Homebrew цього уникає — Cask знімає позначку сам.

### Немає звуку після налаштування

У **Routing** обери BlackHole як вхід, а навушники або колонки — як вихід.
Встанови **BlackHole 2ch** системним виходом macOS, натисни **Увімкнути EQ**
і тримай SystemEQ запущеним.

### Після перемикання на BlackHole звук тихіший

macOS зберігає окрему гучність для кожного вихідного пристрою. Після
перемикання на BlackHole підніми системну гучність клавішами або в налаштуваннях звуку macOS.

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
Закриті форки заборонені; комерційне поширення можливе лише з дотриманням
умов GPLv3 щодо вихідного коду та ліцензії.

Сторонні компоненти та їхні ліцензії — у [THIRDPARTY.md](THIRDPARTY.md).

## 🙏 Подяки

- [AutoEQ](https://github.com/jaakkopasanen/AutoEq) від Jaakko Pasanen — база даних пресетів EQ
- [BlackHole](https://github.com/ExistentialAudio/BlackHole) від Existential Audio — віртуальний аудіодрайвер
- [oratory1990](https://www.reddit.com/r/oratory1990/) — вимірювання навушників та дослідження

Окрема подяка **Michel**, **Renato**, **David** та **Alberto** за підтримку та поради впродовж розробки.

## 💖 Підтримати розробку

- 🍺 [Buy Me a Coffee](https://buymeacoffee.com/denzam)
- 💝 [GitHub Sponsors](https://github.com/sponsors/denzam)

## 📧 Контакти

- **GitHub**: [@denzam](https://github.com/denzam)
- **Issues / Питання**: [GitHub Issues](https://github.com/denzam/SystemEQ-for-Mac/issues)

---

Зроблено з ❤️ для аудіоспільноти
