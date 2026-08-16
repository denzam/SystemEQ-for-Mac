//
//  AudioEngine.swift
//  SystemEQ for Mac
//
//  Facade for CoreAudioEngine
//  Provides ObservableObject state for SwiftUI views
//
//

import Combine
import CoreAudio
import Foundation
import SwiftUI

// MARK: - EQ Band Mode

public enum EQBandMode: String, CaseIterable, Codable {
    case tenBand = "10-band"
    case thirtyOneBand = "31-band"

    var bandCount: Int {
        switch self {
        case .tenBand: 10
        case .thirtyOneBand: 31
        }
    }

    var frequencies: [Float] {
        switch self {
        case .tenBand:
            [31.5, 63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
        case .thirtyOneBand:
            [
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
        }
    }
}

// MARK: - EQ Band

struct EQBand: Identifiable, Codable {
    let id: Int
    let frequency: Float // Hz
    var gain: Float // dB (-20 to +20)

    init(id: Int, frequency: Float, gain: Float = 0.0) {
        self.id = id
        self.frequency = frequency
        self.gain = max(-20.0, min(20.0, gain))
    }
}

// MARK: - Audio Engine Facade

public final class AudioEngine: ObservableObject {
    // MARK: - Published Properties

    @Published var isRunning: Bool = false
    @Published var isEnabled: Bool = true
    @Published var bandMode: EQBandMode = .tenBand {
        didSet {
            if bandMode != oldValue {
                DispatchQueue.main.async { [weak self] in
                    self?.setupEQBands()
                    self?.syncToCoreAudioEngineImmediate()
                    self?.persistCurrentPlaybackState()
                }
            }
        }
    }

    @Published var bands: [EQBand] = []
    @Published var preampGain: Float = 0.0
    @Published var outputBoostGain: Float

    private var cancellables = Set<AnyCancellable>()

    // Debounces rapid slider drags so we rebuild the filter chain at most
    // ~every 20 ms instead of once per UI event (60+ Hz). Final gesture
    // value is always applied via the trailing edge of the work item.
    private var syncDebounceWorkItem: DispatchWorkItem?
    private let syncDebounceInterval: DispatchTimeInterval = .milliseconds(20)
    private var persistenceDebounceWorkItem: DispatchWorkItem?
    private let persistenceDebounceInterval: DispatchTimeInterval = .milliseconds(250)
    private let defaults: UserDefaults
    private let enableRouting: (Bool) -> Bool
    private let disableRouting: (Bool) -> Void
    private static let outputBoostGainKey = "outputBoostGain"

    // MARK: - Singleton

    public static let shared = AudioEngine()

    // MARK: - Initialization

    init(
        defaults: UserDefaults = .standard,
        enableRouting: @escaping (Bool) -> Bool = { persistEnabledStateOnFailure in
            AudioRouter.shared.enableEQRouting(
                persistEnabledStateOnFailure: persistEnabledStateOnFailure
            )
        },
        disableRouting: @escaping (Bool) -> Void = { persistEnabledState in
            AudioRouter.shared.disableEQRouting(persistEnabledState: persistEnabledState)
        }
    ) {
        self.defaults = defaults
        self.enableRouting = enableRouting
        self.disableRouting = disableRouting
        outputBoostGain = Self.sanitizedOutputBoost(defaults.float(forKey: Self.outputBoostGainKey))
        setupEQBands()
        setupBindings()
        engineLog("AudioEngine Facade initialized with \(bandMode.rawValue)", level: .info)
    }

    private func setupBindings() {
        // Bind CoreAudioEngine states to this facade
        CoreAudioEngine.shared.$isRunning
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                DispatchQueue.main.async { self?.isRunning = value }
            }
            .store(in: &cancellables)

        CoreAudioEngine.shared.$isEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                DispatchQueue.main.async { self?.isEnabled = value }
            }
            .store(in: &cancellables)

        // ⚡ Peak levels are deliberately NOT republished here. The App root
        // holds this object as @StateObject, so any @Published change re-evaluates
        // every window's body 10-20×/s — that was the main-thread CPU storm.
        // Meter UIs poll CoreAudioEngine.shared.peakMeter directly (RoutingView).
    }

    // MARK: - Setup

    private func setupEQBands() {
        let frequencies = bandMode.frequencies
        let previous = bands
        bands = frequencies.enumerated().map { index, freq in
            let gain = Self.interpolatedGain(at: freq, from: previous)
            return EQBand(id: index, frequency: freq, gain: gain)
        }
    }

    /// 🔧 `bandMode`'s didSet rebuilds `bands` only on the next main-loop turn; callers
    /// that touch `bands` in the same turn must force the rebuild first. No-op when in sync.
    func syncBandsToMode() {
        guard bands.count != bandMode.bandCount else { return }
        setupEQBands()
    }

    private static func interpolatedGain(at freq: Float, from previous: [EQBand]) -> Float {
        guard !previous.isEmpty else { return 0.0 }
        if let exact = previous.first(where: { abs($0.frequency - freq) < 0.5 }) {
            return exact.gain
        }
        let sorted = previous.sorted { $0.frequency < $1.frequency }
        if let first = sorted.first, freq <= first.frequency { return first.gain }
        if let last = sorted.last, freq >= last.frequency { return last.gain }
        for i in 0..<(sorted.count - 1) {
            let lo = sorted[i], hi = sorted[i + 1]
            if freq >= lo.frequency, freq <= hi.frequency {
                let logLo = log10(lo.frequency)
                let logHi = log10(hi.frequency)
                let logF = log10(freq)
                let t = Float((logF - logLo) / (logHi - logLo))
                return lo.gain + (hi.gain - lo.gain) * t
            }
        }
        return 0.0
    }

    private func syncToCoreAudioEngine() {
        syncDebounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let gains = self.bands.map(\.gain)
            switch self.bandMode {
            case .tenBand:
                CoreAudioEngine.shared.applyFixedBandEQ(
                    gains,
                    preamp: self.preampGain,
                    outputBoost: self.outputBoostGain
                )
            case .thirtyOneBand:
                CoreAudioEngine.shared.applyGraphicEQ31(
                    gains,
                    preamp: self.preampGain,
                    outputBoost: self.outputBoostGain
                )
            }
        }
        syncDebounceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + syncDebounceInterval, execute: work)
    }

    /// Immediate sync (for preset loads, band mode switches — cases where a
    /// caller needs the change applied synchronously).
    private func syncToCoreAudioEngineImmediate() {
        syncDebounceWorkItem?.cancel()
        syncDebounceWorkItem = nil
        let gains = bands.map(\.gain)
        switch bandMode {
        case .tenBand:
            CoreAudioEngine.shared.applyFixedBandEQ(gains, preamp: preampGain, outputBoost: outputBoostGain)
        case .thirtyOneBand:
            CoreAudioEngine.shared.applyGraphicEQ31(gains, preamp: preampGain, outputBoost: outputBoostGain)
        }
    }

    // MARK: - Control Methods

    /// `persistState: false` — для стартового відновлення: провал автостарту
    /// (пристрій ще не enumerated, дозвіл не надано) не має стирати збережений
    /// намір користувача, інакше наступні запуски перестають відновлювати EQ.
    @discardableResult
    func setEnabled(_ enabled: Bool, persistState: Bool = true) -> Bool {
        CoreAudioEngine.shared.setEnabled(enabled)

        // Enable/disable routing based on EQ state
        if enabled {
            // First sync EQ bands to create filters (must be synchronous
            // so filters exist before routing starts pulling audio).
            syncToCoreAudioEngineImmediate()
            // Then enable routing
            guard enableRouting(false) else {
                CoreAudioEngine.shared.setEnabled(false)
                if persistState {
                    defaults.set(false, forKey: "eqWasEnabled")
                }
                return false
            }
            syncToCoreAudioEngineImmediate()
            if persistState {
                persistCurrentPlaybackState()
            }
            DiagnosticEventStore.shared.record("eq.enabled", details: diagnosticStateDetails())
        } else {
            if persistState {
                persistCurrentPlaybackState()
            }
            disableRouting(false)
            DiagnosticEventStore.shared.record("eq.disabled", details: diagnosticStateDetails())
        }

        // Save EQ enabled state for startup behavior
        if persistState {
            defaults.set(enabled, forKey: "eqWasEnabled")
        }
        return true
    }

    func setPreampGain(_ gain: Float) {
        preampGain = Self.sanitizedPreamp(gain)
        syncToCoreAudioEngineImmediate()
        persistCurrentPlaybackState()
    }

    func setOutputBoostGain(_ gain: Float) {
        let sanitized = Self.sanitizedOutputBoost(gain)
        outputBoostGain = sanitized
        defaults.set(sanitized, forKey: Self.outputBoostGainKey)
        syncToCoreAudioEngineImmediate()
    }

    func updateBandGain(bandId: Int, gain: Float) {
        guard bandId < bands.count else { return }
        let clampedGain = max(-20.0, min(20.0, gain))
        if Thread.isMainThread {
            bands[bandId].gain = clampedGain
            syncToCoreAudioEngine()
            schedulePlaybackStatePersistence()
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self, bandId < self.bands.count else { return }
                self.bands[bandId].gain = clampedGain
                self.syncToCoreAudioEngine()
                self.schedulePlaybackStatePersistence()
            }
        }
    }

    func resetAllBands() {
        for index in bands.indices {
            bands[index].gain = 0.0
        }
        syncToCoreAudioEngineImmediate()
        persistCurrentPlaybackState()
    }

    func applyEQValues(_ values: [Float]) {
        syncBandsToMode()
        guard values.count == bands.count else {
            eqLog("EQ values count mismatch: got \(values.count), expected \(bands.count)", level: .error)
            return
        }

        for (index, gain) in values.enumerated() {
            bands[index].gain = gain
        }
        syncToCoreAudioEngineImmediate()
        persistCurrentPlaybackState()
    }

    // MARK: - Legacy / Helpers

    func getCurrentEQValues() -> [Float] {
        bands.map(\.gain)
    }

    /// Auto Preamp Logic
    func applyAutoPreamp() {
        let maxPositiveGain = bands.map(\.gain).max() ?? 0.0
        if maxPositiveGain > 0 {
            setPreampGain(-maxPositiveGain)
        } else {
            setPreampGain(0.0)
        }
        eqLog("Auto preamp applied: \(formatGain(preampGain))")
    }

    private static func sanitizedPreamp(_ gain: Float) -> Float {
        gain.isFinite ? max(-20.0, min(20.0, gain)) : 0.0
    }

    private static func sanitizedOutputBoost(_ gain: Float) -> Float {
        gain.isFinite ? min(max(gain, 0.0), OutputSafetyProcessor.maximumBoostDB) : 0.0
    }

    func persistCurrentPlaybackState() {
        PresetPersistence.savePlaybackState(
            mode: bandMode,
            gains: bands.map(\.gain),
            preamp: preampGain,
            in: defaults
        )
    }

    private func schedulePlaybackStatePersistence() {
        persistenceDebounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.persistCurrentPlaybackState()
        }
        persistenceDebounceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + persistenceDebounceInterval, execute: work)
    }

    private func diagnosticStateDetails() -> [String: String] {
        let gains = bands.map(\.gain)
        return [
            "activeBands": "\(gains.filter { abs($0) >= 0.01 }.count)",
            "bandMode": bandMode.rawValue,
            "boostDB": String(format: "%.1f", outputBoostGain),
            "maxGainDB": String(format: "%.1f", gains.max() ?? 0),
            "minGainDB": String(format: "%.1f", gains.min() ?? 0),
            "preampDB": String(format: "%.1f", preampGain)
        ]
    }

    func formatFrequency(_ freq: Float) -> String {
        let translations = LocalizationManager.shared.translations
        let key: LocalizedString = .frequencyHz
        let hz = translations[key]?[LocalizationManager.shared.currentLanguage] ?? "Hz"
        if freq >= 1000 {
            return String(format: "%.1fk %@", freq / 1000, hz)
        } else {
            return String(format: "%.0f %@", freq, hz)
        }
    }

    func formatGain(_ gain: Float) -> String {
        let translations = LocalizationManager.shared.translations
        let key: LocalizedString = .dB
        let db = translations[key]?[LocalizationManager.shared.currentLanguage] ?? "dB"
        return String(format: "%+.1f %@", gain, db)
    }
}
