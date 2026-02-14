# 🎧 Система калібровації SystemEQ for Mac

## Огляд

Система калібровації на слух для компенсації особливостей слуху, навушників та акустики кімнати. Базується на методології **Sonarworks Neutralizer**.

## 🎵 Типи тестових сигналів

### 1. **Pink Noise (Рекомендовано)** 🥇

**Що це:**
- Шум з рівномірною енергією на октаву
- Спад -3 дБ/октава (природний для людського слуху)
- Всі частоти звучать одночасно

**Чому краще:**
- ✅ Легше оцінити загальний баланс частот
- ✅ Природніше для слуху (як шум води, вітру)
- ✅ Швидше калібрувати (чуєш всі частоти разом)
- ✅ Менше втоми від прослуховування

**Використання:**
```swift
calibration.useFilteredNoise = true
calibration.playFilteredPinkNoise(frequency: 1000, duration: 2.0)
```

### 2. **Filtered Pink Noise (Per-Band)**

**Що це:**
- Pink Noise, відфільтрований на конкретну смугу
- Bandwidth: 1/3 октави (стандарт для EQ)
- Band-pass filter навколо цільової частоти

**Чому використовувати:**
- Ізолює конкретну частоту для точного налаштування
- Легше порівняти з референсною частотою
- Метод Sonarworks Neutralizer

**Приклад:**
```swift
// Калібрація 125 Hz
calibration.playFilteredPinkNoise(
    frequency: 125,
    duration: 2.0,
    amplitude: 0.3
)
```

### 3. **Pure Tone (Класичний метод)**

**Що це:**
- Чистий синусоїдальний тон
- Одна частота за раз

**Коли використовувати:**
- Для точного виявлення проблемних частот
- Якщо Pink Noise здається незвичним
- Для перевірки резонансів

## 🔬 Алгоритми генерації

### Voss-McCartney Pink Noise

**Принцип роботи:**
```
16 генераторів випадкових чисел
Кожен оновлюється на різній швидкості (октави)
Сума всіх = Pink Noise

Generator 0: оновлюється кожен семпл
Generator 1: кожні 2 семпли
Generator 2: кожні 4 семпли
...
Generator 15: кожні 32768 семплів
```

**Переваги:**
- Рівномірне навантаження CPU (1 генератор за семпл)
- Точність: ±0.5 дБ від ідеального -3 дБ/октава
- Без різких стрибків (bounded deviation)

**Код:**
```swift
var generators: [Float] = (0..<16).map { _ in Float.random(in: -1.0...1.0) }
var counter: UInt32 = 0
var runningSum = generators.reduce(0, +)

for frame in 0..<frameCount {
    // White noise для верхньої октави
    let white = Float.random(in: -1.0...1.0) * 0.5
    
    // Оновити один генератор (trailing zeros визначає який)
    let index = counter.trailingZeroBitCount
    if index < 16 {
        runningSum -= generators[index]
        generators[index] = Float.random(in: -1.0...1.0)
        runningSum += generators[index]
    }
    
    counter = counter &+ 1
    
    // Pink = сума всіх генераторів + white
    let pink = (runningSum + white) * 0.1
}
```

### Band-Pass Filter

**Мета:** Виділити конкретну частотну смугу з Pink Noise

**Параметри:**
- Center Frequency: цільова частота (31 Hz, 63 Hz, ...)
- Bandwidth: 1/3 октави (стандарт ISO для EQ)

**Формули:**
```swift
let lowFreq = centerFreq * pow(2.0, -bandwidth / 2.0)
let highFreq = centerFreq * pow(2.0, bandwidth / 2.0)

// Для 1000 Hz з bandwidth 1/3:
// lowFreq = 1000 * 2^(-1/6) ≈ 891 Hz
// highFreq = 1000 * 2^(1/6) ≈ 1122 Hz
```

**Реалізація:**
1. High-pass filter (видаляє частоти нижче lowFreq)
2. Low-pass filter (видаляє частоти вище highFreq)
3. Compensation gain (компенсує втрату від фільтрів)

## 📊 Процес калібровації

### Крок 1: Встановлення референсу

```
Частота: 1000 Hz (середина слухового діапазону)
Рівень: -20 дБ (комфортний для прослуховування)
Сигнал: Pink Noise або Pure Tone
```

**Що робить користувач:**
1. Відтворює референсний сигнал
2. Регулює гучність до комфортного рівня
3. Запам'ятовує цей рівень як еталон

### Крок 2: Калібрація по смугах

**Для кожної частоти (10 або 31 смуга):**

```
1. Відтворюється filtered pink noise на цільовій частоті
2. Користувач порівнює з референсом (1000 Hz)
3. Регулює слайдер:
   - Якщо частота звучить тихіше → збільшує gain
   - Якщо голосніше → зменшує gain
4. Мета: всі частоти звучать однаково голосно
```

**Режими відтворення:**
- **Play Reference:** референсний тон (1000 Hz)
- **Play Test:** тестова частота з поточним adjustment
- **Compare (Alternating):** автоматичне чергування reference/test

### Крок 3: Збереження профілю

```swift
let profile = CalibrationProfile(
    name: "My Headphones + Room",
    type: .equalLoudness,
    bands: testBands // масив з 31 значень dB adjustment
)

calibration.activateProfile(profile)
```

## 🎯 Режими калібровації

### Clean Calibration (Рекомендовано)

**Що робить:**
- Вимикає EQ перед калібруванням
- Калібрує чисті навушники/колонки
- Результат: компенсація тільки hardware + слух

**Коли використовувати:**
- Перша калібрація
- Нові навушники
- Зміна кімнати

### Combined Calibration (Advanced)

**Що робить:**
- Калібрує з активним EQ пресетом
- Результат: компенсація hardware + EQ + слух

**Коли використовувати:**
- Вже є AutoEQ пресет
- Хочеш додаткову персоналізацію
- Fine-tuning існуючого звуку

## 📈 Точність і обмеження

### Точність Pink Noise генератора

**Voss-McCartney:**
- Відхилення: ±0.5 дБ від ідеального -3 дБ/октава
- Діапазон: 20 Hz - 20 kHz
- Ripple: мінімальний завдяки 16 генераторам

### Точність Band-Pass фільтра

**Поточна реалізація:**
- Простий 1st order Butterworth
- Точність: ±1-2 дБ
- **TODO:** Покращити до 2nd order для кращої ізоляції

### Людський фактор

**Обмеження слуху:**
- Точність: ±2-3 дБ (типово для людини)
- Втома: після 15-20 хвилин точність падає
- Рекомендація: робити перерви кожні 10 смуг

## 🔧 API Reference

### CalibrationEngine

```swift
// Singleton
let calibration = CalibrationEngine.shared

// Вибір типу сигналу
calibration.useFilteredNoise = true // Pink Noise
calibration.useFilteredNoise = false // Pure Tone

// Відтворення
calibration.playCalibrationSignal(
    frequency: 1000,
    duration: 2.0,
    amplitude: 0.3
)

// Filtered Pink Noise (per-band)
calibration.playFilteredPinkNoise(
    frequency: 125,
    duration: 2.0,
    amplitude: 0.3
)

// Pure Tone
calibration.playTestTone(
    frequency: 1000,
    duration: 2.0,
    amplitude: 0.3
)

// Comparison mode (alternating)
calibration.startComparisonMode(
    testFrequency: 125,
    testLevel: -18.0
)
calibration.stopComparisonMode()

// Profile management
let profile = calibration.createProfile(
    name: "My Profile",
    type: .equalLoudness
)
calibration.activateProfile(profile)
calibration.deactivateProfile()
```

### CalibrationProfile

```swift
struct CalibrationProfile {
    let id: UUID
    var name: String
    var type: CalibrationType // .equalLoudness, .roomCorrection, .custom
    var bands: [Float] // 31 значень dB adjustment
    var notes: String
    var createdAt: Date
}
```

## 📚 Наукові основи

### ISO 226:2003 Equal-Loudness Contours

**Fletcher-Munson криві:**
- Людське вухо нерівномірно чує різні частоти
- Низькі частоти (20-200 Hz): потребують більше SPL
- Високі частоти (8-16 kHz): також потребують більше SPL
- Середні частоти (1-4 kHz): найчутливіші

**Калібрація компенсує:**
1. Особливості слуху (Fletcher-Munson)
2. Характеристики навушників/колонок
3. Акустику кімнати (резонанси, поглинання)

### Sonarworks Methodology

**Підхід:**
1. Pink Noise як тестовий сигнал
2. Per-band adjustment (1/3 октави)
3. Референсна частота 1000 Hz
4. Subjective loudness matching

**Результат:**
- Flat perceived frequency response
- Компенсація всього ланцюга: слух + hardware + кімната

## 🎓 Best Practices

### Підготовка

1. **Тихе середовище:** мінімум фонового шуму
2. **Комфортна гучність:** не занадто голосно
3. **Відпочинок:** не калібрувати втомленим
4. **Час:** виділити 10-15 хвилин без перерв

### Процес

1. **Почни з 10 смуг:** швидше, 90% результату
2. **Використовуй Pink Noise:** легше оцінити
3. **Порівнюй з референсом:** кнопка "Compare"
4. **Не перфекціонізуй:** ±2 дБ цілком достатньо
5. **Роби перерви:** кожні 10 смуг

### Після калібрації

1. **Тестуй на музиці:** різні жанри
2. **A/B порівняння:** з/без калібрації
3. **Підстроюй при потребі:** можна змінити окремі смуги
4. **Зберігай версії:** різні профілі для різних ситуацій

## 🚀 Roadmap

### Поточна версія (v1.0)

✅ Pink Noise генератор (Voss-McCartney)
✅ Filtered Pink Noise (band-limited)
✅ Pure Tone генератор
✅ Band-pass filtering
✅ Profile management
✅ A/B comparison
✅ 10/31 band modes

### Майбутні покращення

🔄 **v1.1:**
- [ ] Sweep Tone (частотна розгортка)
- [ ] Warble Tone (модульований тон)
- [ ] Покращений band-pass filter (2nd order)
- [ ] Візуалізація frequency response

🔄 **v1.2:**
- [ ] Автоматична калібрація з мікрофоном
- [ ] Room correction (об'єктивна)
- [ ] Target curves (Harman, Diffuse Field)
- [ ] Export/Import профілів

🔄 **v1.3:**
- [ ] ML-assisted calibration
- [ ] Hearing test integration
- [ ] Age-based compensation
- [ ] Multi-device profiles

## 📖 Посилання

**Наукові статті:**
- ISO 226:2003 - Equal-loudness contours
- Voss & Clarke (1978) - 1/f noise generation
- Fletcher & Munson (1933) - Equal-loudness research

**Реалізації:**
- Sonarworks SoundID Reference
- Paul Kellet - Pink Noise filters
- James McCartney - Voss algorithm optimization

**DSP ресурси:**
- https://www.firstpr.com.au/dsp/pink-noise/
- https://ccrma.stanford.edu/~jos/sasp/
- Music-DSP mailing list archives
