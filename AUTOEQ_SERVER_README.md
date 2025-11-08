# AutoEQ Local Server

Локальний Python сервер для точного обчислення GraphicEQ значень з використанням офіційної AutoEQ бібліотеки.

## Встановлення

1. **Встановіть залежності:**
   ```bash
   cd "/Users/denyszamorniak/CascadeProjects/SystemEQ for Mac"
   ./setup_autoeq.sh
   ```

   Це створить віртуальне середовище Python, встановить всі необхідні бібліотеки та склонує AutoEQ репозиторій.

2. **Додайте `AutoEQServer.swift` до Xcode проекту:**
   - Відкрийте проект в Xcode
   - Правою кнопкою на папку "SystemEQ for Mac"
   - Add Files to "SystemEQ for Mac"...
   - Виберіть файл `AutoEQServer.swift`
   - Переконайтеся що "Copy items if needed" увімкнено
   - Натисніть Add

## Використання

### Запуск сервера вручну (для тестування)

```bash
./start_server.sh
```

Сервер запуститься на `http://127.0.0.1:5555`

### Автоматичний запуск з програми

Додайте в `AppDelegate.swift` або головний View:

```swift
import SwiftUI

@main
struct SystemEQApp: App {
    init() {
        // Запускаємо AutoEQ сервер при старті програми
        AutoEQServer.shared.startServer()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

## Як це працює

1. **Python сервер** (`autoeq_server.py`) використовує офіційну AutoEQ бібліотеку
2. **Swift код** (`AutoEQServer.swift`) керує запуском сервера та робить HTTP запити
3. **AutoEQView** автоматично використовує локальний сервер, якщо він доступний
4. Якщо сервер недоступний, програма використовує fallback метод (параметричні фільтри)

## API Endpoints

### Health Check
```
GET http://127.0.0.1:5555/health
```

### Calculate GraphicEQ
```
POST http://127.0.0.1:5555/equalize
Content-Type: application/json

{
    "measurement_name": "oratory1990/over-ear/Sennheiser HD 800 S",
    "target_name": "JM-1 with Harman filters",
    "band_count": 10
}
```

Response:
```json
{
    "bands": [
        {"freq": 31.5, "gain": 2.5},
        {"freq": 63, "gain": 1.8},
        ...
    ],
    "preamp": -6.5,
    "measurement_name": "oratory1990/over-ear/Sennheiser HD 800 S",
    "target_name": "JM-1 with Harman filters"
}
```

## Переваги

✅ **Абсолютно точні значення** - використовує той самий код, що і офіційний AutoEQ
✅ **Підтримка всіх target profiles** - JM-1, Harman, Diffuse Field, тощо
✅ **Швидко** - локальний сервер працює швидше ніж зовнішні API
✅ **Offline** - працює без інтернету (після встановлення)
✅ **Fallback** - якщо сервер недоступний, програма використовує альтернативний метод

## Вимоги

- Python 3.8 або новіший
- ~2 GB вільного місця (для AutoEQ репозиторію)
- macOS 10.15 або новіший

## Troubleshooting

### Сервер не запускається

Перевірте чи встановлений Python 3:
```bash
python3 --version
```

### Помилки при встановленні

Видаліть віртуальне середовище та спробуйте знову:
```bash
rm -rf venv
./setup_autoeq.sh
```

### Сервер працює але програма не може з'єднатися

Перевірте чи сервер доступний:
```bash
curl http://127.0.0.1:5555/health
```

Має повернути: `{"status":"ok","message":"AutoEQ server is running"}`
