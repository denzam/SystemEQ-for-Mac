import AppKit
import ApplicationServices
import AVFoundation
import Combine
import SwiftUI

public struct WelcomeScreen: View {
    @Binding var isPresented: Bool
    @State private var currentTab = 0
    @EnvironmentObject var audioRouter: AudioRouter
    @EnvironmentObject var localization: LocalizationManager

    public init(isPresented: Binding<Bool>) {
        self._isPresented = isPresented
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Content Area
            ZStack {
                switch currentTab {
                case 0: languageSlide.transition(.opacity)
                case 1: welcomeSlide.transition(.opacity)
                case 2: driverSlide.transition(.opacity)
                case 3: privacySlide.transition(.opacity)
                case 4: accessibilitySlide.transition(.opacity)
                default: EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut, value: currentTab)

            // Footer Navigation
            HStack {
                // Page Indicators
                HStack(spacing: 8) {
                    ForEach(0..<5) { index in
                        Circle()
                            .fill(index == currentTab ? Color.blue : Color.gray.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }

                Spacer()

                // Back Button
                if currentTab > 0 {
                    Button(localization.localized(.back)) {
                        withAnimation { currentTab -= 1 }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)
                }

                // Next / Get Started Button
                if currentTab < 4 {
                    Button(action: {
                        withAnimation { currentTab += 1 }
                    }) {
                        Text(localization.localized(.next))
                            .fontWeight(.semibold)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(action: {
                        completeSetup()
                    }) {
                        Text(localization.localized(.getStarted))
                            .fontWeight(.bold)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 24)
            .padding(.horizontal, 40)
            .background(Color(NSColor.windowBackgroundColor))
            .overlay(Rectangle().frame(height: 1).foregroundColor(Color.gray.opacity(0.1)), alignment: .top)
        }
        .frame(width: 600, height: 500)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Slides

    private var languageSlide: some View {
        VStack(spacing: 30) {
            Image(systemName: "globe")
                .font(.system(size: 80))
                .foregroundColor(.blue)
                .padding(.top, 40)

            Text(localization.localized(.chooseLanguage))
                .font(.system(size: 32, weight: .bold))

            VStack(spacing: 16) {
                ForEach(AppLanguage.allCases) { lang in
                    Button(action: {
                        localization.setLanguage(lang)
                    }) {
                        HStack {
                            Text(lang.flag).font(.title)
                            Text(lang.displayName).font(.title3)
                            Spacer()
                            if localization.currentLanguage == lang {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.1)))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(localization.currentLanguage == lang ? Color.blue : Color.clear, lineWidth: 2)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 60)

            Spacer()
        }
    }

    private var welcomeSlide: some View {
        VStack(spacing: 24) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.blue)
                .padding(.top, 40)

            VStack(spacing: 12) {
                Text(localization.localized(.welcomeTitle))
                    .font(.system(size: 32, weight: .bold))
                    .multilineTextAlignment(.center)

                Text(localization.localized(.welcomeSubtitle))
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Text(localization.localized(.welcomeDesc))
                .multilineTextAlignment(.center)
                .font(.body)
                .foregroundColor(.secondary)
                .padding(.horizontal, 40)

            Spacer()
        }
    }

    private var driverSlide: some View {
        VStack(spacing: 24) {
            Image(systemName: "cable.connector.horizontal")
                .font(.system(size: 60))
                .foregroundColor(.orange)
                .padding(.top, 40)

            Text(localization.localized(.driverTitle))
                .font(.title)
                .bold()

            VStack(spacing: 16) {
                Text(localization.localized(.driverDesc))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                if audioRouter.blackHoleDetected {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(localization.localized(.driverFound))
                            .fontWeight(.medium)
                    }
                    .padding()
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)
                } else {
                    VStack(spacing: 12) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text(localization.localized(.driverNotFound))
                        }

                        Button(localization.localized(.downloadDriver)) {
                            BlackHoleInstaller.openDirectDownload()
                        }
                        .buttonStyle(.borderedProminent)

                        Text(localization.localized(.driverInstructions))
                            .font(AppTypography.label)
                            .foregroundColor(.secondary)

                        Button(localization.localized(.refresh)) {
                            Task {
                                await audioRouter.refreshDevices()
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.blue)
                    }
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
                }
            }

            Spacer()
        }
    }

    private var privacySlide: some View {
        VStack(spacing: 24) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 60))
                .foregroundColor(.purple)
                .padding(.top, 40)

            Text(localization.localized(.privacyTitle))
                .font(.title)
                .bold()

            VStack(spacing: 16) {
                Text(localization.localized(.privacyDesc))
                    .multilineTextAlignment(.center)
                    .font(.headline)

                VStack(alignment: .leading, spacing: 10) {
                    Label(localization.localized(.privacyPoint1), systemImage: "cable.connector")
                    Label(localization.localized(.privacyPoint2), systemImage: "music.note")
                    Label(localization.localized(.privacyPoint3), systemImage: "mic.slash.fill")
                        .foregroundColor(.blue)
                    Label(localization.localized(.privacyPoint4), systemImage: "lock.shield.fill")
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)

                if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(localization.localized(.permissionGranted))
                    }
                    .padding()
                } else {
                    Button(localization.localized(.grantPermission)) {
                        AVCaptureDevice.requestAccess(for: .audio) { _ in }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .padding(.horizontal, 40)

            Spacer()
        }
    }

    private var accessibilitySlide: some View {
        VStack(spacing: 24) {
            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue)
                .padding(.top, 40)

            Text(localization.localized(.accessTitle))
                .font(.title)
                .bold()

            VStack(spacing: 16) {
                Text(localization.localized(.accessDesc))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                Text(localization.localized(.accessExplanation))
                    .multilineTextAlignment(.center)
                    .font(AppTypography.label)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 40)

                if AXIsProcessTrusted() {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(localization.localized(.accessEnabled))
                    }
                    .padding()
                } else {
                    Button(localization.localized(.grantAccess)) {
                        let options: CFDictionary =
                            [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                        AXIsProcessTrustedWithOptions(options)
                    }
                    .buttonStyle(.borderedProminent)

                    Text(localization.localized(.accessInstructions))
                        .font(AppTypography.labelSmall)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
    }

    private func completeSetup() {
        isPresented = false
        // Save that we've shown the welcome screen
        UserDefaults.standard.set(true, forKey: "hasCompletedSetup")
    }
}
