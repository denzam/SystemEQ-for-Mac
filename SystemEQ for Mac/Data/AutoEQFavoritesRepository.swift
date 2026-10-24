import Combine
import Foundation

struct FavoritePreset: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let source: String?
    let target: String?
    let path: String
    let timestamp: Date
    var rawText: String?
    var preamp: Double?
}

@MainActor
final class AutoEQFavoritesRepository: ObservableObject {
    static let storageKey = "autoEQFavorites"
    @Published private(set) var favorites: [FavoritePreset] = []
    private let readData: () -> Data?
    private let writeData: (Data) throws -> Void

    convenience init(defaults: UserDefaults = .standard) {
        self.init(
            readData: { defaults.data(forKey: Self.storageKey) },
            writeData: { defaults.set($0, forKey: Self.storageKey) }
        )
    }

    init(readData: @escaping () -> Data?, writeData: @escaping (Data) throws -> Void) {
        self.readData = readData
        self.writeData = writeData
    }

    func load() throws {
        guard let data = readData(), !data.isEmpty else {
            favorites = []
            return
        }
        do {
            favorites = try JSONDecoder().decode([FavoritePreset].self, from: data)
        } catch {
            favorites = []
            throw error
        }
    }

    func contains(path: String) -> Bool {
        favorites.contains { $0.path == path }
    }

    func containsCustom(named name: String) -> Bool {
        favorites.contains { $0.rawText != nil && $0.name == name }
    }

    func togglePath(path: String, name: String, source: String?, target: String?) throws {
        var next = favorites
        if let index = next.firstIndex(where: { $0.path == path }) {
            next.remove(at: index)
        } else {
            next.append(FavoritePreset(
                id: UUID().uuidString, name: name, source: source, target: target,
                path: path, timestamp: Date()
            ))
        }
        try save(next)
    }

    func toggleCustom(name: String, source: String?, target: String?, rawText: String, preamp: Double?) throws {
        var next = favorites
        if let index = next.firstIndex(where: { $0.rawText != nil && $0.name == name }) {
            next.remove(at: index)
        } else {
            next.append(FavoritePreset(
                id: UUID().uuidString, name: name, source: source, target: target,
                path: "custom:\(name)", timestamp: Date(), rawText: rawText, preamp: preamp
            ))
        }
        try save(next)
    }

    func remove(id: String) throws {
        try save(favorites.filter { $0.id != id })
    }

    private func save(_ next: [FavoritePreset]) throws {
        let data = try JSONEncoder().encode(next)
        try writeData(data)
        favorites = next
    }
}
