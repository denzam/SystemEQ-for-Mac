# Уніфікація вікон SystemEQ for Mac

## Огляд

Всі feature-вікна програми тепер використовують уніфікований компонент `FeatureWindowContainer`, що забезпечує консистентний дизайн, структуру та поведінку.

## FeatureWindowContainer

### Основні можливості

- ✅ Єдина структура header з title та subtitle
- ✅ Консистентний padding та spacing
- ✅ Опціональна tab navigation
- ✅ Стандартні розміри вікон
- ✅ Автоматичні Divider
- ✅ ScrollView обгортка (опціонально)
- ✅ Автоматична локалізація
- ✅ Blur ефект при зміні мови

### Стандартні розміри вікон

```swift
WindowSize.standard    // 800x600 - 1200x1000
WindowSize.large       // 900x700 - 1400x1000
WindowSize.compact     // 700x600 - 900x900
WindowSize.wide        // 900x600 - 1600x1200
WindowSize.equalizer   // 600x450 - 1200x800
```

## Використання

### Вікно без табів

```swift
FeatureWindowContainer(
    title: .settingsTitle,
    subtitle: .settingsHeaderSubtitle,
    windowSize: .compact
) {
    VStack {
        // Your content here
    }
}
```

### Вікно з табами

```swift
enum MyTab: CaseIterable, FeatureTab {
    case first, second
    
    var id: String { rawValue }
    
    func localizedTitle(_ localization: LocalizationManager) -> String {
        // Return localized title
    }
}

FeatureWindowContainer(
    title: .myTitle,
    subtitle: .mySubtitle,
    windowSize: .standard,
    selectedTab: $selectedTab
) { tab in
    switch tab {
    case .first: FirstTabContent()
    case .second: SecondTabContent()
    }
}
```

## Рефакторені вікна

### ✅ Повністю уніфіковані

1. **VisualizerView**
   - Розмір: `.wide` (900x600 - 1600x1200)
   - Без табів
   - Без ScrollView (hasScrollView: false)

2. **SettingsView**
   - Розмір: `.compact` (700x600 - 900x900)
   - Без табів
   - З ScrollView

3. **RoutingView**
   - Розмір: `.standard` (800x600 - 1200x1000)
   - З табами: Devices, Status
   - Toolbar з кнопкою Refresh

4. **CalibrationView**
   - Розмір: `.large` (900x700 - 1400x1000)
   - З табами: Equal Loudness, Profiles, Comparison
   - Зберігає всі alerts та sheets

5. **AutoEQView**
   - Розмір: `.large`
   - Без ScrollView (власна структура)
   - Зберігає всю функціональність пошуку та імпорту

## Вікна, що залишилися без змін

### EqualizerView
**Причина:** Має унікальну структуру з горизонтальним ScrollView для EQ слайдерів. Вертикальні слайдери потребують спеціального layout, який не підходить для стандартного контейнера.

### MainWindowView
Головне вікно має власний дизайн з GlassCard компонентом та не потребує уніфікації.

### MenuBarExtraView
Меню-бар має специфічну структуру для macOS menu bar extra.

## Рефакторені вікна

### ✅ VisualizerView
- **Розмір**: `WindowSize.wide`
- **Таби**: Ні
- **ScrollView**: Ні (hasScrollView: false)
- **Особливості**: Простий layout з picker та preview

### ✅ SettingsView
- **Розмір**: `WindowSize.compact`
- **Таби**: Ні
- **Секції**: Language, EQ Startup, General, Accessibility, Links
- **Особливості**: Використовує `.id(localization.currentLanguage)` для оновлення

### ✅ RoutingView
- **Розмір**: `WindowSize.standard`
- **Таби**: Devices, Status
- **Особливості**: Toolbar з кнопкою Refresh, peak meters з real-time оновленням

### ✅ CalibrationView
- **Розмір**: `WindowSize.large`
- **Таби**: Equal Loudness, Profiles, A/B Compare
- **Особливості**: Складна логіка калібрації, модальні вікна, alerts

### ✅ AutoEQView

```swift
FeatureWindowContainer(
    title: .autoEQTitle,
    subtitle: .featureAutoEQSubtitle,
    windowSize: .large,
    hasScrollView: false
) {
    // Content
}
```

### Вікно з табами

```swift
enum MyTab: CaseIterable, FeatureTab {
    case first, second
    
    var id: String { rawValue }
    
    func localizedTitle(_ localization: LocalizationManager) -> String {
        // Return localized title
    }
}

FeatureWindowContainer(
    title: .myTitle,
    subtitle: .mySubtitle,
    windowSize: .standard,
    selectedTab: $selectedTab
) { tab in
    switch tab {
    case .first: firstContent
    case .second: secondContent
    }
}
```

## Рефакторені вікна

### ✅ VisualizerView
- **Тип**: Без табів
- **Розмір**: `.wide` (900x600 - 1600x1200)
- **ScrollView**: Вимкнено (hasScrollView: false)
- **Особливості**: Простий layout з picker та preview

### ✅ SettingsView
- **Розмір**: `.compact` (700x600 - 900x900)
- **Таби**: Ні
- **ScrollView**: Так
- **Секції**: Language, EQ Startup, General, Accessibility, Links

### ✅ RoutingView
- **Розмір**: `.standard` (800x600 - 1200x1000)
- **Таби**: Devices, Status
- **Особливості**: Toolbar з кнопкою Refresh

### ✅ CalibrationView
- **Розмір**: `.large` (900x700 - 1400x1000)
- **Таби**: Equal Loudness, Profiles, A/B Comparison
- **Особливості**: Складна логіка калібрації, alerts, sheets

### ✅ AutoEQView
- **Розмір**: `.large` (900x700 - 1400x1000)
- **Таби**: Немає
- **ScrollView**: Вимкнено (власна логіка скролу)
- **Особливості**: Складна структура з пошуком, favorites, візуалізацією

### ⚠️ EqualizerView - НЕ уніфіковано

**Причина:** Специфічна структура з горизонтальним скролом для EQ слайдерів. Має унікальний layout, який не підходить для стандартного контейнера.

## Переваги уніфікації

### 1. Консистентність
- Всі вікна виглядають однаково
- Однакові відступи та spacing
- Єдиний підхід до header та navigation

### 2. Підтримка
- Легше вносити зміни в дизайн
- Зміни в одному місці застосовуються до всіх вікон
- Менше дублювання коду

### 3. Локалізація
- Автоматична підтримка зміни мови
- Blur ефект при перемиканні мови
- Консистентна поведінка

### 4. Якість коду
- Менше повторюваного коду
- Легше тестувати
- Простіше додавати нові вікна

## Статистика

### До уніфікації
- 6 різних підходів до структури вікон
- Різні розміри вікон (6 варіантів)
- Різні підходи до padding (4 варіанти)
- Різні реалізації tab navigation (2 варіанти)

### Після уніфікації
- 1 уніфікований компонент
- 5 стандартних розмірів вікон
- Консистентний padding
- Єдина реалізація tab navigation
- 5 з 6 вікон уніфіковано (83%)

## Майбутні покращення

1. **Toolbar підтримка** - додати стандартний toolbar для кнопок
2. **Floating panels** - підтримка floating панелей для додаткових контролів
3. **Responsive sizing** - автоматична адаптація розмірів під контент
4. **Accessibility** - покращена підтримка VoiceOver та інших accessibility features
5. **Animations** - стандартні анімації переходів між табами

## Дата створення

11 січня 2026

## Автор

Створено в рамках рефакторингу UI для покращення якості коду та консистентності дизайну.
