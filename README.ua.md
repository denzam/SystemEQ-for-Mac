# SystemEQ for Mac

Системний еквалайзер для macOS з підтримкою пресетів AutoEQ та персоналізованої калібрації.

## Особливості

- 🎛️ **10/31-смуговий еквалайзер** з реальним часом обробки
- 🎧 **Інтеграція з AutoEQ** - 5000+ пресетів для навушників
- 🔬 **Персоналізована калібрація** слуху
- 🏠 **Калібрація кімнати** з аналізом резонансів
- 📊 **Візуалізатор аудіо** з різними стилями
- 🎛️ **Низька затримка** через Core Audio (5-10ms)
- 💾 **SQLite база даних** для швидкого пошуку пресетів

## Системні вимоги

- macOS 13.0 (Ventura) або новіша
- Apple Silicon (M1/M2/M3) або Intel Mac
- 4GB RAM (рекомендовано 8GB)

## Встановлення

### Автоматичне (рекомендовано)

1. Завантажте останній реліз з [Releases](https://github.com/denyszamorniak/SystemEQ-for-Mac/releases)
2. Відкрийте `.dmg` файл
3. Перетягніть SystemEQ в Applications
4. Запустіть додаток

### Ручне збирання

```bash
git clone https://github.com/denyszamorniak/SystemEQ-for-Mac.git
cd "SystemEQ for Mac"
open "SystemEQ for Mac.xcodeproj"
# Натисніть Cmd+R для збірки та запуску
```

## Швидкий старт

1. **Встановіть BlackHole** (віртуальне аудіо пристрій):
   - Завантажте з [BlackHole website](https://existential.audio/blackhole/)
   - Встановіть 16-канальну версію

2. **Налаштуйте аудіо маршрут**:
   - Відкрийте SystemEQ
   - Перейдіть в Routing → Configure Audio Devices
   - Виберіть BlackHole як вхід, ваш DAC як вихід
   - Увімкніть Multi-Output в системних налаштуваннях

3. **Застосуйте пресет**:
   - AutoEQ → Search headphones
   - Введіть модель ваших навушників
   - Натисніть "⚡ Quick Import"

## Структура проекту

```
SystemEQ for Mac/
├── Audio/              # Core Audio обробка
│   ├── CoreAudioEngine.swift
│   ├── BiquadFilter.swift
│   └── CalibrationEngine.swift
├── Data/               # Моделі даних та база даних
│   ├── EQDatabase.swift
│   └── AutoEQModels.swift
├── Features/           # UI компоненти
│   ├── EqualizerView.swift
│   ├── AutoEQView.swift
│   └── CalibrationView.swift
├── DesignSystem/       # Дизайн система
└── Extensions/         # Розширення Swift
```

## Використання

### Еквалайзер

- Використовуйте слайдери для налаштування частот
- Перемикайтеся між 10 та 31 смугами
- Зберігайте власні пресети

### AutoEQ пресети

1. Пошукайте модель навушників
2. Виберіть бажаний пресет (оригінальний або Harman)
3. Імпортуйте налаштування

### Персоналізована калібрація

1. Запустіть тест слуху
2. Регулюйте гучність для кожної частоти
3. Збережіть профіль для автоматичного застосування

### Калібрація кімнати

1. Розмістіть мікрофон у точці прослуховування
2. Запустіть аналіз кімнати
3. Застосуйте notch фільтри для резонансів

## Технічні деталі

### Архітектура

- **CoreAudioEngine**: Низькорівнева обробка через AudioUnit
- **BiquadFilterChain**: DSP ланцюг фільтрів з оптимізацією
- **AudioEngine**: Facade для SwiftUI інтеграції
- **EQDatabase**: SQLite для зберігання пресетів

### Оптимізація

- Використання vDSP для Apple Silicon
- Direct Form II Transposed bіquad фільтри
- Мінімальна затримка (~5-10ms)
- Ефективне використання пам'яті

## Внесок

Запрошуємо до внеску! Будь ласка:

1. Fork проект
2. Створіть feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit зміни (`git commit -m 'Add some AmazingFeature'`)
4. Push до branch (`git push origin feature/AmazingFeature`)
5. Відкрийте Pull Request

## Ліцензія

Цей проект ліцензовано під MIT License - дивіться [LICENSE](LICENSE) файл для деталей.

## Подяка

- [AutoEQ](https://github.com/jaakkopasanen/AutoEq) за базу даних пресетів
- [BlackHole](https://existential.audio/blackhole/) за віртуальний аудіо драйвер
- [oratory1990](https://oratory1990.org/) за вимірювання навушників

## Зв'язок

- GitHub: [@denyszamorniak](https://github.com/denyszamorniak)
- Email: denys.zamorniak@gmail.com

---

**SystemEQ for Mac** - зроблено з ❤️ для аудіофілів
