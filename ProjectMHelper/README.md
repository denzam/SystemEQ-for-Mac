# ProjectMHelper

Окремий helper app для рендерингу MilkDrop візуалізацій через projectM.

## Чому окремий процес?

projectM використовує **deprecated OpenGL**, який на macOS має проблеми:
- Конфлікти OpenGL контексту з SwiftUI
- NSLock в audio callback блокує UI thread
- CVDisplayLink + DispatchQueue створює затримки

**Рішення:** Запускати projectM в окремому процесі, який:
- Повністю ізольований від основного UI
- Якщо зависне — основний app продовжує працювати
- Комунікує через Unix domain socket (IPC)

## Архітектура

```
┌─────────────────────────────────────────────────────────────┐
│                    SystemEQ for Mac                         │
│  ┌─────────────────┐    ┌─────────────────────────────────┐ │
│  │ VisualizerView  │───▶│ ProjectMHelperClient            │ │
│  │ (SwiftUI)       │    │ - Запускає helper process       │ │
│  └─────────────────┘    │ - Надсилає аудіо через IPC      │ │
│                         │ - Отримує статус пресетів       │ │
│                         └──────────────┬──────────────────┘ │
└────────────────────────────────────────┼────────────────────┘
                                         │ Unix Socket
                                         ▼
┌─────────────────────────────────────────────────────────────┐
│                    ProjectMHelper.app                       │
│  ┌─────────────────┐    ┌─────────────────────────────────┐ │
│  │ IPCServer       │◀───│ VisualizerController            │ │
│  │ - Приймає аудіо │    │ - projectM handle               │ │
│  │ - Команди       │    │ - OpenGL rendering              │ │
│  └─────────────────┘    │ - CVDisplayLink                 │ │
│                         └─────────────────────────────────┘ │
│  ┌─────────────────────────────────────────────────────────┐│
│  │ ProjectMOpenGLView (NSOpenGLView)                       ││
│  │ - Borderless window                                     ││
│  │ - 60 FPS rendering                                      ││
│  └─────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────┘
```

## Збірка в Xcode

### Крок 1: Створити новий target

1. Відкрити `SystemEQ for Mac.xcodeproj`
2. File → New → Target...
3. Вибрати **macOS → App**
4. Налаштування:
   - Product Name: `ProjectMHelper`
   - Bundle Identifier: `com.denzam.SystemEQ.ProjectMHelper`
   - Interface: **None** (не SwiftUI, не Storyboard)
   - Language: Swift
   - ❌ Include Tests

### Крок 2: Додати файли до target

Перетягнути ці файли в Xcode та додати до target `ProjectMHelper`:
- `ProjectMHelper/ProjectMHelperApp.swift`
- `ProjectMHelper/IPCServer.swift`
- `ProjectMHelper/Info.plist`
- `ProjectMHelper/ProjectMHelper-Bridging-Header.h`

### Крок 3: Build Settings

В target `ProjectMHelper` → Build Settings:

```
SWIFT_OBJC_BRIDGING_HEADER = $(SRCROOT)/ProjectMHelper/ProjectMHelper-Bridging-Header.h
HEADER_SEARCH_PATHS = /usr/local/include
LIBRARY_SEARCH_PATHS = /usr/local/lib
OTHER_LDFLAGS = -lprojectM-4 -lprojectM-4-playlist
GCC_PREPROCESSOR_DEFINITIONS = GL_SILENCE_DEPRECATION=1
INFOPLIST_FILE = $(SRCROOT)/ProjectMHelper/Info.plist
```

### Крок 4: Frameworks

Додати frameworks до target `ProjectMHelper`:
- AppKit.framework
- OpenGL.framework
- CoreVideo.framework

### Крок 5: Copy Files Phase

В основному target `SystemEQ for Mac`:
1. Build Phases → + → New Copy Files Phase
2. Destination: **Executables** або **Helpers**
3. Subpath: `Helpers`
4. Додати `ProjectMHelper.app`

### Крок 6: Збірка

1. Спочатку зібрати `ProjectMHelper` target
2. Потім зібрати `SystemEQ for Mac`

## IPC Protocol

### Команди (SystemEQ → Helper)

| Команда | Формат | Опис |
|---------|--------|------|
| NEXT | `NEXT\n` | Наступний пресет |
| PREV | `PREV\n` | Попередній пресет |
| RAND | `RAND\n` | Випадковий пресет |
| SELECT | `SELECT:123\n` | Вибрати пресет за індексом |
| SHUFFLE | `SHUFFLE:1\n` | Увімкнути/вимкнути shuffle |
| LOCK | `LOCK:1\n` | Заблокувати пресет |
| RESIZE | `RESIZE:800:600\n` | Змінити розмір |
| AUDIO | `AUDIO:base64...\n` | Аудіо дані (Float32, stereo) |
| STATUS | `STATUS\n` | Запит статусу |
| QUIT | `QUIT\n` | Завершити helper |

### Відповіді (Helper → SystemEQ)

| Відповідь | Формат |
|-----------|--------|
| STATUS | `STATUS:{"presetName":"...", "presetCount":123, "shuffle":true, "locked":false}\n` |

## Аргументи командного рядка

```bash
./ProjectMHelper --x 100 --y 100 --width 800 --height 600 --parent-pid 12345
```

| Аргумент | Опис |
|----------|------|
| `--x` | X координата вікна |
| `--y` | Y координата вікна |
| `--width` | Ширина вікна |
| `--height` | Висота вікна |
| `--parent-pid` | PID батьківського процесу (для автозавершення) |

## Залежності

- libprojectM 4.x (`/usr/local/lib/libprojectM-4.dylib`)
- libprojectM-playlist (`/usr/local/lib/libprojectM-4-playlist.dylib`)
- MilkDrop presets (`~/Library/Application Support/SystemEQ/presets/`)

## Troubleshooting

### Helper не запускається
- Перевірити чи є `libprojectM-4.dylib` в `/usr/local/lib/`
- Перевірити права доступу до socket файлу

### Немає візуалізації
- Перевірити чи є пресети в `~/Library/Application Support/SystemEQ/presets/`
- Перевірити логи: `log stream --predicate 'processImagePath CONTAINS "ProjectMHelper"'`

### Аудіо не синхронізується
- Перевірити чи CoreAudioEngine запущений
- Перевірити IPC з'єднання
