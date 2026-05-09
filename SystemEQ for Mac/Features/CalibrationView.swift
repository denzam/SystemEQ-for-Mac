import SwiftUI

// MARK: - Custom Button Styles for macOS 13+ compatibility

struct ProfileButtonStyle: ButtonStyle {
    let isActive: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(configuration
                .isPressed ? (isActive ? Color.blue.opacity(0.7) : Color.gray.opacity(0.5)) :
                (isActive ? Color.blue : Color.gray.opacity(0.2)))
            .foregroundColor(isActive ? .white : .primary)
            .cornerRadius(6)
    }
}

struct BorderedButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(configuration.isPressed ? Color.gray.opacity(0.1) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.gray.opacity(0.5), lineWidth: 1)
            )
    }
}

struct CalibrationView: View {
    @ObservedObject private var localization = LocalizationManager.shared
    @ObservedObject private var calibration = CalibrationEngine.shared

    @State private var selectedTab: CalibrationTab = .equalLoudness
    @State private var currentProfile: CalibrationProfile?
    @State private var showNewProfileSheet = false
    @State private var showDeleteAlert = false
    @State private var profileToDelete: CalibrationProfile?

    // Equal Loudness state
    @State private var selectedCalibrationMode: CalibrationMode = .clean
    @State private var selectedBandCount: BandCount = .bands10
    @State private var show31BandWarning1 = false
    @State private var show31BandWarning2 = false
    @State private var testBands: [Float] = Array(repeating: 0.0, count: 31)
    @State private var currentTestBandIndex: Int = 0
    @State private var isReferenceStep: Bool = true
    @State private var profileName: String = ""
    @State private var profileNotes: String = ""

    // A/B comparison
    @State private var profileA: CalibrationProfile?
    @State private var profileB: CalibrationProfile?
    @State private var isComparingA: Bool = true
    @State private var isComparingClean: Bool = false

    enum CalibrationTab: CaseIterable, FeatureTab {
        case equalLoudness
        case profiles
        case comparison

        var id: String {
            switch self {
            case .equalLoudness: "equalLoudness"
            case .profiles: "profiles"
            case .comparison: "comparison"
            }
        }

        func localizedTitle(_ localization: LocalizationManager) -> String {
            switch self {
            case .equalLoudness: localization.localized(.equalLoudness)
            case .profiles: localization.localized(.profiles)
            case .comparison: localization.localized(.abCompare)
            }
        }
    }

    enum BandCount: Int, CaseIterable {
        case bands10 = 10
        case bands31 = 31

        func displayName(_ localization: LocalizationManager) -> String {
            switch self {
            case .bands10: localization.localized(.bands10Time)
            case .bands31: localization.localized(.bands31Time)
            }
        }
    }

    var body: some View {
        FeatureWindowContainer(
            title: .calibrationTitle,
            subtitle: .calibrationSubtitle,
            windowSize: .large,
            selectedTab: $selectedTab
        ) { tab in
            switch tab {
            case .equalLoudness:
                equalLoudnessSection
            case .profiles:
                profilesSection
            case .comparison:
                comparisonSection
            }
        }
        .onDisappear {
            // Restore EQ state if calibration was interrupted
            if !isReferenceStep {
                calibration.endCalibration(mode: selectedCalibrationMode)
            }
        }
        .sheet(isPresented: $showNewProfileSheet) {
            newProfileSheet
        }
        .alert(localization.localized(.warning31Bands), isPresented: $show31BandWarning1) {
            Button(localization.localized(.warning31BandsButton1), role: .cancel) {
                selectedBandCount = .bands10
            }
            Button(localization.localized(.warning31BandsButton2)) {
                show31BandWarning2 = true
            }
        } message: {
            Text(localization.localized(.calibration31BandsWarning))
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("Show31BandWarning"))) { _ in
            selectedBandCount = .bands31
            show31BandWarning1 = true
        }
        .alert(localization.localized(.warning31BandsFinal), isPresented: $show31BandWarning2) {
            Button(localization.localized(.warning31BandsFinalButton1), role: .cancel) {
                selectedBandCount = .bands10
            }
            Button(localization.localized(.warning31BandsFinalButton2)) {
                startCalibration()
            }
        } message: {
            Text(localization.localized(.calibration31BandsFinalWarning))
        }
        .alert(
            localization.localized(.deleteProfile2),
            isPresented: $showDeleteAlert,
            presenting: profileToDelete
        ) { profile in
            Button(localization.localized(.cancel), role: .cancel) {}
            Button(localization.localized(.deleteProfile2), role: .destructive) {
                calibration.deleteProfile(profile)
            }
        } message: { profile in
            Text(String(format: localization.localized(.deleteProfileMessage), profile.name))
        }
        .onReceive(NotificationCenter.default.publisher(for: .languageChanged)) { _ in
            // Force view refresh when language changes
        }
    }

    // MARK: - Equal Loudness Section

    private var equalLoudnessSection: some View {
        VStack(spacing: 24) {
            // Info card
            infoCard

            // Calibration mode selector
            if isReferenceStep {
                calibrationModeSelector
            }

            // Band count selector
            if isReferenceStep {
                bandCountSelector
            }

            // Calibration wizard
            if isReferenceStep {
                referenceSetupView
            } else {
                frequencyCalibrationView
            }
        }
        .padding(AppSpacing.xl)
    }

    private var infoCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "headphones")
                .font(.title2)
                .foregroundColor(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(localization.localized(.equalLoudnessCalibration))
                    .font(.headline)
                Text(localization.localized(.calibrationCompensateHeadphones))
                    .font(AppTypography.body)
                    .foregroundColor(.secondary)
            }
            .fixedSize()
            InfoPopoverButton {
                calibrationInfoPopoverContent
            }
            .frame(width: 28, height: 28)
            Spacer()
        }
        .padding(14)
        .background(Color.blue.opacity(0.05))
        .cornerRadius(8)
    }

    private var calibrationInfoPopoverContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(localization.localized(.calibrationImportantLimitations))
                        .font(.headline)
                        .foregroundColor(.orange)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(localization.localized(.calibrationWhatWillImprove))
                        .font(AppTypography.body)
                        .fontWeight(.semibold)
                        .foregroundColor(.green)
                    ForEach([
                        localization.localized(.calibrationMidHighBalance),
                        localization.localized(.calibrationHearingCompensation),
                        localization.localized(.calibrationHeadphoneCorrection),
                        localization.localized(.calibrationLessFatigue)
                    ], id: \.self) { item in
                        Text("• \(item)").font(AppTypography.body).foregroundColor(.secondary)
                    }
                    Text(localization.localized(.calibrationWhatWontFix))
                        .font(AppTypography.body)
                        .fontWeight(.semibold)
                        .foregroundColor(.orange)
                        .padding(.top, 4)
                    Text("• \(localization.localized(.calibrationDriverLimitations))")
                        .font(AppTypography.body)
                        .foregroundColor(.secondary)
                }
            }
            .padding(12)
            .background(Color.orange.opacity(0.07))
            .cornerRadius(8)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("🎯")
                    Text(localization.localized(.calibrationMethodPrincipleTitle))
                        .font(AppTypography.body).fontWeight(.semibold)
                }
                Text(localization.localized(.calibrationMethodPrincipleDesc))
                    .font(AppTypography.body).foregroundColor(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                ForEach([
                    ("1️⃣", localization.localized(.calibrationPreparation), localization.localized(.calibrationPreparationDesc)),
                    ("2️⃣", localization.localized(.calibrationReference1000), localization.localized(.calibrationReference1000Desc)),
                    ("3️⃣", localization.localized(.calibrationAdjustFrequencies), localization.localized(.calibrationAdjustFrequenciesDesc)),
                    ("4️⃣", localization.localized(.calibrationVerification), localization.localized(.calibrationVerificationDesc))
                ], id: \.1) { emoji, title, desc in
                    HStack(alignment: .top, spacing: 8) {
                        Text(emoji)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title).font(AppTypography.body).fontWeight(.semibold)
                            Text(desc).font(AppTypography.body).foregroundColor(.secondary)
                        }
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "lightbulb.fill").foregroundColor(.yellow)
                    Text(localization.localized(.calibrationProTips))
                        .font(AppTypography.body).fontWeight(.semibold)
                }
                ForEach([
                    localization.localized(.calibrationProTip1),
                    localization.localized(.calibrationProTip2),
                    localization.localized(.calibrationProTip3),
                    localization.localized(.calibrationProTip4),
                    localization.localized(.calibrationProTip5)
                ], id: \.self) { tip in
                    Text("• \(tip)").font(AppTypography.body).foregroundColor(.secondary)
                }
            }
        }
    }

    private var calibrationModeSelector: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(localization.localized(.chooseCalibrationMode))
                .font(.headline)

            HStack(spacing: 16) {
                ForEach(CalibrationMode.allCases, id: \.self) { mode in
                    Button(action: {
                        selectedCalibrationMode = mode
                    }) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: mode.icon)
                                    .font(.title2)
                                Text(localization.localized(mode == .clean ? .calibrationModeClean : .calibrationModeCombined))
                                    .font(.headline)
                            }

                            Text(localization.localized(mode == .clean ? .calibrationModeCleanDesc : .calibrationModeCombinedDesc))
                                .font(AppTypography.label)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)

                            if mode == .clean {
                                Text(localization.localized(.recommended))
                                    .font(AppTypography.labelSmall)
                                    .foregroundColor(.green)
                            } else {
                                Text(localization.localized(.advanced))
                                    .font(AppTypography.labelSmall)
                                    .foregroundColor(.orange)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(
                            selectedCalibrationMode == mode ?
                                Color.blue.opacity(0.15) : Color.gray.opacity(0.05)
                        )
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(
                                    selectedCalibrationMode == mode ? Color.blue : Color.clear,
                                    lineWidth: 2
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var bandCountSelector: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(localization.localized(.chooseCalibrationPrecision))
                .font(.headline)

            HStack(spacing: 16) {
                ForEach(BandCount.allCases, id: \.self) { count in
                    Button(action: {
                        if count == .bands31, selectedBandCount != .bands31 {
                            selectedBandCount = .bands31 // Set immediately for visual feedback
                            show31BandWarning1 = true
                        } else {
                            selectedBandCount = count
                        }
                    }) {
                        VStack(spacing: 8) {
                            Text("\(count.rawValue)")
                                .font(.title)
                                .fontWeight(.bold)
                            Text(count.displayName(localization))
                                .font(AppTypography.label)
                            if count == .bands10 {
                                Text(localization.localized(.recommended))
                                    .font(AppTypography.labelSmall)
                                    .foregroundColor(.green)
                            } else {
                                Text(localization.localized(.forPerfectionists))
                                    .font(AppTypography.labelSmall)
                                    .foregroundColor(.orange)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .padding(.horizontal, 12)
                        .background(
                            selectedBandCount == count ?
                                Color.blue.opacity(0.15) : Color.gray.opacity(0.05)
                        )
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(
                                    selectedBandCount == count ? Color.blue : Color.clear,
                                    lineWidth: 2
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var referenceSetupView: some View {
        VStack(spacing: 16) {
            VStack(spacing: 12) {
                Text(localization.localized(.step1SetReference))
                    .font(.title3)
                    .fontWeight(.semibold)

                Text(localization.localized(.step1SetReferenceDesc))
                    .font(AppTypography.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                Text(localization.localized(.step1SetReferenceNote))
                    .font(AppTypography.label)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Reference frequency display
            VStack(spacing: 8) {
                Text("1000 \(localization.localized(.frequencyHz))")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundColor(.blue)

                Text(localization.localized(.referenceFrequency))
                    .font(AppTypography.label)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 20)
            .background(Color.blue.opacity(0.05))
            .cornerRadius(8)

            // Level adjustment
            VStack(spacing: 12) {
                HStack {
                    Text(localization.localized(.volumeLevel))
                        .font(AppTypography.body)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.1f \(localization.localized(.dB))", calibration.referenceLevel))
                        .font(AppTypography.body)
                        .fontWeight(.semibold)
                }

                Slider(value: $calibration.referenceLevel, in: -40...0, step: 1)
                    .accentColor(.blue)
                    .onChange(of: calibration.referenceLevel) { newValue in
                        // ⚡ OPTIMIZATION: Only update if playing loop (not on every slider change)
                        // For loop mode, amplitude updates are handled in real-time without restarting
                        if calibration.isPlayingLoop {
                            let amplitude = pow(10.0, newValue / 20.0) * 0.3
                            if calibration.useFilteredNoise {
                                calibration.updatePinkNoiseLoopAmplitude(amplitude)
                            } else {
                                calibration.updateLoopAmplitude(amplitude)
                            }
                        }
                    }

                HStack {
                    Text("-40 \(localization.localized(.dB))")
                        .font(AppTypography.label)
                        .foregroundColor(.secondary)
                    Text(localization.localized(.quiet))
                        .font(AppTypography.label)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("0 \(localization.localized(.dB))")
                        .font(AppTypography.label)
                        .foregroundColor(.secondary)
                    Text(localization.localized(.loud))
                        .font(AppTypography.label)
                        .foregroundColor(.secondary)
                }
            }
            .padding(14)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            // Play/Stop button
            VStack(spacing: 8) {
                Button(action: {
                    if calibration.isPlayingReference {
                        calibration.stopTestTone()
                    } else {
                        calibration.playReferenceTone()
                    }
                }) {
                    HStack {
                        Image(systemName: calibration.isPlayingReference ? "stop.fill" : "play.fill")
                        Text(calibration.isPlayingReference ? localization.localized(.stopReference) : localization
                            .localized(.playReference))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                if calibration.isPlayingReference {
                    Text(localization.localized(.listenCarefully))
                        .font(AppTypography.label)
                        .foregroundColor(.blue)
                        .fontWeight(.semibold)
                }
            }

            Divider()

            // Instructions
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundColor(.blue)
                        .font(AppTypography.label)
                    Text(localization.localized(.howToSetupCorrectly))
                        .font(AppTypography.label)
                        .fontWeight(.semibold)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("•")
                            .font(AppTypography.label)
                        Text(localization.localized(.sitInUsualPlace))
                            .font(AppTypography.label)
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("•")
                            .font(AppTypography.label)
                        Text(localization.localized(.closeEyesForFocus))
                            .font(AppTypography.label)
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("•")
                            .font(AppTypography.label)
                        Text(localization.localized(.volumeShouldBeComfortable))
                            .font(AppTypography.label)
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("•")
                            .font(AppTypography.label)
                        Text(localization.localized(.rememberThisVolume))
                            .font(AppTypography.label)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(12)
            .background(Color.blue.opacity(0.03))
            .cornerRadius(6)

            // Continue button
            Button(action: {
                calibration.isReferenceSet = true
                isReferenceStep = false
                currentTestBandIndex = 0

                // Start calibration with selected mode
                calibration.startCalibration(mode: selectedCalibrationMode)
            }) {
                HStack {
                    Text(localization.localized(.continueCalibration))
                    Image(systemName: "arrow.right")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!calibration.isReferenceSet)
        }
        .padding(18)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }

    private var frequencyCalibrationView: some View {
        let frequencies = selectedBandCount == .bands10 ?
            calibration.get10BandFrequencies() : calibration.standardFrequencies
        let currentFrequency = frequencies[currentTestBandIndex]

        return VStack(spacing: 20) {
            // Progress
            VStack(spacing: 8) {
                HStack {
                    Text(localization.localized(.progress))
                        .font(AppTypography.body)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(currentTestBandIndex + 1) / \(frequencies.count)")
                        .font(AppTypography.body)
                        .fontWeight(.semibold)
                }

                VStack(spacing: 10) {
                    Text(localization.localized(.step2AdjustFrequencies))
                        .font(.title3)
                        .fontWeight(.semibold)

                    Text(localization.localized(.step2AdjustFrequenciesDesc))
                        .font(AppTypography.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                    VStack(spacing: 10) {
                        Text(localization.localized(.currentFrequencyLabel))
                            .font(AppTypography.body)
                            .foregroundColor(.secondary)

                        Text(calibration.frequencyLabel(currentFrequency) + " \(localization.localized(.frequencyHz))")
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .foregroundColor(.blue)

                        Text(localization.localized(.adjustToReferenceVolume))
                            .font(AppTypography.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        Text(localization.localized(.tipCloseEyes))
                            .font(AppTypography.label)
                            .foregroundColor(.blue)
                            .fontWeight(.semibold)
                    }
                    .padding(.vertical, 18)
                    .padding(.horizontal, 20)
                    .frame(maxWidth: .infinity)
                    .background(Color.blue.opacity(0.05))
                    .cornerRadius(10)
                }

                // Level adjustment
                VStack(spacing: 12) {
                    HStack {
                        Text(localization.localized(.levelCorrection))
                            .font(AppTypography.body)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(String(
                            format: "%+.1f \(localization.localized(.dB))",
                            testBands[getGlobalBandIndex(currentTestBandIndex)]
                        ))
                        .font(AppTypography.body)
                        .fontWeight(.semibold)
                        .foregroundColor(testBands[getGlobalBandIndex(currentTestBandIndex)] > 0 ? .green : .red)
                    }

                    Slider(
                        value: Binding(
                            get: { testBands[getGlobalBandIndex(currentTestBandIndex)] },
                            set: { newValue in
                                testBands[getGlobalBandIndex(currentTestBandIndex)] = newValue
                                // Update amplitude in real-time if tone is playing in loop mode
                                if calibration.isPlayingLoop {
                                    let level = calibration.referenceLevel + newValue
                                    let amplitude = pow(10.0, level / 20.0) * 0.3
                                    if calibration.useFilteredNoise {
                                        calibration.updatePinkNoiseLoopAmplitude(amplitude)
                                    } else {
                                        calibration.updateLoopAmplitude(amplitude)
                                    }
                                }
                                // Also update during comparison mode for next test signal
                                if calibration.comparisonMode {
                                    let level = calibration.referenceLevel + newValue
                                    calibration.updateComparisonTestLevel(level)
                                }
                            }
                        ),
                        in: -20...20,
                        step: 0.5
                    )
                    .accentColor(.blue)

                    HStack {
                        Text(localization.localized(.quieter2))
                            .font(AppTypography.label)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(localization.localized(.louder2))
                            .font(AppTypography.label)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(14)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)

                // Test controls
                VStack(spacing: 12) {
                    Text(localization.localized(.testingFrequency))
                        .font(AppTypography.body)
                        .fontWeight(.semibold)

                    // Signal type selector
                    VStack(spacing: 8) {
                        HStack {
                            Text(localization.localized(.testSignalType))
                                .font(AppTypography.body)
                                .foregroundColor(.secondary)
                            Spacer()
                        }

                        HStack(spacing: 16) {
                            Button(action: {
                                calibration.useFilteredNoise = true
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "waveform.path")
                                        .font(.system(size: 16))
                                    Text(localization.localized(.pinkNoise))
                                        .font(.system(size: 15))
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(calibration.useFilteredNoise ? Color.blue.opacity(0.15) : Color.clear)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(
                                            calibration.useFilteredNoise ? Color.blue : Color.gray.opacity(0.3),
                                            lineWidth: 1
                                        )
                                )
                            }
                            .buttonStyle(.plain)

                            Button(action: {
                                calibration.useFilteredNoise = false
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "sinewave")
                                        .font(.system(size: 16))
                                    Text(localization.localized(.pureTone))
                                        .font(.system(size: 15))
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(!calibration.useFilteredNoise ? Color.blue.opacity(0.15) : Color.clear)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(
                                            !calibration.useFilteredNoise ? Color.blue : Color.gray.opacity(0.3),
                                            lineWidth: 1
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    HStack(spacing: 12) {
                        Button(action: {
                            let level = calibration.referenceLevel + testBands[getGlobalBandIndex(currentTestBandIndex)]
                            let amplitude = pow(10.0, level / 20.0) * 0.3
                            if calibration.isTestTonePlaying {
                                calibration.stopTestTone()
                            } else {
                                if calibration.useFilteredNoise {
                                    calibration.playFilteredPinkNoiseLoop(
                                        frequency: currentFrequency,
                                        amplitude: amplitude
                                    )
                                } else {
                                    calibration.playTestToneLoop(frequency: currentFrequency, amplitude: amplitude)
                                }
                            }
                        }) {
                            HStack {
                                Image(systemName: calibration.isTestTonePlaying ? "stop.fill" : "play.fill")
                                Text(calibration.isTestTonePlaying ? localization.localized(.stopTest) : localization
                                    .localized(.testFrequency))
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)

                        Button(action: {
                            let level = calibration.referenceLevel + testBands[getGlobalBandIndex(currentTestBandIndex)]
                            if calibration.comparisonMode {
                                calibration.stopComparisonMode()
                            } else {
                                calibration.stopTestTone()
                                calibration.startComparisonMode(testFrequency: currentFrequency, testLevel: level)
                            }
                        }) {
                            HStack {
                                Image(systemName: calibration.comparisonMode ? "stop.circle" : "arrow.left.arrow.right")
                                Text(calibration.comparisonMode ? localization.localized(.stopComparison) : localization
                                    .localized(.compareAlternating))
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(BorderedButtonStyle())
                    }

                    if calibration.comparisonMode {
                        Text(localization.localized(.alternatingPattern))
                            .font(AppTypography.label)
                            .foregroundColor(.blue)
                            .fontWeight(.semibold)
                    }
                }

                // Instructions
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "lightbulb.fill")
                            .foregroundColor(.yellow)
                            .font(AppTypography.label)
                        Text(localization.localized(.howToAdjustCorrectly))
                            .font(AppTypography.label)
                            .fontWeight(.semibold)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("1.")
                                .font(AppTypography.label)
                                .fontWeight(.semibold)
                            Text(localization.localized(.pressTestFrequency))
                                .font(AppTypography.label)
                                .foregroundColor(.secondary)
                        }
                        HStack {
                            Text("2.")
                                .font(AppTypography.label)
                                .fontWeight(.semibold)
                            Text(localization.localized(.moveSliderRealtime))
                                .font(AppTypography.label)
                                .foregroundColor(.secondary)
                        }
                        HStack {
                            Text("3.")
                                .font(AppTypography.label)
                                .fontWeight(.semibold)
                            Text(localization.localized(.pressStopWhenDone))
                                .font(AppTypography.label)
                                .foregroundColor(.secondary)
                        }
                        HStack {
                            Text("4.")
                                .font(AppTypography.label)
                                .fontWeight(.semibold)
                            Text(localization.localized(.useCompareForAB))
                                .font(AppTypography.label)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(12)
                .background(Color.yellow.opacity(0.05))
                .cornerRadius(6)

                // Progress indicator
                VStack(spacing: 8) {
                    HStack {
                        Text(localization.localized(.progress))
                            .font(AppTypography.body)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(
                            "\(currentTestBandIndex + 1) \(localization.localized(.progressOf)) \(selectedBandCount == .bands10 ? 10 : 31)"
                        )
                        .font(AppTypography.body)
                        .fontWeight(.semibold)
                    }

                    ProgressView(
                        value: Double(currentTestBandIndex + 1),
                        total: Double(selectedBandCount == .bands10 ? 10 : 31)
                    )
                    .accentColor(.blue)
                }
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)

                // Navigation
                HStack(spacing: 12) {
                    Button(action: {
                        calibration.stopTestTone()
                        calibration.stopComparisonMode()
                        if currentTestBandIndex > 0 {
                            currentTestBandIndex -= 1
                        } else {
                            // Back to reference setup
                            isReferenceStep = true
                        }
                    }) {
                        HStack {
                            Image(systemName: "chevron.left")
                            Text(currentTestBandIndex == 0 ? localization.localized(.backToReference) : localization
                                .localized(.previous))
                        }
                    }
                    .buttonStyle(BorderedButtonStyle())

                    if currentTestBandIndex < (selectedBandCount == .bands10 ? 9 : 30) {
                        Button(action: {
                            calibration.stopTestTone()
                            calibration.stopComparisonMode()
                            currentTestBandIndex += 1
                        }) {
                            HStack {
                                Text(localization.localized(.nextFrequency))
                                Image(systemName: "chevron.right")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button(action: {
                            calibration.stopTestTone()
                            calibration.stopComparisonMode()
                            showNewProfileSheet = true
                        }) {
                            HStack {
                                Text(localization.localized(.saveProfileButton))
                                Image(systemName: "checkmark")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .padding(18)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
        }
    }

    // MARK: - Profiles Section

    private var profilesSection: some View {
        VStack(spacing: 16) {
            // Instructions card
            instructionsCard

            if calibration.profiles.isEmpty {
                emptyProfilesView
            } else {
                profilesList
            }
        }
        .padding(AppSpacing.xl)
    }

    private var instructionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.blue)
                    .font(.title3)
                Text(localization.localized(.howToApplyCalibration))
                    .font(.headline)
                    .fontWeight(.semibold)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Text("1️⃣")
                        .font(AppTypography.body)
                        .fontWeight(.bold)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(localization.localized(.saveCalibrationProfileStep))
                            .font(AppTypography.body)
                            .fontWeight(.medium)
                        Text(localization.localized(.saveCalibrationProfileStepDesc))
                            .font(AppTypography.label)
                            .foregroundColor(.secondary)
                    }
                }

                HStack(alignment: .top, spacing: 8) {
                    Text("2️⃣")
                        .font(AppTypography.body)
                        .fontWeight(.bold)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(localization.localized(.activateProfileHere))
                            .font(AppTypography.body)
                            .fontWeight(.medium)
                        Text(localization.localized(.activateProfileHereDesc))
                            .font(AppTypography.label)
                            .foregroundColor(.secondary)
                    }
                }

                HStack(alignment: .top, spacing: 8) {
                    Text("3️⃣")
                        .font(AppTypography.body)
                        .fontWeight(.bold)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(localization.localized(.enableEQInMainWindow))
                            .font(AppTypography.body)
                            .fontWeight(.medium)
                        Text(localization.localized(.enableEQInMainWindowDesc))
                            .font(AppTypography.label)
                            .foregroundColor(.secondary)
                    }
                }

                Divider()
                    .padding(.vertical, 4)

                HStack {
                    Image(systemName: "lightbulb.fill")
                        .foregroundColor(.yellow)
                        .font(AppTypography.label)
                    Text(localization.localized(.tipCalibrationWorksOnlyWithEQ))
                        .font(AppTypography.label)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(16)
        .background(Color.blue.opacity(0.05))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.blue.opacity(0.2), lineWidth: 1)
        )
    }

    private var emptyProfilesView: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.circle")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            Text(localization.localized(.noCalibrationProfiles))
                .font(.title3)
                .fontWeight(.semibold)
            Text(localization.localized(.noCalibrationProfilesDesc))
                .font(AppTypography.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button(action: {
                selectedTab = .equalLoudness
            }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text(localization.localized(.startCalibrationButton))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }

    private var profilesList: some View {
        VStack(spacing: 12) {
            ForEach(calibration.profiles) { profile in
                profileRow(profile)
            }
        }
    }

    private func profileRow(_ profile: CalibrationProfile) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(profile.name)
                    .font(.headline)
                Text(profile.type.rawValue)
                    .font(AppTypography.label)
                    .foregroundColor(.secondary)
                Text(profile.createdAt, style: .date)
                    .font(AppTypography.labelSmall)
                    .foregroundColor(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                if calibration.activeProfile?.id == profile.id {
                    Text(localization.localized(.active2))
                        .font(AppTypography.label)
                        .fontWeight(.semibold)
                        .foregroundColor(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(4)
                }

                Button(action: {
                    if calibration.activeProfile?.id == profile.id {
                        calibration.deactivateProfile()
                    } else {
                        calibration.activateProfile(profile)
                        // EQ is now enabled automatically, no need for notification
                    }
                }) {
                    HStack {
                        Image(systemName: calibration.activeProfile?.id == profile
                            .id ? "checkmark.circle.fill" : "play.circle.fill")
                        Text(calibration.activeProfile?.id == profile.id ? localization
                            .localized(.active2) : localization.localized(.activate))
                    }
                }
                .buttonStyle(ProfileButtonStyle(isActive: calibration.activeProfile?.id == profile.id))

                Button(action: {
                    profileToDelete = profile
                    showDeleteAlert = true
                }) {
                    Image(systemName: "trash")
                }
                .buttonStyle(BorderedButtonStyle())
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Comparison Section

    private var comparisonSection: some View {
        VStack(spacing: 20) {
            Text(localization.localized(.abProfileComparison))
                .font(.title3)
                .fontWeight(.semibold)

            HStack(spacing: 20) {
                profileSelector(label: localization.localized(.profileA), binding: $profileA)
                profileSelector(label: localization.localized(.profileB), binding: $profileB)
            }

            // Comparison controls
            if profileA != nil || profileB != nil {
                comparisonControls
            }

            // Clean sound comparison
            Divider()
                .padding(.vertical, 10)

            Text(localization.localized(.compareWithCleanSound))
                .font(.headline)
                .foregroundColor(.secondary)

            Text(localization.localized(.compareWithCleanSoundDesc))
                .font(AppTypography.label)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                if isComparingClean {
                    Button(action: {
                        // Bypass EQ for clean sound (keep audio routing active)
                        CoreAudioEngine.shared.setEnabled(false)
                        isComparingClean = true
                        isComparingA = false
                    }) {
                        HStack {
                            Image(systemName: "speaker.wave.2.fill")
                            Text(localization.localized(.cleanSound))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button(action: {
                        // Bypass EQ for clean sound (keep audio routing active)
                        CoreAudioEngine.shared.setEnabled(false)
                        isComparingClean = true
                        isComparingA = false
                    }) {
                        HStack {
                            Image(systemName: "speaker.wave.2")
                            Text("Clean Sound")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(BorderedButtonStyle())
                }

                // Return to last profile
                if isComparingClean {
                    Button(action: {
                        // Re-enable EQ and restore last profile
                        CoreAudioEngine.shared.setEnabled(true)
                        if let profile = isComparingA ? profileA : profileB {
                            calibration.activateProfile(profile)
                        }
                        isComparingClean = false
                    }) {
                        HStack {
                            Image(systemName: "arrow.uturn.backward")
                            Text("Back to Profile")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(AppSpacing.xl)
    }

    private func profileSelector(label: String, binding: Binding<CalibrationProfile?>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(AppTypography.body)
                .foregroundColor(.secondary)

            Picker("", selection: binding) {
                Text("None").tag(nil as CalibrationProfile?)
                ForEach(calibration.profiles) { profile in
                    Text(profile.name).tag(profile as CalibrationProfile?)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity)
        }
    }

    private var comparisonControls: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                if isComparingA {
                    Button(action: {
                        isComparingA = true
                        if let profile = profileA {
                            calibration.activateProfile(profile)
                        }
                    }) {
                        Text("Listen to A")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button(action: {
                        isComparingA = true
                        if let profile = profileA {
                            calibration.activateProfile(profile)
                        }
                    }) {
                        Text("Listen to A")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(BorderedButtonStyle())
                }

                if !isComparingA {
                    Button(action: {
                        isComparingA = false
                        if let profile = profileB {
                            calibration.activateProfile(profile)
                        }
                    }) {
                        Text("Listen to B")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button(action: {
                        isComparingA = false
                        if let profile = profileB {
                            calibration.activateProfile(profile)
                        }
                    }) {
                        Text("Listen to B")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(BorderedButtonStyle())
                }
            }
        }
        .padding(20)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }

    // MARK: - New Profile Sheet

    private var newProfileSheet: some View {
        VStack(spacing: 20) {
            Text("Save Calibration Profile")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 8) {
                Text("Profile Name")
                    .font(AppTypography.body)
                    .foregroundColor(.secondary)
                TextField("e.g., My Headphones", text: $profileName)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Notes (Optional)")
                    .font(AppTypography.body)
                    .foregroundColor(.secondary)
                TextField("e.g., Calibrated for evening listening", text: $profileNotes)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 12) {
                Button("Cancel") {
                    showNewProfileSheet = false
                    profileName = ""
                    profileNotes = ""
                }
                .buttonStyle(BorderedButtonStyle())

                Button("Save") {
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

    private func startCalibration() {
        // Don't change isReferenceStep - let user complete reference setup first
        currentTestBandIndex = 0
        testBands = Array(repeating: 0.0, count: 31)
    }

    private func getGlobalBandIndex(_ localIndex: Int) -> Int {
        if selectedBandCount == .bands10 {
            let indices = calibration.get10BandIndices()
            return indices[localIndex]
        } else {
            return localIndex
        }
    }

    private func saveProfile() {
        let profile = CalibrationProfile(
            name: profileName,
            type: .equalLoudness,
            bands: testBands,
            notes: profileNotes
        )
        calibration.profiles.append(profile)
        calibration.updateProfile(profile)

        showNewProfileSheet = false
        profileName = ""
        profileNotes = ""
        selectedTab = .profiles

        // Reset for next calibration
        isReferenceStep = true
        currentTestBandIndex = 0
        testBands = Array(repeating: 0.0, count: 31)
    }
}

#Preview {
    CalibrationView()
        .frame(width: 1000, height: 750)
}
