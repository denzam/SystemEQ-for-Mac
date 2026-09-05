import Foundation

struct AutoEQDatabaseImport {
    let preset: DatabasePreset
    let gains10: [Float]
    let gains31: [Float]
}

struct AutoEQDatabaseService {
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
}
