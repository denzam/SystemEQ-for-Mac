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
