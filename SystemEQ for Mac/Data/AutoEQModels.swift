//
//  AutoEQModels.swift
//  SystemEQ for Mac
//
//  Created by Denys Zamorniak on 07/10/25.
//

import Combine
import Foundation

// MARK: - EQ Preset Models

public struct EQPreset: Codable, Identifiable {
    public let id: String
    public let name: String
    public let source: PresetSource
    public let targetCurve: TargetCurve?
    public let measurementRig: MeasurementRig?
    public let bands: [ParametricBand]
    public let preamp: Float

    /// Computed properties for compatibility
    public var displayName: String {
        name
    }

    public var preampGain: Float {
        preamp
    }

    public var sourceDisplayName: String {
        source.rawValue
    }

    public var parametricBands: [ParametricBand] {
        bands
    }

    public init(
        id: String,
        name: String,
        source: PresetSource,
        targetCurve: TargetCurve? = nil,
        measurementRig: MeasurementRig? = nil,
        bands: [ParametricBand],
        preamp: Float
    ) {
        self.id = id
        self.name = name
        self.source = source
        self.targetCurve = targetCurve
        self.measurementRig = measurementRig
        self.bands = bands
        self.preamp = preamp
    }
}

public struct ParametricBand: Codable, Identifiable {
    public let id: UUID = .init()
    public let frequency: Float
    public let gain: Float
    public let q: Float
    public let filterType: FilterType

    public init(frequency: Float, gain: Float, q: Float, filterType: FilterType = .peak) {
        self.frequency = max(20.0, min(frequency, 20000.0))
        self.gain = max(-30.0, min(gain, 30.0))
        self.q = max(0.1, min(q, 20.0))
        self.filterType = filterType
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        frequency = try container.decode(Float.self, forKey: .frequency)
        gain = try container.decode(Float.self, forKey: .gain)
        q = try container.decode(Float.self, forKey: .q)
        filterType = try container.decodeIfPresent(FilterType.self, forKey: .filterType) ?? .peak
    }

    private enum CodingKeys: String, CodingKey {
        case frequency
        case gain
        case q
        case filterType
    }
}

// MARK: - Headphone Model

public struct HeadphoneModel: Codable, Identifiable {
    public let id: String
    public let name: String
    public let brand: String
    public let model: String
    public let presets: [String] // Preset IDs
    public let metadata: [String: String]?

    public init(
        id: String,
        name: String,
        brand: String,
        model: String,
        presets: [String] = [],
        metadata: [String: String]? = nil
    ) {
        self.id = id
        self.name = name
        self.brand = brand
        self.model = model
        self.presets = presets
        self.metadata = metadata
    }
}

// MARK: - Enums

public enum PresetSource: String, Codable, CaseIterable {
    case opra = "OPRA"
    case autoeq = "AutoEQ"
    case custom = "Custom"
    case database = "Database"
}

public enum TargetCurve: String, Codable, CaseIterable {
    case jm1 = "JM-1"
    case harman2018 = "Harman 2018"
    case harman2019 = "Harman 2019"
    case neutral = "Neutral"
    case custom = "Custom"
}

public enum MeasurementRig: String, Codable, CaseIterable {
    case GRAS
    case BruelKjaer = "Bruel & Kjaer"
    case dummyHead = "Dummy Head"
    case unknown = "Unknown"
}

public enum FilterType: String, Codable, CaseIterable {
    case peak = "PK"
    case lowShelf = "LS"
    case highShelf = "HS"
    case lowPass = "LP"
    case highPass = "HP"
    case allPass = "AP"
    case bandPass = "BP"
    case notch = "NO"
    case allPassPEQ = "APPEQ"
}

// MARK: - Helper Types for AutoEQView

public struct ParsedBand: Identifiable, Equatable {
    public let id = UUID()
    public let freq: Double
    public let gain: Double
    public let q: Double
    public let type: FilterType

    public init(freq: Double, gain: Double, q: Double = 1.0, type: FilterType = .peak) {
        self.freq = freq
        self.gain = gain
        self.q = q
        self.type = type
    }
}

public struct MappedBand: Identifiable {
    public let id = UUID()
    public let center: Double
    public var gain: Double

    public init(center: Double, gain: Double) {
        self.center = center
        self.gain = gain
    }
}

public struct SearchCandidate: Identifiable, Equatable {
    public let id = UUID()
    public let path: String
    public let name: String
    public let display: String
    public let isParametric: Bool

    public init(path: String, name: String, display: String, isParametric: Bool) {
        self.path = path
        self.name = name
        self.display = display
        self.isParametric = isParametric
    }
}

public struct OfflineIndexEntry: Codable, Equatable {
    public let brand: String
    public let model: String
    public let source: String
    public let type: String
    public let pathFixedBandEQ: String?
    public let pathGraphicEQ: String?
    public let pathParametric: String?
    public let pathReadme: String?

    public init(
        brand: String,
        model: String,
        source: String,
        type: String,
        pathFixedBandEQ: String? = nil,
        pathGraphicEQ: String? = nil,
        pathParametric: String? = nil,
        pathReadme: String? = nil
    ) {
        self.brand = brand
        self.model = model
        self.source = source
        self.type = type
        self.pathFixedBandEQ = pathFixedBandEQ
        self.pathGraphicEQ = pathGraphicEQ
        self.pathParametric = pathParametric
        self.pathReadme = pathReadme
    }
}

// MARK: - Preset Manager

public class PresetManager: ObservableObject {
    public static let shared = PresetManager()

    @Published public var presets: [EQPreset] = []
    @Published public var headphoneModels: [HeadphoneModel] = []

    private init() {}

    public func getPresets(for headphone: HeadphoneModel) -> [EQPreset] {
        presets.filter { headphone.presets.contains($0.id) }
    }

    public func getRecommendedPreset(for headphone: HeadphoneModel) -> EQPreset? {
        let presets = getPresets(for: headphone)
        return presets.first { $0.source == .opra }
    }

    public func getCustomPresets() -> [EQPreset] {
        presets.filter { $0.source == .custom }
    }

    public func convertToFixedBand(_ preset: EQPreset, bandMode: BandMode) -> [Float] {
        let frequencies = bandMode == .ten ? AutoEQConstants.tenBandFrequencies : AutoEQConstants
            .thirtyOneBandFrequencies
        var gains = Array(repeating: 0.0, count: frequencies.count)

        for band in preset.bands {
            if let index = frequencies.enumerated()
                .min(by: { abs($0.1 - band.frequency) < abs($1.1 - band.frequency) })?.offset {
                gains[index] += Double(band.gain)
            }
        }

        return gains.map(Float.init)
    }
}
