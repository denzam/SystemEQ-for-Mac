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
    private let readData: () throws -> Data?
    private let writeData: (Data) throws -> Void
    private var hasLoaded = false
    private var loadError: Error?

    convenience init(defaults: UserDefaults = .standard) {
        self.init(
            readData: {
                guard let stored = defaults.object(forKey: Self.storageKey) else { return nil }
                guard let data = stored as? Data else { throw CocoaError(.coderReadCorrupt) }
                return data
            },
            writeData: { defaults.set($0, forKey: Self.storageKey) }
        )
    }

    init(readData: @escaping () throws -> Data?, writeData: @escaping (Data) throws -> Void) {
        self.readData = readData
        self.writeData = writeData
    }

    func load() throws {
        hasLoaded = true
        do {
            guard let data = try readData(), !data.isEmpty else {
                favorites = []
                loadError = nil
                return
            }
            favorites = try JSONDecoder().decode([FavoritePreset].self, from: data)
            loadError = nil
        } catch {
            favorites = []
            loadError = error
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
        try prepareForMutation()
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
        try prepareForMutation()
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
        try prepareForMutation()
        try save(favorites.filter { $0.id != id })
    }

    private func prepareForMutation() throws {
        if !hasLoaded { try load() }
        if let loadError { throw loadError }
    }

    private func save(_ next: [FavoritePreset]) throws {
        let data = try JSONEncoder().encode(next)
        try writeData(data)
        favorites = next
    }
}
