//
//  SubjectiveRoomTuningView.swift
//  SystemEQ for Mac
//
//  Subjective Room Tuning - Personal room tuning based on hearing
//  NOT professional room correction - results depend on user's hearing and room
//

import Combine
import SwiftUI

struct SubjectiveRoomTuningView: View {
    @EnvironmentObject var localization: LocalizationManager
    @StateObject private var sineSweep = SineSweepGenerator()
    @StateObject private var calibration = CalibrationEngine.shared

    @State private var selectedTab: TuningTab = .tuning
    @State private var showDisclaimer: Bool = true
    @State private var detectedResonances: [ResonancePoint] = []
    @State private var appliedNotchFilters: [NotchFilterConfig] = []
    @State private var currentFrequency: Double = 1000.0
    @State private var refreshID = UUID() // For forcing view refresh
    @State private var showAddResonanceSheet = false
    @State private var newResonanceFrequency: Double = 1000.0
    @State private var newResonanceSeverity: ResonancePoint.Severity = .moderate
    @State private var showSaveProfileSheet = false
    @State private var profileName: String = ""
    @State private var isComparing: Bool = false
    @State private var gainMatchOffset: Float = 0.0
    @State private var abIsFiltered: Bool = true
    @State private var abTimer: Timer?

    enum TuningTab: String, CaseIterable, FeatureTab, Identifiable {
        case tuning = "Tuning"
        case filters = "Notch Filters"
        case compare = "A/B Test"

        var id: String {
            rawValue
        }

        func localizedTitle(_ localization: LocalizationManager) -> String {
            switch self {
            case .tuning:
                localization.localized(.tuningTab)
            case .filters:
                localization.localized(.notchFilters)
            case .compare:
                localization.localized(.abTest)
            }
        }
    }

    var body: some View {
        FeatureWindowContainer(
            title: .subjectiveRoomTuning,
            subtitle: .subjectiveRoomTuningDesc,
            windowSize: .large,
            hasScrollView: true,
            selectedTab: $selectedTab
        ) { tab in
            VStack(spacing: 20) {
                // Disclaimer banner (collapsible)
                if showDisclaimer {
                    disclaimerBanner
                }

                switch tab {
                case .tuning:
                    tuningSection
                case .filters:
                    filtersSection
                case .compare:
                    compareSection
                }
            }
        }
        .onDisappear {
            sineSweep.stopSweep()
        }
        .sheet(isPresented: $showAddResonanceSheet) {
            addResonanceSheet
        }
        .sheet(isPresented: $showSaveProfileSheet) {
            saveProfileSheet
        }
        .onReceive(NotificationCenter.default.publisher(for: .languageChanged)) { _ in
            // CrossfadeText handles blur animation automatically
        }
        .id(refreshID)
    }

    // MARK: - Disclaimer Banner

    private var disclaimerBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.title3)
            Text(localization.localized(.subjectiveRoomTuningDisclaimerTitle))
                .font(AppTypography.body)
                .fontWeight(.semibold)
                .foregroundColor(.orange)
                .fixedSize()
            InfoPopoverButton {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(localization.localized(.subjectiveRoomTuningDisclaimerTitle))
                            .font(.headline)
                            .foregroundColor(.orange)
                    }
                    Text(localization.localized(.subjectiveRoomTuningDisclaimer))
                        .font(.body)
                        .foregroundColor(.primary)
                }
            }
            .frame(width: 28, height: 28)
            Button(action: { showDisclaimer = false }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(10)
    }

    // MARK: - Tuning Section (manual frequency testing + add resonances)

    private var tuningSection: some View {
        VStack(spacing: 24) {
            // Info about workflow
            workflowInfoCard

            // Manual frequency testing
            manualSection

            // Detected resonances list
            resonancesListSection
        }
    }

    // MARK: - Workflow Info Card

    private var workflowInfoCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "lightbulb.fill")
                .foregroundColor(.yellow)
                .font(.title3)
            Text(localization.localized(.howToUse))
                .font(AppTypography.body)
                .fontWeight(.semibold)
                .fixedSize()
            InfoPopoverButton {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "lightbulb.fill").foregroundColor(.yellow)
                        Text(localization.localized(.howToUse)).font(.headline)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Label(localization.localized(.howToUseStep1), systemImage: "1.circle.fill").font(.body)
                        Label(localization.localized(.howToUseStep2), systemImage: "2.circle.fill").font(.body)
                        Label(localization.localized(.howToUseStep3), systemImage: "3.circle.fill").font(.body)
                        Label(localization.localized(.howToUseStep4), systemImage: "4.circle.fill").font(.body)
                    }
                    .foregroundColor(.primary)
                }
            }
            .frame(width: 28, height: 28)
        }
        .padding(12)
        .background(Color.blue.opacity(0.05))
        .cornerRadius(10)
    }

    // MARK: - Resonances List Section

    private var resonancesListSection: some View {
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
                        .font(AppTypography.body)
                        .foregroundColor(.secondary)
                    Text(localization.localized(.useResonanceFinderHint))
                        .font(AppTypography.label)
                        .foregroundColor(.secondary)
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
                                .font(AppTypography.body)
                                .fontWeight(.semibold)
                            Text(resonance.description)
                                .font(AppTypography.label)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        // Severity indicator
                        HStack(spacing: 4) {
                            ForEach(0..<resonance.severity.rating, id: \.self) { _ in
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(AppTypography.label)
                                    .foregroundColor(colorForSeverity(resonance.severity))
                            }
                        }

                        Button(action: {
                            sineSweep.playFixedFrequency(resonance.frequency, duration: 2.0)
                        }) {
                            Image(systemName: "play.circle")
                        }
                        .buttonStyle(BorderedButtonStyle())

                        Button(action: {
                            addNotchFilter(for: resonance)
                        }) {
                            Text(localization.localized(.addFilter))
                                .font(AppTypography.label)
                        }
                        .buttonStyle(.borderedProminent)

                        Button(action: {
                            detectedResonances.removeAll { $0.id == resonance.id }
                        }) {
                            Image(systemName: "trash")
                                .font(AppTypography.label)
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

    // MARK: - Manual Section

    /// Standard EQ frequencies for quick selection
    private let quickFrequencies: [Double] = [31, 63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]

    /// Convert linear slider value (0-1) to logarithmic frequency (20-20000 Hz)
    private func logFrequency(from linear: Double) -> Double {
        let minLog = log10(20.0)
        let maxLog = log10(20000.0)
        return pow(10, minLog + linear * (maxLog - minLog))
    }

    /// Convert frequency to linear slider value (0-1)
    private func linearValue(from frequency: Double) -> Double {
        let minLog = log10(20.0)
        let maxLog = log10(20000.0)
        return (log10(frequency) - minLog) / (maxLog - minLog)
    }

    /// Format frequency for display
    private func formatFrequency(_ freq: Double) -> String {
        if freq >= 1000 {
            String(format: "%.1fk", freq / 1000)
        } else {
            String(format: "%.0f", freq)
        }
    }

    private var manualSection: some View {
        VStack(spacing: 20) {
            Text(localization.localized(.manualFrequencyTest))
                .font(.headline)

            Text(localization.localized(.testSpecificFrequencies))
                .font(AppTypography.body)
                .foregroundColor(.secondary)

            // Quick frequency buttons
            VStack(spacing: 10) {
                Text(localization.localized(.quickFrequencySelect))
                    .font(AppTypography.label)
                    .foregroundColor(.secondary)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                    ForEach(quickFrequencies, id: \.self) { freq in
                        Button(action: {
                            currentFrequency = freq
                            if sineSweep.isPlaying {
                                sineSweep.playContinuousTone(freq)
                            }
                        }) {
                            Text(formatFrequency(freq))
                                .font(.system(size: 15, weight: .medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.bordered)
                        .tint(currentFrequency == freq ? .blue : .secondary)
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
                        .font(AppTypography.body)
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
                        .font(AppTypography.label)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("100")
                        .font(AppTypography.labelSmall)
                        .foregroundColor(.secondary.opacity(0.6))
                    Spacer()
                    Text("1k")
                        .font(AppTypography.labelSmall)
                        .foregroundColor(.secondary.opacity(0.6))
                    Spacer()
                    Text("10k")
                        .font(AppTypography.labelSmall)
                        .foregroundColor(.secondary.opacity(0.6))
                    Spacer()
                    Text("20k Hz")
                        .font(AppTypography.label)
                        .foregroundColor(.secondary)
                }
            }
            .padding(14)
            .background(Color.gray.opacity(0.05))
            .cornerRadius(8)

            // Play/Stop button
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
                        Text(sineSweep.isPlaying ? localization.localized(.stopPlayback) : localization
                            .localized(.playTone))
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

            // Hint
            if sineSweep.isPlaying {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundColor(.blue)
                    Text(localization.localized(.sliderFrequencyHint))
                        .font(AppTypography.label)
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

    // MARK: - Filters Section

    private var filtersSection: some View {
        VStack(spacing: 24) {
            // Detected resonances
            VStack(alignment: .leading, spacing: 12) {
                Text(localization.localized(.detectedResonances))
                    .font(.headline)

                if detectedResonances.isEmpty {
                    Text(localization.localized(.noResonancesDetected))
                        .font(AppTypography.body)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray.opacity(0.05))
                        .cornerRadius(8)
                } else {
                    ForEach(detectedResonances) { resonance in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(Int(resonance.frequency)) \(localization.localized(.frequencyHz))")
                                    .font(AppTypography.body)
                                    .fontWeight(.semibold)
                                Text(resonance.description)
                                    .font(AppTypography.label)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            // Severity indicator
                            HStack(spacing: 4) {
                                ForEach(0..<resonance.severity.rating, id: \.self) { _ in
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(AppTypography.label)
                                        .foregroundColor(colorForSeverity(resonance.severity))
                                }
                            }

                            Button(action: {
                                addNotchFilter(for: resonance)
                            }) {
                                Text(localization.localized(.addFilter))
                                    .font(AppTypography.label)
                            }
                            .buttonStyle(BorderedButtonStyle())
                        }
                        .padding(12)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                    }
                }
            }

            Divider()

            // Applied notch filters
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(localization.localized(.appliedNotchFilters))
                        .font(.headline)
                    Spacer()
                    if !appliedNotchFilters.isEmpty {
                        Button(localization.localized(.clearAll)) {
                            appliedNotchFilters.removeAll()
                            applyNotchFilters()
                        }
                        .buttonStyle(BorderedButtonStyle())
                    }
                }

                if appliedNotchFilters.isEmpty {
                    Text(localization.localized(.noNotchFiltersApplied))
                        .font(AppTypography.body)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray.opacity(0.05))
                        .cornerRadius(8)
                } else {
                    ForEach(appliedNotchFilters) { filter in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(Int(filter.frequency)) \(localization.localized(.frequencyHz)) Notch")
                                    .font(AppTypography.body)
                                    .fontWeight(.semibold)
                                Text(String(format: "Gain: %.1f dB, Q: %.1f", filter.gain, filter.q))
                                    .font(AppTypography.label)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Button(action: {
                                if let index = appliedNotchFilters.firstIndex(where: { $0.id == filter.id }) {
                                    appliedNotchFilters.remove(at: index)
                                    applyNotchFilters()
                                }
                            }) {
                                Image(systemName: "trash")
                                    .font(AppTypography.label)
                            }
                            .buttonStyle(BorderedButtonStyle())
                        }
                        .padding(12)
                        .background(Color.red.opacity(0.05))
                        .cornerRadius(8)
                    }
                }
            }
        }
    }

    // MARK: - Compare Section

    private var compareSection: some View {
        VStack(spacing: 24) {
            Text(localization.localized(.abComparison))
                .font(.headline)

            Text(localization.localized(.compareOriginalVsFiltered))
                .font(AppTypography.body)
                .foregroundColor(.secondary)

            // Gain matching info
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundColor(.blue)
                    Text(localization.localized(.gainMatching))
                        .font(AppTypography.body)
                        .fontWeight(.semibold)
                }
                Text(localization.localized(.gainMatchingDesc))
                    .font(AppTypography.label)
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .background(Color.blue.opacity(0.05))
            .cornerRadius(8)

            // Comparison controls
            HStack(spacing: 12) {
                Button(action: {
                    toggleComparison()
                }) {
                    HStack {
                        Image(systemName: isComparing ? "stop.circle" : "play.circle")
                        Text(isComparing ? localization.localized(.stopABTest) : localization.localized(.startABTest))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button(action: {
                    saveCalibrationProfile()
                }) {
                    HStack {
                        Image(systemName: "checkmark")
                        Text(localization.localized(.saveProfile))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(BorderedButtonStyle())
                .disabled(appliedNotchFilters.isEmpty)
            }

            if isComparing {
                VStack(spacing: 12) {
                    Text(localization.localized(.alternatingOriginalFiltered))
                        .font(AppTypography.body)
                        .foregroundColor(.blue)
                        .fontWeight(.semibold)

                    Text(String(format: "Gain Match: %.1f dB", gainMatchOffset))
                        .font(AppTypography.label)
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .background(Color.blue.opacity(0.05))
                .cornerRadius(8)
            }
        }
        .padding(18)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }

    // MARK: - Helper Views

    private var addResonanceSheet: some View {
        VStack(spacing: 20) {
            // Title
            Text(localization.localized(.addResonance))
                .font(.title2)
                .fontWeight(.semibold)

            // Explanation
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.blue)
                    Text(localization.localized(.whatIsThis))
                        .font(AppTypography.body)
                        .fontWeight(.medium)
                }
                Text(localization.localized(.resonanceExplanation))
                    .font(AppTypography.label)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(Color.blue.opacity(0.1))
            .cornerRadius(8)

            // Frequency display
            VStack(alignment: .leading, spacing: 8) {
                Text(localization.localized(.frequency))
                    .font(AppTypography.body)
                    .foregroundColor(.secondary)
                Text(String(format: "%.0f Hz", newResonanceFrequency))
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Severity picker
            VStack(alignment: .leading, spacing: 10) {
                Text(localization.localized(.resonanceStrength))
                    .font(AppTypography.body)
                    .foregroundColor(.secondary)

                Text(localization.localized(.resonanceStrengthDesc))
                    .font(AppTypography.label)
                    .foregroundColor(.secondary)

                // Vertical buttons instead of segmented picker
                VStack(spacing: 8) {
                    ForEach([
                        (
                            ResonancePoint.Severity.mild,
                            localization.localized(.severityMild),
                            "-2 dB",
                            localization.localized(.severityMildDesc)
                        ),
                        (
                            ResonancePoint.Severity.moderate,
                            localization.localized(.severityModerate),
                            "-4 dB",
                            localization.localized(.severityModerateDesc)
                        ),
                        (
                            ResonancePoint.Severity.severe,
                            localization.localized(.severitySevere),
                            "-6 dB",
                            localization.localized(.severitySevereDesc)
                        ),
                        (
                            ResonancePoint.Severity.extreme,
                            localization.localized(.severityExtreme),
                            "-8 dB",
                            localization.localized(.severityExtremeDesc)
                        )
                    ], id: \.0) { severity, name, db, desc in
                        Button(action: {
                            newResonanceSeverity = severity
                        }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(name)
                                            .font(AppTypography.body)
                                            .fontWeight(.medium)
                                        Text(db)
                                            .font(AppTypography.label)
                                            .foregroundColor(.secondary)
                                    }
                                    Text(desc)
                                        .font(AppTypography.labelSmall)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if newResonanceSeverity == severity {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.blue)
                                }
                            }
                            .padding(10)
                            .background(newResonanceSeverity == severity ? Color.blue.opacity(0.15) : Color.gray
                                .opacity(0.1))
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Action buttons
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
        .frame(width: 450)
    }

    private var saveProfileSheet: some View {
        VStack(spacing: 20) {
            Text(localization.localized(.saveCalibrationProfile))
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 8) {
                Text(localization.localized(.profileName))
                    .font(AppTypography.body)
                    .foregroundColor(.secondary)
                TextField("e.g., Living Room - Notch Filters", text: $profileName)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 12) {
                Button(localization.localized(.cancel)) {
                    showSaveProfileSheet = false
                    profileName = ""
                }
                .buttonStyle(BorderedButtonStyle())

                Button(localization.localized(.save)) {
                    saveProfile()
                }
                .buttonStyle(.borderedProminent)
                .disabled(profileName.isEmpty)
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

    private func addNotchFilter(for resonance: ResonancePoint) {
        let filter = ResonanceDetector.getNotchFilterRecommendation(
            for: resonance.frequency,
            severity: resonance.severity
        )

        if !appliedNotchFilters.contains(where: { $0.frequency == filter.frequency }) {
            appliedNotchFilters.append(filter)
            applyNotchFilters()
        }
    }

    private func applyNotchFilters() {
        let tuples = appliedNotchFilters.map { f in
            (frequency: Float(f.frequency), gain: f.gain, q: f.q)
        }
        CoreAudioEngine.shared.applyRoomNotchFilters(tuples)
        dlog("🏠 Applied \(tuples.count) room notch filter(s)", category: .calibration)
    }

    private func toggleComparison() {
        isComparing.toggle()
        if isComparing {
            startABComparison()
        } else {
            stopABComparison()
        }
    }

    private func startABComparison() {
        guard !appliedNotchFilters.isEmpty else { return }

        // Average notch gain across all filters to estimate loudness change
        let avgGain = appliedNotchFilters.map(\.gain).reduce(0, +) / Float(appliedNotchFilters.count)
        gainMatchOffset = -avgGain // compensate: filters cut, so add back when bypassed

        abIsFiltered = true
        applyNotchFilters()

        abTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            abIsFiltered.toggle()
            if abIsFiltered {
                let tuples = appliedNotchFilters.map { (frequency: Float($0.frequency), gain: $0.gain, q: $0.q) }
                CoreAudioEngine.shared.applyRoomNotchFilters(tuples)
            } else {
                CoreAudioEngine.shared.clearRoomNotchFilters()
            }
        }
        dlog("▶️ A/B comparison started (2s interval, gain offset: \(gainMatchOffset) dB)", category: .calibration)
    }

    private func stopABComparison() {
        abTimer?.invalidate()
        abTimer = nil
        abIsFiltered = true
        applyNotchFilters()
        dlog("⏹ A/B comparison stopped", category: .calibration)
    }

    private func saveCalibrationProfile() {
        showSaveProfileSheet = true
    }

    private func saveProfile() {
        // Create calibration profile with notch filters
        let profile = CalibrationProfile(
            name: profileName,
            type: .roomCorrection,
            bands: Array(repeating: 0.0, count: 31), // Notch filters work differently
            notes: "Room calibration with \(appliedNotchFilters.count) notch filters"
        )

        // Save profile to CalibrationEngine
        calibration.profiles.append(profile)
        calibration.updateProfile(profile)

        showSaveProfileSheet = false
        profileName = ""

        // Switch to profiles tab
        dlog("✅ Room calibration profile '\(profile.name)' saved successfully", category: .calibration)
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

/// Alias for backward compatibility
typealias RoomCalibrationView = SubjectiveRoomTuningView

#Preview {
    SubjectiveRoomTuningView()
        .frame(width: 1000, height: 750)
}
