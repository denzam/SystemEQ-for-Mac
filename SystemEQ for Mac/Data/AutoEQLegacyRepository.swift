import Foundation

struct AutoEQLegacyRepository {
    struct IndexSnapshot: Equatable {
        let entries: [OfflineIndexEntry]
        let lastUpdate: TimeInterval
        let needsUpdate: Bool
    }

    let session: URLSession

    private let applicationSupportDirectory: URL?
    private let bundle: Bundle
    private let indexVersion = 5
    private let indexUpdateInterval: TimeInterval = 30 * 24 * 3600
    private let candidateCacheTTL: TimeInterval = 7 * 24 * 3600

    init(fileManager: FileManager = .default, bundle: Bundle = .main, session: URLSession? = nil) {
        applicationSupportDirectory = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        self.bundle = bundle
        self.session = session ?? Self.makeSession()
    }

    init(applicationSupportDirectory: URL?, bundle: Bundle = .main, session: URLSession? = nil) {
        self.applicationSupportDirectory = applicationSupportDirectory
        self.bundle = bundle
        self.session = session ?? Self.makeSession()
    }

    // MARK: - Offline Index

    func loadOfflineIndex(now: TimeInterval = Date().timeIntervalSince1970) -> IndexSnapshot? {
        guard let url = indexURL(), let data = try? Data(contentsOf: url),
              let cache = try? JSONDecoder().decode(OfflineIndexCache.self, from: data),
              cache.version == indexVersion
        else { return nil }

        return IndexSnapshot(
            entries: cache.entries,
            lastUpdate: cache.lastUpdate,
            needsUpdate: now - cache.lastUpdate > indexUpdateInterval
        )
    }

    func saveOfflineIndex(_ entries: [OfflineIndexEntry], now: TimeInterval = Date().timeIntervalSince1970) {
        guard let url = indexURL() else { return }
        let cache = OfflineIndexCache(version: indexVersion, entries: entries, lastUpdate: now)
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func loadBundledOfflineIndex() -> [OfflineIndexEntry]? {
        guard let url = bundle.url(forResource: "AutoEqIndex", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode([OfflineIndexEntry].self, from: data)
    }

    // MARK: - Search Cache

    func loadCandidates(for query: String, now: TimeInterval = Date().timeIntervalSince1970) -> [SearchCandidate]? {
        guard let url = candidateCacheURL(for: query),
              let data = try? Data(contentsOf: url),
              let cache = try? JSONDecoder().decode(CandidateCache.self, from: data),
              now - cache.ts <= candidateCacheTTL,
              !cache.items.isEmpty
        else { return nil }

        return cache.items.map {
            SearchCandidate(path: $0.path, name: $0.name, display: $0.display, isParametric: $0.isParametric)
        }
    }

    func saveCandidates(
        _ candidates: [SearchCandidate],
        for query: String,
        now: TimeInterval = Date().timeIntervalSince1970
    ) {
        guard !candidates.isEmpty, let url = candidateCacheURL(for: query) else { return }
        let items = candidates.map {
            CandidateDTO(path: $0.path, name: $0.name, display: $0.display, isParametric: $0.isParametric)
        }
        let cache = CandidateCache(ts: now, items: items)
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: url, options: .atomic)
    }

    // MARK: - Paths

    private func indexURL() -> URL? {
        appDirectory()?.appendingPathComponent("AutoEQIndex.json")
    }

    private func candidateCacheURL(for query: String) -> URL? {
        guard let appDirectory = appDirectory() else { return nil }
        let directory = appDirectory.appendingPathComponent("AutoEQCache/search", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let key = Self.sanitize(query).replacingOccurrences(of: "/", with: "_")
        return directory.appendingPathComponent("\(key).json")
    }

    private func appDirectory() -> URL? {
        guard let applicationSupportDirectory else { return nil }
        let directory = applicationSupportDirectory.appendingPathComponent("SystemEQ", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func sanitize(_ value: String) -> String {
        let allowed = value.lowercased().filter { $0.isLetter || $0.isNumber || $0 == " " || $0 == "/" }
        return allowed.replacingOccurrences(of: "  ", with: " ")
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.urlCache = URLCache(
            memoryCapacity: 50 * 1024 * 1024,
            diskCapacity: 100 * 1024 * 1024,
            directory: nil
        )
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        return URLSession(configuration: configuration)
    }
}
