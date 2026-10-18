import AppKit
import AVFoundation
import Combine
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

    typealias BandMode = AutoEQState.BandMode

    // MARK: - Localization

    @StateObject private var localization = LocalizationManager.shared

    // MARK: - Audio Engine (ObservableObject для реактивності)

    @StateObject private var audioEngine = AudioEngine.shared
    @State private var isTogglingEQ = false

    // MARK: - Active Preset Tracking

    @StateObject private var presetState = AutoEQState.shared

    /// Bass Boost low-shelf фільтр: піднімає тільки низькі частоти
    /// Частота зрізу: 200 Hz, slope: 12 dB/octave
    private func bassBoostForFrequency(_ freq: Double) -> Double {
        BassBoostCurve.gain(at: freq, amount: presetState.bassBoost)
    }

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
    @State private var draggingBandIndex: Int?
    @State private var hoveredBandIndex: Int?

    /// ✅ Import cache: prevents re-importing same preset and getting different values
    struct ImportCacheEntry {
        let input: AutoEQImportedPreset
        let text: String
        let name: String
        let source: String?
        let target: String?
        let path: String
    }

    @State private var importCache: [String: ImportCacheEntry] = [:]

    // MARK: - Favorites State

    @AppStorage("autoEQFavorites") private var favoritesData: Data = .init()
    @State private var favorites: [FavoritePreset] = []
    @State private var showFavorites: Bool = false

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

                if !presetState.parsed.isEmpty {
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
        .onDisappear {
            presetState.close()
            isSearching = false
        }
        .onReceive(presetState.$importError.compactMap(\.self)) { showImportError($0) }
        .onAppear {
            let session = presetState.open()
            // Defer state changes to next run loop to avoid "Publishing changes from within view updates"
            DispatchQueue.main.async {
                guard presetState.isOpen(session) else { return }
                // Load favorites from storage
                loadFavoritesFromStorage()

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
        if let presetName = presetState.activePresetName {
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
                            if let source = presetState.activePresetSource {
                                Text(source)
                            }
                            if let target = presetState.activePresetTarget {
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

                if isSearching || presetState.isImporting {
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
        if candidates.isEmpty, isSearching || presetState.isImporting {
            ProgressView()
                .frame(maxWidth: .infinity, alignment: .center)
        } else if !candidates.isEmpty {
            autoEQPanel {
                sectionHeader(
                    title: localization.localized(.autoEQTypeModelName),
                    systemImage: "magnifyingglass"
                )

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: AppSpacing.xs) {
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
                                    importCandidate(c)
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

            if let identity = presetState.previewIdentity, identity != presetState.appliedIdentity,
               let name = identity.name {
                Text(name)
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .firstTextBaseline) {
                Text(showingBandLabel)
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(.secondary)

                Spacer()

                if let p = presetState.preampDB {
                    Text(String(format: "%@: %+.1f dB", localization.localized(.autoEQPreamp), p))
                        .font(AppTypography.mono)
                        .foregroundStyle(.secondary)
                }
            }

            if let preparedImport = presetState.preparedImport, !presetState.importCurveEdited {
                let result = preparedImport.result(for: presetState.bandMode.audioEngineMode)
                Text(String(format: localization.localized(.autoEQFitSummary), result.rms, result.maximumError))
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(.secondary)
                if preparedImport.input.legacyPreamp {
                    Text(localization.localized(.autoEQLegacyPreamp)).font(AppTypography.bodySmall)
                }
                if result
                    .preampAdjusted || abs((presetState.preampDB ?? Double(result.preamp)) - Double(result.preamp)) >
                    0.05 {
                    Text(String(
                        format: localization.localized(.autoEQPreampAdjusted),
                        preparedImport.input.preamp ?? 0,
                        presetState.preampDB ?? Double(result.preamp)
                    ))
                    .font(AppTypography.bodySmall)
                }
                if presetState.importNeedsApply {
                    Text(localization.localized(.autoEQApplyReview)).font(AppTypography.bodySmall)
                        .foregroundStyle(.orange)
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
                .disabled(presetState.mapped.isEmpty || isSearching || presetState.isImporting)

                if !presetState.mapped.isEmpty {
                    Text(String(
                        format: localization.localized(.applyBandsCount),
                        presetState.mapped.count,
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

                    Text(String(format: "%.1f dB", presetState.bassBoost))
                        .font(AppTypography.mono)
                }

                Slider(value: Binding(
                    get: { presetState.bassBoost },
                    set: { presetState.setBassBoost($0) }
                ), in: 0...6, step: 0.5)
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
                                        loadFavorite(favorite)
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
            get: { presetState.bandMode },
            set: { selectBandMode($0) }
        )
    }

    private func selectBandMode(_ newMode: BandMode) {
        presetState.selectBandMode(newMode)
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

    static func fallbackIndexEntries(from data: Data) throws -> [OfflineIndexEntry] {
        guard let text = String(data: data, encoding: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }
        var map: [String: OfflineIndexEntry] = [:]
        let linkPattern = #"\[[^\n]+?\]\((\./[^\n]+?)\)(?:\s|$)"#
        let re = try NSRegularExpression(pattern: linkPattern, options: [])
        do {
            let nsr = NSRange(text.startIndex..<text.endIndex, in: text)
            re.enumerateMatches(in: text, options: [], range: nsr) { m, _, _ in
                guard let m, m.numberOfRanges >= 2, let r1 = Range(m.range(at: 1), in: text) else { return }
                let rel =
                    String(text[r1])
                let relPath = String(rel.dropFirst(2))
                guard let decodedRelPath = relPath.removingPercentEncoding else { return }
                let comps = decodedRelPath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
                guard comps.count == 3,
                      comps.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains(where: \.isNewline) }),
                      ["in-ear", "over-ear", "earbud"].contains(where: {
                          comps[1] == $0 || comps[1].hasSuffix(" " + $0)
                      })
                else { return }
                guard let lastSeg = comps.last else { return }
                guard !["md", "txt", "json", "csv", "png", "jpg", "jpeg", "pdf"].contains(
                    (lastSeg as NSString).pathExtension.lowercased()
                ) else { return }
                var guessedBrand = ""
                var guessedModel = lastSeg

                let words = lastSeg.split(separator: " ").map(String.init)
                if words.count >= 2 {
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

                let key = decodedRelPath

                let source = comps[0]
                let type = comps[1]
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
        let entries = Array(map.values).filter { $0.pathReadme != nil || $0.pathParametric != nil }
        guard !entries.isEmpty else { throw URLError(.cannotParseResponse) }
        return entries
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
            try Task.checkCancellation()
            let out = try Self.fallbackIndexEntries(from: data)
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
        presetState.mapped.enumerated().map { index, mb in
            let bassBoostValue = bassBoostForFrequency(mb.center)
            let total = min(max(mb.gain + bassBoostValue, -20), 20)
            return EQBand(id: index, frequency: Float(mb.center), gain: Float(total))
        }
    }

    private func mappedGainBinding(id: Int) -> Binding<Float> {
        Binding(
            get: {
                guard id < presetState.mapped.count else { return 0 }
                let mb = presetState.mapped[id]
                let total = mb.gain + bassBoostForFrequency(mb.center)
                return Float(min(max(total, -20), 20))
            },
            set: { newValue in
                guard id < presetState.mapped.count else { return }
                let bassBoostValue = bassBoostForFrequency(presetState.mapped[id].center)
                let rawGain = Double(newValue) - bassBoostValue
                let clamped = min(max(rawGain, -12), 12)
                let stepped = (clamped / 0.5).rounded() * 0.5
                if presetState.mapped[id].gain != stepped {
                    presetState.editBand(at: id, gain: stepped)
                }
            }
        )
    }

    private func barsBody() -> some View {
        GeometryReader { geo in
            let labelHeight: CGFloat = presetState.bandMode == .thirtyOne ? 28 : 18
            let dbAxisWidth: CGFloat = 32
            let topReserve: CGFloat = 18
            let maxH = max(160.0, geo.size.height - labelHeight - topReserve - 8)
            let bandCount = CGFloat(presetState.mapped
                .isEmpty ? (presetState.bandMode == .thirtyOne ? 31 : 10) : presetState.mapped.count)
            let availableWidth = geo.size.width - dbAxisWidth - 6
            let minSpacing: CGFloat = presetState.bandMode == .thirtyOne ? 3 : 5
            let minBarWidth: CGFloat = presetState.bandMode == .thirtyOne ? 8 : 14
            let spacing: CGFloat = max(
                minSpacing,
                min(10, (availableWidth - bandCount * minBarWidth) / max(1, bandCount - 1))
            )
            let hitWidth: CGFloat = max(minBarWidth, (availableWidth - spacing * (bandCount - 1)) / bandCount)
            let barWidth: CGFloat = presetState.bandMode == .thirtyOne ? max(hitWidth * 0.65, hitWidth - 4) : 14
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
                        ForEach(Array(presetState.mapped.enumerated()), id: \.element.id) { index, mb in
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
        let thumbSize: CGFloat = presetState.bandMode == .thirtyOne ? 12 : 14
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
                .font(presetState.bandMode == .thirtyOne ? Font.system(size: 16) : AppTypography.labelSmall)
                .foregroundStyle(isHovered || isActive ? .primary : .secondary)
                .fontWeight(isHovered || isActive ? .semibold : .regular)
                .fixedSize()
                .padding(.top, 4)
                .rotationEffect(.degrees(presetState.bandMode == .thirtyOne ? -45 : 0))
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
                guard index < presetState.mapped.count else { return }
                if draggingBandIndex != index { draggingBandIndex = index }
                let yInBar = value.location.y - topReserve
                let zeroY = maxH / 2
                let offsetFromZero = zeroY - yInBar
                let bassBoostValue = bassBoostForFrequency(presetState.mapped[index].center)
                let rawTotal = Double(offsetFromZero / maxH) * 24.0
                let rawGain = rawTotal - bassBoostValue
                let clamped = min(max(rawGain, -12), 12)
                let stepped = (clamped / 0.5).rounded() * 0.5
                if presetState.mapped[index].gain != stepped {
                    presetState.editBand(at: index, gain: stepped)
                }
            }
            .onEnded { _ in
                draggingBandIndex = nil
            }
    }

    // MARK: - Search helpers

    private var normalizedQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var showingBandLabel: String {
        presetState.bandMode == .ten ? localization.localized(.bands10) : localization.localized(.bands31)
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
        let queryTokens = q.split(separator: " ").map(String.init)
        let scored = input.map { candidate in
            let sanitizedCandidate = sanitize(candidate.display + " " + candidate.path)
            var score = 0
            for token in queryTokens {
                if sanitizedCandidate.contains(token) { score += 2 }
                if sanitizedCandidate.hasPrefix(token) { score += 1 }
            }
            if candidate.isParametric { score += 1 }
            return (candidate: candidate, score: score)
        }
        return scored.sorted { lhs, rhs in
            lhs.score == rhs.score
                ? lhs.candidate.display.count < rhs.candidate.display.count
                : lhs.score > rhs.score
        }.map(\.candidate)
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
    private func importCandidate(_ candidate: SearchCandidate, preservePlayback: Bool = false) {
        let session = presetState.sessionToken
        Task {
            await presetState.fetch(session: session) { request in
                await fetchCandidate(candidate, preservePlayback: preservePlayback, request: request)
            }
        }
    }

    @MainActor
    private func fetchCandidate(
        _ candidate: SearchCandidate,
        preservePlayback: Bool,
        request: AutoEQState.Request
    ) async {
        defer { presetState.finishFetch(request) }
        guard presetState.isCurrent(request) else { return }
        searchError = nil
        if let cached = importCache[candidate.path] {
            startPreparedImport(
                cached.input,
                text: cached.text,
                name: cached.name,
                source: cached.source,
                target: cached.target,
                path: cached.path,
                autoApply: !preservePlayback,
                preservePlayback: preservePlayback,
                request: request
            )
            return
        }
        if candidate.path.hasPrefix(Self.databaseCandidatePrefix) {
            guard let id = databaseHeadphoneID(from: candidate) else {
                showImportError(AutoEQImportError.invalidSource)
                return
            }
            importDatabaseCandidate(candidate, headphoneID: id, preservePlayback: preservePlayback, request: request)
            return
        }
        do {
            let localRoot = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("CascadeProjects/SystemEQ for Mac/AutoEq").resolvingSymlinksInPath()
            if let entry = offlineIndex
                .first(where: { $0.pathReadme == candidate.path || $0.pathParametric == candidate.path }) {
                for path in [entry.pathParametric, entry.pathFixedBandEQ, entry.pathGraphicEQ, entry.pathReadme]
                    .compactMap(\.self) {
                    let file = localRoot.appendingPathComponent(path).resolvingSymlinksInPath()
                    guard file.path.hasPrefix(localRoot.path + "/") else { throw AutoEQImportError.invalidSource }
                    if FileManager.default.fileExists(atPath: file.path) {
                        let text = try String(contentsOf: file, encoding: .utf8)
                        guard presetState.isCurrent(request) else { return }
                        try acceptImportedText(
                            text,
                            candidate: candidate,
                            resolvedPath: path,
                            preservePlayback: preservePlayback,
                            request: request
                        )
                        return
                    }
                }
            }
            if let text = readmeCache[candidate.path] {
                try acceptImportedText(
                    text,
                    candidate: candidate,
                    resolvedPath: candidate.path,
                    preservePlayback: preservePlayback,
                    request: request
                )
                return
            }
            let path = candidate.path.removingPercentEncoding ?? candidate.path
            guard !path.hasPrefix("/"), !path.split(separator: "/").contains(".."),
                  let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                  let url = URL(string: AppConstants.URLs.autoEQRawBase + encoded)
            else { throw AutoEQImportError.invalidSource }
            let (data, response) = try await legacyRepository.session.data(from: url)
            try Task.checkCancellation()
            guard presetState.isCurrent(request) else { return }
            guard let http = response as? HTTPURLResponse else { throw AutoEQImportError.invalidSource }
            var resolvedPath = candidate.path
            var text: String
            if http.statusCode == 200, let decoded = String(data: data, encoding: .utf8) {
                text = decoded
            } else if http.statusCode == 404, candidate.isParametric {
                resolvedPath = candidate.path.split(separator: "/").dropLast().joined(separator: "/") + "/README.md"
                guard let encodedFallback = resolvedPath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                      let fallbackURL = URL(string: AppConstants.URLs.autoEQRawBase + encodedFallback)
                else { throw AutoEQImportError.invalidSource }
                let (fallback, fallbackResponse) = try await legacyRepository.session.data(from: fallbackURL)
                try Task.checkCancellation()
                guard presetState.isCurrent(request) else { return }
                guard (fallbackResponse as? HTTPURLResponse)?.statusCode == 200,
                      let decoded = String(data: fallback, encoding: .utf8)
                else { throw AutoEQImportError.invalidSource }
                text = decoded
            } else { throw AutoEQImportError.invalidSource }
            try acceptImportedText(
                text,
                candidate: candidate,
                resolvedPath: resolvedPath,
                preservePlayback: preservePlayback,
                request: request
            )
            readmeCache[resolvedPath] = text
        } catch is CancellationError {
            return
        } catch {
            if presetState.isCurrent(request) { showImportError(error) }
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
        let text: String
        do {
            guard let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                  size <= 1_000_000 else { throw AutoEQImportError.invalidSource }
            text = try String(contentsOf: url, encoding: .utf8)
        } catch {
            showImportError(error)
            return
        }

        let presetName = url.deletingPathExtension().lastPathComponent
        applyCustomPreset(text: text, name: presetName, persist: true, autoApply: true)
    }

    /// Парсить і застосовує custom .txt пресет. Використовується при імпорті,
    /// відновленні при старті та завантаженні з обраних.
    @discardableResult
    private func applyCustomPreset(text: String, name: String, persist: Bool, autoApply: Bool) -> Bool {
        let request = presetState.beginRequest()
        do {
            let input = try AutoEQImportParser.parse(text)
            startPreparedImport(
                input,
                text: text,
                name: name,
                source: "Custom",
                target: nil,
                path: nil,
                autoApply: autoApply,
                preservePlayback: !autoApply,
                request: request
            )
            return true
        } catch {
            presetState.finishFetch(request)
            showImportError(error)
            return false
        }
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
        importCandidate(bestMatch)
    }

    @MainActor
    private func importDatabaseCandidate(
        _ candidate: SearchCandidate,
        headphoneID: Int,
        preservePlayback: Bool = false,
        request: AutoEQState.Request
    ) {
        guard presetState.isCurrent(request) else { return }
        do {
            let imported = try databaseService.loadCanonical(headphoneID: headphoneID)
            let preset = imported.preset
            let name = candidate.display.components(separatedBy: " · ").first ?? candidate.display
            let source = !preset.author.isEmpty ? preset.author : preset.source
            let entry = ImportCacheEntry(
                input: imported.input,
                text: "EQDatabase.db",
                name: name,
                source: source,
                target: preset.targetCurve,
                path: candidate.path
            )
            importCache[candidate.path] = entry
            startPreparedImport(
                entry.input,
                text: entry.text,
                name: name,
                source: source,
                target: entry.target,
                path: entry.path,
                autoApply: !preservePlayback,
                preservePlayback: preservePlayback,
                request: request
            )
        } catch { showImportError(error) }
    }

    @MainActor

    private func showImportError(_ error: Error) {
        if let value = error as? AutoEQImportError, case let .invalidLine(line) = value {
            searchError = String(format: localization.localized(.autoEQImportLineError), line)
        } else if error as? AutoEQImportError == .insufficientHeadroom {
            searchError = localization.localized(.autoEQHeadroomError)
        } else {
            searchError = localization.localized(.autoEQImportFileError)
        }
    }

    private func acceptImportedText(
        _ text: String,
        candidate: SearchCandidate,
        resolvedPath: String,
        preservePlayback: Bool,
        request: AutoEQState.Request
    ) throws {
        guard presetState.isCurrent(request) else { return }
        let input = try AutoEQImportParser.parse(text)
        let components = resolvedPath.split(separator: "/")
        let source = (components.first == "results" ? components.dropFirst().first : components.first).map(String.init)
        let displayParts = candidate.display.components(separatedBy: " / ")
        let name = displayParts.count > 1 ? displayParts.dropFirst().joined(separator: " / ")
            : candidate.display.components(separatedBy: " · ").first ?? candidate.display
        importCache[candidate.path] = ImportCacheEntry(
            input: input,
            text: text,
            name: name,
            source: source,
            target: nil,
            path: resolvedPath
        )
        startPreparedImport(
            input,
            text: text,
            name: name,
            source: source,
            target: nil,
            path: resolvedPath,
            autoApply: !preservePlayback,
            preservePlayback: preservePlayback,
            request: request
        )
    }

    private func startPreparedImport(
        _ input: AutoEQImportedPreset,
        text: String,
        name: String,
        source: String?,
        target: String?,
        path: String?,
        autoApply: Bool,
        preservePlayback: Bool,
        request: AutoEQState.Request? = nil
    ) {
        presetState.startImport(
            input,
            identity: AutoEQState.Identity(name: name, source: source, path: path, rawText: text, target: target),
            autoApply: autoApply,
            preservePlayback: preservePlayback,
            request: request
        )
    }

    private func applyToAudioEngine() {
        presetState.apply()
    }

    private func restoreLastAppliedPresetUI() {
        guard presetState.preparedImport == nil, let descriptor = presetState.appliedIdentity else { return }
        if let text = descriptor.rawText, descriptor.path == nil, descriptor.source == "Custom", !text.isEmpty {
            _ = applyCustomPreset(text: text, name: descriptor.name ?? "", persist: false, autoApply: false)
        } else if let path = descriptor.path, !path.isEmpty {
            let parametric = path.contains("ParametricEQ.txt")
            let candidate = SearchCandidate(
                path: path,
                name: parametric ? "ParametricEQ.txt" : "README.md",
                display: descriptor.name ?? path,
                isParametric: parametric
            )
            importCandidate(candidate, preservePlayback: true)
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
        guard let name = presetState.activePresetName, !presetState.appliedText.isEmpty else { return false }
        return favorites.contains { $0.rawText != nil && $0.name == name }
    }

    private var canToggleCurrentFavorite: Bool {
        presetState
            .activePresetPath != nil || (presetState.activePresetSource == "Custom" && !presetState.appliedText.isEmpty)
    }

    private var isCurrentPresetFavorite: Bool {
        if let path = presetState.activePresetPath {
            return favorites.contains { $0.path == path }
        }
        return isCurrentCustomFavorite
    }

    private func toggleCurrentFavorite() {
        if let path = presetState.activePresetPath, let name = presetState.activePresetName {
            if let index = favorites.firstIndex(where: { $0.path == path }) {
                favorites.remove(at: index)
            } else {
                favorites.append(FavoritePreset(
                    id: UUID().uuidString,
                    name: name,
                    source: presetState.activePresetSource,
                    target: presetState.activePresetTarget,
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
        guard let name = presetState.activePresetName, !presetState.appliedText.isEmpty else { return }
        if let index = favorites.firstIndex(where: { $0.rawText != nil && $0.name == name }) {
            favorites.remove(at: index)
        } else {
            favorites.append(FavoritePreset(
                id: UUID().uuidString,
                name: name,
                source: presetState.activePresetSource,
                target: presetState.activePresetTarget,
                path: "custom:\(name)",
                timestamp: Date(),
                rawText: presetState.appliedText,
                preamp: presetState.preampDB
            ))
        }
        saveFavoritesToStorage()
    }

    private func loadFavorite(_ favorite: FavoritePreset) {
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
            importCandidate(candidate)
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
            importCandidate(candidate)
        }
    }
}
