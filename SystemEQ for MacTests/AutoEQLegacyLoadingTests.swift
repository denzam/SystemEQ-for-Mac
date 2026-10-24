import Foundation
@testable import SystemEQ_for_Mac
import XCTest

@MainActor
final class AutoEQLegacyLoadingTests: XCTestCase {
    private var directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    private var blockedSession: URLSession?
    private let presetText = "Preamp: -3 dB\nFilter 1: ON PK Fc 1000 Hz Gain 2 dB Q 1"
    private let validIndex = "[Model](./source/over-ear/Maker%20Model)\n"

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BlockedAutoEQNetwork.self]
        blockedSession = URLSession(configuration: configuration)
    }

    override func tearDownWithError() throws {
        blockedSession?.invalidateAndCancel()
        blockedSession = nil
        try FileManager.default.removeItem(at: directory)
    }

    private func candidate(
        path: String = "results/source/over-ear/Maker Model/ParametricEQ.txt",
        parametric: Bool = true
    )
        -> SearchCandidate {
        SearchCandidate(path: path, name: "Preset", display: "source / Maker Model", isParametric: parametric)
    }

    private func repository(_ loader: ScriptedAutoEQLoader) -> AutoEQLegacyRepository {
        AutoEQLegacyRepository(
            applicationSupportDirectory: directory,
            session: blockedSession,
            localRoot: directory.appendingPathComponent("local"),
            dataLoader: { try await loader.load($0) }
        )
    }

    private func failure(_ action: () async throws -> some Any) async -> Error? {
        do {
            _ = try await action()
            XCTFail("Expected failure")
            return nil
        } catch {
            return error
        }
    }

    func testIndexRefreshReturnsOnlyAfterCacheWrite() async throws {
        let loader = ScriptedAutoEQLoader()
        loader.append(status: 201, text: validIndex)
        let repository = repository(loader)
        let entries = try await repository.refreshOfflineIndex(now: 200)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(repository.loadOfflineIndex(now: 201)?.entries, entries)
        XCTAssertEqual(repository.loadOfflineIndex(now: 201)?.lastUpdate, 200)
        XCTAssertEqual(loader.requests.count, 1)
    }

    func testHTTPFailuresAndMalformedIndexPreservePreviousBytesAndTimestamp() async throws {
        let loader = ScriptedAutoEQLoader()
        let repository = repository(loader)
        try repository.saveOfflineIndex([], now: 100)
        let url = directory.appendingPathComponent("SystemEQ/AutoEQIndex.json")
        let original = try Data(contentsOf: url)
        let modified = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
        for (status, data) in [
            (500, Data(validIndex.utf8)),
            (200, Data()),
            (200, Data([0xFF])),
            (200, Data("[Bad](./../over-ear/Model)".utf8))
        ] {
            loader.append(status: status, data: data)
            let error = await failure { try await repository.refreshOfflineIndex(now: 200) }
            XCTAssertNotNil(error)
            XCTAssertEqual(try Data(contentsOf: url), original)
            XCTAssertEqual(
                try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date,
                modified
            )
            XCTAssertEqual(repository.loadOfflineIndex(now: 201)?.lastUpdate, 100)
        }
    }

    func testNonHTTPResponseAndTransportFailurePreserveIndex() async throws {
        let loader = ScriptedAutoEQLoader()
        let repository = repository(loader)
        try repository.saveOfflineIndex([], now: 100)
        let url = directory.appendingPathComponent("SystemEQ/AutoEQIndex.json")
        let original = try Data(contentsOf: url)
        loader.responses.append(.success((
            Data(validIndex.utf8), URLResponse(
                url: loader.url,
                mimeType: nil,
                expectedContentLength: 0,
                textEncodingName: nil
            )
        )))
        let responseError = await failure { try await repository.refreshOfflineIndex(now: 200) }
        XCTAssertTrue(responseError is AutoEQLegacyRepository.IndexRefreshError)
        loader.responses.append(.failure(URLError(.timedOut)))
        let networkError = await failure { try await repository.refreshOfflineIndex(now: 200) }
        XCTAssertEqual((networkError as? URLError)?.code, .timedOut)
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    func testIndexRefreshWriteFailureDoesNotReturnSuccessOrReplaceDestination() async throws {
        let loader = ScriptedAutoEQLoader()
        loader.append(status: 200, text: validIndex)
        let repository = repository(loader)
        let destination = directory.appendingPathComponent("SystemEQ/AutoEQIndex.json")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let sentinel = destination.appendingPathComponent("preserved")
        try Data("keep".utf8).write(to: sentinel)
        let error = await failure { try await repository.refreshOfflineIndex(now: 200) }
        XCTAssertNotNil(error)
        XCTAssertEqual(try Data(contentsOf: sentinel), Data("keep".utf8))
    }

    func testCancelledRefreshDoesNotReplaceCache() async throws {
        let loader = ScriptedAutoEQLoader()
        loader.append(status: 200, text: validIndex)
        let repository = repository(loader)
        try repository.saveOfflineIndex([], now: 100)
        let task = Task { try await repository.refreshOfflineIndex(now: 200) }
        task.cancel()
        let error = await failure { try await task.value }
        XCTAssertTrue(error is CancellationError)
        XCTAssertEqual(repository.loadOfflineIndex(now: 201)?.lastUpdate, 100)
    }

    func testLocalFilesTakePriorityOverMemoryAndNetwork() async throws {
        let loader = ScriptedAutoEQLoader()
        loader.append(status: 200, text: presetText)
        let repository = repository(loader)
        let candidate = candidate()
        let downloaded = try await repository.resolveCandidateText(candidate, offlineIndex: [], checkValidity: {})
        repository.rememberDownloadedText(downloaded)
        let localRoot = directory.appendingPathComponent("local")
        let parametric = localRoot.appendingPathComponent(candidate.path)
        try FileManager.default.createDirectory(
            at: parametric.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("local".utf8).write(to: parametric)
        let fixedPath = "results/source/over-ear/Maker Model/FixedBandEQ.txt"
        try Data("fixed".utf8).write(to: localRoot.appendingPathComponent(fixedPath))
        let index = OfflineIndexEntry(
            brand: "Maker",
            model: "Model",
            source: "source",
            type: "over-ear",
            pathFixedBandEQ: fixedPath,
            pathParametric: candidate.path,
            pathReadme: "readme"
        )
        let result = try await repository.resolveCandidateText(candidate, offlineIndex: [index], checkValidity: {})
        XCTAssertEqual(result.origin, .local)
        XCTAssertEqual(result.text, "local")
        XCTAssertEqual(result.resolvedPath, candidate.path)
        XCTAssertEqual(loader.requests.count, 1)
    }

    func testUnreadableFirstLocalFileDoesNotFallBackToAnotherFormat() async throws {
        let loader = ScriptedAutoEQLoader()
        let repository = repository(loader)
        let candidate = candidate()
        let localRoot = directory.appendingPathComponent("local")
        try FileManager.default.createDirectory(
            at: localRoot.appendingPathComponent(candidate.path),
            withIntermediateDirectories: true
        )
        let fixedPath = "results/source/over-ear/Maker Model/FixedBandEQ.txt"
        try Data(presetText.utf8).write(to: localRoot.appendingPathComponent(fixedPath))
        let index = OfflineIndexEntry(
            brand: "Maker",
            model: "Model",
            source: "source",
            type: "over-ear",
            pathFixedBandEQ: fixedPath,
            pathParametric: candidate.path
        )
        let error = await failure {
            try await repository.resolveCandidateText(candidate, offlineIndex: [index], checkValidity: {})
        }
        XCTAssertNotNil(error)
        XCTAssertTrue(loader.requests.isEmpty)
    }

    func testLocalSymlinkEscapeIsRejectedWithoutNetwork() async throws {
        let loader = ScriptedAutoEQLoader()
        let repository = repository(loader)
        let root = directory.appendingPathComponent("local")
        let outside = directory.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data("private".utf8).write(to: outside.appendingPathComponent("preset"))
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("escape"),
            withDestinationURL: outside
        )
        let index = OfflineIndexEntry(
            brand: "Maker",
            model: "Model",
            source: "source",
            type: "over-ear",
            pathParametric: "escape/preset",
            pathReadme: "lookup"
        )
        let error = await failure {
            try await repository.resolveCandidateText(
                candidate(path: "lookup"),
                offlineIndex: [index],
                checkValidity: {}
            )
        }
        XCTAssertEqual(error as? AutoEQImportError, .invalidSource)
        XCTAssertTrue(loader.requests.isEmpty)
    }

    func testParametric404FallbackAndOriginalCacheIdentity() async throws {
        let loader = ScriptedAutoEQLoader()
        loader.append(status: 404, text: "missing")
        loader.append(status: 200, text: presetText)
        let repository = repository(loader)
        let candidate = candidate()
        let result = try await repository.resolveCandidateText(candidate, offlineIndex: [], checkValidity: {})
        let readme = "results/source/over-ear/Maker Model/README.md"
        XCTAssertEqual(result.resolvedPath, readme)
        XCTAssertEqual(loader.requests.count, 2)
        let imported = try repository.prepareImport(
            result.text,
            candidate: candidate,
            resolvedPath: result.resolvedPath
        )
        XCTAssertEqual(imported.name, "Maker Model")
        XCTAssertEqual(imported.source, "source")
        XCTAssertNil(imported.target)
        repository.cacheImport(imported, for: candidate.path)
        repository.rememberDownloadedText(result)
        XCTAssertEqual(repository.cachedImport(for: candidate.path)?.path, readme)
        XCTAssertNil(repository.cachedImport(for: readme))
        let cached = try await repository.resolveCandidateText(
            self.candidate(path: readme, parametric: false),
            offlineIndex: [],
            checkValidity: {}
        )
        XCTAssertEqual(cached.origin, .memory)
        XCTAssertEqual(cached.text, presetText)
        XCTAssertEqual(loader.requests.count, 2)
    }

    func testResolverDoesNotCacheUnacceptedOrMalformedText() async throws {
        let loader = ScriptedAutoEQLoader()
        loader.append(status: 200, text: "invalid preset")
        loader.append(status: 200, text: presetText)
        let repository = repository(loader)
        let candidate = candidate()
        let malformed = try await repository.resolveCandidateText(candidate, offlineIndex: [], checkValidity: {})
        XCTAssertThrowsError(try repository.prepareImport(
            malformed.text,
            candidate: candidate,
            resolvedPath: malformed.resolvedPath
        ))
        XCTAssertNil(repository.cachedImport(for: candidate.path))
        let valid = try await repository.resolveCandidateText(candidate, offlineIndex: [], checkValidity: {})
        XCTAssertEqual(loader.requests.count, 2)
        repository.rememberDownloadedText(valid)
        let cached = try await repository.resolveCandidateText(candidate, offlineIndex: [], checkValidity: {})
        XCTAssertEqual(cached.origin, .memory)
        XCTAssertEqual(loader.requests.count, 2)
    }

    func testInvalidPathsAndNonParametric404NeverStartFallback() async {
        let loader = ScriptedAutoEQLoader()
        let repository = repository(loader)
        for path in ["/private/preset", "../preset", "%2E%2E/preset", "%2Fprivate/preset"] {
            let error = await failure {
                try await repository.resolveCandidateText(candidate(path: path), offlineIndex: [], checkValidity: {})
            }
            XCTAssertEqual(error as? AutoEQImportError, .invalidSource)
        }
        XCTAssertTrue(loader.requests.isEmpty)
        loader.append(status: 404, text: "missing")
        let error = await failure {
            try await repository.resolveCandidateText(candidate(parametric: false), offlineIndex: [], checkValidity: {})
        }
        XCTAssertEqual(error as? AutoEQImportError, .invalidSource)
        XCTAssertEqual(loader.requests.count, 1)
    }

    func testInvalidResponseEncodingOrStatusNeverStartsFallback() async {
        let loader = ScriptedAutoEQLoader()
        let repository = repository(loader)
        for (status, data) in [(200, Data([0xFF])), (201, Data(presetText.utf8)), (500, Data())] {
            loader.append(status: status, data: data)
            let error = await failure {
                try await repository.resolveCandidateText(candidate(), offlineIndex: [], checkValidity: {})
            }
            XCTAssertEqual(error as? AutoEQImportError, .invalidSource)
        }
        XCTAssertEqual(loader.requests.count, 3)
    }

    func testStaleCheckpointStopsBefore404Fallback() async {
        let loader = ScriptedAutoEQLoader()
        loader.append(status: 404, text: "missing")
        let repository = repository(loader)
        let error = await failure {
            try await repository.resolveCandidateText(candidate(), offlineIndex: [], checkValidity: {
                throw CancellationError()
            })
        }
        XCTAssertTrue(error is CancellationError)
        XCTAssertEqual(loader.requests.count, 1)
        XCTAssertNil(repository.cachedImport(for: candidate().path))
    }

    func testCancelledCandidateDoesNotStartFallback() async {
        let loader = ScriptedAutoEQLoader()
        loader.append(status: 404, text: "missing")
        let repository = repository(loader)
        let candidate = candidate()
        let task = Task { try await repository.resolveCandidateText(candidate, offlineIndex: [], checkValidity: {}) }
        task.cancel()
        let error = await failure { try await task.value }
        XCTAssertTrue(error is CancellationError)
        XCTAssertEqual(loader.requests.count, 1)
    }
}

@MainActor
private final class ScriptedAutoEQLoader {
    let url = URL(fileURLWithPath: "/unused")
    var requests: [URL] = []
    var responses: [Result<(Data, URLResponse), Error>] = []

    func append(status: Int, text: String) {
        append(status: status, data: Data(text.utf8))
    }

    func append(status: Int, data: Data) {
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil) else {
            XCTFail("Invalid HTTP fixture")
            return
        }
        responses.append(.success((data, response)))
    }

    func load(_ url: URL) async throws -> (Data, URLResponse) {
        requests.append(url)
        guard !responses.isEmpty else { throw URLError(.badServerResponse) }
        return try responses.removeFirst().get()
    }
}

nonisolated private class BlockedAutoEQNetwork: URLProtocol, @unchecked Sendable {
    override class func canInit(with _: URLRequest) -> Bool {
        true
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }
    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() {}
}
