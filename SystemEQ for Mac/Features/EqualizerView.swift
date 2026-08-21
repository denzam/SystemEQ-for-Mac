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
        let recommendedPreamp = audioEngine.recommendedPreampGain()
        return VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack(spacing: AppSpacing.lg) {
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    HStack(spacing: AppSpacing.sm) {
                        Text(localization.localized(.preamp))
                            .font(AppTypography.bodySmall)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(audioEngine.formatGain(audioEngine.preampGain))
                            .font(AppTypography.mono)
                            .frame(width: 68, alignment: .trailing)
                    }
                }
                .frame(maxWidth: 280)
                .padding(AppSpacing.sm)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(AppRadius.sm)

                Spacer()

                Button(action: {
                    withAnimation(.spring(response: 0.3)) { _ = audioEngine.restorePresetDefaults() }
                }) {
                    Label(localization.localized(.reset), systemImage: "arrow.counterclockwise")
                        .font(AppTypography.body)
                }
                .buttonStyle(.bordered)
                .disabled(!audioEngine.hasPresetDefaults)

                Button(action: {
                    withAnimation(.spring(response: 0.3)) { audioEngine.applyAutoPreamp() }
                }) {
                    Label(localization.localized(.autoPreamp), systemImage: "wand.and.stars")
                        .font(AppTypography.body)
                }
                .buttonStyle(.borderedProminent)
            }

            if audioEngine.preampGain > recommendedPreamp + 0.05 {
                Text(String(
                    format: localization.localized(.preampSafetyWarning),
                    audioEngine.formatGain(recommendedPreamp)
                ))
                .font(AppTypography.bodySmall)
                .foregroundColor(.orange)
            }

            HStack(spacing: AppSpacing.sm) {
                Text(localization.localized(.outputBoost))
                    .font(AppTypography.bodySmall)
                    .foregroundColor(.secondary)
                Slider(
                    value: Binding(
                        get: { Double(audioEngine.outputBoostGain) },
                        set: { audioEngine.setOutputBoostGain(Float($0)) }
                    ),
                    in: 0...Double(OutputSafetyProcessor.maximumBoostDB),
                    step: 0.5
                )
                Text(audioEngine.formatGain(audioEngine.outputBoostGain))
                    .font(AppTypography.mono)
                    .foregroundColor(audioEngine.outputBoostGain > 3 ? .orange : .primary)
                    .frame(width: 68, alignment: .trailing)
            }

            Text(localization.localized(.outputBoostDescription))
                .font(AppTypography.bodySmall)
                .foregroundColor(.secondary)

            LimiterIndicatorView(
                peakMeter: CoreAudioEngine.shared.peakMeter,
                description: localization.localized(.limiterActivityDescription),
                gainUnit: localization.localized(.dB)
            )
        }
        .padding(AppSpacing.lg)
    }
}

private struct LimiterIndicatorView: View {
    @ObservedObject var peakMeter: PeakMeter
    let description: String
    let gainUnit: String

    var body: some View {
        let reduction = peakMeter.limiterGainReductionDB
        let state = LimiterIndicatorState.state(for: reduction)
        let color: Color = switch state {
        case .normal: .green
        case .mild: .yellow
        case .heavy: .red
        }

        return VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            HStack(spacing: AppSpacing.sm) {
                Circle()
                    .fill(color)
                    .frame(width: 12, height: 12)
                    .shadow(color: color.opacity(state == .normal ? 0.25 : 0.8), radius: 5)
                Text("LIMIT")
                    .font(AppTypography.bodySmall)
                Text(String(format: "GR %+.1f %@", reduction > 0 ? -reduction : 0, gainUnit))
                    .font(AppTypography.mono)
                    .foregroundColor(state == .normal ? .secondary : color)
                Spacer()
            }

            Text(description)
                .font(AppTypography.bodySmall)
                .foregroundColor(.secondary)
        }
    }
}
