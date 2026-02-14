//
//  VisualizerEngine.swift
//  SystemEQ for Mac
//
//  Professional VisualizerEngine with Compute Shaders
//  Combines AudioAnalyzer, ComputeShaderEngine, and AsyncRenderer
//

import Metal
import MetalKit
import Combine

// MARK: - Visualizer Engine

final class VisualizerEngine: NSObject, MTKViewDelegate {
    
    // Components
    private let device: MTLDevice
    private let audioAnalyzer: AudioAnalyzer
    private let computeEngine: ComputeShaderEngine
    private let asyncRenderer: AsyncRenderer
    
    // Current state
    @Published var currentShader: ComputeShaderType = .plasma
    @Published var intensity: Float = 0.5
    
    // Audio data (thread-safe)
    private let dataLock = NSLock()
    private var audioSamples: [Float] = []
    private var currentFeatures: AudioFeatures?
    
    // Performance monitoring
    @Published var currentFPS: Double = 0
    @Published var averageFrameTime: Double = 0
    
    // Render pass descriptor
    private let renderPassDescriptor = MTLRenderPassDescriptor()
    
    // MARK: - Initialization
    
    init?(device: MTLDevice) {
        self.device = device
        
        // Create components
        self.audioAnalyzer = AudioAnalyzer(fftSize: 2048, hopSize: 512)
        
        guard let computeEngine = ComputeShaderEngine(device: device) else {
            dlog("⚠️ Failed to create ComputeShaderEngine", level: .error, category: .audio)
            return nil
        }
        self.computeEngine = computeEngine
        
        guard let asyncRenderer = AsyncRenderer(device: device) else {
            dlog("⚠️ Failed to create AsyncRenderer", level: .error, category: .audio)
            return nil
        }
        self.asyncRenderer = asyncRenderer
        
        super.init()
        
        // Subscribe to renderer performance
        asyncRenderer.$currentFPS
            .assign(to: &$currentFPS)
        
        asyncRenderer.$averageFrameTime
            .assign(to: &$averageFrameTime)
        
        dlog("✅ VisualizerEngine initialized", category: .audio)
    }
    
    // MARK: - Audio Input
    
    func updateAudio(samples: [Float]) {
        dataLock.lock()
        audioSamples = samples
        dataLock.unlock()
    }
    
    // MARK: - Public API
    
    func setShader(_ shader: ComputeShaderType) {
        currentShader = shader
        dlog("🎨 Shader changed to: \(shader.rawValue)", category: .audio)
    }
    
    func setIntensity(_ value: Float) {
        intensity = max(0.0, min(1.0, value))
        computeEngine.setIntensity(intensity)
        dlog("🎚️ Intensity set to: \(intensity)", category: .audio)
    }
    
    // MARK: - MTKViewDelegate
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        computeEngine.ensureTextures(width: Int(size.width), height: Int(size.height))
        dlog("📐 Drawable size changed: \(size)", category: .audio)
    }
    
    func draw(in view: MTKView) {
        // Get drawable
        guard let drawable = view.currentDrawable else {
            return
        }
        
        // Analyze audio
        dataLock.lock()
        let samples = audioSamples
        dataLock.unlock()
        
        let features = audioAnalyzer.analyze(samples: samples)
        currentFeatures = features
        
        // Render using compute shader
        asyncRenderer.renderCompute(drawable: drawable) { [weak self] commandBuffer, _ in
            guard let self = self else { return }
            
            // Get output texture
            let outputTexture = drawable.texture
            
            // Render with compute shader
            self.computeEngine.render(
                commandBuffer: commandBuffer,
                shaderType: self.currentShader,
                audioFeatures: features,
                outputTexture: outputTexture
            )
        }
    }
}
