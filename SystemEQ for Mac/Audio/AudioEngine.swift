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
                setupEQBands()
                syncToCoreAudioEngineImmediate()
            }
        }
    }

    @Published var bands: [EQBand] = []
    @Published var preampGain: Float = 0.0

    // Levels (Delegated from CoreAudioEngine)
    @Published var inputPeakLevel: Float = 0.0
    @Published var outputPeakLevel: Float = 0.0

    private var cancellables = Set<AnyCancellable>()

    // Debounces rapid slider drags so we rebuild the filter chain at most
    // ~every 20 ms instead of once per UI event (60+ Hz). Final gesture
    // value is always applied via the trailing edge of the work item.
    private var syncDebounceWorkItem: DispatchWorkItem?
    private let syncDebounceInterval: DispatchTimeInterval = .milliseconds(20)

    // MARK: - Singleton

    public static let shared = AudioEngine()

    // MARK: - Initialization

    private init() {
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

        // ⚡ CRITICAL OPTIMIZATION: Throttle peak meters to reduce Main Thread UI updates
        // From 23 updates/sec (~43ms) to 10 updates/sec (100ms) = 50-60% less UI overhead
        CoreAudioEngine.shared.peakMeter.$inputPeakLevel
            .throttle(for: .milliseconds(100), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] value in
                DispatchQueue.main.async { self?.inputPeakLevel = value }
            }
            .store(in: &cancellables)

        CoreAudioEngine.shared.peakMeter.$outputPeakLevel
            .throttle(for: .milliseconds(100), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] value in
                DispatchQueue.main.async { self?.outputPeakLevel = value }
            }
            .store(in: &cancellables)
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

    private static func interpolatedGain(at freq: Float, from previous: [EQBand]) -> Float {
        guard !previous.isEmpty else { return 0.0 }
        if let exact = previous.first(where: { abs($0.frequency - freq) < 0.5 }) {
            return exact.gain
        }
        let sorted = previous.sorted { $0.frequency < $1.frequency }
        if freq <= sorted.first!.frequency { return sorted.first!.gain }
        if freq >= sorted.last!.frequency { return sorted.last!.gain }
        for i in 0..<(sorted.count - 1) {
            let lo = sorted[i], hi = sorted[i + 1]
            if freq >= lo.frequency && freq <= hi.frequency {
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
                CoreAudioEngine.shared.applyFixedBandEQ(gains, preamp: self.preampGain)
            case .thirtyOneBand:
                CoreAudioEngine.shared.applyGraphicEQ31(gains, preamp: self.preampGain)
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
            CoreAudioEngine.shared.applyFixedBandEQ(gains, preamp: preampGain)
        case .thirtyOneBand:
            CoreAudioEngine.shared.applyGraphicEQ31(gains, preamp: preampGain)
        }
    }

    // MARK: - Control Methods

    func setEnabled(_ enabled: Bool) {
        CoreAudioEngine.shared.setEnabled(enabled)

        // Enable/disable routing based on EQ state
        if enabled {
            // First sync EQ bands to create filters (must be synchronous
            // so filters exist before routing starts pulling audio).
            syncToCoreAudioEngineImmediate()
            // Then enable routing
            AudioRouter.shared.enableEQRouting()
        } else {
            AudioRouter.shared.disableEQRouting()
        }

        // Save EQ enabled state for startup behavior
        UserDefaults.standard.set(enabled, forKey: "eqWasEnabled")
    }

    func setPreampGain(_ gain: Float) {
        preampGain = gain
        CoreAudioEngine.shared.setPreampGain(gain)
    }

    func updateBandGain(bandId: Int, gain: Float) {
        guard bandId < bands.count else { return }
        let clampedGain = max(-20.0, min(20.0, gain))
        if Thread.isMainThread {
            bands[bandId].gain = clampedGain
            syncToCoreAudioEngine()
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self, bandId < self.bands.count else { return }
                self.bands[bandId].gain = clampedGain
                self.syncToCoreAudioEngine()
            }
        }
    }

    func resetAllBands() {
        for index in bands.indices {
            bands[index].gain = 0.0
        }
        syncToCoreAudioEngineImmediate()
    }

    func applyEQValues(_ values: [Float]) {
        guard values.count == bands.count else {
            eqLog("EQ values count mismatch: got \(values.count), expected \(bands.count)", level: .error)
            return
        }

        for (index, gain) in values.enumerated() {
            bands[index].gain = gain
        }
        syncToCoreAudioEngineImmediate()
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
