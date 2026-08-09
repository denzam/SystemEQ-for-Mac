//
//  PresetPersistence.swift
//  SystemEQ for Mac
//
//  EQ preset persistence layer using UserDefaults
//  Saves and restores EQ band mode, gains, preamp, and bass boost settings
//

import Foundation

public enum PresetPersistence {
    private static let modeKey = "lastPreset.mode"
    private static let gainsKey = "lastPreset.gains"
    private static let preampKey = "lastPreset.preamp"
    private static let bassBoostKey = "lastPreset.bassBoost"

    // 🔧 Тести підміняють на ізольований suite: запис у .standard у тест-хості
    // стирає реальний збережений пресет користувача.
    nonisolated(unsafe) static var defaults: UserDefaults = .standard

    public static func save(mode: EQBandMode, gains: [Float], preamp: Float, bassBoost: Float = 0.0) {
        defaults.set(mode.rawValue, forKey: modeKey)
        if let data = try? JSONEncoder().encode(gains) {
            defaults.set(data, forKey: gainsKey)
        }
        defaults.set(Double(preamp), forKey: preampKey)
        defaults.set(Double(bassBoost), forKey: bassBoostKey)
    }

    public static func load() -> (mode: EQBandMode, gains: [Float], preamp: Float, bassBoost: Float)? {
        guard let raw = defaults.string(forKey: modeKey), let mode = EQBandMode(rawValue: raw) else { return nil }
        guard let data = defaults.data(forKey: gainsKey),
              let gains = try? JSONDecoder().decode([Float].self, from: data) else { return nil }
        let preamp = Float(defaults.double(forKey: preampKey))
        let bassBoost = Float(defaults.double(forKey: bassBoostKey))
        return (mode, gains, preamp, bassBoost)
    }

    public static func clear() {
        defaults.removeObject(forKey: modeKey)
        defaults.removeObject(forKey: gainsKey)
        defaults.removeObject(forKey: preampKey)
        defaults.removeObject(forKey: bassBoostKey)
    }

    public static var hasSavedPreset: Bool {
        defaults.string(forKey: modeKey) != nil && defaults.data(forKey: gainsKey) != nil
    }
}
