import Foundation

struct ProjectMPresetPerformance {
    struct Context: Codable, Equatable {
        let hardware: String
        let renderer: String
        let quality: String
        let width: Int
        let height: Int
        let version: String

        var isValid: Bool {
            !hardware.isEmpty && !renderer.isEmpty && !quality.isEmpty && !version.isEmpty
                && width > 0 && height > 0
        }
    }

    struct Entry: Codable {
        let fingerprint: String
        let context: Context
        let recordedAt: Date
    }

    private struct Storage: Codable {
        let version: Int
        let entries: [String: [Entry]]
    }

    enum Failure: Error {
        case invalidStorage
        case invalidObservation
    }

    static let lifetime: TimeInterval = 7 * 24 * 60 * 60
    let storageURL: URL
    private var entries: [String: [Entry]] = [:]

    init(storageURL: URL) {
        self.storageURL = storageURL
    }

    mutating func load() throws {
        let data: Data
        do {
            data = try Data(contentsOf: storageURL)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return
        }
        let storage = try JSONDecoder().decode(Storage.self, from: data)
        guard storage.version == 1,
              storage.entries.count <= 20000,
              storage.entries.allSatisfy({ path, records in
                  !path.isEmpty && records.count <= 8 && records.allSatisfy {
                      !$0.fingerprint.isEmpty && $0.context.isValid
                          && $0.recordedAt.timeIntervalSinceReferenceDate.isFinite
                  }
              }) else { throw Failure.invalidStorage }
        entries = storage.entries
    }

    func isExcluded(path: String, fingerprint: String, context: Context, now: Date) -> Bool {
        guard context.isValid, now.timeIntervalSinceReferenceDate.isFinite else { return false }
        return entries[path, default: []].contains { entry in
            let age = now.timeIntervalSince(entry.recordedAt)
            return entry.fingerprint == fingerprint && entry.context == context
                && age >= 0 && age < Self.lifetime
        }
    }

    func nextExpiration(context: Context, now: Date) -> Date? {
        entries.values.flatMap(\.self).filter {
            $0.context == context && now.timeIntervalSince($0.recordedAt) >= 0
                && now.timeIntervalSince($0.recordedAt) < Self.lifetime
        }.map { $0.recordedAt.addingTimeInterval(Self.lifetime) }.min()
    }

    mutating func record(path: String, fingerprint: String, context: Context, now: Date) throws {
        guard !path.isEmpty, !fingerprint.isEmpty, context.isValid,
              now.timeIntervalSinceReferenceDate.isFinite else { throw Failure.invalidObservation }
        var currentStorage = self
        try currentStorage.load()
        var updated = currentStorage.entries.compactMapValues { records -> [Entry]? in
            let current = records.filter {
                let age = now.timeIntervalSince($0.recordedAt)
                return age >= 0 && age < Self.lifetime
            }
            return current.isEmpty ? nil : current
        }
        var records = updated[path, default: []].filter { $0.context != context }
        records.append(Entry(fingerprint: fingerprint, context: context, recordedAt: now))
        updated[path] = Array(records.suffix(8))
        guard updated.count <= 20000 else { throw Failure.invalidStorage }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(Storage(version: 1, entries: updated))
        try FileManager.default.createDirectory(
            at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try data.write(to: storageURL, options: .atomic)
        entries = updated
    }
}
