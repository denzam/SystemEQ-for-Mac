import AppKit
import AVFoundation
import Combine
import CoreAudio
import SwiftUI

struct RoutingView: View {
    @StateObject private var audioRouter = AudioRouter.shared
    @ObservedObject private var audioEngine = AudioEngine.shared
    @ObservedObject private var core = CoreAudioEngine.shared
    @StateObject private var localization = LocalizationManager.shared

    @State private var selectedTab: RoutingTab = .devices

    // Smoothed peak values for better visualization
    @State private var smoothedInputPeak: Float = 0.0
    @State private var smoothedOutputPeak: Float = 0.0
    @State private var meterCancellable: AnyCancellable?

    enum RoutingTab: String, CaseIterable, FeatureTab {
        case devices
        case checks

        var id: String {
            rawValue
        }

        var localizedKey: LocalizedString {
            switch self {
            case .devices: .devices
            case .checks: .status
            }
        }

        func localizedTitle(_ localization: LocalizationManager) -> String {
            localization.localized(localizedKey)
        }
    }

    var body: some View {
        FeatureWindowContainer(
            title: .routingTitle,
            subtitle: .routingDesc,
            windowSize: .standard,
            selectedTab: $selectedTab
        ) { tab in
            switch tab {
            case .devices:
                devicesSection
            case .checks:
                checksSection
            }
        }
        .onAppear {
            Task {
                await audioRouter.refreshDevices()
            }
            // ⚡ OPTIMIZED: Use Combine throttle at 20 FPS to reduce Main Thread load
            meterCancellable = Timer.publish(every: 1.0 / 20.0, on: .main, in: .common)
                .autoconnect()
                .sink { _ in
                    let smoothingFactor: Float = 0.3
                    smoothedInputPeak = Self.nextSmoothedPeak(
                        current: smoothedInputPeak,
                        incoming: core.inputPeakLevel,
                        smoothingFactor: smoothingFactor
                    )
                    smoothedOutputPeak = Self.nextSmoothedPeak(
                        current: smoothedOutputPeak,
                        incoming: core.outputPeakLevel,
                        smoothingFactor: smoothingFactor
                    )
                }
        }
        .onDisappear {
            meterCancellable?.cancel()
            meterCancellable = nil
        }
    }

    // MARK: - Devices Section

    private var devicesSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            // BlackHole Status
            blackHoleStatusCard

            // System Output Management
            systemOutputCard

            // Input Device Selection
            deviceSelectionCard(
                title: localization.localized(.inputDevice),
                subtitle: localization.localized(.routingDesc), // Using similar context
                devices: audioRouter.inputDevices,
                selectedDevice: audioRouter.selectedInputDevice,
                onSelect: { device in
                    audioRouter.selectInputDevice(device)
                }
            )

            // Output Device Selection
            deviceSelectionCard(
                title: localization.localized(.outputDevice),
                subtitle: localization.localized(.routingDesc),
                devices: audioRouter.outputDevices,
                selectedDevice: audioRouter.selectedOutputDevice,
                onSelect: { device in
                    audioRouter.selectOutputDevice(device)
                }
            )
        }
        .padding(AppSpacing.xl)
    }

    // MARK: - BlackHole Status Card

    private var blackHoleStatusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: audioRouter
                    .blackHoleDetected ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(audioRouter.blackHoleDetected ? .green : .orange)
                    .font(AppTypography.heading1)

                VStack(alignment: .leading, spacing: 4) {
                    Text(localization.localized(.blackHole))
                        .font(AppTypography.heading2)
                    Text(audioRouter.blackHoleDetected ? localization.localized(.installed) : localization
                        .localized(.notInstalled))
                        .font(AppTypography.bodySmall)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if !audioRouter.blackHoleDetected {
                    Button(localization.localized(.download)) {
                        audioRouter.openBlackHoleDownload()
                    }
                    .font(AppTypography.body)
                    .buttonStyle(.borderedProminent)
                }
            }

            if !audioRouter.blackHoleDetected {
                Text(localization.localized(.blackHoleRequiredForRouting))
                    .font(AppTypography.bodySmall)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
        }
        .padding(AppSpacing.lg)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }

    // MARK: - System Output Card

    private var systemOutputCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "speaker.wave.3")
                    .foregroundColor(.blue)
                    .font(AppTypography.heading1)

                VStack(alignment: .leading, spacing: 4) {
                    Text(localization.localized(.systemOutput))
                        .font(AppTypography.heading2)
                    Text(localization.localized(.systemOutputDesc))
                        .font(AppTypography.bodySmall)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            VStack(alignment: .leading, spacing: 12) {
                // Status indicator with refresh button
                HStack {
                    Circle()
                        .fill(audioRouter.isRoutingActive ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                    Text(audioRouter.isRoutingActive ? "EQ Active" : "EQ Inactive")
                        .font(AppTypography.bodySmall)
                        .foregroundColor(.secondary)

                    Spacer()

                    Button(action: {
                        Task {
                            await audioRouter.refreshDevices()
                        }
                    }) {
                        Label(localization.localized(.refresh), systemImage: "arrow.clockwise")
                            .font(AppTypography.bodySmall)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                HStack(spacing: 12) {
                    // Main controls
                    Button(action: {
                        Self.setEQEnabled(true, engine: audioEngine)
                    }) {
                        Label(localization.localized(.enableEQ), systemImage: "waveform.circle.fill")
                            .font(AppTypography.body)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!audioRouter.canEnableRouting)

                    Button(action: {
                        Self.setEQEnabled(false, engine: audioEngine)
                    }) {
                        Label(localization.localized(.disableEQ), systemImage: "stop.circle")
                            .font(AppTypography.body)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }

                Divider()

                // Test tone controls
                HStack {
                    Button(action: {
                        CoreAudioEngine.shared.startTestTone(440)
                    }) {
                        Label(localization.localized(.testTone), systemImage: "speaker.wave.2.fill")
                            .font(AppTypography.body)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!audioRouter.isRoutingActive)

                    Button(action: {
                        CoreAudioEngine.shared.stopTestTone()
                    }) {
                        Label(localization.localized(.stopTone), systemImage: "speaker.slash")
                            .font(AppTypography.body)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!audioRouter.isRoutingActive)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                if !audioRouter.isRoutingActive {
                    Text("💡 Test Tone available only when EQ is enabled")
                        .font(AppTypography.labelSmall)
                        .foregroundColor(.secondary)
                }
            }

            // Peak meters
            VStack(alignment: .leading, spacing: 12) {
                Text(localization.localized(.audioLevels))
                    .font(AppTypography.bodySmall)
                    .foregroundColor(.secondary)

                // Input Peak Meter
                meterRow(title: localization.localized(.input), peak: smoothedInputPeak)

                // Output Peak Meter
                meterRow(title: localization.localized(.output), peak: smoothedOutputPeak)
            }
            .padding(AppSpacing.md)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            .cornerRadius(AppRadius.md)
            // ⚡ REMOVED: .id(meterUpdateTrigger) was forcing full view recreation 30 times per second
        }
        .padding(AppSpacing.lg)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }

    private func meterRow(title: String, peak: Float) -> some View {
        let displayPeak = Self.normalizedPeak(peak)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(AppTypography.bodySmall)
                    .fontWeight(.medium)
                    .frame(width: 60, alignment: .leading)
                Spacer()
                Text(peakToDB(displayPeak))
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.semibold)
                    .foregroundColor(peakColor(displayPeak))
                    .frame(width: 80, alignment: .trailing)
                    .monospacedDigit()
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))

                    // Peak bar with gradient
                    RoundedRectangle(cornerRadius: 4)
                        .fill(peakGradient(displayPeak))
                        .frame(width: geometry.size.width * CGFloat(min(displayPeak, 1.0)))
                        .animation(.easeOut(duration: 0.1), value: displayPeak)
                }
            }
            .frame(height: 8)
        }
    }

    // MARK: - Device Selection Card

    private func deviceSelectionCard(
        title: String,
        subtitle: String,
        devices: [AudioDevice],
        selectedDevice: AudioDevice?,
        onSelect: @escaping (AudioDevice) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(AppTypography.heading2)
                Text(subtitle)
                    .font(AppTypography.bodySmall)
                    .foregroundColor(.secondary)
            }

            if devices.isEmpty {
                Text("No devices found")
                    .font(AppTypography.body)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(devices) { device in
                    Button(action: {
                        onSelect(device)
                    }) {
                        HStack {
                            Image(systemName: selectedDevice?.id == device.id ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(selectedDevice?.id == device.id ? .blue : .secondary)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(device.name)
                                    .font(AppTypography.body)
                                Text(device.uid)
                                    .font(AppTypography.labelSmall)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(selectedDevice?.id == device.id ? Color.blue.opacity(0.1) : Color.clear)
                    .cornerRadius(6)
                }
            }
        }
        .padding(AppSpacing.lg)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }

    // MARK: - Checks Section

    private var checksSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(localization.localized(.status))
                .font(AppTypography.heading2)
                .padding(.horizontal, 4)

            // Status checks
            statusCheckCard(
                title: localization.localized(.blackHole),
                status: audioRouter.blackHoleDetected ? .success : .warning,
                message: audioRouter.blackHoleDetected ? localization.localized(.installed) : localization
                    .localized(.notInstalled)
            )

            statusCheckCard(
                title: localization.localized(.inputDevice),
                status: audioRouter.selectedInputDevice != nil ? .success : .warning,
                message: audioRouter.selectedInputDevice?.name ?? localization.localized(.notConfigured)
            )

            statusCheckCard(
                title: localization.localized(.outputDevice),
                status: audioRouter.selectedOutputDevice != nil ? .success : .warning,
                message: audioRouter.selectedOutputDevice?.name ?? localization.localized(.notConfigured)
            )

            // Overall Status
            Divider()
                .padding(.vertical, 8)

            HStack {
                Image(systemName: audioRouter
                    .isRoutingActive ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(audioRouter.isRoutingActive ? .green : .orange)
                    .font(AppTypography.displaySmall)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Overall Status")
                        .font(AppTypography.heading2)
                    Text(audioRouter.statusMessage)
                        .font(AppTypography.body)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding(AppSpacing.lg)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        }
        .padding(AppSpacing.xl)
    }

    private func statusCheckCard(title: String, status: CheckStatus, message: String) -> some View {
        HStack {
            Image(systemName: status.icon)
                .foregroundColor(status.color)
                .font(AppTypography.heading2)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTypography.heading3)
                    .fontWeight(.medium)
                Text(message)
                    .font(AppTypography.bodySmall)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(AppSpacing.md)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(AppRadius.md)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }

    enum CheckStatus {
        case success
        case warning
        case info

        var icon: String {
            switch self {
            case .success: "checkmark.circle.fill"
            case .warning: "exclamationmark.triangle.fill"
            case .info: "info.circle"
            }
        }

        var color: Color {
            switch self {
            case .success: .green
            case .warning: .orange
            case .info: .blue
            }
        }
    }

    // MARK: - Peak Meter Helpers

    static func setEQEnabled(_ enabled: Bool, engine: AudioEngine) {
        engine.setEnabled(enabled)
    }

    static func normalizedPeak(_ peak: Float) -> Float {
        guard peak.isFinite, peak >= 0.0001 else { return 0 }
        return max(peak, 0)
    }

    static func nextSmoothedPeak(current: Float, incoming: Float, smoothingFactor: Float) -> Float {
        let stableCurrent = normalizedPeak(current)
        let stableIncoming = normalizedPeak(incoming)
        let factor = min(max(smoothingFactor, 0), 1)
        if stableIncoming > stableCurrent {
            return stableIncoming
        }
        return factor * stableIncoming + (1 - factor) * stableCurrent
    }

    /// Convert linear peak value to dB string
    private func peakToDB(_ peak: Float) -> String {
        let stablePeak = Self.normalizedPeak(peak)
        if stablePeak <= 0.0 {
            return "-∞ dB"
        }
        let db = 20 * log10(stablePeak)
        return String(format: "%.1f dB", db)
    }

    /// Get color based on peak level
    private func peakColor(_ peak: Float) -> Color {
        if peak >= 0.9 {
            .red
        } else if peak >= 0.7 {
            .orange
        } else if peak >= 0.3 {
            .green
        } else {
            .gray
        }
    }

    /// Get gradient for peak meter
    private func peakGradient(_ peak: Float) -> LinearGradient {
        if peak >= 0.9 {
            LinearGradient(colors: [.green, .yellow, .red], startPoint: .leading, endPoint: .trailing)
        } else if peak >= 0.7 {
            LinearGradient(colors: [.green, .yellow], startPoint: .leading, endPoint: .trailing)
        } else {
            LinearGradient(colors: [.green, .green.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
        }
    }
}
