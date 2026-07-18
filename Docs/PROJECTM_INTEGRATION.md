# 🎨 projectM Integration Guide

## Що встановлено

### libprojectM 4.1.6
- **Бібліотека**: `/usr/local/lib/libprojectM-4.dylib`
- **Playlist**: `/usr/local/lib/libprojectM-4-playlist.dylib`
- **Headers**: `/usr/local/include/projectM-4/`

### Пресети
- **Шлях**: `~/Library/Application Support/SystemEQ/presets/`
- **Кількість**: 9,795 MilkDrop пресетів (cream-of-the-crop collection)

## Налаштування Xcode

### 1. Build Settings

Додати в **Build Settings** проекту:

#### Header Search Paths
```
/usr/local/include
```

#### Library Search Paths
```
/usr/local/lib
```

#### Other Linker Flags
```
-lprojectM-4 -lprojectM-4-playlist
```

#### Swift Compiler - Custom Flags
```
-DGL_SILENCE_DEPRECATION
```

### 2. Bridging Header

Створити або оновити bridging header:

**File**: `SystemEQ for Mac-Bridging-Header.h`
```c
#import "Audio/Visualizer/ProjectM/ProjectMBridge.h"
```

В **Build Settings** → **Swift Compiler - General** → **Objective-C Bridging Header**:
```
$(SRCROOT)/SystemEQ for Mac/SystemEQ for Mac-Bridging-Header.h
```

### 3. Frameworks

Додати frameworks в **Build Phases** → **Link Binary With Libraries**:
- OpenGL.framework
- CoreVideo.framework (для CVDisplayLink)

### 4. Copy Libraries (для distribution)

Для розповсюдження додатку, потрібно скопіювати dylib файли:

1. Створити **Copy Files** build phase
2. Destination: Frameworks
3. Додати:
   - `/usr/local/lib/libprojectM-4.dylib`
   - `/usr/local/lib/libprojectM-4-playlist.dylib`

Або використати `install_name_tool` для зміни шляхів.

## Використання

### Ініціалізація
```swift
// В VisualizerView або при старті
Task { @MainActor in
    ProjectMEngine.shared.setup(width: 800, height: 600)
}
```

### Передача аудіо
```swift
// В audio callback
let samples: [Float] = ... // stereo interleaved
ProjectMEngine.shared.addAudioSamples(samples, channels: 2)
```

### Керування пресетами
```swift
// Наступний пресет
ProjectMEngine.shared.nextPreset()

// Попередній
ProjectMEngine.shared.previousPreset()

// Випадковий
ProjectMEngine.shared.randomPreset()

// Пошук
let results = ProjectMEngine.shared.searchPresets(query: "tunnel")
```

### SwiftUI View
```swift
struct VisualizerView: View {
    @StateObject var engine = ProjectMEngine.shared
    
    var body: some View {
        ProjectMView(engine: engine)
            .overlay(alignment: .bottom) {
                HStack {
                    Button("◀") { engine.previousPreset() }
                    Text(engine.currentPresetName)
                    Button("▶") { engine.nextPreset() }
                }
            }
    }
}
```

## Архітектура

```
┌─────────────────────────────────────────────────────────┐
│                    SystemEQ for Mac                      │
├─────────────────────────────────────────────────────────┤
│  VisualizerView (SwiftUI)                               │
│       │                                                  │
│       ▼                                                  │
│  ProjectMEngine (Swift)                                  │
│       │                                                  │
│       ▼                                                  │
│  ProjectMBridge.h (C API declarations)                   │
│       │                                                  │
│       ▼                                                  │
│  libprojectM-4.dylib (C++ implementation)               │
│       │                                                  │
│       ▼                                                  │
│  OpenGL 3.2 Core Profile                                │
│       │                                                  │
│       ▼                                                  │
│  .milk presets (MilkDrop format)                        │
└─────────────────────────────────────────────────────────┘
```

## Примітки

### OpenGL Deprecation
macOS 10.14+ позначив OpenGL як deprecated, але він все ще працює. projectM використовує OpenGL, тому ми використовуємо `GL_SILENCE_DEPRECATION` для приховування warnings.

### Альтернатива: Metal Interop
Для майбутнього можна розглянути:
1. Рендерити projectM в OpenGL texture
2. Конвертувати в Metal texture через `CVMetalTextureCache`
3. Відображати в MTKView

### Performance
- projectM оптимізований для 60+ FPS
- Mesh size 128x96 — баланс якості/продуктивності
- Для слабших машин: зменшити mesh до 64x48

## Troubleshooting

### "Cannot find projectm_create in scope"
Перевірте:
1. Bridging header налаштований
2. Header Search Paths включає `/usr/local/include`
3. ProjectMBridge.h доступний

### "Library not loaded"
```bash
# Перевірити бібліотеку
otool -L /usr/local/lib/libprojectM-4.dylib

# Якщо потрібно, оновити install name
install_name_tool -id @rpath/libprojectM-4.dylib /usr/local/lib/libprojectM-4.dylib
```

### Чорний екран
1. Перевірте OpenGL context створено
2. Перевірте preset завантажено
3. Перевірте audio samples передаються
