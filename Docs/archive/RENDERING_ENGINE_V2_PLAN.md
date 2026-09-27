# 🏗️ VisualizerEngine v2: Професійний Rendering Engine

**Дата початку:** 14 лютого 2026, 14:35  
**Мета:** Якість Winamp MilkDrop + 60-120 FPS без компромісів  
**Підхід:** Варіант В - повна переробка на професійний рівень

---

## 🎯 ЦІЛІ ПРОЕКТУ

### Продуктивність:
- ✅ **60 FPS мінімум** на M1/M2 Mac
- ✅ **90-120 FPS** на потужніших Mac
- ✅ **Стабільний frame time** без стрибків
- ✅ **< 5% CPU usage** (все на GPU)

### Якість:
- ✅ **Візуальна якість як у MilkDrop**
- ✅ **Плавна реакція на музику**
- ✅ **Красиві переходи між пресетами**
- ✅ **800+ візуалізацій** (як у MilkDrop)

### Архітектура:
- ✅ **Metal Compute Shaders** замість Fragment
- ✅ **Metal Performance Shaders** для filters
- ✅ **Preset System** (.milk файли)
- ✅ **GPU Profiling** та optimization
- ✅ **Adaptive Quality** (автоматичний LOD)

---

## 📐 АРХІТЕКТУРА НОВОГО ENGINE

### Поточна архітектура (проблемна):
```
AudioEngine → VisualizerEngine → MetalVisualizerRenderer
                                         ↓
                                  Fragment Shaders
                                         ↓
                                    MTKView (60 FPS?)
```

**Проблеми:**
- Fragment Shaders виконуються для КОЖНОГО пікселя
- Немає контролю над thread groups
- Синхронне rendering (чекаємо GPU)
- Немає кешування compiled shaders
- Немає adaptive quality

---

### Нова архітектура v2 (професійна):
```
AudioEngine → AudioAnalyzer (FFT, beat detection)
                    ↓
            PresetManager (.milk файли)
                    ↓
         ComputeShaderEngine (Metal Compute)
                    ↓
         MPSFilterPipeline (blur, feedback)
                    ↓
         AsyncRenderer (triple buffering)
                    ↓
            MTKView (60-120 FPS!)
```

**Переваги:**
- Compute Shaders - контроль над паралелізмом
- MPS - оптимізовані Apple filters
- Preset System - як у MilkDrop
- Async Rendering - GPU працює паралельно
- Adaptive Quality - автоматичний LOD

---

## 🔧 КОМПОНЕНТИ СИСТЕМИ

### 1. AudioAnalyzer (покращений)
**Файл:** `AudioAnalyzer.swift` (новий)

**Функції:**
- FFT аналіз (64-256 bins)
- Beat detection (bass, mid, treble)
- Smoothing (exponential + adaptive)
- Peak detection
- Frequency bands (sub-bass, bass, mid, treble, presence)

**Приклад:**
```swift
class AudioAnalyzer {
    private let fft: vDSP.FFT<Float>
    private var smoothedSpectrum: [Float]
    
    func analyze(samples: [Float]) -> AudioFeatures {
        // FFT
        let spectrum = performFFT(samples)
        
        // Smoothing
        smoothedSpectrum = smooth(spectrum)
        
        // Beat detection
        let beats = detectBeats(spectrum)
        
        return AudioFeatures(
            spectrum: smoothedSpectrum,
            bass: beats.bass,
            mid: beats.mid,
            treble: beats.treble,
            beat: beats.detected
        )
    }
}
```

---

### 2. PresetManager (.milk файли)
**Файл:** `PresetManager.swift` (новий)

**Функції:**
- Завантаження .milk пресетів
- Парсинг per-frame/per-pixel equations
- Компіляція в Metal код
- Кешування compiled shaders
- Transition effects

**Формат .milk:**
```ini
[preset00]
fRating=3.000000
fGammaAdj=2.000000
fDecay=0.980000
fVideoEchoZoom=1.006596
fVideoEchoAlpha=0.000000

per_frame_1=wave_r = 0.5 + 0.4*sin(time*1.324);
per_frame_2=wave_g = 0.5 + 0.4*sin(time*1.371);
per_frame_3=wave_b = 0.5 + 0.4*sin(time*1.495);

per_pixel_1=zoom = 1 + 0.02*sin(time);
per_pixel_2=rot = rot + 0.01*sin(time*0.3);
```

**Приклад:**
```swift
class PresetManager {
    private var presets: [String: Preset] = [:]
    private var compiledShaders: [String: MTLComputePipelineState] = [:]
    
    func loadPreset(from url: URL) -> Preset? {
        let content = try? String(contentsOf: url)
        return parsePreset(content)
    }
    
    func compilePreset(_ preset: Preset) -> MTLComputePipelineState? {
        // Конвертуємо per-frame/per-pixel equations в Metal код
        let metalCode = generateMetalCode(from: preset)
        return compileShader(metalCode)
    }
}
```

---

### 3. ComputeShaderEngine (ядро системи)
**Файл:** `ComputeShaderEngine.swift` (новий)

**Функції:**
- Metal Compute Shaders замість Fragment
- Thread group optimization
- Shared memory для кешування
- Parallel execution

**Приклад Compute Shader:**
```metal
// Plasma Compute Shader (замість Fragment)
kernel void plasmaCompute(
    texture2d<float, access::write> output [[texture(0)]],
    texture2d<float, access::read> feedback [[texture(1)]],
    constant AudioFeatures &audio [[buffer(0)]],
    constant PresetParams &params [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]],
    uint2 tsize [[threads_per_grid]]
) {
    // Нормалізовані координати
    float2 uv = float2(gid) / float2(tsize);
    
    // Обчислення (тільки для цього пікселя)
    float3 color = computePlasma(uv, audio, params);
    
    // Feedback loop
    float3 feedbackColor = feedback.read(gid).rgb;
    color = mix(color, feedbackColor, params.feedbackDecay);
    
    // Запис результату
    output.write(float4(color, 1.0), gid);
}
```

**Переваги над Fragment Shaders:**
- Контроль thread groups (оптимізація)
- Threadgroup memory (кешування)
- Більш ефективний доступ до текстур
- Можна використати atomic operations

---

### 4. MPSFilterPipeline (Apple оптимізації)
**Файл:** `MPSFilterPipeline.swift` (новий)

**Функції:**
- Gaussian Blur (hardware accelerated)
- Image filters (brightness, contrast, saturation)
- Convolution (edge detection, sharpen)
- Histogram (для audio аналізу)

**Приклад:**
```swift
class MPSFilterPipeline {
    private let device: MTLDevice
    private let gaussianBlur: MPSImageGaussianBlur
    private let brightnessFilter: MPSImageBrightnessFilter
    
    init(device: MTLDevice) {
        self.device = device
        self.gaussianBlur = MPSImageGaussianBlur(device: device, sigma: 2.0)
        self.brightnessFilter = MPSImageBrightnessFilter(device: device)
    }
    
    func applyFeedbackBlur(
        commandBuffer: MTLCommandBuffer,
        input: MTLTexture,
        output: MTLTexture
    ) {
        // Hardware-accelerated blur
        gaussianBlur.encode(
            commandBuffer: commandBuffer,
            sourceTexture: input,
            destinationTexture: output
        )
    }
}
```

**Переваги:**
- Оптимізовано Apple для Metal
- Hardware acceleration
- Мінімальний overhead
- Простий API

---

### 5. AsyncRenderer (triple buffering)
**Файл:** `AsyncRenderer.swift` (новий)

**Функції:**
- Triple buffering (3 command buffers)
- Async rendering (GPU паралельно з CPU)
- Frame pacing (стабільний FPS)
- VSync control

**Приклад:**
```swift
class AsyncRenderer {
    private let semaphore = DispatchSemaphore(value: 3)
    private var commandBuffers: [MTLCommandBuffer] = []
    
    func render(drawable: CAMetalDrawable) {
        // Чекаємо на вільний buffer
        semaphore.wait()
        
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            semaphore.signal()
            return
        }
        
        // Коли GPU закінчить - звільняємо buffer
        commandBuffer.addCompletedHandler { [weak self] _ in
            self?.semaphore.signal()
        }
        
        // Encode rendering commands
        encodeRenderCommands(commandBuffer)
        
        // Present
        commandBuffer.present(drawable)
        commandBuffer.commit()
        
        // CPU може продовжувати роботу, GPU працює паралельно
    }
}
```

**Переваги:**
- GPU працює паралельно з CPU
- Стабільний frame time
- Немає stalls
- Максимальна продуктивність

---

### 6. AdaptiveQualitySystem (LOD)
**Файл:** `AdaptiveQualitySystem.swift` (новий)

**Функції:**
- Моніторинг FPS в реальному часі
- Автоматичне зменшення якості при падінні FPS
- Динамічний LOD для шейдерів
- Профілювання GPU

**Приклад:**
```swift
class AdaptiveQualitySystem {
    private var targetFPS: Double = 60.0
    private var currentQuality: QualityLevel = .high
    
    enum QualityLevel {
        case low    // 1-2 iterations
        case medium // 3-4 iterations
        case high   // 5+ iterations
    }
    
    func updateQuality(currentFPS: Double) {
        if currentFPS < targetFPS - 10 {
            // Знижуємо якість
            currentQuality = .medium
        } else if currentFPS > targetFPS + 10 {
            // Підвищуємо якість
            currentQuality = .high
        }
    }
    
    func getShaderIterations() -> Int {
        switch currentQuality {
        case .low: return 2
        case .medium: return 4
        case .high: return 6
        }
    }
}
```

---

## 📋 ПЛАН ІМПЛЕМЕНТАЦІЇ

### Фаза 1: Фундамент (3-4 години)
**Мета:** Створити базову архітектуру

1. ✅ **AudioAnalyzer** (1 година)
   - FFT аналіз
   - Beat detection
   - Smoothing

2. ✅ **ComputeShaderEngine** (2 години)
   - Базовий compute shader
   - Texture management
   - Command buffer encoding

3. ✅ **AsyncRenderer** (1 година)
   - Triple buffering
   - Frame pacing

---

### Фаза 2: Compute Shaders (4-5 годин)
**Мета:** Переписати всі візуалізації на Compute

1. ✅ **Базові візуалізації** (2 години)
   - Spectrum (compute)
   - Waveform (compute)
   - Bars (compute)

2. ✅ **MilkDrop візуалізації** (3 години)
   - Plasma (compute)
   - Tunnel (compute)
   - Galaxy (compute)
   - Fire (compute)
   - Aurora (compute)

---

### Фаза 3: MPS та Optimization (2-3 години)
**Мета:** Додати Apple оптимізації

1. ✅ **MPSFilterPipeline** (1 година)
   - Gaussian blur
   - Brightness/Contrast
   - Saturation

2. ✅ **Feedback Optimization** (1 година)
   - MPS для feedback loop
   - Texture pooling
   - Memory optimization

3. ✅ **GPU Profiling** (1 година)
   - Xcode Metal Debugger
   - Знайти bottlenecks
   - Оптимізувати

---

### Фаза 4: Preset System (3-4 години)
**Мета:** Підтримка .milk файлів

1. ✅ **PresetManager** (2 години)
   - Парсинг .milk файлів
   - Per-frame equations
   - Per-pixel equations

2. ✅ **Shader Compilation** (2 години)
   - Генерація Metal коду
   - Компіляція в runtime
   - Кешування

---

### Фаза 5: Adaptive Quality (2 години)
**Мета:** Автоматичний LOD

1. ✅ **AdaptiveQualitySystem** (1 година)
   - FPS моніторинг
   - Динамічний LOD
   - Quality presets

2. ✅ **Shader LOD** (1 година)
   - Змінна кількість ітерацій
   - Early exit optimization
   - Distance-based LOD

---

### Фаза 6: Тестування та Polish (2-3 години)
**Мета:** Довести до ідеалу

1. ✅ **Performance Testing** (1 година)
   - Всі візуалізації 60+ FPS
   - Стабільний frame time
   - CPU usage < 5%

2. ✅ **Visual Quality** (1 година)
   - Порівняння з MilkDrop
   - Tweaking параметрів
   - Transitions

3. ✅ **Bug Fixing** (1 година)
   - Edge cases
   - Memory leaks
   - Crashes

---

## 📊 ОЧІКУВАНІ РЕЗУЛЬТАТИ

### Продуктивність:
- **FPS:** 60-120 (залежно від Mac)
- **CPU:** < 5% usage
- **GPU:** 30-50% usage (оптимально)
- **Memory:** < 200 MB

### Якість:
- **Візуальна якість:** Як у MilkDrop
- **Плавність:** Стабільний frame time
- **Реакція на музику:** Плавна та природна
- **Transitions:** Красиві переходи

### Функціональність:
- **800+ візуалізацій** (.milk пресети)
- **Beat detection** auto-change
- **Color randomization**
- **Adaptive quality**
- **GPU profiling**

---

## 🚀 ПОЧАТОК РОБОТИ

### Крок 1: Створити нову структуру
```
SystemEQ for Mac/
  Audio/
    Visualizer/
      EngineV2/              ← НОВА ПАПКА
        AudioAnalyzer.swift
        ComputeShaderEngine.swift
        MPSFilterPipeline.swift
        AsyncRenderer.swift
        PresetManager.swift
        AdaptiveQualitySystem.swift
        Shaders/
          ComputeShaders.metal
          Presets/
            *.milk файли
```

### Крок 2: Імплементувати по фазах
1. Фаза 1: Фундамент (3-4 години)
2. Фаза 2: Compute Shaders (4-5 годин)
3. Фаза 3: MPS та Optimization (2-3 години)
4. Фаза 4: Preset System (3-4 години)
5. Фаза 5: Adaptive Quality (2 години)
6. Фаза 6: Testing та Polish (2-3 години)

**Загальний час:** 16-21 година (2-3 дні роботи)

---

## 💡 КЛЮЧОВІ ПРИНЦИПИ

1. **Якість > Швидкість** - не йдемо на компроміси
2. **GPU-first** - всі обчислення на GPU
3. **Профілювання** - вимірюємо все
4. **Модульність** - кожен компонент незалежний
5. **Тестування** - кожна фаза тестується окремо

---

## 🎯 ГОТОВИЙ ПОЧАТИ?

**Починаємо з Фази 1: Фундамент**

Створюю:
1. `AudioAnalyzer.swift` - покращений audio аналіз
2. `ComputeShaderEngine.swift` - базовий compute engine
3. `AsyncRenderer.swift` - triple buffering

**Це професійне рішення без компромісів! 🚀**
