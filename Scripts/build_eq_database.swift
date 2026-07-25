#!/usr/bin/env swift

import Foundation
import SQLite3

// MARK: - Data Models

struct HeadphoneEntry {
    let brand: String
    let model: String
    let type: String
    let source: String
    let measurementRig: String
}

struct PresetEntry {
    let headphoneKey: String
    let source: String
    let author: String
    let targetCurve: String
    let preampGain: Float
    let isHandCrafted: Bool
    let isRecommended: Bool
    let bands10: [Float]
    let bands31: [Float]
    let parametricBands: [ParametricBandEntry]
}

struct ParametricBandEntry {
    let filterType: String
    let frequency: Double
    let gain: Float
    let qFactor: Float
}

struct OfflineIndexEntry: Codable {
    let brand: String
    let model: String
    let source: String
    let type: String
    var pathFixedBandEQ: String?
    var pathGraphicEQ: String?
    var pathParametric: String?
    var pathReadme: String?
}

// MARK: - Database Builder

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

class EQDatabaseBuilder {
    private var db: OpaquePointer?
    private let dbPath: String
    private var headphones: [String: Int] = [:]
    private var nextHeadphoneId = 1
    private var nextPresetId = 1
    
    init(dbPath: String) {
        self.dbPath = dbPath
    }
    
    func build() throws {
        print("🏗️  Building EQ Database...")
        
        // 1. Create database
        try createDatabase()
        
        // 2. Parse AutoEQ index
        print("📂 Parsing AutoEQ index...")
        let autoEQData = try parseAutoEQIndex()
        print("   Found \(autoEQData.count) entries")
        
        // 3. Insert data
        print("💾 Inserting data into database...")
        try insertData(autoEQData)
        
        // 4. Create indexes
        print("🔍 Creating search indexes...")
        try createIndexes()
        
        // 5. Insert metadata (version)
        print("📝 Adding metadata...")
        try insertMetadata()
        
        // 6. Optimize
        print("⚡ Optimizing database...")
        try optimize()
        
        sqlite3_close(db)
        
        let fileSize = try getFileSize(dbPath)
        print("✅ Database built successfully!")
        print("   Path: \(dbPath)")
        print("   Size: \(fileSize) MB")
    }
    
    private func createDatabase() throws {
        // Remove old database
        try? FileManager.default.removeItem(atPath: dbPath)
        
        // Open new database
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else {
            throw NSError(domain: "Cannot create database", code: -1)
        }
        
        // Create tables
        let schema = """
        -- Headphones table
        CREATE TABLE headphones (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            brand TEXT NOT NULL,
            model TEXT NOT NULL,
            type TEXT NOT NULL,
            source TEXT NOT NULL,
            measurement_rig TEXT,
            UNIQUE(brand, model, source)
        );
        
        -- Presets table
        CREATE TABLE presets (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            headphone_id INTEGER NOT NULL,
            source TEXT NOT NULL,
            author TEXT NOT NULL,
            target_curve TEXT NOT NULL,
            preamp_gain REAL NOT NULL,
            is_hand_crafted INTEGER DEFAULT 0,
            is_recommended INTEGER DEFAULT 0,
            date_created TEXT,
            FOREIGN KEY (headphone_id) REFERENCES headphones(id)
        );
        
        -- Fixed-band 10 (pre-calculated)
        CREATE TABLE fixed_band_10 (
            preset_id INTEGER NOT NULL,
            band_index INTEGER NOT NULL,
            frequency REAL NOT NULL,
            gain REAL NOT NULL,
            PRIMARY KEY (preset_id, band_index),
            FOREIGN KEY (preset_id) REFERENCES presets(id)
        );
        
        -- Graphic EQ 31 (pre-calculated)
        CREATE TABLE graphic_eq_31 (
            preset_id INTEGER NOT NULL,
            band_index INTEGER NOT NULL,
            frequency REAL NOT NULL,
            gain REAL NOT NULL,
            PRIMARY KEY (preset_id, band_index),
            FOREIGN KEY (preset_id) REFERENCES presets(id)
        );
        
        -- Parametric bands (variable)
        CREATE TABLE parametric_bands (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            preset_id INTEGER NOT NULL,
            band_index INTEGER NOT NULL,
            filter_type TEXT NOT NULL,
            frequency REAL NOT NULL,
            gain REAL NOT NULL,
            q_factor REAL NOT NULL,
            FOREIGN KEY (preset_id) REFERENCES presets(id)
        );
        
        -- Database metadata (version tracking)
        CREATE TABLE metadata (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );
        """
        
        try executeSQL(schema)
    }
    
    private func parseAutoEQIndex() throws -> [OfflineIndexEntry] {
        // Try multiple paths for flexibility
        let possiblePaths = [
            "Scripts/AutoEqIndex.json",           // When run from project root
            "AutoEqIndex.json",                   // When run from Scripts folder
            "SystemEQ for Mac/AutoEqIndex.json"   // Legacy path
        ]
        
        for path in possiblePaths {
            let indexURL = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: path) {
                let data = try Data(contentsOf: indexURL)
                return try JSONDecoder().decode([OfflineIndexEntry].self, from: data)
            }
        }
        
        throw NSError(domain: "AutoEqIndex.json not found", code: -1)
    }
    
    private func insertData(_ entries: [OfflineIndexEntry]) throws {
        let tenCenters: [Double] = [31.5, 63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
        let thirtyOneCenters: [Double] = [20, 25, 31.5, 40, 50, 63, 80, 100, 125, 160, 200, 250, 315, 400, 500, 630, 800, 1000, 1250, 1600, 2000, 2500, 3150, 4000, 5000, 6300, 8000, 10000, 12500, 16000, 20000]
        
        var processedCount = 0
        
        for entry in entries {
            // Insert headphone
            let headphoneId = try insertHeadphone(
                brand: entry.brand,
                model: entry.model,
                type: entry.type,
                source: entry.source
            )
            
            // Parse and insert preset
            var bands10: [Float] = []
            var bands31: [Float] = []
            var preampGain: Float = 0.0
            var parametricBands: [ParametricBandEntry] = []
            
            // Try to parse FixedBandEQ.txt (10-band)
            if let fixedPath = entry.pathFixedBandEQ {
                let fullPath = "AutoEq/\(fixedPath)"
                if let result = parseFixedBandEQFile(path: fullPath) {
                    bands10 = result.bands.map { Float($0.gain) }
                    preampGain = Float(result.preamp ?? 0.0)
                }
            }
            
            // Try to parse GraphicEQ.txt (31-band)
            if let graphicPath = entry.pathGraphicEQ {
                let fullPath = "AutoEq/\(graphicPath)"
                if let result = parseGraphicEQFile(path: fullPath) {
                    // Map to 31-band centers
                    bands31 = thirtyOneCenters.map { center in
                        if let closest = result.bands.min(by: { abs($0.freq - center) < abs($1.freq - center) }) {
                            return Float(closest.gain)
                        }
                        return 0.0
                    }
                    if preampGain == 0.0 {
                        preampGain = Float(result.preamp ?? 0.0)
                    }
                }
            }
            
            // Try to parse ParametricEQ.txt
            if let parametricPath = entry.pathParametric {
                let fullPath = "AutoEq/\(parametricPath)"
                if let result = parseParametricEQFile(path: fullPath) {
                    parametricBands = result.bands.map { band in
                        ParametricBandEntry(
                            filterType: band.type,
                            frequency: band.freq,
                            gain: Float(band.gain),
                            qFactor: Float(band.q)
                        )
                    }
                    if preampGain == 0.0 {
                        preampGain = Float(result.preamp ?? 0.0)
                    }
                }
            }
            
            // If we have at least 10-band or 31-band data, insert preset
            if !bands10.isEmpty || !bands31.isEmpty {
                // Determine if hand-crafted (oratory1990)
                let isHandCrafted = entry.source.lowercased().contains("oratory")
                
                let presetId = try insertPreset(
                    headphoneId: headphoneId,
                    source: entry.source,
                    author: entry.source,
                    targetCurve: "JM-1 with Harman filters",
                    preampGain: preampGain,
                    isHandCrafted: isHandCrafted,
                    isRecommended: isHandCrafted
                )
                
                // Insert 10-band data
                if !bands10.isEmpty {
                    for (index, gain) in bands10.enumerated() {
                        try insertFixedBand10(
                            presetId: presetId,
                            bandIndex: index,
                            frequency: tenCenters[index],
                            gain: gain
                        )
                    }
                }
                
                // Insert 31-band data
                if !bands31.isEmpty {
                    for (index, gain) in bands31.enumerated() {
                        try insertGraphicEQ31(
                            presetId: presetId,
                            bandIndex: index,
                            frequency: thirtyOneCenters[index],
                            gain: gain
                        )
                    }
                }
                
                // Insert parametric bands
                for (index, band) in parametricBands.enumerated() {
                    try insertParametricBand(
                        presetId: presetId,
                        bandIndex: index,
                        band: band
                    )
                }
                
                processedCount += 1
                if processedCount % 100 == 0 {
                    print("   Processed \(processedCount) presets...")
                }
            }
        }
        
        print("   Total presets inserted: \(processedCount)")
    }
    
    private func insertHeadphone(brand: String, model: String, type: String, source: String) throws -> Int {
        let key = "\(brand)_\(model)_\(source)"
        
        if let existingId = headphones[key] {
            return existingId
        }
        
        // Try to insert, ignore if exists
        let insertSQL = """
        INSERT OR IGNORE INTO headphones (brand, model, type, source, measurement_rig)
        VALUES (?, ?, ?, ?, ?)
        """
        
        var insertStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, insertSQL, -1, &insertStmt, nil) == SQLITE_OK else {
            throw NSError(domain: "Cannot prepare headphone insert", code: -1)
        }
        defer { sqlite3_finalize(insertStmt) }
        
        _ = (brand as NSString).utf8String.map { sqlite3_bind_text(insertStmt, 1, $0, -1, SQLITE_TRANSIENT) }
        _ = (model as NSString).utf8String.map { sqlite3_bind_text(insertStmt, 2, $0, -1, SQLITE_TRANSIENT) }
        _ = (type as NSString).utf8String.map { sqlite3_bind_text(insertStmt, 3, $0, -1, SQLITE_TRANSIENT) }
        _ = (source as NSString).utf8String.map { sqlite3_bind_text(insertStmt, 4, $0, -1, SQLITE_TRANSIENT) }
        sqlite3_bind_text(insertStmt, 5, "Unknown", -1, SQLITE_TRANSIENT)
        
        sqlite3_step(insertStmt)
        
        // Get the ID (either newly inserted or existing)
        let selectSQL = "SELECT id FROM headphones WHERE brand = ? AND model = ? AND source = ?"
        var selectStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, selectSQL, -1, &selectStmt, nil) == SQLITE_OK else {
            throw NSError(domain: "Cannot select headphone", code: -1)
        }
        defer { sqlite3_finalize(selectStmt) }
        
        _ = (brand as NSString).utf8String.map { sqlite3_bind_text(selectStmt, 1, $0, -1, SQLITE_TRANSIENT) }
        _ = (model as NSString).utf8String.map { sqlite3_bind_text(selectStmt, 2, $0, -1, SQLITE_TRANSIENT) }
        _ = (source as NSString).utf8String.map { sqlite3_bind_text(selectStmt, 3, $0, -1, SQLITE_TRANSIENT) }
        
        guard sqlite3_step(selectStmt) == SQLITE_ROW else {
            throw NSError(domain: "Cannot find headphone after insert", code: -1)
        }
        
        let id = Int(sqlite3_column_int(selectStmt, 0))
        headphones[key] = id
        return id
    }
    
    private func insertPreset(headphoneId: Int, source: String, author: String, targetCurve: String, preampGain: Float, isHandCrafted: Bool, isRecommended: Bool) throws -> Int {
        let sql = """
        INSERT INTO presets (headphone_id, source, author, target_curve, preamp_gain, is_hand_crafted, is_recommended, date_created)
        VALUES (?, ?, ?, ?, ?, ?, ?, datetime('now'))
        """
        
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw NSError(domain: "Cannot prepare preset insert", code: -1)
        }
        defer { sqlite3_finalize(statement) }
        
        sqlite3_bind_int(statement, 1, Int32(headphoneId))
        sqlite3_bind_text(statement, 2, source, -1, nil)
        sqlite3_bind_text(statement, 3, author, -1, nil)
        sqlite3_bind_text(statement, 4, targetCurve, -1, nil)
        sqlite3_bind_double(statement, 5, Double(preampGain))
        sqlite3_bind_int(statement, 6, isHandCrafted ? 1 : 0)
        sqlite3_bind_int(statement, 7, isRecommended ? 1 : 0)
        
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw NSError(domain: "Cannot insert preset", code: -1)
        }
        
        return Int(sqlite3_last_insert_rowid(db))
    }
    
    private func insertFixedBand10(presetId: Int, bandIndex: Int, frequency: Double, gain: Float) throws {
        let sql = "INSERT INTO fixed_band_10 (preset_id, band_index, frequency, gain) VALUES (?, ?, ?, ?)"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        
        sqlite3_bind_int(statement, 1, Int32(presetId))
        sqlite3_bind_int(statement, 2, Int32(bandIndex))
        sqlite3_bind_double(statement, 3, frequency)
        sqlite3_bind_double(statement, 4, Double(gain))
        
        sqlite3_step(statement)
    }
    
    private func insertGraphicEQ31(presetId: Int, bandIndex: Int, frequency: Double, gain: Float) throws {
        let sql = "INSERT INTO graphic_eq_31 (preset_id, band_index, frequency, gain) VALUES (?, ?, ?, ?)"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        
        sqlite3_bind_int(statement, 1, Int32(presetId))
        sqlite3_bind_int(statement, 2, Int32(bandIndex))
        sqlite3_bind_double(statement, 3, frequency)
        sqlite3_bind_double(statement, 4, Double(gain))
        
        sqlite3_step(statement)
    }
    
    private func insertParametricBand(presetId: Int, bandIndex: Int, band: ParametricBandEntry) throws {
        let sql = "INSERT INTO parametric_bands (preset_id, band_index, filter_type, frequency, gain, q_factor) VALUES (?, ?, ?, ?, ?, ?)"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        
        sqlite3_bind_int(statement, 1, Int32(presetId))
        sqlite3_bind_int(statement, 2, Int32(bandIndex))
        sqlite3_bind_text(statement, 3, band.filterType, -1, nil)
        sqlite3_bind_double(statement, 4, band.frequency)
        sqlite3_bind_double(statement, 5, Double(band.gain))
        sqlite3_bind_double(statement, 6, Double(band.qFactor))
        
        sqlite3_step(statement)
    }
    
    private func createIndexes() throws {
        let indexes = """
        CREATE INDEX idx_headphones_brand ON headphones(brand);
        CREATE INDEX idx_headphones_model ON headphones(model);
        CREATE INDEX idx_presets_headphone ON presets(headphone_id);
        CREATE INDEX idx_presets_recommended ON presets(is_recommended);
        
        CREATE VIRTUAL TABLE headphones_fts USING fts5(
            brand, model, type, content=headphones, content_rowid=id
        );
        
        INSERT INTO headphones_fts(rowid, brand, model, type)
        SELECT id, brand, model, type FROM headphones;
        """
        
        try executeSQL(indexes)
    }
    
    private func insertMetadata() throws {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let buildDate = dateFormatter.string(from: Date())
        
        // Version format: YYYY-MM-DD
        let sql = """
        INSERT INTO metadata (key, value) VALUES
            ('version', '\(buildDate)'),
            ('build_date', '\(buildDate)'),
            ('source', 'AutoEQ'),
            ('schema_version', '1')
        """
        try executeSQL(sql)
        print("   Version: \(buildDate)")
    }
    
    private func optimize() throws {
        try executeSQL("VACUUM")
        try executeSQL("ANALYZE")
    }
    
    private func executeSQL(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &error) == SQLITE_OK else {
            if let error = error {
                let message = String(cString: error)
                sqlite3_free(error)
                throw NSError(domain: message, code: -1)
            }
            throw NSError(domain: "SQL execution failed", code: -1)
        }
    }
    
    // MARK: - File Parsers
    
    private func parseFixedBandEQFile(path: String) -> (bands: [(freq: Double, gain: Double)], preamp: Double?)? {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        
        var bands: [(freq: Double, gain: Double)] = []
        var preamp: Double?
        
        for line in content.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Parse preamp: "Preamp: -6.4 dB"
            if trimmed.hasPrefix("Preamp:") {
                let parts = trimmed.split(separator: " ")
                if parts.count >= 2, let value = Double(parts[1]) {
                    preamp = value
                }
            }
            
            // Parse filter: "Filter 1: ON PK Fc 31 Hz Gain 6.4 dB Q 1.41"
            if trimmed.hasPrefix("Filter") {
                let parts = trimmed.split(separator: " ")
                var freq: Double?
                var gain: Double?
                
                for i in 0..<parts.count {
                    if parts[i] == "Fc" && i + 1 < parts.count {
                        freq = Double(parts[i + 1])
                    }
                    if parts[i] == "Gain" && i + 1 < parts.count {
                        gain = Double(parts[i + 1])
                    }
                }
                
                if let f = freq, let g = gain {
                    bands.append((freq: f, gain: g))
                }
            }
        }
        
        return bands.isEmpty ? nil : (bands: bands, preamp: preamp)
    }
    
    private func parseGraphicEQFile(path: String) -> (bands: [(freq: Double, gain: Double)], preamp: Double?)? {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        
        var bands: [(freq: Double, gain: Double)] = []
        var preamp: Double?
        
        for line in content.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Parse preamp
            if trimmed.hasPrefix("Preamp:") {
                let parts = trimmed.split(separator: " ")
                if parts.count >= 2, let value = Double(parts[1]) {
                    preamp = value
                }
            }
            
            // Parse GraphicEQ: "GraphicEQ: 20 -0.2; 21 -0.2; ..."
            if trimmed.hasPrefix("GraphicEQ:") {
                let eqPart = trimmed.replacingOccurrences(of: "GraphicEQ:", with: "").trimmingCharacters(in: .whitespaces)
                let pairs = eqPart.split(separator: ";")
                
                for pair in pairs {
                    let values = pair.trimmingCharacters(in: .whitespaces).split(separator: " ")
                    if values.count == 2,
                       let freq = Double(values[0]),
                       let gain = Double(values[1]) {
                        bands.append((freq: freq, gain: gain))
                    }
                }
            }
        }
        
        return bands.isEmpty ? nil : (bands: bands, preamp: preamp)
    }
    
    private func parseParametricEQFile(path: String) -> (bands: [(type: String, freq: Double, gain: Double, q: Double)], preamp: Double?)? {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        
        var bands: [(type: String, freq: Double, gain: Double, q: Double)] = []
        var preamp: Double?
        
        for line in content.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Parse preamp
            if trimmed.hasPrefix("Preamp:") {
                let parts = trimmed.split(separator: " ")
                if parts.count >= 2, let value = Double(parts[1]) {
                    preamp = value
                }
            }
            
            // Parse filter: "Filter 1: ON PK Fc 105 Hz Gain 6.5 dB Q 0.69"
            if trimmed.hasPrefix("Filter") {
                let parts = trimmed.split(separator: " ")
                var filterType = "PK"
                var freq: Double?
                var gain: Double?
                var q: Double?
                
                for i in 0..<parts.count {
                    if parts[i] == "ON" && i + 1 < parts.count {
                        filterType = String(parts[i + 1])
                    }
                    if parts[i] == "Fc" && i + 1 < parts.count {
                        freq = Double(parts[i + 1])
                    }
                    if parts[i] == "Gain" && i + 1 < parts.count {
                        gain = Double(parts[i + 1])
                    }
                    if parts[i] == "Q" && i + 1 < parts.count {
                        q = Double(parts[i + 1])
                    }
                }
                
                if let f = freq, let g = gain, let qVal = q {
                    bands.append((type: filterType, freq: f, gain: g, q: qVal))
                }
            }
        }
        
        return bands.isEmpty ? nil : (bands: bands, preamp: preamp)
    }
    
    private func getFileSize(_ path: String) throws -> String {
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        let size = attributes[.size] as! UInt64
        let sizeMB = Double(size) / 1024.0 / 1024.0
        return String(format: "%.1f", sizeMB)
    }
}

// MARK: - Main

let outputPath = "SystemEQ for Mac/Resources/EQDatabase.db"
let builder = EQDatabaseBuilder(dbPath: outputPath)

do {
    try builder.build()
} catch {
    print("❌ Error: \(error)")
    exit(1)
}
