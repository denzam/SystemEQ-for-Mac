import SwiftUI
import Metal
import MetalKit

struct VisualizerView: View {
    @ObservedObject private var localization = LocalizationManager.shared
    @State private var currentShader: ComputeShaderType = .plasma
    @State private var intensity: Double = 0.7
    @State private var isFullscreen: Bool = false
    @State private var metalViewID = UUID()
    @State private var showFPS: Bool = false
    @State private var currentFPS: Double = 0
    @State private var averageFrameTime: Double = 0

    var body: some View {
        Group {
            if isFullscreen {
                // Fullscreen: no container chrome, just the visualization
                ZStack {
                    Color.black.ignoresSafeArea()

                    MetalVisualizerView(
                        currentShader: $currentShader,
                        intensity: .constant(Float(intensity)),
                        currentFPS: $currentFPS,
                        averageFrameTime: $averageFrameTime
                    )
                    .id(metalViewID)
                    .ignoresSafeArea()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
            } else {
                // Normal: standard feature window container
                FeatureWindowContainer(
                    title: .visualizerTitle,
                    subtitle: .visualizerStyleColorsSubtitle,
                    windowSize: .wide,
                    hasScrollView: false
                ) {
                    VStack(spacing: 0) {
                        // MARK: - Controls Bar

                        controlsBar
                            .padding(.horizontal, AppSpacing.lg)
                            .padding(.bottom, AppSpacing.sm)

                        // MARK: - Visualization Canvas

                        MetalVisualizerView(
                            currentShader: $currentShader,
                            intensity: .constant(Float(intensity)),
                            currentFPS: $currentFPS,
                            averageFrameTime: $averageFrameTime
                        )
                        .id(metalViewID)
                        .cornerRadius(AppRadius.md)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal, AppSpacing.lg)
                        .padding(.bottom, AppSpacing.md)

                        // MARK: - Status Bar

                        statusBar
                            .padding(.horizontal, AppSpacing.lg)
                            .padding(.bottom, AppSpacing.md)
                    }
                }
            }
        }
        .onAppear {
            metalViewID = UUID()
        }
        .onReceive(NotificationCenter.default.publisher(for: .languageChanged)) { _ in
            // Force view refresh when language changes
        }

        // MARK: - Fullscreen Toggle (double-click or any key)

        .onReceive(NotificationCenter.default.publisher(for: .visualizerToggleFullscreen)) { notification in
            let exitOnly = notification.userInfo?["exitOnly"] as? Bool ?? false
            if exitOnly {
                // Key press or single click — only exit fullscreen
                if isFullscreen {
                    toggleFullscreen()
                }
            } else {
                // Double-click — toggle
                toggleFullscreen()
            }
        }
        // Track window fullscreen state changes (e.g. user presses green button)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { notification in
            if let window = notification.object as? NSWindow,
               window.identifier?.rawValue == FeatureID.visualizer.rawValue {
                withAnimation(.easeInOut(duration: 0.1)) {
                    isFullscreen = true
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { notification in
            if let window = notification.object as? NSWindow,
               window.identifier?.rawValue == FeatureID.visualizer.rawValue {
                withAnimation(.easeInOut(duration: 0.1)) {
                    isFullscreen = false
                }
                NSCursor.unhide()
            }
        }
    }

    // MARK: - Fullscreen

    private func toggleFullscreen() {
        if FullscreenOverlayManager.shared.isShowingOverlay {
            FullscreenOverlayManager.shared.hideFullscreen()
        } else {
            FullscreenOverlayManager.shared.showFullscreen(shader: currentShader, intensity: Float(intensity))
        }
    }

    private func nextShader() {
        let allShaders = ComputeShaderType.allCases
        guard let idx = allShaders.firstIndex(of: currentShader) else { return }
        let nextIdx = allShaders.index(after: idx)
        currentShader = nextIdx < allShaders.endIndex ? allShaders[nextIdx] : allShaders[allShaders.startIndex]
    }

    private func prevShader() {
        let allShaders = ComputeShaderType.allCases
        guard let idx = allShaders.firstIndex(of: currentShader) else { return }
        if idx == allShaders.startIndex {
            currentShader = allShaders[allShaders.index(before: allShaders.endIndex)]
        } else {
            currentShader = allShaders[allShaders.index(before: idx)]
        }
    }

    // MARK: - Controls Bar

    private var controlsBar: some View {
        HStack(spacing: AppSpacing.md) {
            // Previous
            Button(action: prevShader) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .help("Previous shader")

            // Shader picker
            Menu {
                ForEach(ComputeShaderType.allCases, id: \.self) { shader in
                    Button(action: { currentShader = shader }) {
                        Text(shader.rawValue)
                    }
                }
            } label: {
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: "cpu")
                        .font(.system(size: 12))
                    Text(currentShader.rawValue)
                        .font(AppTypography.labelSmall)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, AppSpacing.sm)
                .padding(.vertical, AppSpacing.xxs)
                .background(Color.green.opacity(0.2))
                .cornerRadius(AppRadius.xs)
            }
            .menuStyle(.borderlessButton)

            // Next
            Button(action: nextShader) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .help("Next shader")

            Spacer()

            // Fullscreen button
            Button(action: toggleFullscreen) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .help("Fullscreen (double-click visualization)")

            // Intensity slider
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "sun.min")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Slider(value: $intensity, in: 0.1...1.5)
                    .frame(width: 120)
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: AppSpacing.lg) {
            // Status indicator
            HStack(spacing: AppSpacing.xs) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)

                Text("Compute Shaders Active")
                    .font(AppTypography.labelSmall)
                    .foregroundColor(.secondary)
            }

            // FPS counter (toggle with click)
            Button(action: { showFPS.toggle() }) {
                HStack(spacing: 4) {
                    Image(systemName: "speedometer")
                        .font(.system(size: 10))
                    if showFPS {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(format: "%.1f FPS", currentFPS))
                                .font(AppTypography.monoSmall)
                            Text(String(format: "%.1f ms", averageFrameTime))
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Text("FPS")
                            .font(AppTypography.labelSmall)
                    }
                }
                .foregroundColor(fpsColor)
            }
            .buttonStyle(.plain)
            .help("Click to toggle FPS display")


            Spacer()

            // Shader indicator
            HStack(spacing: 4) {
                Image(systemName: "cpu")
                    .font(.system(size: 10))
                Text(currentShader.rawValue)
                    .font(AppTypography.labelSmall)
            }
            .foregroundColor(.secondary)
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, AppSpacing.xxs)
            .background(Color.green.opacity(0.15))
            .cornerRadius(AppRadius.xs)
        }
    }

    private var fpsColor: Color {
        if currentFPS < 25 {
            return .red
        } else if currentFPS < 45 {
            return .orange
        } else if currentFPS >= 60 {
            return .green
        } else {
            return .secondary
        }
    }
}
