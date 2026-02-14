//
//  VisualizerShaderTypes.h
//  SystemEQ for Mac
//
//  Shared types between Metal shader files
//

#ifndef VisualizerShaderTypes_h
#define VisualizerShaderTypes_h

#ifdef __METAL_VERSION__
// Metal Shading Language (metal_stdlib and namespace already included by .metal files)

struct VisualizerUniforms {
    float time;
    float intensity;
    float2 resolution;
    float bass;
    float mid;
    float treble;
    float peakLevel;
    
    // Feedback parameters (MilkDrop-style motion blur)
    float feedbackZoom;      // 0.98-1.02, zoom for feedback texture
    float feedbackRotation;  // -0.02 to +0.02, rotation for feedback
    float feedbackDecay;     // 0.90-0.98, blend factor (higher = more trails)
    
    // Per-frame variables (smooth oscillations like MilkDrop)
    float waveR;  // 0-1, smooth color wave for red channel
    float waveG;  // 0-1, smooth color wave for green channel
    float waveB;  // 0-1, smooth color wave for blue channel
    float zoom;   // ~1.0, smooth zoom oscillation
    float rot;    // smooth rotation accumulator
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

#else
// C/C++/Swift bridging
#include <simd/simd.h>

struct VisualizerUniformsShared {
    float time;
    float intensity;
    simd_float2 resolution;
    float bass;
    float mid;
    float treble;
    float peakLevel;
    
    // Feedback parameters (MilkDrop-style motion blur)
    float feedbackZoom;      // 0.98-1.02, zoom for feedback texture
    float feedbackRotation;  // -0.02 to +0.02, rotation for feedback
    float feedbackDecay;     // 0.90-0.98, blend factor (higher = more trails)
    
    // Per-frame variables (smooth oscillations like MilkDrop)
    float waveR;  // 0-1, smooth color wave for red channel
    float waveG;  // 0-1, smooth color wave for green channel
    float waveB;  // 0-1, smooth color wave for blue channel
    float zoom;   // ~1.0, smooth zoom oscillation
    float rot;    // smooth rotation accumulator
};

#endif

#endif /* VisualizerShaderTypes_h */
