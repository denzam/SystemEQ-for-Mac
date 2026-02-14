//
//  PersonalizedHearingProfile.swift
//  SystemEQ for Mac
//
//  Personalized Hearing Profile - adaptive hearing calibration for headphones
//  Premium feature: personalized EQ profiles that adapt to user's hearing
//

import Combine
import Foundation

/// Personalized hearing profile data
public struct PersonalizedHearingProfile: Codable, Identifiable {
    public let id: UUID
    public let name: String
    public let created: Date
    private var _lastUpdated: Date

    /// Hearing response data (logarithmic frequency points)
    private var _frequencyPoints: [FrequencyResponsePoint]

    // Adaptive learning data
    public var trainingSessions: Int
    public var confidenceScore: Double // 0.0 to 1.0

    // Profile metadata
    public let headphoneModel: String?
    public let testDuration: TimeInterval // seconds
    public var averageAccuracy: Double // dB deviation from ideal

    public init(name: String, headphoneModel: String? = nil) {
        self.id = UUID()
        self.name = name
        self.created = Date()
        self._lastUpdated = Date()
        self._frequencyPoints = []
        self.trainingSessions = 0
        self.confidenceScore = 0.0
        self.headphoneModel = headphoneModel
        self.testDuration = 0
        self.averageAccuracy = 0.0
    }

    public var frequencyPoints: [FrequencyResponsePoint] {
        _frequencyPoints
    }

    public var lastUpdated: Date {
        _lastUpdated
    }

    /// Initialize with frequency response data
    public init(
        id: UUID = UUID(),
        name: String,
        frequencyPoints: [FrequencyResponsePoint],
        headphoneModel: String? = nil,
        testDuration: TimeInterval = 0
    ) {
        self.id = id
        self.name = name
        self.created = Date()
        self._lastUpdated = Date()
        self._frequencyPoints = frequencyPoints
        self.trainingSessions = 1
        self.confidenceScore = Self.calculateConfidence(frequencyPoints)
        self.headphoneModel = headphoneModel
        self.testDuration = testDuration
        self.averageAccuracy = Self.calculateAccuracy(frequencyPoints)
    }

    /// Single frequency response measurement point
    public struct FrequencyResponsePoint: Codable, Identifiable {
        public var id: UUID {
            UUID()
        }

        public let frequency: Double // Hz
        public let gainCorrection: Float // dB correction needed
        public let confidence: Float // 0.0 to 1.0
        public let measurementCount: Int // number of measurements for this point

        public init(frequency: Double, gainCorrection: Float, confidence: Float = 0.5, measurementCount: Int = 1) {
            self.frequency = frequency
            self.gainCorrection = gainCorrection
            self.confidence = confidence
            self.measurementCount = measurementCount
        }
    }

    // MARK: - Profile Analysis

    /// Calculate confidence score based on measurement consistency
    private static func calculateConfidence(_ points: [FrequencyResponsePoint]) -> Double {
        guard !points.isEmpty else { return 0.0 }

        let totalConfidence = points.reduce(0.0) { sum, point in
            sum + Double(point.confidence)
        }

        return min(1.0, totalConfidence / Double(points.count))
    }

    /// Calculate average accuracy (lower is better)
    private static func calculateAccuracy(_ points: [FrequencyResponsePoint]) -> Double {
        guard !points.isEmpty else { return 0.0 }

        let totalDeviation = points.reduce(0.0) { sum, point in
            sum + abs(Double(point.gainCorrection))
        }

        return totalDeviation / Double(points.count)
    }

    /// Get correction for specific frequency (interpolated)
    public func getCorrection(for frequency: Double) -> Float {
        guard !_frequencyPoints.isEmpty else { return 0.0 }

        // Find surrounding points for interpolation
        let sortedPoints = _frequencyPoints.sorted { $0.frequency < $1.frequency }

        // Exact match
        if let exact = sortedPoints.first(where: { $0.frequency == frequency }) {
            return exact.gainCorrection
        }

        // Below range
        guard let firstPoint = sortedPoints.first, frequency > firstPoint.frequency else {
            return sortedPoints.first?.gainCorrection ?? 0.0
        }

        // Above range
        guard let lastPoint = sortedPoints.last, frequency < lastPoint.frequency else {
            return sortedPoints.last?.gainCorrection ?? 0.0
        }

        // Linear interpolation
        for i in 0..<sortedPoints.count - 1 {
            let lower = sortedPoints[i]
            let upper = sortedPoints[i + 1]

            if frequency >= lower.frequency, frequency <= upper.frequency {
                let ratio = (frequency - lower.frequency) / (upper.frequency - lower.frequency)
                return lower.gainCorrection + Float(ratio) * (upper.gainCorrection - lower.gainCorrection)
            }
        }

        return 0.0
    }

    /// Update profile with new measurements
    public mutating func updateWithMeasurements(_ newPoints: [FrequencyResponsePoint]) {
        // Merge with existing points
        var mergedPoints = _frequencyPoints

        for newPoint in newPoints {
            if let existingIndex = mergedPoints.firstIndex(where: { $0.frequency == newPoint.frequency }) {
                // Weighted average based on measurement count
                let existing = mergedPoints[existingIndex]
                let totalMeasurements = existing.measurementCount + newPoint.measurementCount

                let weightedGain = (existing.gainCorrection * Float(existing.measurementCount) +
                    newPoint.gainCorrection * Float(newPoint.measurementCount)) / Float(totalMeasurements)

                let weightedConfidence = (existing.confidence * Float(existing.measurementCount) +
                    newPoint.confidence * Float(newPoint.measurementCount)) / Float(totalMeasurements)

                mergedPoints[existingIndex] = FrequencyResponsePoint(
                    frequency: newPoint.frequency,
                    gainCorrection: weightedGain,
                    confidence: weightedConfidence,
                    measurementCount: totalMeasurements
                )
            } else {
                mergedPoints.append(newPoint)
            }
        }

        self._frequencyPoints = mergedPoints
        self._lastUpdated = Date()
        self.trainingSessions += 1
        self.confidenceScore = Self.calculateConfidence(mergedPoints)
        self.averageAccuracy = Self.calculateAccuracy(mergedPoints)
    }

    /// Check if profile is ready for use
    public var isReady: Bool {
        confidenceScore >= 0.7 && trainingSessions >= 1
    }

    /// Get profile quality description
    public var qualityDescription: String {
        switch confidenceScore {
        case 0.9...1.0:
            "Excellent"
        case 0.7..<0.9:
            "Good"
        case 0.5..<0.7:
            "Fair"
        default:
            "Needs Training"
        }
    }
}

/// Test configuration for personalized calibration
public struct PersonalizedTestConfig {
    public let frequencies: [Double]
    public let testLevels: [Float] // dB SPL
    public let adaptiveMode: Bool
    public let quickTest: Bool

    public static let standard = PersonalizedTestConfig(
        frequencies: [
            // Extended range: 20Hz to 20kHz
            20, 25, 31.5, 40, 50, 63, 80, 100, 125, 160,
            200, 250, 315, 400, 500, 630, 800, 1000, 1250, 1600,
            2000, 2500, 3150, 4000, 5000, 6300, 8000, 10000, 12500, 16000, 20000
        ],
        testLevels: [-30, -20, -10], // Test at multiple levels
        adaptiveMode: true,
        quickTest: false
    )

    public static let quick = PersonalizedTestConfig(
        frequencies: [
            31.5, 63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000
        ],
        testLevels: [-20],
        adaptiveMode: false,
        quickTest: true
    )
}

/// Premium feature manager
public class PersonalizedProfileManager: ObservableObject {
    public static let shared = PersonalizedProfileManager()

    @Published public var isUnlocked: Bool = false
    @Published public var profiles: [PersonalizedHearingProfile] = []
    @Published public var activeProfile: PersonalizedHearingProfile?

    private let unlockKey = "PersonalizedProfileUnlocked"

    private init() {
        loadUnlockStatus()
        loadProfiles()
    }

    // MARK: - Premium Access

    public func unlockFeature() {
        // Feature is unlocked by default in open-source version
        isUnlocked = true
        UserDefaults.standard.set(true, forKey: unlockKey)
    }

    private func loadUnlockStatus() {
        isUnlocked = UserDefaults.standard.bool(forKey: unlockKey)
    }

    // MARK: - Profile Management

    public func saveProfile(_ profile: PersonalizedHearingProfile) {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }

        saveProfilesToDisk()
    }

    public func deleteProfile(_ profile: PersonalizedHearingProfile) {
        profiles.removeAll { $0.id == profile.id }
        if activeProfile?.id == profile.id {
            activeProfile = nil
        }
        saveProfilesToDisk()
    }

    private func loadProfiles() {
        guard let documentsURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return }
        let appSupportURL = documentsURL.appendingPathComponent("SystemEQ for Mac")
        let profilesURL = appSupportURL.appendingPathComponent("PersonalizedProfiles.json")

        do {
            let data = try Data(contentsOf: profilesURL)
            let loadedProfiles = try JSONDecoder().decode([PersonalizedHearingProfile].self, from: data)
            profiles = loadedProfiles
            dlog("Loaded \(profiles.count) personalized profiles", category: .preset)
        } catch {
            dlog("Could not load profiles: \(error)", level: .warning, category: .preset)
        }
    }

    private func saveProfilesToDisk() {
        guard let documentsURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return }
        let appSupportURL = documentsURL.appendingPathComponent("SystemEQ for Mac")

        // Create directory if it doesn't exist
        do {
            try FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
        } catch {
            dlog("Could not create app support directory: \(error)", level: .error, category: .preset)
            return
        }

        let profilesURL = appSupportURL.appendingPathComponent("PersonalizedProfiles.json")

        do {
            let data = try JSONEncoder().encode(profiles)
            try data.write(to: profilesURL)
            dlog("Saved \(profiles.count) personalized profiles", category: .preset)
        } catch {
            dlog("Could not save profiles: \(error)", level: .error, category: .preset)
        }
    }

    // MARK: - Profile Application

    /// Apply personalized correction to EQ bands
    public func applyPersonalizedCorrection(to bands: [Float], frequencies: [Double]) -> [Float] {
        guard let profile = activeProfile else { return bands }

        return zip(bands, frequencies).map { band, frequency in
            let correction = profile.getCorrection(for: frequency)
            return band + correction
        }
    }
}
