//
//  PresetPersistence.swift
//  SystemEQ for Mac
//
//  EQ preset persistence layer using UserDefaults
//  Saves and restores EQ band mode, gains, preamp, and bass boost settings
//

import Foundation

public enum PresetPersistence {
    private static let snapshotKey = "lastPreset.snapshot"
    private static let playbackSnapshotKey = "lastPlayback.snapshot"
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

    private struct Snapshot: Codable {
        let mode: EQBandMode
        let gains: [Float]
        let preamp: Float
        let bassBoost: Float

        var isValid: Bool {
            gains.count == mode.bandCount && gains.allSatisfy(\.isFinite) && preamp.isFinite && bassBoost.isFinite
        }
    }

    // 🔧 Тести підміняють на ізольований suite: запис у .standard у тест-хості
    // стирає реальний збережений пресет користувача.
    nonisolated(unsafe) static var defaults: UserDefaults = .standard

    public static func save(mode: EQBandMode, gains: [Float], preamp: Float, bassBoost: Float = 0.0) {
        let snapshot = Snapshot(mode: mode, gains: gains, preamp: preamp, bassBoost: bassBoost)
        guard snapshot.isValid, let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: snapshotKey)
    }

    public static func load() -> (mode: EQBandMode, gains: [Float], preamp: Float, bassBoost: Float)? {
        if let snapshot = loadSnapshot(key: snapshotKey, from: defaults) {
            return (snapshot.mode, snapshot.gains, snapshot.preamp, snapshot.bassBoost)
        }
        guard let raw = defaults.string(forKey: modeKey), let mode = EQBandMode(rawValue: raw) else { return nil }
        guard let data = defaults.data(forKey: gainsKey),
              let gains = try? JSONDecoder().decode([Float].self, from: data),
              gains.count == mode.bandCount, gains.allSatisfy(\.isFinite) else { return nil }
        let preamp = Float(defaults.double(forKey: preampKey))
        let bassBoost = Float(defaults.double(forKey: bassBoostKey))
        guard preamp.isFinite, bassBoost.isFinite else { return nil }
        return (mode, gains, preamp, bassBoost)
    }

    public static func savePlaybackState(
        mode: EQBandMode,
        gains: [Float],
        preamp: Float,
        in targetDefaults: UserDefaults? = nil
    ) {
        let target = targetDefaults ?? defaults
        let snapshot = Snapshot(mode: mode, gains: gains, preamp: preamp, bassBoost: 0)
        guard snapshot.isValid, let data = try? JSONEncoder().encode(snapshot) else { return }
        target.set(data, forKey: playbackSnapshotKey)
    }

    public static func loadPlaybackState(in targetDefaults: UserDefaults? = nil) -> PlaybackState? {
        let target = targetDefaults ?? defaults
        if let snapshot = loadSnapshot(key: playbackSnapshotKey, from: target) {
            return PlaybackState(mode: snapshot.mode, gains: snapshot.gains, preamp: snapshot.preamp)
        }
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
        defaults.removeObject(forKey: snapshotKey)
        defaults.removeObject(forKey: playbackSnapshotKey)
        defaults.removeObject(forKey: modeKey)
        defaults.removeObject(forKey: gainsKey)
        defaults.removeObject(forKey: preampKey)
        defaults.removeObject(forKey: bassBoostKey)
        defaults.removeObject(forKey: playbackModeKey)
        defaults.removeObject(forKey: playbackGainsKey)
        defaults.removeObject(forKey: playbackPreampKey)
    }

    public static var hasSavedPreset: Bool {
        load() != nil
    }

    private static func loadSnapshot(key: String, from target: UserDefaults) -> Snapshot? {
        guard let data = target.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
              snapshot.isValid else { return nil }
        return snapshot
    }

    private static func loadLegacyPlaybackState(in target: UserDefaults) -> PlaybackState? {
        if let snapshot = loadSnapshot(key: snapshotKey, from: target) {
            return PlaybackState(mode: snapshot.mode, gains: snapshot.gains, preamp: snapshot.preamp)
        }
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
