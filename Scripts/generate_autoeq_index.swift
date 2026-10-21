#!/usr/bin/env swift

import Foundation
import Darwin

struct OfflineIndexEntry: Codable {
    let brand: String
    let model: String
    let source: String // oratory1990, crinacle, etc.
    let type: String   // over-ear, in-ear, etc.
    var pathFixedBandEQ: String?
    var pathGraphicEQ: String?
    var pathParametric: String?
    var pathReadme: String?
}

func generateIndex() async throws {
    let arguments = Array(CommandLine.arguments.dropFirst())
    var options: [String: String] = [:]
    var offset = 0
    while offset < arguments.count {
        let flag = arguments[offset]
        guard ["--input", "--output"].contains(flag), options[flag] == nil, offset + 1 < arguments.count,
              !arguments[offset + 1].isEmpty, !arguments[offset + 1].hasPrefix("--") else {
            throw NSError(domain: "Invalid or missing argument: \(flag)", code: 1)
        }
        options[flag] = arguments[offset + 1]
        offset += 2
    }
    let data: Data
    if let input = options["--input"] {
        data = try Data(contentsOf: URL(fileURLWithPath: input))
    } else {
        let url = URL(string: "https://raw.githubusercontent.com/jaakkopasanen/AutoEq/master/results/INDEX.md")!
        let (responseData, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "HTTP error", code: 1)
        }
        data = responseData
    }
    guard let text = String(data: data, encoding: .utf8), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw NSError(domain: "Invalid or empty UTF-8 index", code: 1)
    }
    print("✅ Завантажено \(text.count) символів")
    
    var map: [String: OfflineIndexEntry] = [:]
    
    // Match markdown links: [text](./path)
    let linkPattern = #"\((\./[^\n]+?)\)(?:\s|$)"#
    guard let regex = try? NSRegularExpression(pattern: linkPattern, options: []) else {
        throw NSError(domain: "Regex", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create regex"])
    }
    
    let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
    for match in regex.matches(in: text, options: [], range: nsRange) {
        guard match.numberOfRanges >= 2,
              let range = Range(match.range(at: 1), in: text) else { continue }
        
        let rel = String(text[range])
        let relPath = String(rel.dropFirst(2)) // drop "./"
        guard let decodedRelPath = relPath.removingPercentEncoding,
              !decodedRelPath.contains("\0"), !decodedRelPath.contains("\\") else {
            throw NSError(domain: "Invalid index path", code: 1)
        }
        let comps = decodedRelPath.split(separator: "/").map(String.init)
        guard comps.count == 3, !comps.contains(".."), !comps.contains("."),
              !decodedRelPath.hasPrefix("/"), !decodedRelPath.contains("//"),
              ["in-ear", "over-ear", "earbud"].contains(where: { comps[1].lowercased().contains($0) }) else {
            throw NSError(domain: "Unexpected index path", code: 1)
        }
        
        let lastSeg = comps.last!
        var guessedBrand = ""
        var guessedModel = lastSeg
        
        // Визначаємо source та type з шляху
        let source = comps.count >= 1 ? comps[0] : "unknown"
        let type = comps.count >= 2 ? comps[1] : "unknown"
        
        // Покращений парсинг бренду
        let words = lastSeg.split(separator: " ").map(String.init)
        if words.count >= 2 {
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
        guard !guessedBrand.isEmpty, !guessedModel.isEmpty else {
            throw NSError(domain: "Invalid headphone name", code: 1)
        }
        
        let key = decodedRelPath
        let basePath = "results/" + decodedRelPath
        
        var entry = OfflineIndexEntry(
            brand: guessedBrand,
            model: guessedModel,
            source: source,
            type: type,
            pathFixedBandEQ: nil,
            pathGraphicEQ: nil,
            pathParametric: nil,
            pathReadme: nil
        )
        
        // Генеруємо шляхи до файлів
        entry.pathReadme = basePath + "/README.md"
        entry.pathFixedBandEQ = basePath + "/" + lastSeg + " FixedBandEQ.txt"
        entry.pathGraphicEQ = basePath + "/" + lastSeg + " GraphicEQ.txt"
        entry.pathParametric = basePath + "/" + lastSeg + " ParametricEQ.txt"
        
        map[key] = entry
    }
    
    let entries = Array(map.values).sorted { ($0.brand + $0.model) < ($1.brand + $1.model) }
    guard !entries.isEmpty else { throw NSError(domain: "No usable index entries", code: 1) }
    print("✅ Знайдено \(entries.count) записів")
    
    // Статистика по sources
    let sourceStats = Dictionary(grouping: entries, by: { $0.source })
        .mapValues { $0.count }
        .sorted { $0.value > $1.value }
    print("\n📊 По sources:")
    for (source, count) in sourceStats.prefix(5) {
        print("  - \(source): \(count) моделей")
    }
    
    // Зберегти як JSON
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let jsonData = try encoder.encode(entries)
    
    let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let scriptsDir = cwd.appendingPathComponent("Scripts")
    let dir = FileManager.default.fileExists(atPath: scriptsDir.path) ? scriptsDir : cwd
    let outputURL = options["--output"].map { URL(fileURLWithPath: $0) } ?? dir.appendingPathComponent("AutoEqIndex.json")
    var outputInfo = stat()
    if Darwin.lstat(outputURL.path, &outputInfo) == 0 {
        guard outputInfo.st_mode & S_IFMT == S_IFREG else { throw NSError(domain: "Output must be a regular file", code: 1) }
    } else if errno != ENOENT {
        throw NSError(domain: "Cannot inspect index output", code: 1)
    }
    let outputPath = outputURL.path
    try jsonData.write(to: outputURL, options: .atomic)
    
    print("✅ Індекс збережено в: \(outputPath)")
    print("📊 Розмір файлу: \(jsonData.count / 1024) KB")
    
    // Показати перші 3 записи
    print("\n📝 Перші 3 записи:")
    for entry in entries.prefix(3) {
        print("  - \(entry.brand) \(entry.model)")
    }
}

// Запустити генерацію
Task {
    do {
        try await generateIndex()
        exit(0)
    } catch {
        print("❌ Помилка: \(error.localizedDescription)")
        exit(1)
    }
}

// Тримати програму запущеною
RunLoop.main.run()
