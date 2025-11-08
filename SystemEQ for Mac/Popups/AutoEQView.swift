import SwiftUI
import Foundation

struct AutoEQView: View {
    enum BandMode: String, CaseIterable, Identifiable { case ten = "10", thirtyOne = "31"; var id: String { rawValue } }
    struct ParsedBand: Identifiable, Equatable { let id = UUID(); let freq: Double; let gain: Double }
    struct MappedBand: Identifiable { let id = UUID(); let center: Double; var gain: Double }
    enum DisplayMode: String, CaseIterable, Identifiable { case sliders = "Sliders", bars = "Bars", curve = "Curve"; var id: String { rawValue } }
    struct SearchCandidate: Identifiable, Hashable { let id = UUID(); let path: String; let name: String; let display: String; let isParametric: Bool }
    struct CandidateDTO: Codable { let path: String; let name: String; let display: String; let isParametric: Bool }
    struct CandidateCache: Codable { let ts: TimeInterval; let items: [CandidateDTO] }
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
    struct OfflineIndexCache: Codable { 
        let version: Int
        let entries: [OfflineIndexEntry]
        let lastUpdate: TimeInterval
    }
    private static let indexVersion = 5 // Increment when path logic changes
    private static let indexUpdateInterval: TimeInterval = 30 * 24 * 3600 // 30 днів (1 місяць)

    @State private var bassBoost: Double = 0
    @State private var rawText: String = ""
    
    // Bass Boost low-shelf фільтр: піднімає тільки низькі частоти
    // Частота зрізу: 200 Hz, slope: 12 dB/octave
    private func bassBoostForFrequency(_ freq: Double) -> Double {
        guard bassBoost > 0 else { return 0 }
        let cutoffFreq = 200.0  // Частота зрізу
        let slope = 12.0        // Крутизна схилу dB/octave
        
        if freq <= cutoffFreq {
            // Нижче частоти зрізу - повний boost
            return bassBoost
        } else {
            // Вище частоти зрізу - експоненційний спад
            let octaves = log2(freq / cutoffFreq)
            let attenuation = octaves * slope
            return max(0, bassBoost - attenuation)
        }
    }
    @State private var parsed: [ParsedBand] = []
    @State private var parsed10: [ParsedBand] = []
    @State private var parsed31: [ParsedBand] = []
    @State private var bandMode: BandMode = .ten
    @State private var displayMode: DisplayMode = .curve
    @State private var mapped: [MappedBand] = []
    @State private var searchText: String = ""
    @State private var isSearching: Bool = false
    @State private var candidates: [SearchCandidate] = []
    @State private var searchError: String? = nil
    @State private var offlineIndex: [OfflineIndexEntry] = []
    @State private var isBuildingIndex: Bool = false
    @State private var indexStatus: String? = nil
    @State private var preampDB: Double? = nil
    @State private var targetProfile: String = "JM-1 with Harman filters"
    private let targetProfileVariants: [String] = [
        "JM-1 with Harman filters",
        "JM1 with Harman filters",
        "JM-1 Harman",
        "JM1 Harman",
        "JM-1",
        "JM1"
    ]
    @State private var indexTruncated: Bool = false
    
    // AutoEQ Setup Dialog
    @State private var showAutoEQSetup: Bool = false
    @State private var isInstallingAutoEQ: Bool = false
    @State private var autoEQInstallProgress: Double = 0.0
    @State private var autoEQInstallStatus: String = ""
    @State private var autoEQInstallError: String? = nil
    
    // Optimization: Caching and request management
    @State private var readmeCache: [String: String] = [:]
    @State private var activeRequests: Set<String> = []
    @State private var searchDebounceTask: Task<Void, Never>? = nil
    
    // URLSession з кешуванням (computed property для struct)
    private var cachedSession: URLSession {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.urlCache = URLCache(
            memoryCapacity: 50 * 1024 * 1024,  // 50 MB в пам'яті
            diskCapacity: 100 * 1024 * 1024,   // 100 MB на диску
            directory: nil
        )
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config)
    }

    private let tenCenters: [Double] = [31.5, 63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    private let thirtyOneCenters: [Double] = [20, 25, 31.5, 40, 50, 63, 80, 100, 125, 160, 200, 250, 315, 400, 500, 630, 800, 1000, 1250, 1600, 2000, 2500, 3150, 4000, 5000, 6300, 8000, 10000, 12500, 16000, 20000]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("AutoEQ").font(.title)
                Spacer()
                Text("Type a model name to search")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    TextField("Search headphones model", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 360)
                        .disableAutocorrection(true)
                    if let e = searchError {
                        Text(e)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if isSearching { ProgressView().controlSize(.small) }
                if isBuildingIndex {
                    ProgressView().controlSize(.small)
                } else {
                    Button(action: { Task { await buildOrUpdateIndex() } }) {
                        Image(systemName: "arrow.clockwise").imageScale(.medium)
                    }
                }
                if let s = indexStatus {
                    Text(s)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .font(.caption)
                }
            }

            Picker("Band Mode", selection: $bandMode) {
                Text("10").tag(BandMode.ten)
                Text("31").tag(BandMode.thirtyOne)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 200)
            .onChange(of: bandMode) { newMode in
                // Перемикаємось між кешованими даними
                if newMode == .ten && !parsed10.isEmpty {
                    parsed = parsed10
                } else if newMode == .thirtyOne && !parsed31.isEmpty {
                    parsed = parsed31
                }
                // Оновлюємо mapped bands
                mapped = mappedBands()
            }

            if !normalizedQuery.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    if candidates.isEmpty && isSearching {
                        ProgressView()
                    } else if candidates.isEmpty {
                        EmptyView()
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(candidates) { c in
                                    HStack {
                                        Text(c.display).lineLimit(1)
                                        Spacer()
                                        Button("Import") { Task { await importCandidate(c) } }
                                    }
                                }
                            }
                        }
                        .frame(maxHeight: 220)
                    }
                }
            }

            if !parsed.isEmpty {
                Text("Mapped Preview")
                    .font(.headline)
                Text(showingBandLabel)
                    .foregroundStyle(.secondary)

                Picker("View", selection: $displayMode) {
                    Text("Sliders").tag(DisplayMode.sliders)
                    Text("Bars").tag(DisplayMode.bars)
                    Text("Curve").tag(DisplayMode.curve)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 300)

                if displayMode == .sliders {
                    slidersBody()
                } else if displayMode == .bars {
                    barsBody()
                } else {
                    curveBody()
                }
                if let p = preampDB {
                    Text(String(format: "Preamp: %+.1f dB", p))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            }

            VStack(alignment: .leading) {
                Text("Bass Boost")
                Slider(value: $bassBoost, in: 0...6, step: 0.5)
            }

            Spacer()
        }
        .task(id: normalizedQuery) { await searchDebounced() }
        .task(id: parsed) {
            self.mapped = mappedBands()
        }
        .task(id: bandMode.rawValue) {
            if !parsed10.isEmpty || !parsed31.isEmpty {
                if bandMode == .ten {
                    if !parsed10.isEmpty { parsed = parsed10 }
                } else {
                    if !parsed31.isEmpty { parsed = parsed31 }
                }
            }
            self.mapped = mappedBands()
        }
        .padding(16)
        .frame(minWidth: 800, minHeight: 600)
        .onAppear {
            // Load offline index from user or bundle
            if let result = loadOfflineIndexFromDisk() {
                offlineIndex = result.entries
                print("DEBUG: Loaded index from disk with \(result.entries.count) entries")
                
                // Показати статус індексу
                if let cache = try? JSONDecoder().decode(OfflineIndexCache.self, from: Data(contentsOf: indexDiskPath()!)) {
                    let ageStr = formatIndexAge(cache.lastUpdate)
                    indexStatus = "Index: \(result.entries.count) (оновлено \(ageStr))"
                }
                
                // Автоматичне оновлення якщо індекс застарів
                if result.needsUpdate {
                    print("DEBUG: Index is outdated, updating in background...")
                    indexStatus = "Оновлення індексу..."
                    Task { await buildOrUpdateIndex() }
                }
            } else if let bundled = loadOfflineIndexFromBundle() {
                offlineIndex = bundled
                print("DEBUG: Loaded index from bundle with \(bundled.count) entries")
                // Оновити індекс в фоні після завантаження з bundle
                Task { await buildOrUpdateIndex() }
            } else {
                print("DEBUG: No cached index found, will build new one")
                Task { await buildOrUpdateIndex() }
            }
            
            // Діалог встановлення AutoEQ вимкнено - працюємо через GitHub API
            // checkAutoEQSetup()
        }
        .sheet(isPresented: $showAutoEQSetup) {
            autoEQSetupDialog()
        }
    }

    // MARK: - Offline index helpers
    
    private func formatIndexAge(_ timestamp: TimeInterval) -> String {
        let age = Date().timeIntervalSince1970 - timestamp
        let days = Int(age / (24 * 3600))
        if days == 0 {
            return "сьогодні"
        } else if days == 1 {
            return "вчора"
        } else if days < 7 {
            return "\(days) дн. тому"
        } else if days < 30 {
            let weeks = days / 7
            return "\(weeks) тижн. тому"
        } else {
            let months = days / 30
            return "\(months) міс. тому"
        }
    }
    
    private func indexDiskPath() -> URL? {
        do {
            let dir = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let appDir = dir.appendingPathComponent("SystemEQ", isDirectory: true)
            try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
            return appDir.appendingPathComponent("AutoEQIndex.json")
        } catch { return nil }
    }

    private func loadOfflineIndexFromDisk() -> (entries: [OfflineIndexEntry], needsUpdate: Bool)? {
        guard let p = indexDiskPath(), let data = try? Data(contentsOf: p) else { return nil }
        // Try new versioned format first
        if let cache = try? JSONDecoder().decode(OfflineIndexCache.self, from: data) {
            guard cache.version == Self.indexVersion else { return nil }
            let age = Date().timeIntervalSince1970 - cache.lastUpdate
            let needsUpdate = age > Self.indexUpdateInterval
            return (cache.entries, needsUpdate)
        }
        // Old format - ignore it
        return nil
    }

    private func saveOfflineIndexToDisk(_ items: [OfflineIndexEntry]) {
        guard let p = indexDiskPath() else { return }
        let cache = OfflineIndexCache(version: Self.indexVersion, entries: items, lastUpdate: Date().timeIntervalSince1970)
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: p, options: .atomic)
    }

    private func loadOfflineIndexFromBundle() -> [OfflineIndexEntry]? {
        if let url = Bundle.main.url(forResource: "AutoEqIndex", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let items = try? JSONDecoder().decode([OfflineIndexEntry].self, from: data) {
            return items
        }
        return nil
    }

    private func offlineSearch(_ query: String) -> [SearchCandidate] {
        let q = sanitize(query)
        let t = tokens(q)
        guard !offlineIndex.isEmpty, !t.isEmpty else { return [] }
        func match(entry: OfflineIndexEntry) -> Bool {
            let combined = sanitize(entry.brand + " " + entry.model)
            return t.allSatisfy { combined.contains($0) }
        }
        let hits = offlineIndex.filter { match(entry: $0) }
        return hits.map { e in
            if let r = e.pathReadme {
                // Ensure path is decoded (in case old cache has encoded paths)
                let decoded = r.removingPercentEncoding ?? r
                let full = decoded.hasPrefix("results/") ? decoded : "results/" + decoded
                let parts = full.split(separator: "/").map(String.init)
                let src = parts.count > 1 ? parts[1] : ""
                return SearchCandidate(path: full, name: "README.md", display: "\(src) / \(e.brand) / \(e.model) / README.md", isParametric: false)
            } else if let p = e.pathParametric {
                // Ensure path is decoded (in case old cache has encoded paths)
                let decoded = p.removingPercentEncoding ?? p
                let full = decoded.hasPrefix("results/") ? decoded : "results/" + decoded
                let parts = full.split(separator: "/").map(String.init)
                let src = parts.count > 1 ? parts[1] : ""
                return SearchCandidate(path: full, name: "ParametricEQ.txt", display: "\(src) / \(e.brand) / \(e.model) / ParametricEQ.txt", isParametric: true)
            } else {
                return SearchCandidate(path: "", name: "", display: "", isParametric: false)
            }
        }.filter { !$0.path.isEmpty }
    }

    private func clearIndexCache() {
        guard let p = indexDiskPath() else { return }
        try? FileManager.default.removeItem(at: p)
        print("DEBUG: Cleared index cache")
    }
    
    private func buildOrUpdateIndex() async {
        guard !isBuildingIndex else { return }
        isBuildingIndex = true
        indexStatus = "Building index…"
        defer { isBuildingIndex = false }
        // Clear old cache before building
        clearIndexCache()
        do {
            let url = URL(string: "https://raw.githubusercontent.com/jaakkopasanen/AutoEq/master/results/INDEX.md")!
            let (data, resp) = try await cachedSession.data(from: url)
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else { indexStatus = "HTTP error (INDEX.md)"; return }
            let text = String(data: data, encoding: .utf8) ?? ""
            var map: [String: OfflineIndexEntry] = [:]
            // Match markdown links: [text](./path) - capture everything between (./ and ) at end of line
            // Pattern matches: ( then ./ then any chars until ) followed by space, newline, or end
            let linkPattern = #"\((\./[^\n]+?)\)(?:\s|$)"#
            if let re = try? NSRegularExpression(pattern: linkPattern, options: []) {
                let nsr = NSRange(text.startIndex..<text.endIndex, in: text)
                re.enumerateMatches(in: text, options: [], range: nsr) { m,_,_ in
                    guard let m = m, m.numberOfRanges >= 2, let r1 = Range(m.range(at: 1), in: text) else { return }
                    let rel = String(text[r1]) // e.g. "./oratory1990/over-ear/HIFIMAN%20HE400se%20(non-stealth%20magnet)"
                    let relPath = String(rel.dropFirst(2)) // drop "./"
                    // Decode the entire path first, then split
                    let decodedRelPath = relPath.removingPercentEncoding ?? relPath
                    let comps = decodedRelPath.split(separator: "/").map(String.init)
                    guard comps.count >= 2 else { return }
                    let lastSeg = comps.last!
                    // Покращений парсинг: зберігаємо повну назву як бренд+модель
                    var guessedBrand = ""
                    var guessedModel = lastSeg
                    
                    // Спробувати виділити бренд (перше слово або перші два слова)
                    let words = lastSeg.split(separator: " ").map(String.init)
                    if words.count >= 2 {
                        // Перевірити чи перші 2 слова - це бренд (наприклад "Audio Technica")
                        let twoWords = words[0] + " " + words[1]
                        let knownTwoWordBrands = ["Audio Technica", "Beats by", "Sony WH", "Bose QuietComfort", "Bang Olufsen"]
                        if knownTwoWordBrands.contains(where: { twoWords.hasPrefix($0) }) && words.count > 2 {
                            guessedBrand = twoWords
                            guessedModel = words.dropFirst(2).joined(separator: " ")
                        } else {
                            guessedBrand = words[0]
                            guessedModel = words.dropFirst().joined(separator: " ")
                        }
                    }
                    
                    let key = decodedRelPath // unique per source/category/model
                    
                    // Визначаємо source та type з шляху
                    let source = comps.count >= 1 ? comps[0] : "unknown"
                    let type = comps.count >= 2 ? comps[1] : "unknown"
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
            let out = Array(map.values).filter { $0.pathReadme != nil || $0.pathParametric != nil }
            saveOfflineIndexToDisk(out)
            offlineIndex = out
            indexTruncated = false
            indexStatus = "Index: \(out.count) (оновлено сьогодні)"
            // Debug: print first few entries
            print("DEBUG: Index built with \(out.count) entries")
            for entry in out.prefix(3) {
                print("  - \(entry.brand) \(entry.model): \(entry.pathReadme ?? "no readme")")
            }
            if !normalizedQuery.isEmpty {
                let local = offlineSearch(normalizedQuery)
                candidates = rank(local, query: normalizedQuery)
                print("DEBUG: Search '\(normalizedQuery)' found \(candidates.count) results")
                for c in candidates.prefix(3) {
                    print("  - \(c.display): \(c.path)")
                }
            }
        } catch {
            indexStatus = friendlyNetworkError(error)
        }
    }

    // MARK: - Cache helpers (search results)
    private let cacheTTL: TimeInterval = 7 * 24 * 3600

    private func cacheRoot() -> URL? {
        do {
            let dir = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let appDir = dir.appendingPathComponent("SystemEQ", isDirectory: true)
            try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
            let searchDir = appDir.appendingPathComponent("AutoEQCache/search", isDirectory: true)
            try? FileManager.default.createDirectory(at: searchDir, withIntermediateDirectories: true)
            return searchDir
        } catch { return nil }
    }

    private func cachePathForQuery(_ q: String) -> URL? {
        guard let root = cacheRoot() else { return nil }
        let key = sanitize(q).replacingOccurrences(of: "/", with: "_")
        return root.appendingPathComponent("\(key).json")
    }

    private func loadCachedCandidates(for q: String) -> [SearchCandidate]? {
        guard let url = cachePathForQuery(q), let data = try? Data(contentsOf: url) else { return nil }
        guard let cache = try? JSONDecoder().decode(CandidateCache.self, from: data) else { return nil }
        if Date().timeIntervalSince1970 - cache.ts > cacheTTL { return nil }
        if cache.items.isEmpty { return nil }
        return cache.items.map { dto in
            SearchCandidate(path: dto.path, name: dto.name, display: dto.display, isParametric: dto.isParametric)
        }
    }

    private func saveCachedCandidates(for q: String, items: [SearchCandidate]) {
        guard !items.isEmpty else { return }
        guard let url = cachePathForQuery(q) else { return }
        let dto = items.map { CandidateDTO(path: $0.path, name: $0.name, display: $0.display, isParametric: $0.isParametric) }
        let payload = CandidateCache(ts: Date().timeIntervalSince1970, items: dto)
        if let data = try? JSONEncoder().encode(payload) {
            try? data.write(to: url, options: .atomic)
        }
    }

    @ViewBuilder
    private func slidersBody() -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(mapped.indices, id: \.self) { idx in
                    let bassBoostValue = bassBoostForFrequency(mapped[idx].center)
                    let totalGain = mapped[idx].gain + bassBoostValue
                    
                    HStack {
                        Text(String(format: "%.0f Hz", mapped[idx].center))
                            .frame(width: 80, alignment: .leading)
                        
                        // Слайдер показує фактичне значення з bass boost
                        Slider(value: .constant(totalGain), in: -12...12)
                            .disabled(true)
                            .opacity(bassBoost > 0 ? 0.7 : 1.0)
                            .overlay(
                                // Невидимий інтерактивний слайдер для зміни базового gain
                                Slider(value: $mapped[idx].gain, in: -12...12, step: 0.1)
                                    .opacity(0.01)
                            )
                            .frame(maxWidth: .infinity)
                        
                        Text(String(format: "%+.1f dB", totalGain))
                            .monospacedDigit()
                            .frame(width: 70, alignment: .trailing)
                            .foregroundColor(bassBoostValue > 0 ? .orange : .primary)
                    }
                }
            }
            .padding(8)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .frame(maxHeight: 320)
    }

    @ViewBuilder
    private func barsBody() -> some View {
        GeometryReader { geo in
            let maxH = max(200.0, geo.size.height - 40)
            ScrollView(.horizontal) {
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(mapped) { mb in
                        let bassBoostValue = bassBoostForFrequency(mb.center)
                        let totalGain = mb.gain + bassBoostValue
                        
                        VStack(spacing: 0) {
                            // Spacer займає весь простір зверху, текст завжди внизу
                            Spacer(minLength: 0)
                            
                            Rectangle()
                                .fill(.tint)
                                .frame(width: 12, height: CGFloat((min(max(totalGain, -12), 12) + 12) / 24) * maxH)
                                .animation(.easeInOut(duration: 0.2), value: mb.gain)
                                .animation(.easeInOut(duration: 0.2), value: bassBoost)
                            
                            Text(String(format: "%.0f", mb.center))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.top, 6)
                        }
                        .frame(height: maxH + 30) // Фіксована висота для кожного стовпчика
                    }
                }
                .padding(.vertical, 8)
                .frame(minWidth: geo.size.width)
            }
        }
        .frame(height: 260)
    }

    @ViewBuilder
    private func curveBody() -> some View {
        GeometryReader { geo in
            Canvas { context, size in
                let w = size.width
                let h = size.height
                let minDb: Double = -12
                let maxDb: Double = 12
                let minF = (bandMode == .ten) ? tenCenters.first! : thirtyOneCenters.first!
                let maxF = (bandMode == .ten) ? tenCenters.last! : thirtyOneCenters.last!
                let minL = log10(minF)
                let maxL = log10(maxF)

                var gridPath = Path()
                for db in stride(from: -12, through: 12, by: 3) {
                    let y = h * CGFloat((maxDb - Double(db)) / (maxDb - minDb))
                    gridPath.move(to: CGPoint(x: 0, y: y))
                    gridPath.addLine(to: CGPoint(x: w, y: y))
                }
                context.stroke(gridPath, with: .color(.secondary.opacity(0.2)), lineWidth: 1)

                var curve = Path()
                var isFirst = true
                for mb in mapped {
                    let f = max(min(mb.center, maxF), minF)
                    let l = log10(f)
                    let x = w * CGFloat((l - minL) / (maxL - minL))
                    let bassBoostValue = bassBoostForFrequency(mb.center)
                    let g = min(max(mb.gain + bassBoostValue, -12), 12)
                    let y = h * CGFloat((maxDb - g) / (maxDb - minDb))
                    if isFirst {
                        curve.move(to: CGPoint(x: x, y: y))
                        isFirst = false
                    } else {
                        curve.addLine(to: CGPoint(x: x, y: y))
                    }
                }
                context.stroke(curve, with: .color(.accentColor), lineWidth: 2)
            }
        }
        .frame(height: 260)
    }

    // MARK: - Search helpers

    private var normalizedQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var showingBandLabel: String {
        bandMode == .ten ? "Showing 10-band" : "Showing 31-band"
    }

    private func sanitize(_ s: String) -> String {
        let lower = s.lowercased()
        let allowed = lower.filter { $0.isLetter || $0.isNumber || $0 == " " || $0 == "/" }
        return allowed.replacingOccurrences(of: "  ", with: " ")
    }

    private func tokens(_ s: String) -> [String] {
        sanitize(s).split(separator: " ").map(String.init)
    }

    private func displayName(from path: String) -> String {
        let comps = path.split(separator: "/").map(String.init)
        let tail = comps.suffix(3)
        return tail.joined(separator: " / ")
    }

    private func rank(_ input: [SearchCandidate], query: String) -> [SearchCandidate] {
        let q = sanitize(query)
        let t = tokens(q)
        func score(_ c: SearchCandidate) -> Int {
            let s = sanitize(c.display + " " + c.path)
            var sc = 0
            for tok in t {
                if s.contains(tok) { sc += 2 }
                if s.hasPrefix(tok) { sc += 1 }
            }
            if c.isParametric { sc += 1 }
            return sc
        }
        return input.sorted { a, b in
            let sa = score(a), sb = score(b)
            return sa == sb ? a.display.count < b.display.count : sa > sb
        }
    }

    private func friendlyNetworkError(_ error: Error) -> String {
        if let e = error as? URLError {
            switch e.code {
            case .cannotFindHost:
                return "Cannot resolve GitHub host. Check Internet/DNS."
            case .notConnectedToInternet:
                return "No Internet connection."
            case .timedOut:
                return "Network timeout."
            case .cannotConnectToHost:
                return "Cannot connect to GitHub."
            default:
                return e.localizedDescription
            }
        }
        return error.localizedDescription
    }

    private func searchDebounced() async {
        // Скасувати попередній запит
        searchDebounceTask?.cancel()
        
        let q = normalizedQuery
        if q.count < 2 { 
            candidates = []
            searchError = nil
            return 
        }
        
        // Створити новий Task з затримкою
        searchDebounceTask = Task {
            // Debounce: чекаємо 300ms
            try? await Task.sleep(nanoseconds: 300_000_000)
            
            // Перевірити чи запит ще актуальний
            guard !Task.isCancelled, q == normalizedQuery else { return }
            
            await MainActor.run {
                isSearching = true
            }
            
            defer {
                Task { @MainActor in
                    isSearching = false
                }
            }
            
            // Використовуємо офлайн індекс та кеш
            var combined: [SearchCandidate] = offlineSearch(q)
            if combined.isEmpty, let cached = loadCachedCandidates(for: q) {
                combined = cached
            }
            
            guard !Task.isCancelled else { return }
            
            let ranked = rank(combined, query: q)
            
            await MainActor.run {
                candidates = ranked
            }
            
            // Зберегти результати пошуку в кеш
            if !ranked.isEmpty {
                saveCachedCandidates(for: q, items: ranked)
            }
        }
        
        await searchDebounceTask?.value
    }
    @MainActor
    private func importCandidate(_ c: SearchCandidate) async {
        isSearching = true
        defer { isSearching = false }
        searchError = nil
        print("DEBUG: Importing path: \(c.path)")

        // Request deduplication
        if activeRequests.contains(c.path) {
            print("DEBUG: Request already in progress for \(c.path), skipping")
            return
        }
        activeRequests.insert(c.path)
        defer { activeRequests.remove(c.path) }
        
        // Знаходимо entry в offline index для отримання шляхів до .txt файлів
        let entry = offlineIndex.first { entry in
            entry.pathReadme?.contains(c.path) == true ||
            entry.pathParametric?.contains(c.path) == true
        }
        
        // 🎯 TIER 0: Python AutoEQ Server (НАЙТОЧНІШЕ - як autoeq.app)
        // Середня точність: 0.4 дБ, ідеальне співпадіння з autoeq.app на більшості частот
        if let entry = entry {
            // Витягуємо папку моделі з pathReadme (містить повну назву з брендом)
            let measurementName: String
            if let readmePath = entry.pathReadme {
                // З "results/Filk/over-ear/HIFIMAN HE400se (non-stealth magnet)/README.md"
                // робимо "Filk/over-ear/HIFIMAN HE400se (non-stealth magnet)"
                let components = readmePath.split(separator: "/")
                if components.count >= 4 {
                    measurementName = "\(components[1])/\(components[2])/\(components[3])"
                } else {
                    measurementName = "\(entry.source)/\(entry.type)/\(entry.model)"
                }
            } else {
                measurementName = "\(entry.source)/\(entry.type)/\(entry.model)"
            }
            
            do {
                print("DEBUG: 🚀 TIER 0: Trying Python AutoEQ Server...")
                
                // Запитуємо ОБА режими одночасно для швидкого перемикання
                async let result10 = AutoEQServer.shared.calculateGraphicEQ(
                    measurementName: measurementName,
                    targetName: "JM-1 with Harman filters",
                    bandCount: 10
                )
                async let result31 = AutoEQServer.shared.calculateGraphicEQ(
                    measurementName: measurementName,
                    targetName: "JM-1 with Harman filters",
                    bandCount: 31
                )
                
                let bands10 = try await result10
                let bands31 = try await result31
                
                print("DEBUG: ✅ TIER 0: Python Server SUCCESS - 10-band: \(bands10.bands.count), 31-band: \(bands31.bands.count)")
                
                // Зберігаємо обидва набори
                self.parsed10 = bands10.bands.map { ParsedBand(freq: $0.freq, gain: $0.gain) }
                self.parsed31 = bands31.bands.map { ParsedBand(freq: $0.freq, gain: $0.gain) }
                
                // Використовуємо поточний режим
                self.parsed = (bandMode == .ten) ? self.parsed10 : self.parsed31
                self.preampDB = (bandMode == .ten) ? bands10.preamp : bands31.preamp
                self.rawText = "Imported via Python AutoEQ Server (JM-1)"
                
                let currentResult = (bandMode == .ten) ? bands10 : bands31
                print("DEBUG: Preamp: \(String(format: "%.1f dB", currentResult.preamp))")
                for (i, band) in currentResult.bands.prefix(3).enumerated() {
                    print("DEBUG:   Band \(i+1): \(String(format: "%.0f Hz = %+.1f dB", band.freq, band.gain))")
                }
                
                return
            } catch {
                print("DEBUG: ⚠️ TIER 0: Python Server failed: \(error.localizedDescription)")
                print("DEBUG: Falling back to TIER 1 (local .txt files)...")
            }
        }

        // 🎯 TIER 1: Локальні .txt файли (резервний fallback)
        // УВАГА: ці файли можуть бути застарілими та мати великі розбіжності з autoeq.app
        if let entry = entry {
            print("DEBUG: Found entry in offline index for \(c.path)")
            
            // Завантажуємо обидва режими з локальних файлів
            var loaded10: [ParsedBand]?
            var loaded31: [ParsedBand]?
            var loadedPreamp: Double?
            
            // FixedBandEQ.txt для 10-band
            if let fixedPath = entry.pathFixedBandEQ {
                if let result = parseFixedBandEQFile(fromPath: fixedPath) {
                    loaded10 = result.bands
                    loadedPreamp = result.preamp
                    print("DEBUG: ✅ TIER 1: Loaded FixedBandEQ.txt (10-band)")
                }
            }
            
            // GraphicEQ.txt для обох режимів
            if let graphicPath = entry.pathGraphicEQ {
                if let graphicBands = parseGraphicEQFile(fromPath: graphicPath) {
                    print("DEBUG: ✅ TIER 1: Loaded GraphicEQ.txt (\(graphicBands.count) points)")
                    
                    // Маппимо на 10-band якщо не маємо FixedBandEQ
                    if loaded10 == nil {
                        var mapped10: [ParsedBand] = []
                        for center in tenCenters {
                            if let closest = graphicBands.min(by: { abs($0.freq - center) < abs($1.freq - center) }) {
                                mapped10.append(ParsedBand(freq: center, gain: closest.gain))
                            }
                        }
                        loaded10 = mapped10
                    }
                    
                    // Маппимо на 31-band
                    var mapped31: [ParsedBand] = []
                    for center in thirtyOneCenters {
                        if let closest = graphicBands.min(by: { abs($0.freq - center) < abs($1.freq - center) }) {
                            mapped31.append(ParsedBand(freq: center, gain: closest.gain))
                        }
                    }
                    loaded31 = mapped31
                }
            }
            
            // Якщо щось завантажили - зберігаємо
            if let bands10 = loaded10, let bands31 = loaded31 {
                self.parsed10 = bands10
                self.parsed31 = bands31
                self.parsed = (bandMode == .ten) ? bands10 : bands31
                self.preampDB = loadedPreamp
                self.rawText = "Imported from local .txt files"
                print("DEBUG: ✅ TIER 1: Both modes loaded successfully")
                return
            } else if let bands10 = loaded10 {
                self.parsed10 = bands10
                self.parsed = bands10
                self.preampDB = loadedPreamp
                self.rawText = "Imported from local FixedBandEQ.txt"
                print("DEBUG: ⚠️ TIER 1: Only 10-band loaded")
                return
            }
        }

        // 🎯 TIER 2: Cache hit (попередньо завантажений README)
        if let cached = readmeCache[c.path] {
            print("DEBUG: ✅ TIER 2: Using cached README for \(c.path)")
            await processReadmeText(cached, path: c.path)
            return
        }

        // 🎯 TIER 3: Завантаження з GitHub (fallback)
        print("DEBUG: ⚠️ TIER 3: Falling back to GitHub README fetch")
        
        // Build URL to raw README/ParametricEQ
        let decoded = c.path.removingPercentEncoding ?? c.path
        let encoded = decoded.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? decoded
        let raw = "https://raw.githubusercontent.com/jaakkopasanen/AutoEq/master/" + encoded
        print("DEBUG: Decoded path: \(decoded)")
        print("DEBUG: Full URL: \(raw)")
        guard let url = URL(string: raw) else { searchError = "Bad URL"; return }

        do {
            var text: String = ""
            var ok = false
            var statusCode: Int? = nil

            // Try primary URL
            let (data, resp) = try await cachedSession.data(from: url)
            if let http = resp as? HTTPURLResponse { statusCode = http.statusCode }
            if let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                text = String(data: data, encoding: .utf8) ?? ""
                ok = true
            }

            // Fallback 1: if Parametric fetch failed, try README.md from same directory
            if !ok, c.isParametric {
                let dir = c.path.split(separator: "/").dropLast().joined(separator: "/")
                let readmePath = dir + "/README.md"
                let renc = readmePath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? readmePath
                let rraw = "https://raw.githubusercontent.com/jaakkopasanen/AutoEq/master/" + renc
                if let rurl = URL(string: rraw) {
                    let (d2, r2) = try await cachedSession.data(from: rurl)
                    if let h2 = r2 as? HTTPURLResponse, (200...299).contains(h2.statusCode) {
                        text = String(data: d2, encoding: .utf8) ?? ""
                        ok = true
                    }
                }
            }

            // Fallback 2: README.md from other sources with the same model folder
            if !ok {
                let parts = c.path.split(separator: "/").map(String.init)
                if parts.count >= 2 {
                    let modelFolder = parts[parts.count - 2]
                    var alts: [String] = offlineIndex.compactMap { $0.pathReadme }
                        .filter { path in
                            let ps = path.split(separator: "/").map(String.init)
                            return ps.count >= 2 && ps[ps.count - 2] == modelFolder
                        }
                    func srcRank(_ s: String) -> Int {
                        let ss = s.split(separator: "/").map(String.init)
                        guard ss.count > 1 else { return 99 }
                        let src = ss[1].lowercased()
                        if src.contains("oratory1990") { return 0 }
                        if src.contains("filk") { return 1 }
                        if src.contains("rtings") { return 2 }
                        return 9
                    }
                    alts.sort { srcRank($0) < srcRank($1) }
                    for ap in alts.prefix(2) {
                        let enc = ap.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ap
                        let url2s = "https://raw.githubusercontent.com/jaakkopasanen/AutoEq/master/" + enc
                        guard let url2 = URL(string: url2s) else { continue }
                        let (d3, r3) = try await cachedSession.data(from: url2)
                        if let h3 = r3 as? HTTPURLResponse, (200...299).contains(h3.statusCode) {
                            text = String(data: d3, encoding: .utf8) ?? ""
                            ok = true
                            break
                        }
                    }
                }
            }

            guard ok else {
                let urlInfo = raw.replacingOccurrences(of: "https://raw.githubusercontent.com/jaakkopasanen/AutoEq/master/", with: "")
                searchError = statusCode != nil ? "HTTP \(statusCode!): \(urlInfo)" : "Import failed"
                return
            }

            // Cache and process
            readmeCache[c.path] = text
            await processReadmeText(text, path: c.path)
        } catch {
            searchError = error.localizedDescription
        }
    }
    
    @MainActor
    private func processReadmeText(_ text: String, path: String) async {
        print("DEBUG: Processing README text from \(path)")
        
        // Parse both 10-band and 31-band versions
        let bands10 = parseFixedBandTable(text: text, bands: 10)
        let bands31 = parseFixedBandTable(text: text, bands: 31)
        
        print("DEBUG: Parsed \(bands10.count) bands (10-band mode)")
        print("DEBUG: Parsed \(bands31.count) bands (31-band mode)")
        
        // Try old format if table parsing failed
        var currentBands: [ParsedBand] = []
        if bands10.isEmpty && bands31.isEmpty {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.contains("GraphicEQ:") || trimmed.contains("FixedBandEQ:") {
                currentBands = parseGraphicEQ(text: trimmed)
                print("DEBUG: Parsed \(currentBands.count) bands (old format)")
            }
        }
        
        if bands10.isEmpty && bands31.isEmpty && currentBands.isEmpty {
            searchError = "No EQ data found in file"
            return
        }
        
        // Parse preamp value
        let preamp = parsePreamp(text: text)
        
        // Update state
        self.parsed10 = bands10.isEmpty ? currentBands : bands10
        self.parsed31 = bands31.isEmpty ? currentBands : bands31
        self.parsed = (bandMode == .ten) ? self.parsed10 : self.parsed31
        self.preampDB = preamp
        self.rawText = text
        
        print("DEBUG: Import successful - 10-band: \(self.parsed10.count), 31-band: \(self.parsed31.count), preamp: \(preamp.map { String(format: "%.1f dB", $0) } ?? "none")")
    }

    // MARK: - Mapping
    private func mappedBands() -> [MappedBand] {
        let centers = (bandMode == .ten) ? tenCenters : thirtyOneCenters
        var buckets: [[Double]] = Array(repeating: [], count: centers.count)
        
        print("DEBUG: Mapping \(parsed.count) parsed bands to \(centers.count) centers")
        
        for b in parsed {
            let idx = nearestCenterIndex(for: b.freq, centers: centers)
            buckets[idx].append(b.gain)
        }
        
        let result = centers.enumerated().map { (i, c) in
            let avg = buckets[i].isEmpty ? 0 : buckets[i].reduce(0,+) / Double(buckets[i].count)
            if !buckets[i].isEmpty {
                print("DEBUG:   \(c) Hz -> \(buckets[i].count) values: \(buckets[i]) -> avg: \(String(format: "%+.1f", avg)) dB")
            }
            return MappedBand(center: c, gain: avg)
        }
        
        return result
    }

    private func nearestCenterIndex(for freq: Double, centers: [Double]) -> Int {
        var best = 0
        var bestDist = Double.greatestFiniteMagnitude
        for (i, c) in centers.enumerated() {
            let d = abs(freq - c)
            if d < bestDist {
                bestDist = d
                best = i
            }
        }
        return best
    }

    private func parseAutoEQ(text: String) -> [ParsedBand] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Try modern table format first (Fixed Band EQs section)
        if trimmed.contains("### Fixed Band EQ") {
            let bands = parseFixedBandTable(text: trimmed, bands: bandMode == .ten ? 10 : 31)
            if !bands.isEmpty {
                return bands
            }
        }
        
        // Try old inline format (GraphicEQ: or FixedBandEQ:)
        if trimmed.contains("GraphicEQ:") || trimmed.contains("FixedBandEQ:") {
            return parseGraphicEQ(text: trimmed)
        }
        
        return []
    }

    private func parseGraphicEQ(text: String) -> [ParsedBand] {
        // Expect format like: "GraphicEQ: 31.5 -5; 63 -4.3; 125 -3; ..." or "FixedBandEQ: ..."
        let payload: Substring
        if let r = text.range(of: "GraphicEQ:") {
            payload = text[r.upperBound...]
        } else if let r = text.range(of: "FixedBandEQ:") {
            payload = text[r.upperBound...]
        } else {
            return []
        }
        
        let parts = payload.split(separator: ";")
        var result: [ParsedBand] = []
        for p in parts {
            let toks = p.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ")
            if toks.count >= 2, let f = Double(toks[0]), let g = Double(toks[1]) {
                result.append(ParsedBand(freq: f, gain: g))
            }
        }
        return result
    }

    private func parsePreamp(text: String) -> Double? {
        // First, try to find preamp in Fixed Band EQ section
        if let range = text.range(of: "### Fixed Band EQ", options: .caseInsensitive) {
            let startIndex = range.lowerBound
            let endIndex = text.index(startIndex, offsetBy: min(500, text.distance(from: startIndex, to: text.endIndex)))
            let fixedBandSection = String(text[startIndex..<endIndex])
            
            // Pattern: "apply preamp of **-X.X dB**" or "apply preamp of -X.X dB"
            let pattern1 = "apply preamp of \\*\\*(-?\\d+\\.?\\d*)\\s*dB\\*\\*"
            if let regex = try? NSRegularExpression(pattern: pattern1, options: .caseInsensitive) {
                let nsRange = NSRange(fixedBandSection.startIndex..., in: fixedBandSection)
                if let match = regex.firstMatch(in: fixedBandSection, range: nsRange),
                   let valueRange = Range(match.range(at: 1), in: fixedBandSection) {
                    if let value = Double(fixedBandSection[valueRange]) {
                        print("DEBUG: Parsed preamp from Fixed Band EQ section: \(value) dB")
                        return value
                    }
                }
            }
        }
        
        // Fallback: try to find preamp in the target profile section
        var searchText = text
        for variant in targetProfileVariants {
            if let range = text.range(of: variant, options: .caseInsensitive) {
                let startIndex = range.lowerBound
                let endIndex = text.index(startIndex, offsetBy: min(500, text.distance(from: startIndex, to: text.endIndex)))
                searchText = String(text[startIndex..<endIndex])
                break
            }
        }
        
        // Look for "Preamp: -X.X dB" pattern
        let pattern2 = "Preamp:\\s*(-?\\d+\\.?\\d*)\\s*dB"
        if let regex = try? NSRegularExpression(pattern: pattern2, options: .caseInsensitive) {
            let nsRange = NSRange(searchText.startIndex..., in: searchText)
            if let match = regex.firstMatch(in: searchText, range: nsRange),
               let valueRange = Range(match.range(at: 1), in: searchText) {
                if let value = Double(searchText[valueRange]) {
                    print("DEBUG: Parsed preamp from target profile section: \(value) dB")
                    return value
                }
            }
        }
        
        return nil
    }
    
    /// Парсить параметричний EQ в структуровані фільтри для EQProcessor
    private func parseParametricFilters(text: String) -> [EQProcessor.ParametricFilter] {
        var filters: [EQProcessor.ParametricFilter] = []
        let lines = text.components(separatedBy: .newlines)
        
        // Find the target profile section
        let targetSectionStart = lines.firstIndex { line in
            targetProfileVariants.contains { line.localizedCaseInsensitiveContains($0) }
        }
        
        // Extract lines after target profile mention
        let relevantLines: [String]
        if let startIdx = targetSectionStart {
            let endIdx = min(startIdx + 100, lines.count)
            relevantLines = Array(lines[startIdx..<endIdx])
        } else {
            relevantLines = lines
        }
        
        // Parse the parametric EQ table
        var started = false
        var lineCount = 0
        
        for line in relevantLines {
            lineCount += 1
            if lineCount > 100 { break }
            
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Зупиняємося на наступній секції
            if trimmed.hasPrefix("###") && started && !trimmed.contains("Fixed Band") {
                print("DEBUG: Hit next section, stopping")
                break
            }
            
            if trimmed.hasPrefix("|") {
                started = true
                if trimmed.contains("Frequency") || trimmed.contains("Type") || trimmed.contains("Fc") { continue }
                if trimmed.contains("---") { continue }
                
                let cols = trimmed.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                if cols.count >= 5 {
                    let typeStr = cols[1]
                    let fcStr = cols[2].replacingOccurrences(of: ",", with: "")
                    let qStr = cols[3].replacingOccurrences(of: ",", with: "")
                    let gainStr = cols[4].replacingOccurrences(of: "dB", with: "").replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
                    
                    if let fc = Double(fcStr), let q = Double(qStr), let gain = Double(gainStr) {
                        let type = parseFilterType(typeStr)
                        filters.append(EQProcessor.ParametricFilter(type: type, frequency: fc, q: q, gain: gain))
                    }
                }
            }
        }
        
        print("DEBUG: Parsed \(filters.count) parametric filters")
        return filters
    }
    
    private func parseFilterType(_ str: String) -> EQProcessor.FilterType {
        let lower = str.lowercased()
        if lower.contains("pk") || lower.contains("peaking") {
            return .peaking
        } else if lower.contains("lsh") || lower.contains("low shelf") || lower.contains("lowshelf") {
            return .lowShelf
        } else if lower.contains("hsh") || lower.contains("high shelf") || lower.contains("highshelf") {
            return .highShelf
        } else if lower.contains("lpf") || lower.contains("low pass") {
            return .lowPass
        } else if lower.contains("hpf") || lower.contains("high pass") {
            return .highPass
        }
        return .peaking
    }

    private func parseFixedBandTable(text: String, bands: Int) -> [ParsedBand] {
        // Шукаємо Fixed Band EQ секцію
        var searchText = text
        
        // Знаходимо "### Fixed Band EQ" секцію
        if let range = text.range(of: "### Fixed Band EQ", options: .caseInsensitive) {
            let startIndex = range.lowerBound
            let endIndex = text.index(startIndex, offsetBy: min(1500, text.distance(from: startIndex, to: text.endIndex)))
            searchText = String(text[startIndex..<endIndex])
            print("DEBUG: Found Fixed Band EQ section")
        } else {
            print("DEBUG: Fixed Band EQ section not found")
            return []
        }
        
        let lines = searchText.components(separatedBy: .newlines)
        var result: [ParsedBand] = []
        var started = false
        var lineCount = 0
        
        for line in lines {
            lineCount += 1
            if lineCount > 100 { break }
            
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Зупиняємося на наступній секції
            if trimmed.hasPrefix("###") && started && !trimmed.contains("Fixed Band") {
                print("DEBUG: Hit next section, stopping")
                break
            }
            
            if trimmed.hasPrefix("|") {
                // Пропускаємо заголовок та роздільник
                if trimmed.contains("Type") || trimmed.contains("Fc") || trimmed.contains("Gain") { continue }
                if trimmed.contains("---") { continue }
                
                let cols = trimmed.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                
                // DEBUG для першого рядка
                if result.isEmpty && cols.count > 0 {
                    print("DEBUG: First data row cols.count=\(cols.count)")
                    for (i, col) in cols.enumerated() {
                        print("DEBUG:   cols[\(i)] = '\(col)'")
                    }
                }
                
                // Таблиця: | # | Type | Fc (Hz) | Q | Gain (dB) |
                // Після split по "|": cols[0]="#", cols[1]="Type", cols[2]="Fc", cols[3]="Q", cols[4]="Gain"
                if cols.count >= 5 {
                    let fStr = cols[2].replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "Hz", with: "").trimmingCharacters(in: .whitespaces)
                    let gStr = cols[4].replacingOccurrences(of: "dB", with: "").replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
                    
                    if result.isEmpty {
                        print("DEBUG: Trying to parse fStr='\(fStr)' gStr='\(gStr)'")
                    }
                    
                    if let freq = Double(fStr), let gain = Double(gStr) {
                        result.append(ParsedBand(freq: freq, gain: gain))
                        started = true  // Встановлюємо started тільки після успішного парсингу
                        if result.count <= 3 {
                            print("DEBUG: Parsed band #\(result.count): \(String(format: "%.0f", freq)) Hz, \(String(format: "%+.1f", gain)) dB")
                        }
                    } else if result.isEmpty {
                        print("DEBUG: Failed to parse Double from fStr or gStr")
                    }
                }
            }
        }
        
        // Filter by band count if specified
        if bands == 10 && result.count > 10 {
            result = Array(result.prefix(10))
        } else if bands == 31 && result.count > 31 {
            result = Array(result.prefix(31))
        }
        
        print("DEBUG: Parsed \(result.count) bands from Fixed Band EQ table")
        
        return result
    }
    
    /// Застосовує корекцію JM-1 до Harman значень
    private func applyJM1Correction(harmanBands: [ParsedBand]) -> [ParsedBand] {
        return harmanBands.map { band in
            let jm1Target = EQProcessor.getJM1TargetGain(frequency: band.freq)
            let harmanTarget = EQProcessor.getHarmanTargetGain(frequency: band.freq)
            let targetDiff = jm1Target - harmanTarget
            let correctedGain = band.gain + targetDiff
            return ParsedBand(freq: band.freq, gain: correctedGain)
        }
    }
    
    /// Парсить FixedBandEQ.txt файл з локального AutoEq repo
    /// Формат: Filter 1: ON PK Fc 31 Hz Gain 6.4 dB Q 1.41
    private func parseFixedBandEQFile(fromPath path: String) -> (bands: [ParsedBand], preamp: Double?)? {
        // Визначаємо шлях до AutoEq repo відносно home directory
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let projectPath = homeDir + "/CascadeProjects/SystemEQ for Mac"
        let fullPath = projectPath + "/AutoEq/" + path
        
        guard let content = try? String(contentsOfFile: fullPath, encoding: .utf8) else {
            print("DEBUG: Failed to read FixedBandEQ file at \(fullPath)")
            return nil
        }
        
        var preamp: Double? = nil
        var bands: [ParsedBand] = []
        
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Парсимо Preamp: -7.1 dB
            if trimmed.hasPrefix("Preamp:") {
                let parts = trimmed.split(separator: " ")
                if parts.count >= 2,
                   let value = Double(parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "dB "))) {
                    preamp = value
                }
                continue
            }
            
            // Парсимо Filter 1: ON PK Fc 31 Hz Gain 6.4 dB Q 1.41
            if trimmed.hasPrefix("Filter") && trimmed.contains("Fc") && trimmed.contains("Gain") {
                let components = trimmed.split(separator: " ")
                var freq: Double? = nil
                var gain: Double? = nil
                
                for (i, comp) in components.enumerated() {
                    if comp == "Fc" && i + 1 < components.count {
                        freq = Double(components[i + 1])
                    }
                    if comp == "Gain" && i + 1 < components.count {
                        gain = Double(components[i + 1])
                    }
                }
                
                if let f = freq, let g = gain {
                    bands.append(ParsedBand(freq: f, gain: g))
                }
            }
        }
        
        print("DEBUG: Parsed FixedBandEQ.txt: \(bands.count) bands, preamp: \(preamp?.description ?? "nil")")
        return bands.isEmpty ? nil : (bands: bands, preamp: preamp)
    }
    
    /// Парсить GraphicEQ.txt файл з локального AutoEq repo
    /// Формат: GraphicEQ: 20 -0.2; 21 -0.2; 22 -0.2; ...
    private func parseGraphicEQFile(fromPath path: String) -> [ParsedBand]? {
        // Визначаємо шлях до AutoEq repo відносно home directory
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let projectPath = homeDir + "/CascadeProjects/SystemEQ for Mac"
        let fullPath = projectPath + "/AutoEq/" + path
        
        guard let content = try? String(contentsOfFile: fullPath, encoding: .utf8) else {
            print("DEBUG: Failed to read GraphicEQ file at \(fullPath)")
            return nil
        }
        
        var bands: [ParsedBand] = []
        
        // Знаходимо рядок що починається з "GraphicEQ:"
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("GraphicEQ:") {
                // Витягуємо все після "GraphicEQ:"
                let dataStr = trimmed.dropFirst("GraphicEQ:".count).trimmingCharacters(in: .whitespaces)
                
                // Розбиваємо по ";"
                let pairs = dataStr.split(separator: ";")
                for pair in pairs {
                    let components = pair.trimmingCharacters(in: .whitespaces).split(separator: " ")
                    if components.count == 2,
                       let freq = Double(components[0]),
                       let gain = Double(components[1]) {
                        bands.append(ParsedBand(freq: freq, gain: gain))
                    }
                }
                break
            }
        }
        
        print("DEBUG: Parsed GraphicEQ.txt: \(bands.count) frequency points")
        return bands.isEmpty ? nil : bands
    }
    
    private struct WebAppMeasurement: Codable { let frequency: [Double]; let raw: [Double] }
    private struct WebAppRequest: Codable {
        let measurement: WebAppMeasurement
        let target: String
        let fixed_band_eq: Bool
        let fixed_band_eq_config: String
        let fs: Int?
        let preamp: Double?
    }
    private struct WebAppFilter: Codable { let type: String?; let fc: Double?; let q: Double?; let gain: Double? }
    private struct WebAppFixedBand: Codable { let filters: [WebAppFilter]; let preamp: Double? }
    private struct WebAppResponse: Codable { let fixed_band_eq: WebAppFixedBand? }
    
    private func computeCSVURL(fromReadmePath path: String) -> URL? {
        let decoded = path.removingPercentEncoding ?? path
        let parts = decoded.split(separator: "/").map(String.init)
        guard parts.count >= 4 else { return nil }
        let model = parts[parts.count - 2]
        let dir = parts.dropLast().joined(separator: "/")
        let csvRelative = dir + "/" + model + ".csv"
        let enc = csvRelative.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? csvRelative
        let urlStr = "https://raw.githubusercontent.com/jaakkopasanen/AutoEq/master/" + enc
        return URL(string: urlStr)
    }
    
    private func parseCSVFrequencyRaw(_ data: Data) -> (freqs: [Double], raw: [Double])? {
        guard let s = String(data: data, encoding: .utf8) else { return nil }
        let lines = s.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard !lines.isEmpty else { return nil }
        let header = lines[0].split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        guard let fi = header.firstIndex(of: "frequency"), let ri = header.firstIndex(of: "raw") else { return nil }
        var f: [Double] = []
        var r: [Double] = []
        for line in lines.dropFirst() {
            let cols = line.split(separator: ",", omittingEmptySubsequences: false).map { String($0).trimmingCharacters(in: .whitespaces) }
            if fi < cols.count, ri < cols.count, let fv = Double(cols[fi]), let rv = Double(cols[ri]) {
                f.append(fv)
                r.append(rv)
            }
        }
        if f.isEmpty { return nil }
        let n = f.count
        let step = max(1, n / 600)
        if step > 1 {
            var fd: [Double] = []
            var rd: [Double] = []
            var i = 0
            while i < n {
                fd.append(f[i])
                rd.append(r[i])
                i += step
            }
            return (fd, rd)
        }
        return (f, r)
    }
    
    private func fetchJM1FromWebApp(csvURL: URL) async throws -> (bands: [ParsedBand], preamp: Double?)? {
        let csvDataTuple: (freqs: [Double], raw: [Double])?
        do {
            let (data, resp) = try await cachedSession.data(from: csvURL)
            if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) { return nil }
            csvDataTuple = parseCSVFrequencyRaw(data)
        } catch { throw error }
        guard let parsed = csvDataTuple else { return nil }
        let measurement = WebAppMeasurement(frequency: parsed.freqs, raw: parsed.raw)
        let req = WebAppRequest(measurement: measurement, target: self.targetProfile, fixed_band_eq: true, fixed_band_eq_config: "10_BAND_GRAPHIC_EQ", fs: 48000, preamp: nil)
        let enc = JSONEncoder()
        let body = try enc.encode(req)
        let urls = ["https://autoeq.app/equalize", "http://127.0.0.1:8000/equalize"].compactMap { URL(string: $0) }
        for u in urls {
            var rq = URLRequest(url: u)
            rq.httpMethod = "POST"
            rq.setValue("application/json", forHTTPHeaderField: "Content-Type")
            rq.httpBody = body
            do {
                let (data, resp) = try await cachedSession.data(for: rq)
                if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) { continue }
                let dec = JSONDecoder()
                let out = try dec.decode(WebAppResponse.self, from: data)
                if let fb = out.fixed_band_eq {
                    let bands = fb.filters.compactMap { f -> ParsedBand? in
                        guard let fc = f.fc, let g = f.gain else { return nil }
                        return ParsedBand(freq: fc, gain: g)
                    }
                    if !bands.isEmpty { return (bands, fb.preamp) }
                }
            } catch {
                continue
            }
        }
        return nil
    }
}

// MARK: - AutoEQ View Extension for Setup Dialog

extension AutoEQView {
    /// Перевіряє чи потрібно показати діалог встановлення AutoEQ
    func checkAutoEQSetup() {
        // Перевіряємо чи користувач вже відмовився
        if UserDefaults.standard.bool(forKey: "AutoEQSetupSkipped") {
            return
        }
        
        // Перевіряємо чи вже встановлено
        if UserDefaults.standard.bool(forKey: "AutoEQInstalled") {
            // Запускаємо сервер
            // AutoEQServer.shared.startServer() // TODO: Розкоментувати після налаштування
            return
        }
        
        // Показуємо діалог через 2 секунди після запуску
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.showAutoEQSetup = true
        }
    }
    
    /// Діалог встановлення AutoEQ
    @ViewBuilder
    private func autoEQSetupDialog() -> some View {
        VStack(spacing: 20) {
            // Іконка
            Image(systemName: isInstallingAutoEQ ? "arrow.down.circle" : "arrow.down.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            
            // Заголовок
            Text("Встановлення AutoEQ")
                .font(.title)
                .fontWeight(.bold)
            
            // Опис
            VStack(alignment: .leading, spacing: 10) {
                Text("Для найточніших результатів рекомендуємо встановити AutoEQ.")
                    .multilineTextAlignment(.center)
                
                Text("Це займе ~2 хвилини та вимагає Python 3.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal)
            
            // Progress bar
            if isInstallingAutoEQ {
                VStack(spacing: 10) {
                    ProgressView(value: autoEQInstallProgress)
                        .progressViewStyle(.linear)
                    
                    Text(autoEQInstallStatus)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
            }
            
            // Повідомлення про помилку
            if let error = autoEQInstallError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }
            
            // Кнопки
            HStack(spacing: 12) {
                if !isInstallingAutoEQ {
                    Button("Ніколи не питати") {
                        UserDefaults.standard.set(true, forKey: "AutoEQSetupSkipped")
                        showAutoEQSetup = false
                    }
                    .keyboardShortcut(.cancelAction)
                    
                    Button("Пізніше") {
                        showAutoEQSetup = false
                    }
                    
                    Button("Встановити зараз") {
                        Task {
                            await startAutoEQInstallation()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(30)
        .frame(width: 500)
    }
    
    /// Запускає встановлення AutoEQ
    private func startAutoEQInstallation() async {
        isInstallingAutoEQ = true
        autoEQInstallError = nil
        
        do {
            // Крок 1: Перевірка Python
            autoEQInstallStatus = "Перевірка Python..."
            autoEQInstallProgress = 0.1
            try await checkPython()
            
            // Крок 2: Створення віртуального середовища
            autoEQInstallStatus = "Створення віртуального середовища..."
            autoEQInstallProgress = 0.3
            try await createVirtualEnv()
            
            // Крок 3: Встановлення залежностей
            autoEQInstallStatus = "Встановлення бібліотек (це може зайняти кілька хвилин)..."
            autoEQInstallProgress = 0.5
            try await installDependencies()
            
            // Крок 4: Завершення
            autoEQInstallStatus = "Завершення..."
            autoEQInstallProgress = 1.0
            
            // Зберігаємо що встановлення завершено
            UserDefaults.standard.set(true, forKey: "AutoEQInstalled")
            
            // Запускаємо сервер
            // AutoEQServer.shared.startServer() // TODO: Розкоментувати після налаштування
            
            try await Task.sleep(nanoseconds: 1_000_000_000)
            
            showAutoEQSetup = false
            
        } catch {
            autoEQInstallError = "Помилка: \(error.localizedDescription)"
            isInstallingAutoEQ = false
            autoEQInstallProgress = 0.0
        }
    }
    
    private func checkPython() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["python3"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        try process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "AutoEQ", code: 1, userInfo: [NSLocalizedDescriptionKey: "Python 3 не знайдено. Будь ласка, встановіть Python 3."])
        }
    }
    
    private func createVirtualEnv() async throws {
        let projectPath = getProjectPath()
        let venvPath = projectPath.appending("/venv")
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-m", "venv", venvPath]
        process.currentDirectoryURL = URL(fileURLWithPath: projectPath)
        
        try process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "AutoEQ", code: 2, userInfo: [NSLocalizedDescriptionKey: "Помилка створення віртуального середовища"])
        }
    }
    
    private func installDependencies() async throws {
        let projectPath = getProjectPath()
        let pipPath = projectPath.appending("/venv/bin/pip")
        let requirementsPath = projectPath.appending("/requirements.txt")
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: pipPath)
        process.arguments = ["install", "-r", requirementsPath]
        process.currentDirectoryURL = URL(fileURLWithPath: projectPath)
        
        try process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "AutoEQ", code: 3, userInfo: [NSLocalizedDescriptionKey: "Помилка встановлення залежностей"])
        }
    }
    
    private func getProjectPath() -> String {
        let projectPath = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return projectPath.path
    }
}

// MARK: - EQ Processor

/// Процесор для обчислення еквалайзера з параметричного EQ та цільової кривої
struct EQProcessor {
    
    // MARK: - Filter Types
    
    enum FilterType: String {
        case peaking = "PK"
        case lowShelf = "LSC"
        case highShelf = "HSC"
        case lowPass = "LPF"
        case highPass = "HPF"
    }
    
    struct ParametricFilter {
        let type: FilterType
        let frequency: Double
        let q: Double
        let gain: Double
    }
    
    // MARK: - Generate Graphic EQ Values
    
    /// Застосовує JM-1 корекцію до Fixed Band EQ значень (Harman)
    static func applyJM1ToFixedBand(fixedBandEQ: [(freq: Double, gain: Double)], centerFrequencies: [Double]) -> (bands: [(freq: Double, gain: Double)], preamp: Double) {
        var bands: [(freq: Double, gain: Double)] = []
        var maxGain: Double = 0.0
        
        for centerFreq in centerFrequencies {
            // Знаходимо Harman gain з Fixed Band EQ таблиці
            let harmanGain = interpolateFixedBand(fixedBandEQ: fixedBandEQ, frequency: centerFreq)
            
            // Отримуємо target значення
            let harmanTarget = getHarmanTargetGain(frequency: centerFreq)
            let jm1Target = getJM1TargetGain(frequency: centerFreq)
            
            // Для JM-1: беремо Fixed Band значення і додаємо різницю targets
            let finalGain = harmanGain + (jm1Target - harmanTarget)
            
            bands.append((freq: centerFreq, gain: finalGain))
            
            if finalGain > maxGain {
                maxGain = finalGain
            }
        }
        
        let preamp = -(maxGain + 0.5)
        return (bands: bands, preamp: preamp)
    }
    
    /// Інтерполює значення з Fixed Band EQ таблиці
    private static func interpolateFixedBand(fixedBandEQ: [(freq: Double, gain: Double)], frequency: Double) -> Double {
        // Лінійна інтерполяція
        if frequency <= fixedBandEQ.first!.freq {
            return fixedBandEQ.first!.gain
        }
        if frequency >= fixedBandEQ.last!.freq {
            return fixedBandEQ.last!.gain
        }
        
        for i in 0..<(fixedBandEQ.count - 1) {
            let p1 = fixedBandEQ[i]
            let p2 = fixedBandEQ[i + 1]
            
            if frequency >= p1.freq && frequency <= p2.freq {
                let t = (frequency - p1.freq) / (p2.freq - p1.freq)
                return p1.gain + t * (p2.gain - p1.gain)
            }
        }
        
        return 0.0
    }
    
    /// Генерує значення для графічного еквалайзера (10 або 31 смуга) з параметричного EQ (Harman) та корекції JM-1
    static func generateGraphicEQ(filters: [ParametricFilter], centerFrequencies: [Double]) -> (bands: [(freq: Double, gain: Double)], preamp: Double) {
        var bands: [(freq: Double, gain: Double)] = []
        var maxGain: Double = 0.0
        
        for (index, centerFreq) in centerFrequencies.enumerated() {
            // DEBUG: тільки для першої частоти
            let isFirst = index == 0
            
            // ПРОСТІШЕ: параметричні фільтри вже дають Harman корекцію
            // Обчислюємо їх response на центральній частоті смуги
            let harmanCorrection = calculateFrequencyResponse(filters: filters, frequency: centerFreq)
            let harmanTarget = getHarmanTargetGain(frequency: centerFreq)
            let jm1Target = getJM1TargetGain(frequency: centerFreq)
            
            // DEBUG
            if isFirst {
                print("DEBUG CALC at \(centerFreq) Hz:")
                print("  harmanCorrection: \(harmanCorrection)")
                print("  harmanTarget: \(harmanTarget)")
                print("  jm1Target: \(jm1Target)")
                print("  difference: \(jm1Target - harmanTarget)")
            }
            
            // Для JM-1: беремо Harman корекцію і додаємо різницю targets
            let finalGain = harmanCorrection + (jm1Target - harmanTarget)
            
            bands.append((freq: centerFreq, gain: finalGain))
            
            if finalGain > maxGain {
                maxGain = finalGain
            }
        }
        
        // Додатковий smoothing для усунення різких переходів
        bands = applySmoothingToBands(bands: bands)
        
        // Перераховуємо maxGain після smoothing
        maxGain = bands.map { $0.gain }.max() ?? 0.0
        let preamp = -(maxGain + 0.5)
        
        return (bands: bands, preamp: preamp)
    }
    
    /// Застосовує легкий smoothing для усунення різких переходів між смугами
    private static func applySmoothingToBands(bands: [(freq: Double, gain: Double)]) -> [(freq: Double, gain: Double)] {
        guard bands.count > 2 else { return bands }
        
        var smoothed: [(freq: Double, gain: Double)] = []
        
        for i in 0..<bands.count {
            let current = bands[i]
            
            // Для першої та останньої смуги не застосовуємо smoothing
            if i == 0 || i == bands.count - 1 {
                smoothed.append(current)
                continue
            }
            
            // Легкий smoothing: 70% поточне значення + 15% попереднє + 15% наступне
            let prev = bands[i - 1]
            let next = bands[i + 1]
            
            let smoothedGain = current.gain * 0.70 + prev.gain * 0.15 + next.gain * 0.15
            
            smoothed.append((freq: current.freq, gain: smoothedGain))
        }
        
        return smoothed
    }
    
    /// Генерує значення для графічного еквалайзера з сирих вимірювань та JM-1 target
    static func generateGraphicEQFromRaw(rawMeasurements: [(freq: Double, raw: Double)], centerFrequencies: [Double]) -> (bands: [(freq: Double, gain: Double)], preamp: Double) {
        var bands: [(freq: Double, gain: Double)] = []
        var maxGain: Double = 0.0
        
        for centerFreq in centerFrequencies {
            // Інтерполюємо сире вимірювання
            let rawValue = interpolateRaw(measurements: rawMeasurements, frequency: centerFreq)
            
            // Отримуємо JM-1 target
            let jm1Target = getJM1TargetGain(frequency: centerFreq)
            
            // Формула AutoEQ: EQ = target - raw
            let finalGain = jm1Target - rawValue
            
            bands.append((freq: centerFreq, gain: finalGain))
            
            if finalGain > maxGain {
                maxGain = finalGain
            }
        }
        
        let preamp = -(maxGain + 0.5)
        
        return (bands: bands, preamp: preamp)
    }
    
    /// Інтерполює сире вимірювання для заданої частоти
    private static func interpolateRaw(measurements: [(freq: Double, raw: Double)], frequency: Double) -> Double {
        // Якщо частота за межами діапазону, повертаємо крайні значення
        if frequency <= measurements.first!.freq {
            return measurements.first!.raw
        }
        if frequency >= measurements.last!.freq {
            return measurements.last!.raw
        }
        
        // Лінійна інтерполяція
        for i in 0..<(measurements.count - 1) {
            let m1 = measurements[i]
            let m2 = measurements[i + 1]
            
            if frequency >= m1.freq && frequency <= m2.freq {
                let t = (frequency - m1.freq) / (m2.freq - m1.freq)
                return m1.raw + t * (m2.raw - m1.raw)
            }
        }
        
        return 0.0
    }
    
    // MARK: - Frequency Response Calculation
    
    /// Обчислює частотну характеристику для заданої частоти з урахуванням всіх фільтрів
    static func calculateFrequencyResponse(filters: [ParametricFilter], frequency: Double) -> Double {
        var totalGain: Double = 0.0
        
        for filter in filters {
            switch filter.type {
            case .peaking:
                totalGain += calculatePeakingEQ(f: frequency, fc: filter.frequency, q: filter.q, gain: filter.gain)
            case .lowShelf:
                totalGain += calculateLowShelf(f: frequency, fc: filter.frequency, q: filter.q, gain: filter.gain)
            case .highShelf:
                totalGain += calculateHighShelf(f: frequency, fc: filter.frequency, q: filter.q, gain: filter.gain)
            case .lowPass:
                totalGain += calculateLowPass(f: frequency, fc: filter.frequency, q: filter.q)
            case .highPass:
                totalGain += calculateHighPass(f: frequency, fc: filter.frequency, q: filter.q)
            }
        }
        
        return totalGain
    }
    
    /// Peaking EQ (bell filter) - ТОЧНА ФОРМУЛА З AutoEQ
    private static func calculatePeakingEQ(f: Double, fc: Double, q: Double, gain: Double) -> Double {
        let sampleRate = 48000.0
        let w0 = 2.0 * .pi * fc / sampleRate
        let w = 2.0 * .pi * f / sampleRate
        let A = pow(10.0, gain / 40.0)
        let alpha = sin(w0) / (2.0 * q)
        
        // Biquad coefficients (як в AutoEQ - БЕЗ нормалізації)
        let a0 = 1.0 + alpha / A
        var a1 = -2.0 * cos(w0)
        var a2 = 1.0 - alpha / A
        
        let b0 = 1.0 + alpha * A
        let b1 = -2.0 * cos(w0)
        let b2 = 1.0 - alpha * A
        
        // Інвертуємо знак a1, a2 (як в AutoEQ)
        a1 *= -1.0
        a2 *= -1.0
        
        // Frequency response з phi формулою (ТОЧНО як в AutoEQ)
        let phi = 4.0 * pow(sin(w / 2.0), 2.0)
        
        let numerator = pow(b0 + b1 + b2, 2.0) + 
                       (b0 * b2 * phi - (b1 * (b0 + b2) + 4.0 * b0 * b2)) * phi
        let denominator = pow(a0 + a1 + a2, 2.0) + 
                         (a0 * a2 * phi - (a1 * (a0 + a2) + 4.0 * a0 * a2)) * phi
        
        // DEBUG для першого виклику
        if f == 31.5 && fc == 105.0 {
            print("DEBUG PEAKING fc=\(fc), q=\(q), gain=\(gain):")
            print("  a0=\(a0), a1=\(a1), a2=\(a2)")
            print("  b0=\(b0), b1=\(b1), b2=\(b2)")
            print("  phi=\(phi)")
            print("  numerator=\(numerator)")
            print("  denominator=\(denominator)")
        }
        
        guard numerator > 0, denominator > 0 else { return 0.0 }
        
        let result = 10.0 * log10(numerator) - 10.0 * log10(denominator)
        
        // DEBUG
        if f == 31.5 && fc == 105.0 {
            print("  result=\(result) dB")
        }
        
        return result
    }
    
    /// Low Shelf filter - ТОЧНА ФОРМУЛА З AutoEQ
    private static func calculateLowShelf(f: Double, fc: Double, q: Double, gain: Double) -> Double {
        let sampleRate = 48000.0
        let w0 = 2.0 * .pi * fc / sampleRate
        let w = 2.0 * .pi * f / sampleRate
        let A = pow(10.0, gain / 40.0)
        let alpha = sin(w0) / (2.0 * q)
        
        // Biquad coefficients (БЕЗ нормалізації)
        let a0 = (A + 1) + (A - 1) * cos(w0) + 2 * sqrt(A) * alpha
        var a1 = -2 * ((A - 1) + (A + 1) * cos(w0))
        var a2 = (A + 1) + (A - 1) * cos(w0) - 2 * sqrt(A) * alpha
        
        let b0 = A * ((A + 1) - (A - 1) * cos(w0) + 2 * sqrt(A) * alpha)
        let b1 = 2 * A * ((A - 1) - (A + 1) * cos(w0))
        let b2 = A * ((A + 1) - (A - 1) * cos(w0) - 2 * sqrt(A) * alpha)
        
        // Інвертуємо знак
        a1 *= -1.0
        a2 *= -1.0
        
        // Frequency response з phi формулою
        let phi = 4.0 * pow(sin(w / 2.0), 2.0)
        
        let numerator = pow(b0 + b1 + b2, 2.0) + 
                       (b0 * b2 * phi - (b1 * (b0 + b2) + 4.0 * b0 * b2)) * phi
        let denominator = pow(a0 + a1 + a2, 2.0) + 
                         (a0 * a2 * phi - (a1 * (a0 + a2) + 4.0 * a0 * a2)) * phi
        
        // DEBUG
        if f == 31.5 && fc == 105.0 {
            print("DEBUG LOWSHELF fc=\(fc), q=\(q), gain=\(gain):")
            print("  A=\(A)")
            print("  a0=\(a0), a1=\(a1), a2=\(a2)")
            print("  b0=\(b0), b1=\(b1), b2=\(b2)")
            print("  b0+b1+b2=\(b0+b1+b2)")
            print("  a0+a1+a2=\(a0+a1+a2)")
            print("  phi=\(phi)")
            print("  numerator=\(numerator)")
            print("  denominator=\(denominator)")
        }
        
        guard numerator > 0, denominator > 0 else { return 0.0 }
        
        let result = 10.0 * log10(numerator) - 10.0 * log10(denominator)
        
        if f == 31.5 && fc == 105.0 {
            print("  result=\(result) dB")
        }
        
        return result
    }
    
    /// High Shelf filter - ТОЧНА ФОРМУЛА З AutoEQ
    private static func calculateHighShelf(f: Double, fc: Double, q: Double, gain: Double) -> Double {
        let sampleRate = 48000.0
        let w0 = 2.0 * .pi * fc / sampleRate
        let w = 2.0 * .pi * f / sampleRate
        let A = pow(10.0, gain / 40.0)
        let alpha = sin(w0) / (2.0 * q)
        
        // Biquad coefficients (БЕЗ нормалізації)
        let a0 = (A + 1) - (A - 1) * cos(w0) + 2 * sqrt(A) * alpha
        var a1 = 2 * ((A - 1) - (A + 1) * cos(w0))
        var a2 = (A + 1) - (A - 1) * cos(w0) - 2 * sqrt(A) * alpha
        
        let b0 = A * ((A + 1) + (A - 1) * cos(w0) + 2 * sqrt(A) * alpha)
        let b1 = -2 * A * ((A - 1) + (A + 1) * cos(w0))
        let b2 = A * ((A + 1) + (A - 1) * cos(w0) - 2 * sqrt(A) * alpha)
        
        // Інвертуємо знак
        a1 *= -1.0
        a2 *= -1.0
        
        // Frequency response з phi формулою
        let phi = 4.0 * pow(sin(w / 2.0), 2.0)
        
        let numerator = pow(b0 + b1 + b2, 2.0) + 
                       (b0 * b2 * phi - (b1 * (b0 + b2) + 4.0 * b0 * b2)) * phi
        let denominator = pow(a0 + a1 + a2, 2.0) + 
                         (a0 * a2 * phi - (a1 * (a0 + a2) + 4.0 * a0 * a2)) * phi
        
        guard numerator > 0, denominator > 0 else { return 0.0 }
        
        return 10.0 * log10(numerator) - 10.0 * log10(denominator)
    }
    
    /// Low Pass filter - ТОЧНА ФОРМУЛА З AutoEQ
    private static func calculateLowPass(f: Double, fc: Double, q: Double) -> Double {
        let sampleRate = 48000.0
        let w0 = 2.0 * .pi * fc / sampleRate
        let w = 2.0 * .pi * f / sampleRate
        let alpha = sin(w0) / (2.0 * q)
        
        // Biquad coefficients (БЕЗ нормалізації)
        let a0 = 1 + alpha
        var a1 = -2 * cos(w0)
        var a2 = 1 - alpha
        
        let b0 = (1 - cos(w0)) / 2
        let b1 = 1 - cos(w0)
        let b2 = (1 - cos(w0)) / 2
        
        // Інвертуємо знак
        a1 *= -1.0
        a2 *= -1.0
        
        // Frequency response з phi формулою
        let phi = 4.0 * pow(sin(w / 2.0), 2.0)
        
        let numerator = pow(b0 + b1 + b2, 2.0) + 
                       (b0 * b2 * phi - (b1 * (b0 + b2) + 4.0 * b0 * b2)) * phi
        let denominator = pow(a0 + a1 + a2, 2.0) + 
                         (a0 * a2 * phi - (a1 * (a0 + a2) + 4.0 * a0 * a2)) * phi
        
        guard numerator > 0, denominator > 0 else { return 0.0 }
        
        return 10.0 * log10(numerator) - 10.0 * log10(denominator)
    }
    
    /// High Pass filter - ТОЧНА ФОРМУЛА З AutoEQ
    private static func calculateHighPass(f: Double, fc: Double, q: Double) -> Double {
        let sampleRate = 48000.0
        let w0 = 2.0 * .pi * fc / sampleRate
        let w = 2.0 * .pi * f / sampleRate
        let alpha = sin(w0) / (2.0 * q)
        
        // Biquad coefficients (БЕЗ нормалізації)
        let a0 = 1 + alpha
        var a1 = -2 * cos(w0)
        var a2 = 1 - alpha
        
        let b0 = (1 + cos(w0)) / 2
        let b1 = -(1 + cos(w0))
        let b2 = (1 + cos(w0)) / 2
        
        // Інвертуємо знак
        a1 *= -1.0
        a2 *= -1.0
        
        // Frequency response з phi формулою
        let phi = 4.0 * pow(sin(w / 2.0), 2.0)
        
        let numerator = pow(b0 + b1 + b2, 2.0) + 
                       (b0 * b2 * phi - (b1 * (b0 + b2) + 4.0 * b0 * b2)) * phi
        let denominator = pow(a0 + a1 + a2, 2.0) + 
                         (a0 * a2 * phi - (a1 * (a0 + a2) + 4.0 * a0 * a2)) * phi
        
        guard numerator > 0, denominator > 0 else { return 0.0 }
        
        return 10.0 * log10(numerator) - 10.0 * log10(denominator)
    }
    
    // MARK: - Target Curves
    
    /// JM-1 target curve - ТОЧНІ ЗНАЧЕННЯ З AutoEQ
    static func getJM1TargetGain(frequency: Double) -> Double {
        // Точні значення з JM-1 with Harman filters.csv (кожна 5-та точка для оптимізації)
        let jm1Points: [(freq: Double, gain: Double)] = [
            (20.0, 4.538), (25.0, 4.563), (30.0, 4.570), (35.0, 4.563), (40.0, 4.536),
            (45.0, 4.483), (50.0, 4.399), (55.0, 4.273), (60.0, 4.121), (65.0, 3.927),
            (70.0, 3.698), (75.0, 3.437), (80.0, 3.152), (85.0, 2.850), (90.0, 2.539),
            (95.0, 2.225), (100.0, 1.917), (106.0, 1.559), (112.0, 1.224), (118.0, 0.916),
            (125.0, 0.595), (132.0, 0.314), (140.0, 0.041), (150.0, -0.235), (160.0, -0.445),
            (170.0, -0.602), (180.0, -0.718), (190.0, -0.798), (200.0, -0.855), (212.0, -0.898),
            (227.0, -0.917), (243.0, -0.912), (262.0, -0.883), (280.0, -0.839), (300.0, -0.781),
            (325.0, -0.689), (350.0, -0.598), (375.0, -0.499), (400.0, -0.392), (425.0, -0.277),
            (450.0, -0.157), (475.0, -0.034), (500.0, 0.090), (530.0, 0.236), (560.0, 0.379),
            (590.0, 0.512), (622.0, 0.640), (650.0, 0.742), (680.0, 0.839), (710.0, 0.926),
            (740.0, 1.004), (775.0, 1.085), (812.0, 1.164), (850.0, 1.242), (885.0, 1.315),
            (925.0, 1.407), (962.0, 1.506), (1000.0, 1.623), (1044.0, 1.780), (1090.0, 1.961),
            (1138.0, 2.164), (1180.0, 2.347), (1220.0, 2.525), (1265.0, 2.726), (1315.0, 2.951),
            (1360.0, 3.152), (1400.0, 3.330), (1450.0, 3.553), (1500.0, 3.776), (1550.0, 4.001),
            (1600.0, 4.230), (1650.0, 4.463), (1700.0, 4.702), (1750.0, 4.948), (1800.0, 5.203),
            (1850.0, 5.470), (1900.0, 5.750), (1950.0, 6.041), (2000.0, 6.342), (2060.0, 6.707),
            (2120.0, 7.067), (2180.0, 7.412), (2240.0, 7.733), (2300.0, 8.025), (2360.0, 8.284),
            (2430.0, 8.548), (2500.0, 8.774), (2580.0, 8.995), (2650.0, 9.166), (2720.0, 9.323),
            (2800.0, 9.488), (2900.0, 9.671), (3000.0, 9.815), (3110.0, 9.911), (3200.0, 9.930),
            (3300.0, 9.891), (3400.0, 9.792), (3500.0, 9.645), (3600.0, 9.460), (3700.0, 9.248),
            (3820.0, 8.970), (3950.0, 8.654), (4060.0, 8.384), (4180.0, 8.093), (4310.0, 7.789),
            (4440.0, 7.500), (4550.0, 7.271), (4680.0, 7.021), (4820.0, 6.776), (4940.0, 6.588),
            (5080.0, 6.393), (5220.0, 6.223), (5380.0, 6.057), (5520.0, 5.935), (5700.0, 5.806),
            (5900.0, 5.697), (6080.0, 5.628), (6300.0, 5.576), (6500.0, 5.556), (6700.0, 5.559),
            (6900.0, 5.577), (7100.0, 5.603), (7300.0, 5.628), (7500.0, 5.637), (7750.0, 5.599),
            (8000.0, 5.477), (8250.0, 5.254), (8500.0, 4.951), (8750.0, 4.598), (9000.0, 4.221),
            (9250.0, 3.836), (9500.0, 3.448), (9750.0, 3.061), (10000.0, 2.676), (10300.0, 2.220),
            (10600.0, 1.773), (10900.0, 1.341), (11200.0, 0.928), (11500.0, 0.539), (11800.0, 0.180),
            (12200.0, -0.251), (12500.0, -0.537), (12800.0, -0.790), (13200.0, -1.092), (13600.0, -1.361),
            (14000.0, -1.611), (14500.0, -1.911), (15000.0, -2.214), (15500.0, -2.530), (16000.0, -2.864),
            (16500.0, -3.218), (17000.0, -3.589), (17500.0, -3.971), (18000.0, -4.354), (18500.0, -4.732),
            (19000.0, -5.111), (19500.0, -5.771), (20000.0, -7.158)
        ]
        
        // Linear interpolation
        if frequency <= jm1Points.first!.freq {
            return jm1Points.first!.gain
        }
        if frequency >= jm1Points.last!.freq {
            return jm1Points.last!.gain
        }
        
        for i in 0..<(jm1Points.count - 1) {
            let p1 = jm1Points[i]
            let p2 = jm1Points[i + 1]
            
            if frequency >= p1.freq && frequency <= p2.freq {
                let t = (frequency - p1.freq) / (p2.freq - p1.freq)
                return p1.gain + t * (p2.gain - p1.gain)
            }
        }
        
        return 0.0
    }
    
    /// Harman target curve - ТОЧНІ ЗНАЧЕННЯ З AutoEQ
    static func getHarmanTargetGain(frequency: Double) -> Double {
        // Точні значення з Harman over-ear 2018.csv (кожна 10-та точка для оптимізації)
        let harmanPoints: [(freq: Double, gain: Double)] = [
            (20.0, 3.86), (30.0, 3.96), (40.0, 3.70), (50.0, 3.30), (60.0, 2.88),
            (70.0, 2.43), (80.0, 1.96), (90.0, 1.50), (100.0, 1.04), (110.0, 0.55),
            (120.0, 0.07), (130.0, -0.34), (140.0, -0.66), (150.0, -0.92), (160.0, -1.16),
            (170.0, -1.39), (180.0, -1.62), (190.0, -1.82), (200.0, -1.96), (210.0, -2.05),
            (220.0, -2.08), (230.0, -2.08), (240.0, -2.06), (250.0, -2.02), (260.0, -1.95),
            (270.0, -1.87), (280.0, -1.79), (290.0, -1.73), (300.0, -1.67), (310.0, -1.60),
            (320.0, -1.50), (330.0, -1.44), (340.0, -1.38), (350.0, -1.32), (360.0, -1.27),
            (370.0, -1.22), (380.0, -1.17), (390.0, -1.14), (400.0, -1.13), (410.0, -1.11),
            (420.0, -1.08), (430.0, -1.06), (440.0, -1.02), (450.0, -1.00), (460.0, -0.96),
            (470.0, -0.93), (480.0, -0.90), (490.0, -0.86), (500.0, -0.83), (520.0, -0.76),
            (540.0, -0.69), (560.0, -0.64), (580.0, -0.58), (600.0, -0.52), (620.0, -0.48),
            (640.0, -0.42), (660.0, -0.37), (680.0, -0.34), (700.0, -0.30), (720.0, -0.27),
            (740.0, -0.24), (760.0, -0.22), (780.0, -0.20), (800.0, -0.18), (820.0, -0.16),
            (840.0, -0.15), (860.0, -0.14), (880.0, -0.13), (900.0, -0.11), (920.0, -0.09),
            (940.0, -0.08), (960.0, -0.06), (980.0, -0.03), (1000.0, 0.00), (1020.0, 0.04),
            (1040.0, 0.08), (1060.0, 0.12), (1080.0, 0.18), (1100.0, 0.24), (1120.0, 0.31),
            (1140.0, 0.40), (1160.0, 0.48), (1180.0, 0.53), (1200.0, 0.63), (1220.0, 0.74),
            (1240.0, 0.79), (1260.0, 0.91), (1280.0, 0.97), (1300.0, 1.10), (1320.0, 1.17),
            (1340.0, 1.24), (1360.0, 1.38), (1380.0, 1.46), (1400.0, 1.60), (1420.0, 1.67),
            (1440.0, 1.82), (1460.0, 1.89), (1480.0, 2.03), (1500.0, 2.11), (1520.0, 2.20),
            (1540.0, 2.37), (1560.0, 2.46), (1580.0, 2.55), (1600.0, 2.73), (1620.0, 2.83),
            (1640.0, 2.93), (1660.0, 3.14), (1680.0, 3.24), (1700.0, 3.35), (1720.0, 3.46),
            (1740.0, 3.58), (1760.0, 3.69), (1780.0, 3.81), (1800.0, 4.04), (1820.0, 4.16),
            (1840.0, 4.29), (1860.0, 4.41), (1880.0, 4.53), (1900.0, 4.65), (1920.0, 4.78),
            (1940.0, 4.91), (1960.0, 5.04), (1980.0, 5.16), (2000.0, 5.29), (2040.0, 5.50),
            (2080.0, 5.71), (2120.0, 5.92), (2160.0, 6.13), (2200.0, 6.33), (2240.0, 6.54),
            (2280.0, 6.63), (2320.0, 6.83), (2360.0, 7.01), (2400.0, 7.16), (2440.0, 7.31),
            (2480.0, 7.46), (2520.0, 7.52), (2560.0, 7.65), (2600.0, 7.71), (2640.0, 7.77),
            (2680.0, 7.88), (2720.0, 7.94), (2760.0, 8.04), (2800.0, 8.09), (2840.0, 8.13),
            (2880.0, 8.20), (2920.0, 8.23), (2960.0, 8.30), (3000.0, 8.33), (3040.0, 8.37),
            (3080.0, 8.44), (3120.0, 8.47), (3160.0, 8.50), (3200.0, 8.51), (3240.0, 8.54),
            (3280.0, 8.56), (3320.0, 8.57), (3360.0, 8.58), (3400.0, 8.58), (3440.0, 8.57),
            (3480.0, 8.57), (3520.0, 8.57), (3560.0, 8.56), (3600.0, 8.53), (3640.0, 8.49),
            (3680.0, 8.46), (3720.0, 8.44), (3760.0, 8.40), (3800.0, 8.36), (3840.0, 8.32),
            (3880.0, 8.28), (3920.0, 8.25), (3960.0, 8.21), (4000.0, 8.16), (4040.0, 8.10),
            (4080.0, 8.04), (4120.0, 7.99), (4160.0, 7.93), (4200.0, 7.87), (4240.0, 7.81),
            (4280.0, 7.73), (4320.0, 7.65), (4360.0, 7.58), (4400.0, 7.50), (4440.0, 7.42),
            (4480.0, 7.34), (4520.0, 7.25), (4560.0, 7.17), (4600.0, 7.08), (4640.0, 6.99),
            (4680.0, 6.91), (4720.0, 6.81), (4760.0, 6.72), (4800.0, 6.63), (4840.0, 6.53),
            (4880.0, 6.44), (4920.0, 6.36), (4960.0, 6.28), (5000.0, 6.21), (5040.0, 6.13),
            (5080.0, 6.05), (5120.0, 5.97), (5160.0, 5.89), (5200.0, 5.81), (5240.0, 5.74),
            (5280.0, 5.66), (5320.0, 5.58), (5360.0, 5.52), (5400.0, 5.45), (5440.0, 5.39),
            (5480.0, 5.33), (5520.0, 5.27), (5560.0, 5.21), (5600.0, 5.14), (5640.0, 5.06),
            (5680.0, 4.97), (5720.0, 4.88), (5760.0, 4.79), (5800.0, 4.70), (5840.0, 4.62),
            (5880.0, 4.54), (5920.0, 4.47), (5960.0, 4.39), (6000.0, 4.31), (6040.0, 4.23),
            (6080.0, 4.15), (6120.0, 4.06), (6160.0, 3.96), (6200.0, 3.87), (6240.0, 3.78),
            (6280.0, 3.69), (6320.0, 3.59), (6360.0, 3.48), (6400.0, 3.37), (6440.0, 3.26),
            (6480.0, 3.15), (6520.0, 3.04), (6560.0, 2.94), (6600.0, 2.84), (6640.0, 2.74),
            (6680.0, 2.64), (6720.0, 2.54), (6760.0, 2.44), (6800.0, 2.33), (6840.0, 2.22),
            (6880.0, 2.10), (6920.0, 1.99), (6960.0, 1.88), (7000.0, 1.77), (7040.0, 1.64),
            (7080.0, 1.51), (7120.0, 1.38), (7160.0, 1.25), (7200.0, 1.12), (7240.0, 1.00),
            (7280.0, 0.85), (7320.0, 0.70), (7360.0, 0.55), (7400.0, 0.41), (7440.0, 0.26),
            (7480.0, 0.10), (7520.0, -0.08), (7560.0, -0.25), (7600.0, -0.43), (7640.0, -0.60),
            (7680.0, -0.77), (7720.0, -0.94), (7760.0, -1.11), (7800.0, -1.28), (7840.0, -1.45),
            (7880.0, -1.62), (7920.0, -1.80), (7960.0, -2.00), (8000.0, -2.19), (8040.0, -2.39),
            (8080.0, -2.59), (8120.0, -2.78), (8160.0, -3.00), (8200.0, -3.22), (8240.0, -3.43),
            (8280.0, -3.65), (8320.0, -3.87), (8360.0, -4.06), (8400.0, -4.26), (8440.0, -4.45),
            (8480.0, -4.64), (8520.0, -4.83), (8560.0, -5.02), (8600.0, -5.21), (8640.0, -5.40),
            (8680.0, -5.59), (8720.0, -5.78), (8760.0, -5.97), (8800.0, -6.15), (8840.0, -6.30),
            (8880.0, -6.46), (8920.0, -6.62), (8960.0, -6.78), (9000.0, -6.94), (9040.0, -7.09),
            (9080.0, -7.22), (9120.0, -7.36), (9160.0, -7.50), (9200.0, -7.63), (9240.0, -7.77),
            (9280.0, -7.91), (9320.0, -8.08), (9360.0, -8.26), (9400.0, -8.44), (9440.0, -8.63),
            (9480.0, -8.81), (9520.0, -8.99), (9560.0, -9.20), (9600.0, -9.49), (9640.0, -9.78),
            (9680.0, -10.07), (9720.0, -10.36), (9760.0, -10.65), (9800.0, -10.96), (9840.0, -11.44),
            (9880.0, -11.91), (9920.0, -12.39), (9960.0, -12.86), (10000.0, -13.34), (10200.0, -15.39),
            (10400.0, -16.88), (10600.0, -18.66), (10800.0, -19.73), (11000.0, -20.79), (11200.0, -21.86),
            (11400.0, -22.92), (12000.0, -22.92), (15000.0, -22.92), (20000.0, -22.92)
        ]
        
        // Linear interpolation
        if frequency <= harmanPoints.first!.freq {
            return harmanPoints.first!.gain
        }
        if frequency >= harmanPoints.last!.freq {
            return harmanPoints.last!.gain
        }
        
        for i in 0..<(harmanPoints.count - 1) {
            let p1 = harmanPoints[i]
            let p2 = harmanPoints[i + 1]
            
            if frequency >= p1.freq && frequency <= p2.freq {
                let t = (frequency - p1.freq) / (p2.freq - p1.freq)
                return p1.gain + t * (p2.gain - p1.gain)
            }
        }
        
        return 0.0
    }
}
