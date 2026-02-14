//
//  MetalVisualizerView.swift
//  SystemEQ for Mac
//
//  SwiftUI wrapper for professional VisualizerEngine
//  Professional rendering with 60-120 FPS using Compute Shaders
//

import SwiftUI
import MetalKit
import Combine

// MARK: - Metal Visualizer View

struct MetalVisualizerView: NSViewRepresentable {
    
    @Binding var currentShader: ComputeShaderType
    @Binding var intensity: Float
    
    // Performance monitoring
    @Binding var currentFPS: Double
    @Binding var averageFrameTime: Double
    
    func makeNSView(context: Context) -> MTKView {
        dlog("🖱️ MetalVisualizerView.makeNSView called", level: .debug, category: .audio)
        
        let mtkView = MTKView()
        mtkView.wantsLayer = true
        mtkView.layer?.isOpaque = true
        mtkView.layer?.backgroundColor = NSColor.black.cgColor
        
        // Metal device
        guard let device = MTLCreateSystemDefaultDevice() else {
            dlog("⚠️ Metal is not supported", level: .error, category: .audio)
            return mtkView
        }
        
        mtkView.device = device
        
        // Create engine
        guard let engine = VisualizerEngine(device: device) else {
            dlog("⚠️ Failed to create VisualizerEngine", level: .error, category: .audio)
            return mtkView
        }
        
        // Store engine in coordinator
        context.coordinator.engine = engine
        
        // Set delegate
        mtkView.delegate = engine
        
        // Configure for maximum performance
        mtkView.preferredFramesPerSecond = 120  // Target 120 FPS
        mtkView.isPaused = false
        mtkView.enableSetNeedsDisplay = false
        
        // Subscribe to audio
        subscribeToAudio(engine: engine)
        
        // Subscribe to performance metrics
        engine.$currentFPS
            .receive(on: DispatchQueue.main)
            .assign(to: \.currentFPS, on: context.coordinator)
            .store(in: &context.coordinator.cancellables)
        
        engine.$averageFrameTime
            .receive(on: DispatchQueue.main)
            .assign(to: \.averageFrameTime, on: context.coordinator)
            .store(in: &context.coordinator.cancellables)
        
        dlog("✅ MetalVisualizerView initialized", category: .audio)
        
        return mtkView
    }
    
    func updateNSView(_ nsView: MTKView, context: Context) {
        guard let engine = context.coordinator.engine else { return }
        
        // Update shader
        if engine.currentShader != currentShader {
            engine.setShader(currentShader)
        }
        
        // Update intensity
        engine.setIntensity(intensity)
        
        // Update bindings
        DispatchQueue.main.async {
            currentFPS = context.coordinator.currentFPS
            averageFrameTime = context.coordinator.averageFrameTime
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(currentFPS: $currentFPS, averageFrameTime: $averageFrameTime)
    }
    
    // MARK: - Audio Subscription
    
    private func subscribeToAudio(engine: VisualizerEngine) {
        // Subscribe to audio data from AudioEngine
        NotificationCenter.default.publisher(for: NSNotification.Name("AudioSpectrumUpdated"))
            .compactMap { $0.userInfo?["waveform"] as? [Float] }
            .sink { samples in
                engine.updateAudio(samples: samples)
            }
            .store(in: &Coordinator.staticCancellables)
    }
    
    // MARK: - Coordinator
    
    class Coordinator {
        var engine: VisualizerEngine?
        var cancellables = Set<AnyCancellable>()
        static var staticCancellables = Set<AnyCancellable>()
        
        @Binding var currentFPS: Double
        @Binding var averageFrameTime: Double
        
        init(currentFPS: Binding<Double>, averageFrameTime: Binding<Double>) {
            _currentFPS = currentFPS
            _averageFrameTime = averageFrameTime
        }
    }
}

// MARK: - Preview

struct MetalVisualizerView_Previews: PreviewProvider {
    static var previews: some View {
        MetalVisualizerView(
            currentShader: .constant(.plasma),
            intensity: .constant(0.5),
            currentFPS: .constant(60.0),
            averageFrameTime: .constant(16.67)
        )
        .frame(width: 800, height: 600)
    }
}
