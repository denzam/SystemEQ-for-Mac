//
//  EQDatabase.swift
//  SystemEQ for Mac
//
//  Unified EQ database client - replaces OPRA + AutoEQ file parsing
//

import Foundation
import SQLite3

/// SQLITE_TRANSIENT tells SQLite to make its own copy of the string
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

// MARK: - Models

struct DatabaseHeadphone: Identifiable, Hashable {
    let id: Int
    let brand: String
    let model: String
    let type: String
    let source: String

    var displayName: String {
        "\(brand) \(model)"
    }

    var searchableText: String {
        "\(brand) \(model) \(type)".lowercased()
    }
}

struct DatabasePreset: Identifiable {
    let id: Int
    let headphoneId: Int
    let source: String
    let author: String
    let targetCurve: String
    let preampGain: Float
    let isHandCrafted: Bool
    let isRecommended: Bool

    var displayName: String {
        if isHandCrafted {
            return "⭐ \(author) (hand-crafted)"
        }
        return "\(author) - \(targetCurve)"
    }
}

struct DatabaseEQBand {
    let frequency: Double
    let gain: Float
}

// MARK: - Database Client

class EQDatabase {
    static let shared = EQDatabase()

    private var db: OpaquePointer?
    private var dbURL: URL?

    /// Indicates if database is available and ready for use
    var isAvailable: Bool {
        db != nil
    }

    private init() {
        // Database is embedded in app bundle (Resources folder)
        guard let bundleURL = Bundle.main.url(forResource: "EQDatabase", withExtension: "db", subdirectory: "Resources")
            ?? Bundle.main.url(forResource: "EQDatabase", withExtension: "db") else {
            dlog("⚠️ EQDatabase.db not found in bundle - AutoEQ features disabled", level: .warning, category: .database)
            self.dbURL = nil
            self.db = nil
            return
        }
        self.dbURL = bundleURL

        // Open read-only (the DB is a bundled resource) with a full mutex so
        // concurrent queries from different threads are serialized inside SQLite.
        let openFlags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(bundleURL.path, &db, openFlags, nil) == SQLITE_OK else {
            dlog("⚠️ Cannot open EQDatabase - AutoEQ features disabled", level: .warning, category: .database)
            self.db = nil
            return
        }

        // Get database stats
        let stats = getDatabaseStats()
        dlog(
            "EQDatabase loaded: \(stats.headphones) headphones, \(stats.presets) presets, \(stats.sizeMB) MB",
            level: .info,
            category: .database
        )
    }

    deinit {
        sqlite3_close(db)
    }

    /// Safe text-column reader: a NULL column returns "" instead of crashing
    /// (String(cString:) traps on a nil pointer).
    private func columnText(_ statement: OpaquePointer?, _ index: Int32) -> String {
        guard let c = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: c)
    }

    // MARK: - Search

    /// Search headphones by query (full-text search with LIKE fallback)
    func searchHeadphones(_ query: String) -> [DatabaseHeadphone] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        // If empty query, return all headphones (limited)
        guard !normalizedQuery.isEmpty else {
            return getAllHeadphones(limit: 100)
        }

        // Try FTS5 first
        var results = searchWithFTS(normalizedQuery)

        // Fallback to LIKE if FTS returns nothing
        if results.isEmpty {
            results = searchWithLike(normalizedQuery)
        }

        return results
    }

    /// Build an FTS5 MATCH expression from free-form user text.
    ///
    /// Punctuation in a model name is FTS5 syntax: "AirPods Pro (2nd gen)" has an
    /// unbalanced paren, a stray `"` opens an unterminated string, `-` and `^` are
    /// operators. Any of those makes sqlite3_step fail, which silently looked like
    /// "no matches". Split on non-alphanumerics and quote every token instead.
    /// Returns nil when nothing searchable is left.
    private func ftsMatchExpression(for query: String) -> String? {
        let tokens = query.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        guard !tokens.isEmpty else { return nil }
        return tokens.map { "\"\($0)\"*" }.joined(separator: " OR ")
    }

    private func searchWithFTS(_ query: String) -> [DatabaseHeadphone] {
        guard let ftsQuery = ftsMatchExpression(for: query) else { return [] }

        let sql = """
        SELECT DISTINCT h.id, h.brand, h.model, h.type, h.source
        FROM headphones h
        JOIN headphones_fts fts ON h.id = fts.rowid
        WHERE headphones_fts MATCH ?
        ORDER BY 
            CASE WHEN h.source = 'oratory1990' THEN 0 ELSE 1 END,
            h.brand, h.model
        LIMIT 100
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, ftsQuery, -1, SQLITE_TRANSIENT)

        var results: [DatabaseHeadphone] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let headphone = parseHeadphoneRow(statement) {
                results.append(headphone)
            }
        }

        return results
    }

    private func searchWithLike(_ query: String) -> [DatabaseHeadphone] {
        // LIKE search as fallback - more flexible matching
        let sql = """
        SELECT DISTINCT id, brand, model, type, source
        FROM headphones
        WHERE brand || ' ' || model LIKE ?
           OR model LIKE ?
           OR brand LIKE ?
        ORDER BY 
            CASE WHEN source = 'oratory1990' THEN 0 ELSE 1 END,
            brand, model
        LIMIT 100
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        let likePattern = "%\(query)%"
        likePattern.withCString { cString in
            sqlite3_bind_text(statement, 1, cString, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_text(statement, 2, cString, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_text(statement, 3, cString, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }

        var results: [DatabaseHeadphone] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let headphone = parseHeadphoneRow(statement) {
                results.append(headphone)
            }
        }

        return results
    }

    private func parseHeadphoneRow(_ statement: OpaquePointer?) -> DatabaseHeadphone? {
        guard let statement,
              let brandPtr = sqlite3_column_text(statement, 1),
              let modelPtr = sqlite3_column_text(statement, 2),
              let typePtr = sqlite3_column_text(statement, 3),
              let sourcePtr = sqlite3_column_text(statement, 4) else {
            return nil
        }

        return DatabaseHeadphone(
            id: Int(sqlite3_column_int(statement, 0)),
            brand: String(cString: brandPtr),
            model: String(cString: modelPtr),
            type: String(cString: typePtr),
            source: String(cString: sourcePtr)
        )
    }

    /// Get all headphones (for browsing)
    func getAllHeadphones(limit: Int = 100) -> [DatabaseHeadphone] {
        let sql = """
        SELECT DISTINCT id, brand, model, type, source
        FROM headphones
        ORDER BY 
            CASE WHEN source = 'oratory1990' THEN 0 ELSE 1 END,
            brand, model
        LIMIT ?
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int(statement, 1, Int32(limit))

        var results: [DatabaseHeadphone] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let headphone = parseHeadphoneRow(statement) {
                results.append(headphone)
            }
        }

        return results
    }

    /// Get all brands (for filtering)
    func getAllBrands() -> [String] {
        let sql = "SELECT DISTINCT brand FROM headphones ORDER BY brand"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        var brands: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let brand = columnText(statement, 0)
            brands.append(brand)
        }
        return brands
    }

    /// Filter headphones by brand
    func filterByBrand(_ brand: String) -> [DatabaseHeadphone] {
        let sql = """
        SELECT id, brand, model, type, source
        FROM headphones
        WHERE brand = ?
        ORDER BY model
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, brand, -1, SQLITE_TRANSIENT)

        var results: [DatabaseHeadphone] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let headphone = parseHeadphoneRow(statement) {
                results.append(headphone)
            }
        }

        return results
    }

    // MARK: - Presets

    /// Get all presets for a headphone
    func getPresets(for headphoneId: Int) -> [DatabasePreset] {
        let sql = """
        SELECT id, headphone_id, source, author, target_curve, preamp_gain,
               is_hand_crafted, is_recommended
        FROM presets
        WHERE headphone_id = ?
        ORDER BY 
            is_recommended DESC,
            is_hand_crafted DESC,
            CASE WHEN author = 'oratory1990' THEN 0 ELSE 1 END,
            CASE WHEN target_curve LIKE '%JM-1%' OR target_curve LIKE '%JM1%' THEN 0 ELSE 1 END,
            source
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int(statement, 1, Int32(headphoneId))

        var presets: [DatabasePreset] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let preset = DatabasePreset(
                id: Int(sqlite3_column_int(statement, 0)),
                headphoneId: Int(sqlite3_column_int(statement, 1)),
                source: columnText(statement, 2),
                author: columnText(statement, 3),
                targetCurve: columnText(statement, 4),
                preampGain: Float(sqlite3_column_double(statement, 5)),
                isHandCrafted: sqlite3_column_int(statement, 6) == 1,
                isRecommended: sqlite3_column_int(statement, 7) == 1
            )
            presets.append(preset)
        }

        return presets
    }

    /// Get recommended preset for headphone
    func getRecommendedPreset(for headphoneId: Int) -> DatabasePreset? {
        let presets = getPresets(for: headphoneId)
        return presets.first { $0.isRecommended } ?? presets.first
    }

    // MARK: - EQ Bands

    /// Get 10-band fixed EQ (instant - pre-calculated)
    func getFixedBand10(presetId: Int) -> [Float] {
        let sql = """
        SELECT gain
        FROM fixed_band_10
        WHERE preset_id = ?
        ORDER BY band_index
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int(statement, 1, Int32(presetId))

        var gains: [Float] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let gain = Float(sqlite3_column_double(statement, 0))
            gains.append(gain)
        }

        return gains
    }

    /// Get 31-band graphic EQ (instant - pre-calculated)
    func getGraphicEQ31(presetId: Int) -> [Float] {
        let sql = """
        SELECT gain
        FROM graphic_eq_31
        WHERE preset_id = ?
        ORDER BY band_index
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int(statement, 1, Int32(presetId))

        var gains: [Float] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let gain = Float(sqlite3_column_double(statement, 0))
            gains.append(gain)
        }

        return gains
    }

    /// Get parametric bands (for advanced users)
    func getParametricBands(presetId: Int) -> [(filterType: String, frequency: Double, gain: Float, qFactor: Float)] {
        let sql = """
        SELECT filter_type, frequency, gain, q_factor
        FROM parametric_bands
        WHERE preset_id = ?
        ORDER BY band_index
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int(statement, 1, Int32(presetId))

        var bands: [(String, Double, Float, Float)] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let filterType = columnText(statement, 0)
            let frequency = sqlite3_column_double(statement, 1)
            let gain = Float(sqlite3_column_double(statement, 2))
            let qFactor = Float(sqlite3_column_double(statement, 3))

            bands.append((filterType, frequency, gain, qFactor))
        }

        return bands
    }

    // MARK: - Version & Updates

    /// Get database version (format: YYYY-MM-DD)
    func getVersion() -> String {
        let sql = "SELECT value FROM metadata WHERE key = 'version'"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return "Unknown"
        }
        defer { sqlite3_finalize(statement) }

        if sqlite3_step(statement) == SQLITE_ROW {
            return columnText(statement, 0)
        }
        return "Unknown"
    }

    /// Get build date
    func getBuildDate() -> Date? {
        let version = getVersion()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: version)
    }

    /// Check for updates from GitHub releases
    func checkForUpdates() async -> UpdateCheckResult {
        let currentVersion = getVersion()

        // GitHub API: get latest release
        guard let url = URL(string: "https://api.github.com/repos/jaakkopasanen/AutoEq/commits?per_page=1") else {
            return .checkFailed("Invalid URL")
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)

            if let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
               let firstCommit = json.first,
               let commitInfo = firstCommit["commit"] as? [String: Any],
               let committer = commitInfo["committer"] as? [String: Any],
               let dateString = committer["date"] as? String {
                // Parse ISO 8601 date
                let formatter = ISO8601DateFormatter()
                if let latestDate = formatter.date(from: dateString) {
                    let latestVersion = formatDate(latestDate)

                    if latestVersion > currentVersion {
                        return .updateAvailable(currentVersion: currentVersion, latestVersion: latestVersion)
                    } else {
                        return .upToDate(version: currentVersion)
                    }
                }
            }

            return .checkFailed("Could not parse response")
        } catch {
            return .checkFailed(error.localizedDescription)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    enum UpdateCheckResult {
        case upToDate(version: String)
        case updateAvailable(currentVersion: String, latestVersion: String)
        case checkFailed(String)

        var message: String {
            let l = LocalizationManager.shared
            switch self {
            case let .upToDate(version):
                return String(format: l.localized(.dbUpToDate), version)
            case let .updateAvailable(current, latest):
                return String(format: l.localized(.dbUpdateAvailable), current, latest)
            case let .checkFailed(error):
                return String(format: l.localized(.dbCheckFailed), error)
            }
        }

        var hasUpdate: Bool {
            if case .updateAvailable = self { return true }
            return false
        }
    }

    // MARK: - Statistics

    func getDatabaseStats() -> (headphones: Int, presets: Int, sizeMB: String) {
        var headphonesCount = 0
        var presetsCount = 0

        // Count headphones
        let sql1 = "SELECT COUNT(DISTINCT id) FROM headphones"
        var statement1: OpaquePointer?
        if sqlite3_prepare_v2(db, sql1, -1, &statement1, nil) == SQLITE_OK {
            if sqlite3_step(statement1) == SQLITE_ROW {
                headphonesCount = Int(sqlite3_column_int(statement1, 0))
            }
            sqlite3_finalize(statement1)
        }

        // Count presets
        let sql2 = "SELECT COUNT(*) FROM presets"
        var statement2: OpaquePointer?
        if sqlite3_prepare_v2(db, sql2, -1, &statement2, nil) == SQLITE_OK {
            if sqlite3_step(statement2) == SQLITE_ROW {
                presetsCount = Int(sqlite3_column_int(statement2, 0))
            }
            sqlite3_finalize(statement2)
        }

        // Get file size
        var sizeMB = "0.0"
        if let path = dbURL?.path,
           let attributes = try? FileManager.default.attributesOfItem(atPath: path),
           let size = attributes[.size] as? UInt64 {
            sizeMB = String(format: "%.1f", Double(size) / 1024.0 / 1024.0)
        }

        return (headphonesCount, presetsCount, sizeMB)
    }
}
