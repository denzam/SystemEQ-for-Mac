//
//  SystemEQ_for_MacApp.swift
//  SystemEQ for Mac
//
//  Created by Denys Zamorniak on 07/10/25.
//

import AVFoundation
import Foundation
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        StatusItemController.shared.install()

        guard !UserDefaults.standard.bool(forKey: "hasCompletedSetup") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            WelcomeWindowController.shared.showWelcome()
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // While EQ routing is active the system default output is BlackHole.
        // Restore the real output device before quitting, otherwise the user is
        // left with no sound until they fix it manually in System Settings.
        // AudioObjectSetPropertyData is synchronous, so .terminateNow is safe.
        if AudioRouter.shared.isRoutingOwned {
            AudioRouter.shared.disableEQRouting()
        }
        return .terminateNow
    }
}

@main
struct SystemEQ_for_MacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var featureRegistry = FeatureRegistry()
    @StateObject private var audioRouter = AudioRouter.shared
    @StateObject private var audioEngine = AudioEngine.shared
    @StateObject private var localizationManager = LocalizationManager.shared

    init() {
        #if DEBUG
            EQDatabaseTest.runTests()
        #endif
        WindowTitleManager.shared.setupObserver()
    }

    var body: some Scene {
        Window("SystemEQ", id: "main") {
            MainWindowView()
                .environmentObject(featureRegistry)
                .environmentObject(localizationManager)
                .environmentObject(audioRouter)
                .environmentObject(audioEngine)
                .background(WindowAccessor(id: "main", localizationKey: .mainWindowTitle))
                .dynamicWindowTitle(id: "main", key: .mainWindowTitle)
                .task {
                    // First, perform the async device scan to ensure the list is ready.
                    dlog("Scanning for audio devices...", category: .routing)
                    await audioRouter.refreshDevices()
                    dlog("Device scan complete", category: .routing)

                    // Check status but DO NOT request access immediately (let WelcomeView do it)
                    if AVCaptureDevice.authorizationStatus(for: .audio) != .authorized {
                        dlog("Audio access not authorized - waiting for user setup", level: .warning, category: .audio)
                    } else {
                        dlog("Audio access authorized", category: .audio)
                    }

                    // NOTE: Python AutoEQ Server removed - using SQLite database instead
                    // To restore: see git history for AutoEQServer.swift

                    // Listen for calibration activation hints
                    NotificationCenter.default.addObserver(
                        forName: NSNotification.Name("ShowCalibrationActivationHint"),
                        object: nil,
                        queue: .main
                    ) { _ in
                        // Show alert about enabling EQ
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            NSAlert.show(
                                title: LocalizationManager.shared.localized(.calibrationActivatedTitle),
                                message: LocalizationManager.shared.localized(.calibrationActivatedMessage),
                                style: .informational
                            )
                        }
                    }

                    // Apply startup behavior based on user settings
                    let startupModeRaw = UserDefaults.standard.string(forKey: "eqStartupMode") ?? EQStartupMode
                        .restoreLastState.rawValue
                    let startupMode = EQStartupMode(rawValue: startupModeRaw) ?? .restoreLastState

                    if startupMode == .restoreLastState {
                        // 🔧 FIX: Restore preset values to UI WITHOUT applying filters
                        // Filters will be created only when user enables EQ
                        if let saved = PresetPersistence.load() {
                            let engine = AudioEngine.shared
                            engine.bandMode = saved.mode

                            // Load values into UI bands WITHOUT syncing to CoreAudioEngine
                            for (index, gain) in saved.gains.prefix(engine.bands.count).enumerated() {
                                engine.bands[index].gain = gain
                            }
                            engine.preampGain = saved.preamp

                            // Restore EQ enabled state
                            let wasEnabled = UserDefaults.standard.bool(forKey: "eqWasEnabled")
                            if wasEnabled {
                                // Now apply to CoreAudioEngine (this will create filters)
                                engine.applyEQValues(saved.gains)
                                engine.setPreampGain(saved.preamp)
                                engine.setEnabled(true)
                                CoreAudioEngine.shared.isEnabled = true
                                dlog("Restored last state: preset + EQ enabled", category: .preset)
                            } else {
                                // EQ disabled - values loaded to UI but NO filters created
                                engine.setEnabled(false)
                                CoreAudioEngine.shared.isEnabled = false
                                dlog(
                                    "Restored last state: preset loaded to UI, EQ disabled (no filters)",
                                    category: .preset
                                )
                            }
                        }
                    } else if startupMode == .restorePresetOnly {
                        // Load preset but keep EQ disabled
                        if let saved = PresetPersistence.load() {
                            let engine = AudioEngine.shared
                            engine.bandMode = saved.mode

                            // Load values into UI bands WITHOUT syncing to CoreAudioEngine
                            for (index, gain) in saved.gains.prefix(engine.bands.count).enumerated() {
                                engine.bands[index].gain = gain
                            }
                            engine.preampGain = saved.preamp

                            // Keep EQ disabled - NO filters created
                            engine.setEnabled(false)
                            CoreAudioEngine.shared.isEnabled = false
                            dlog(
                                "Restored preset to UI but EQ is disabled (no filters, user must enable manually)",
                                category: .preset
                            )
                        }
                    } else if startupMode == .startClean {
                        // Start with flat EQ and disabled
                        let engine = AudioEngine.shared
                        engine.setEnabled(false)
                        CoreAudioEngine.shared.isEnabled = false
                        dlog("Started clean - no preset loaded, EQ disabled", category: .preset)
                    }

                    // Now that devices are loaded, we can reliably check for BlackHole
                    if audioRouter.blackHoleDetected {
                        dlog("\(AppConstants.DeviceNames.blackHole) detected", category: .routing)
                        dlog("Routing will enable when you toggle 'Enable EQ'", category: .routing)
                    } else {
                        dlog(
                            "\(AppConstants.DeviceNames.blackHole) not detected - please install for system-wide EQ",
                            level: .warning,
                            category: .routing
                        )
                    }
                }
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)

        Window("Equalizer", id: FeatureID.equalizer.rawValue) {
            EqualizerView()
                .environmentObject(localizationManager)
                .environmentObject(audioEngine)
                .background(WindowAccessor(id: FeatureID.equalizer.rawValue, localizationKey: .equalizerTitle))
                .frame(width: 900, height: 650)
                .dynamicWindowTitle(id: FeatureID.equalizer.rawValue, key: .equalizerTitle)
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)

        Window("Calibration", id: FeatureID.calibration.rawValue) {
            CalibrationView()
                .environmentObject(localizationManager)
                .background(WindowAccessor(id: FeatureID.calibration.rawValue, localizationKey: .calibration))
                .frame(width: 900, height: 650)
                .dynamicWindowTitle(id: FeatureID.calibration.rawValue, key: .calibration)
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)

        Window("Subjective Room Tuning", id: FeatureID.subjectiveRoomTuning.rawValue) {
            SubjectiveRoomTuningView()
                .environmentObject(localizationManager)
                .background(WindowAccessor(
                    id: FeatureID.subjectiveRoomTuning.rawValue,
                    localizationKey: .subjectiveRoomTuning
                ))
                .frame(width: 900, height: 650)
                .dynamicWindowTitle(id: FeatureID.subjectiveRoomTuning.rawValue, key: .subjectiveRoomTuning)
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)

        Window("Resonance Finder", id: FeatureID.resonanceFinder.rawValue) {
            ResonanceFinderView()
                .environmentObject(localizationManager)
                .background(WindowAccessor(id: FeatureID.resonanceFinder.rawValue, localizationKey: .resonanceFinder))
                .frame(width: 900, height: 650)
                .dynamicWindowTitle(id: FeatureID.resonanceFinder.rawValue, key: .resonanceFinder)
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)

        Window("AutoEQ Presets", id: FeatureID.autoeq.rawValue) {
            AutoEQView()
                .environmentObject(localizationManager)
                .environmentObject(audioEngine)
                .background(WindowAccessor(id: FeatureID.autoeq.rawValue, localizationKey: .autoEQTitle))
                .frame(width: 900, height: 650)
                .dynamicWindowTitle(id: FeatureID.autoeq.rawValue, key: .autoEQTitle)
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)

        Window("Personalized", id: FeatureID.personalized.rawValue) {
            PersonalizedCalibrationView()
                .environmentObject(localizationManager)
                .background(WindowAccessor(id: FeatureID.personalized.rawValue, localizationKey: .personalized))
                .frame(width: 900, height: 650)
                .dynamicWindowTitle(id: FeatureID.personalized.rawValue, key: .personalized)
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)

        Window("Routing", id: FeatureID.routing.rawValue) {
            RoutingView()
                .environmentObject(localizationManager)
                .environmentObject(audioRouter)
                .environmentObject(CoreAudioEngine.shared)
                .background(WindowAccessor(id: FeatureID.routing.rawValue, localizationKey: .routing))
                .frame(width: 900, height: 650)
                .dynamicWindowTitle(id: FeatureID.routing.rawValue, key: .routing)
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)

        Window("Settings", id: FeatureID.settings.rawValue) {
            SettingsView()
                .environmentObject(localizationManager)
                .background(WindowAccessor(id: FeatureID.settings.rawValue, localizationKey: .settingsTitle))
                .frame(width: 900, height: 650)
                .dynamicWindowTitle(id: FeatureID.settings.rawValue, key: .settingsTitle)
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)

        Window("Visualizer", id: FeatureID.visualizer.rawValue) {
            VisualizerView()
                .environmentObject(localizationManager)
                .background(WindowAccessor(id: FeatureID.visualizer.rawValue, localizationKey: .visualizer))
                .frame(minWidth: 900, minHeight: 650)
                .dynamicWindowTitle(id: FeatureID.visualizer.rawValue, key: .visualizer)
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 900, height: 650)
    }
}
