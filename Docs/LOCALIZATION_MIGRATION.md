# Міграція на професійну систему локалізації

## Що ми зробили:

### 1. **Створили .strings файли**
- `/Resources/Localizations/en.lproj/Localizable.strings`
- `/Resources/Localizations/it.lproj/Localizable.strings`
- `/Resources/Localizations/uk.lproj/Localizable.strings`

Це стандартний підхід Apple для локалізації.

### 2. **Новий LocalizationManager**
- Використовує `NSLocalizedString` замість словників в коді
- Підтримує динамічну зміну мови
- Автоматично оновлює назви вікон

### 3. **LocalizationKey enum**
- Всі ключі в одному місці
- Типобезпека (немає помилок у назвах)
- Автокомпліт в Xcode

### 4. **Утиліта для генерації**
- `generate_localizations.sh` - автоматично знаходить усі ключі
- Експортує для перекладачів
- Валідує локалізацію

## Як користуватися:

### Додавання нового тексту:
```swift
// Замість старого:
text: localizationManager.localized(.myText)

// Новий спосіб:
text: LocalizationManager.shared.localized(.myText)
```

### Додавання нового ключа:
1. Додайте в `LocalizationKey` enum
2. Запустіть `generate_localizations.sh`
3. Перекладіть у всіх .strings файлах

### Переклад для UI:
```swift
// У SwiftUI
Text(LocalizationManager.shared.localized(.save))

// Або з аргументами:
Text(LocalizationManager.shared.localized(.volumeWarning, "50%"))
```

## Переваги нового підходу:

✅ **Стандарт Apple** - сумісно з Xcode Localizations
✅ **External translators** - можна експортувати .xliff
✅ **Validation** - Xcode перевіряє відсутні переклади
✅ **Performance** - NSLocalizedString оптимізований
✅ **Pluralization** - підтримка множини (.stringsdict)
✅ **Future-proof** - легко додати нові мови

## Наступні кроки:

1. **Замінити всі виклики старого LocalizationManager**
2. **Запустити `xcodebuild -exportLocalizations`** для валідації
3. **Налаштувати CI/CD** для автоматичної перевірки локалізації
4. **Додати .stringsdict** для множин (напр. "1 file", "2 files")

## Міграція існуючого коду:

Знайдіть і замініть:
```bash
# Знайти всі старі виклики
grep -r "localizationManager.localized\(" . --include="*.swift"

# Замінити на нові
sed -i '' 's/localizationManager\.localized\(/LocalizationManager\.shared\.localized\(/g' **/*.swift
```

Це професійний підхід, який використовують у великих проектах як Apple, Google, Meta.
