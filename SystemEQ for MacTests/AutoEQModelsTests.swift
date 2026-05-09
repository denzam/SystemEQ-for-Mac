//
//  AutoEQModelsTests.swift
//  SystemEQ for MacTests
//
//  Unit tests for AutoEQ data models
//

@testable import SystemEQ_for_Mac
import XCTest

@MainActor
final class AutoEQModelsTests: XCTestCase {
    // MARK: - ParametricBand Tests

    func testParametricBand_codableRoundtrip() throws {
        let original = ParametricBand(
            frequency: 1000.0,
            gain: 6.0,
            q: 1.4,
            filterType: .peak
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ParametricBand.self, from: data)

        XCTAssertEqual(decoded.frequency, original.frequency, accuracy: 0.001)
        XCTAssertEqual(decoded.gain, original.gain, accuracy: 0.001)
        XCTAssertEqual(decoded.q, original.q, accuracy: 0.001)
        XCTAssertEqual(decoded.filterType, original.filterType)
    }

    func testParametricBand_defaultFilterType_isPeak() throws {
        // JSON without filterType should default to .peak
        let json = """
        {"frequency": 500.0, "gain": 3.0, "q": 1.0}
        """
        guard let data = json.data(using: .utf8) else {
            XCTFail("Failed to create data from JSON string")
            return
        }
        let decoded = try JSONDecoder().decode(ParametricBand.self, from: data)

        XCTAssertEqual(
            decoded.filterType,
            .peak,
            "Missing filterType should default to .peak"
        )
    }

    func testParametricBand_allFilterTypes_codable() throws {
        let filterTypes: [FilterType] = [.peak, .lowShelf, .highShelf, .lowPass, .highPass, .notch]

        for type in filterTypes {
            let band = ParametricBand(frequency: 1000, gain: 0, q: 1.0, filterType: type)
            let data = try JSONEncoder().encode(band)
            let decoded = try JSONDecoder().decode(ParametricBand.self, from: data)
            XCTAssertEqual(
                decoded.filterType,
                type,
                "FilterType \(type.rawValue) should survive Codable roundtrip"
            )
        }
    }

    func testParametricBand_uniqueIDs() {
        let band1 = ParametricBand(frequency: 1000, gain: 0, q: 1.0)
        let band2 = ParametricBand(frequency: 1000, gain: 0, q: 1.0)

        XCTAssertNotEqual(
            band1.id,
            band2.id,
            "Each ParametricBand should have a unique ID"
        )
    }

    // MARK: - EQPreset Tests

    func testEQPreset_codableRoundtrip() throws {
        let bands = [
            ParametricBand(frequency: 100, gain: 3.0, q: 0.7, filterType: .lowShelf),
            ParametricBand(frequency: 1000, gain: -2.0, q: 1.4, filterType: .peak),
            ParametricBand(frequency: 8000, gain: 1.5, q: 0.7, filterType: .highShelf)
        ]

        let original = EQPreset(
            id: "test-preset",
            name: "Test Preset",
            source: .autoeq,
            targetCurve: .harman2018,
            measurementRig: .GRAS,
            bands: bands,
            preamp: -2.5
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(EQPreset.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.source, original.source)
        XCTAssertEqual(decoded.preamp, original.preamp, accuracy: 0.001)
        XCTAssertEqual(decoded.bands.count, original.bands.count)
    }

    func testEQPreset_computedProperties() {
        let preset = EQPreset(
            id: "test",
            name: "My Preset",
            source: .custom,
            bands: [ParametricBand(frequency: 1000, gain: 3.0, q: 1.0)],
            preamp: -1.5
        )

        XCTAssertEqual(preset.displayName, "My Preset")
        XCTAssertEqual(preset.preampGain, -1.5, accuracy: 0.001)
        XCTAssertEqual(preset.sourceDisplayName, "Custom")
        XCTAssertEqual(preset.parametricBands.count, 1)
    }

    // MARK: - FilterType Tests

    func testFilterType_rawValues() {
        XCTAssertEqual(FilterType.peak.rawValue, "PK")
        XCTAssertEqual(FilterType.lowShelf.rawValue, "LS")
        XCTAssertEqual(FilterType.highShelf.rawValue, "HS")
        XCTAssertEqual(FilterType.lowPass.rawValue, "LP")
        XCTAssertEqual(FilterType.highPass.rawValue, "HP")
        XCTAssertEqual(FilterType.allPass.rawValue, "AP")
        XCTAssertEqual(FilterType.bandPass.rawValue, "BP")
        XCTAssertEqual(FilterType.notch.rawValue, "NO")
    }

    func testFilterType_caseIterable() {
        // Should have all 9 cases
        XCTAssertEqual(FilterType.allCases.count, 9)
    }

    // MARK: - PresetSource Tests

    func testPresetSource_rawValues() {
        XCTAssertEqual(PresetSource.opra.rawValue, "OPRA")
        XCTAssertEqual(PresetSource.autoeq.rawValue, "AutoEQ")
        XCTAssertEqual(PresetSource.custom.rawValue, "Custom")
        XCTAssertEqual(PresetSource.database.rawValue, "Database")
    }

    // MARK: - AutoEQConstants Tests

    func testAutoEQConstants_tenBandFrequencies() {
        let freqs = AutoEQConstants.tenBandFrequencies
        XCTAssertEqual(freqs.count, 10, "Should have exactly 10 frequencies")
        XCTAssertEqual(freqs.first ?? 0, 31.5, accuracy: 0.001)
        XCTAssertEqual(freqs.last ?? 0, 16000, accuracy: 0.001)

        // Frequencies should be in ascending order
        for i in 1..<freqs.count {
            XCTAssertGreaterThan(
                freqs[i],
                freqs[i - 1],
                "Frequencies should be sorted ascending"
            )
        }
    }

    func testAutoEQConstants_thirtyOneBandFrequencies() {
        let freqs = AutoEQConstants.thirtyOneBandFrequencies
        XCTAssertEqual(freqs.count, 31, "Should have exactly 31 frequencies")
        XCTAssertEqual(freqs.first ?? 0, 20, accuracy: 0.001)
        XCTAssertEqual(freqs.last ?? 0, 20000, accuracy: 0.001)

        for i in 1..<freqs.count {
            XCTAssertGreaterThan(
                freqs[i],
                freqs[i - 1],
                "Frequencies should be sorted ascending"
            )
        }
    }

    func testAutoEQConstants_thirtyOneCenters_matchesFrequencies() {
        XCTAssertEqual(
            AutoEQConstants.thirtyOneCenters,
            AutoEQConstants.thirtyOneBandFrequencies,
            "thirtyOneCenters should be an alias for thirtyOneBandFrequencies"
        )
    }

    // MARK: - HeadphoneModel Tests

    func testHeadphoneModel_init() {
        let model = HeadphoneModel(
            id: "hd600",
            name: "Sennheiser HD 600",
            brand: "Sennheiser",
            model: "HD 600"
        )

        XCTAssertEqual(model.id, "hd600")
        XCTAssertEqual(model.brand, "Sennheiser")
        XCTAssertTrue(model.presets.isEmpty)
        XCTAssertNil(model.metadata)
    }

    // MARK: - BandMode Tests

    func testBandMode_rawValues() {
        XCTAssertEqual(BandMode.ten.rawValue, "10")
        XCTAssertEqual(BandMode.thirtyOne.rawValue, "31")
    }
}
