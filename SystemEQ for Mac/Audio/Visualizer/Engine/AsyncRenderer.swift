//
//  AsyncRenderer.swift
//  SystemEQ for Mac
//
//  Async rendering with triple buffering for maximum performance
//  GPU works in parallel with CPU - no stalls, stable FPS
//

import Combine
import Metal
import MetalKit

// MARK: - Async Renderer

final class AsyncRenderer {
    // Metal objects
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue

    // Triple buffering (3 in-flight command buffers)
    private let maxBuffersInFlight = 3
    private let inFlightSemaphore: DispatchSemaphore

    // Frame timing
    private var frameCount: UInt64 = 0
    private var lastFrameTime: CFTimeInterval = 0
    private var frameTimeHistory: [Double] = []

    // Performance monitoring
    @Published var currentFPS: Double = 0
    @Published var averageFrameTime: Double = 0
    @Published var gpuUtilization: Double = 0

    // MARK: - Initialization

    init?(device: MTLDevice) {
        self.device = device

        guard let queue = device.makeCommandQueue() else {
            return nil
        }
        self.commandQueue = queue

        // Create semaphore for triple buffering
        self.inFlightSemaphore = DispatchSemaphore(value: maxBuffersInFlight)

        dlog("✅ AsyncRenderer initialized with triple buffering", category: .audio)
    }

    // MARK: - Rendering

    func render(
        drawable: CAMetalDrawable,
        renderPass: MTLRenderPassDescriptor,
        encodeCommands: (MTLCommandBuffer, MTLRenderCommandEncoder) -> Void
    ) {
        // Wait for available buffer (blocks if 3 buffers in flight)
        _ = inFlightSemaphore.wait(timeout: .distantFuture)

        // Create command buffer
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            inFlightSemaphore.signal()
            dlog("⚠️ Failed to create command buffer", level: .error, category: .audio)
            return
        }

        // Label for debugging
        commandBuffer.label = "Frame \(frameCount)"

        // Add completion handler to signal semaphore
        commandBuffer.addCompletedHandler { [weak self] buffer in
            self?.inFlightSemaphore.signal()
            self?.updatePerformanceMetrics(buffer)
        }

        // Set render pass descriptor
        renderPass.colorAttachments[0].texture = drawable.texture
        renderPass.colorAttachments[0].loadAction = .clear
        renderPass.colorAttachments[0].clearColor = MTLClearColor(
            red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0
        )
        renderPass.colorAttachments[0].storeAction = .store

        // Create render command encoder
        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(
            descriptor: renderPass
        ) else {
            inFlightSemaphore.signal()
            dlog("⚠️ Failed to create render encoder", level: .error, category: .audio)
            return
        }

        renderEncoder.label = "Render Encoder \(frameCount)"

        // Encode rendering commands (provided by caller)
        encodeCommands(commandBuffer, renderEncoder)

        // End encoding
        renderEncoder.endEncoding()

        // Present drawable
        commandBuffer.present(drawable)

        // Commit
        commandBuffer.commit()

        // Update frame count
        frameCount += 1

        // Update FPS
        updateFPS()
    }

    // MARK: - Compute Rendering (for compute shaders)

    func renderCompute(
        drawable: CAMetalDrawable,
        encodeCompute: (MTLCommandBuffer, MTLComputeCommandEncoder) -> Void
    ) {
        // Wait for available buffer
        _ = inFlightSemaphore.wait(timeout: .distantFuture)

        // Create command buffer
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            inFlightSemaphore.signal()
            dlog("⚠️ Failed to create command buffer", level: .error, category: .audio)
            return
        }

        commandBuffer.label = "Compute Frame \(frameCount)"

        // Add completion handler
        commandBuffer.addCompletedHandler { [weak self] buffer in
            self?.inFlightSemaphore.signal()
            self?.updatePerformanceMetrics(buffer)
        }

        // Create compute command encoder
        guard let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            inFlightSemaphore.signal()
            dlog("⚠️ Failed to create compute encoder", level: .error, category: .audio)
            return
        }

        computeEncoder.label = "Compute Encoder \(frameCount)"

        // Encode compute commands (provided by caller)
        encodeCompute(commandBuffer, computeEncoder)

        // End encoding
        computeEncoder.endEncoding()

        // Present drawable
        commandBuffer.present(drawable)

        // Commit
        commandBuffer.commit()

        // Update frame count
        frameCount += 1

        // Update FPS
        updateFPS()
    }

    // MARK: - Performance Monitoring

    private func updateFPS() {
        let currentTime = CACurrentMediaTime()

        if lastFrameTime > 0 {
            let deltaTime = currentTime - lastFrameTime

            // Add to history
            frameTimeHistory.append(deltaTime)
            if frameTimeHistory.count > 60 {
                frameTimeHistory.removeFirst()
            }

            // Calculate average
            let avgFrameTime = frameTimeHistory.reduce(0, +) / Double(frameTimeHistory.count)
            averageFrameTime = avgFrameTime * 1000.0 // Convert to ms

            // Calculate FPS
            currentFPS = 1.0 / avgFrameTime
        }

        lastFrameTime = currentTime
    }

    private func updatePerformanceMetrics(_ commandBuffer: MTLCommandBuffer) {
        // GPU time (available after completion)
        let gpuStartTime = commandBuffer.gpuStartTime
        let gpuEndTime = commandBuffer.gpuEndTime

        if gpuStartTime > 0, gpuEndTime > 0 {
            let gpuTime = gpuEndTime - gpuStartTime

            // Estimate GPU utilization (assuming 16.67ms per frame at 60 FPS)
            let frameTime = 1.0 / 60.0
            gpuUtilization = min(gpuTime / frameTime, 1.0)
        }
    }

    // MARK: - Utility

    func waitForCompletion() {
        // Wait for all in-flight buffers to complete
        for _ in 0..<maxBuffersInFlight {
            _ = inFlightSemaphore.wait(timeout: .distantFuture)
        }

        // Signal them back
        for _ in 0..<maxBuffersInFlight {
            inFlightSemaphore.signal()
        }
    }

    func reset() {
        frameCount = 0
        lastFrameTime = 0
        frameTimeHistory.removeAll()
        currentFPS = 0
        averageFrameTime = 0
        gpuUtilization = 0
    }
}
