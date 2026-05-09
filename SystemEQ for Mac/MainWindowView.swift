//
//  MainWindowView.swift
//  SystemEQ for Mac
//
//  Main application window with feature navigation
//  Displays glass card UI with feature buttons for accessing different app sections
//  Handles welcome screen and setup flow integration
//

import AppKit
import Combine
import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject var featureRegistry: FeatureRegistry
    @EnvironmentObject var localizationManager: LocalizationManager
    @EnvironmentObject var audioRouter: AudioRouter
    @EnvironmentObject var audioEngine: AudioEngine
    @Environment(\.openWindow) private var openWindow

    // Setup Logic
    @AppStorage("hasCompletedSetup") private var hasCompletedSetup: Bool = false
    @AppStorage("hasShownWelcome") private var hasShownWelcome: Bool = false
    @State private var showWelcome: Bool = false

    var body: some View {
        GlassCard(topCornersOnly: true) {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    CrossfadeText(.mainWindowTitle, localization: localizationManager)
                        .font(AppTypography.displaySmall)
                        .foregroundColor(AppColors.primary)

                    CrossfadeText(.mainSubtitle, localization: localizationManager)
                        .font(AppTypography.bodySmall)
                        .foregroundColor(AppColors.secondary)
                }
                .padding([.horizontal, .top], AppSpacing.lg)
                .padding(.bottom, AppSpacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)

                // AppDivider() // Not needed on glass

                // Features List
                VStack(spacing: AppSpacing.sm) {
                    ForEach(featureRegistry.ordered()) { (feature: Feature) in
                        FeatureButton(
                            title: localizedTitle(for: feature.id),
                            icon: iconForFeature(feature.id),
                            subtitle: subtitleForFeature(feature.id)
                        ) {
                            if !WindowCoordinator.shared.focus(id: feature.id.rawValue) {
                                openWindow(id: feature.id.rawValue)
                            }
                        }
                    }
                }
                .padding(AppSpacing.lg)

                Spacer()
            }
            // Welcome Wizard is handled by sheet presentation now
        }
        .frame(width: 380, height: 750)
        .frame(maxWidth: 380, maxHeight: 750)
        .background(.clear)
        .shadow(color: .black.opacity(0.2), radius: 24, x: 0, y: 8)
        .sheet(isPresented: $showWelcome) {
            WelcomeScreen(isPresented: $showWelcome)
                .environmentObject(localizationManager)
                .padding(24)
                .background(Color(NSColor.windowBackgroundColor))
                .onAppear {
                    if !hasShownWelcome {
                        openWindow(id: "welcome")
                        hasShownWelcome = true
                    }
                }
        }
        .task {
            // Check setup on appear
            if !hasCompletedSetup {
                showWelcome = true
            }
        }
        .blurOnLanguageChange()
    }

    private func iconForFeature(_ featureId: FeatureID) -> String {
        switch featureId {
        case .equalizer: "slider.horizontal.3"
        case .calibration: "waveform.path"
        case .subjectiveRoomTuning: "ear.and.waveform"
        case .resonanceFinder: "waveform.path.ecg"
        case .autoeq: "headphones"
        case .personalized: "brain.head.profile"
        case .routing: "arrow.triangle.branch"
        case .settings: "gearshape"
        case .visualizer: "waveform"
        }
    }

    private func subtitleForFeature(_ featureId: FeatureID) -> String {
        switch featureId {
        case .equalizer: localizationManager.localized(.featureEqualizerSubtitle)
        case .calibration: localizationManager.localized(.featureCalibrationSubtitle)
        case .subjectiveRoomTuning: localizationManager.localized(.subjectiveRoomTuningDesc)
        case .resonanceFinder: localizationManager.localized(.resonanceFinderSubtitle)
        case .autoeq: localizationManager.localized(.featureAutoEQSubtitle)
        case .personalized: "Hearing Profile (Premium)"
        case .routing: localizationManager.localized(.featureRoutingSubtitle)
        case .settings: localizationManager.localized(.featureSettingsSubtitle)
        case .visualizer: localizationManager.localized(.featureVisualizerSubtitle)
        }
    }

    private func localizedTitle(for featureId: FeatureID) -> String {
        switch featureId {
        case .equalizer:
            localizationManager.localized(.equalizer)
        case .calibration:
            localizationManager.localized(.calibration)
        case .subjectiveRoomTuning:
            localizationManager.localized(.subjectiveRoomTuning)
        case .resonanceFinder:
            localizationManager.localized(.resonanceFinder)
        case .autoeq:
            localizationManager.localized(.autoeqPresets)
        case .personalized:
            localizationManager.localized(.personalized)
        case .routing:
            localizationManager.localized(.routing)
        case .settings:
            localizationManager.localized(.settingsTitle)
        case .visualizer:
            localizationManager.localized(.visualizer)
        }
    }
}

// MARK: - Window Drag Area

struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowDragAreaView {
        WindowDragAreaView()
    }

    func updateNSView(_ nsView: WindowDragAreaView, context: Context) {}
}

class WindowDragAreaView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Приймати кліки навіть коли вікно не активне
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    // Ключове: повертаємо self щоб view приймав hit testing
    override func hitTest(_ point: NSPoint) -> NSView? {
        self
    }

    override var mouseDownCanMoveWindow: Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}
