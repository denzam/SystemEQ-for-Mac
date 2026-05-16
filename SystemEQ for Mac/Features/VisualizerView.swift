import SwiftUI

struct VisualizerView: View {
    @ObservedObject private var localization = LocalizationManager.shared
    @StateObject private var helperClient = ProjectMHelperClient.shared
    @State private var isFullscreen: Bool = false
    @State private var helperWindowFrame: NSRect = .zero
    @State private var isTransitioningFullscreen: Bool = false

    var body: some View {
        Group {
            if isFullscreen {
                // Fullscreen: no container chrome, just the visualization
                ZStack {
                    Color.black.ignoresSafeArea()
                    visualizationCanvas
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

                        visualizationCanvas
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
                isTransitioningFullscreen = true
                withAnimation(.easeInOut(duration: 0.1)) {
                    isFullscreen = true
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { notification in
            if let window = notification.object as? NSWindow,
               window.identifier?.rawValue == FeatureID.visualizer.rawValue {
                isTransitioningFullscreen = true
                withAnimation(.easeInOut(duration: 0.1)) {
                    isFullscreen = false
                }
                NSCursor.unhide()
            }
        }
        .onAppear {
            isTransitioningFullscreen = false
            startVisualizerIfNeeded()
        }
        .onDisappear {
            // Guard against SwiftUI destroying the outgoing branch when toggling
            // fullscreen — that fires onDisappear but the helper must keep running.
            if isTransitioningFullscreen {
                isTransitioningFullscreen = false
                return
            }
            stopVisualizerIfNeeded()
        }
    }

    // MARK: - Visualization Canvas

    private var visualizationCanvas: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black

                if helperClient.isRunning {
                    // Helper is running - show info overlay
                    VStack(spacing: AppSpacing.md) {
                        Image(systemName: "waveform.circle.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.purple.opacity(0.5))

                        Text(localization.localized(.visualizerInSeparateWindow))
                            .font(AppTypography.body)
                            .foregroundColor(.secondary)

                        Text(localization.localized(.dragProjectMWindowHint))
                            .font(AppTypography.labelSmall)
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                } else {
                    // Helper not running - show start button
                    VStack(spacing: AppSpacing.md) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.purple)

                        Button(localization.localized(.launchMilkDrop)) {
                            startHelperWithFrame(geometry.frame(in: .global))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.purple)
                    }
                }
            }
            .onChange(of: geometry.frame(in: .global)) { newFrame in
                // Defer to avoid triggering layout during an active layout pass
                DispatchQueue.main.async {
                    helperWindowFrame = newFrame
                }
            }
        }
    }

    // MARK: - Lifecycle

    private func startVisualizerIfNeeded() {
        // Will start when user clicks button
    }

    private func stopVisualizerIfNeeded() {
        helperClient.stop()
    }

    private func startHelperWithFrame(_ frame: NSRect) {
        // Position helper window next to main window
        let helperFrame = NSRect(
            x: frame.origin.x + frame.width + 20,
            y: frame.origin.y,
            width: 800,
            height: 600
        )
        helperClient.start(frame: helperFrame)
    }

    // MARK: - Fullscreen

    private func toggleFullscreen() {
        // Use native macOS fullscreen via window toggle
        guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: {
            $0.identifier?.rawValue == FeatureID.visualizer.rawValue
        }) else { return }

        window.toggleFullScreen(nil)
    }

    // MARK: - Controls Bar

    private var controlsBar: some View {
        HStack(spacing: AppSpacing.md) {
            // Category picker
            Picker("", selection: $helperClient.selectedCategory) {
                ForEach(helperClient.availableCategories, id: \.self) { category in
                    Text(category).tag(category)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 120)
            .help(localization.localized(.presetCategoryHelp))

            // Weight picker
            Picker("", selection: $helperClient.selectedWeight) {
                Text("All").tag("All")
                Text("Light").tag("Light")
                Text("Medium").tag("Medium")
                Text("Heavy").tag("Heavy")
            }
            .pickerStyle(.menu)
            .frame(width: 90)
            .help(localization.localized(.presetWeightHelp))

            Divider()
                .frame(height: 20)

            // projectM controls
            projectMControls

            Spacer()
        }
    }

    // MARK: - projectM Controls

    private var projectMControls: some View {
        HStack(spacing: AppSpacing.md) {
            Button(action: {
                helperClient.previousPreset()
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .help(localization.localized(.previousPresetHelp))

            VStack(alignment: .leading, spacing: 2) {
                Text(helperClient.currentPresetName)
                    .font(AppTypography.labelSmall)
                    .lineLimit(1)
                    .frame(maxWidth: 200)
                Text("\(helperClient.presetCount) presets")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, AppSpacing.xxs)
            .background(Color.purple.opacity(0.2))
            .cornerRadius(AppRadius.xs)

            Button(action: {
                helperClient.nextPreset()
            }) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .help(localization.localized(.nextPresetHelp))

            Button(action: {
                helperClient.randomPreset()
            }) {
                Image(systemName: "shuffle")
                    .font(.system(size: 16, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .help(localization.localized(.randomPresetHelp))

            HStack(spacing: 4) {
                Text(localization.localized(.autoLabel))
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
                Toggle("", isOn: $helperClient.isShuffleEnabled)
                    .toggleStyle(.switch)
                    .scaleEffect(0.7)
            }
            .help(localization.localized(.autoPresetsHelp))

            HStack(spacing: 4) {
                Text(localization.localized(.lockLabel))
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
                Toggle("", isOn: $helperClient.isPresetLocked)
                    .toggleStyle(.switch)
                    .scaleEffect(0.7)
            }
            .help(localization.localized(.lockPresetHelp))
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: AppSpacing.lg) {
            // Status indicator
            HStack(spacing: AppSpacing.xs) {
                Circle()
                    .fill(helperClient.isRunning ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)

                Text(helperClient.isRunning ? "projectM Active" : "projectM Inactive")
                    .font(AppTypography.labelSmall)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Stable mode indicator
            HStack(spacing: 4) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 15))
                Text("Stable Mode")
                    .font(AppTypography.labelSmall)
            }
            .foregroundColor(.green)
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, AppSpacing.xxs)
            .background(Color.green.opacity(0.15))
            .cornerRadius(AppRadius.xs)
        }
    }
}
