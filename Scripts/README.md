# Скрипти для SystemEQ

## generate_autoeq_index.swift

Генерує попередньо зібраний індекс AutoEQ для включення в bundle програми.

### Використання:

```bash
cd Scripts
swift generate_autoeq_index.swift
```

Це створить файл `AutoEqIndex.json` який потім треба додати до проєкту Xcode.

### Додавання AutoEqIndex.json до Xcode проєкту:

1. Відкрийте `SystemEQ for Mac.xcodeproj` в Xcode
2. Перетягніть файл `SystemEQ for Mac/AutoEqIndex.json` в Project Navigator
3. У діалозі що з'явиться:
   - ✅ Увімкніть "Copy items if needed"
   - ✅ Виберіть "Create groups"
   - ✅ Виберіть target "SystemEQ for Mac"
4. Натисніть "Finish"

Файл буде автоматично включений в bundle програми і завантажуватиметься при першому запуску.

### Оновлення індексу:

Запускайте скрипт періодично (наприклад, раз на місяць) щоб оновити індекс з останніми даними AutoEQ.

### Розмір:

Поточний індекс: ~1.3 MB (8850+ моделей навушників)

---

## check_blackhole_updates.sh

Перевіряє чи доступна нова версія BlackHole через Homebrew API і порівнює з
`AppConstants.BlackHole.bundledVersion`.

### Як запустити

```bash
# Лише перевірка
./Scripts/check_blackhole_updates.sh

# Автоматичне оновлення AppConstants.swift + показ diff
./Scripts/check_blackhole_updates.sh --update
```

### Що оновлюється

Один рядок у [SystemEQ for Mac/Config/AppConstants.swift](../SystemEQ%20for%20Mac/Config/AppConstants.swift):

```swift
public static let bundledVersion = "0.6.1"
```

Всі URL (прямий .pkg, Homebrew, UI-тексти) будуються з цієї однієї константи.

### Коли запускати

- Перед релізом нової версії SystemEQ
- Якщо користувачі скаржаться на застарілу версію BlackHole
- Рекомендовано — раз на квартал
