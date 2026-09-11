import AppKit
import AVFoundation
import CoreAudio
import Foundation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Favorites Model

struct FavoritePreset: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let source: String?
    let target: String?
    let path: String
    let timestamp: Date
    var rawText: String? // Повний вміст .txt для custom-імпортованих пресетів
    var preamp: Double?
}

struct LimiterIndicatorView: View {
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

            if !description.isEmpty {
                Text(description)
                    .font(AppTypography.bodySmall)
                    .foregroundColor(.secondary)
            }
        }
    }
}

private func autoEQPanel(@ViewBuilder content: () -> some View) -> some View {
    VStack(alignment: .leading, spacing: AppSpacing.md) {
        content()
    }
    .padding(AppSpacing.lg)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(NSColor.controlBackgroundColor).opacity(0.42))
    .overlay {
        RoundedRectangle(cornerRadius: AppRadius.lg)
            .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
    }
    .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
}

struct AutoEQView: View {
    static let databaseCandidatePrefix = "database:"
    private let databaseService = AutoEQDatabaseService(database: .shared)
    @StateObject private var legacyRepository = AutoEQLegacyRepository()

    enum BandMode: String, CaseIterable, Identifiable {
        case ten = "10"
        case thirtyOne = "31"

        var id: String {
            rawValue
        }

        init(audioEngineMode: EQBandMode) {
            self = audioEngineMode == .tenBand ? .ten : .thirtyOne
        }

        var audioEngineMode: EQBandMode {
            self == .ten ? .tenBand : .thirtyOneBand
        }
    }

    // MARK: - Localization

    @StateObject private var localization = LocalizationManager.shared

    // MARK: - Audio Engine (ObservableObject для реактивності)

    @StateObject private var audioEngine = AudioEngine.shared
    @State private var isTogglingEQ = false

    // MARK: - Active Preset Tracking

    @State private var activePresetName: String?
    @State private var activePresetSource: String?
    @State private var activePresetTarget: String? // JM-1, Harman, etc.
    @State private var activePresetPath: String? // шлях у БД, коли пресет прийшов з пошуку/обраного

    // Відновлення UI при відкритті вікна ставить parsed, і вотчер .task(id: parsed)
    // застосував би пресет повторно поверх уже відновленого рушія — гасимо один раз.
    @State private var suppressNextAutoApply = false

    @State private var bassBoost: Double = 0
    @State private var rawText: String = ""

    /// Bass Boost low-shelf фільтр: піднімає тільки низькі частоти
    /// Частота зрізу: 200 Hz, slope: 12 dB/octave
    private func bassBoostForFrequency(_ freq: Double) -> Double {
        BassBoostCurve.gain(at: freq, amount: bassBoost)
    }

    @State private var parsed: [ParsedBand] = []
    @State private var parsed10: [ParsedBand] = []
    @State private var parsed31: [ParsedBand] = []
    @State private var bandMode: BandMode = .ten
    @State private var mapped: [MappedBand] = []
    @State private var searchText: String = ""
    @State private var isSearching: Bool = false
    @State private var candidates: [SearchCandidate] = []
    @State private var searchError: String?
    @State private var offlineIndex: [OfflineIndexEntry] = []
    @State private var isBuildingIndex: Bool = false
    @State private var indexStatusRaw: IndexStatusKind?

    private enum IndexStatusKind: Equatable {
        case updated(count: Int, timestamp: TimeInterval)
        case updatedNow(count: Int)
        case updating
        case building
        case error(String)
        case raw(String)
    }

    private var indexStatus: String? {
        guard let kind = indexStatusRaw else { return nil }
        switch kind {
        case let .updated(count, ts):
            return String(format: localization.localized(.indexUpdated), count, formatIndexAge(ts))
        case let .updatedNow(count):
            return String(format: localization.localized(.indexUpdated), count, localization.localized(.indexToday))
        case .updating:
            return localization.localized(.updatingIndex)
        case .building:
            return localization.localized(.buildingIndex)
        case let .error(s):
            return s
        case let .raw(s):
            return s
        }
    }

    @State private var preampDB: Double?
    @State private var preampDB10: Double? // Preamp для 10-band
    @State private var preampDB31: Double? // Preamp для 31-band
    @State private var targetProfile: String = "JM-1 with Harman filters"
    private let targetProfileVariants: [String] = [
        "JM-1 with Harman filters",
        "JM1 with Harman filters",
        "JM-1 Harman",
        "JM1 Harman",
        "JM-1",
        "JM1"
    ]
    @State private var indexTruncated: Bool = false

    // Optimization: Caching and request management
    @State private var readmeCache: [String: String] = [:]
    @State private var activeRequests: Set<String> = []
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var applyEQDebounceTask: Task<Void, Never>? // Debounce для applyToAudioEngine
    @State private var draggingBandIndex: Int?
    @State private var hoveredBandIndex: Int?

    /// ✅ Import cache: prevents re-importing same preset and getting different values
    struct ImportCacheEntry {
        let parsed10: [ParsedBand]
        let parsed31: [ParsedBand]
        let preampDB10: Double? // Preamp для 10-band
        let preampDB31: Double? // Preamp для 31-band
        let name: String
        let source: String?
        let target: String?
        let timestamp: Date
    }

    @State private var importCache: [String: ImportCacheEntry] = [:]

    // MARK: - Favorites State

    @AppStorage("autoEQFavorites") private var favoritesData: Data = .init()
    @State private var favorites: [FavoritePreset] = []
    @State private var showFavorites: Bool = false

    // Останній імпортований custom-пресет (легасі-ключі, лишаються для міграції)
    @AppStorage("lastCustomPresetText") private var lastCustomPresetText: String = ""
    @AppStorage("lastCustomPresetName") private var lastCustomPresetName: String = ""

    // Останній ЗАСТОСОВАНИЙ пресет будь-якого походження (custom або БД) —
    // саме він відновлюється в UI при відкритті вікна
    @AppStorage("lastAppliedPresetJSON") private var lastAppliedPresetJSON: String = ""

    private let tenCenters: [Double] = [31.5, 63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    private let thirtyOneCenters: [Double] = [
        20,
        25,
        31.5,
        40,
        50,
        63,
        80,
        100,
        125,
        160,
        200,
        250,
        315,
        400,
        500,
        630,
        800,
        1000,
        1250,
        1600,
        2000,
        2500,
        3150,
        4000,
        5000,
        6300,
        8000,
        10000,
        12500,
        16000,
        20000
    ]

    var body: some View {
        FeatureWindowContainer(
            title: .autoEQTitle,
            subtitle: .featureAutoEQSubtitle,
            windowSize: .large
        ) {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                activePresetSection
                presetLibrarySection

                if !normalizedQuery.isEmpty {
                    searchResultsSection
                }

                if !parsed.isEmpty {
                    mappedPreviewSection
                } else {
                    manualEQGraphSection
                }

                eqControlsSection
                bassBoostSection
                Spacer()
            }
        }
        .task(id: normalizedQuery) { await searchDebounced() }
        .task(id: parsed) {
            let newMapped = mappedBands()
            await MainActor.run {
                self.mapped = newMapped

                // Debounce: Apply to AudioEngine after 100ms to prevent overload
                applyEQDebounceTask?.cancel()
                applyEQDebounceTask = Task {
                    try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        // Без завантаженого пресета mapped — це самі нулі: авто-застосування
                        // тут означало б стерти відновлений стан рушія плоским EQ.
                        guard !self.parsed.isEmpty, !self.mapped.isEmpty else { return }
                        let suppressed = suppressNextAutoApply
                        suppressNextAutoApply = false
                        if !suppressed, audioEngine.isEnabled {
                            applyToAudioEngine()
                        }
                    }
                }
            }
        }
        .onReceive(audioEngine.$bandMode) { restoredMode in
            syncBandModeFromAudioEngine(restoredMode)
        }
        .onAppear {
            // Defer state changes to next run loop to avoid "Publishing changes from within view updates"
            DispatchQueue.main.async {
                // Load favorites from storage
                loadFavoritesFromStorage()

                // Restore bassBoost from saved preset
                if let saved = PresetPersistence.load() {
                    bassBoost = Double(saved.bassBoost)
                }

                if EQDatabase.shared.isAvailable {
                    let stats = EQDatabase.shared.getDatabaseStats()
                    indexStatusRaw = .raw("\(localization.localized(.databaseHeadphones)): \(stats.headphones)")
                    if let result = legacyRepository.loadOfflineIndex() {
                        offlineIndex = result.entries
                    }
                } else if let result = legacyRepository.loadOfflineIndex() {
                    offlineIndex = result.entries
                    indexStatusRaw = .updated(count: result.entries.count, timestamp: result.lastUpdate)

                    if result.needsUpdate {
                        indexStatusRaw = .updating
                        Task { await buildOrUpdateIndex() }
                    }
                } else if let bundled = legacyRepository.loadBundledOfflineIndex() {
                    offlineIndex = bundled
                    // Оновити індекс в фоні після завантаження з bundle
                    Task { await buildOrUpdateIndex() }
                } else {
                    Task { await buildOrUpdateIndex() }
                }

                restoreLastAppliedPresetUI()
            }
        }
    }

    @ViewBuilder private var activePresetSection: some View {
        if let presetName = activePresetName {
            autoEQPanel {
                HStack(spacing: AppSpacing.md) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .imageScale(.medium)

                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        Text(presetName)
                            .font(AppTypography.heading3)
                            .lineLimit(1)
                            .tooltip(presetName)

                        HStack(spacing: AppSpacing.xs) {
                            if let source = activePresetSource {
                                Text(source)
                            }
                            if let target = activePresetTarget {
                                Text("•")
                                Text(target)
                                    .foregroundStyle(.blue)
                            }
                        }
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if canToggleCurrentFavorite {
                        Button {
                            toggleCurrentFavorite()
                        } label: {
                            Image(systemName: isCurrentPresetFavorite ? "star.fill" : "star")
                                .foregroundStyle(isCurrentPresetFavorite ? .yellow : .secondary)
                        }
                        .buttonStyle(.borderless)
                        .help(isCurrentPresetFavorite
                            ? localization.localized(.removeFromFavorites)
                            : localization.localized(.autoEQSaveToFavorites))
                    }
                }
            }
        }
    }

    private var presetLibrarySection: some View {
        autoEQPanel {
            sectionHeader(
                title: localization.localized(.autoeqPresets),
                systemImage: "headphones",
                help: "\(localization.localized(.quickImportHelp))\n\n\(localization.localized(.autoEQImportFileHelp))"
            )

            HStack(spacing: AppSpacing.sm) {
                TextField(localization.localized(.searchHeadphonesModel), text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
                    .disableAutocorrection(true)

                Button(localization.localized(.autoEQQuickImport)) {
                    importFromDatabase(searchText)
                }
                .buttonStyle(.borderedProminent)
                .disabled(searchText.isEmpty)
                .help(localization.localized(.quickImportHelp))

                if isSearching {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            HStack(spacing: AppSpacing.md) {
                Button {
                    importPresetFromFile()
                } label: {
                    Label(localization.localized(.autoEQImportFile), systemImage: "doc.badge.plus")
                }
                .buttonStyle(.bordered)
                .help(localization.localized(.autoEQImportFileHelp))

                favoritesLink

                Spacer()

                if EQDatabase.shared.isAvailable {
                    if let s = indexStatus {
                        Text(s)
                            .font(AppTypography.bodySmall)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    HStack(spacing: AppSpacing.sm) {
                        if isBuildingIndex {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Button {
                                Task { await buildOrUpdateIndex() }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .buttonStyle(.borderless)
                        }

                        if let s = indexStatus {
                            Text(s)
                                .font(AppTypography.bodySmall)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                                .tooltip(s)
                        }
                    }
                }
            }

            if let e = searchError {
                Text(e)
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var searchResultsSection: some View {
        if candidates.isEmpty, isSearching {
            ProgressView()
                .frame(maxWidth: .infinity, alignment: .center)
        } else if !candidates.isEmpty {
            autoEQPanel {
                sectionHeader(
                    title: localization.localized(.autoEQTypeModelName),
                    systemImage: "magnifyingglass"
                )

                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        ForEach(candidates) { c in
                            HStack(spacing: AppSpacing.sm) {
                                Text(c.display)
                                    .lineLimit(1)
                                    .tooltip(c.display)

                                Spacer(minLength: AppSpacing.sm)

                                Button {
                                    toggleFavoriteForCandidate(c)
                                } label: {
                                    Image(systemName: isFavorite(c) ? "star.fill" : "star")
                                        .foregroundStyle(isFavorite(c) ? .yellow : .secondary)
                                }
                                .buttonStyle(.borderless)
                                .help(isFavorite(c)
                                    ? localization.localized(.removeFromFavorites)
                                    : localization.localized(.addToFavorites))

                                Button(localization.localized(.autoEQImport)) {
                                    Task { await importCandidate(c) }
                                }
                                .controlSize(.small)
                            }
                            .padding(.vertical, AppSpacing.xs)
                        }
                    }
                }
                .frame(maxHeight: 240)
            }
        }
    }

    private var mappedPreviewSection: some View {
        autoEQPanel {
            sectionHeader(
                title: localization.localized(.autoEQMappedPreviewTitle),
                systemImage: "waveform.path.ecg"
            )

            HStack(alignment: .firstTextBaseline) {
                Text(showingBandLabel)
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(.secondary)

                Spacer()

                if let p = preampDB {
                    Text(String(format: "%@: %+.1f dB", localization.localized(.autoEQPreamp), p))
                        .font(AppTypography.mono)
                        .foregroundStyle(.secondary)
                }
            }

            EQGraphView(
                bands: mappedAsEQBands,
                gainBinding: { id in mappedGainBinding(id: id) }
            )
            .frame(height: 300)

            HStack(spacing: AppSpacing.md) {
                Button(localization.localized(.autoEQApplyToEQ)) {
                    applyToAudioEngine()
                }
                .buttonStyle(.borderedProminent)
                .disabled(mapped.isEmpty)

                if !mapped.isEmpty {
                    Text(String(
                        format: localization.localized(.applyBandsCount),
                        mapped.count,
                        audioEngine.isEnabled ? localization.localized(.autoEQEQOn) : localization
                            .localized(.autoEQEQOff)
                    ))
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(.secondary)
                }

                Spacer()
            }
        }
    }

    private var manualEQGraphSection: some View {
        autoEQPanel {
            EQGraphView(
                bands: audioEngine.bands,
                gainBinding: { id in manualBandGainBinding(id: id) }
            )
            .frame(height: 300)
        }
    }

    private func manualBandGainBinding(id: Int) -> Binding<Float> {
        Binding(
            get: {
                guard id < audioEngine.bands.count else { return 0 }
                return audioEngine.bands[id].gain
            },
            set: { audioEngine.updateBandGain(bandId: id, gain: $0) }
        )
    }

    private func sectionHeader(title: String, systemImage: String, help: String? = nil) -> some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 20)

            Text(title)
                .font(AppTypography.heading2)

            if let help {
                InfoPopoverButton {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        Text(title)
                            .font(.headline)
                        Text(help)
                            .font(AppTypography.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Spacer()
        }
    }

    private var eqControlsSection: some View {
        let recommendedPreamp = audioEngine.recommendedPreampGain()

        return autoEQPanel {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                sectionHeader(
                    title: localization.localized(.eqShort),
                    systemImage: "slider.horizontal.3",
                    help: "\(localization.localized(.outputBoostDescription))\n\n\(localization.localized(.limiterActivityDescription))"
                )

                HStack {
                    Picker(localization.localized(.autoEQBandMode), selection: bandModeSelection) {
                        Text("10").tag(BandMode.ten)
                        Text("31").tag(BandMode.thirtyOne)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 240)

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
                        Text(localization.localized(.eqShort))
                            .font(AppTypography.heading3)
                    }
                    .toggleStyle(.switch)
                }

                HStack(spacing: AppSpacing.md) {
                    Button {
                        withAnimation(.spring(response: 0.3)) { _ = audioEngine.restorePresetDefaults() }
                    } label: {
                        Label(localization.localized(.reset), systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!audioEngine.hasPresetDefaults)

                    Button {
                        withAnimation(.spring(response: 0.3)) { audioEngine.applyAutoPreamp() }
                    } label: {
                        Label(localization.localized(.autoPreamp), systemImage: "wand.and.stars")
                    }
                    .buttonStyle(.borderedProminent)

                    Spacer()

                    VStack(alignment: .trailing, spacing: AppSpacing.xxs) {
                        Text(localization.localized(.preamp))
                            .font(AppTypography.labelSmall)
                            .foregroundStyle(.secondary)
                        Text(audioEngine.formatGain(audioEngine.preampGain))
                            .font(AppTypography.mono)
                    }
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

                LimiterIndicatorView(
                    peakMeter: CoreAudioEngine.shared.peakMeter,
                    description: "",
                    gainUnit: localization.localized(.dB)
                )
            }
        }
    }

    private var bassBoostSection: some View {
        autoEQPanel {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                HStack {
                    sectionHeader(
                        title: localization.localized(.autoEQBassBoost),
                        systemImage: "speaker.wave.2.fill"
                    )

                    Spacer()

                    Text(String(format: "%.1f dB", bassBoost))
                        .font(AppTypography.mono)
                }

                Slider(value: $bassBoost, in: 0...6, step: 0.5)
                    .onChange(of: bassBoost) { _ in
                        applyEQDebounceTask?.cancel()
                        applyEQDebounceTask = Task {
                            try? await Task.sleep(nanoseconds: 50_000_000)
                            guard !Task.isCancelled else { return }
                            await MainActor.run {
                                applyToAudioEngine()
                            }
                        }
                    }
            }
        }
    }

    private var favoritesLink: some View {
        Button {
            showFavorites.toggle()
        } label: {
            Label(
                "\(localization.localized(.autoEQFavoritesLink)) (\(favorites.count))",
                systemImage: "star.fill"
            )
            .foregroundStyle(.blue)
        }
        .buttonStyle(.link)
        .popover(isPresented: $showFavorites, arrowEdge: .top) {
            favoritesPopover
        }
    }

    private var favoritesPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(localization.localized(.autoEQFavoritesTitle))
                .font(AppTypography.heading2)

            if favorites.isEmpty {
                Text(localization.localized(.autoEQFavoritesEmpty))
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(favorites) { favorite in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "star.fill")
                                    .foregroundStyle(.yellow)
                                    .imageScale(.small)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(favorite.name)
                                        .font(AppTypography.bodySmall)
                                        .fontWeight(.medium)
                                        .lineLimit(2)
                                        .tooltip(favorite.name)
                                    if let source = favorite.source {
                                        Text(source)
                                            .font(AppTypography.labelSmall)
                                            .foregroundStyle(.secondary)
                                    }
                                    Button(localization.localized(.autoEQLoad)) {
                                        showFavorites = false
                                        Task { await loadFavorite(favorite) }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                }
                                Spacer(minLength: 4)
                                Button {
                                    removeFavorite(favorite)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help(localization.localized(.removeFromFavorites))
                            }
                            .padding(AppSpacing.sm)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(AppRadius.md)
                        }
                    }
                }
            }
        }
        .padding(AppSpacing.md)
        .frame(width: 360, height: 280)
    }

    private var bandModeSelection: Binding<BandMode> {
        Binding(
            get: { bandMode },
            set: { selectBandMode($0) }
        )
    }

    private func selectBandMode(_ newMode: BandMode) {
        guard newMode != bandMode else { return }
        bandMode = newMode
        if audioEngine.bandMode != newMode.audioEngineMode {
            audioEngine.bandMode = newMode.audioEngineMode
        }
        refreshDisplayedBands(shouldApply: true)
    }

    private func syncBandModeFromAudioEngine(_ restoredMode: EQBandMode) {
        let newMode = BandMode(audioEngineMode: restoredMode)
        guard newMode != bandMode else { return }
        bandMode = newMode
        refreshDisplayedBands(shouldApply: false)
    }

    private func refreshDisplayedBands(shouldApply: Bool) {
        DispatchQueue.main.async {
            if bandMode == .ten, !parsed10.isEmpty {
                parsed = parsed10
                preampDB = preampDB10
            } else if bandMode == .thirtyOne, !parsed31.isEmpty {
                parsed = parsed31
                preampDB = preampDB31
            }
            mapped = mappedBands()
            guard shouldApply else { return }
            applyEQDebounceTask?.cancel()
            applyEQDebounceTask = Task {
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    if !mapped.isEmpty, audioEngine.isEnabled {
                        applyToAudioEngine()
                    }
                }
            }
        }
    }

    // MARK: - Offline index helpers

    private func formatIndexAge(_ timestamp: TimeInterval) -> String {
        let age = Date().timeIntervalSince1970 - timestamp
        let days = Int(age / (24 * 3600))
        if days == 0 {
            return localization.localized(.indexToday)
        } else if days == 1 {
            return localization.localized(.indexYesterday)
        } else if days < 7 {
            return String(format: localization.localized(.indexDaysAgo), days)
        } else if days < 30 {
            let weeks = days / 7
            return String(format: localization.localized(.indexWeeksAgo), weeks)
        } else {
            let months = days / 30
            return String(format: localization.localized(.indexMonthsAgo), months)
        }
    }

    private func offlineSearch(_ query: String) -> [SearchCandidate] {
        let q = sanitize(query)
        let t = tokens(q)
        guard !offlineIndex.isEmpty, !t.isEmpty else { return [] }
        func match(entry: OfflineIndexEntry) -> Bool {
            let combined = sanitize(entry.brand + " " + entry.model)
            return t.allSatisfy { combined.contains($0) }
        }
        let hits = offlineIndex.filter { match(entry: $0) }
        return hits.map { e in
            if let r = e.pathReadme {
                // Ensure path is decoded (in case old cache has encoded paths)
                let decoded = r.removingPercentEncoding ?? r
                let full = decoded.hasPrefix("results/") ? decoded : "results/" + decoded
                let parts = full.split(separator: "/").map(String.init)
                let src = parts.count > 1 ? parts[1] : ""
                return SearchCandidate(
                    path: full,
                    name: "README.md",
                    display: "\(src) / \(e.brand) / \(e.model) / README.md",
                    isParametric: false
                )
            } else if let p = e.pathParametric {
                // Ensure path is decoded (in case old cache has encoded paths)
                let decoded = p.removingPercentEncoding ?? p
                let full = decoded.hasPrefix("results/") ? decoded : "results/" + decoded
                let parts = full.split(separator: "/").map(String.init)
                let src = parts.count > 1 ? parts[1] : ""
                return SearchCandidate(
                    path: full,
                    name: "ParametricEQ.txt",
                    display: "\(src) / \(e.brand) / \(e.model) / ParametricEQ.txt",
                    isParametric: true
                )
            } else {
                return SearchCandidate(path: "", name: "", display: "", isParametric: false)
            }
        }.filter { !$0.path.isEmpty }
    }

    static func databaseCandidate(_ headphone: DatabaseHeadphone) -> SearchCandidate {
        let identity = [headphone.source, headphone.brand, headphone.model]
            .map { Data($0.utf8).base64EncodedString() }
            .joined(separator: ":")
        return SearchCandidate(
            path: databaseCandidatePrefix + identity,
            name: String(headphone.id),
            display: "\(headphone.displayName) · \(headphone.source)",
            isParametric: false
        )
    }

    static func directBands(centers: [Double], gains: [Float]) -> [ParsedBand]? {
        guard centers.count == gains.count, gains.allSatisfy(\.isFinite) else { return nil }
        return zip(centers, gains).map { center, gain in
            ParsedBand(freq: center, gain: Double(gain))
        }
    }

    private func databaseCandidates(for query: String) -> [SearchCandidate] {
        var candidates: [SearchCandidate] = []
        for headphone in databaseService.search(query) {
            candidates.append(Self.databaseCandidate(headphone))
        }
        return candidates
    }

    static func databaseSource(from candidate: SearchCandidate) -> String? {
        databaseIdentity(from: candidate.path)?.source
    }

    static func databaseIdentity(from path: String) -> (source: String, brand: String, model: String)? {
        guard path.hasPrefix(databaseCandidatePrefix) else { return nil }
        let encoded = path.dropFirst(databaseCandidatePrefix.count).split(separator: ":")
        guard encoded.count == 3 else { return nil }
        let values = encoded.compactMap { component -> String? in
            guard let data = Data(base64Encoded: String(component)) else { return nil }
            return String(data: data, encoding: .utf8)
        }
        guard values.count == 3 else { return nil }
        return (values[0], values[1], values[2])
    }

    private func databaseHeadphoneID(from candidate: SearchCandidate) -> Int? {
        guard candidate.path.hasPrefix(Self.databaseCandidatePrefix) else { return nil }
        guard let identity = Self.databaseIdentity(from: candidate.path) else { return nil }
        return databaseService.headphoneID(
            brand: identity.brand,
            model: identity.model,
            source: identity.source
        )
    }

    private func buildOrUpdateIndex() async {
        guard !isBuildingIndex else { return }
        isBuildingIndex = true
        indexStatusRaw = .building
        defer { isBuildingIndex = false }
        do {
            guard let url = URL(string: AppConstants.URLs.autoEQIndex)
            else { indexStatusRaw = .raw("Invalid URL"); return }
            let (data, resp) = try await legacyRepository.session.data(from: url)
            guard let http = resp as? HTTPURLResponse,
                  (200...299).contains(http.statusCode)
            else { indexStatusRaw = .error(localization.localized(.httpError)); return }
            let text = String(data: data, encoding: .utf8) ?? ""
            var map: [String: OfflineIndexEntry] = [:]
            // Match markdown links: [text](./path) - capture everything between (./ and ) at end of line
            // Pattern matches: ( then ./ then any chars until ) followed by space, newline, or end
            let linkPattern = #"\((\./[^\n]+?)\)(?:\s|$)"#
            if let re = try? NSRegularExpression(pattern: linkPattern, options: []) {
                let nsr = NSRange(text.startIndex..<text.endIndex, in: text)
                re.enumerateMatches(in: text, options: [], range: nsr) { m, _, _ in
                    guard let m, m.numberOfRanges >= 2, let r1 = Range(m.range(at: 1), in: text) else { return }
                    let rel =
                        String(text[r1]) // e.g. "./oratory1990/over-ear/HIFIMAN%20HE400se%20(non-stealth%20magnet)"
                    let relPath = String(rel.dropFirst(2)) // drop "./"
                    // Decode the entire path first, then split
                    let decodedRelPath = relPath.removingPercentEncoding ?? relPath
                    let comps = decodedRelPath.split(separator: "/").map(String.init)
                    guard comps.count >= 2 else { return }
                    guard let lastSeg = comps.last else { return }
                    // Покращений парсинг: зберігаємо повну назву як бренд+модель
                    var guessedBrand = ""
                    var guessedModel = lastSeg

                    // Спробувати виділити бренд (перше слово або перші два слова)
                    let words = lastSeg.split(separator: " ").map(String.init)
                    if words.count >= 2 {
                        // Перевірити чи перші 2 слова - це бренд (наприклад "Audio Technica")
                        let twoWords = words[0] + " " + words[1]
                        let knownTwoWordBrands = [
                            "Audio Technica",
                            "Beats by",
                            "Sony WH",
                            "Bose QuietComfort",
                            "Bang Olufsen"
                        ]
                        if knownTwoWordBrands.contains(where: { twoWords.hasPrefix($0) }), words.count > 2 {
                            guessedBrand = twoWords
                            guessedModel = words.dropFirst(2).joined(separator: " ")
                        } else {
                            guessedBrand = words[0]
                            guessedModel = words.dropFirst().joined(separator: " ")
                        }
                    }

                    let key = decodedRelPath // unique per source/category/model

                    // Визначаємо source та type з шляху
                    let source = comps.count >= 1 ? comps[0] : "unknown"
                    let type = comps.count >= 2 ? comps[1] : "unknown"
                    let basePath = "results/" + decodedRelPath

                    let entry = OfflineIndexEntry(
                        brand: guessedBrand,
                        model: guessedModel,
                        source: source,
                        type: type,
                        pathFixedBandEQ: basePath + "/" + lastSeg + " FixedBandEQ.txt",
                        pathGraphicEQ: basePath + "/" + lastSeg + " GraphicEQ.txt",
                        pathParametric: basePath + "/" + lastSeg + " ParametricEQ.txt",
                        pathReadme: basePath + "/README.md"
                    )

                    map[key] = entry
                }
            }
            let out = Array(map.values).filter { $0.pathReadme != nil || $0.pathParametric != nil }
            legacyRepository.saveOfflineIndex(out)
            offlineIndex = out
            indexTruncated = false
            indexStatusRaw = .updatedNow(count: out.count)
            if !normalizedQuery.isEmpty {
                let local = offlineSearch(normalizedQuery)
                candidates = rank(local, query: normalizedQuery)
            }
        } catch {
            indexStatusRaw = .error(friendlyNetworkError(error))
        }
    }

    private func formatFrequency(_ hz: Double) -> String {
        if hz >= 1000 {
            let k = hz / 1000.0
            return k == k.rounded() ? String(format: "%.0fk", k) : String(format: "%.1fk", k)
        }
        return String(format: "%.0f", hz)
    }

    private var mappedAsEQBands: [EQBand] {
        mapped.enumerated().map { index, mb in
            let bassBoost = bassBoostForFrequency(mb.center)
            let total = min(max(mb.gain + bassBoost, -20), 20)
            return EQBand(id: index, frequency: Float(mb.center), gain: Float(total))
        }
    }

    private func mappedGainBinding(id: Int) -> Binding<Float> {
        Binding(
            get: {
                guard id < mapped.count else { return 0 }
                let mb = mapped[id]
                let total = mb.gain + bassBoostForFrequency(mb.center)
                return Float(min(max(total, -20), 20))
            },
            set: { newValue in
                guard id < mapped.count else { return }
                let bassBoost = bassBoostForFrequency(mapped[id].center)
                let rawGain = Double(newValue) - bassBoost
                let clamped = min(max(rawGain, -12), 12)
                let stepped = (clamped / 0.5).rounded() * 0.5
                if mapped[id].gain != stepped {
                    mapped[id].gain = stepped
                    scheduleLiveApply()
                }
            }
        )
    }

    private func barsBody() -> some View {
        GeometryReader { geo in
            let labelHeight: CGFloat = bandMode == .thirtyOne ? 28 : 18
            let dbAxisWidth: CGFloat = 32
            let topReserve: CGFloat = 18
            let maxH = max(160.0, geo.size.height - labelHeight - topReserve - 8)
            let bandCount = CGFloat(mapped.isEmpty ? (bandMode == .thirtyOne ? 31 : 10) : mapped.count)
            let availableWidth = geo.size.width - dbAxisWidth - 6
            let minSpacing: CGFloat = bandMode == .thirtyOne ? 3 : 5
            let minBarWidth: CGFloat = bandMode == .thirtyOne ? 8 : 14
            let spacing: CGFloat = max(
                minSpacing,
                min(10, (availableWidth - bandCount * minBarWidth) / max(1, bandCount - 1))
            )
            let hitWidth: CGFloat = max(minBarWidth, (availableWidth - spacing * (bandCount - 1)) / bandCount)
            let barWidth: CGFloat = bandMode == .thirtyOne ? max(hitWidth * 0.65, hitWidth - 4) : 14
            let gridDbs: [Int] = [12, 6, 0, -6, -12]

            HStack(alignment: .top, spacing: 6) {
                VStack(spacing: 0) {
                    Spacer().frame(height: topReserve)
                    ZStack {
                        ForEach(gridDbs, id: \.self) { db in
                            let y = CGFloat(12 - db) / 24.0 * maxH
                            Text(db > 0 ? "+\(db)" : "\(db)")
                                .font(.system(size: 16, weight: db == 0 ? .semibold : .regular).monospacedDigit())
                                .foregroundStyle(db == 0 ? Color.primary.opacity(0.85) : .secondary)
                                .frame(width: dbAxisWidth - 4, alignment: .trailing)
                                .position(x: (dbAxisWidth - 4) / 2, y: y)
                        }
                    }
                    .frame(width: dbAxisWidth - 4, height: maxH)
                    Spacer().frame(height: labelHeight + 4)
                }

                ZStack(alignment: .top) {
                    VStack(spacing: 0) {
                        Spacer().frame(height: topReserve)
                        ZStack(alignment: .top) {
                            ForEach(gridDbs, id: \.self) { db in
                                let y = CGFloat(12 - db) / 24.0 * maxH
                                Rectangle()
                                    .fill(db == 0 ? Color.secondary.opacity(0.55) : Color.secondary.opacity(0.12))
                                    .frame(height: db == 0 ? 1 : 0.5)
                                    .offset(y: y)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: maxH, alignment: .top)
                        Spacer().frame(height: labelHeight + 4)
                    }

                    HStack(alignment: .top, spacing: spacing) {
                        ForEach(Array(mapped.enumerated()), id: \.element.id) { index, mb in
                            bandColumn(
                                index: index,
                                mb: mb,
                                maxH: maxH,
                                barWidth: barWidth,
                                hitWidth: hitWidth,
                                labelHeight: labelHeight,
                                topReserve: topReserve
                            )
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
        }
        .frame(height: 300)
    }

    @ViewBuilder
    private func bandColumn(
        index: Int,
        mb: MappedBand,
        maxH: CGFloat,
        barWidth: CGFloat,
        hitWidth: CGFloat,
        labelHeight: CGFloat,
        topReserve: CGFloat
    ) -> some View {
        let bassBoostValue = bassBoostForFrequency(mb.center)
        let totalGain = mb.gain + bassBoostValue
        let clampedTotal = min(max(totalGain, -12), 12)
        let zeroY = maxH / 2
        let barHeight = CGFloat(abs(clampedTotal) / 24) * maxH
        let barTop = clampedTotal >= 0 ? zeroY - barHeight : zeroY
        let thumbY = clampedTotal >= 0 ? zeroY - barHeight : zeroY + barHeight
        let isActive = draggingBandIndex == index
        let isHovered = hoveredBandIndex == index
        let thumbSize: CGFloat = bandMode == .thirtyOne ? 12 : 14
        let showReadout = isActive || isHovered

        VStack(spacing: 0) {
            Text(String(format: "%+.1f dB", mb.gain))
                .font(.system(size: 16, weight: .medium).monospacedDigit())
                .foregroundStyle(.white)
                .fixedSize()
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.black.opacity(0.7))
                )
                .opacity(showReadout ? 1 : 0)
                .frame(height: topReserve)
                .zIndex(10)

            ZStack(alignment: .top) {
                Rectangle()
                    .fill(Color.accentColor.opacity(isActive ? 1.0 : (isHovered ? 0.95 : 0.85)))
                    .frame(width: barWidth, height: barHeight)
                    .offset(y: barTop)

                Circle()
                    .fill(Color.white.opacity(isActive ? 0.45 : (isHovered ? 0.95 : 0.85)))
                    .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                    .frame(width: thumbSize, height: thumbSize)
                    .offset(y: thumbY - thumbSize / 2)
                    .animation(.easeOut(duration: 0.1), value: isActive)
                    .animation(.easeOut(duration: 0.1), value: isHovered)
            }
            .frame(width: hitWidth, height: maxH, alignment: .top)

            Text(formatFrequency(mb.center))
                .font(bandMode == .thirtyOne ? Font.system(size: 16) : AppTypography.labelSmall)
                .foregroundStyle(isHovered || isActive ? .primary : .secondary)
                .fontWeight(isHovered || isActive ? .semibold : .regular)
                .fixedSize()
                .padding(.top, 4)
                .rotationEffect(.degrees(bandMode == .thirtyOne ? -45 : 0))
                .frame(height: labelHeight)
        }
        .frame(width: hitWidth, height: topReserve + maxH + labelHeight + 4)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                hoveredBandIndex = index
            } else if hoveredBandIndex == index {
                hoveredBandIndex = nil
            }
        }
        .gesture(bandDragGesture(index: index, maxH: maxH, topReserve: topReserve))
    }

    private func bandDragGesture(index: Int, maxH: CGFloat, topReserve: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard index < mapped.count else { return }
                if draggingBandIndex != index { draggingBandIndex = index }
                let yInBar = value.location.y - topReserve
                let zeroY = maxH / 2
                let offsetFromZero = zeroY - yInBar
                let bassBoostValue = bassBoostForFrequency(mapped[index].center)
                let rawTotal = Double(offsetFromZero / maxH) * 24.0
                let rawGain = rawTotal - bassBoostValue
                let clamped = min(max(rawGain, -12), 12)
                let stepped = (clamped / 0.5).rounded() * 0.5
                if mapped[index].gain != stepped {
                    mapped[index].gain = stepped
                    scheduleLiveApply()
                }
            }
            .onEnded { _ in
                draggingBandIndex = nil
            }
    }

    private func scheduleLiveApply() {
        applyEQDebounceTask?.cancel()
        applyEQDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 30_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                applyToAudioEngine()
            }
        }
    }

    // MARK: - Search helpers

    private var normalizedQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var showingBandLabel: String {
        bandMode == .ten ? localization.localized(.bands10) : localization.localized(.bands31)
    }

    private func sanitize(_ s: String) -> String {
        let lower = s.lowercased()
        let allowed = lower.filter { $0.isLetter || $0.isNumber || $0 == " " || $0 == "/" }
        return allowed.replacingOccurrences(of: "  ", with: " ")
    }

    private func tokens(_ s: String) -> [String] {
        sanitize(s).split(separator: " ").map(String.init)
    }

    private func displayName(from path: String) -> String {
        let comps = path.split(separator: "/").map(String.init)
        let tail = comps.suffix(3)
        return tail.joined(separator: " / ")
    }

    private func rank(_ input: [SearchCandidate], query: String) -> [SearchCandidate] {
        let q = sanitize(query)
        let t = tokens(q)
        func score(_ c: SearchCandidate) -> Int {
            let s = sanitize(c.display + " " + c.path)
            var sc = 0
            for tok in t {
                if s.contains(tok) { sc += 2 }
                if s.hasPrefix(tok) { sc += 1 }
            }
            if c.isParametric { sc += 1 }
            return sc
        }
        return input.sorted { a, b in
            let sa = score(a), sb = score(b)
            return sa == sb ? a.display.count < b.display.count : sa > sb
        }
    }

    private func friendlyNetworkError(_ error: Error) -> String {
        if let e = error as? URLError {
            switch e.code {
            case .cannotFindHost:
                return "Cannot resolve GitHub host. Check Internet/DNS."
            case .notConnectedToInternet:
                return "No Internet connection."
            case .timedOut:
                return "Network timeout."
            case .cannotConnectToHost:
                return "Cannot connect to GitHub."
            default:
                return e.localizedDescription
            }
        }
        return error.localizedDescription
    }

    private func searchDebounced() async {
        // Скасувати попередній запит
        searchDebounceTask?.cancel()

        let q = normalizedQuery
        if q.count < 2 {
            candidates = []
            searchError = nil
            return
        }

        // Створити новий Task з затримкою
        searchDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            // Перевірити чи запит ще актуальний
            guard !Task.isCancelled, q == normalizedQuery else { return }

            await MainActor.run {
                isSearching = true
            }

            defer {
                Task { @MainActor in
                    isSearching = false
                }
            }

            let combined: [SearchCandidate]
            if EQDatabase.shared.isAvailable {
                combined = databaseCandidates(for: q)
            } else {
                var fallback = offlineSearch(q)
                if fallback.isEmpty, let cached = legacyRepository.loadCandidates(for: q) {
                    fallback = cached
                }
                combined = fallback
            }

            guard !Task.isCancelled else { return }

            let ranked = rank(combined, query: q)

            await MainActor.run {
                candidates = ranked
            }

            // Зберегти результати пошуку в кеш
            if !ranked.isEmpty {
                legacyRepository.saveCandidates(ranked, for: q)
            }
        }

        await searchDebounceTask?.value
    }

    @MainActor
    private func importCandidate(_ c: SearchCandidate) async {
        isSearching = true
        defer { isSearching = false }
        searchError = nil

        // ✅ Check cache first - prevents re-importing and getting different values
        if let cached = importCache[c.path] {
            self.parsed10 = cached.parsed10
            self.parsed31 = cached.parsed31
            self.parsed = (bandMode == .ten) ? cached.parsed10 : cached.parsed31

            // ✅ Використовуємо правильний preamp для поточного режиму
            self.preampDB10 = cached.preampDB10
            self.preampDB31 = cached.preampDB31
            self.preampDB = (bandMode == .ten) ? cached.preampDB10 : cached.preampDB31
            self.rawText = "Imported from cache"
            self.activePresetName = cached.name
            self.activePresetSource = cached.source
            self.activePresetTarget = cached.target
            self.activePresetPath = c.path

            // Update mapped bands
            self.mapped = mappedBands()

            return
        }

        // ✅ Очищаємо попередній активний пресет перед імпортом нового
        self.activePresetName = nil
        self.activePresetSource = nil
        self.activePresetTarget = nil
        self.activePresetPath = nil

        // Request deduplication
        if activeRequests.contains(c.path) {
            return
        }
        activeRequests.insert(c.path)
        defer { activeRequests.remove(c.path) }

        if c.path.hasPrefix(Self.databaseCandidatePrefix) {
            guard let headphoneID = databaseHeadphoneID(from: c) else {
                searchError = localization.localized(.autoEQImportFileError)
                return
            }
            importDatabaseCandidate(c, headphoneID: headphoneID)
            return
        }

        // Знаходимо entry в offline index для отримання шляхів до .txt файлів
        let entry = offlineIndex.first { entry in
            entry.pathReadme?.contains(c.path) == true ||
                entry.pathParametric?.contains(c.path) == true
        }

        // NOTE: TIER 0 (Python AutoEQ Server) removed - using SQLite database instead
        // To restore: see git history for AutoEQServer.swift

        // 🎯 TIER 1: Локальні .txt файли (основний fallback для legacy index)
        if let entry {
            // Завантажуємо обидва режими з локальних файлів
            var loaded10: [ParsedBand]?
            var loaded31: [ParsedBand]?
            var loadedPreamp: Double?

            // FixedBandEQ.txt для 10-band
            if let fixedPath = entry.pathFixedBandEQ {
                if let result = parseFixedBandEQFile(fromPath: fixedPath) {
                    loaded10 = result.bands
                    loadedPreamp = result.preamp
                }
            }

            // GraphicEQ.txt для обох режимів
            if let graphicPath = entry.pathGraphicEQ {
                if let graphicBands = parseGraphicEQFile(fromPath: graphicPath) {
                    // Маппимо на 10-band якщо не маємо FixedBandEQ
                    if loaded10 == nil {
                        var mapped10: [ParsedBand] = []
                        for center in tenCenters {
                            if let closest = graphicBands.min(by: { abs($0.freq - center) < abs($1.freq - center) }) {
                                mapped10.append(ParsedBand(freq: center, gain: closest.gain))
                            }
                        }
                        loaded10 = mapped10
                    }

                    // Маппимо на 31-band
                    var mapped31: [ParsedBand] = []
                    for center in thirtyOneCenters {
                        if let closest = graphicBands.min(by: { abs($0.freq - center) < abs($1.freq - center) }) {
                            mapped31.append(ParsedBand(freq: center, gain: closest.gain))
                        }
                    }
                    loaded31 = mapped31
                }
            }

            // Якщо щось завантажили - зберігаємо
            if let bands10 = loaded10, let bands31 = loaded31 {
                self.parsed10 = bands10
                self.parsed31 = bands31
                self.parsed = (bandMode == .ten) ? bands10 : bands31

                // ✅ TIER 1 має однаковий preamp для обох режимів
                self.preampDB10 = loadedPreamp
                self.preampDB31 = loadedPreamp
                self.preampDB = loadedPreamp
                self.rawText = "Imported from local .txt files"

                // Зберігаємо назву активного пресета
                self.activePresetName = "\(entry.brand) \(entry.model)"
                self.activePresetSource = entry.source
                self.activePresetTarget = nil
                self.activePresetPath = c.path

                // ✅ Cache the import result
                importCache[c.path] = ImportCacheEntry(
                    parsed10: self.parsed10,
                    parsed31: self.parsed31,
                    preampDB10: loadedPreamp,
                    preampDB31: loadedPreamp, // TIER 1 має однаковий preamp
                    name: self.activePresetName ?? c.display,
                    source: self.activePresetSource,
                    target: self.activePresetTarget,
                    timestamp: Date()
                )

                return
            } else if let bands10 = loaded10 {
                self.parsed10 = bands10
                self.parsed = bands10
                self.preampDB = loadedPreamp
                self.rawText = "Imported from local FixedBandEQ.txt"

                // Зберігаємо назву активного пресета
                self.activePresetName = "\(entry.brand) \(entry.model)"
                self.activePresetSource = entry.source
                self.activePresetTarget = nil // TIER 1 doesn't specify target
                self.activePresetPath = c.path

                return
            }
        }

        // 🎯 TIER 2: Cache hit (попередньо завантажений README)
        if let cached = readmeCache[c.path] {
            await processReadmeText(cached, candidate: c)
            return
        }

        // 🎯 TIER 3: Завантаження з GitHub (fallback)

        // Build URL to raw README/ParametricEQ
        let decoded = c.path.removingPercentEncoding ?? c.path
        let encoded = decoded.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? decoded
        let raw = AppConstants.URLs.autoEQRawBase + encoded
        guard let url = URL(string: raw) else { searchError = "Bad URL"; return }

        do {
            var text = ""
            var ok = false
            var statusCode: Int?

            // Try primary URL
            let (data, resp) = try await legacyRepository.session.data(from: url)
            if let http = resp as? HTTPURLResponse { statusCode = http.statusCode }
            if let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                text = String(data: data, encoding: .utf8) ?? ""
                ok = true
            }

            // Fallback 1: if Parametric fetch failed, try README.md from same directory
            if !ok, c.isParametric {
                let dir = c.path.split(separator: "/").dropLast().joined(separator: "/")
                let readmePath = dir + "/README.md"
                let renc = readmePath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? readmePath
                let rraw = AppConstants.URLs.autoEQRawBase + renc
                if let rurl = URL(string: rraw) {
                    let (d2, r2) = try await legacyRepository.session.data(from: rurl)
                    if let h2 = r2 as? HTTPURLResponse, (200...299).contains(h2.statusCode) {
                        text = String(data: d2, encoding: .utf8) ?? ""
                        ok = true
                    }
                }
            }

            // Fallback 2: README.md from other sources with the same model folder
            if !ok {
                let parts = c.path.split(separator: "/").map(String.init)
                if parts.count >= 2 {
                    let modelFolder = parts[parts.count - 2]
                    var alts: [String] = offlineIndex.compactMap(\.pathReadme)
                        .filter { path in
                            let ps = path.split(separator: "/").map(String.init)
                            return ps.count >= 2 && ps[ps.count - 2] == modelFolder
                        }
                    func srcRank(_ s: String) -> Int {
                        let ss = s.split(separator: "/").map(String.init)
                        guard ss.count > 1 else { return 99 }
                        let src = ss[1].lowercased()
                        if src.contains("oratory1990") { return 0 }
                        if src.contains("filk") { return 1 }
                        if src.contains("rtings") { return 2 }
                        return 9
                    }
                    alts.sort { srcRank($0) < srcRank($1) }
                    for ap in alts.prefix(2) {
                        let enc = ap.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ap
                        let url2s = AppConstants.URLs.autoEQRawBase + enc
                        guard let url2 = URL(string: url2s) else { continue }
                        let (d3, r3) = try await legacyRepository.session.data(from: url2)
                        if let h3 = r3 as? HTTPURLResponse, (200...299).contains(h3.statusCode) {
                            text = String(data: d3, encoding: .utf8) ?? ""
                            ok = true
                            break
                        }
                    }
                }
            }

            guard ok else {
                let urlInfo = raw.replacingOccurrences(of: AppConstants.URLs.autoEQRawBase, with: "")
                searchError = statusCode.map { "HTTP \($0): \(urlInfo)" } ?? "Import failed"
                return
            }

            // Cache and process
            readmeCache[c.path] = text
            await processReadmeText(text, candidate: c)
        } catch {
            searchError = error.localizedDescription
        }
    }

    // MARK: - Database Import (New - Fast!)

    @MainActor
    private func importPresetFromFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.plainText, .text]
        panel.message = localization.localized(.autoEQImportFileHelp)

        guard panel.runModal() == .OK, let url = panel.url else { return }
        // Реальні AutoEQ-пресети — кілобайти; більший файл або не текст, або DoS
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 1_000_000 {
            searchError = localization.localized(.autoEQImportFileError)
            return
        }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            searchError = localization.localized(.autoEQImportFileError)
            return
        }

        let presetName = url.deletingPathExtension().lastPathComponent
        applyCustomPreset(text: text, name: presetName, persist: true, autoApply: true)
    }

    /// Парсить і застосовує custom .txt пресет. Використовується при імпорті,
    /// відновленні при старті та завантаженні з обраних.
    @discardableResult
    private func applyCustomPreset(text: String, name: String, persist: Bool, autoApply: Bool) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var bands: [ParsedBand] = []
        var preamp: Double?

        let apo = parseEqualizerAPOFormat(text: trimmed)
        if !apo.bands.isEmpty {
            bands = apo.bands
            preamp = apo.preamp
        } else if trimmed.contains("GraphicEQ:") || trimmed.contains("FixedBandEQ:") {
            bands = parseGraphicEQ(text: trimmed)
        } else if trimmed.contains("### Fixed Band EQ") {
            let parsedBands = parseFixedBandTable(text: trimmed, bands: bandMode == .ten ? 10 : 31)
            if !parsedBands.isEmpty {
                bands = parsedBands
                preamp = parsePreamp(text: trimmed)
            }
        }

        // Нечислові й екстремальні значення з файлу не мають дійти до DSP
        bands = Array(bands.filter {
            $0.freq.isFinite && $0.freq > 0 && $0.freq <= 30000
                && $0.gain.isFinite && abs($0.gain) <= 40
                && $0.q.isFinite && $0.q > 0 && $0.q <= 100
        }.prefix(256))
        if let p = preamp, !p.isFinite || abs(p) > 40 {
            preamp = nil
        }

        guard !bands.isEmpty else {
            searchError = localization.localized(.autoEQImportFileError)
            return false
        }

        parsed10 = bands
        parsed31 = bands
        parsed = bands
        preampDB10 = preamp
        preampDB31 = preamp
        preampDB = preamp
        rawText = text
        activePresetName = name
        activePresetSource = "Custom"
        activePresetTarget = nil
        activePresetPath = nil
        searchError = nil
        mapped = mappedBands()

        if persist {
            lastCustomPresetText = text
            lastCustomPresetName = name
        }

        if autoApply {
            applyEQDebounceTask?.cancel()
            applyEQDebounceTask = Task {
                try? await Task.sleep(nanoseconds: 100_000_000)
                if !Task.isCancelled {
                    await MainActor.run {
                        applyToAudioEngine()
                    }
                }
            }
        }

        dlog(
            "Custom preset applied: \(name), \(bands.count) filters, preamp: \(preamp ?? 0)",
            level: .info,
            category: .network
        )
        return true
    }

    private func importFromDatabase(_ searchQuery: String) {
        searchError = nil

        let normalizedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            searchError = "Please enter a headphone name"
            return
        }

        let searchResults = EQDatabase.shared.isAvailable
            ? databaseCandidates(for: normalizedQuery)
            : offlineSearch(normalizedQuery)
        let rankedCandidates = rank(searchResults, query: normalizedQuery)

        guard !rankedCandidates.isEmpty else {
            searchError = "❌ No headphones found for '\(searchQuery)'\n\nTry:\n• Different spelling\n• Brand name (e.g. 'Sennheiser HD 600')"
            return
        }

        let oratoryMatch = rankedCandidates.first {
            Self.databaseSource(from: $0)?.localizedCaseInsensitiveContains("oratory") == true
        }
        guard let bestMatch = oratoryMatch ?? rankedCandidates.first else {
            searchError = "No valid match found"
            return
        }

        // Import the preset
        Task {
            await importCandidate(bestMatch)
        }
    }

    @MainActor
    private func importDatabaseCandidate(_ candidate: SearchCandidate, headphoneID: Int) {
        guard let imported = databaseService.load(headphoneID: headphoneID),
              let bands10 = Self.directBands(
                  centers: tenCenters,
                  gains: imported.gains10
              ),
              let bands31 = Self.directBands(
                  centers: thirtyOneCenters,
                  gains: imported.gains31
              ) else {
            searchError = localization.localized(.autoEQImportFileError)
            return
        }

        let preset = imported.preset
        let name = candidate.display.components(separatedBy: " · ").first ?? candidate.display
        parsed10 = bands10
        parsed31 = bands31
        parsed = bandMode == .ten ? bands10 : bands31
        preampDB10 = Double(preset.preampGain)
        preampDB31 = Double(preset.preampGain)
        preampDB = Double(preset.preampGain)
        rawText = "EQDatabase.db"
        activePresetName = name
        activePresetSource = if !preset.author.isEmpty {
            preset.author
        } else if !preset.source.isEmpty {
            preset.source
        } else {
            Self.databaseSource(from: candidate)
        }
        activePresetTarget = preset.targetCurve.isEmpty ? targetProfile : preset.targetCurve
        activePresetPath = candidate.path
        mapped = mappedBands()

        importCache[candidate.path] = ImportCacheEntry(
            parsed10: bands10,
            parsed31: bands31,
            preampDB10: Double(preset.preampGain),
            preampDB31: Double(preset.preampGain),
            name: name,
            source: activePresetSource,
            target: activePresetTarget,
            timestamp: Date()
        )
    }

    @MainActor
    private func processReadmeText(_ text: String, candidate: SearchCandidate) async {
        // Parse both 10-band and 31-band versions
        let bands10 = parseFixedBandTable(text: text, bands: 10)
        let bands31 = parseFixedBandTable(text: text, bands: 31)

        // Try old format if table parsing failed
        var currentBands: [ParsedBand] = []
        if bands10.isEmpty, bands31.isEmpty {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.contains("GraphicEQ:") || trimmed.contains("FixedBandEQ:") {
                currentBands = parseGraphicEQ(text: trimmed)
            }
        }

        if bands10.isEmpty, bands31.isEmpty, currentBands.isEmpty {
            searchError = "No EQ data found in file"
            return
        }

        // Parse preamp value
        let preamp = parsePreamp(text: text)

        // Update state
        self.parsed10 = bands10.isEmpty ? currentBands : bands10
        self.parsed31 = bands31.isEmpty ? currentBands : bands31
        self.parsed = (bandMode == .ten) ? self.parsed10 : self.parsed31
        self.preampDB = preamp
        self.rawText = text

        // Зберігаємо назву активного пресета (витягуємо з display name)
        let displayParts = candidate.display.split(separator: "/").map(String.init)
        if displayParts.count >= 2 {
            self.activePresetSource = displayParts[0].trimmingCharacters(in: .whitespaces)
            self.activePresetName = displayParts.dropFirst().joined(separator: " / ")
                .trimmingCharacters(in: .whitespaces)
        } else {
            self.activePresetName = candidate.display
            self.activePresetSource = nil
        }
        self.activePresetTarget = nil // README doesn't specify target
        self.activePresetPath = candidate.path

        dlog(
            "Import successful - 10-band: \(self.parsed10.count), 31-band: \(self.parsed31.count)",
            level: .info,
            category: .network
        )
    }

    // MARK: - Mapping

    private func mappedBands() -> [MappedBand] {
        let centers = (bandMode == .ten) ? tenCenters : thirtyOneCenters
        if activePresetPath?.hasPrefix(Self.databaseCandidatePrefix) == true {
            let direct = bandMode == .ten ? parsed10 : parsed31
            if direct.count == centers.count {
                return zip(centers, direct).map { center, band in
                    MappedBand(center: center, gain: band.gain)
                }
            }
        }
        let sampleRate: Double = 48000

        return centers.map { c in
            let total = parsed.reduce(0.0) { acc, b in
                acc + Self.biquadGainDB(at: c, filter: b, sampleRate: sampleRate)
            }
            return MappedBand(center: c, gain: total)
        }
    }

    private static func biquadGainDB(at freq: Double, filter b: ParsedBand, sampleRate: Double) -> Double {
        let f0 = b.freq
        let gain = b.gain
        let q = max(b.q, 0.001)
        let A = pow(10.0, gain / 40.0)
        let w0 = 2.0 * .pi * f0 / sampleRate
        let alpha = sin(w0) / (2.0 * q)
        let cosW0 = cos(w0)

        var b0 = 1.0, b1 = 0.0, b2 = 0.0
        var a0 = 1.0, a1 = 0.0, a2 = 0.0

        switch b.type {
        case .allPassPEQ,
             .peak:
            b0 = 1 + alpha * A
            b1 = -2 * cosW0
            b2 = 1 - alpha * A
            a0 = 1 + alpha / A
            a1 = -2 * cosW0
            a2 = 1 - alpha / A
        case .lowShelf:
            let beta = sqrt(A) / q
            b0 = A * ((A + 1) - (A - 1) * cosW0 + beta * sin(w0))
            b1 = 2 * A * ((A - 1) - (A + 1) * cosW0)
            b2 = A * ((A + 1) - (A - 1) * cosW0 - beta * sin(w0))
            a0 = (A + 1) + (A - 1) * cosW0 + beta * sin(w0)
            a1 = -2 * ((A - 1) + (A + 1) * cosW0)
            a2 = (A + 1) + (A - 1) * cosW0 - beta * sin(w0)
        case .highShelf:
            let beta = sqrt(A) / q
            b0 = A * ((A + 1) + (A - 1) * cosW0 + beta * sin(w0))
            b1 = -2 * A * ((A - 1) + (A + 1) * cosW0)
            b2 = A * ((A + 1) + (A - 1) * cosW0 - beta * sin(w0))
            a0 = (A + 1) - (A - 1) * cosW0 + beta * sin(w0)
            a1 = 2 * ((A - 1) - (A + 1) * cosW0)
            a2 = (A + 1) - (A - 1) * cosW0 - beta * sin(w0)
        default:
            return 0
        }

        let w = 2.0 * .pi * freq / sampleRate
        let cosW = cos(w), cos2W = cos(2 * w)
        let sinW = sin(w), sin2W = sin(2 * w)

        let numRe = b0 + b1 * cosW + b2 * cos2W
        let numIm = -(b1 * sinW + b2 * sin2W)
        let denRe = a0 + a1 * cosW + a2 * cos2W
        let denIm = -(a1 * sinW + a2 * sin2W)

        let numMag = sqrt(numRe * numRe + numIm * numIm)
        let denMag = sqrt(denRe * denRe + denIm * denIm)
        guard denMag > 0 else { return 0 }
        return 20.0 * log10(numMag / denMag)
    }

    private func nearestCenterIndex(for freq: Double, centers: [Double]) -> Int {
        var best = 0
        var bestDist = Double.greatestFiniteMagnitude
        for (i, c) in centers.enumerated() {
            let d = abs(freq - c)
            if d < bestDist {
                bestDist = d
                best = i
            }
        }
        return best
    }

    // MARK: - Apply to AudioEngine

    private func applyToAudioEngine() {
        guard !mapped.isEmpty else {
            dlog("⚠️ No mapped bands to apply", category: .network)
            return
        }

        let engine = AudioEngine.shared

        // Переконуємось що bandMode співпадає з AudioEngine
        let targetBandMode: EQBandMode = (bandMode == .ten) ? .tenBand : .thirtyOneBand
        if engine.bandMode != targetBandMode {
            engine.bandMode = targetBandMode
        }

        // Застосовуємо gain значення для кожної смуги (з Bass Boost)
        var eqValues: [Float] = []
        var cleanGains: [Float] = [] // Чисті gains без Bass Boost для збереження
        for mb in mapped {
            cleanGains.append(Float(mb.gain))
            let bassBoostValue = bassBoostForFrequency(mb.center)
            let totalGain = mb.gain + bassBoostValue
            eqValues.append(Float(totalGain))
        }

        if let preamp = preampDB {
            engine.preampGain = Float(preamp)
        } else {
            let maxPositive = eqValues.max() ?? 0
            engine.preampGain = maxPositive > 0 ? -maxPositive : 0
        }

        engine.applyEQValues(eqValues)

        // ✅ CRITICAL: Save clean gains WITHOUT Bass Boost to avoid accumulation
        PresetPersistence.save(
            mode: targetBandMode,
            gains: cleanGains,
            preamp: engine.preampGain,
            bassBoost: Float(bassBoost)
        )
        if let descriptorJSON = persistLastAppliedDescriptor() {
            DevicePresetManager.shared.recordApply(DevicePresetRecord(
                mode: targetBandMode.rawValue,
                appliedGains: eqValues,
                cleanGains: cleanGains,
                preamp: engine.preampGain,
                bassBoost: Float(bassBoost),
                descriptorJSON: descriptorJSON
            ))
        }

        // Вмикаємо EQ якщо він вимкнений
        if !engine.isEnabled {
            engine.setEnabled(true)
        }
    }

    // MARK: - Last Applied Preset (UI restore)

    private struct LastAppliedDescriptor: Codable {
        let name: String?
        let source: String?
        let path: String? // БД-пресет: шлях у AutoEQ-репозиторії
        let rawText: String? // custom-пресет: повний текст
    }

    @discardableResult
    private func persistLastAppliedDescriptor() -> String? {
        let descriptor: LastAppliedDescriptor
        if let path = activePresetPath {
            descriptor = LastAppliedDescriptor(
                name: activePresetName,
                source: activePresetSource,
                path: path,
                rawText: nil
            )
        } else if activePresetSource == "Custom", !rawText.isEmpty {
            descriptor = LastAppliedDescriptor(
                name: activePresetName,
                source: activePresetSource,
                path: nil,
                rawText: rawText
            )
        } else {
            return nil
        }
        guard let data = try? JSONEncoder().encode(descriptor),
              let json = String(data: data, encoding: .utf8) else { return nil }
        lastAppliedPresetJSON = json
        return json
    }

    /// Відновлює у вікні останній застосований пресет — лише UI: рушій свій стан
    /// уже відновив через PresetPersistence, тому вотчер parsed гаситься на один цикл.
    private func restoreLastAppliedPresetUI() {
        guard parsed.isEmpty else { return }

        if let data = lastAppliedPresetJSON.data(using: .utf8),
           let descriptor = try? JSONDecoder().decode(LastAppliedDescriptor.self, from: data) {
            if let text = descriptor.rawText, !text.isEmpty {
                suppressNextAutoApply = true
                if !applyCustomPreset(text: text, name: descriptor.name ?? "", persist: false, autoApply: false) {
                    suppressNextAutoApply = false
                }
            } else if let path = descriptor.path, !path.isEmpty {
                suppressNextAutoApply = true
                let isParametric = path.contains("ParametricEQ.txt")
                let candidate = SearchCandidate(
                    path: path,
                    name: isParametric ? "ParametricEQ.txt" : "README.md",
                    display: descriptor.name ?? path,
                    isParametric: isParametric
                )
                Task {
                    await importCandidate(candidate)
                    // Невдалий імпорт не ставить parsed — повертаємо вотчер до звичайної роботи
                    if parsed.isEmpty { suppressNextAutoApply = false }
                }
            }
        } else if !lastCustomPresetText.isEmpty {
            // Легасі-міграція: до появи дескриптора зберігався лише custom-імпорт
            suppressNextAutoApply = true
            if !applyCustomPreset(
                text: lastCustomPresetText,
                name: lastCustomPresetName,
                persist: false,
                autoApply: false
            ) {
                suppressNextAutoApply = false
            }
        }
    }

    private func setupEQRoutingIfNeeded() {
        Task { @MainActor in
            let router = AudioRouter.shared

            // Оновлюємо список пристроїв
            await router.refreshDevices()

            // BlackHole-only routing
            if let blackHoleInput = router.inputDevices.first(where: { $0.name.lowercased().contains("blackhole") }) {
                router.selectInputDevice(blackHoleInput)
                let preferredOutput = router.outputDevices
                    .first(where: { $0.name.lowercased().contains("scarlett") }) ??
                    router.outputDevices.first(where: { !$0.name.lowercased().contains("blackhole") })
                if let out = preferredOutput {
                    router.selectOutputDevice(out)
                    router.setAsDefaultOutputDevice(blackHoleInput)
                    NotificationCenter.default.post(name: NSNotification.Name("StartAudioEngine"), object: nil)
                } else {
                    dlog("❌ No physical output device found", category: .network)
                }
            } else {
                dlog("❌ BlackHole not found. Please install BlackHole 2ch.", category: .network)
            }
        }
    }

    private func parseAutoEQ(text: String) -> [ParsedBand] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Try modern table format first (Fixed Band EQs section)
        if trimmed.contains("### Fixed Band EQ") {
            let bands = parseFixedBandTable(text: trimmed, bands: bandMode == .ten ? 10 : 31)
            if !bands.isEmpty {
                return bands
            }
        }

        // Try old inline format (GraphicEQ: or FixedBandEQ:)
        if trimmed.contains("GraphicEQ:") || trimmed.contains("FixedBandEQ:") {
            return parseGraphicEQ(text: trimmed)
        }

        return []
    }

    private func parseEqualizerAPOFormat(text: String) -> (bands: [ParsedBand], preamp: Double?) {
        var bands: [ParsedBand] = []
        var preamp: Double?

        let filterPattern = #"Filter\s+\d+\s*:\s*ON\s+(\w+)\s+Fc\s+([\d.]+)\s*Hz\s+Gain\s+(-?[\d.]+)\s*dB\s+Q\s+([\d.]+)"#
        let preampPattern = #"Preamp\s*:\s*(-?[\d.]+)\s*dB"#

        if let regex = try? NSRegularExpression(pattern: preampPattern, options: .caseInsensitive) {
            let nsRange = NSRange(text.startIndex..., in: text)
            if let match = regex.firstMatch(in: text, range: nsRange),
               let r = Range(match.range(at: 1), in: text),
               let v = Double(text[r]) {
                preamp = v
            }
        }

        guard let regex = try? NSRegularExpression(pattern: filterPattern, options: .caseInsensitive) else {
            return ([], preamp)
        }

        let nsRange = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: nsRange)
        for m in matches {
            guard m.numberOfRanges >= 5,
                  let typeR = Range(m.range(at: 1), in: text),
                  let fcR = Range(m.range(at: 2), in: text),
                  let gainR = Range(m.range(at: 3), in: text),
                  let qR = Range(m.range(at: 4), in: text),
                  let fc = Double(text[fcR]),
                  let gain = Double(text[gainR]),
                  let q = Double(text[qR]) else { continue }

            let type = mapAPOFilterType(String(text[typeR]))
            bands.append(ParsedBand(freq: fc, gain: gain, q: q, type: type))
        }

        return (bands, preamp)
    }

    private func mapAPOFilterType(_ token: String) -> FilterType {
        let upper = token.uppercased()
        switch upper {
        case "BELL",
             "PEQ",
             "PK": return .peak
        case "LOWSHELF",
             "LS",
             "LSC": return .lowShelf
        case "HIGHSHELF",
             "HS",
             "HSC": return .highShelf
        case "LOWPASS",
             "LP",
             "LPQ": return .lowPass
        case "HIGHPASS",
             "HP",
             "HPQ": return .highPass
        case "AP": return .allPass
        case "BP": return .bandPass
        case "NO",
             "NOTCH": return .notch
        default: return .peak
        }
    }

    private func parseGraphicEQ(text: String) -> [ParsedBand] {
        // Expect format like: "GraphicEQ: 31.5 -5; 63 -4.3; 125 -3; ..." or "FixedBandEQ: ..."
        let payload: Substring
        if let r = text.range(of: "GraphicEQ:") {
            payload = text[r.upperBound...]
        } else if let r = text.range(of: "FixedBandEQ:") {
            payload = text[r.upperBound...]
        } else {
            return []
        }

        let parts = payload.split(separator: ";")
        var result: [ParsedBand] = []
        for p in parts {
            let toks = p.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ")
            if toks.count >= 2, let f = Double(toks[0]), let g = Double(toks[1]) {
                result.append(ParsedBand(freq: f, gain: g))
            }
        }
        return result
    }

    private func parsePreamp(text: String) -> Double? {
        // First, try to find preamp in Fixed Band EQ section
        if let range = text.range(of: "### Fixed Band EQ", options: .caseInsensitive) {
            let startIndex = range.lowerBound
            let endIndex = text.index(
                startIndex,
                offsetBy: min(500, text.distance(from: startIndex, to: text.endIndex))
            )
            let fixedBandSection = String(text[startIndex..<endIndex])

            // Pattern: "apply preamp of **-X.X dB**" or "apply preamp of -X.X dB"
            let pattern1 = "apply preamp of \\*\\*(-?\\d+\\.?\\d*)\\s*dB\\*\\*"
            if let regex = try? NSRegularExpression(pattern: pattern1, options: .caseInsensitive) {
                let nsRange = NSRange(fixedBandSection.startIndex..., in: fixedBandSection)
                if let match = regex.firstMatch(in: fixedBandSection, range: nsRange),
                   let valueRange = Range(match.range(at: 1), in: fixedBandSection) {
                    if let value = Double(fixedBandSection[valueRange]) {
                        return value
                    }
                }
            }
        }

        // Fallback: try to find preamp in the target profile section
        var searchText = text
        for variant in targetProfileVariants {
            if let range = text.range(of: variant, options: .caseInsensitive) {
                let startIndex = range.lowerBound
                let endIndex = text.index(
                    startIndex,
                    offsetBy: min(500, text.distance(from: startIndex, to: text.endIndex))
                )
                searchText = String(text[startIndex..<endIndex])
                break
            }
        }

        // Look for "Preamp: -X.X dB" pattern
        let pattern2 = "Preamp:\\s*(-?\\d+\\.?\\d*)\\s*dB"
        if let regex = try? NSRegularExpression(pattern: pattern2, options: .caseInsensitive) {
            let nsRange = NSRange(searchText.startIndex..., in: searchText)
            if let match = regex.firstMatch(in: searchText, range: nsRange),
               let valueRange = Range(match.range(at: 1), in: searchText) {
                if let value = Double(searchText[valueRange]) {
                    return value
                }
            }
        }

        return nil
    }

    /// Парсить параметричний EQ в структуровані фільтри для EQProcessor
    private func parseParametricFilters(text: String) -> [EQProcessor.ParametricFilter] {
        var filters: [EQProcessor.ParametricFilter] = []
        let lines = text.components(separatedBy: .newlines)

        // Find the target profile section
        let targetSectionStart = lines.firstIndex { line in
            targetProfileVariants.contains { line.localizedCaseInsensitiveContains($0) }
        }

        // Extract lines after target profile mention
        let relevantLines: [String]
        if let startIdx = targetSectionStart {
            let endIdx = min(startIdx + 100, lines.count)
            relevantLines = Array(lines[startIdx..<endIdx])
        } else {
            relevantLines = lines
        }

        // Parse the parametric EQ table
        var started = false
        var lineCount = 0

        for line in relevantLines {
            lineCount += 1
            if lineCount > 100 { break }

            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            // Зупиняємося на наступній секції
            if trimmed.hasPrefix("###"), started, !trimmed.contains("Fixed Band") {
                break
            }

            if trimmed.hasPrefix("|") {
                started = true
                if trimmed.contains("Frequency") || trimmed.contains("Type") || trimmed.contains("Fc") { continue }
                if trimmed.contains("---") { continue }

                let cols = trimmed.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                if cols.count >= 5 {
                    let typeStr = cols[1]
                    let fcStr = cols[2].replacingOccurrences(of: ",", with: "")
                    let qStr = cols[3].replacingOccurrences(of: ",", with: "")
                    let gainStr = cols[4].replacingOccurrences(of: "dB", with: "").replacingOccurrences(
                        of: ",",
                        with: ""
                    ).trimmingCharacters(in: .whitespaces)

                    if let fc = Double(fcStr), let q = Double(qStr), let gain = Double(gainStr) {
                        let type = parseFilterType(typeStr)
                        filters.append(EQProcessor.ParametricFilter(type: type, frequency: fc, q: q, gain: gain))
                    }
                }
            }
        }

        return filters
    }

    private func parseFilterType(_ str: String) -> EQProcessor.ProcessorFilterType {
        let lower = str.lowercased()
        if lower.contains("pk") || lower.contains("peaking") {
            return .peaking
        } else if lower.contains("lsh") || lower.contains("low shelf") || lower.contains("lowshelf") {
            return .lowShelf
        } else if lower.contains("hsh") || lower.contains("high shelf") || lower.contains("highshelf") {
            return .highShelf
        } else if lower.contains("lpf") || lower.contains("low pass") {
            return .lowPass
        } else if lower.contains("hpf") || lower.contains("high pass") {
            return .highPass
        }
        return .peaking
    }

    private func parseFixedBandTable(text: String, bands: Int) -> [ParsedBand] {
        // Шукаємо Fixed Band EQ секцію
        var searchText = text

        // Знаходимо "### Fixed Band EQ" секцію
        if let range = text.range(of: "### Fixed Band EQ", options: .caseInsensitive) {
            let startIndex = range.lowerBound
            let endIndex = text.index(
                startIndex,
                offsetBy: min(1500, text.distance(from: startIndex, to: text.endIndex))
            )
            searchText = String(text[startIndex..<endIndex])
        } else {
            return []
        }

        let lines = searchText.components(separatedBy: .newlines)
        var result: [ParsedBand] = []
        var started = false
        var lineCount = 0

        for line in lines {
            lineCount += 1
            if lineCount > 100 { break }

            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            // Зупиняємося на наступній секції
            if trimmed.hasPrefix("###"), started, !trimmed.contains("Fixed Band") {
                break
            }

            if trimmed.hasPrefix("|") {
                // Пропускаємо заголовок та роздільник
                if trimmed.contains("Type") || trimmed.contains("Fc") || trimmed.contains("Gain") { continue }
                if trimmed.contains("---") { continue }

                let cols = trimmed.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }

                // DEBUG для першого рядка (removed empty loop)

                // Таблиця: | # | Type | Fc (Hz) | Q | Gain (dB) |
                // Після split по "|": cols[0]="#", cols[1]="Type", cols[2]="Fc", cols[3]="Q", cols[4]="Gain"
                if cols.count >= 5 {
                    let fStr = cols[2].replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "Hz", with: "")
                        .trimmingCharacters(in: .whitespaces)
                    let gStr = cols[4].replacingOccurrences(of: "dB", with: "").replacingOccurrences(of: ",", with: "")
                        .trimmingCharacters(in: .whitespaces)

                    if result.isEmpty {}

                    if let freq = Double(fStr), let gain = Double(gStr) {
                        result.append(ParsedBand(freq: freq, gain: gain))
                        started = true // Встановлюємо started тільки після успішного парсингу

                    } else if result.isEmpty {}
                }
            }
        }

        // Filter by band count if specified
        if bands == 10, result.count > 10 {
            result = Array(result.prefix(10))
        } else if bands == 31, result.count > 31 {
            result = Array(result.prefix(31))
        }

        return result
    }

    /// Застосовує корекцію JM-1 до Harman значень
    private func applyJM1Correction(harmanBands: [ParsedBand]) -> [ParsedBand] {
        harmanBands.map { band in
            let jm1Target = EQProcessor.getJM1TargetGain(frequency: band.freq)
            let harmanTarget = EQProcessor.getHarmanTargetGain(frequency: band.freq)
            let targetDiff = jm1Target - harmanTarget
            let correctedGain = band.gain + targetDiff
            return ParsedBand(freq: band.freq, gain: correctedGain)
        }
    }

    /// Парсить FixedBandEQ.txt файл з локального AutoEq repo
    /// Формат: Filter 1: ON PK Fc 31 Hz Gain 6.4 dB Q 1.41
    private func parseFixedBandEQFile(fromPath path: String) -> (bands: [ParsedBand], preamp: Double?)? {
        // Визначаємо шлях до AutoEq repo відносно home directory
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let projectPath = homeDir + "/CascadeProjects/SystemEQ for Mac"
        let fullPath = projectPath + "/AutoEq/" + path

        guard let content = try? String(contentsOfFile: fullPath, encoding: .utf8) else {
            return nil
        }

        var preamp: Double?
        var bands: [ParsedBand] = []

        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Парсимо Preamp: -7.1 dB
            if trimmed.hasPrefix("Preamp:") {
                let parts = trimmed.split(separator: " ")
                if parts.count >= 2,
                   let value = Double(parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "dB "))) {
                    preamp = value
                }
                continue
            }

            // Парсимо Filter 1: ON PK Fc 31 Hz Gain 6.4 dB Q 1.41
            if trimmed.hasPrefix("Filter"), trimmed.contains("Fc"), trimmed.contains("Gain") {
                let components = trimmed.split(separator: " ")
                var freq: Double?
                var gain: Double?

                for (i, comp) in components.enumerated() {
                    if comp == "Fc", i + 1 < components.count {
                        freq = Double(components[i + 1])
                    }
                    if comp == "Gain", i + 1 < components.count {
                        gain = Double(components[i + 1])
                    }
                }

                if let f = freq, let g = gain {
                    bands.append(ParsedBand(freq: f, gain: g))
                }
            }
        }

        dlog(
            "DEBUG: Parsed FixedBandEQ.txt: \(bands.count) bands, preamp: \(preamp?.description ?? "nil")",
            category: .network
        )
        return bands.isEmpty ? nil : (bands: bands, preamp: preamp)
    }

    /// Парсить GraphicEQ.txt файл з локального AutoEq repo
    /// Формат: GraphicEQ: 20 -0.2; 21 -0.2; 22 -0.2; ...
    private func parseGraphicEQFile(fromPath path: String) -> [ParsedBand]? {
        // Визначаємо шлях до AutoEq repo відносно home directory
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let projectPath = homeDir + "/CascadeProjects/SystemEQ for Mac"
        let fullPath = projectPath + "/AutoEq/" + path

        guard let content = try? String(contentsOfFile: fullPath, encoding: .utf8) else {
            return nil
        }

        var bands: [ParsedBand] = []

        // Знаходимо рядок що починається з "GraphicEQ:"
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("GraphicEQ:") {
                // Витягуємо все після "GraphicEQ:"
                let dataStr = trimmed.dropFirst("GraphicEQ:".count).trimmingCharacters(in: .whitespaces)

                // Розбиваємо по ";"
                let pairs = dataStr.split(separator: ";")
                for pair in pairs {
                    let components = pair.trimmingCharacters(in: .whitespaces).split(separator: " ")
                    if components.count == 2,
                       let freq = Double(components[0]),
                       let gain = Double(components[1]) {
                        bands.append(ParsedBand(freq: freq, gain: gain))
                    }
                }
                break
            }
        }

        return bands.isEmpty ? nil : bands
    }

    // MARK: - Favorites Management

    private func loadFavoritesFromStorage() {
        guard !favoritesData.isEmpty else {
            favorites = []
            return
        }

        do {
            favorites = try JSONDecoder().decode([FavoritePreset].self, from: favoritesData)
        } catch {
            dlog("Failed to decode favorites: \(error)", category: .network)
            favorites = []
        }
    }

    private func saveFavoritesToStorage() {
        do {
            favoritesData = try JSONEncoder().encode(favorites)
        } catch {
            dlog("Failed to encode favorites: \(error)", category: .network)
        }
    }

    private func isFavorite(_ candidate: SearchCandidate) -> Bool {
        favorites.contains { $0.path == candidate.path }
    }

    private func toggleFavoriteForCandidate(_ candidate: SearchCandidate) {
        if let index = favorites.firstIndex(where: { $0.path == candidate.path }) {
            favorites.remove(at: index)
        } else {
            let favorite = FavoritePreset(
                id: UUID().uuidString,
                name: candidate.display,
                source: Self.databaseSource(from: candidate),
                target: candidate.path.hasPrefix(Self.databaseCandidatePrefix) ? targetProfile : nil,
                path: candidate.path,
                timestamp: Date()
            )
            favorites.append(favorite)
        }
        saveFavoritesToStorage()
    }

    private func removeFavorite(_ favorite: FavoritePreset) {
        favorites.removeAll { $0.id == favorite.id }
        saveFavoritesToStorage()
    }

    /// Чи збережений поточний custom-пресет в обране (за іменем)
    private var isCurrentCustomFavorite: Bool {
        guard let name = activePresetName, !rawText.isEmpty else { return false }
        return favorites.contains { $0.rawText != nil && $0.name == name }
    }

    private var canToggleCurrentFavorite: Bool {
        activePresetPath != nil || (activePresetSource == "Custom" && !rawText.isEmpty)
    }

    private var isCurrentPresetFavorite: Bool {
        if let path = activePresetPath {
            return favorites.contains { $0.path == path }
        }
        return isCurrentCustomFavorite
    }

    private func toggleCurrentFavorite() {
        if let path = activePresetPath, let name = activePresetName {
            if let index = favorites.firstIndex(where: { $0.path == path }) {
                favorites.remove(at: index)
            } else {
                favorites.append(FavoritePreset(
                    id: UUID().uuidString,
                    name: name,
                    source: activePresetSource,
                    target: activePresetTarget,
                    path: path,
                    timestamp: Date()
                ))
            }
            saveFavoritesToStorage()
            return
        }

        toggleCurrentCustomFavorite()
    }

    /// Додати/прибрати поточний імпортований custom-пресет в обране
    private func toggleCurrentCustomFavorite() {
        guard let name = activePresetName, !rawText.isEmpty else { return }
        if let index = favorites.firstIndex(where: { $0.rawText != nil && $0.name == name }) {
            favorites.remove(at: index)
        } else {
            favorites.append(FavoritePreset(
                id: UUID().uuidString,
                name: name,
                source: activePresetSource,
                target: activePresetTarget,
                path: "custom:\(name)",
                timestamp: Date(),
                rawText: rawText,
                preamp: preampDB
            ))
        }
        saveFavoritesToStorage()
    }

    private func loadFavorite(_ favorite: FavoritePreset) async {
        // Custom-пресет: маємо повний текст, парсимо напряму
        if let raw = favorite.rawText, !raw.isEmpty {
            applyCustomPreset(text: raw, name: favorite.name, persist: true, autoApply: true)
            return
        }

        if favorite.path.hasPrefix(Self.databaseCandidatePrefix) {
            let candidate = SearchCandidate(
                path: favorite.path,
                name: "",
                display: favorite.name,
                isParametric: false
            )
            await importCandidate(candidate)
        } else if offlineIndex.contains(where: { entry in
            entry.pathReadme?.contains(favorite.path) == true ||
                entry.pathParametric?.contains(favorite.path) == true
        }) {
            let isParametric = favorite.path.contains("ParametricEQ.txt")
            let candidate = SearchCandidate(
                path: favorite.path,
                name: isParametric ? "ParametricEQ.txt" : "README.md",
                display: favorite.name,
                isParametric: isParametric
            )
            await importCandidate(candidate)
        }
    }
}
