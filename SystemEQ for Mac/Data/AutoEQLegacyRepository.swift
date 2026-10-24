import Combine
import Foundation

final class AutoEQLegacyRepository: ObservableObject {
    typealias DataLoader = (URL) async throws -> (Data, URLResponse)

    enum IndexRefreshError: Error {
        case invalidURL
        case http
    }

    struct ImportCacheEntry {
        let input: AutoEQImportedPreset
        let text: String
        let name: String
        let source: String?
        let target: String?
        let path: String
    }

    struct CandidateText {
        enum Origin: Equatable { case local, memory, downloaded }
        let text: String
        let resolvedPath: String
        let origin: Origin
    }

    struct IndexSnapshot: Equatable {
        let entries: [OfflineIndexEntry]
        let lastUpdate: TimeInterval
        let needsUpdate: Bool
    }

    private var cachedSession: URLSession?
    private let sessionFactory: () -> URLSession
    private let dataLoader: DataLoader?
    private let localRoot: URL?
    private var readmeCache: [String: String] = [:]
    private var importCache: [String: ImportCacheEntry] = [:]

    var session: URLSession {
        if let cachedSession { return cachedSession }
        let session = sessionFactory()
        cachedSession = session
        return session
    }

    private let applicationSupportDirectory: URL?
    private let bundle: Bundle
    private let indexVersion = 5
    private let indexUpdateInterval: TimeInterval = 30 * 24 * 3600
    private let candidateCacheTTL: TimeInterval = 7 * 24 * 3600

    init(
        fileManager: FileManager = .default, bundle: Bundle = .main, session: URLSession? = nil,
        localRoot: URL? = nil, dataLoader: DataLoader? = nil
    ) {
        applicationSupportDirectory = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        self.bundle = bundle
        cachedSession = session
        sessionFactory = Self.makeSession
        self.localRoot = localRoot
        self.dataLoader = dataLoader
    }

    init(
        applicationSupportDirectory: URL?,
        bundle: Bundle = .main,
        session: URLSession? = nil,
        sessionFactory: @escaping () -> URLSession = AutoEQLegacyRepository.makeSession,
        localRoot: URL? = nil,
        dataLoader: DataLoader? = nil
    ) {
        self.applicationSupportDirectory = applicationSupportDirectory
        self.bundle = bundle
        cachedSession = session
        self.sessionFactory = sessionFactory
        self.localRoot = localRoot
        self.dataLoader = dataLoader
    }

    func cachedImport(for originalPath: String) -> ImportCacheEntry? {
        importCache[originalPath]
    }

    func cacheImport(_ entry: ImportCacheEntry, for originalPath: String) {
        importCache[originalPath] = entry
    }

    func resolveCandidateText(
        _ candidate: SearchCandidate,
        offlineIndex: [OfflineIndexEntry],
        checkValidity: () throws -> Void
    ) async throws -> CandidateText {
        let root = (localRoot ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("CascadeProjects/SystemEQ for Mac/AutoEq")).resolvingSymlinksInPath()
        if let entry = offlineIndex.first(where: {
            $0.pathReadme == candidate.path || $0.pathParametric == candidate.path
        }) {
            for path in [entry.pathParametric, entry.pathFixedBandEQ, entry.pathGraphicEQ, entry.pathReadme]
                .compactMap(\.self) {
                let file = root.appendingPathComponent(path).resolvingSymlinksInPath()
                guard file.path.hasPrefix(root.path + "/") else { throw AutoEQImportError.invalidSource }
                if FileManager.default.fileExists(atPath: file.path) {
                    let text = try String(contentsOf: file, encoding: .utf8)
                    try checkValidity()
                    return CandidateText(text: text, resolvedPath: path, origin: .local)
                }
            }
        }
        if let text = readmeCache[candidate.path] {
            return CandidateText(text: text, resolvedPath: candidate.path, origin: .memory)
        }
        let path = candidate.path.removingPercentEncoding ?? candidate.path
        guard !path.hasPrefix("/"), !path.split(separator: "/").contains(".."),
              let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: AppConstants.URLs.autoEQRawBase + encoded)
        else { throw AutoEQImportError.invalidSource }
        let (data, response) = try await download(from: url)
        try Task.checkCancellation()
        try checkValidity()
        guard let http = response as? HTTPURLResponse else { throw AutoEQImportError.invalidSource }
        if http.statusCode == 200, let text = String(data: data, encoding: .utf8) {
            return CandidateText(text: text, resolvedPath: candidate.path, origin: .downloaded)
        }
        guard http.statusCode == 404, candidate.isParametric else { throw AutoEQImportError.invalidSource }
        let resolvedPath = candidate.path.split(separator: "/").dropLast().joined(separator: "/") + "/README.md"
        guard let encodedFallback = resolvedPath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: AppConstants.URLs.autoEQRawBase + encodedFallback)
        else { throw AutoEQImportError.invalidSource }
        let (fallback, fallbackResponse) = try await download(from: url)
        try Task.checkCancellation()
        try checkValidity()
        guard (fallbackResponse as? HTTPURLResponse)?.statusCode == 200,
              let text = String(data: fallback, encoding: .utf8)
        else { throw AutoEQImportError.invalidSource }
        return CandidateText(text: text, resolvedPath: resolvedPath, origin: .downloaded)
    }

    func prepareImport(_ text: String, candidate: SearchCandidate, resolvedPath: String) throws -> ImportCacheEntry {
        let input = try AutoEQImportParser.parse(text)
        let components = resolvedPath.split(separator: "/")
        let source = (components.first == "results" ? components.dropFirst().first : components.first).map(String.init)
        let displayParts = candidate.display.components(separatedBy: " / ")
        let name = displayParts.count > 1 ? displayParts.dropFirst().joined(separator: " / ")
            : candidate.display.components(separatedBy: " · ").first ?? candidate.display
        return ImportCacheEntry(input: input, text: text, name: name, source: source, target: nil, path: resolvedPath)
    }

    func rememberDownloadedText(_ result: CandidateText) {
        if result.origin == .downloaded {
            readmeCache[result.resolvedPath] = result.text
        }
    }

    func refreshOfflineIndex(now: TimeInterval? = nil) async throws -> [OfflineIndexEntry] {
        guard let url = URL(string: AppConstants.URLs.autoEQIndex) else { throw IndexRefreshError.invalidURL }
        let (data, response) = try await download(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode)
        else { throw IndexRefreshError.http }
        try Task.checkCancellation()
        let entries = try Self.fallbackIndexEntries(from: data)
        try saveOfflineIndex(entries, now: now ?? Date().timeIntervalSince1970)
        return entries
    }

    private func download(from url: URL) async throws -> (Data, URLResponse) {
        if let dataLoader { return try await dataLoader(url) }
        return try await session.data(from: url)
    }

    // MARK: - Offline Index

    static func fallbackIndexEntries(from data: Data) throws -> [OfflineIndexEntry] {
        guard let text = String(data: data, encoding: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }
        var map: [String: OfflineIndexEntry] = [:]
        let linkPattern = #"\[[^\n]+?\]\((\./[^\n]+?)\)(?:\s|$)"#
        let re = try NSRegularExpression(pattern: linkPattern, options: [])
        do {
            let nsr = NSRange(text.startIndex..<text.endIndex, in: text)
            re.enumerateMatches(in: text, options: [], range: nsr) { m, _, _ in
                guard let m, m.numberOfRanges >= 2, let r1 = Range(m.range(at: 1), in: text) else { return }
                let rel =
                    String(text[r1])
                let relPath = String(rel.dropFirst(2))
                guard let decodedRelPath = relPath.removingPercentEncoding else { return }
                let comps = decodedRelPath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
                guard comps.count == 3,
                      comps.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains(where: \.isNewline) }),
                      ["in-ear", "over-ear", "earbud"].contains(where: {
                          comps[1] == $0 || comps[1].hasSuffix(" " + $0)
                      })
                else { return }
                guard let lastSeg = comps.last else { return }
                guard !["md", "txt", "json", "csv", "png", "jpg", "jpeg", "pdf"].contains(
                    (lastSeg as NSString).pathExtension.lowercased()
                ) else { return }
                var guessedBrand = ""
                var guessedModel = lastSeg

                let words = lastSeg.split(separator: " ").map(String.init)
                if words.count >= 2 {
                    let twoWords = words[0] + " " + words[1]
                    let knownTwoWordBrands = [
                        "Audio Technica",
                        "Beats by",
                        "Sony WH",
                        "Bose QuietComfort",
                        "Bang Olufsen"
                    ]
                    if knownTwoWordBrands.contains(where: { twoWords.hasPrefix($0) }), words.count > 2 {
                        guessedBrand = twoWords
                        guessedModel = words.dropFirst(2).joined(separator: " ")
                    } else {
                        guessedBrand = words[0]
                        guessedModel = words.dropFirst().joined(separator: " ")
                    }
                }

                let key = decodedRelPath

                let source = comps[0]
                let type = comps[1]
                let basePath = "results/" + decodedRelPath

                let entry = OfflineIndexEntry(
                    brand: guessedBrand,
                    model: guessedModel,
                    source: source,
                    type: type,
                    pathFixedBandEQ: basePath + "/" + lastSeg + " FixedBandEQ.txt",
                    pathGraphicEQ: basePath + "/" + lastSeg + " GraphicEQ.txt",
                    pathParametric: basePath + "/" + lastSeg + " ParametricEQ.txt",
                    pathReadme: basePath + "/README.md"
                )

                map[key] = entry
            }
        }
        let entries = Array(map.values).filter { $0.pathReadme != nil || $0.pathParametric != nil }
        guard !entries.isEmpty else { throw URLError(.cannotParseResponse) }
        return entries
    }

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

    func saveOfflineIndex(_ entries: [OfflineIndexEntry], now: TimeInterval = Date().timeIntervalSince1970) throws {
        guard let applicationSupportDirectory else { throw CocoaError(.fileNoSuchFile) }
        let cache = OfflineIndexCache(version: indexVersion, entries: entries, lastUpdate: now)
        let data = try JSONEncoder().encode(cache)
        let directory = applicationSupportDirectory.appendingPathComponent("SystemEQ", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent("AutoEQIndex.json"), options: .atomic)
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

    nonisolated private static func makeSession() -> URLSession {
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
