@testable import SystemEQ_for_Mac
import XCTest

final class AutoEQLegacyRepositoryTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        temporaryDirectory = nil
    }

    func testOfflineIndexRoundTripReportsAge() throws {
        let repository = AutoEQLegacyRepository(applicationSupportDirectory: temporaryDirectory)
        let entries = [
            OfflineIndexEntry(
                brand: "Sennheiser",
                model: "HD 600",
                source: "oratory1990",
                type: "over-ear",
                pathReadme: "results/oratory1990/over-ear/Sennheiser HD 600/README.md"
            )
        ]

        repository.saveOfflineIndex(entries, now: 100)

        let fresh = try XCTUnwrap(repository.loadOfflineIndex(now: 200))
        XCTAssertEqual(fresh.entries, entries)
        XCTAssertEqual(fresh.lastUpdate, 100)
        XCTAssertFalse(fresh.needsUpdate)

        let stale = try XCTUnwrap(repository.loadOfflineIndex(now: 31 * 24 * 3600 + 100))
        XCTAssertTrue(stale.needsUpdate)
    }

    func testCandidateCacheRoundTripAndExpiration() throws {
        let repository = AutoEQLegacyRepository(applicationSupportDirectory: temporaryDirectory)
        let candidate = SearchCandidate(
            path: "results/oratory1990/over-ear/Sennheiser HD 600/README.md",
            name: "README.md",
            display: "oratory1990 / Sennheiser / HD 600 / README.md",
            isParametric: false
        )

        repository.saveCandidates([candidate], for: "HD 600 / Reference", now: 100)

        let cached = try XCTUnwrap(repository.loadCandidates(for: "HD 600 / Reference", now: 200))
        XCTAssertEqual(cached.count, 1)
        XCTAssertEqual(cached[0].path, candidate.path)
        XCTAssertEqual(cached[0].name, candidate.name)
        XCTAssertEqual(cached[0].display, candidate.display)
        XCTAssertEqual(cached[0].isParametric, candidate.isParametric)

        XCTAssertNil(repository.loadCandidates(for: "HD 600 / Reference", now: 8 * 24 * 3600 + 100))
    }
}
