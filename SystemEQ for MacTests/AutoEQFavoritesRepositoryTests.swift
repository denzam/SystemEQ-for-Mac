import Foundation
@testable import SystemEQ_for_Mac
import XCTest

@MainActor
final class AutoEQFavoritesRepositoryTests: XCTestCase {
    private func favorite(
        id: String = "one", name: String = "Model", path: String = "database:stable-identity",
        rawText: String? = nil, preamp: Double? = nil
    ) -> FavoritePreset {
        FavoritePreset(
            id: id, name: name, source: "source", target: "target", path: path,
            timestamp: Date(timeIntervalSinceReferenceDate: 42), rawText: rawText, preamp: preamp
        )
    }

    func testInitializationIsLazyAndLoadRefreshesStorage() throws {
        let storage = MemoryFavoritesStorage()
        let repository = storage.repository()
        XCTAssertEqual(storage.reads, 0)
        XCTAssertEqual(storage.writes, 0)
        XCTAssertTrue(repository.favorites.isEmpty)
        let first = favorite()
        storage.data = try JSONEncoder().encode([first])
        try repository.load()
        XCTAssertEqual(repository.favorites, [first])
        storage.data = try JSONEncoder().encode([favorite(id: "two", path: "other")])
        try repository.load()
        XCTAssertEqual(repository.favorites.map(\.id), ["two"])
        XCTAssertEqual(storage.writes, 0)
    }

    func testLegacyJSONWithoutOptionalMetadataRemainsReadable() throws {
        let storage = MemoryFavoritesStorage()
        storage.data = Data(#"[{"id":"legacy","name":"Legacy","path":"results/legacy","timestamp":0}]"#.utf8)
        let repository = storage.repository()
        try repository.load()
        let entry = try XCTUnwrap(repository.favorites.first)
        XCTAssertEqual(entry.id, "legacy")
        XCTAssertNil(entry.source)
        XCTAssertNil(entry.target)
        XCTAssertNil(entry.rawText)
        XCTAssertNil(entry.preamp)
        XCTAssertEqual(entry.timestamp, Date(timeIntervalSinceReferenceDate: 0))
        XCTAssertEqual(storage.writes, 0)
    }

    func testDefaultAdapterKeepsExistingUserDefaultsKeyAndJSONFormat() throws {
        let name = "SystemEQFavoritesTests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let entry = favorite()
        try defaults.set(JSONEncoder().encode([entry]), forKey: "autoEQFavorites")
        let repository = AutoEQFavoritesRepository(defaults: defaults)
        XCTAssertTrue(repository.favorites.isEmpty)
        try repository.load()
        XCTAssertEqual(repository.favorites, [entry])
        try repository.togglePath(path: "results/second", name: "Second", source: nil, target: nil)
        let data = try XCTUnwrap(defaults.data(forKey: "autoEQFavorites"))
        XCTAssertEqual(try JSONDecoder().decode([FavoritePreset].self, from: data), repository.favorites)
    }

    func testPathMatchingKeepsSourcesSeparateAndIgnoresDisplayName() throws {
        let storage = MemoryFavoritesStorage()
        let repository = storage.repository()
        try repository.togglePath(path: "database:source-a", name: "Same model", source: "a", target: "target")
        try repository.togglePath(path: "database:source-b", name: "Same model", source: "b", target: "target")
        XCTAssertTrue(repository.contains(path: "database:source-a"))
        XCTAssertTrue(repository.contains(path: "database:source-b"))
        XCTAssertFalse(repository.contains(path: "database:source"))
        try repository.togglePath(path: "database:source-a", name: "Renamed", source: nil, target: nil)
        XCTAssertEqual(repository.favorites.map(\.path), ["database:source-b"])
    }

    func testRemotePathsAndAppendOrderArePreserved() throws {
        let storage = MemoryFavoritesStorage()
        let repository = storage.repository()
        for path in ["results/a/over-ear/Model/README.md", "results/b/over-ear/Model/ParametricEQ.txt"] {
            try repository.togglePath(path: path, name: path, source: nil, target: nil)
        }
        XCTAssertEqual(repository.favorites.map(\.path), [
            "results/a/over-ear/Model/README.md", "results/b/over-ear/Model/ParametricEQ.txt",
        ])
        XCTAssertTrue(repository.favorites.allSatisfy { $0.source == nil && $0.target == nil })
        let restored = storage.repository()
        try restored.load()
        XCTAssertEqual(restored.favorites, repository.favorites)
    }

    func testCustomFavoriteRoundTripKeepsTextPreampAndMetadata() throws {
        let storage = MemoryFavoritesStorage()
        let repository = storage.repository()
        let text = "Preamp: -3 dB\nFilter 1: ON PK Fc 1000 Hz Gain 2 dB Q 1"
        try repository.toggleCustom(name: "Custom preset", source: "Custom", target: "flat", rawText: text, preamp: -3)
        let restored = storage.repository()
        try restored.load()
        let entry = try XCTUnwrap(restored.favorites.first)
        XCTAssertEqual(entry.path, "custom:Custom preset")
        XCTAssertEqual(entry.name, "Custom preset")
        XCTAssertEqual(entry.source, "Custom")
        XCTAssertEqual(entry.target, "flat")
        XCTAssertEqual(entry.rawText, text)
        XCTAssertEqual(entry.preamp, -3)
        XCTAssertTrue(restored.containsCustom(named: "Custom preset"))
    }

    func testCustomToggleMatchesNameRatherThanTextOrRegularFavorite() throws {
        let storage = MemoryFavoritesStorage()
        storage.data = try JSONEncoder().encode([favorite(name: "Same name")])
        let repository = storage.repository()
        try repository.load()
        XCTAssertFalse(repository.containsCustom(named: "Same name"))
        try repository.toggleCustom(name: "Same name", source: nil, target: nil, rawText: "first", preamp: nil)
        XCTAssertEqual(repository.favorites.count, 2)
        try repository.toggleCustom(name: "Same name", source: nil, target: nil, rawText: "different", preamp: -10)
        XCTAssertEqual(repository.favorites.count, 1)
        XCTAssertEqual(repository.favorites.first?.rawText, nil)
    }

    func testToggleRemovesFirstPathMatchAndRemoveDeletesAllMatchingIDs() throws {
        let storage = MemoryFavoritesStorage()
        let one = favorite(id: "duplicate", name: "first")
        let two = favorite(id: "duplicate", name: "second")
        let three = favorite(id: "third", path: "other")
        storage.data = try JSONEncoder().encode([one, two, three])
        let repository = storage.repository()
        try repository.load()
        try repository.togglePath(path: one.path, name: "ignored", source: nil, target: nil)
        XCTAssertEqual(repository.favorites, [two, three])
        storage.data = try JSONEncoder().encode([one, two, three])
        try repository.load()
        try repository.remove(id: "duplicate")
        XCTAssertEqual(repository.favorites, [three])
    }

    func testCorruptedOrWrongSchemaDataIsNotOverwritten() throws {
        let storage = MemoryFavoritesStorage()
        let repository = storage.repository()
        for data in [Data([0xFF]), Data("{}".utf8), Data("[{\"id\":\"broken\"}]".utf8)] {
            storage.data = try JSONEncoder().encode([favorite()])
            try repository.load()
            storage.data = data
            XCTAssertThrowsError(try repository.load())
            XCTAssertTrue(repository.favorites.isEmpty)
            XCTAssertEqual(storage.data, data)
            XCTAssertEqual(storage.writes, 0)
        }
    }

    func testMissingOrEmptyStorageClearsMemoryWithoutWriting() throws {
        let storage = MemoryFavoritesStorage()
        let repository = storage.repository()
        let emptyCases: [Data?] = [nil, Data()]
        for data in emptyCases {
            storage.data = try JSONEncoder().encode([favorite()])
            try repository.load()
            storage.data = data
            try repository.load()
            XCTAssertTrue(repository.favorites.isEmpty)
            XCTAssertEqual(storage.writes, 0)
        }
    }

    func testEncodingFailurePreservesSavedBytesAndPublishedState() throws {
        let storage = MemoryFavoritesStorage()
        storage.data = try JSONEncoder().encode([favorite()])
        let repository = storage.repository()
        try repository.load()
        let previous = storage.data
        let state = repository.favorites
        XCTAssertThrowsError(try repository.toggleCustom(
            name: "invalid", source: "Custom", target: nil, rawText: "text", preamp: .nan
        ))
        XCTAssertEqual(storage.data, previous)
        XCTAssertEqual(repository.favorites, state)
        XCTAssertEqual(storage.writes, 0)
    }

    func testWriteFailurePreservesPublishedStateAndAllowsRetry() throws {
        let storage = MemoryFavoritesStorage()
        storage.data = try JSONEncoder().encode([favorite()])
        let repository = storage.repository()
        try repository.load()
        let previous = storage.data
        let state = repository.favorites
        storage.failWrite = true
        XCTAssertThrowsError(try repository.remove(id: "one"))
        XCTAssertEqual(storage.data, previous)
        XCTAssertEqual(repository.favorites, state)
        storage.failWrite = false
        try repository.remove(id: "one")
        XCTAssertTrue(repository.favorites.isEmpty)
        XCTAssertEqual(try JSONDecoder().decode([FavoritePreset].self, from: XCTUnwrap(storage.data)), [])
    }
}

@MainActor
private final class MemoryFavoritesStorage {
    var data: Data?
    var reads = 0
    var writes = 0
    var failWrite = false

    func repository() -> AutoEQFavoritesRepository {
        AutoEQFavoritesRepository(readData: { [self] in
            reads += 1
            return data
        }, writeData: { [self] value in
            if failWrite { throw CocoaError(.fileWriteUnknown) }
            writes += 1
            data = value
        })
    }
}
