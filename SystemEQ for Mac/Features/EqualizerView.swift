//
//  EqualizerView.swift
//  SystemEQ for Mac
//
//  Equalizer Window - 10/31 band parametric EQ with real-time controls
//

import Foundation
import SwiftUI

struct EqualizerView: View {
    @StateObject private var audioEngine = AudioEngine.shared
    @StateObject private var localization = LocalizationManager.shared

    var body: some View {
        FeatureWindowContainer(
            title: .equalizerTitle,
            subtitle: .featureEqualizerSubtitle,
            windowSize: .equalizer,
            hasScrollView: false
        ) {
            VStack(spacing: 0) {
                // MARK: - Header with Controls

                headerControlsSection

                Divider()

                // MARK: - EQ Sliders

                ScrollView(.horizontal, showsIndicators: true) {
                    eqSlidersSection
                }

                Divider()

                // MARK: - Footer Controls

                footerSection
            }
        }
        .blurOnLanguageChange()
    }

    // MARK: - Header Controls Section

    @State private var isTogglingEQ = false

    private var headerControlsSection: some View {
        VStack(spacing: AppSpacing.md) {
            HStack {
                Spacer()

                // Global ON/OFF
                Toggle(isOn: Binding(
                    get: { audioEngine.isEnabled },
                    set: { newValue in
                        guard !isTogglingEQ else { return }
                        isTogglingEQ = true
                        audioEngine.setEnabled(newValue)
                        isTogglingEQ = false
                    }
                )) {
                    Text("EQ")
                        .font(AppTypography.heading3)
                }
                .toggleStyle(.switch)
            }

            HStack {
                // Band Mode Selector
                Picker(localization.localized(.bandMode), selection: $audioEngine.bandMode) {
                    Text(localization.localized(.bands10)).tag(EQBandMode.tenBand)
                    Text(localization.localized(.bands31)).tag(EQBandMode.thirtyOneBand)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)

                Spacer()

                // Reset Button
                Button(action: {
                    withAnimation {
                        audioEngine.resetAllBands()
                    }
                }) {
                    Label(localization.localized(.reset), systemImage: "arrow.counterclockwise")
                        .font(AppTypography.body)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.bottom, AppSpacing.md)
    }

    // MARK: - EQ Sliders Section

    private var eqSlidersSection: some View {
        HStack(spacing: AppSpacing.md) {
            ForEach(audioEngine.bands) { band in
                EQBandSliderControl(
                    frequency: band.frequency,
                    gain: binding(for: band.id),
                    formatter: audioEngine
                )
            }
        }
        .padding(AppSpacing.xl)
    }

    private func binding(for bandId: Int) -> Binding<Float> {
        Binding(
            get: {
                guard bandId < audioEngine.bands.count else { return 0.0 }
                return audioEngine.bands[bandId].gain
            },
            set: { newValue in
                audioEngine.updateBandGain(bandId: bandId, gain: newValue)
            }
        )
    }

    // MARK: - Footer Section

    private var footerSection: some View {
        HStack(spacing: AppSpacing.lg) {
            // Preamp info
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(localization.localized(.preamp))
                    .font(AppTypography.bodySmall)
                    .foregroundColor(.secondary)
                Text(audioEngine.formatGain(audioEngine.preampGain))
                    .font(AppTypography.mono)
            }
            .padding(AppSpacing.sm)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(AppRadius.sm)

            Spacer()

            // Test Tone Button (temporarily disabled)
            // Button(action: {
            //     AudioEngine.shared.playTestTone(frequency: 1000, duration: 2.0)
            // }) {
            //     Label(localization.localized(.testTone1k), systemImage: "waveform")
            // }
            // .buttonStyle(.bordered)

            // Auto Preamp Button
            Button(action: {
                withAnimation {
                    audioEngine.applyAutoPreamp()
                }
            }) {
                Label(localization.localized(.autoPreamp), systemImage: "wand.and.stars")
                    .font(AppTypography.body)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(AppSpacing.lg)
    }
}

// MARK: - EQ Band Slider Control

struct EQBandSliderControl: View {
    let frequency: Float
    @Binding var gain: Float
    let formatter: AudioEngine

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            // Gain label
            Text(formatter.formatGain(gain))
                .font(AppTypography.labelSmall)
                .fontWeight(.bold)
                .foregroundColor(gainColor)
                .frame(height: 16)
                .padding(.horizontal, AppSpacing.xs)
                .padding(.vertical, AppSpacing.xxs)
                .background(gainColor.opacity(0.1))
                .cornerRadius(AppRadius.xs)

            // Vertical Slider Container
            ZStack {
                // Center line
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 2, height: 160)

                // Active level indicator (optional visual flair)
                Rectangle()
                    .fill(gainColor.opacity(0.3))
                    .frame(width: 4, height: abs(CGFloat(gain) * 8)) // Approximate scaling
                    .offset(y: CGFloat(-gain * 4)) // Move up/down from center

                Slider(
                    value: $gain,
                    in: -20...20,
                    step: 0.1
                )
                .rotationEffect(.degrees(-90))
                .frame(width: 160) // Width becomes height due to rotation
                .offset(x: 0, y: 0) // Center alignment fix for rotated views often needs tweaking but ZStack helps
            }
            .frame(width: 40, height: 160)

            // Frequency label
            Text(formatter.formatFrequency(frequency))
                .font(AppTypography.labelSmall)
                .foregroundColor(.secondary)
                .frame(height: 16)
                .fixedSize() // Prevent truncation
        }
        .padding(.vertical, AppSpacing.md)
        .padding(.horizontal, AppSpacing.xs)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(AppRadius.md)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }

    private var gainColor: Color {
        if gain == 0 {
            .secondary
        } else if gain > 0 {
            .green
        } else {
            .orange
        }
    }
}
