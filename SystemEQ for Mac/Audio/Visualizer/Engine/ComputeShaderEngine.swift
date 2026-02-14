//
//  ComputeShaderEngine.swift
//  SystemEQ for Mac
//
//  Professional Metal Compute Shader Engine
//  Replaces Fragment Shaders with Compute Shaders for better performance
//

import Metal
import MetalKit
import simd

// MARK: - Shader Types

enum ComputeShaderType: String, CaseIterable {
    case spectrum = "spectrumCompute"
    case waveform = "waveformCompute"
    case plasma = "plasmaCompute"
    case tunnel = "tunnelCompute"
    case galaxy = "galaxyCompute"
    case particles = "particlesCompute"

    var functionName: String {
        rawValue
    }
}

// MARK: - Uniforms (matching Metal shader)

struct ComputeUniforms {
    var time: Float = 0
    var resolution: SIMD2<Float> = SIMD2(1920, 1080)
    var bass: Float = 0
    var mid: Float = 0
    var treble: Float = 0
    var intensity: Float = 0.5
    var peakLevel: Float = 0

    // MilkDrop-style variables
    var waveR: Float = 0.5
    var waveG: Float = 0.5
    var waveB: Float = 0.5
    var zoom: Float = 1.0
    var rot: Float = 0

    // Feedback parameters
    var feedbackZoom: Float = 1.0
    var feedbackRotation: Float = 0
    var feedbackDecay: Float = 0.95
}

// MARK: - Compute Shader Engine

final class ComputeShaderEngine {
    // Metal objects
    private let device: MTLDevice
    private let library: MTLLibrary

    /// Compute pipelines (cached)
    private var pipelines: [ComputeShaderType: MTLComputePipelineState] = [:]

    // Buffers
    private var uniformBuffer: MTLBuffer?
    private var spectrumBuffer: MTLBuffer?

    // Textures
    private var outputTexture: MTLTexture?
    private var feedbackTextureA: MTLTexture?
    private var feedbackTextureB: MTLTexture?
    private var useFeedbackA: Bool = true

    /// Uniforms
    private var uniforms = ComputeUniforms()

    /// Thread group size (optimized for Apple Silicon)
    private let threadGroupSize = MTLSize(width: 16, height: 16, depth: 1)

    // MARK: - Initialization

    init?(device: MTLDevice) {
        self.device = device

        guard let library = device.makeDefaultLibrary() else {
            dlog("⚠️ Failed to create Metal library", level: .error, category: .audio)
            return nil
        }
        self.library = library

        // Create buffers
        setupBuffers()

        // Precompile all shaders
        precompileShaders()

        dlog("✅ ComputeShaderEngine initialized", category: .audio)
    }

    // MARK: - Setup

    private func setupBuffers() {
        uniformBuffer = device.makeBuffer(
            length: MemoryLayout<ComputeUniforms>.size,
            options: .storageModeShared
        )

        spectrumBuffer = device.makeBuffer(
            length: MemoryLayout<Float>.size * 256,
            options: .storageModeShared
        )
    }

    private func precompileShaders() {
        for shaderType in ComputeShaderType.allCases {
            if let pipeline = createComputePipeline(for: shaderType) {
                pipelines[shaderType] = pipeline
                dlog("✅ Compiled: \(shaderType.rawValue)", category: .audio)
            } else {
                dlog(
                    "⚠️ Failed to compile: \(shaderType.rawValue)",
                    level: .error,
                    category: .audio
                )
            }
        }
    }

    private func createComputePipeline(
        for type: ComputeShaderType
    ) -> MTLComputePipelineState? {
        guard let function = library.makeFunction(name: type.functionName) else {
            return nil
        }

        do {
            return try device.makeComputePipelineState(function: function)
        } catch {
            dlog(
                "Pipeline error for \(type.functionName): \(error)",
                level: .error,
                category: .audio
            )
            return nil
        }
    }

    // MARK: - Texture Management

    func ensureTextures(width: Int, height: Int) {
        // Check if textures need recreation
        if let existing = outputTexture,
           existing.width == width, existing.height == height {
            return
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .private

        outputTexture = device.makeTexture(descriptor: descriptor)
        feedbackTextureA = device.makeTexture(descriptor: descriptor)
        feedbackTextureB = device.makeTexture(descriptor: descriptor)

        dlog("📐 Textures created: \(width)x\(height)", category: .audio)
    }

    // MARK: - Rendering

    func render(
        commandBuffer: MTLCommandBuffer,
        shaderType: ComputeShaderType,
        audioFeatures: AudioFeatures,
        outputTexture: MTLTexture
    ) {
        guard let pipeline = pipelines[shaderType] else {
            dlog("⚠️ Pipeline not found: \(shaderType)", level: .error, category: .audio)
            return
        }

        guard let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            dlog("⚠️ Failed to create compute encoder", level: .error, category: .audio)
            return
        }

        computeEncoder.label = "Compute: \(shaderType.rawValue)"

        // Update uniforms
        updateUniforms(
            audioFeatures: audioFeatures,
            resolution: SIMD2(
                Float(outputTexture.width),
                Float(outputTexture.height)
            )
        )

        // Set pipeline
        computeEncoder.setComputePipelineState(pipeline)

        // Set textures
        computeEncoder.setTexture(outputTexture, index: 0)

        // Set feedback texture if needed
        if needsFeedback(shaderType) {
            let feedbackTexture = useFeedbackA ? feedbackTextureA : feedbackTextureB
            computeEncoder.setTexture(feedbackTexture, index: 1)
        }

        // Set buffers
        if let uniformBuffer {
            var uniformsCopy = uniforms
            uniformBuffer.contents().copyMemory(
                from: &uniformsCopy,
                byteCount: MemoryLayout<ComputeUniforms>.size
            )
            computeEncoder.setBuffer(uniformBuffer, offset: 0, index: 0)
        }

        if let spectrumBuffer {
            var spectrumCopy = audioFeatures.spectrum
            let copySize = min(spectrumCopy.count, 256) * MemoryLayout<Float>.size
            spectrumBuffer.contents().copyMemory(
                from: &spectrumCopy,
                byteCount: copySize
            )
            computeEncoder.setBuffer(spectrumBuffer, offset: 0, index: 1)
        }

        // Calculate thread groups
        let threadGroupCount = MTLSize(
            width: (outputTexture.width + threadGroupSize.width - 1) / threadGroupSize.width,
            height: (outputTexture.height + threadGroupSize.height - 1) / threadGroupSize.height,
            depth: 1
        )

        // Dispatch
        computeEncoder.dispatchThreadgroups(
            threadGroupCount,
            threadsPerThreadgroup: threadGroupSize
        )

        // End encoding
        computeEncoder.endEncoding()

        // Copy output to feedback for next frame
        if needsFeedback(shaderType) {
            copyToFeedback(commandBuffer: commandBuffer, source: outputTexture)
        }
    }

    // MARK: - Uniforms Update

    private func updateUniforms(audioFeatures: AudioFeatures, resolution: SIMD2<Float>) {
        uniforms.time = Float(audioFeatures.timestamp)
        uniforms.resolution = resolution
        uniforms.bass = audioFeatures.bass
        uniforms.mid = audioFeatures.mid
        uniforms.treble = audioFeatures.highMid
        uniforms.peakLevel = audioFeatures.peakLevel

        // MilkDrop-style per-frame variables
        let t = uniforms.time
        uniforms.waveR += 0.4 * (0.6 * sin(0.980 * t) + 0.4 * sin(1.047 * t))
        uniforms.waveG += 0.4 * (0.6 * sin(0.835 * t) + 0.4 * sin(1.081 * t))
        uniforms.waveB += 0.4 * (0.6 * sin(0.814 * t) + 0.4 * sin(1.011 * t))

        uniforms.waveR = uniforms.waveR.truncatingRemainder(dividingBy: 1.0)
        uniforms.waveG = uniforms.waveG.truncatingRemainder(dividingBy: 1.0)
        uniforms.waveB = uniforms.waveB.truncatingRemainder(dividingBy: 1.0)

        uniforms.zoom = 1.0 + 0.013 * (0.6 * sin(0.339 * t) + 0.4 * sin(0.276 * t))
        uniforms.rot += 0.010 * (0.6 * sin(0.381 * t) + 0.4 * sin(0.579 * t))

        // Feedback parameters
        uniforms.feedbackZoom = 0.99 + audioFeatures.bass * 0.02
        uniforms.feedbackRotation = sin(t * 0.2) * 0.015 + audioFeatures.mid * 0.01
        uniforms.feedbackDecay = 0.95 - audioFeatures.bass * 0.05
    }

    // MARK: - Feedback

    private func needsFeedback(_ type: ComputeShaderType) -> Bool {
        switch type {
        case .galaxy,
             .plasma,
             .tunnel:
            true
        default:
            false
        }
    }

    private func copyToFeedback(commandBuffer: MTLCommandBuffer, source: MTLTexture) {
        guard let blitEncoder = commandBuffer.makeBlitCommandEncoder() else {
            return
        }

        let destination = useFeedbackA ? feedbackTextureB : feedbackTextureA

        if let dest = destination {
            blitEncoder.copy(
                from: source,
                sourceSlice: 0,
                sourceLevel: 0,
                sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                sourceSize: MTLSize(width: source.width, height: source.height, depth: 1),
                to: dest,
                destinationSlice: 0,
                destinationLevel: 0,
                destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
            )
        }

        blitEncoder.endEncoding()
        useFeedbackA.toggle()
    }

    // MARK: - Public API

    func setIntensity(_ value: Float) {
        uniforms.intensity = max(0.0, min(1.0, value))
    }
}
