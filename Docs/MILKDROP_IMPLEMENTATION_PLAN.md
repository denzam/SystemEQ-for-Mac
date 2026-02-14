# 🚀 План імплементації MilkDrop технік

## 📋 Загальний огляд

**Мета:** Зробити візуалізації такими ж плавними та красивими як у Winamp MilkDrop

**Час:** 4-5 годин

**Пріоритет:** Feedback Loop > Audio Smoothing > Smooth Transitions > Per-Frame Variables

---

## 🎯 Фаза 1: Feedback Loop для всіх шейдерів (КРИТИЧНО!)

### Проблема
Зараз тільки Psychedelic використовує feedback texture. Інші шейдери рендерять кожен кадр з нуля, що робить їх різкими та не плавними.

### Рішення
Додати feedback loop до **ВСІХ** шейдерів MilkDrop-inspired.

### Зміни в MetalVisualizerRenderer.swift

```swift
// Замість 2 feedback textures тільки для psychedelic:
private var feedbackTextureA: MTLTexture?
private var feedbackTextureB: MTLTexture?

// Робимо для ВСІХ шейдерів:
private var feedbackTextures: [VisualizerStyle: (a: MTLTexture, b: MTLTexture)] = [:]
private var useFeedbackA: [VisualizerStyle: Bool] = [:]
```

### Зміни в VisualizerUniforms

```swift
struct VisualizerUniforms {
    var time: Float = 0
    var intensity: Float = 0
    var resolution: SIMD2<Float> = .zero
    var bass: Float = 0
    var mid: Float = 0
    var treble: Float = 0
    var peakLevel: Float = 0
    
    // НОВІ змінні для feedback:
    var feedbackZoom: Float = 0.99    // 0.98-1.02
    var feedbackRotation: Float = 0.0  // -0.02 до +0.02
    var feedbackDecay: Float = 0.95    // 0.9-0.98
}
```

### Зміни в Metal шейдерах

Кожен MilkDrop шейдер має отримувати feedback texture:

```metal
fragment float4 tunnelFragment(
    VertexOut in [[stage_in]],
    constant VisualizerUniforms &uniforms [[buffer(0)]],
    constant float *spectrumData [[buffer(1)]],
    texture2d<float> feedbackTexture [[texture(0)]]  // ДОДАТИ!
) {
    // 1. Sample feedback з попереднього кадру
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    
    float2 center = float2(0.5, 0.5);
    float2 delta = in.uv - center;
    
    // 2. Застосувати zoom + rotation
    float zoom = uniforms.feedbackZoom + uniforms.bass * 0.01;
    float rotation = uniforms.feedbackRotation + uniforms.mid * 0.005;
    
    float cs = cos(rotation);
    float sn = sin(rotation);
    float2 feedbackUV = center + float2(
        (delta.x * cs - delta.y * sn) * zoom,
        (delta.x * sn + delta.y * cs) * zoom
    );
    
    float4 feedback = feedbackTexture.sample(s, feedbackUV);
    
    // 3. Обчислити новий візуальний контент
    float3 newColor = computeTunnelEffect(...);
    
    // 4. Blend старий кадр з новим (motion blur!)
    float3 finalColor = feedback.rgb * uniforms.feedbackDecay + newColor * (1.0 - uniforms.feedbackDecay);
    
    return float4(finalColor, 1.0);
}
```

### Які шейдери потребують feedback:
- ✅ Tunnel
- ✅ Plasma
- ✅ Galaxy
- ✅ Aurora
- ✅ Fire
- ✅ Vortex
- ✅ Kaleidoscope
- ✅ Nebula
- ✅ Fluid
- ⚠️ Spectrum/Waveform - НЕ потрібен (classic style)
- ⚠️ Particles - опціонально

---

## 🎯 Фаза 2: Audio Smoothing (Exponential Filter)

### Проблема
Audio reactivity занадто різка. Bass/mid/treble змінюються миттєво, що створює "дергані" рухи.

### Рішення
Додати exponential smoothing filter в VisualizerEngine.

### Зміни в VisualizerEngine.swift

```swift
public final class VisualizerEngine: ObservableObject {
    // Існуючі змінні
    @Published public var spectrumData: [Float] = Array(repeating: 0.0, count: 64)
    
    // НОВІ змінні для smoothing:
    private var smoothedBass: Float = 0.0
    private var smoothedMid: Float = 0.0
    private var smoothedTreble: Float = 0.0
    
    // Smoothing factor (0.7-0.9, більше = плавніше але повільніше)
    private let audioSmoothingFactor: Float = 0.8
    
    private func updateSpectrumData() {
        // ... існуючий код ...
        
        // Обчислити bass/mid/treble як зараз
        let rawBass = calculateBass(from: normalized)
        let rawMid = calculateMid(from: normalized)
        let rawTreble = calculateTreble(from: normalized)
        
        // Застосувати exponential smoothing
        smoothedBass = smoothedBass * audioSmoothingFactor + rawBass * (1.0 - audioSmoothingFactor)
        smoothedMid = smoothedMid * audioSmoothingFactor + rawMid * (1.0 - audioSmoothingFactor)
        smoothedTreble = smoothedTreble * audioSmoothingFactor + rawTreble * (1.0 - audioSmoothingFactor)
        
        // Передати smoothed значення в renderer
        // (через існуючий механізм)
    }
}
```

### Результат
- Плавні зміни замість різких стрибків
- Природна реакція на музику
- Як у справжньому MilkDrop

---

## 🎯 Фаза 3: Smooth Transitions між візуалізаціями

### Проблема
При перемиканні візуалізацій відбувається різкий cut. MilkDrop робить плавний 3-5 секундний blend.

### Рішення
Створити TransitionManager який рендерить 2 шейдери одночасно та змішує їх.

### Новий файл: VisualizerTransitionManager.swift

```swift
final class VisualizerTransitionManager {
    private var isTransitioning: Bool = false
    private var transitionProgress: Float = 0.0  // 0.0 -> 1.0
    private var transitionDuration: Float = 3.0  // секунди
    private var transitionStartTime: CFTimeInterval = 0
    
    private var fromStyle: VisualizerStyle?
    private var toStyle: VisualizerStyle?
    
    func startTransition(from: VisualizerStyle, to: VisualizerStyle) {
        isTransitioning = true
        transitionProgress = 0.0
        transitionStartTime = CACurrentMediaTime()
        fromStyle = from
        toStyle = to
    }
    
    func updateTransition(currentTime: CFTimeInterval) -> Float {
        guard isTransitioning else { return 1.0 }
        
        let elapsed = Float(currentTime - transitionStartTime)
        transitionProgress = min(elapsed / transitionDuration, 1.0)
        
        if transitionProgress >= 1.0 {
            isTransitioning = false
            fromStyle = nil
        }
        
        return transitionProgress
    }
    
    var needsDoubleRender: Bool {
        isTransitioning
    }
}
```

### Зміни в MetalVisualizerRenderer.swift

```swift
private let transitionManager = VisualizerTransitionManager()

func draw(in view: MTKView) {
    // ... existing code ...
    
    if transitionManager.needsDoubleRender {
        // Рендерити обидва шейдери
        let alpha = transitionManager.updateTransition(currentTime: CACurrentMediaTime())
        
        // Render fromStyle to textureA
        renderToTexture(style: transitionManager.fromStyle!, texture: tempTextureA)
        
        // Render toStyle to textureB
        renderToTexture(style: transitionManager.toStyle!, texture: tempTextureB)
        
        // Blend з alpha
        blendTextures(a: tempTextureA, b: tempTextureB, alpha: alpha, output: drawable)
    } else {
        // Звичайний рендеринг одного шейдера
        renderNormal(style: currentStyle, output: drawable)
    }
}
```

### Результат
- Плавні переходи як у MilkDrop
- Візуалізації "перетікають" одна в одну
- Немає різких cuts

---

## 🎯 Фаза 4: Per-Frame Variables (Плавні коливання)

### Проблема
Параметри змінюються тільки від audio. MilkDrop має плавні sin/cos коливання навіть без музики.

### Рішення
Додати per-frame змінні які плавно коливаються.

### Зміни в VisualizerUniforms

```swift
struct VisualizerUniforms {
    // Існуючі
    var time: Float = 0
    var intensity: Float = 0
    var resolution: SIMD2<Float> = .zero
    var bass: Float = 0
    var mid: Float = 0
    var treble: Float = 0
    var peakLevel: Float = 0
    
    // Feedback
    var feedbackZoom: Float = 0.99
    var feedbackRotation: Float = 0.0
    var feedbackDecay: Float = 0.95
    
    // НОВІ per-frame змінні:
    var waveR: Float = 0.5  // плавно коливається для червоного каналу
    var waveG: Float = 0.5  // для зеленого
    var waveB: Float = 0.5  // для синього
    var zoom: Float = 1.0   // плавно коливається
    var rot: Float = 0.0    // плавно обертається
}
```

### Зміни в MetalVisualizerRenderer.swift

```swift
private func updateUniforms() {
    let currentTime = CACurrentMediaTime() - startTime
    uniforms.time = Float(currentTime)
    
    // Оновити per-frame змінні з плавними коливаннями
    // (як у MilkDrop per_frame equations)
    
    // Wave colors (для rainbow effects)
    uniforms.waveR += 0.4 * (0.6 * sin(0.980 * uniforms.time) + 0.4 * sin(1.047 * uniforms.time))
    uniforms.waveG += 0.4 * (0.6 * sin(0.835 * uniforms.time) + 0.4 * sin(1.081 * uniforms.time))
    uniforms.waveB += 0.4 * (0.6 * sin(0.814 * uniforms.time) + 0.4 * sin(1.011 * uniforms.time))
    
    // Keep in range [0, 1]
    uniforms.waveR = fmod(uniforms.waveR, 1.0)
    uniforms.waveG = fmod(uniforms.waveG, 1.0)
    uniforms.waveB = fmod(uniforms.waveB, 1.0)
    
    // Zoom oscillation
    uniforms.zoom = 1.0 + 0.013 * (0.6 * sin(0.339 * uniforms.time) + 0.4 * sin(0.276 * uniforms.time))
    
    // Rotation oscillation
    uniforms.rot += 0.010 * (0.6 * sin(0.381 * uniforms.time) + 0.4 * sin(0.579 * uniforms.time))
    
    // Feedback parameters (audio-reactive)
    uniforms.feedbackZoom = 0.99 + uniforms.bass * 0.02
    uniforms.feedbackRotation = sin(uniforms.time * 0.2) * 0.015 + uniforms.mid * 0.01
    uniforms.feedbackDecay = 0.95 - uniforms.bass * 0.05
    
    // ... rest of existing code ...
}
```

### Використання в шейдерах

```metal
fragment float4 plasmaFragment(...) {
    // Використати per-frame змінні для плавних ефектів
    float hue = plasma + uniforms.time * 0.1 + uniforms.waveR;
    float3 color = hsv2rgb(hue, 0.8, 0.9);
    
    // Zoom effect
    float2 uv = in.uv;
    uv = (uv - 0.5) * uniforms.zoom + 0.5;
    
    // Rotation effect
    float cs = cos(uniforms.rot);
    float sn = sin(uniforms.rot);
    uv = float2(
        uv.x * cs - uv.y * sn,
        uv.x * sn + uv.y * cs
    );
    
    // ...
}
```

---

## 📊 Очікувані результати

### До імплементації:
- ❌ Різкі, "дергані" рухи
- ❌ Немає motion blur
- ❌ Різкі переходи між візуалізаціями
- ❌ Статичні параметри

### Після імплементації:
- ✅ Плавні, органічні рухи
- ✅ Motion blur через feedback loop
- ✅ Smooth transitions (3-5 сек)
- ✅ Плавні коливання параметрів
- ✅ Як справжній MilkDrop! 🎉

---

## 🔧 Порядок імплементації

### День 1 (2-3 год):
1. ✅ Фаза 1: Feedback Loop (1.5 год)
   - Розширити feedback textures для всіх шейдерів
   - Оновити Metal шейдери
   - Тестувати кожен шейдер

2. ✅ Фаза 2: Audio Smoothing (30 хв)
   - Додати exponential filter
   - Тестувати плавність

### День 2 (2 год):
3. ✅ Фаза 3: Smooth Transitions (1 год)
   - Створити TransitionManager
   - Імплементувати double rendering
   - Тестувати transitions

4. ✅ Фаза 4: Per-Frame Variables (1 год)
   - Додати нові uniforms
   - Імплементувати коливання
   - Інтегрувати в шейдери

---

## 🎯 Критерії успіху

Візуалізації вважаються успішними якщо:

1. ✅ **Motion blur працює** - видно сліди від рухів
2. ✅ **Плавні переходи** - немає різких cuts
3. ✅ **Organic motion** - рухи виглядають природно
4. ✅ **Smooth audio reaction** - немає "дергань"
5. ✅ **Схожість з MilkDrop** - візуально близько до оригіналу

---

## 📝 Примітки

- Feedback loop - **найважливіша** техніка MilkDrop
- Audio smoothing робить величезну різницю у плавності
- Smooth transitions - це те, що робить MilkDrop професійним
- Per-frame variables додають "життя" візуалізаціям

**Час початку:** 14 лютого 2026, 13:35
**Очікуваний час завершення:** 14 лютого 2026, 17:35

Поїхали! 🚀
