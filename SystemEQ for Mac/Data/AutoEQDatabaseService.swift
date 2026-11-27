import Foundation

struct AutoEQDatabaseImport {
    let preset: DatabasePreset
    let gains10: [Float]
    let gains31: [Float]
}

struct AutoEQDatabaseService {
    static let candidatePrefix = "database:"

    let database: EQDatabase

    func search(_ query: String) -> [DatabaseHeadphone] {
        database.searchHeadphones(query)
    }

    func headphoneID(brand: String, model: String, source: String) -> Int? {
        database.headphone(brand: brand, model: model, source: source)?.id
    }

    func load(headphoneID: Int) -> AutoEQDatabaseImport? {
        guard let preset = database.getRecommendedPreset(for: headphoneID) else { return nil }
        let gains10 = database.getFixedBand10(presetId: preset.id)
        let gains31 = database.getGraphicEQ31(presetId: preset.id)
        guard gains10.count == 10, gains31.count == 31,
              gains10.allSatisfy(\.isFinite), gains31.allSatisfy(\.isFinite),
              preset.preampGain.isFinite else { return nil }
        return AutoEQDatabaseImport(preset: preset, gains10: gains10, gains31: gains31)
    }

    func loadCanonical(headphoneID: Int) throws -> (preset: DatabasePreset, input: AutoEQImportedPreset) {
        guard let preset = database.getRecommendedPreset(for: headphoneID)
        else { throw AutoEQImportError.invalidSource }
        let input = try database.canonicalPreset(presetId: preset.id, legacy: preset.source != "community")
        return (preset, input)
    }

    static func candidate(_ headphone: DatabaseHeadphone) -> SearchCandidate {
        let identity = [headphone.source, headphone.brand, headphone.model]
            .map { Data($0.utf8).base64EncodedString() }
            .joined(separator: ":")
        return SearchCandidate(
            path: candidatePrefix + identity,
            name: String(headphone.id),
            display: "\(headphone.displayName) · \(headphone.source)",
            isParametric: false
        )
    }

    func searchCandidates(for query: String) -> [SearchCandidate] {
        var candidates: [SearchCandidate] = []
        for headphone in search(query) {
            candidates.append(Self.candidate(headphone))
        }
        return candidates
    }

    static func source(from candidate: SearchCandidate) -> String? {
        identity(from: candidate.path)?.source
    }

    static func identity(from path: String) -> (source: String, brand: String, model: String)? {
        guard path.hasPrefix(candidatePrefix) else { return nil }
        let encoded = path.dropFirst(candidatePrefix.count).split(separator: ":")
        guard encoded.count == 3 else { return nil }
        let values = encoded.compactMap { component -> String? in
            guard let data = Data(base64Encoded: String(component)) else { return nil }
            return String(data: data, encoding: .utf8)
        }
        guard values.count == 3 else { return nil }
        return (values[0], values[1], values[2])
    }

    func headphoneID(from candidate: SearchCandidate) -> Int? {
        headphoneID(from: candidate.path)
    }

    private func headphoneID(from path: String) -> Int? {
        guard let identity = Self.identity(from: path) else { return nil }
        return headphoneID(
            brand: identity.brand,
            model: identity.model,
            source: identity.source
        )
    }

    func targetCurve(for path: String) -> String? {
        guard let id = headphoneID(from: path) else { return nil }
        return database.getRecommendedPreset(for: id)?.targetCurve
    }

    func displayIdentity(_ identity: AutoEQState.Identity?) -> AutoEQState.Identity? {
        guard var identity else { return nil }
        if identity.target == AppConstants.EQ.defaultTarget,
           let path = identity.path, path.hasPrefix(Self.candidatePrefix) {
            identity.target = targetCurve(for: path)
        }
        return identity
    }
}
