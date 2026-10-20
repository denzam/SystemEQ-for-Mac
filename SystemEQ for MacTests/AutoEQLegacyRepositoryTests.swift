import Darwin
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

        try repository.saveOfflineIndex(entries, now: 100)

        let fresh = try XCTUnwrap(repository.loadOfflineIndex(now: 200))
        XCTAssertEqual(fresh.entries, entries)
        XCTAssertEqual(fresh.lastUpdate, 100)
        XCTAssertFalse(fresh.needsUpdate)

        let stale = try XCTUnwrap(repository.loadOfflineIndex(now: 31 * 24 * 3600 + 100))
        XCTAssertTrue(stale.needsUpdate)
    }

    func testDiskCacheDoesNotCreateNetworkSessionAndFirstAccessReusesIt() throws {
        var sessionCreationCount = 0
        let expectedSession = URLSession(configuration: .ephemeral)
        defer { expectedSession.invalidateAndCancel() }
        let repository = AutoEQLegacyRepository(
            applicationSupportDirectory: temporaryDirectory,
            sessionFactory: {
                sessionCreationCount += 1
                return expectedSession
            }
        )

        try repository.saveOfflineIndex([], now: 100)
        XCTAssertNotNil(repository.loadOfflineIndex(now: 200))
        XCTAssertNil(repository.loadCandidates(for: "missing"))
        XCTAssertEqual(sessionCreationCount, 0)

        XCTAssertTrue(repository.session === expectedSession)
        XCTAssertTrue(repository.session === expectedSession)
        XCTAssertEqual(sessionCreationCount, 1)
    }

    func testOfflineIndexSaveRequiresApplicationSupportDirectoryWithoutCreatingSession() {
        var sessionCreationCount = 0
        let repository = AutoEQLegacyRepository(
            applicationSupportDirectory: nil,
            sessionFactory: {
                sessionCreationCount += 1
                return URLSession(configuration: .ephemeral)
            }
        )

        XCTAssertThrowsError(try repository.saveOfflineIndex([], now: 100)) { error in
            XCTAssertEqual((error as NSError).domain, NSCocoaErrorDomain)
            XCTAssertEqual((error as NSError).code, CocoaError.fileNoSuchFile.rawValue)
        }
        XCTAssertEqual(sessionCreationCount, 0)
    }

    func testOfflineIndexSaveRejectsBlockedDirectoryAndPreservesExistingFile() throws {
        let blocked = temporaryDirectory.appendingPathComponent("blocked")
        let original = Data("preserved data".utf8)
        try original.write(to: blocked)
        let repository = AutoEQLegacyRepository(applicationSupportDirectory: blocked)

        XCTAssertThrowsError(try repository.saveOfflineIndex([], now: 100))
        XCTAssertEqual(try Data(contentsOf: blocked), original)
    }

    func testOfflineIndexSaveRejectsDirectoryAtDestinationAndPreservesItsContents() throws {
        let directory = temporaryDirectory.appendingPathComponent("SystemEQ/AutoEQIndex.json", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let sentinel = directory.appendingPathComponent("preserved")
        let original = Data("preserved data".utf8)
        try original.write(to: sentinel)
        let repository = AutoEQLegacyRepository(applicationSupportDirectory: temporaryDirectory)

        XCTAssertThrowsError(try repository.saveOfflineIndex([], now: 100))
        XCTAssertEqual(try Data(contentsOf: sentinel), original)
    }

    func testOfflineIndexEncodingFailurePreservesPreviousCacheAndTimestamp() throws {
        let repository = AutoEQLegacyRepository(applicationSupportDirectory: temporaryDirectory)
        try repository.saveOfflineIndex([], now: 100)
        let cacheURL = temporaryDirectory.appendingPathComponent("SystemEQ/AutoEQIndex.json")
        let original = try Data(contentsOf: cacheURL)
        let modified = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: cacheURL.path)[.modificationDate] as? Date
        )

        for timestamp in [TimeInterval.nan, .infinity, -.infinity] {
            XCTAssertThrowsError(try repository.saveOfflineIndex([], now: timestamp)) { error in
                XCTAssertTrue(error is EncodingError)
            }
            XCTAssertEqual(try Data(contentsOf: cacheURL), original)
            XCTAssertEqual(
                try FileManager.default.attributesOfItem(atPath: cacheURL.path)[.modificationDate] as? Date,
                modified
            )
            XCTAssertEqual(repository.loadOfflineIndex(now: 200)?.lastUpdate, 100)
        }
    }

    func testOfflineIndexWriteFailurePreservesPreviousCacheAndTimestamp() throws {
        try XCTSkipIf(geteuid() == 0, "Root can bypass directory write permissions")
        let repository = AutoEQLegacyRepository(applicationSupportDirectory: temporaryDirectory)
        try repository.saveOfflineIndex([], now: 100)
        let directory = temporaryDirectory.appendingPathComponent("SystemEQ", isDirectory: true)
        let cacheURL = directory.appendingPathComponent("AutoEQIndex.json")
        let original = try Data(contentsOf: cacheURL)
        let modified = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: cacheURL.path)[.modificationDate] as? Date
        )
        let permissions = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions]
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
        defer {
            do {
                try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: directory.path)
            } catch {
                XCTFail("Failed to restore fixture permissions: \(error)")
            }
        }

        XCTAssertThrowsError(try repository.saveOfflineIndex([], now: 200))
        XCTAssertEqual(try Data(contentsOf: cacheURL), original)
        XCTAssertEqual(
            try FileManager.default.attributesOfItem(atPath: cacheURL.path)[.modificationDate] as? Date,
            modified
        )
        XCTAssertEqual(repository.loadOfflineIndex(now: 300)?.lastUpdate, 100)
    }

    func testInjectedNetworkSessionDoesNotCallFactory() {
        let expectedSession = URLSession(configuration: .ephemeral)
        defer { expectedSession.invalidateAndCancel() }
        let repository = AutoEQLegacyRepository(
            applicationSupportDirectory: temporaryDirectory,
            session: expectedSession,
            sessionFactory: {
                XCTFail("An injected session must take priority over the factory")
                return expectedSession
            }
        )

        XCTAssertTrue(repository.session === expectedSession)
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
