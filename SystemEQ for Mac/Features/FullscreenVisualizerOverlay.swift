//
//  FullscreenVisualizerOverlay.swift
//  SystemEQ for Mac
//
//  Custom fullscreen overlay for smooth visualization transitions
//

import AppKit
import Combine
import SwiftUI
import Metal
import MetalKit

/// Custom window that can become key to receive events
class FullscreenOverlayWindow: NSWindow {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }
}

/// Manages a fullscreen overlay window for the visualizer
class FullscreenOverlayManager {
    static let shared = FullscreenOverlayManager()

    private var overlayWindow: FullscreenOverlayWindow?
    var isShowingOverlay = false

    private init() {}

    private var eventMonitor: Any?

    func showFullscreen(shader: ComputeShaderType, intensity: Float) {
        guard overlayWindow == nil else { return }

        // Get main screen
        guard let screen = NSScreen.main else { return }

        // Create borderless window covering entire screen
        let window = FullscreenOverlayWindow(
            contentRect: screen.frame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        // CRITICAL: Use .screenSaver level to hide Dock and menu bar
        window.level = .screenSaver
        window.collectionBehavior = [.fullScreenPrimary, .stationary, .ignoresCycle]
        window.backgroundColor = .black
        window.isOpaque = true
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.isReleasedWhenClosed = false
        window.acceptsMouseMovedEvents = true

        // Create SwiftUI content
        let contentView = FullscreenVisualizerContent(
            shader: shader,
            intensity: intensity,
            onDismiss: { [weak self] in
                self?.hideFullscreen()
            }
        )

        window.contentView = NSHostingView(rootView: contentView)

        // Install event monitor for clicks and keyboard
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [
            .leftMouseUp,
            .rightMouseUp,
            .keyDown
        ]) { [weak self] _ in
            // Any click or key press exits fullscreen
            self?.hideFullscreen()
            return nil // consume the event
        }

        // Fade in animation
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().alphaValue = 1.0
        }

        overlayWindow = window
        isShowingOverlay = true
    }

    func hideFullscreen() {
        guard let window = overlayWindow else { return }

        // Remove event monitor
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }

        // Fade out animation
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().alphaValue = 0
        } completionHandler: {
            window.close()
            self.overlayWindow = nil
            self.isShowingOverlay = false
        }
    }
}

/// SwiftUI content for fullscreen overlay
struct FullscreenVisualizerContent: View {
    let shader: ComputeShaderType
    let intensity: Float
    let onDismiss: () -> Void
    
    @State private var fps: Double = 0
    @State private var frameTime: Double = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            MetalVisualizerView(
                currentShader: .constant(shader),
                intensity: .constant(intensity),
                currentFPS: $fps,
                averageFrameTime: $frameTime
            )
            .ignoresSafeArea()
        }
    }
}
