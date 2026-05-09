//
//  EqualizerView.swift
//  SystemEQ for Mac
//

import Foundation
import SwiftUI

// MARK: - Main View

struct EqualizerView: View {
    @StateObject private var audioEngine = AudioEngine.shared
    @StateObject private var localization = LocalizationManager.shared
    @State private var isTogglingEQ = false

    var body: some View {
        FeatureWindowContainer(
            title: .equalizerTitle,
            subtitle: .featureEqualizerSubtitle,
            windowSize: .equalizer,
            hasScrollView: false
        ) {
            VStack(spacing: 0) {
                headerControlsSection
                Divider()
                eqGraphSection
                Divider()
                footerSection
            }
        }
        .blurOnLanguageChange()
    }

    // MARK: - Header

    private var headerControlsSection: some View {
        VStack(spacing: AppSpacing.md) {
            HStack {
                Picker(localization.localized(.bandMode), selection: $audioEngine.bandMode) {
                    Text(localization.localized(.bands10)).tag(EQBandMode.tenBand)
                    Text(localization.localized(.bands31)).tag(EQBandMode.thirtyOneBand)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)

                Spacer()

                Toggle(isOn: Binding(
                    get: { audioEngine.isEnabled },
                    set: { newValue in
                        guard !isTogglingEQ else { return }
                        isTogglingEQ = true
                        audioEngine.setEnabled(newValue)
                        isTogglingEQ = false
                    }
                )) {
                    Text("EQ").font(AppTypography.heading3)
                }
                .toggleStyle(.switch)
            }
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.md)
    }

    // MARK: - EQ Graph

    private var eqGraphSection: some View {
        EQGraphView(
            bands: audioEngine.bands,
            gainBinding: { id in binding(for: id) }
        )
    }

    private func binding(for bandId: Int) -> Binding<Float> {
        Binding(
            get: {
                guard bandId < audioEngine.bands.count else { return 0.0 }
                return audioEngine.bands[bandId].gain
            },
            set: { audioEngine.updateBandGain(bandId: bandId, gain: $0) }
        )
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack(spacing: AppSpacing.lg) {
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
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

            Button(action: {
                withAnimation(.spring(response: 0.3)) { audioEngine.resetAllBands() }
            }) {
                Label(localization.localized(.reset), systemImage: "arrow.counterclockwise")
                    .font(AppTypography.body)
            }
            .buttonStyle(.bordered)

            Button(action: {
                withAnimation(.spring(response: 0.3)) { audioEngine.applyAutoPreamp() }
            }) {
                Label(localization.localized(.autoPreamp), systemImage: "wand.and.stars")
                    .font(AppTypography.body)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(AppSpacing.lg)
    }
}
