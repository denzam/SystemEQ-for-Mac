//
//  AutoEQModelsTests.swift
//  SystemEQ for MacTests
//
//  Unit tests for AutoEQ data models
//

import SQLite3
@testable import SystemEQ_for_Mac
import XCTest

@MainActor
final class EQDatabaseFixtureTests: XCTestCase {
    private func withFixture(
        fts: Bool = false, bands10: Int = 10, bands31: Int = 31,
        gain: String = "0", preamp: String = "-3", body: (EQDatabase) -> Void
    ) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("fixture.sqlite")
        var writer: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &writer), SQLITE_OK)
        defer { if let writer { sqlite3_close(writer) } }
        var sql = """
        CREATE TABLE headphones(id INTEGER PRIMARY KEY, brand TEXT, model TEXT, type TEXT, source TEXT);
        CREATE TABLE presets(id INTEGER PRIMARY KEY, headphone_id INTEGER, source TEXT, author TEXT, target_curve TEXT, preamp_gain REAL, is_hand_crafted INTEGER, is_recommended INTEGER);
        CREATE TABLE fixed_band_10(preset_id INTEGER, band_index INTEGER, gain REAL);
        CREATE TABLE graphic_eq_31(preset_id INTEGER, band_index INTEGER, gain REAL);
        CREATE TABLE metadata(key TEXT, value TEXT);
        INSERT INTO metadata VALUES('version', '2026-10-03');
        INSERT INTO headphones VALUES(1, 'Apple', 'AirPods Pro (2nd gen)', NULL, 'fixture');
        INSERT INTO presets VALUES(1, 1, NULL, NULL, NULL, \(preamp), 0, 1);
        """
        for index in 0..<bands10 {
            sql += "INSERT INTO fixed_band_10 VALUES(1, \(index), \(gain));\n"
        }
        for index in 0..<bands31 {
            sql += "INSERT INTO graphic_eq_31 VALUES(1, \(index), \(gain));\n"
        }
        if fts {
            sql += """
            CREATE VIRTUAL TABLE headphones_fts USING fts5(brand, model, type, content='headphones', content_rowid='id');
            INSERT INTO headphones_fts(headphones_fts) VALUES('rebuild');
            """
        }
        var error: UnsafeMutablePointer<CChar>?
        let status = sqlite3_exec(writer, sql, nil, nil, &error)
        let message = error.map { String(cString: $0) } ?? "SQLite fixture failed"
        sqlite3_free(error)
        XCTAssertEqual(status, SQLITE_OK, message)
        guard status == SQLITE_OK else { return }
        sqlite3_close(writer)
        writer = nil
        let database = EQDatabase(databaseURL: url)
        XCTAssertTrue(database.isAvailable)
        body(database)
    }

    func testPunctuationSearchAndNullableMetadata() throws {
        try withFixture(fts: true) { database in
            XCTAssertEqual(database.searchHeadphones("AirPods Pro (2nd gen)").first?.id, 1)
            XCTAssertEqual(database.searchHeadphones("\"AirPods\" - Pro^").first?.id, 1)
            let loaded = AutoEQDatabaseService(database: database).load(headphoneID: 1)
            XCTAssertEqual(loaded?.preset.author, "fixture")
            XCTAssertEqual(loaded?.preset.source, "fixture")
            XCTAssertEqual(loaded?.preset.targetCurve, AppConstants.EQ.defaultTarget)
            XCTAssertEqual(loaded?.gains10.count, 10)
            XCTAssertEqual(loaded?.gains31.count, 31)
        }
    }

    func testMissingFTSTableFallsBackToLike() throws {
        try withFixture { database in
            XCTAssertEqual(database.searchHeadphones("AirPods Pro").first?.id, 1)
            XCTAssertEqual(database.readVersion(), "2026-10-03")
        }
    }

    func testIncompleteAndNonFinitePresetsAreRejected() throws {
        for counts in [(9, 31), (10, 30)] {
            try withFixture(bands10: counts.0, bands31: counts.1) { database in
                XCTAssertNil(AutoEQDatabaseService(database: database).load(headphoneID: 1))
            }
        }
        try withFixture(gain: "1e999") { database in
            XCTAssertNil(AutoEQDatabaseService(database: database).load(headphoneID: 1))
        }
        try withFixture(preamp: "1e999") { database in
            XCTAssertNil(AutoEQDatabaseService(database: database).load(headphoneID: 1))
        }
    }

    func testMissingDatabaseIsUnavailable() {
        XCTAssertFalse(EQDatabase(databaseURL: nil).isAvailable)
    }
}

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

    func testDatabaseCandidate_usesStableDatabasePath() {
        let headphone = DatabaseHeadphone(
            id: 42,
            brand: "Sennheiser",
            model: "HD 600",
            type: "over-ear",
            source: "oratory1990"
        )

        let candidate = AutoEQView.databaseCandidate(headphone)

        XCTAssertTrue(candidate.path.hasPrefix("database:"))
        XCTAssertEqual(candidate.name, "42")
        XCTAssertEqual(candidate.display, "Sennheiser HD 600 · oratory1990")
        XCTAssertEqual(AutoEQView.databaseSource(from: candidate), "oratory1990")
        let identity = AutoEQView.databaseIdentity(from: candidate.path)
        XCTAssertEqual(identity?.brand, "Sennheiser")
        XCTAssertEqual(identity?.model, "HD 600")
        XCTAssertEqual(identity?.source, "oratory1990")

        let rebuiltDatabaseRow = DatabaseHeadphone(
            id: 9001,
            brand: headphone.brand,
            model: headphone.model,
            type: headphone.type,
            source: headphone.source
        )
        XCTAssertEqual(AutoEQView.databaseCandidate(rebuiltDatabaseRow).path, candidate.path)
    }

    func testDirectBands_preservesDatabaseGains() throws {
        let centers = [31.5, 63.0, 125.0]
        let gains: [Float] = [-1.5, 2.25, 0.0]

        let bands = try XCTUnwrap(AutoEQView.directBands(centers: centers, gains: gains))

        XCTAssertEqual(bands.map(\.freq), centers)
        XCTAssertEqual(bands.map(\.gain), gains.map(Double.init))
    }

    func testDirectBands_rejectsInvalidDatabaseRows() {
        XCTAssertNil(AutoEQView.directBands(centers: [31.5], gains: []))
        XCTAssertNil(AutoEQView.directBands(centers: [31.5], gains: [.nan]))
    }

    func testBundledDatabase_providesSearchableTenAndThirtyOneBandPreset() throws {
        let database = EQDatabase.shared
        XCTAssertTrue(database.isAvailable)

        let headphone = try XCTUnwrap(database.searchHeadphones("Sennheiser HD 600").first(where: {
            $0.brand == "Sennheiser" && $0.model == "HD 600" && $0.source == "oratory1990"
        }))
        let preset = try XCTUnwrap(database.getRecommendedPreset(for: headphone.id))
        let gains10 = database.getFixedBand10(presetId: preset.id)
        let gains31 = database.getGraphicEQ31(presetId: preset.id)

        XCTAssertEqual(gains10.count, 10)
        XCTAssertEqual(gains31.count, 31)
        XCTAssertNotNil(AutoEQView.directBands(
            centers: AutoEQConstants.tenBandFrequencies.map(Double.init),
            gains: gains10
        ))
        XCTAssertNotNil(AutoEQView.directBands(
            centers: AutoEQConstants.thirtyOneBandFrequencies.map(Double.init),
            gains: gains31
        ))
    }

    func testDatabaseServiceLoadsBothModesWithoutView() throws {
        let service = AutoEQDatabaseService(database: .shared)
        let id = try XCTUnwrap(service.headphoneID(
            brand: "Sennheiser", model: "HD 800", source: "Innerfidelity"
        ))
        let imported = try XCTUnwrap(service.load(headphoneID: id))
        XCTAssertEqual(imported.gains10.count, 10)
        XCTAssertEqual(imported.gains31.count, 31)
        XCTAssertEqual(imported.preset.headphoneId, id)
        XCTAssertNil(service.load(headphoneID: -1))
    }

    func testExactHeadphoneLookupPreservesSourceAndRejectsPartialIdentity() throws {
        let database = EQDatabase.shared
        let headphone = try XCTUnwrap(database.headphone(
            brand: "Sennheiser", model: "HD 800", source: "Innerfidelity"
        ))
        XCTAssertEqual(headphone.model, "HD 800")
        XCTAssertEqual(headphone.source, "Innerfidelity")
        let results = database.searchHeadphones("Sennheiser HD 800")
        XCTAssertEqual(results.first?.model, "HD 800")
        XCTAssertTrue(results.contains { $0.id == headphone.id })
        XCTAssertNotNil(database.getRecommendedPreset(for: headphone.id))
        XCTAssertNil(database.headphone(brand: "Sennheiser", model: "HD 80", source: "Innerfidelity"))
        XCTAssertNil(database.headphone(brand: "Sennheiser", model: "HD 800", source: "missing"))
    }

    func testBundledDatabase_presetMetadataFallsBackWhenStoredFieldsAreEmpty() throws {
        let database = EQDatabase.shared
        XCTAssertTrue(database.isAvailable)

        let headphone = try XCTUnwrap(database.searchHeadphones("Sennheiser HD 600").first(where: {
            $0.brand == "Sennheiser" && $0.model == "HD 600" && $0.source == "oratory1990"
        }))
        let preset = try XCTUnwrap(database.getRecommendedPreset(for: headphone.id))

        XCTAssertEqual(preset.source, headphone.source)
        XCTAssertEqual(preset.author, headphone.source)
        XCTAssertFalse(preset.targetCurve.isEmpty)
        XCTAssertFalse(preset.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}
