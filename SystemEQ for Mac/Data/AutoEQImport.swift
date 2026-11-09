import Foundation

nonisolated enum AutoEQImportError: Error, Equatable {
    case invalidSource
    case invalidLine(Int)
    case invalidSampleRate
    case insufficientHeadroom
    case directUnavailable
}

nonisolated public struct AutoEQSourceFilter: Codable, Equatable, Sendable {
    let frequency: Double
    let gain: Double
    let q: Double
    let type: FilterType
    var enabled = true

    var band: ParametricBand {
        ParametricBand(frequency: Float(frequency), gain: Float(gain), q: Float(q), filterType: type)
    }

    static func validDirect(_ filters: [Self]) -> Bool {
        filters.count <= 256 && filters.allSatisfy {
            $0.enabled && (20...20000).contains($0.frequency) &&
                (-30...30).contains($0.gain) && (0.1...20).contains($0.q)
        }
    }

    func centerResponseError(_ response: Double) -> Double {
        let expected: Double
        switch type {
        case .notch:
            return response <= -30 ? 0 : .infinity
        case .peak:
            expected = gain
        case .highShelf,
             .lowShelf:
            expected = gain / 2
        case .highPass,
             .lowPass:
            expected = 20 * log10(q)
        case .allPass,
             .allPassPEQ,
             .bandPass:
            expected = 0
        }
        return abs(response - expected)
    }
}

nonisolated struct AutoEQCurvePoint: Equatable, Sendable {
    let frequency: Double
    let gain: Double
}

nonisolated struct EQLinearResponse: Equatable, Sendable {
    let sampleRate: Float
    let coefficients: [BiquadCoefficients]
    let preampDB: Float
    var criticalFrequencies: [Double] = []

    func gain(at frequency: Double) -> Double? {
        guard sampleRate.isFinite, sampleRate > 0, preampDB.isFinite,
              frequency.isFinite, (0...Double(sampleRate) / 2).contains(frequency)
        else { return nil }
        return try? coefficients.reduce(Double(preampDB)) {
            try $0 + EQConverter.response($1, frequency: frequency, rate: Double(sampleRate))
        }
    }

    func plot() -> [AutoEQCurvePoint] {
        let upper = min(20000, Double(sampleRate) / 2)
        guard upper.isFinite, upper > 20 else { return [] }
        let grid = (0..<768).map { index in
            index == 767 ? upper : 20 * pow(upper / 20, Double(index) / 767)
        }
        let frequencies = Set(grid + criticalFrequencies.filter { (20...upper).contains($0) }).sorted()
        var points: [AutoEQCurvePoint] = []
        points.reserveCapacity(frequencies.count)
        for frequency in frequencies {
            if Task.isCancelled { return [] }
            guard let gain = gain(at: frequency) else { return [] }
            points.append(AutoEQCurvePoint(frequency: frequency, gain: gain))
        }
        return points
    }
}

nonisolated struct AutoEQImportedPreset: Equatable, Sendable {
    enum Response: Equatable, Sendable {
        case parametric([AutoEQSourceFilter])
        case graphic([AutoEQCurvePoint])
    }

    let response: Response
    let preamp: Double?
    var legacyPreamp = false

    var directFilters: [AutoEQSourceFilter]? {
        guard case let .parametric(filters) = response else { return nil }
        let enabled = filters.filter(\.enabled)
        return AutoEQSourceFilter.validDirect(enabled) ? enabled : nil
    }

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

nonisolated private struct SectionPeakResponse {
    let coefficients: BiquadCoefficients
    let stationary: [(cosine: Double, gain: Double)]

    init(_ coefficients: BiquadCoefficients) throws {
        self.coefficients = coefficients
        stationary = try [-1.0, 1.0].flatMap { edge in
            let n = Self.powerPolynomial(
                Double(coefficients.b0), Double(coefficients.b1), Double(coefficients.b2), edge: edge
            )
            let d = Self.powerPolynomial(1, Double(coefficients.a1), Double(coefficients.a2), edge: edge)
            let a = n.square * d.linear - n.linear * d.square
            let b = 2 * (n.square * d.constant - n.constant * d.square)
            let c = n.linear * d.constant - n.constant * d.linear
            return try Self.roots(a: a, b: b, c: c).filter { (0...1).contains($0) }.map {
                let cosine = edge * (1 - $0)
                return try (cosine, Self.gain(coefficients, cosine: cosine))
            }
        }
    }

    private static func roots(a: Double, b: Double, c: Double) -> [Double] {
        let roots: [Double]
        if a == 0 {
            roots = b == 0 ? [] : [-c / b]
        } else {
            let discriminant = b * b - 4 * a * c
            if discriminant < 0 {
                roots = []
            } else {
                let root = sqrt(discriminant)
                let q = -0.5 * (b + (b >= 0 ? root : -root))
                roots = q == 0 ? [0] : [q / a, c / q]
            }
        }
        return roots
    }

    func gain(cosine: Double) throws -> Double {
        try Self.gain(coefficients, cosine: cosine)
    }

    private static func powerPolynomial(_ first: Double, _ middle: Double, _ last: Double, edge: Double)
        -> (square: Double, linear: Double, constant: Double) {
        let sum = first + last
        let difference = first - last
        let endpoint = sum * edge + middle
        return (4 * first * last, 2 * (difference * difference - sum * edge * endpoint), endpoint * endpoint)
    }

    private static func gain(_ c: BiquadCoefficients, cosine: Double) throws -> Double {
        func power(_ first: Double, _ middle: Double, _ last: Double) -> Double {
            let real = (first + last) * cosine + middle
            let difference = first - last
            return real * real + difference * difference * (1 - cosine * cosine)
        }
        let numerator = power(Double(c.b0), Double(c.b1), Double(c.b2))
        let denominator = power(1, Double(c.a1), Double(c.a2))
        guard numerator.isFinite, denominator.isFinite, denominator > 0
        else { throw AutoEQImportError.invalidSource }
        return 10 * log10(max(1e-30, numerator / denominator))
    }
}

extension EQConverter {
    nonisolated static func directPreampLimit(bands: [ParametricBand], sampleRate: Double) throws -> Float {
        guard sampleRate.isFinite, sampleRate > 0, sampleRate <= 384_000
        else { throw AutoEQImportError.invalidSampleRate }
        let coefficients = BiquadResponseCalculator.preparedCoefficients(
            bands: bands, sampleRate: Float(sampleRate), minimumGainMagnitude: 0
        )
        guard !coefficients.isEmpty else { return 0 }
        let sections = try coefficients.map(SectionPeakResponse.init)
        var previousCosine = 1.0
        var previousGains = try sections.map { try $0.gain(cosine: previousCosine) }
        var maximum = 0.0
        var refinements = 4096
        func intervalBound(
            low: Double, lowGains: [Double], high: Double, highGains: [Double], depth: Int
        ) throws -> Double {
            var bound = 0.0
            var lowTotal = 0.0
            var highTotal = 0.0
            for index in sections.indices {
                var peak = max(lowGains[index], highGains[index])
                for point in sections[index].stationary where (low...high).contains(point.cosine) {
                    peak = max(peak, point.gain)
                }
                bound += peak
                lowTotal += lowGains[index]
                highTotal += highGains[index]
            }
            let middle = (low + high) / 2
            guard bound > max(maximum, lowTotal, highTotal) + 0.1,
                  refinements > 0, depth > 0, low < middle, middle < high else { return bound }
            refinements -= 1
            let middleGains = try sections.map { try $0.gain(cosine: middle) }
            let left = try intervalBound(
                low: low, lowGains: lowGains, high: middle, highGains: middleGains, depth: depth - 1
            )
            let right = try intervalBound(
                low: middle, lowGains: middleGains, high: high, highGains: highGains, depth: depth - 1
            )
            return max(left, right)
        }
        for index in 0...4096 {
            if index.isMultiple(of: 128) { try Task.checkCancellation() }
            let frequency = pow(sampleRate / 2, Double(index) / 4096)
            let cosine = index == 4096 ? -1 : cos(2 * .pi * frequency / sampleRate)
            let gains = try sections.map { try $0.gain(cosine: cosine) }
            let bound = try intervalBound(
                low: cosine, lowGains: gains, high: previousCosine, highGains: previousGains, depth: 14
            )
            maximum = max(maximum, bound)
            previousCosine = cosine
            previousGains = gains
        }
        return maximum > 0.001 ? Float(-ceil((maximum + 0.2) * 10) / 10) : 0
    }

    nonisolated static func preampLimit(mode: EQBandMode, gains: [Float], sampleRate: Double) throws -> Float {
        guard sampleRate.isFinite, (40000...384_000).contains(sampleRate), gains.count == mode.bandCount,
              gains.allSatisfy({ $0.isFinite && abs($0) <= 20 }) else { throw AutoEQImportError.invalidSource }
        return try preampLimit(bands: FixedBandEQDefinition.bands(mode: mode, gains: gains), sampleRate: sampleRate)
    }

    nonisolated static func preampLimit(bands: [ParametricBand], sampleRate: Double) throws -> Float {
        guard sampleRate.isFinite, sampleRate > 0, sampleRate <= 384_000
        else { throw AutoEQImportError.invalidSampleRate }
        let coefficients = BiquadResponseCalculator.preparedCoefficients(
            bands: bands, sampleRate: Float(sampleRate)
        )
        guard !coefficients.isEmpty else { return 0 }
        var peak = 0.0
        for index in 0...4097 {
            if index.isMultiple(of: 128) { try Task.checkCancellation() }
            let frequency = index == 0 ? 0 : pow(sampleRate / 2, Double(index - 1) / 4096)
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
        guard numerator.isFinite, denominator.isFinite, denominator > 0
        else { throw AutoEQImportError.invalidSource }
        if numerator == 0 { return -300 }
        let value = 10 * log10(numerator / denominator)
        guard value.isFinite else { throw AutoEQImportError.invalidSource }
        return value
    }
}
