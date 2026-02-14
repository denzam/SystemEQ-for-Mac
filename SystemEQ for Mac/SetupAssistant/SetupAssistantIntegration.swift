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
        Button("Run Setup Assistant") {
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
                            .font(.caption)
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

// MARK: - Quit Prevention Manager

class QuitPreventionManager: NSObject, NSApplicationDelegate {
    static let shared = QuitPreventionManager()

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Check if EQ is active
        if CoreAudioEngine.shared.isRunning {
            DispatchQueue.main.async {
                self.showQuitWarning()
            }
            return .terminateCancel
        }

        return .terminateNow
    }

    private func showQuitWarning() {
        let alert = NSAlert()
        alert.messageText = "EQ is Currently Active"
        alert.informativeText = """
        Closing SystemEQ will stop audio processing.

        If System Output is still set to BlackHole, you won't hear any audio.

        What would you like to do?
        """
        alert.alertStyle = .warning

        alert.addButton(withTitle: "Disable EQ & Quit")
        alert.addButton(withTitle: "Minimize to Menu Bar")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()

        switch response {
        case .alertFirstButtonReturn:
            // Disable EQ and restore output
            AudioRouter.shared.disableEQRouting()
            NSApplication.shared.terminate(nil)

        case .alertSecondButtonReturn:
            // Hide window but keep running
            NSApplication.shared.hide(nil)

        default:
            // Cancel - do nothing
            break
        }
    }
}

// MARK: - System Health Monitor

class SystemHealthMonitor: ObservableObject {
    @Published var blackHoleStatus: HealthStatus = .unknown
    @Published var systemOutputStatus: HealthStatus = .unknown
    @Published var audioEngineStatus: HealthStatus = .unknown
    @Published var lastCheckTime: Date?

    enum HealthStatus: Equatable {
        case unknown
        case healthy
        case warning(String)
        case error(String)

        var icon: String {
            switch self {
            case .unknown: "questionmark.circle"
            case .healthy: "checkmark.circle.fill"
            case .warning: "exclamationmark.triangle.fill"
            case .error: "xmark.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .unknown: .gray
            case .healthy: .green
            case .warning: .orange
            case .error: .red
            }
        }

        var message: String {
            switch self {
            case .unknown: "Unknown"
            case .healthy: "OK"
            case let .warning(msg): msg
            case let .error(msg): msg
            }
        }
    }

    static let shared = SystemHealthMonitor()

    private init() {
        // Start periodic health checks
        startPeriodicChecks()
    }

    func performHealthCheck() {
        Task {
            // Check BlackHole
            if !AudioRouter.shared.blackHoleDetected {
                blackHoleStatus = .error("BlackHole not installed")
            } else {
                blackHoleStatus = .healthy
            }

            // Check System Output
            if CoreAudioEngine.shared.isRunning {
                if let currentOutput = await AudioRouter.shared.getCurrentSystemOutput() {
                    if currentOutput.name.lowercased().contains("blackhole") {
                        systemOutputStatus = .healthy
                    } else {
                        systemOutputStatus = .warning("System Output is '\(currentOutput.name)'")
                    }
                } else {
                    systemOutputStatus = .error("Cannot detect System Output")
                }
            } else {
                systemOutputStatus = .unknown
            }

            if CoreAudioEngine.shared.isRunning {
                if CoreAudioEngine.shared.inputPeakLevel > 0.001 {
                    audioEngineStatus = .healthy
                } else {
                    audioEngineStatus = .warning("No audio detected (play something)")
                }
            } else {
                audioEngineStatus = .unknown
            }

            lastCheckTime = Date()
        }
    }

    private func startPeriodicChecks() {
        // Check every 5 seconds
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.performHealthCheck()
            }
        }
    }
}

// MARK: - Diagnostics View

struct DiagnosticsView: View {
    @StateObject private var healthMonitor = SystemHealthMonitor.shared
    @ObservedObject private var localization = LocalizationManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(localization.localized(.systemDiagnostics))
                .font(.title2)
                .fontWeight(.semibold)

            if let lastCheck = healthMonitor.lastCheckTime {
                Text(lastCheck, style: .relative) + Text(" ") + Text(localization.localized(.ago))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            VStack(spacing: 12) {
                HealthStatusRow(
                    title: localization.localized(.blackHoleInstallation),
                    status: healthMonitor.blackHoleStatus
                )

                HealthStatusRow(
                    title: "System Output",
                    status: healthMonitor.systemOutputStatus
                )

                HealthStatusRow(
                    title: "Audio Engine",
                    status: healthMonitor.audioEngineStatus
                )
            }

            Divider()

            HStack {
                Button("Refresh") {
                    healthMonitor.performHealthCheck()
                }

                Button("Run Setup Assistant") {
                    Task { @MainActor in
                        SetupAssistantCoordinator.shared.startSetup()
                    }
                }

                Spacer()

                Button("View Logs") {
                    openConsoleApp()
                }
            }
        }
        .padding()
        .frame(width: 400)
        .onAppear {
            healthMonitor.performHealthCheck()
        }
    }

    private func openConsoleApp() {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Console.app")
        NSWorkspace.shared.open(url)
    }
}

struct HealthStatusRow: View {
    let title: String
    let status: SystemHealthMonitor.HealthStatus

    var body: some View {
        HStack {
            Image(systemName: status.icon)
                .foregroundColor(status.color)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(.medium)
                Text(status.message)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - Enhanced Settings View Integration

struct LaunchAtLoginToggle: View {
    @StateObject private var launchManager = LaunchAtLoginManager()

    var body: some View {
        Toggle("Launch at Login", isOn: $launchManager.isEnabled)
            .help("Automatically start SystemEQ when you log in")
    }
}
