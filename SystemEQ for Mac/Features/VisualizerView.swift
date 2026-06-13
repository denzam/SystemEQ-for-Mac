import SwiftUI

struct VisualizerView: View {
    @ObservedObject private var localization = LocalizationManager.shared
    @StateObject private var helperClient = ProjectMHelperClient.shared
    @State private var isFullscreen: Bool = false
    @State private var helperWindowFrame: NSRect = .zero
    @State private var isTransitioningFullscreen: Bool = false
    @State private var showPresetList: Bool = false
    @State private var presetSearch: String = ""
    @State private var showOnlyFavorites: Bool = false

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
            // Preset list browser
            Button(action: {
                helperClient.requestPresetList()
                showPresetList = true
            }) {
                Image(systemName: "list.bullet")
                    .font(.system(size: 15, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .help(localization.localized(.vizPresetListHelp))
            .popover(isPresented: $showPresetList, arrowEdge: .bottom) {
                presetListPopover
            }

            // Favorite current preset
            Button(action: {
                helperClient.toggleFavorite(helperClient.currentPresetName)
            }) {
                Image(systemName: helperClient.favoritePresets.contains(helperClient.currentPresetName)
                    ? "star.fill" : "star")
                    .font(.system(size: 15))
                    .foregroundColor(helperClient.favoritePresets.contains(helperClient.currentPresetName)
                        ? .yellow : .secondary)
            }
            .buttonStyle(.borderless)
            .help(localization.localized(.vizFavoriteHelp))

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

            // Quality picker — lower = higher FPS on heavy presets
            Picker("", selection: $helperClient.selectedQuality) {
                Text(localization.localized(.qualityLow)).tag("Low")
                Text(localization.localized(.qualityMedium)).tag("Medium")
                Text(localization.localized(.qualityHigh)).tag("High")
            }
            .pickerStyle(.menu)
            .frame(width: 110)
            .help(localization.localized(.visualizerQualityHelp))

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
                    .truncationMode(.middle)
                    .frame(maxWidth: 200)
                    .tooltip(helperClient.currentPresetName)
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
                    .fixedSize()
                Toggle("", isOn: $helperClient.isShuffleEnabled)
                    .toggleStyle(.switch)
                    .scaleEffect(0.7)
            }
            .help(localization.localized(.autoPresetsHelp))

            HStack(spacing: 4) {
                Text(localization.localized(.lockLabel))
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
                    .fixedSize()
                Toggle("", isOn: $helperClient.isPresetLocked)
                    .toggleStyle(.switch)
                    .scaleEffect(0.7)
            }
            .help(localization.localized(.lockPresetHelp))
        }
    }

    // MARK: - Preset List Popover

    private var filteredPresetList: [VizPreset] {
        let q = presetSearch.trimmingCharacters(in: .whitespaces).lowercased()
        return helperClient.presetList.filter { p in
            if showOnlyFavorites, !helperClient.favoritePresets.contains(p.name) { return false }
            if q.isEmpty { return true }
            return p.name.lowercased().contains(q) || p.category.lowercased().contains(q)
        }
    }

    private var presetListPopover: some View {
        VStack(spacing: AppSpacing.sm) {
            HStack {
                TextField(localization.localized(.vizSearchPresets), text: $presetSearch)
                    .textFieldStyle(.roundedBorder)
                Button(action: { showOnlyFavorites.toggle() }) {
                    Image(systemName: showOnlyFavorites ? "star.fill" : "star")
                        .foregroundColor(showOnlyFavorites ? .yellow : .secondary)
                }
                .buttonStyle(.borderless)
                .help(localization.localized(.vizShowFavoritesHelp))
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2, pinnedViews: [.sectionHeaders]) {
                    ForEach(groupedPresets, id: \.0) { category, presets in
                        Section {
                            ForEach(presets) { preset in
                                presetRow(preset)
                            }
                        } header: {
                            Text(category)
                                .font(AppTypography.labelSmall)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 2)
                                .background(Color(NSColor.windowBackgroundColor))
                        }
                    }
                }
            }
            .frame(width: 340, height: 380)
        }
        .padding(AppSpacing.sm)
        .frame(width: 360)
    }

    private var groupedPresets: [(String, [VizPreset])] {
        Dictionary(grouping: filteredPresetList, by: { $0.category })
            .sorted { $0.key < $1.key }
            .map { ($0.key, $0.value) }
    }

    private func presetRow(_ preset: VizPreset) -> some View {
        let isCurrent = preset.name == helperClient.currentPresetName
        return HStack(spacing: 6) {
            Button(action: {
                helperClient.selectPreset(at: preset.index)
                showPresetList = false
            }) {
                Text(preset.name)
                    .font(AppTypography.bodySmall)
                    .foregroundColor(isCurrent ? .accentColor : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .tooltip(preset.name)

            Button(action: { helperClient.toggleFavorite(preset.name) }) {
                Image(systemName: helperClient.favoritePresets.contains(preset.name) ? "star.fill" : "star")
                    .font(.system(size: 11))
                    .foregroundColor(helperClient.favoritePresets.contains(preset.name) ? .yellow : .secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 1)
        .padding(.horizontal, 4)
        .background(isCurrent ? Color.accentColor.opacity(0.12) : Color.clear)
        .cornerRadius(AppRadius.xs)
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

            if helperClient.isRunning, helperClient.currentFPS > 0 {
                Text("\(helperClient.currentFPS) FPS")
                    .font(AppTypography.mono)
                    .foregroundColor(fpsColor(helperClient.currentFPS))
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

    private func fpsColor(_ fps: Int) -> Color {
        if fps >= 55 { return .green }
        if fps >= 30 { return .orange }
        return .red
    }
}
