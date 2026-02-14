//
//  MenuBarExtraView.swift
//  SystemEQ for Mac
//
//  Minimalist menu bar with essential controls
//

import Foundation
import SwiftUI

struct MenuBarExtraView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var localization: LocalizationManager
    @EnvironmentObject private var audioRouter: AudioRouter
    @EnvironmentObject private var audioEngine: AudioEngine
    @EnvironmentObject private var coreEngine: CoreAudioEngine

    @AppStorage("eqEnabled") private var eqEnabled: Bool = true
    @AppStorage("outputGain") private var storedOutputGain: Double = 0
    @AppStorage("activePresetName") private var activePresetName: String = ""
    @State private var sliderGain: Double = 0
    @State private var refreshID = UUID()
    @State private var hoveredButton: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // MARK: - Status indicator

            statusIndicator

            Divider()

            // MARK: - EQ Toggle + Mute

            controlsRow

            // MARK: - Master Gain

            gainSlider

            // MARK: - Active Preset

            if !activePresetName.isEmpty {
                activePresetRow
            }

            Divider()

            // MARK: - Quick Actions

            quickActions
        }
        .padding(12)
        .frame(width: 260)
        .onAppear {
            sliderGain = storedOutputGain
        }
        .onReceive(NotificationCenter.default.publisher(for: .languageChanged)) { _ in
            refreshID = UUID()
        }
        .id(refreshID)
    }

    // MARK: - Status Indicator

    private var statusIndicator: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            Text(statusText)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primary)

            Spacer()

            if !audioRouter.blackHoleDetected {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.system(size: 11))
                    .help("BlackHole not detected")
            }
        }
    }

    private var statusColor: Color {
        if !audioEngine.isEnabled {
            .gray
        } else if coreEngine.isRunning, audioRouter.isRoutingActive {
            .green
        } else {
            .orange
        }
    }

    private var statusText: String {
        if !audioEngine.isEnabled {
            localization.localized(.menuEQDisabled)
        } else if coreEngine.isRunning, audioRouter.isRoutingActive {
            localization.localized(.menuEQEnabled)
        } else {
            localization.localized(.menuWaitingForRouting)
        }
    }

    // MARK: - Controls Row (EQ Toggle + Mute)

    private var controlsRow: some View {
        HStack(spacing: 12) {
            Toggle(isOn: Binding(
                get: { audioEngine.isEnabled },
                set: { newValue in
                    eqEnabled = newValue
                    audioEngine.setEnabled(newValue)
                    coreEngine.setEnabled(newValue)
                    NotificationCenter.default.post(
                        name: NSNotification.Name(newValue ? "EnableEQRouting" : "DisableEQRouting"),
                        object: nil
                    )
                }
            )) {
                HStack(spacing: 6) {
                    Image(systemName: "waveform")
                        .font(.system(size: 12))
                    Text("EQ")
                        .font(.system(size: 13))
                }
            }
            .toggleStyle(SwitchToggleStyle(tint: .blue))

            Spacer()

            // Mute button
            Button(action: { coreEngine.setMuted(!coreEngine.muted) }) {
                Image(systemName: coreEngine.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 14))
                    .foregroundColor(coreEngine.muted ? .orange : .primary)
                    .frame(width: 28, height: 28)
                    .background(hoveredButton == "mute" ? Color.primary.opacity(0.1) : Color.clear)
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                hoveredButton = hovering ? "mute" : nil
            }
            .help(coreEngine.muted ? localization.localized(.menuUnmute) : localization.localized(.menuMute))
        }
    }

    // MARK: - Active Preset

    private var activePresetRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "waveform.badge.checkmark")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Text(activePresetName)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    // MARK: - Gain Slider

    private var gainSlider: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(localization.localized(.menuMainGain))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Spacer()
                Text(String(format: "%+.1f dB", sliderGain))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            Slider(value: $sliderGain, in: -12...12, step: 0.5)
                .disabled(!audioEngine.isEnabled)
                .onChange(of: sliderGain) { newValue in
                    storedOutputGain = newValue
                    coreEngine.setMainGainDb(Float(newValue))
                }
        }
    }

    // MARK: - Quick Actions

    private var quickActions: some View {
        VStack(spacing: 2) {
            menuButton(
                id: "open",
                icon: "slider.horizontal.3",
                title: localization.localized(.menuMain),
                shortcut: "⌘O"
            ) {
                openWindow(id: "main")
            }

            menuButton(
                id: "quit",
                icon: "power",
                title: localization.localized(.menuQuit),
                shortcut: "⌘Q"
            ) {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    // MARK: - Menu Button with Hover

    private func menuButton(
        id: String,
        icon: String,
        title: String,
        shortcut: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .frame(width: 16)
                Text(title)
                Spacer()
                Text(shortcut)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .font(.system(size: 13))
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hoveredButton == id ? Color.primary.opacity(0.1) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredButton = hovering ? id : nil
        }
    }
}
