//
//  ResonanceFinderView.swift
//  SystemEQ for Mac
//
//  Resonance Finder - Sine Sweep tool for identifying room resonances
//  This is a diagnostic tool, NOT a calibration tool
//

import Combine
import SwiftUI

struct ResonanceFinderView: View {
    @EnvironmentObject var localization: LocalizationManager
    @StateObject private var sineSweep = SineSweepGenerator()

    @State private var currentFrequency: Double = 1000.0
    @State private var detectedResonances: [ResonancePoint] = []
    @State private var showAddResonanceSheet = false
    @State private var newResonanceFrequency: Double = 1000.0
    @State private var newResonanceSeverity: ResonancePoint.Severity = .moderate
    @State private var refreshID = UUID()

    var body: some View {
        FeatureWindowContainer(
            title: .resonanceFinder,
            subtitle: .resonanceFinderDesc,
            windowSize: .large,
            hasScrollView: true
        ) {
            VStack(spacing: 24) {
                // Info card - what this tool does
                infoCard

                // Current frequency display
                frequencyDisplay

                // Sweep controls
                sweepControls

                // Quick test buttons
                quickTestSection

                // Detected resonances list
                resonancesSection
            }
        }
        .onDisappear {
            sineSweep.stopSweep()
        }
        .sheet(isPresented: $showAddResonanceSheet) {
            addResonanceSheet
        }
        .onReceive(NotificationCenter.default.publisher(for: .languageChanged)) { _ in
            refreshID = UUID()
        }
        .id(refreshID)
    }

    // MARK: - Info Card

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "waveform.path.ecg")
                    .font(AppTypography.heading1)
                    .foregroundColor(.blue)
                Text(localization.localized(.resonanceFinder))
                    .font(AppTypography.heading2)
            }

            Text(localization.localized(.resonanceFinderSubtitle))
                .font(.subheadline)
                .foregroundColor(.secondary)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Label(localization.localized(.resonanceStep1), systemImage: "speaker.wave.2")
                    .font(.subheadline)
                Label(localization.localized(.resonanceStep2), systemImage: "ear")
                    .font(.subheadline)
                Label(localization.localized(.resonanceStep3), systemImage: "flag")
                    .font(.subheadline)
            }
            .foregroundColor(.secondary)

            // Important note
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.orange)
                Text(localization.localized(.resonanceNote))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 8)
        }
        .padding(16)
        .background(Color.blue.opacity(0.05))
        .cornerRadius(10)
    }

    // MARK: - Frequency Display

    private var frequencyDisplay: some View {
        VStack(spacing: 10) {
            Text(localization.localized(.currentFrequency))
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text(String(format: "%.1f Hz", sineSweep.currentFrequency))
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundColor(.blue)

            if sineSweep.isPlaying {
                Text(localization.localized(.sweepInProgress))
                    .font(.subheadline)
                    .foregroundColor(.orange)
                    .fontWeight(.semibold)
            }
        }
        .padding(.vertical, AppSpacing.lg)
        .padding(.horizontal, AppSpacing.lg)
        .frame(maxWidth: .infinity)
        .background(Color.blue.opacity(0.05))
        .cornerRadius(10)
    }

    // MARK: - Sweep Controls

    private var sweepControls: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "waveform.path")
                    .foregroundColor(.orange)
                Text("Автоматичний sweep")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }

            Text("Sweep автоматично проходить через всі частоти. Коли почуєте резонанс — натисніть 'Позначити'.")
                .font(.caption)
                .foregroundColor(.secondary)

            // Speed selector
            VStack(alignment: .leading, spacing: 8) {
                Text(localization.localized(.sweepSpeed))
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Picker("", selection: $sineSweep.sweepSpeed) {
                    ForEach(SineSweepGenerator.SweepSpeed.allCases, id: \.self) { speed in
                        Text(speed.rawValue).tag(speed)
                    }
                }
                .pickerStyle(.segmented)
            }

            // Playback controls
            HStack(spacing: 12) {
                Button(action: {
                    if sineSweep.isPlaying {
                        sineSweep.stopSweep()
                    } else {
                        sineSweep.startSweep()
                    }
                }) {
                    HStack {
                        Image(systemName: sineSweep.isPlaying ? "stop.fill" : "play.fill")
                        Text(sineSweep.isPlaying ? localization.localized(.stopSweep) : localization
                            .localized(.startSweep))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(sineSweep.isPlaying ? .orange : .blue)

                Button(action: {
                    newResonanceFrequency = sineSweep.currentFrequency
                    showAddResonanceSheet = true
                }) {
                    HStack {
                        Image(systemName: "flag.fill")
                        Text(localization.localized(.markResonance))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(!sineSweep.isPlaying)
            }
        }
        .padding(18)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }

    // MARK: - Quick Test Section

    /// Standard problem frequencies for quick selection
    private let quickFrequencies: [Int] = [40, 50, 63, 80, 100, 125, 160, 200, 250, 315, 400, 500]

    /// Convert linear slider value (0-1) to logarithmic frequency (20-500 Hz)
    private func logFrequency(from linear: Double) -> Double {
        let minLog = log10(20.0)
        let maxLog = log10(500.0)
        return pow(10, minLog + linear * (maxLog - minLog))
    }

    /// Convert frequency to linear slider value (0-1)
    private func linearValue(from frequency: Double) -> Double {
        let minLog = log10(20.0)
        let maxLog = log10(500.0)
        return (log10(frequency) - minLog) / (maxLog - minLog)
    }

    private var quickTestSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(localization.localized(.quickTestCommon))
                .font(.subheadline)
                .fontWeight(.semibold)

            Text(localization.localized(.commonProblemFrequencies))
                .font(.caption)
                .foregroundColor(.secondary)

            // Quick frequency buttons - switch frequency, don't auto-stop
            VStack(spacing: 10) {
                Text("Швидкий вибір частоти")
                    .font(.caption)
                    .foregroundColor(.secondary)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                    ForEach(quickFrequencies, id: \.self) { freq in
                        Button(action: {
                            currentFrequency = Double(freq)
                            if sineSweep.isPlaying {
                                sineSweep.playContinuousTone(Double(freq))
                            }
                        }) {
                            Text("\(freq)")
                                .font(.system(size: 11, weight: .medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.bordered)
                        .tint(Int(currentFrequency) == freq ? .blue : .secondary)
                    }
                }
            }
            .padding(12)
            .background(Color.blue.opacity(0.05))
            .cornerRadius(8)

            // Logarithmic frequency slider
            VStack(spacing: 12) {
                HStack {
                    Text(localization.localized(.frequency))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.0f Hz", currentFrequency))
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                }

                // Logarithmic slider using binding
                Slider(
                    value: Binding(
                        get: { linearValue(from: currentFrequency) },
                        set: { newValue in
                            currentFrequency = logFrequency(from: newValue)
                            if sineSweep.isPlaying {
                                sineSweep.playContinuousTone(currentFrequency)
                            }
                        }
                    ),
                    in: 0...1
                )
                .accentColor(.blue)

                HStack {
                    Text("20 Hz")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("50")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.6))
                    Spacer()
                    Text("100")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.6))
                    Spacer()
                    Text("200")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.6))
                    Spacer()
                    Text("500 Hz")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(14)
            .background(Color.gray.opacity(0.05))
            .cornerRadius(8)

            // Play/Stop button - user controls when to stop
            HStack(spacing: 12) {
                Button(action: {
                    if sineSweep.isPlaying {
                        sineSweep.stopSweep()
                    } else {
                        sineSweep.playContinuousTone(currentFrequency)
                    }
                }) {
                    HStack {
                        Image(systemName: sineSweep.isPlaying ? "stop.fill" : "play.fill")
                        Text(sineSweep.isPlaying ? "Зупинити" : "Відтворити")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(sineSweep.isPlaying ? .red : .blue)

                // Add resonance button
                Button(action: {
                    newResonanceFrequency = currentFrequency
                    showAddResonanceSheet = true
                }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text(localization.localized(.addResonance))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(BorderedButtonStyle())
            }

            // Hint when playing
            if sineSweep.isPlaying {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundColor(.blue)
                    Text("Рухайте повзунок або натискайте кнопки частот — звук оновиться автоматично")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(10)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(6)
            }
        }
        .padding(18)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }

    // MARK: - Resonances Section

    private var resonancesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(localization.localized(.detectedResonances))
                    .font(.headline)
                Spacer()
                if !detectedResonances.isEmpty {
                    Button(localization.localized(.clearAll)) {
                        detectedResonances.removeAll()
                    }
                    .buttonStyle(BorderedButtonStyle())
                }
            }

            if detectedResonances.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "waveform.badge.magnifyingglass")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text(localization.localized(.noResonancesDetected))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text(localization.localized(.playSweepHint))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.gray.opacity(0.05))
                .cornerRadius(8)
            } else {
                ForEach(detectedResonances) { resonance in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(Int(resonance.frequency)) Hz")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text(resonance.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        // Severity indicator
                        HStack(spacing: 4) {
                            ForEach(0..<resonance.severity.rating, id: \.self) { _ in
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundColor(colorForSeverity(resonance.severity))
                            }
                        }

                        Button(action: {
                            sineSweep.playFixedFrequency(resonance.frequency, duration: 2.0)
                        }) {
                            Image(systemName: "play.circle")
                                .font(.title3)
                        }
                        .buttonStyle(BorderedButtonStyle())

                        Button(action: {
                            detectedResonances.removeAll { $0.id == resonance.id }
                        }) {
                            Image(systemName: "trash")
                                .font(.caption)
                        }
                        .buttonStyle(BorderedButtonStyle())
                    }
                    .padding(12)
                    .background(Color.orange.opacity(0.05))
                    .cornerRadius(8)
                }
            }
        }
        .padding(18)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }

    // MARK: - Add Resonance Sheet

    private var addResonanceSheet: some View {
        VStack(spacing: 20) {
            Text(localization.localized(.addResonance))
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 8) {
                Text(localization.localized(.frequency))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text(String(format: "%.0f Hz", newResonanceFrequency))
                    .font(.title3)
                    .fontWeight(.semibold)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(localization.localized(.severity))
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Picker("", selection: $newResonanceSeverity) {
                    Text(localization.localized(.mild)).tag(ResonancePoint.Severity.mild)
                    Text(localization.localized(.moderate)).tag(ResonancePoint.Severity.moderate)
                    Text(localization.localized(.severe)).tag(ResonancePoint.Severity.severe)
                    Text(localization.localized(.extreme)).tag(ResonancePoint.Severity.extreme)
                }
                .pickerStyle(.segmented)
            }

            HStack(spacing: 12) {
                Button(localization.localized(.cancel)) {
                    showAddResonanceSheet = false
                }
                .buttonStyle(BorderedButtonStyle())

                Button(localization.localized(.add)) {
                    addResonance()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 400)
    }

    // MARK: - Helper Methods

    private func addResonance() {
        let resonance = ResonancePoint(
            frequency: newResonanceFrequency,
            severity: newResonanceSeverity,
            description: localization.localized(.userDetectedResonance)
        )

        detectedResonances.append(resonance)
        showAddResonanceSheet = false
    }

    private func colorForSeverity(_ severity: ResonancePoint.Severity) -> Color {
        switch severity {
        case .mild: .yellow
        case .moderate: .orange
        case .severe: .red
        case .extreme: .purple
        }
    }
}

#Preview {
    ResonanceFinderView()
        .frame(width: 900, height: 700)
}
