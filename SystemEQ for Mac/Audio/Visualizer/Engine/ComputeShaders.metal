//
//  ComputeShaders.metal
//  SystemEQ for Mac
//
//  Professional Metal Compute Shaders for VisualizerEngine v2
//  Optimized for Apple Silicon - 60-120 FPS target
//

#include <metal_stdlib>
using namespace metal;

// MARK: - Uniforms

struct ComputeUniforms {
    float time;
    float2 resolution;
    float bass;
    float mid;
    float treble;
    float intensity;
    float peakLevel;
    
    // MilkDrop-style variables
    float waveR;
    float waveG;
    float waveB;
    float zoom;
    float rot;
    
    // Feedback parameters
    float feedbackZoom;
    float feedbackRotation;
    float feedbackDecay;
};

// MARK: - Utility Functions

// Hash function for noise
float hash(float2 p) {
    float h = dot(p, float2(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

// 2D Noise
float noise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    
    float a = hash(i);
    float b = hash(i + float2(1.0, 0.0));
    float c = hash(i + float2(0.0, 1.0));
    float d = hash(i + float2(1.0, 1.0));
    
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Fractional Brownian Motion (optimized - 3 octaves)
float fbm(float2 p, float time) {
    float value = 0.0;
    float amplitude = 0.5;
    float frequency = 1.0;
    
    for (int i = 0; i < 3; i++) {
        value += amplitude * noise(p * frequency + time * 0.1);
        frequency *= 2.0;
        amplitude *= 0.5;
    }
    
    return value;
}

// Smooth HSV to RGB conversion
float3 hsv2rgb(float3 c) {
    float4 K = float4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    float3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

// MARK: - SPECTRUM COMPUTE SHADER

kernel void spectrumCompute(
    texture2d<float, access::write> output [[texture(0)]],
    constant ComputeUniforms &uniforms [[buffer(0)]],
    constant float *spectrum [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    // Normalized coordinates
    float2 resolution = uniforms.resolution;
    float2 uv = float2(gid) / resolution;
    
    // Spectrum visualization
    int numBars = 64;
    int barIndex = int(uv.x * float(numBars));
    barIndex = clamp(barIndex, 0, numBars - 1);
    
    float barHeight = spectrum[barIndex] * uniforms.intensity * 2.0;
    float barWidth = 1.0 / float(numBars);
    
    // Bar position
    float barX = float(barIndex) / float(numBars);
    float distX = abs(uv.x - (barX + barWidth * 0.5)) / barWidth;
    
    // Color based on frequency
    float hue = float(barIndex) / float(numBars);
    float3 color = hsv2rgb(float3(hue, 0.8, 1.0));
    
    // Draw bar
    float alpha = 0.0;
    if (distX < 0.4 && uv.y < barHeight) {
        alpha = 1.0 - distX * 2.5;
    }
    
    // Glow effect
    float glow = exp(-abs(uv.y - barHeight) * 20.0) * 0.3;
    alpha += glow;
    
    // Output
    float3 finalColor = color * alpha;
    output.write(float4(finalColor, 1.0), gid);
}

// MARK: - WAVEFORM COMPUTE SHADER

kernel void waveformCompute(
    texture2d<float, access::write> output [[texture(0)]],
    constant ComputeUniforms &uniforms [[buffer(0)]],
    constant float *spectrum [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    float2 resolution = uniforms.resolution;
    float2 uv = float2(gid) / resolution;
    
    // Waveform from spectrum (approximation)
    int sampleIndex = int(uv.x * 64.0);
    sampleIndex = clamp(sampleIndex, 0, 63);
    
    float waveValue = spectrum[sampleIndex] * 0.5;
    float centerY = 0.5;
    float waveY = centerY + waveValue * sin(uniforms.time * 2.0 + uv.x * 10.0);
    
    // Distance to waveform
    float dist = abs(uv.y - waveY);
    
    // Color
    float3 color = float3(
        0.5 + 0.5 * sin(uniforms.time + uv.x * 3.0),
        0.5 + 0.5 * sin(uniforms.time * 1.3 + uv.x * 3.0),
        0.5 + 0.5 * sin(uniforms.time * 1.7 + uv.x * 3.0)
    );
    
    // Line thickness
    float alpha = smoothstep(0.02, 0.0, dist);
    
    // Glow
    alpha += exp(-dist * 50.0) * 0.3;
    
    output.write(float4(color * alpha, 1.0), gid);
}

// MARK: - PLASMA COMPUTE SHADER

kernel void plasmaCompute(
    texture2d<float, access::write> output [[texture(0)]],
    texture2d<float, access::read> feedback [[texture(1)]],
    constant ComputeUniforms &uniforms [[buffer(0)]],
    constant float *spectrum [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    float2 resolution = uniforms.resolution;
    float2 uv = float2(gid) / resolution;
    float t = uniforms.time * 0.5;
    
    // Audio reactivity (smooth)
    float bassBoost = pow(uniforms.bass, 2.0) * 1.0;
    float midBoost = pow(uniforms.mid, 1.8) * 0.8;
    float trebleBoost = pow(uniforms.treble, 1.6) * 0.6;
    
    // Domain warping layer 1
    float2 q = float2(
        fbm(uv * 3.0 + float2(0.0, t * 0.2), t),
        fbm(uv * 3.0 + float2(5.2, t * 0.15), t)
    );
    
    // Domain warping layer 2
    float2 r = float2(
        fbm(uv * 2.0 + 4.0 * q + float2(1.7, 9.2) + bassBoost, t),
        fbm(uv * 2.0 + 4.0 * q + float2(8.3, 2.8) + midBoost, t)
    );
    
    // Plasma waves
    float plasma = 0.0;
    plasma += sin(uv.x * 10.0 + t + bassBoost * 2.0);
    plasma += sin(uv.y * 10.0 + t * 1.3 + midBoost * 2.0);
    plasma += sin((uv.x + uv.y) * 10.0 + t * 1.7 + trebleBoost);
    plasma += sin(length(uv - 0.5) * 20.0 + t * 2.0);
    plasma *= 0.25;
    
    // Add domain warping influence
    plasma += fbm(uv + r, t) * 0.5;
    
    // Color mapping
    float hue = plasma + t * 0.1 + uniforms.waveR;
    float sat = 0.6 + midBoost * 0.4;
    float val = 0.5 + bassBoost * 0.5;
    
    float3 color = hsv2rgb(float3(hue, sat, val)) * uniforms.intensity;
    
    // Feedback loop
    if (feedback.get_width() > 0) {
        float3 feedbackColor = feedback.read(gid).rgb;
        color = mix(color, feedbackColor, uniforms.feedbackDecay);
    }
    
    output.write(float4(color, 1.0), gid);
}

// MARK: - TUNNEL COMPUTE SHADER

kernel void tunnelCompute(
    texture2d<float, access::write> output [[texture(0)]],
    texture2d<float, access::read> feedback [[texture(1)]],
    constant ComputeUniforms &uniforms [[buffer(0)]],
    constant float *spectrum [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    float2 resolution = uniforms.resolution;
    float2 uv = float2(gid) / resolution * 2.0 - 1.0;
    uv.x *= resolution.x / resolution.y;
    
    float t = uniforms.time;
    
    // Audio reactivity
    float bassBoost = pow(uniforms.bass, 1.8) * 2.0;
    float midBoost = pow(uniforms.mid, 1.5) * 1.5;
    
    // Polar coordinates
    float r = length(uv);
    float angle = atan2(uv.y, uv.x);
    
    // Tunnel depth
    float depth = 1.0 / (r + 0.1) + t * 0.5 + bassBoost;
    
    // Spiral rotation
    float spiralAngle = angle + depth * 0.5 + midBoost * 0.3;
    
    // Tunnel texture coordinates
    float2 tunnelUV = float2(spiralAngle / (2.0 * M_PI_F), depth);
    
    // Noise layers (optimized - 2 octaves)
    float noise1 = fbm(tunnelUV * 3.0, t);
    float noise2 = fbm(tunnelUV * 6.0 + float2(5.2, 1.3), t);
    
    // Combine
    float pattern = noise1 * 0.6 + noise2 * 0.4;
    
    // Color
    float hue = pattern + t * 0.1 + uniforms.waveG;
    float sat = 0.7 + bassBoost * 0.3;
    float val = 0.6 + midBoost * 0.4;
    
    float3 color = hsv2rgb(float3(hue, sat, val));
    
    // Vignette
    float vignette = 1.0 - smoothstep(0.5, 1.5, r);
    color *= vignette;
    
    // Intensity
    color *= uniforms.intensity;
    
    // Feedback
    if (feedback.get_width() > 0) {
        float3 feedbackColor = feedback.read(gid).rgb;
        color = mix(color, feedbackColor, uniforms.feedbackDecay);
    }
    
    output.write(float4(color, 1.0), gid);
}

// MARK: - GALAXY COMPUTE SHADER

kernel void galaxyCompute(
    texture2d<float, access::write> output [[texture(0)]],
    texture2d<float, access::read> feedback [[texture(1)]],
    constant ComputeUniforms &uniforms [[buffer(0)]],
    constant float *spectrum [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    float2 resolution = uniforms.resolution;
    float2 uv = float2(gid) / resolution * 2.0 - 1.0;
    uv.x *= resolution.x / resolution.y;
    
    float t = uniforms.time;
    
    // Smooth audio response
    float bassBoost = pow(uniforms.bass, 2.0) * 1.2;
    float midBoost = pow(uniforms.mid, 1.8) * 0.8;
    float trebleBoost = pow(uniforms.treble, 1.5) * 0.6;
    
    float r = length(uv);
    
    // Differential rotation
    float rotSpeed = 0.2 + 0.3 / (r + 0.5);
    float rotAngle = t * rotSpeed + bassBoost * 0.3;
    
    float2 rotUV = float2(
        uv.x * cos(rotAngle) - uv.y * sin(rotAngle),
        uv.x * sin(rotAngle) + uv.y * cos(rotAngle)
    );
    
    float rotR = length(rotUV);
    float rotAngleCoord = atan2(rotUV.y, rotUV.x);
    
    // Spiral arms (smooth changes)
    float numArms = 3.0 + floor(midBoost * 1.0);
    float spiralTightness = 8.0 + trebleBoost * 1.5;
    
    float spiralPattern = sin(numArms * rotAngleCoord - spiralTightness * log(rotR + 0.1));
    spiralPattern = smoothstep(-0.3, 0.3, spiralPattern);
    
    // Noise for texture
    float noiseValue = fbm(rotUV * 2.0, t) * 0.5 + 0.5;
    
    // Combine
    float brightness = spiralPattern * noiseValue;
    brightness *= exp(-rotR * 0.8);
    
    // Color
    float hue = rotAngleCoord / (2.0 * M_PI_F) + t * 0.05 + uniforms.waveB;
    float sat = 0.7 + bassBoost * 0.3;
    float val = brightness * (0.8 + midBoost * 0.2);
    
    float3 color = hsv2rgb(float3(hue, sat, val)) * uniforms.intensity;
    
    // Core glow
    float coreGlow = exp(-rotR * 5.0) * 0.5;
    color += float3(1.0, 0.9, 0.7) * coreGlow;
    
    // Feedback
    if (feedback.get_width() > 0) {
        float3 feedbackColor = feedback.read(gid).rgb;
        color = mix(color, feedbackColor, uniforms.feedbackDecay);
    }
    
    output.write(float4(color, 1.0), gid);
}

// MARK: - PARTICLES COMPUTE SHADER (OPTIMIZED)

kernel void particlesCompute(
    texture2d<float, access::write> output [[texture(0)]],
    constant ComputeUniforms &uniforms [[buffer(0)]],
    constant float *spectrum [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    float2 resolution = uniforms.resolution;
    float2 uv = float2(gid) / resolution;
    float t = uniforms.time;
    
    // Audio
    float bassBoost = pow(uniforms.bass, 1.5) * 1.5;
    float midBoost = pow(uniforms.mid, 1.3) * 1.2;
    float trebleBoost = pow(uniforms.treble, 1.4) * 1.0;
    
    float3 color = float3(0.0);
    
    // Optimized: 2 layers instead of 4
    for (int layer = 0; layer < 2; layer++) {
        float fl = float(layer);
        float depth = 1.0 - fl * 0.2;
        float layerOffset = fl * 1.337;
        float layerSpeed = 0.4 + fl * 0.25;
        float particleSize = (0.018 - fl * 0.004) * depth;
        
        // Optimized: 8x6 grid instead of 14x10
        for (int i = 0; i < 8; i++) {
            for (int j = 0; j < 6; j++) {
                float fi = float(i);
                float fj = float(j);
                
                // Particle position
                float2 basePos = float2(fi / 8.0, fj / 6.0);
                float phaseX = hash(basePos + layerOffset) * 6.28;
                float phaseY = hash(basePos + layerOffset + 1.0) * 6.28;
                
                float2 offset = float2(
                    sin(t * layerSpeed + phaseX + bassBoost) * 0.1,
                    cos(t * layerSpeed * 0.8 + phaseY + midBoost) * 0.1
                );
                
                float2 particlePos = basePos + offset;
                
                // Distance
                float dist = length(uv - particlePos);
                
                // Particle brightness
                float brightness = smoothstep(particleSize, 0.0, dist);
                brightness += exp(-dist * 100.0) * 0.3;
                
                // Color
                float hue = hash(basePos) + t * 0.1 + trebleBoost * 0.2;
                float3 particleColor = hsv2rgb(float3(hue, 0.8, 1.0));
                
                color += particleColor * brightness * depth;
            }
        }
    }
    
    color *= uniforms.intensity;
    output.write(float4(color, 1.0), gid);
}
