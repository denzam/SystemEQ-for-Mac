import Darwin
@testable import SystemEQ_for_Mac
import XCTest

@MainActor
final class ProjectMHelperClientTests: XCTestCase {
    func testLargeFragmentedResponseRetainsIncompleteTail() {
        let accumulator = ProjectMHelperClient.ResponseBuffer()
        let line = "LIST:" + String(repeating: "Пресет🎵;", count: 80000)
        let payload = Data((line + "\nREADY\nTAIL").utf8)
        var lines: [String] = []
        for offset in stride(from: 0, to: payload.count, by: 65531) {
            accumulator.data.append(payload[offset..<min(offset + 65531, payload.count)])
            while let data = accumulator.nextLine() {
                lines.append(String(decoding: data, as: UTF8.self))
            }
        }
        XCTAssertEqual(lines, [line, "READY"])
        XCTAssertEqual(String(decoding: accumulator.data, as: UTF8.self), "TAIL")
        accumulator.data.append(Data("END\n".utf8))
        XCTAssertEqual(accumulator.nextLine(), Data("TAILEND".utf8))
        XCTAssertTrue(accumulator.data.isEmpty)
    }

    func testSocketLeaseSurvivesDisconnectAndStaleGenerationIsRejected() throws {
        var sockets: [Int32] = [-1, -1]
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &sockets), 0)
        let client = ProjectMHelperClient()
        defer { close(sockets[1]) }
        let generation = client.installSocket(sockets[0])
        let lease = try XCTUnwrap(client.socketLease())
        defer { close(lease.socket) }
        XCTAssertTrue(client.socketIsCurrent(sockets[0], generation: generation))
        XCTAssertEqual(client.invalidateSocket(), sockets[0])
        close(sockets[0])
        XCTAssertNil(client.socketLease())
        XCTAssertFalse(client.socketIsCurrent(sockets[0], generation: generation))
        let payload = Data("LOCK:1\n".utf8)
        XCTAssertTrue(payload.withUnsafeBytes {
            guard let baseAddress = $0.baseAddress else { return false }
            return ProjectMHelperClient.writeAll(socket: lease.socket, baseAddress: baseAddress, count: $0.count)
        })
        var received = [UInt8](repeating: 0, count: payload.count)
        XCTAssertEqual(read(sockets[1], &received, received.count), payload.count)
        XCTAssertEqual(Data(received), payload)
        var replacement: [Int32] = [-1, -1]
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &replacement), 0)
        let replacementGeneration = client.installSocket(replacement[0])
        XCTAssertNotEqual(replacementGeneration, generation)
        XCTAssertTrue(client.socketIsCurrent(replacement[0], generation: replacementGeneration))
        XCTAssertFalse(client.socketIsCurrent(replacement[0], generation: generation))
        close(client.invalidateSocket())
        close(replacement[1])
    }

    func testStartupCommandsReplayNonDefaultIntent() {
        XCTAssertEqual(
            ProjectMHelperClient.startupCommands(
                category: "Fractals",
                weight: "Heavy",
                quality: "Low",
                shuffle: false,
                locked: true
            ),
            ["CATEGORY:Fractals", "WEIGHT:Heavy", "QUALITY:Low", "SHUFFLE:0", "LOCK:1"]
        )
    }

    func testStartupCommandsOmitHelperDefaults() {
        XCTAssertTrue(
            ProjectMHelperClient.startupCommands(
                category: "All",
                weight: "All",
                quality: "High",
                shuffle: true,
                locked: false
            ).isEmpty
        )
    }

    func testReportedSelectionReplacesSynchronizedIntent() {
        XCTAssertTrue(ProjectMHelperClient.shouldAdoptReportedSelection(selected: "Heavy", current: "Heavy"))
    }

    func testReportedSelectionDoesNotReplacePendingIntent() {
        XCTAssertFalse(ProjectMHelperClient.shouldAdoptReportedSelection(selected: "Heavy", current: "All"))
    }
}
