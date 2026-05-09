//
//  SetupAssistantIntegration.swift
//  SystemEQ for Mac
//
//  Integration of Setup Assistant into main app flow
//  Handles first-run detection and setup triggering
//

import Combine
import Foundation
import SwiftUI

// MARK: - First Run Detection

class FirstRunManager {
    private static let hasCompletedSetupKey = "hasCompletedInitialSetup"
    private static let appVersionKey = "lastRunAppVersion"

    static var isFirstRun: Bool {
        !UserDefaults.standard.bool(forKey: hasCompletedSetupKey)
    }

    static var shouldShowSetup: Bool {
        // Show setup if:
        // 1. First run
        // 2. BlackHole not detected
        // 3. Major version upgrade (optional)

        if isFirstRun {
            return true
        }

        // Check BlackHole status
        if !AudioRouter.shared.blackHoleDetected {
            return true
        }

        return false
    }

    static func markSetupComplete() {
        UserDefaults.standard.set(true, forKey: hasCompletedSetupKey)
        UserDefaults.standard.set(getCurrentAppVersion(), forKey: appVersionKey)
    }

    static func resetSetup() {
        UserDefaults.standard.removeObject(forKey: hasCompletedSetupKey)
        UserDefaults.standard.removeObject(forKey: appVersionKey)
    }

    private static func getCurrentAppVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
}

// MARK: - Setup Assistant Trigger View

struct SetupAssistantTrigger: ViewModifier {
    @StateObject private var coordinator = SetupAssistantCoordinator.shared
    @State private var showSetup = false
    @EnvironmentObject var localization: LocalizationManager

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showSetup) {
                BlackHoleSetupAssistantView()
                    .environmentObject(localization)
                    .onDisappear {
                        // Mark setup as complete when dismissed
                        if coordinator.currentStep == .complete {
                            FirstRunManager.markSetupComplete()
                        }
                    }
            }
            .task {
                // Check if setup should be shown
                if FirstRunManager.shouldShowSetup {
                    // Delay slightly to let main window appear first
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
                    showSetup = true
                }
            }
    }
}

extension View {
    func setupAssistant() -> some View {
        modifier(SetupAssistantTrigger())
    }
}

// MARK: - Manual Setup Trigger (for Settings)

struct SetupAssistantButton: View {
    @State private var showSetup = false
    @EnvironmentObject var localization: LocalizationManager

    var body: some View {
        Button(localization.localized(.runSetupAssistant)) {
            showSetup = true
        }
        .sheet(isPresented: $showSetup) {
            BlackHoleSetupAssistantView()
                .environmentObject(localization)
        }
    }
}

// MARK: - Quick Setup Banner (for main window)

struct QuickSetupBanner: View {
    @EnvironmentObject var audioRouter: AudioRouter
    @State private var showSetup = false
    @State private var dismissed = false
    @EnvironmentObject var localization: LocalizationManager

    var body: some View {
        if !audioRouter.blackHoleDetected, !dismissed {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(localization.localized(.setupRequired))
                            .font(.headline)
                        Text(localization.localized(.blackHoleNotInstalledShort))
                            .font(AppTypography.label)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button(localization.localized(.setupNow)) {
                        showSetup = true
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button(action: { dismissed = true }) {
                        Image(systemName: "xmark")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding()
                .background(Color.orange.opacity(0.1))
            }
            .sheet(isPresented: $showSetup) {
                BlackHoleSetupAssistantView()
            }
        }
    }
}

// MARK: - Launch at Login Manager

import ServiceManagement

class LaunchAtLoginManager: ObservableObject {
    @Published var isEnabled: Bool {
        didSet {
            setLaunchAtLogin(enabled: isEnabled)
        }
    }

    init() {
        // Check current status
        if #available(macOS 13.0, *) {
            self.isEnabled = SMAppService.mainApp.status == .enabled
        } else {
            self.isEnabled = false
        }
    }

    private func setLaunchAtLogin(enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                    dlog("✅ Launch at login enabled", category: .general)
                } else {
                    try SMAppService.mainApp.unregister()
                    dlog("✅ Launch at login disabled", category: .general)
                }
            } catch {
                dlog("❌ Failed to set launch at login: \(error)", category: .general)
            }
        }
    }
}

// MARK: - Enhanced Settings View Integration

struct LaunchAtLoginToggle: View {
    @StateObject private var launchManager = LaunchAtLoginManager()
    @ObservedObject private var localization = LocalizationManager.shared

    var body: some View {
        Toggle(localization.localized(.launchAtLogin), isOn: $launchManager.isEnabled)
            .help(localization.localized(.launchAtLoginHelp))
    }
}
