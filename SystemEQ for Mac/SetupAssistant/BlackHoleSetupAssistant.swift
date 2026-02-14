//
//  BlackHoleSetupAssistant.swift
//  SystemEQ for Mac
//
//  Setup wizard for BlackHole installation and configuration
//  Guides users through the complete setup process
//

import AppKit
import Combine
import CoreAudio
import SwiftUI

// Import LocalizationManager
import Foundation

// MARK: - Setup Assistant Coordinator

@MainActor
class SetupAssistantCoordinator: ObservableObject {
    @Published var isPresented = false
    @Published var currentStep: SetupStep = .welcome
    @Published var blackHoleInstalled = false
    @Published var systemOutputConfigured = false

    /// Use @MainActor to ensure thread-safe access to shared instance
    @MainActor static let shared = SetupAssistantCoordinator()

    enum SetupStep: Int, CaseIterable {
        case welcome
        case checkBlackHole
        case installBlackHole
        case configureOutput
        case testAudio
        case complete

        var title: LocalizedString {
            switch self {
            case .welcome: .welcomeTitle
            case .checkBlackHole: .systemDiagnostics
            case .installBlackHole: .installBlackHole
            case .configureOutput: .configureSystemAudio
            case .testAudio: .testAudioRouting
            case .complete: .setupComplete
            }
        }

        var localizedTitle: String {
            LocalizationManager.shared.localized(title)
        }
    }

    private init() {}

    func startSetup() {
        currentStep = .welcome
        isPresented = true
    }

    func nextStep() {
        if let nextStep = SetupStep(rawValue: currentStep.rawValue + 1) {
            currentStep = nextStep
        }
    }

    func previousStep() {
        if let prevStep = SetupStep(rawValue: currentStep.rawValue - 1) {
            currentStep = prevStep
        }
    }

    func checkBlackHoleStatus() async {
        blackHoleInstalled = AudioRouter.shared.blackHoleDetected
    }

    func checkSystemOutputStatus() async {
        let currentOutput = await AudioRouter.shared.getCurrentSystemOutput()
        systemOutputConfigured = currentOutput?.name.lowercased().contains("blackhole") ?? false
    }
}

// MARK: - Setup Assistant View

struct BlackHoleSetupAssistantView: View {
    @StateObject private var coordinator = SetupAssistantCoordinator.shared
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var localization: LocalizationManager

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(coordinator.currentStep.localizedTitle)
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button(localization.localized(.cancel)) {
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Content
            ScrollView {
                Group {
                    switch coordinator.currentStep {
                    case .welcome:
                        WelcomeStepView()
                    case .checkBlackHole:
                        CheckBlackHoleStepView()
                    case .installBlackHole:
                        InstallBlackHoleStepView()
                    case .configureOutput:
                        ConfigureOutputStepView()
                    case .testAudio:
                        TestAudioStepView()
                    case .complete:
                        CompleteStepView()
                    }
                }
                .padding()
            }

            Divider()

            // Footer
            HStack {
                if coordinator.currentStep != .welcome {
                    Button(localization.localized(.back)) {
                        coordinator.previousStep()
                    }
                }

                Spacer()

                Button(coordinator.currentStep == .complete ? localization.localized(.close) : localization
                    .localized(.next)) {
                        if coordinator.currentStep == .complete {
                            dismiss()
                        } else {
                            coordinator.nextStep()
                        }
                    }
                    .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .frame(width: 600, height: 500)
    }
}

// MARK: - Step 1: Welcome

struct WelcomeStepView: View {
    @ObservedObject private var localization = LocalizationManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.blue.gradient)
                .frame(maxWidth: .infinity)

            Text(localization.localized(.welcomeTitle))
                .font(.title)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity)

            Text(localization.localized(.welcomeSubtitle))
                .font(.headline)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity)

            Divider()
                .padding(.vertical)

            VStack(alignment: .leading, spacing: 16) {
                FeatureRow(
                    icon: "slider.horizontal.3",
                    title: localization.localized(.equalizer),
                    description: localization.localized(.featureEqualizerSubtitle)
                )

                FeatureRow(
                    icon: "waveform.path.ecg",
                    title: localization.localized(.autoeqPresets),
                    description: localization.localized(.featureAutoEQSubtitle)
                )

                FeatureRow(
                    icon: "speaker.wave.3.fill",
                    title: localization.localized(.mainSubtitle),
                    description: localization.localized(.calibrationSubtitle)
                )

                FeatureRow(
                    icon: "lock.shield.fill",
                    title: localization.localized(.privacyTitle),
                    description: localization.localized(.privacyDesc)
                )
            }

            Spacer()

            InfoBox(
                icon: "info.circle.fill",
                text: localization.localized(.welcomeDesc),
                color: .blue
            )
        }
    }
}

// MARK: - Step 2: Check BlackHole

struct CheckBlackHoleStepView: View {
    @StateObject private var coordinator = SetupAssistantCoordinator.shared
    @State private var isChecking = false
    @ObservedObject private var localization = LocalizationManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(localization.localized(.checkingYourSystem))
                .font(.title2)
                .fontWeight(.semibold)

            Text(localization.localized(.systemeqRequiresBlackHole))
                .foregroundColor(.secondary)

            Divider()

            VStack(spacing: 16) {
                CheckRow(
                    title: localization.localized(.installBlackHole),
                    status: coordinator.blackHoleInstalled ? .success : .pending,
                    description: coordinator.blackHoleInstalled
                        ? localization.localized(.installed)
                        : localization.localized(.notInstalled)
                )

                CheckRow(
                    title: localization.localized(.privacyTitle),
                    status: .success,
                    description: localization.localized(.permissionGranted)
                )

                CheckRow(
                    title: "macOS Version",
                    status: .success,
                    description: "macOS 13+ detected"
                )
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)

            Spacer()

            if !coordinator.blackHoleInstalled {
                InfoBox(
                    icon: "exclamationmark.triangle.fill",
                    text: localization.localized(.blackHoleNotInstalledShort) + ". " + localization
                        .localized(.next) + " to proceed with installation.",
                    color: .orange
                )
            } else {
                InfoBox(
                    icon: "checkmark.circle.fill",
                    text: localization.localized(.systemeqReady) + "! " + localization
                        .localized(.next) + " to configure audio routing.",
                    color: .green
                )
            }
        }
        .onAppear {
            Task { @MainActor in
                await coordinator.checkBlackHoleStatus()
            }
        }
    }
}

// MARK: - Step 3: Install BlackHole

struct InstallBlackHoleStepView: View {
    @StateObject private var coordinator = SetupAssistantCoordinator.shared
    @ObservedObject private var localization = LocalizationManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(localization.localized(.installBlackHole))
                .font(.title2)
                .fontWeight(.semibold)

            Text(localization.localized(.blackHoleFreeOpenSource))
                .foregroundColor(.secondary)

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                Text(localization.localized(.whatIsBlackHole))
                    .font(.headline)

                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(localization.localized(.freeOpenSource))
                            .fontWeight(.medium)
                        Text(localization.localized(.mitLicense))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(localization.localized(.safeTrusted))
                            .fontWeight(.medium)
                        Text(localization.localized(.usedByThousands))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(localization.localized(.easyToUninstall))
                            .fontWeight(.medium)
                        Text(localization.localized(.canBeRemovedAnytime))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)

            VStack(alignment: .leading, spacing: 12) {
                Text(localization.localized(.installationSteps))
                    .font(.headline)

                StepRow(number: 1, text: localization.localized(.download) + " BlackHole below")
                StepRow(number: 2, text: "Download BlackHole2ch.pkg from GitHub")
                StepRow(number: 3, text: "Run the installer (requires admin password)")
                StepRow(number: 4, text: "Return here and click '" + localization.localized(.next) + "'")
            }

            Spacer()

            HStack(spacing: 12) {
                Button(action: downloadBlackHole) {
                    Label(localization.localized(.download) + " BlackHole", systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("View on GitHub") {
                    openBlackHoleGitHub()
                }
                .controlSize(.large)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func downloadBlackHole() {
        guard let url = URL(string: AppConstants.URLs.blackHoleLatest) else { return }
        NSWorkspace.shared.open(url)
    }

    private func openBlackHoleGitHub() {
        guard let url = URL(string: AppConstants.URLs.blackHoleRepo) else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Step 4: Configure Output

struct ConfigureOutputStepView: View {
    @StateObject private var coordinator = SetupAssistantCoordinator.shared
    @State private var currentOutput: String = "Unknown"
    @ObservedObject private var localization = LocalizationManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(localization.localized(.configureSystemAudio))
                .font(.title2)
                .fontWeight(.semibold)

            Text(localization.localized(.setBlackHoleAsSystemOutput))
                .foregroundColor(.secondary)

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                Text(localization.localized(.currentSystemOutput))
                    .font(.headline)

                HStack {
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundColor(.blue)
                    Text(currentOutput)
                        .fontWeight(.medium)
                    Spacer()
                    if coordinator.systemOutputConfigured {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text(localization.localized(.configurationSteps))
                    .font(.headline)

                StepRow(number: 1, text: "Click 'Open System Settings' below")
                StepRow(number: 2, text: "Go to Sound → " + localization.localized(.output))
                StepRow(number: 3, text: "Select 'BlackHole 2ch' from the list")
                StepRow(number: 4, text: "Return here and click '" + localization.localized(.refresh) + "'")
            }

            Spacer()

            InfoBox(
                icon: "exclamationmark.triangle.fill",
                text: "Important: You won't hear audio until SystemEQ is running with EQ " + localization
                    .localized(.active) + ".",
                color: .orange
            )

            HStack(spacing: 12) {
                Button(action: openSystemSettings) {
                    Label("Open System Settings", systemImage: "gear")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button(localization.localized(.refresh) + " Status") {
                    refreshStatus()
                }
                .controlSize(.large)
            }
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            refreshStatus()
        }
    }

    private func openSystemSettings() {
        // Open Sound settings
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.sound") else { return }
        NSWorkspace.shared.open(url)
    }

    private func refreshStatus() {
        Task { @MainActor in
            await coordinator.checkSystemOutputStatus()
            if let output = await AudioRouter.shared.getCurrentSystemOutput() {
                currentOutput = output.name
            }
        }
    }
}

// MARK: - Step 5: Test Audio

struct TestAudioStepView: View {
    @StateObject private var coordinator = SetupAssistantCoordinator.shared
    @State private var isTestingAudio = false
    @State private var testResult: TestResult?
    @ObservedObject private var localization = LocalizationManager.shared

    enum TestResult {
        case success
        case noAudio
        case error(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(localization.localized(.testAudioRouting))
                .font(.title2)
                .fontWeight(.semibold)

            Text(localization.localized(.verifyAudioRouting))
                .foregroundColor(.secondary)

            Divider()

            VStack(spacing: 16) {
                if let result = testResult {
                    switch result {
                    case .success:
                        InfoBox(
                            icon: "checkmark.circle.fill",
                            text: "Audio test successful! You should hear a " + localization.localized(.testTone) + ".",
                            color: .green
                        )
                    case .noAudio:
                        InfoBox(
                            icon: "exclamationmark.triangle.fill",
                            text: "No audio detected. Please check your " + localization.localized(.settings) + ".",
                            color: .orange
                        )
                    case let .error(message):
                        InfoBox(
                            icon: "xmark.circle.fill",
                            text: "Error: \(message)",
                            color: .red
                        )
                    }
                }

                Button(action: runAudioTest) {
                    Label(
                        isTestingAudio ? "Testing..." : localization.localized(.testTone),
                        systemImage: "play.circle.fill"
                    )
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isTestingAudio)
                .frame(maxWidth: .infinity)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)

            VStack(alignment: .leading, spacing: 12) {
                Text(localization.localized(.troubleshooting))
                    .font(.headline)

                TroubleshootRow(
                    icon: "speaker.slash.fill",
                    text: "No sound?",
                    solution: "Check that SystemEQ is running and EQ is " + localization.localized(.active)
                )

                TroubleshootRow(
                    icon: "exclamationmark.triangle.fill",
                    text: "Distorted audio?",
                    solution: "Lower the EQ gains or enable " + localization.localized(.autoPreamp)
                )

                TroubleshootRow(
                    icon: "arrow.clockwise",
                    text: "Still not working?",
                    solution: "Restart SystemEQ and check " + localization.localized(.systemOutput) + " " + localization
                        .localized(.settings)
                )
            }

            Spacer()
        }
    }

    private func runAudioTest() {
        isTestingAudio = true
        testResult = nil

        // Start audio engine if not running
        if !CoreAudioEngine.shared.isRunning {
            AudioRouter.shared.enableEQRouting()
        }

        // Play test tone
        CoreAudioEngine.shared.startTestTone(440.0)

        // Stop after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            CoreAudioEngine.shared.stopTestTone()
            isTestingAudio = false

            // Check if audio was detected
            if CoreAudioEngine.shared.inputPeakLevel > 0.01 {
                testResult = .success
            } else {
                testResult = .noAudio
            }
        }
    }
}

// MARK: - Step 6: Complete

struct CompleteStepView: View {
    @StateObject private var coordinator = SetupAssistantCoordinator.shared
    @ObservedObject private var localization = LocalizationManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green.gradient)
                .frame(maxWidth: .infinity)

            Text(localization.localized(.setupComplete))
                .font(.title)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity)

            Text(localization.localized(.systemeqReady))
                .font(.headline)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity)

            Divider()
                .padding(.vertical)

            VStack(alignment: .leading, spacing: 16) {
                NextStepRow(
                    icon: "slider.horizontal.3",
                    title: localization.localized(.equalizer),
                    description: "Open the " + localization.localized(.equalizer) + " window to customize your sound"
                )

                NextStepRow(
                    icon: "waveform.path.ecg",
                    title: localization.localized(.autoEQImport),
                    description: "Load headphone correction profiles"
                )

                NextStepRow(
                    icon: "gearshape.fill",
                    title: localization.localized(.configureSystemAudio),
                    description: "Set launch at login and other preferences"
                )
            }

            Spacer()

            InfoBox(
                icon: "lightbulb.fill",
                text: "Tip: Keep SystemEQ running in the background for continuous audio processing.",
                color: .blue
            )
        }
    }
}

// MARK: - Helper Views

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.blue.gradient)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct CheckRow: View {
    let title: String
    let status: Status
    let description: String

    enum Status {
        case pending
        case success
        case error

        var icon: String {
            switch self {
            case .pending: "circle"
            case .success: "checkmark.circle.fill"
            case .error: "xmark.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .pending: .secondary
            case .success: .green
            case .error: .red
            }
        }
    }

    var body: some View {
        HStack {
            Image(systemName: status.icon)
                .foregroundColor(status.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
    }
}

struct StepRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(.blue))

            Text(text)
                .foregroundColor(.primary)
        }
    }
}

struct TroubleshootRow: View {
    let icon: String
    let text: String
    let solution: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.orange)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(text)
                    .fontWeight(.medium)
                Text(solution)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct NextStepRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.blue.gradient)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct InfoBox: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(color)
            Text(text)
                .font(.callout)
                .foregroundColor(.primary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Extension for AudioRouter

extension AudioRouter {
    func getCurrentSystemOutput() async -> AudioDevice? {
        // Get device data on background thread
        let deviceData = await withCheckedContinuation { (continuation: CheckedContinuation<
            (deviceID: AudioDeviceID, deviceName: String)?,
            Never
        >) in
            Task.detached {
                var propertyAddress = AudioObjectPropertyAddress(
                    mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                    mScope: kAudioObjectPropertyScopeGlobal,
                    mElement: kAudioObjectPropertyElementMain
                )

                var deviceID: AudioDeviceID = 0
                var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)

                let status = AudioObjectGetPropertyData(
                    AudioObjectID(kAudioObjectSystemObject),
                    &propertyAddress,
                    0,
                    nil,
                    &dataSize,
                    &deviceID
                )

                if status != noErr || deviceID == 0 {
                    continuation.resume(returning: nil)
                    return
                }

                // Get device name
                var nameAddr = AudioObjectPropertyAddress(
                    mSelector: kAudioDevicePropertyDeviceNameCFString,
                    mScope: kAudioObjectPropertyScopeGlobal,
                    mElement: kAudioObjectPropertyElementMain
                )

                var name: Unmanaged<CFString>?
                var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>>.size)

                let nameStatus = withUnsafeMutablePointer(to: &name) { pointer in
                    AudioObjectGetPropertyData(
                        deviceID,
                        &nameAddr,
                        0,
                        nil,
                        &nameSize,
                        pointer
                    )
                }

                guard nameStatus == noErr, let deviceName = name?.takeRetainedValue() else {
                    continuation.resume(returning: nil)
                    return
                }

                continuation.resume(returning: (deviceID: deviceID, deviceName: deviceName as String))
            }
        }

        // Create AudioDevice on the calling actor (usually MainActor)
        guard let data = deviceData else { return nil }
        return AudioDevice(
            id: data.deviceID,
            name: data.deviceName,
            uid: "\(data.deviceID)",
            isInput: false,
            isOutput: true
        )
    }
}
