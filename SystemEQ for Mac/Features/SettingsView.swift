import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @StateObject private var localization = LocalizationManager.shared
    @StateObject private var launchManager = LaunchAtLoginManager()
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true
    @AppStorage("hideDockIcon") private var hideDockIcon = false
    @AppStorage(DevicePresetManager.autoSwitchKey) private var autoSwitchPresetPerDevice = false
    @AppStorage("eqStartupMode") private var startupModeRaw: String = EQStartupMode.restoreLastState.rawValue
    @State private var isExportingDiagnostics = false
    @State private var diagnosticsExportMessage: String?
    @State private var diagnosticReportURL: URL?

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

                diagnosticsSection

                // Links Section
                linksSection
            }
        }
        .onAppear {
            dbStats = EQDatabase.shared.getDatabaseStats()
            dbVersion = EQDatabase.shared.getVersion()
        }
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
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 4)
    }

    private func languageCard(_ language: AppLanguage) -> some View {
        Button(action: {
            localization.setLanguage(language)
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

    @AppStorage("useGlassEffect") private var useGlassEffect = true

    private var glassDesignSection: some View {
        Toggle(isOn: $useGlassEffect) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 20))
                    .foregroundColor(.blue)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 4) {
                    Text(localization.localized(.glassDesignTitle))
                        .font(AppTypography.body)
                        .foregroundColor(.primary)
                    Text(localization.localized(.glassDesignDesc))
                        .font(AppTypography.bodySmall)
                        .foregroundColor(.secondary)
                }
            }
        }
        .toggleStyle(SwitchToggleStyle(tint: .blue))
        .padding(AppSpacing.xl)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 4)
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
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 4)
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
                Toggle(isOn: $launchManager.isEnabled) {
                    HStack {
                        Image(systemName: "power.circle.fill")
                            .foregroundColor(.purple)
                            .frame(width: 24)
                        Text(localization.localized(.launchAtLogin))
                    }
                }
                .toggleStyle(SwitchToggleStyle(tint: .blue))
                .help(localization.localized(.launchAtLoginHelp))
                .padding()
                .onAppear { launchManager.refreshStatus() }
                // Login item can be flipped in System Settings while this window stays open —
                // re-read whenever the user comes back to the app.
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    launchManager.refreshStatus()
                }

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
                .onChange(of: showMenuBarIcon) { visible in
                    // Без іконки в меню схований Dock зробив би застосунок недосяжним
                    if !visible, hideDockIcon {
                        hideDockIcon = false
                    }
                }
                .padding()

                Divider()

                Toggle(isOn: $hideDockIcon) {
                    HStack {
                        Image(systemName: "dock.rectangle")
                            .foregroundColor(.orange)
                            .frame(width: 24)
                        Text(localization.localized(.hideDockIcon))
                    }
                }
                .toggleStyle(SwitchToggleStyle(tint: .blue))
                .help(localization.localized(.hideDockIconHelp))
                .onChange(of: hideDockIcon) { hidden in
                    if hidden {
                        showMenuBarIcon = true
                    }
                    NSApp.setActivationPolicy(hidden ? .accessory : .regular)
                    // Повернути фокус вікну Налаштувань після зміни політики
                    NSApp.activate(ignoringOtherApps: true)
                }
                .padding()

                Divider()

                Toggle(isOn: $autoSwitchPresetPerDevice) {
                    HStack {
                        Image(systemName: "hifispeaker.2")
                            .foregroundColor(.green)
                            .frame(width: 24)
                        Text(localization.localized(.autoSwitchPresetPerDevice))
                    }
                }
                .toggleStyle(SwitchToggleStyle(tint: .blue))
                .help(localization.localized(.autoSwitchPresetPerDeviceHelp))
            }
            .background(Color(NSColor.textBackgroundColor).opacity(0.05))
            .cornerRadius(8)
        }
        .padding(AppSpacing.xl)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 4)
    }

    // MARK: - Database Section

    @State private var updateCheckResult: EQDatabase.UpdateCheckResult?
    @State private var isCheckingUpdates = false
    @State private var dbStats: (headphones: Int, presets: Int, sizeMB: String) = (0, 0, "0.0")
    @State private var dbVersion = ""

    private var databaseSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(localization.localized(.eqDatabase))
                .font(AppTypography.heading2)
                .padding(.horizontal, 4)

            let stats = dbStats
            let version = dbVersion

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
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 4)
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

    private var diagnosticsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(localization.localized(.diagnostics))
                .font(AppTypography.heading2)
                .padding(.horizontal, 4)

            Text(localization.localized(.diagnosticsDesc))
                .font(AppTypography.bodySmall)
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)

            Text(localization.localized(.diagnosticsPrivacy))
                .font(AppTypography.bodySmall)
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)

            HStack(spacing: 12) {
                Button(action: exportDiagnosticReport) {
                    HStack {
                        if isExportingDiagnostics {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 16, height: 16)
                        } else {
                            Image(systemName: "square.and.arrow.up")
                        }
                        Text(localization.localized(.exportDiagnostics))
                    }
                }
                .disabled(isExportingDiagnostics)

                if let diagnosticsExportMessage {
                    Text(diagnosticsExportMessage)
                        .font(AppTypography.bodySmall)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 4)

            if let diagnosticReportURL {
                HStack(spacing: 12) {
                    Button(action: {
                        NSWorkspace.shared.activateFileViewerSelecting([diagnosticReportURL])
                    }) {
                        Label(localization.localized(.revealDiagnostics), systemImage: "folder")
                    }
                    ShareLink(item: diagnosticReportURL) {
                        Label(localization.localized(.shareDiagnostics), systemImage: "square.and.arrow.up")
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .padding(AppSpacing.xl)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 4)
    }

    private func exportDiagnosticReport() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "SystemEQ-diagnostics-\(formatter.string(from: Date())).txt"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        launchManager.refreshStatus()
        diagnosticsExportMessage = nil
        diagnosticReportURL = nil
        isExportingDiagnostics = true
        let snapshot = diagnosticSnapshot()

        DispatchQueue.global(qos: .utility).async {
            do {
                try snapshot.write(to: url, atomically: true, encoding: .utf8)
                DispatchQueue.main.async {
                    diagnosticsExportMessage = localization.localized(.diagnosticsExported)
                    diagnosticReportURL = url
                    isExportingDiagnostics = false
                }
            } catch {
                dlog(
                    "Could not export diagnostic report: \(error.localizedDescription)",
                    level: .warning,
                    category: .general
                )
                DispatchQueue.main.async {
                    diagnosticsExportMessage = localization.localized(.diagnosticsExportFailed)
                    isExportingDiagnostics = false
                }
            }
        }
    }

    private func diagnosticSnapshot() -> String {
        let router = AudioRouter.shared
        let engine = AudioEngine.shared
        let core = CoreAudioEngine.shared
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        let gains = engine.bands.map(\.gain)
        let activeBandCount = gains.filter { abs($0) >= 0.01 }.count
        let maximumGain = gains.max() ?? 0
        let minimumGain = gains.min() ?? 0

        return """
        SystemEQ diagnostic report
        Report format: 2
        Privacy: This report contains only SystemEQ state and generic audio-device capabilities. It contains no audio, media metadata, device names, UIDs, file paths, or automatic upload.
        Created: \(ISO8601DateFormatter().string(from: Date()))
        App version: \(version)
        macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        Launch at login: \(launchManager.isEnabled)
        Startup mode: \(startupMode.rawValue)

        --- EQ state ---
        EQ enabled: \(engine.isEnabled)
        Audio engine running: \(engine.isRunning)
        Band mode: \(engine.bandMode.rawValue)
        Active EQ bands: \(activeBandCount)/\(gains.count)
        Minimum band gain: \(String(format: "%.1f", minimumGain)) dB
        Maximum band gain: \(String(format: "%.1f", maximumGain)) dB
        Preamp: \(engine.preampGain) dB
        Output boost: \(engine.outputBoostGain) dB
        Input peak: \(core.inputPeakLevel)
        Output peak: \(core.outputPeakLevel)

        --- Routing state ---
        \(router.diagnosticSummary())

        --- Core Audio state ---
        \(core.diagnosticSummary())

        --- Recent SystemEQ diagnostic events ---
        \(DiagnosticEventStore.shared.reportText())
        """
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

                linkButton(
                    title: localization.localized(.linkBuyMeACoffee),
                    icon: "cup.and.saucer.fill",
                    url: AppConstants.URLs.buyMeACoffee
                )
            }
        }
        .padding(AppSpacing.xl)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 4)
    }

    private func linkButton(title: String, icon: String, url: String) -> some View {
        HStack(spacing: 0) {
            Button(action: {
                if let url = URL(string: url) {
                    NSWorkspace.shared.open(url)
                }
            }) {
                HStack(alignment: .center, spacing: 6) {
                    Text(title)
                        .font(AppTypography.body)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 16, height: 16)
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
            Spacer()
        }
    }

    private func revealAppInFinder() {
        let appURL = Bundle.main.bundleURL
        NSWorkspace.shared.activateFileViewerSelecting([appURL])
    }
}
