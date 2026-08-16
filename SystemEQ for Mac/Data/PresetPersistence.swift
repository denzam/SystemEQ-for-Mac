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
    private static let playbackModeKey = "lastPlayback.mode"
    private static let playbackGainsKey = "lastPlayback.gains"
    private static let playbackPreampKey = "lastPlayback.preamp"

    public struct PlaybackState: Equatable {
        public let mode: EQBandMode
        public let gains: [Float]
        public let preamp: Float
    }

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

    public static func savePlaybackState(
        mode: EQBandMode,
        gains: [Float],
        preamp: Float,
        in targetDefaults: UserDefaults? = nil
    ) {
        let target = targetDefaults ?? defaults
        target.set(mode.rawValue, forKey: playbackModeKey)
        if let data = try? JSONEncoder().encode(gains) {
            target.set(data, forKey: playbackGainsKey)
        }
        target.set(Double(preamp), forKey: playbackPreampKey)
    }

    public static func loadPlaybackState(in targetDefaults: UserDefaults? = nil) -> PlaybackState? {
        let target = targetDefaults ?? defaults
        guard let raw = target.string(forKey: playbackModeKey), let mode = EQBandMode(rawValue: raw) else {
            return loadLegacyPlaybackState(in: target)
        }
        guard let data = target.data(forKey: playbackGainsKey),
              let gains = try? JSONDecoder().decode([Float].self, from: data),
              gains.count == mode.bandCount,
              gains.allSatisfy(\.isFinite)
        else {
            return loadLegacyPlaybackState(in: target)
        }

        let preamp = Float(target.double(forKey: playbackPreampKey))
        guard preamp.isFinite else { return loadLegacyPlaybackState(in: target) }
        return PlaybackState(mode: mode, gains: gains, preamp: preamp)
    }

    public static func clear() {
        defaults.removeObject(forKey: modeKey)
        defaults.removeObject(forKey: gainsKey)
        defaults.removeObject(forKey: preampKey)
        defaults.removeObject(forKey: bassBoostKey)
        defaults.removeObject(forKey: playbackModeKey)
        defaults.removeObject(forKey: playbackGainsKey)
        defaults.removeObject(forKey: playbackPreampKey)
    }

    public static var hasSavedPreset: Bool {
        defaults.string(forKey: modeKey) != nil && defaults.data(forKey: gainsKey) != nil
    }

    private static func loadLegacyPlaybackState(in target: UserDefaults) -> PlaybackState? {
        guard let raw = target.string(forKey: modeKey), let mode = EQBandMode(rawValue: raw) else { return nil }
        guard let data = target.data(forKey: gainsKey),
              let gains = try? JSONDecoder().decode([Float].self, from: data),
              gains.count == mode.bandCount,
              gains.allSatisfy(\.isFinite)
        else { return nil }

        let preamp = Float(target.double(forKey: preampKey))
        guard preamp.isFinite else { return nil }
        return PlaybackState(mode: mode, gains: gains, preamp: preamp)
    }
}
