//
//  PersonalizedCalibrationView.swift
//  SystemEQ for Mac
//
//  UI for Personalized Hearing Profile calibration
//  Premium feature with adaptive hearing test
//

import AVFoundation
import Combine
import SwiftUI

struct PersonalizedCalibrationView: View {
    @StateObject private var profileManager = PersonalizedProfileManager.shared
    @StateObject private var calibrationEngine = CalibrationEngine.shared
    @EnvironmentObject private var localization: LocalizationManager

    @State private var selectedTestType: TestType = .standard
    @State private var isTestRunning = false
    @State private var currentFrequency: Double = 1000
    @State private var currentLevel: Float = -20
    @State private var userResponse: Float = 0
    @State private var testResults: [(frequency: Double, level: Float, userHeard: Bool)] = []
    @State private var refreshID = UUID() // For forcing view refresh
    @State private var testProgress: Double = 0
    @State private var measurements: [PersonalizedHearingProfile.FrequencyResponsePoint] = []
    @State private var showingUnlockPrompt = false
    @State private var newProfileName = ""
    @State private var showingNamePrompt = false
    @State private var testStartDate: Date?

    enum TestType: CaseIterable {
        case quick
        case standard
        case extended

        func localizedName(_ localization: LocalizationManager) -> String {
            switch self {
            case .quick: localization.localized(.quickTest)
            case .standard: localization.localized(.standardTest)
            case .extended: localization.localized(.extendedTest)
            }
        }

        var config: PersonalizedTestConfig {
            switch self {
            case .quick:
                .quick
            case .standard:
                .standard
            case .extended:
                PersonalizedTestConfig(
                    frequencies: Array(stride(from: 20, through: 20000, by: 0.5).map(\.self)),
                    testLevels: [-30, -20, -10, 0],
                    adaptiveMode: true,
                    quickTest: false
                )
            }
        }

        func localizedDescription(_ localization: LocalizationManager) -> String {
            switch self {
            case .quick:
                localization.localized(.quickTestDesc)
            case .standard:
                localization.localized(.standardTestDesc)
            case .extended:
                localization.localized(.extendedTestDesc)
            }
        }
    }

    var body: some View {
        FeatureWindowContainer(
            title: .personalizedHearingProfile,
            subtitle: .personalizedDesc,
            windowSize: .large,
            hasScrollView: true
        ) {
            VStack(spacing: 20) {
                // Premium badge in header
                if profileManager.isUnlocked {
                    HStack {
                        Spacer()
                        Text(localization.localized(.premium))
                            .font(AppTypography.bodySmall)
                            .padding(.horizontal, AppSpacing.sm)
                            .padding(.vertical, AppSpacing.xs)
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(4)
                    }
                    .padding(.bottom, AppSpacing.sm)
                }

                if !profileManager.isUnlocked {
                    premiumLockedView
                } else {
                    mainContentView
                }
            }
        }
        .sheet(isPresented: $showingUnlockPrompt) {
            UnlockPromptView(isPresented: $showingUnlockPrompt)
        }
        .sheet(isPresented: $showingNamePrompt) {
            NamePromptView(name: $newProfileName, isPresented: $showingNamePrompt) {
                startTest()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .languageChanged)) { _ in
            // CrossfadeText handles blur animation automatically
        }
        .id(refreshID)
    }

    private var premiumLockedView: some View {
        VStack(spacing: 30) {
            Image(systemName: "lock.shield")
                .font(.system(size: 60))
                .foregroundColor(.accentColor)

            VStack(spacing: 12) {
                Text(localization.localized(.unlockPersonalizedCalibration))
                    .font(AppTypography.heading1)

                Text(localization.localized(.personalizedSubtitle))
                    .font(AppTypography.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 12) {
                FeatureRow(
                    icon: "person.crop.circle",
                    title: localization.localized(.personalized),
                    description: localization.localized(.adaptsToHearing)
                )
                FeatureRow(
                    icon: "chart.line.uptrend.xyaxis",
                    title: localization.localized(.highPrecision),
                    description: localization.localized(.extendedFrequencyRange)
                )
                FeatureRow(
                    icon: "brain",
                    title: localization.localized(.smartLearning),
                    description: localization.localized(.improvesOverTime)
                )
                FeatureRow(
                    icon: "headphones",
                    title: localization.localized(.universal),
                    description: localization.localized(.worksWithAnyHeadphones)
                )
            }

            Button(action: { showingUnlockPrompt = true }) {
                HStack {
                    Image(systemName: "crown.fill")
                    Text(localization.localized(.unlockForPrice))
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.accentColor)
                .cornerRadius(10)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var mainContentView: some View {
        VStack(spacing: 20) {
            // Test Type Selection
            if !isTestRunning {
                testTypeSelection
            }

            // Profile Management
            if !isTestRunning, !profileManager.profiles.isEmpty {
                profileSelection
            }

            // Test Interface
            if isTestRunning {
                testInterface
            }

            // Start Button
            if !isTestRunning {
                startTestButton
            }

            // Progress
            if isTestRunning {
                progressBar
            }
        }
    }

    private var testTypeSelection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(localization.localized(.selectTestType))
                .font(.headline)

            HStack(spacing: 12) {
                ForEach(TestType.allCases, id: \.self) { type in
                    TestTypeCard(
                        type: type,
                        isSelected: selectedTestType == type
                    ) {
                        selectedTestType = type
                    }
                }
            }
        }
    }

    private var profileSelection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(localization.localized(.yourProfiles))
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(profileManager.profiles) { profile in
                        ProfileCard(profile: profile) {
                            profileManager.activeProfile = profile
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private var testInterface: some View {
        VStack(spacing: 20) {
            // Frequency Display
            VStack(spacing: 8) {
                Text("\(Int(currentFrequency)) \(localization.localized(.frequencyHz))")
                    .font(.system(size: 48, weight: .bold, design: .monospaced))

                Text("\(String(format: "%.1f", currentLevel)) dB")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }

            // Response Slider
            VStack(spacing: 12) {
                Text(localization.localized(.adjustUntilEquallyLoud))
                    .font(.caption)
                    .foregroundColor(.secondary)

                Slider(value: $userResponse, in: -30...30, step: 0.5)
                    .frame(height: 20)

                HStack {
                    Text(localization.localized(.quieter))
                        .font(.caption2)
                    Spacer()
                    Text(localization.localized(.louder))
                        .font(.caption2)
                }
                .foregroundColor(.secondary)
            }

            // Control Buttons
            HStack(spacing: 12) {
                Button(localization.localized(.tooQuiet)) {
                    recordResponse(-5)
                }
                .buttonStyle(SecondaryButtonStyle())

                Button(localization.localized(.justRight)) {
                    recordResponse(0)
                }
                .buttonStyle(PrimaryButtonStyle())

                Button(localization.localized(.tooLoud)) {
                    recordResponse(5)
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
        .frame(height: 250)
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }

    private var startTestButton: some View {
        Button(action: { showingNamePrompt = true }) {
            HStack {
                Image(systemName: "play.circle.fill")
                Text(localization.localized(.startCalibration))
            }
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.accentColor)
            .cornerRadius(10)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var progressBar: some View {
        VStack(spacing: 8) {
            ProgressView(value: testProgress, total: 1.0)
                .progressViewStyle(LinearProgressViewStyle(tint: .accentColor))

            Text("\(Int(testProgress * 100))% \(localization.localized(.complete).lowercased())")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Methods

    private func startTest() {
        guard !newProfileName.isEmpty else { return }

        isTestRunning = true
        testProgress = 0
        measurements = []
        testStartDate = Date()

        // Start with first frequency
        currentFrequency = selectedTestType.config.frequencies.first ?? 1000
        currentLevel = selectedTestType.config.testLevels.first ?? -20

        calibrationEngine.playTestToneAtLevel(frequency: currentFrequency, level: currentLevel)
    }

    private func recordResponse(_ adjustment: Float) {
        let correction = userResponse + adjustment

        // Save measurement
        let point = PersonalizedHearingProfile.FrequencyResponsePoint(
            frequency: currentFrequency,
            gainCorrection: correction,
            confidence: 0.8,
            measurementCount: 1
        )
        measurements.append(point)

        // Move to next frequency
        if let currentIndex = selectedTestType.config.frequencies.firstIndex(of: currentFrequency),
           currentIndex < selectedTestType.config.frequencies.count - 1 {
            currentFrequency = selectedTestType.config.frequencies[currentIndex + 1]
            calibrationEngine.playTestToneAtLevel(frequency: currentFrequency, level: currentLevel)
            userResponse = 0
        } else {
            // Test complete
            completeTest()
        }

        // Update progress
        testProgress = Double(measurements.count) / Double(selectedTestType.config.frequencies.count)
    }

    private func completeTest() {
        isTestRunning = false
        calibrationEngine.stopTestTone()

        // Create profile
        let profile = PersonalizedHearingProfile(
            name: newProfileName,
            frequencyPoints: measurements,
            headphoneModel: nil, // Headphone model can be added later from preset selection
            testDuration: Date().timeIntervalSince(testStartDate ?? Date())
        )

        profileManager.saveProfile(profile)
        profileManager.activeProfile = profile
    }
}

struct TestTypeCard: View {
    let type: PersonalizedCalibrationView.TestType
    let isSelected: Bool
    let action: () -> Void
    @ObservedObject private var localization = LocalizationManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(type.localizedName(localization))
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)

            Text(type.localizedDescription(localization))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color(NSColor.controlBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .onTapGesture(perform: action)
    }
}

struct ProfileCard: View {
    let profile: PersonalizedHearingProfile
    let action: () -> Void
    @ObservedObject private var localization = LocalizationManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(profile.name)
                .font(.subheadline)
                .fontWeight(.medium)

            HStack {
                Text(profile.qualityDescription)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(qualityColor.opacity(0.2))
                    .foregroundColor(qualityColor)
                    .cornerRadius(4)

                Spacer()

                Text("\(profile.trainingSessions) \(localization.localized(.sessions).lowercased())")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(width: 180)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .onTapGesture(perform: action)
    }

    private var qualityColor: Color {
        switch profile.confidenceScore {
        case 0.9...1.0:
            .green
        case 0.7..<0.9:
            .orange
        default:
            .red
        }
    }
}

struct UnlockPromptView: View {
    @Binding var isPresented: Bool
    @ObservedObject private var localization = LocalizationManager.shared

    var body: some View {
        VStack(spacing: 30) {
            Text(localization.localized(.unlockPersonalizedHearingProfile))
                .font(.title2)
                .fontWeight(.semibold)

            Text(localization.localized(.professionalGradeCalibration))
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 20) {
                Text(localization.localized(.price))
                    .font(.system(size: 48, weight: .bold, design: .rounded))

                Text(localization.localized(.oneTimePurchase))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 12) {
                Button(localization.localized(.cancel)) {
                    isPresented = false
                }
                .buttonStyle(SecondaryButtonStyle())

                Button(localization.localized(.unlock)) {
                    PersonalizedProfileManager.shared.unlockFeature()
                    isPresented = false
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(40)
        .frame(width: 400)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct NamePromptView: View {
    @Binding var name: String
    @Binding var isPresented: Bool
    let onConfirm: () -> Void
    @ObservedObject private var localization = LocalizationManager.shared

    var body: some View {
        VStack(spacing: 20) {
            Text(localization.localized(.nameYourProfile))
                .font(.headline)

            TextField(localization.localized(.exampleProfileName), text: $name)
                .textFieldStyle(RoundedBorderTextFieldStyle())

            HStack(spacing: 12) {
                Button(localization.localized(.cancel)) {
                    isPresented = false
                }
                .buttonStyle(SecondaryButtonStyle())

                Button(localization.localized(.start)) {
                    isPresented = false
                    onConfirm()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(name.isEmpty)
            }
        }
        .padding(30)
        .frame(width: 350)
        .background(Color(NSColor.windowBackgroundColor))
    }
}
