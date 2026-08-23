//
//  FeatureRegistry.swift
//  SystemEQ for Mac
//
//  Feature registry and configuration system
//  Manages app features, their availability, and display order
//  Loads feature configuration from JSON file
//

import Combine
import Foundation
import SwiftUI

enum FeatureID: String, CaseIterable, Identifiable {
    case equalizer
    case calibration
    case subjectiveRoomTuning // Renamed from roomCalibration - subjective room tuning
    case resonanceFinder // New - Sine Sweep tool for finding resonances
    case autoeq
    case personalized
    case routing
    case settings
    case visualizer
    var id: String {
        rawValue
    }
}

struct Feature: Identifiable {
    let id: FeatureID
    let title: String
    let enabled: Bool
    let order: Int
}

final class FeatureRegistry: ObservableObject {
    @Published var features: [Feature] = [
        Feature(id: .calibration, title: "Calibration", enabled: true, order: 2),
        Feature(id: .subjectiveRoomTuning, title: "Subjective Room Tuning", enabled: true, order: 3),
        Feature(id: .resonanceFinder, title: "Resonance Finder", enabled: true, order: 4),
        Feature(id: .autoeq, title: "AutoEQ presets", enabled: true, order: 5),
        Feature(id: .personalized, title: "Personalized", enabled: true, order: 6),
        Feature(id: .routing, title: "Routing", enabled: true, order: 7),
        Feature(id: .settings, title: "Settings", enabled: true, order: 8),
        Feature(id: .visualizer, title: "Visualizer", enabled: true, order: 9)
    ]

    private struct FeaturesFile: Decodable {
        struct Item: Decodable { let id: String; let title: String; let enabled: Bool; let order: Int }
        let features: [Item]
    }

    init() {
        if let loaded = Self.loadFromBundle() {
            self.features = loaded
        }
    }

    private static func loadFromBundle() -> [Feature]? {
        let bundle = Bundle.main
        var url: URL?
        if let u = bundle.url(forResource: "features", withExtension: "json", subdirectory: "Config") {
            url = u
        } else if let u = bundle.url(forResource: "features", withExtension: "json") {
            url = u
        }
        guard let fileURL = url, let data = try? Data(contentsOf: fileURL) else { return nil }
        guard let decoded = try? JSONDecoder().decode(FeaturesFile.self, from: data) else { return nil }
        return decoded.features.compactMap { item -> Feature? in
            guard let fid = FeatureID(rawValue: item.id) else { return nil }
            return Feature(id: fid, title: item.title, enabled: item.enabled, order: item.order)
        }
    }

    func ordered() -> [Feature] {
        features.filter(\.enabled).sorted { $0.order < $1.order }
    }
}
