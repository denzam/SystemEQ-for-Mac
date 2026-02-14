# 💰 Donation Setup Guide

## Налаштування Donation Кнопок

У `SettingsView.swift` є 3 donation кнопки з placeholder URLs. Заміни їх на свої реальні посилання:

### 1. Ko-fi (РЕКОМЕНДУЮ)
- Зареєструйся на https://ko-fi.com
- Обери username
- Заміни URL в коді: `https://ko-fi.com/ТВІЙ_USERNAME`
- **0% комісії** на donations

### 2. Buy Me a Coffee
- Зареєструйся на https://buymeacoffee.com
- Обери username
- Заміни URL в коді: `https://buymeacoffee.com/ТВІЙ_USERNAME`
- **0% комісії** на donations

### 3. GitHub Sponsors
- Увімкни GitHub Sponsors на своєму профілі
- Налаштуй tiers ($2, $5, $10/місяць)
- Заміни URL в коді: `https://github.com/sponsors/ТВІЙ_USERNAME`
- **0% комісії** (GitHub платить fees)

## Де Змінити URLs

Файл: `SystemEQ for Mac/Features/SettingsView.swift`

Знайди рядки ~256, ~264, ~272 та заміни `yourname` на свій username.

## Готово!

Після зміни URLs, donation кнопки з'являться в Settings → Support Development.
