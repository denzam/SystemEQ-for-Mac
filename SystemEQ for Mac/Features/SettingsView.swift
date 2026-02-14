import ApplicationServices
import SwiftUI

struct SettingsView: View {
    @StateObject private var localization = LocalizationManager.shared
    @ObservedObject private var glassManager = GlassDesignManager.shared
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true
    @AppStorage("eqStartupMode") private var startupModeRaw: String = EQStartupMode.restoreLastState.rawValue

    private var startupMode: EQStartupMode {
        EQStartupMode(rawValue: startupModeRaw) ?? .restoreLastState
    }

    var body: some View {
        FeatureWindowContainer(
            title: .settingsTitle,
            subtitle: .settingsHeaderSubtitle,
            windowSize: .compact
        ) {
            VStack(alignment: .leading, spacing: 20) {
                // Language Section
                languageSection

                // Glass Design Section
                glassDesignSection

                // EQ Startup Behavior Section
                eqStartupSection

                // General Section
                generalSection

                // EQ Database Section
                databaseSection

                // Accessibility Section
                accessibilitySection

                // Links Section
                linksSection
            }
        }
        .id(localization.currentLanguage)
    }

    // MARK: - Language Section

    private var languageSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(localization.localized(.language))
                .font(AppTypography.heading2)
                .padding(.horizontal, 4)

            Text(localization.localized(.languageDesc))
                .font(AppTypography.bodySmall)
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)

            // Language Cards
            HStack(spacing: 12) {
                ForEach(AppLanguage.allCases) { language in
                    languageCard(language)
                }
            }
        }
        .padding(AppSpacing.xl)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }

    private func languageCard(_ language: AppLanguage) -> some View {
        Button(action: {
            withAnimation {
                localization.currentLanguage = language
            }
        }) {
            VStack(spacing: 12) {
                Text(language.flag)
                    .font(.system(size: 32))

                VStack(spacing: 2) {
                    Text(language.displayName)
                        .font(AppTypography.heading3)
                        .foregroundColor(.primary)
                    Text(language.rawValue.uppercased())
                        .font(AppTypography.labelSmall)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                }

                if localization.currentLanguage == language {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                        .font(AppTypography.heading2)
                } else {
                    Image(systemName: "circle")
                        .foregroundColor(.clear)
                        .font(AppTypography.heading2)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                localization.currentLanguage == language ?
                    Color.blue.opacity(0.1) : Color(NSColor.controlBackgroundColor).opacity(0.5)
            )
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        localization.currentLanguage == language ? Color.blue.opacity(0.5) : Color.gray.opacity(0.1),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Glass Design Section

    private var glassDesignSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Glass Design")
                .font(AppTypography.heading2)
                .padding(.horizontal, 4)

            Text("Customize the appearance of glass UI elements")
                .font(AppTypography.bodySmall)
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)

            VStack(spacing: 12) {
                // Style Picker
                VStack(alignment: .leading, spacing: 8) {
                    Text("Style")
                        .font(AppTypography.body)
                        .foregroundColor(.primary)

                    Picker("", selection: $glassManager.style) {
                        ForEach(GlassStyle.allCases) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // Custom Opacity Toggle
                Toggle(isOn: $glassManager.useCustomOpacity) {
                    HStack {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundColor(.purple)
                            .frame(width: 24)
                        Text("Custom Opacity")
                    }
                }
                .toggleStyle(SwitchToggleStyle(tint: .blue))
                .padding(.vertical, 8)

                // Opacity Slider (shown only when custom opacity is enabled)
                if glassManager.useCustomOpacity {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Opacity")
                                .font(AppTypography.body)
                                .foregroundColor(.primary)
                            Spacer()
                            Text("\(Int(glassManager.customOpacity * 100))%")
                                .font(AppTypography.mono)
                                .foregroundColor(.secondary)
                        }

                        Slider(value: $glassManager.customOpacity, in: 0.3...0.95, step: 0.05)
                            .accentColor(.blue)
                    }
                    .padding(.vertical, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // Preview Card
                VStack(alignment: .leading, spacing: 8) {
                    Text("Preview")
                        .font(AppTypography.bodySmall)
                        .foregroundColor(.secondary)

                    ZStack {
                        // Background pattern to show transparency
                        HStack(spacing: 0) {
                            ForEach(0..<4) { _ in
                                VStack(spacing: 0) {
                                    ForEach(0..<2) { _ in
                                        Rectangle()
                                            .fill(Color.gray.opacity(0.2))
                                            .frame(width: 20, height: 20)
                                        Rectangle()
                                            .fill(Color.gray.opacity(0.1))
                                            .frame(width: 20, height: 20)
                                    }
                                }
                            }
                        }
                        .frame(height: 80)
                        .cornerRadius(8)

                        // Glass preview
                        GlassCard(padding: 12) {
                            HStack {
                                Image(systemName: "sparkles")
                                    .foregroundColor(.blue)
                                Text("Glass Effect Preview")
                                    .font(AppTypography.body)
                            }
                        }
                        .frame(height: 60)
                    }
                    .frame(height: 80)
                }
            }
            .padding(16)
            .background(Color(NSColor.textBackgroundColor).opacity(0.05))
            .cornerRadius(8)
        }
        .padding(AppSpacing.xl)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }

    // MARK: - EQ Startup Section

    private var eqStartupSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(localization.localized(.eqStartupBehaviorTitle))
                .font(AppTypography.heading2)
                .padding(.horizontal, 4)

            Text(localization.localized(.eqStartupBehaviorDesc))
                .font(AppTypography.bodySmall)
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)

            // Startup Mode Cards
            VStack(spacing: 12) {
                ForEach(EQStartupMode.allCases, id: \.self) { mode in
                    startupModeCard(mode)
                }
            }
        }
        .padding(AppSpacing.xl)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }

    private func startupModeCard(_ mode: EQStartupMode) -> some View {
        Button(action: {
            withAnimation {
                startupModeRaw = mode.rawValue
            }
        }) {
            HStack(spacing: 12) {
                Image(systemName: mode.icon)
                    .font(.system(size: 24))
                    .foregroundColor(mode.color == "blue" ? .blue : (mode.color == "orange" ? .orange : .green))
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 4) {
                    Text(mode.displayName)
                        .font(AppTypography.body)
                        .foregroundColor(.primary)
                    Text(mode.description)
                        .font(AppTypography.bodySmall)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                if startupMode == mode {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                        .font(AppTypography.heading2)
                } else {
                    Image(systemName: "circle")
                        .foregroundColor(.gray.opacity(0.3))
                        .font(AppTypography.heading2)
                }
            }
            .padding(12)
            .background(
                startupMode == mode ?
                    Color.blue.opacity(0.1) : Color(NSColor.textBackgroundColor).opacity(0.05)
            )
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(startupMode == mode ? Color.blue.opacity(0.5) : Color.gray.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - General Section

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(localization.localized(.general))
                .font(AppTypography.heading2)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                Toggle(isOn: $launchAtLogin) {
                    HStack {
                        Image(systemName: "power.circle.fill")
                            .foregroundColor(.purple)
                            .frame(width: 24)
                        Text(localization.localized(.launchAtLogin))
                    }
                }
                .toggleStyle(SwitchToggleStyle(tint: .blue))
                .padding()

                Divider()

                Toggle(isOn: $showMenuBarIcon) {
                    HStack {
                        Image(systemName: "menubar.rectangle")
                            .foregroundColor(.blue)
                            .frame(width: 24)
                        Text(localization.localized(.showMenuBarIcon))
                    }
                }
                .toggleStyle(SwitchToggleStyle(tint: .blue))
            }
            .background(Color(NSColor.textBackgroundColor).opacity(0.05))
            .cornerRadius(8)
        }
        .padding(AppSpacing.xl)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }

    // MARK: - Database Section

    @State private var updateCheckResult: EQDatabase.UpdateCheckResult?
    @State private var isCheckingUpdates = false

    private var databaseSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(localization.localized(.eqDatabase))
                .font(AppTypography.heading2)
                .padding(.horizontal, 4)

            let stats = EQDatabase.shared.getDatabaseStats()
            let version = EQDatabase.shared.getVersion()

            VStack(spacing: 12) {
                // Database Info
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "cylinder.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.blue)
                        .frame(width: 32)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(localization.localized(.databaseVersion))
                                .font(AppTypography.body)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(version)
                                .font(AppTypography.mono)
                                .foregroundColor(.primary)
                        }

                        HStack {
                            Text(localization.localized(.databaseHeadphones))
                                .font(AppTypography.body)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(stats.headphones)")
                                .font(AppTypography.mono)
                                .foregroundColor(.primary)
                        }

                        HStack {
                            Text(localization.localized(.databasePresets))
                                .font(AppTypography.body)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(stats.presets)")
                                .font(AppTypography.mono)
                                .foregroundColor(.primary)
                        }

                        HStack {
                            Text(localization.localized(.databaseSize))
                                .font(AppTypography.body)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(stats.sizeMB) MB")
                                .font(AppTypography.mono)
                                .foregroundColor(.primary)
                        }
                    }
                }
                .padding()
                .background(Color(NSColor.textBackgroundColor).opacity(0.05))
                .cornerRadius(8)

                // Update Check Result
                if let result = updateCheckResult {
                    HStack(spacing: 8) {
                        switch result {
                        case .upToDate:
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text(result.message)
                                .font(AppTypography.bodySmall)
                                .foregroundColor(.green)
                        case .updateAvailable:
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundColor(.orange)
                            Text(result.message)
                                .font(AppTypography.bodySmall)
                                .foregroundColor(.orange)
                        case .checkFailed:
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.secondary)
                            Text(result.message)
                                .font(AppTypography.bodySmall)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 4)
                }

                // Buttons
                HStack(spacing: 12) {
                    Button(action: {
                        checkForDatabaseUpdates()
                    }) {
                        HStack {
                            if isCheckingUpdates {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .frame(width: 16, height: 16)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                            Text(localization.localized(.checkForUpdates))
                        }
                    }
                    .disabled(isCheckingUpdates)

                    if case .updateAvailable = updateCheckResult {
                        Button(action: {
                            if let url = URL(string: "\(AppConstants.URLs.projectRepo)/releases") {
                                NSWorkspace.shared.open(url)
                            }
                        }) {
                            HStack {
                                Image(systemName: "arrow.down.to.line")
                                Text(localization.localized(.downloadUpdate))
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .padding(AppSpacing.xl)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }

    private func checkForDatabaseUpdates() {
        isCheckingUpdates = true
        updateCheckResult = nil

        Task {
            let result = await EQDatabase.shared.checkForUpdates()
            await MainActor.run {
                updateCheckResult = result
                isCheckingUpdates = false
            }
        }
    }

    // MARK: - Accessibility Section

    private var accessibilitySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(localization.localized(.accessibility))
                .font(AppTypography.heading2)
                .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.orange)
                        .frame(width: 32)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(localization.localized(.accessibilityDesc))
                            .font(AppTypography.body)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if !AXIsProcessTrusted() {
                            Text(localization.localized(.accessibilityStatusNotGranted))
                                .font(AppTypography.bodySmall)
                                .foregroundColor(.orange)
                                .bold()
                                .padding(.top, 4)
                        } else {
                            Text(localization.localized(.accessibilityStatusGranted))
                                .font(AppTypography.bodySmall)
                                .foregroundColor(.green)
                                .bold()
                                .padding(.top, 4)
                        }
                    }
                }

                HStack {
                    Button(localization.localized(.accessibilityRequestButton)) { requestAccessibilityTrustPrompt() }
                        .font(AppTypography.body)
                    Button(localization.localized(.accessibilityOpenSettingsButton)) {
                        openAccessibilityAccessibilityPane()
                    }
                    .font(AppTypography.body)
                    .buttonStyle(.bordered)
                }
                .padding(.leading, 44)
            }
        }
        .padding(AppSpacing.xl)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }

    // MARK: - Links Section

    private var linksSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(localization.localized(.links))
                .font(AppTypography.heading2)
                .padding(.horizontal, 4)

            VStack(spacing: 12) {
                linkButton(
                    title: localization.localized(.linkGitHub),
                    icon: "chevron.right",
                    url: AppConstants.URLs.projectRepo
                )

                linkButton(
                    title: localization.localized(.linkAutoEQ),
                    icon: "chevron.right",
                    url: AppConstants.URLs.autoEQRepo
                )

                linkButton(
                    title: localization.localized(.linkBlackHole),
                    icon: "chevron.right",
                    url: AppConstants.URLs.blackHoleReleases
                )
            }
        }
        .padding(AppSpacing.xl)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }

    private func linkButton(title: String, icon: String, url: String) -> some View {
        Button(action: {
            if let url = URL(string: url) {
                NSWorkspace.shared.open(url)
            }
        }) {
            HStack {
                Text(title)
                    .font(AppTypography.body)
                Spacer()
                Image(systemName: icon)
                    .font(AppTypography.bodySmall)
                    .foregroundColor(.secondary)
            }
            .padding(AppSpacing.md)
            .background(Color(NSColor.textBackgroundColor).opacity(0.05))
            .cornerRadius(AppRadius.md)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    /// ... Helper methods stay the same ...
    private func openAccessibilityAccessibilityPane() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func openInputMonitoringSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        } else if let fallback = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
            NSWorkspace.shared.open(fallback)
        }
    }

    private func revealAppInFinder() {
        let appURL = Bundle.main.bundleURL
        NSWorkspace.shared.activateFileViewerSelecting([appURL])
    }

    private func requestAccessibilityTrustPrompt() {
        let options: CFDictionary = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
