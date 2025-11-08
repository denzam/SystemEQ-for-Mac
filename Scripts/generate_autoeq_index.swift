#!/usr/bin/env swift

import Foundation

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
    print("📥 Завантаження INDEX.md з GitHub...")
    
    let url = URL(string: "https://raw.githubusercontent.com/jaakkopasanen/AutoEq/master/results/INDEX.md")!
    let (data, response) = try await URLSession.shared.data(from: url)
    
    guard let httpResponse = response as? HTTPURLResponse,
          (200...299).contains(httpResponse.statusCode) else {
        throw NSError(domain: "HTTP", code: -1, userInfo: [NSLocalizedDescriptionKey: "HTTP error"])
    }
    
    let text = String(data: data, encoding: .utf8) ?? ""
    print("✅ Завантажено \(text.count) символів")
    
    var map: [String: OfflineIndexEntry] = [:]
    
    // Match markdown links: [text](./path)
    let linkPattern = #"\((\./[^\n]+?)\)(?:\s|$)"#
    guard let regex = try? NSRegularExpression(pattern: linkPattern, options: []) else {
        throw NSError(domain: "Regex", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create regex"])
    }
    
    let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
    regex.enumerateMatches(in: text, options: [], range: nsRange) { match, _, _ in
        guard let match = match,
              match.numberOfRanges >= 2,
              let range = Range(match.range(at: 1), in: text) else { return }
        
        let rel = String(text[range])
        let relPath = String(rel.dropFirst(2)) // drop "./"
        let decodedRelPath = relPath.removingPercentEncoding ?? relPath
        let comps = decodedRelPath.split(separator: "/").map(String.init)
        
        guard comps.count >= 2 else { return }
        
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
    
    let outputPath = FileManager.default.currentDirectoryPath + "/AutoEqIndex.json"
    try jsonData.write(to: URL(fileURLWithPath: outputPath))
    
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
