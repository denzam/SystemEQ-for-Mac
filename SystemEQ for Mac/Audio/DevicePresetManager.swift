//
//  DevicePresetManager.swift
//  SystemEQ for Mac
//
//  Issue #31: авто-перемикання пресета за обраним пристроєм виводу.
//  Мапа «UID виводу → останній застосований на ньому пресет» поповнюється при
//  кожному застосуванні; перемикання виводу відтворює збережений стан з готових
//  gain-значень — без повторного парсингу тексту пресета.
//

import Combine
import Foundation

struct DevicePresetRecord: Codable, Equatable {
    let mode: String // EQBandMode.rawValue
    let appliedGains: [Float] // з урахуванням bass boost — те, що реально грає
    let cleanGains: [Float] // без boost — для PresetPersistence
    let preamp: Float
    let bassBoost: Float
    let descriptorJSON: String // дескриптор пресета для UI AutoEQ
}

@MainActor
final class DevicePresetManager {
    static let shared = DevicePresetManager()

    static let autoSwitchKey = "autoSwitchPresetPerDevice"
    private static let mapKey = "devicePresets.v1"

    // 🔧 Тести підміняють на ізольований suite — як у PresetPersistence
    nonisolated(unsafe) static var defaults: UserDefaults = .standard

    private var cancellable: AnyCancellable?

    private init() {}

    /// Стежити за зміною пристрою виводу. Викликається один раз з AppStartup.
    func bind() {
        cancellable = AudioRouter.shared.$selectedOutputDevice
            .compactMap(\.?.uid)
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] uid in
                self?.outputChanged(to: uid)
            }
    }

    // MARK: - Recording

    /// Запам'ятати щойно застосований пресет за пристроєм виводу.
    /// `outputUID: nil` — взяти поточний вибраний вивід.
    func recordApply(_ record: DevicePresetRecord, outputUID: String? = nil) {
        guard let uid = outputUID ?? AudioRouter.shared.selectedOutputDevice?.uid else { return }
        var map = loadMap()
        map[uid] = record
        saveMap(map)
    }

    func record(for uid: String) -> DevicePresetRecord? {
        loadMap()[uid]
    }

    // MARK: - Switching

    private func outputChanged(to uid: String) {
        outputChanged(to: uid, engine: .shared)
    }

    func outputChanged(to uid: String, engine: AudioEngine) {
        guard Self.defaults.bool(forKey: Self.autoSwitchKey) else { return }
        guard let record = loadMap()[uid] else {
            applyFlat(to: engine, outputUID: uid)
            return
        }
        guard let mode = EQBandMode(rawValue: record.mode),
              record.appliedGains.count == mode.bandCount,
              record.cleanGains.count == mode.bandCount,
              record.appliedGains.allSatisfy(\.isFinite),
              record.cleanGains.allSatisfy(\.isFinite),
              record.preamp.isFinite,
              record.bassBoost.isFinite else {
            applyFlat(to: engine, outputUID: uid)
            return
        }

        engine.bandMode = mode
        engine.applyEQValues(record.appliedGains)
        engine.setPreampGain(record.preamp)

        // Глобальний стан: наступний запуск відновить пресет саме цього виводу
        PresetPersistence.save(
            mode: mode,
            gains: record.cleanGains,
            preamp: record.preamp,
            bassBoost: record.bassBoost
        )
        Self.defaults.set(record.descriptorJSON, forKey: "lastAppliedPresetJSON")

        dlog("Device preset applied for output \(uid)", level: .info, category: .preset)
    }

    private func applyFlat(to engine: AudioEngine, outputUID: String) {
        let mode = engine.bandMode
        let gains = [Float](repeating: 0, count: mode.bandCount)
        engine.applyEQValues(gains)
        engine.setPreampGain(0)
        PresetPersistence.save(mode: mode, gains: gains, preamp: 0, bassBoost: 0)
        Self.defaults.removeObject(forKey: "lastAppliedPresetJSON")
        dlog("Flat EQ applied for unmapped output \(outputUID)", level: .info, category: .preset)
    }

    // MARK: - Storage

    private func loadMap() -> [String: DevicePresetRecord] {
        guard let data = Self.defaults.data(forKey: Self.mapKey),
              let map = try? JSONDecoder().decode([String: DevicePresetRecord].self, from: data)
        else { return [:] }
        return map
    }

    private func saveMap(_ map: [String: DevicePresetRecord]) {
        if let data = try? JSONEncoder().encode(map) {
            Self.defaults.set(data, forKey: Self.mapKey)
        }
    }
}
