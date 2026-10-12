import SQLite3
@testable import SystemEQ_for_Mac
import XCTest

@MainActor
final class AutoEQImportTests: XCTestCase {
    func testUnknownMalformedAndPartialFiltersFailClosed() {
        for text in [
            "Filter 1: ON UNKNOWN Fc 1000 Hz Gain 3 dB Q 1",
            "Filter 1: ON PK Fc 1000 Hz Gain 3 dB Q 1\nFilter 2: ON PK Fc broken Hz Gain 2 dB Q 1",
            "Preamp: -3 dB\nPreamp: -2 dB\nFilter 1: ON PK Fc 1000 Hz Gain 3 dB Q 1",
            "Channel: L\nFilter 1: ON PK Fc 1000 Hz Gain 3 dB Q 1",
            "Filter 1: ON PK Fc 1000 Hz Gain 3 dB Q 0",
            "Filter 1: ON PK Fc 1000 Hz Gain 1e999 dB Q 1"
        ] {
            XCTAssertThrowsError(try AutoEQImportParser.parse(text), text)
        }
    }

    func testGraphicDuplicatesAndMixedFormatsAreRejected() {
        for text in [
            "GraphicEQ: 100 -3; 100 2",
            "GraphicEQ: 1000 -3; 100 2",
            "GraphicEQ: 100 nan; 1000 0",
            "GraphicEQ: 100 -3; 1000 0\nFilter 1: ON PK Fc 1000 Hz Gain 3 dB Q 1"
        ] {
            XCTAssertThrowsError(try AutoEQImportParser.parse(text))
        }
    }

    func testMalformedTableRowsCannotBeMistakenForHeaders() throws {
        let table = """
        ## Parametric EQ
        Preamp: -3 dB
        | # | Type | Fc (Hz) | Q | Gain (dB) |
        | --- | --- | --- | --- | --- |
        | 1 | PK | 1000 | 1 | 3 |
        """
        guard case let .parametric(filters) = try AutoEQImportParser.parse(table).response else {
            return XCTFail("Expected table filters")
        }
        XCTAssertEqual(filters.count, 1)
        for row in [
            "| 2 | PK | Fc broken | 1 | 4 |",
            "| 2 | Type | 2000 | 1 | 4 |",
            "| 2 | PK | 2000 | --- | 4 |",
            "| 2 | PK | 2000 | | 1 | 4 |"
        ] {
            XCTAssertThrowsError(try AutoEQImportParser.parse(table + "\n" + row))
        }
        XCTAssertThrowsError(try AutoEQImportParser.parse(table.replacingOccurrences(of: "-3 dB", with: "broken dB")))
    }

    func testLargeHighFrequencyErrorRequiresExplicitApply() throws {
        let preset = try AutoEQImportParser.parse("Preamp: -3 dB\nFilter 1: ON PK Fc 16000 Hz Gain -15 dB Q 10")
        let prepared = try EQConverter(sampleRate: 48000).prepare(preset)
        for result in [prepared.ten, prepared.thirtyOne] {
            XCTAssertLessThan(result.rms, 1)
            XCTAssertGreaterThan(result.maximumError, 3)
            XCTAssertTrue(result.requiresApply)
        }
    }

    func testParametricFieldsBandwidthDisabledAndPreampArePreserved() throws {
        let preset = try AutoEQImportParser
            .parse("Preamp: -7.5 dB\nFilter 1: ON HP Fc 20 Hz Q 0.7\nFilter 2: OFF PK Fc 1250 Hz Gain -16 dB BW Oct 1")
        guard case let .parametric(filters) = preset.response else { return XCTFail("Expected parametric source") }
        XCTAssertEqual(filters.count, 2)
        XCTAssertEqual(filters[0].type, .highPass)
        XCTAssertEqual(filters[1].gain, -16)
        XCTAssertFalse(filters[1].enabled)
        XCTAssertEqual(filters[1].q, sqrt(2), accuracy: 0.00001)
        XCTAssertEqual(preset.preamp, -7.5)
    }

    func testFlatPreampOnlyRemainsUnityWithoutDoubleTrim() throws {
        let preset = try AutoEQImportParser.parse("Preamp: -3 dB")
        let result = try EQConverter(sampleRate: 48000).prepare(preset)
        XCTAssertTrue(result.ten.gains.allSatisfy { $0 == 0 })
        XCTAssertTrue(result.thirtyOne.gains.allSatisfy { $0 == 0 })
        XCTAssertEqual(result.ten.preamp, -3)
        XCTAssertEqual(result.thirtyOne.preamp, -3)
        XCTAssertFalse(result.ten.preampAdjusted)
    }

    func testGraphicPointsAreAnInterpolatedCurveRatherThanSummedPeaks() throws {
        let preset = try AutoEQImportParser.parse("GraphicEQ: 20 0; 100 0; 1000 0; 20000 0")
        guard case let .graphic(points) = preset.response else { return XCTFail("Expected curve points") }
        XCTAssertEqual(points.count, 4)
        let result = try EQConverter(sampleRate: 48000).prepare(preset)
        XCTAssertTrue(result.thirtyOne.gains.allSatisfy { $0 == 0 })
        XCTAssertEqual(result.thirtyOne.preamp, 0)
    }

    func testCanonicalDatabaseFitUsesIndependentDenseErrorAndHeadroom() throws {
        let database = EQDatabase.shared
        let headphones = database.searchHeadphones("Sennheiser HD 600")
        let headphone = try XCTUnwrap(headphones.first { $0.source.lowercased() == "oratory1990" })
        let input = try AutoEQDatabaseService(database: database).loadCanonical(headphoneID: headphone.id).input
        XCTAssertTrue(input.legacyPreamp)
        for rate in [48000.0, 96000.0] {
            let result = try EQConverter(sampleRate: rate).prepare(input)
            XCTAssertEqual(result.ten.gains.count, 10)
            XCTAssertEqual(result.thirtyOne.gains.count, 31)
            XCTAssertLessThan(result.thirtyOne.rms, 0.4)
            XCTAssertLessThan(result.ten.rms, 0.9)
            for (mode, fit) in [(EQBandMode.tenBand, result.ten), (.thirtyOneBand, result.thirtyOne)] {
                XCTAssertTrue(fit.gains.allSatisfy { $0.isFinite && abs($0) <= 20 })
                let coefficients = FixedBandEQDefinition.bands(mode: mode, gains: fit.gains).map {
                    BiquadResponseCalculator.coefficients(
                        frequency: $0.frequency,
                        gain: $0.gain,
                        q: $0.q,
                        type: $0.filterType,
                        sampleRate: Float(rate)
                    )
                }
                var peak = 0.0
                for index in 0..<8192 {
                    let frequency = pow(rate * 0.499, Double(index) / 8191)
                    let gain = try coefficients.reduce(0.0) { try $0 + EQConverter.response(
                        $1,
                        frequency: frequency,
                        rate: rate
                    ) }
                    peak = max(peak, gain)
                }
                XCTAssertLessThanOrEqual(peak + Double(fit.preamp), -0.18)
            }
        }
    }

    func testInvalidRateExtremeTrimAndCancellationCannotProducePreparedResult() async throws {
        let input = try AutoEQImportParser.parse("Preamp: -40 dB\nFilter 1: ON PK Fc 1000 Hz Gain 3 dB Q 1")
        XCTAssertThrowsError(try EQConverter(sampleRate: .nan).prepare(input))
        XCTAssertThrowsError(try EQConverter(sampleRate: 48000).prepare(input))
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try EQConverter(sampleRate: 48000).prepare(input)
        }
        do {
            _ = try await task.value
            XCTFail("Cancellation must not succeed")
        } catch is CancellationError {}
    }

    func testFittedPresetsRenderThroughProductionVDSPAtBothRates() throws {
        for query in ["HD 600", "ER2XR", "WH-1000XM4"] {
            let headphone = try XCTUnwrap(EQDatabase.shared.searchHeadphones(query)
                .first { $0.source.lowercased() == "oratory1990" })
            let input = try AutoEQDatabaseService(database: .shared).loadCanonical(headphoneID: headphone.id).input
            guard case let .parametric(source) = input.response else { return XCTFail("Expected canonical filters") }
            let original = source.filter(\.enabled).map {
                ParametricBand(
                    frequency: Float($0.frequency),
                    gain: Float($0.gain),
                    q: Float($0.q),
                    filterType: $0.type
                )
            }
            for rate in [48000.0, 96000.0] {
                let prepared = try EQConverter(sampleRate: rate).prepare(input)
                for mode in [EQBandMode.tenBand, .thirtyOneBand] {
                    let fit = prepared.result(for: mode)
                    let bands = FixedBandEQDefinition.bands(mode: mode, gains: fit.gains)
                    let errors = [125.0, 250, 500, 1000, 2000, 4000, 6000].map {
                        renderedGain(bands, frequency: $0, rate: rate) - renderedGain(
                            original,
                            frequency: $0,
                            rate: rate
                        )
                    }
                    let rms = sqrt(errors.reduce(0) { $0 + $1 * $1 } / Double(errors.count))
                    XCTAssertLessThan(rms, mode == .tenBand ? 1.6 : 0.7, "\(query) \(mode) \(rate)")
                    XCTAssertLessThan(try XCTUnwrap(errors.map(abs).max()), fit.maximumError + 0.1)
                }
            }
        }
    }

    private func renderedGain(_ bands: [ParametricBand], frequency: Double, rate: Double) -> Double {
        let filter = BiquadFilterVDSP(sampleRate: Float(rate))
        filter.configure(bands: bands, preamp: 0, sampleRate: Float(rate))
        let count = Int(rate)
        let input = (0..<count).map { Float(0.001 * sin(2 * Double.pi * frequency * Double($0) / rate)) }
        var left = input
        var right = input
        left.withUnsafeMutableBufferPointer { l in
            right.withUnsafeMutableBufferPointer { r in
                guard let leftAddress = l.baseAddress, let rightAddress = r.baseAddress else {
                    XCTFail("Missing render storage")
                    return
                }
                XCTAssertGreaterThan(filter.processStereo(leftAddress, rightAddress, frameCount: count), 0.999)
            }
        }
        XCTAssertTrue(left.allSatisfy(\.isFinite))
        let range = (count / 2)..<count
        let output = range.reduce(0.0) { $0 + Double(left[$1]) * Double(left[$1]) }
        let reference = range.reduce(0.0) { $0 + Double(input[$1]) * Double(input[$1]) }
        return 10 * log10(output / reference)
    }

    func testMissingCanonicalTableAndInvalidRowsAreNotLegacyFallbackSuccess() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("source.sqlite")
        var writer: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &writer), SQLITE_OK)
        defer { if let writer { sqlite3_close(writer) } }
        XCTAssertEqual(
            sqlite3_exec(
                writer,
                "CREATE TABLE presets(id INTEGER PRIMARY KEY, preamp_gain REAL); INSERT INTO presets VALUES(1,-3);",
                nil,
                nil,
                nil
            ),
            SQLITE_OK
        )
        do {
            let database = EQDatabase(databaseURL: url)
            XCTAssertThrowsError(try database.canonicalPreset(presetId: 1))
        }
        XCTAssertEqual(
            sqlite3_exec(
                writer,
                "CREATE TABLE parametric_bands(preset_id INTEGER,band_index INTEGER,filter_type TEXT,frequency REAL,gain REAL,q_factor REAL); INSERT INTO parametric_bands VALUES(1,0,'UNKNOWN',1000,3,1);",
                nil,
                nil,
                nil
            ),
            SQLITE_OK
        )
        do {
            let database = EQDatabase(databaseURL: url)
            XCTAssertThrowsError(try database.canonicalPreset(presetId: 1))
        }
        XCTAssertEqual(
            sqlite3_exec(writer, "UPDATE parametric_bands SET filter_type='PK',q_factor=NULL;", nil, nil, nil),
            SQLITE_OK
        )
        do {
            let database = EQDatabase(databaseURL: url)
            XCTAssertThrowsError(try database.canonicalPreset(presetId: 1))
        }
        for column in ["frequency", "gain", "q_factor"] {
            XCTAssertEqual(
                sqlite3_exec(
                    writer,
                    "UPDATE parametric_bands SET filter_type='PK',frequency=1000,gain=3,q_factor=1;",
                    nil,
                    nil,
                    nil
                ),
                SQLITE_OK
            )
            XCTAssertEqual(
                sqlite3_exec(writer, "UPDATE parametric_bands SET \(column)='broken';", nil, nil, nil),
                SQLITE_OK
            )
            let database = EQDatabase(databaseURL: url)
            XCTAssertThrowsError(try database.canonicalPreset(presetId: 1))
        }
        XCTAssertEqual(
            sqlite3_exec(
                writer,
                "UPDATE parametric_bands SET frequency=1000,gain=3,q_factor=1; UPDATE presets SET preamp_gain='broken';",
                nil,
                nil,
                nil
            ),
            SQLITE_OK
        )
        do {
            let database = EQDatabase(databaseURL: url)
            XCTAssertThrowsError(try database.canonicalPreset(presetId: 1))
        }
        XCTAssertEqual(sqlite3_exec(writer, "UPDATE presets SET preamp_gain=-3;", nil, nil, nil), SQLITE_OK)
        do {
            let database = EQDatabase(databaseURL: url)
            XCTAssertNoThrow(try database.canonicalPreset(presetId: 1))
        }
    }
}
