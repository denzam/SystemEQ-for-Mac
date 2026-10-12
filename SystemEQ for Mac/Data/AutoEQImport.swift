import Foundation

nonisolated enum AutoEQImportError: Error, Equatable {
    case invalidSource
    case invalidLine(Int)
    case invalidSampleRate
    case insufficientHeadroom
}

nonisolated struct AutoEQSourceFilter: Equatable, Sendable {
    let frequency: Double
    let gain: Double
    let q: Double
    let type: FilterType
    var enabled = true
}

nonisolated struct AutoEQCurvePoint: Equatable, Sendable {
    let frequency: Double
    let gain: Double
}

nonisolated struct AutoEQImportedPreset: Equatable, Sendable {
    enum Response: Equatable, Sendable {
        case parametric([AutoEQSourceFilter])
        case graphic([AutoEQCurvePoint])
    }

    let response: Response
    let preamp: Double?
    var legacyPreamp = false

    var displayBands: [ParsedBand] {
        switch response {
        case let .parametric(filters):
            filters.filter(\.enabled).map {
                ParsedBand(freq: $0.frequency, gain: $0.gain, q: $0.q, type: $0.type)
            }
        case let .graphic(points):
            points.map { ParsedBand(freq: $0.frequency, gain: $0.gain) }
        }
    }
}

nonisolated enum AutoEQImportParser {
    private static let number = #"[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?"#

    static func parse(_ text: String) throws -> AutoEQImportedPreset {
        guard !text.isEmpty, text.utf8.count <= 1_000_000 else { throw AutoEQImportError.invalidSource }
        let lines = text.components(separatedBy: .newlines)
        if lines.contains(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("|") }) {
            return try parseTable(lines)
        }
        var filters: [AutoEQSourceFilter] = []
        var points: [AutoEQCurvePoint]?
        var preamp: Double?
        var foundDirective = false
        for (index, original) in lines.enumerated() {
            let line = original.components(separatedBy: "#")[0].trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix(";") { continue }
            if let values = captures(#"^Preamp\s*:\s*("# + number + #")\s*(?:dB)?\s*$"#, line) {
                guard preamp == nil, let value = Double(values[0]), value.isFinite, abs(value) <= 40 else {
                    throw AutoEQImportError.invalidLine(index + 1)
                }
                preamp = value
                foundDirective = true
            } else if let values = captures(#"^Filter\s*(?:\d+)?\s*:\s*(ON|OFF)\s+(\w+)\s+(.+)$"#, line) {
                guard points == nil, filters.count < 256 else { throw AutoEQImportError.invalidLine(index + 1) }
                try filters.append(filter(
                    values[2],
                    kind: values[1],
                    enabled: values[0].uppercased() == "ON",
                    line: index + 1
                ))
                foundDirective = true
            } else if let values = captures(#"^(?:GraphicEQ|FixedBandEQ)\s*:\s*(.+)$"#, line) {
                guard points == nil, filters.isEmpty else { throw AutoEQImportError.invalidLine(index + 1) }
                points = try graphic(values[0], line: index + 1)
                foundDirective = true
            } else {
                throw AutoEQImportError.invalidLine(index + 1)
            }
        }
        guard foundDirective else { throw AutoEQImportError.invalidSource }
        return AutoEQImportedPreset(response: points.map { .graphic($0) } ?? .parametric(filters), preamp: preamp)
    }

    static func validated(
        _ filters: [AutoEQSourceFilter],
        preamp: Double?,
        legacy: Bool = false
    ) throws -> AutoEQImportedPreset {
        guard !filters.isEmpty, filters.count <= 256,
              preamp.map({ $0.isFinite && abs($0) <= 40 }) ?? true,
              filters.allSatisfy(validFilter) else { throw AutoEQImportError.invalidSource }
        return AutoEQImportedPreset(response: .parametric(filters), preamp: preamp, legacyPreamp: legacy)
    }

    static func kind(_ value: String) -> FilterType? {
        switch value.uppercased() {
        case "BELL",
             "PEAKING",
             "PEQ",
             "PK": .peak
        case "LOW_SHELF",
             "LOWSHELF",
             "LS",
             "LSC": .lowShelf
        case "HIGH_SHELF",
             "HIGHSHELF",
             "HS",
             "HSC": .highShelf
        case "HIGHPASS",
             "HP",
             "HPQ": .highPass
        case "LOWPASS",
             "LP",
             "LPQ": .lowPass
        case "NO",
             "NOTCH": .notch
        case "AP": .allPass
        case "BP": .bandPass
        default: nil
        }
    }

    private static func validFilter(_ filter: AutoEQSourceFilter) -> Bool {
        filter.frequency.isFinite && (20...20000).contains(filter.frequency)
            && filter.gain.isFinite && abs(filter.gain) <= 30
            && filter.q.isFinite && (0.1...20).contains(filter.q)
    }

    private static func filter(
        _ payload: String,
        kind token: String,
        enabled: Bool,
        line: Int
    ) throws -> AutoEQSourceFilter {
        guard let type = kind(token), let values = captures(
            #"^Fc\s+("# + number + #")\s*(?:Hz)?(?:\s+Gain\s+("# + number
                + #")\s*(?:dB)?)?(?:\s+(Q|BW(?:\s+Oct)?)\s+("# + number + #"))?\s*$"#, payload
        ), let frequency = Double(values[0]) else { throw AutoEQImportError.invalidLine(line) }
        let usesGain = type == .peak || type == .lowShelf || type == .highShelf
        guard !usesGain || !values[1].isEmpty else { throw AutoEQImportError.invalidLine(line) }
        let gain = values[1].isEmpty ? 0 : Double(values[1]) ?? .nan
        var q = type == .lowShelf || type == .highShelf || type == .highPass || type == .lowPass ? 0.707 : 1.4
        if !values[3].isEmpty {
            guard let value = Double(values[3]), value.isFinite,
                  value > 0 else { throw AutoEQImportError.invalidLine(line) }
            if values[2].uppercased().hasPrefix("BW") {
                let width = pow(2, value)
                q = sqrt(width) / (width - 1)
            } else {
                q = value
            }
        }
        let result = AutoEQSourceFilter(frequency: frequency, gain: gain, q: q, type: type, enabled: enabled)
        guard validFilter(result), usesGain || gain == 0 else { throw AutoEQImportError.invalidLine(line) }
        return result
    }

    private static func graphic(_ payload: String, line: Int) throws -> [AutoEQCurvePoint] {
        var parts = payload.split(separator: ";", omittingEmptySubsequences: false)
        if parts.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { parts.removeLast() }
        guard !parts.isEmpty, parts.count <= 4096 else { throw AutoEQImportError.invalidLine(line) }
        var result: [AutoEQCurvePoint] = []
        for part in parts {
            let tokens = part.split(whereSeparator: \.isWhitespace)
            guard tokens.count == 2, let frequency = Double(tokens[0]), let gain = Double(tokens[1]),
                  frequency.isFinite, (10...30000).contains(frequency), gain.isFinite, abs(gain) <= 40,
                  result.last.map({ $0.frequency < frequency }) ?? true
            else { throw AutoEQImportError.invalidLine(line) }
            result.append(AutoEQCurvePoint(frequency: frequency, gain: gain))
        }
        return result
    }

    private static func parseTable(_ lines: [String]) throws -> AutoEQImportedPreset {
        let heading = lines.firstIndex { $0.hasPrefix("#") && $0.localizedCaseInsensitiveContains("Parametric EQ") }
            ?? lines.firstIndex { $0.hasPrefix("#") && $0.localizedCaseInsensitiveContains("Fixed Band EQ") }
        guard let heading else { throw AutoEQImportError.invalidSource }
        var filters: [AutoEQSourceFilter] = []
        var preamp: Double?
        for index in (heading + 1)..<lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#") { break }
            let clean = line.replacingOccurrences(of: "*", with: "").replacingOccurrences(of: "`", with: "")
            if let values = captures(#".*preamp\s*(?:of|:)\s*("# + number + #")\s*dB.*"#, clean) {
                guard preamp == nil, let value = Double(values[0]), value.isFinite, abs(value) <= 40 else {
                    throw AutoEQImportError.invalidLine(index + 1)
                }
                preamp = value
            } else if clean.localizedCaseInsensitiveContains("preamp") {
                throw AutoEQImportError.invalidLine(index + 1)
            }
            guard line.hasPrefix("|") else { continue }
            var cells = line.split(separator: "|", omittingEmptySubsequences: false).dropFirst()
                .map { $0.trimmingCharacters(in: .whitespaces) }
            if cells.last?.isEmpty == true { cells.removeLast() }
            if cells.count == 5, cells[0] == "#", cells[1] == "Type",
               cells[2].hasPrefix("Fc"), cells[3] == "Q", cells[4].hasPrefix("Gain") {
                continue
            }
            if cells.count == 5, cells.allSatisfy({
                let separator = $0.replacingOccurrences(of: ":", with: "")
                return separator.count >= 3 && separator.allSatisfy { $0 == "-" }
            }) {
                continue
            }
            guard cells.count == 5, Int(cells[0]) != nil, let type = kind(cells[1]),
                  let frequency = Double(cells[2].replacingOccurrences(of: ",", with: "")),
                  let q = Double(cells[3]), let gain = Double(cells[4]), filters.count < 256 else {
                throw AutoEQImportError.invalidLine(index + 1)
            }
            let value = AutoEQSourceFilter(frequency: frequency, gain: gain, q: q, type: type)
            guard validFilter(value) else { throw AutoEQImportError.invalidLine(index + 1) }
            filters.append(value)
        }
        return try validated(filters, preamp: preamp)
    }

    private static func captures(_ pattern: String, _ text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (1..<match.numberOfRanges).map { index in
            Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
        }
    }
}

nonisolated struct AutoEQFitResult: Sendable {
    let gains: [Float]
    let preamp: Float
    let rms: Double
    let maximumError: Double
    let sampleRate: Double
    let preampAdjusted: Bool

    var requiresApply: Bool {
        preampAdjusted || rms > 1 || maximumError > 3
    }
}

nonisolated struct AutoEQPreparedPreset: Sendable {
    let input: AutoEQImportedPreset
    let ten: AutoEQFitResult
    let thirtyOne: AutoEQFitResult

    func result(for mode: EQBandMode) -> AutoEQFitResult {
        mode == .tenBand ? ten : thirtyOne
    }
}

extension EQConverter {
    nonisolated static func preampLimit(mode: EQBandMode, gains: [Float], sampleRate: Double) throws -> Float {
        guard sampleRate.isFinite, (40000...384_000).contains(sampleRate), gains.count == mode.bandCount,
              gains.allSatisfy({ $0.isFinite && abs($0) <= 20 }) else { throw AutoEQImportError.invalidSource }
        let coefficients = FixedBandEQDefinition.bands(mode: mode, gains: gains).map {
            BiquadResponseCalculator.coefficients(
                frequency: $0.frequency,
                gain: $0.gain,
                q: $0.q,
                type: $0.filterType,
                sampleRate: Float(sampleRate)
            )
        }
        var peak = 0.0
        for index in 0...4096 {
            if index.isMultiple(of: 128) { try Task.checkCancellation() }
            let frequency = pow(sampleRate * 0.499, Double(index) / 4096)
            let value = try coefficients.reduce(0.0) { try $0 + response($1, frequency: frequency, rate: sampleRate) }
            peak = max(peak, value)
        }
        return peak > 0.001 ? Float(-ceil((peak + 0.2) * 10) / 10) : 0
    }

    nonisolated func prepare(_ preset: AutoEQImportedPreset) throws -> AutoEQPreparedPreset {
        guard sampleRate.isFinite, sampleRate >= 40000,
              sampleRate <= 384_000 else { throw AutoEQImportError.invalidSampleRate }
        guard preset.preamp.map({ $0.isFinite && abs($0) <= 40 }) ?? true else { throw AutoEQImportError.invalidSource }
        switch preset.response {
        case let .parametric(filters):
            if !filters.isEmpty {
                _ = try AutoEQImportParser.validated(filters, preamp: preset.preamp)
            } else if preset.preamp == nil {
                throw AutoEQImportError.invalidSource
            }
        case let .graphic(points):
            guard !points.isEmpty, points.count <= 4096,
                  points
                  .allSatisfy({
                      $0.frequency.isFinite && (10...30000).contains($0.frequency) && $0.gain
                          .isFinite && abs($0.gain) <= 40 }),
                  zip(points, points.dropFirst()).allSatisfy({ $0.frequency < $1.frequency })
            else { throw AutoEQImportError.invalidSource }
        }
        return try AutoEQPreparedPreset(
            input: preset,
            ten: fit(preset, mode: .tenBand),
            thirtyOne: fit(preset, mode: .thirtyOneBand)
        )
    }

    nonisolated private func fit(_ preset: AutoEQImportedPreset, mode: EQBandMode) throws -> AutoEQFitResult {
        try Task.checkCancellation()
        let grid = (0..<256).map { 20 * pow(1000, Double($0) / 255) }
        let target = try grid.map { try sourceResponse(preset.response, at: $0) }
        let bases = FixedBandEQDefinition.bands(mode: mode, gains: [Float](repeating: 0, count: mode.bandCount))
        func curve(_ index: Int, _ gain: Float) throws -> [Double] {
            let band = bases[index]
            let coefficients = BiquadResponseCalculator.coefficients(
                frequency: band.frequency,
                gain: gain,
                q: band.q,
                type: band.filterType,
                sampleRate: Float(sampleRate)
            )
            return try grid.map { try Self.response(coefficients, frequency: $0, rate: sampleRate) }
        }
        func loss(_ values: [Double]) -> Double {
            zip(values, target).reduce(0) { $0 + pow($1.0 - $1.1, 2) }
        }
        var gains = [Float](repeating: 0, count: bases.count)
        var responses = try gains.indices.map { try curve($0, 0) }
        var total = [Double](repeating: 0, count: grid.count)
        for step in [4.0, 2, 1, 0.5, 0.25, 0.125, 0.0625, 0.03125] {
            for _ in 0..<8 {
                var changed = false
                for index in gains.indices {
                    try Task.checkCancellation()
                    let rest = zip(total, responses[index]).map(-)
                    var best = loss(total)
                    var chosen = gains[index]
                    var chosenResponse = responses[index]
                    for direction in [-1.0, 1.0] {
                        let candidate = Float(min(20, max(-20, Double(gains[index]) + step * direction)))
                        let values = try curve(index, candidate)
                        let score = loss(zip(rest, values).map(+))
                        if score.isFinite, score < best {
                            best = score
                            chosen = candidate
                            chosenResponse = values
                        }
                    }
                    changed = changed || chosen != gains[index]
                    gains[index] = chosen
                    responses[index] = chosenResponse
                    total = zip(rest, chosenResponse).map(+)
                }
                if !changed { break }
            }
        }
        let coefficients = FixedBandEQDefinition.bands(mode: mode, gains: gains).map {
            BiquadResponseCalculator.coefficients(
                frequency: $0.frequency,
                gain: $0.gain,
                q: $0.q,
                type: $0.filterType,
                sampleRate: Float(sampleRate)
            )
        }
        var peak = 0.0
        var squared = 0.0
        var lowCount = 0
        var maximum = 0.0
        for index in 0...4096 {
            if index.isMultiple(of: 128) { try Task.checkCancellation() }
            let frequency = pow(sampleRate * 0.499, Double(index) / 4096)
            let actual = try coefficients.reduce(0.0) { try $0 + Self.response(
                $1,
                frequency: frequency,
                rate: sampleRate
            ) }
            peak = max(peak, actual)
            if frequency >= 20, frequency <= 20000 {
                let delta = try actual - sourceResponse(preset.response, at: frequency)
                maximum = max(maximum, abs(delta))
                if frequency <= 6000 {
                    squared += delta * delta
                    lowCount += 1
                }
            }
        }
        let required = peak > 0.001 ? -ceil((peak + 0.2) * 10) / 10 : 0
        let declared = preset.legacyPreamp ? nil : preset.preamp
        let preamp = min(declared ?? 0, required)
        guard preamp >= -20, lowCount > 0, maximum.isFinite else { throw AutoEQImportError.insufficientHeadroom }
        return AutoEQFitResult(
            gains: gains,
            preamp: Float(preamp),
            rms: sqrt(squared / Double(lowCount)),
            maximumError: maximum,
            sampleRate: sampleRate,
            preampAdjusted: abs((preset.preamp ?? 0) - preamp) > 0.05
        )
    }

    nonisolated private func sourceResponse(
        _ source: AutoEQImportedPreset.Response,
        at frequency: Double
    ) throws -> Double {
        switch source {
        case let .parametric(filters):
            return try filters.filter(\.enabled).reduce(0) { value, filter in
                let coefficients = BiquadResponseCalculator.coefficients(
                    frequency: Float(filter.frequency),
                    gain: Float(filter.gain),
                    q: Float(filter.q),
                    type: filter.type,
                    sampleRate: Float(sampleRate)
                )
                return try value + Self.response(coefficients, frequency: frequency, rate: sampleRate)
            }
        case let .graphic(points):
            guard let first = points.first, let last = points.last else { throw AutoEQImportError.invalidSource }
            if frequency <= first.frequency { return first.gain }
            if frequency >= last.frequency { return last.gain }
            guard let high = points.firstIndex(where: { $0.frequency > frequency }), high > 0
            else { throw AutoEQImportError.invalidSource }
            let low = points[high - 1]
            let upper = points[high]
            return low
                .gain + (upper.gain - low.gain) * log(frequency / low.frequency) / log(upper.frequency / low.frequency)
        }
    }

    nonisolated static func response(
        _ coefficients: BiquadCoefficients,
        frequency: Double,
        rate: Double
    ) throws -> Double {
        let omega = 2 * Double.pi * frequency / rate
        let nr = Double(coefficients.b0) + Double(coefficients.b1) * cos(omega) + Double(coefficients.b2) *
            cos(2 * omega)
        let ni = -Double(coefficients.b1) * sin(omega) - Double(coefficients.b2) * sin(2 * omega)
        let dr = 1 + Double(coefficients.a1) * cos(omega) + Double(coefficients.a2) * cos(2 * omega)
        let di = -Double(coefficients.a1) * sin(omega) - Double(coefficients.a2) * sin(2 * omega)
        let numerator = nr * nr + ni * ni
        let denominator = dr * dr + di * di
        guard numerator > 0, denominator > 0 else { throw AutoEQImportError.invalidSource }
        let value = 10 * log10(numerator / denominator)
        guard value.isFinite else { throw AutoEQImportError.invalidSource }
        return value
    }
}
