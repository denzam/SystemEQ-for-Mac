import Darwin
@testable import SystemEQ_for_Mac
import XCTest

@MainActor
final class ProjectMHelperClientTests: XCTestCase {
    func testCancelledSenderCanDeinitializeBeforeCancelHandlerRuns() async {
        let queue = DispatchQueue(label: "ProjectMHelperClientTests.cancel")
        let gate = DispatchSemaphore(value: 0)
        let blocked = DispatchSemaphore(value: 0)
        queue.async {
            blocked.signal()
            gate.wait()
        }
        XCTAssertEqual(blocked.wait(timeout: .now() + 2), .success)
        weak var released: ProjectMHelperClient?
        autoreleasepool {
            let client = ProjectMHelperClient(ipcQueue: queue)
            released = client
            client.startAudioSending()
            client.stopAudioSending()
        }
        XCTAssertNil(released)
        gate.signal()
        let drained = expectation(description: "Cancellation queue drained")
        queue.asyncAfter(deadline: .now() + .milliseconds(50)) { drained.fulfill() }
        await fulfillment(of: [drained], timeout: 2)
    }

    func testLargeFragmentedResponseRetainsIncompleteTail() {
        let accumulator = ProjectMHelperClient.ResponseBuffer()
        let line = "LIST:" + String(repeating: "Пресет🎵;", count: 80000)
        let payload = Data((line + "\nREADY\nTAIL").utf8)
        var lines: [Data] = []
        for offset in stride(from: 0, to: payload.count, by: 65531) {
            XCTAssertTrue(accumulator.append(Data(payload[offset..<min(offset + 65531, payload.count)])))
            while let data = accumulator.nextLine() {
                lines.append(data)
            }
        }
        XCTAssertEqual(lines, [Data(line.utf8), Data("READY".utf8)])
        XCTAssertEqual(accumulator.data, Data("TAIL".utf8))
        XCTAssertTrue(accumulator.append(Data("END\n".utf8)))
        XCTAssertEqual(accumulator.nextLine(), Data("TAILEND".utf8))
        XCTAssertTrue(accumulator.data.isEmpty)
    }

    func testResponseLimitAcceptsExactBoundaryAndRejectsOneExtraByte() {
        let accumulator = ProjectMHelperClient.ResponseBuffer(maximumBytes: 8)
        XCTAssertTrue(accumulator.append(Data("1234567".utf8)))
        XCTAssertTrue(accumulator.append(Data("\n".utf8)))
        XCTAssertEqual(accumulator.nextLine(), Data("1234567".utf8))
        XCTAssertTrue(accumulator.append(Data("12345678".utf8)))
        XCTAssertNil(accumulator.nextLine())
        XCTAssertFalse(accumulator.append(Data("9".utf8)))
        XCTAssertTrue(accumulator.data.isEmpty)
    }

    func testCompletedResponsesAreDrainedBeforeCheckingNextLineLimit() {
        let accumulator = ProjectMHelperClient.ResponseBuffer(maximumBytes: 8)
        var lines: [Data] = []
        XCTAssertTrue(accumulator.receive(Data("1234567\n1234567\nTAIL".utf8)) { lines.append($0) })
        XCTAssertEqual(lines, [Data("1234567".utf8), Data("1234567".utf8)])
        XCTAssertEqual(accumulator.data, Data("TAIL".utf8))
        XCTAssertFalse(accumulator.receive(Data("12345".utf8)) { lines.append($0) })
        XCTAssertTrue(accumulator.data.isEmpty)
        XCTAssertEqual(lines.count, 2)
    }

    func testOversizedUnterminatedResponseDisconnectsTheSocket() async throws {
        var sockets: [Int32] = [-1, -1]
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &sockets), 0)
        let client = ProjectMHelperClient()
        let generation = client.installSocket(sockets[0])
        client.startReadingResponses(socket: sockets[0], generation: generation)
        let peer = sockets[1]
        var noSigPipe: Int32 = 1
        setsockopt(peer, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        defer {
            client.disconnectSocket()
            close(peer)
        }
        let writer = dup(peer)
        XCTAssertGreaterThanOrEqual(writer, 0)
        guard writer >= 0 else { return }
        let written = expectation(description: "Oversized peer write finished")
        DispatchQueue.global().async {
            defer { close(writer) }
            let payload = Data(repeating: 0x78, count: 4 * 1024 * 1024 + 1)
            payload.withUnsafeBytes {
                guard let address = $0.baseAddress else { return }
                _ = ProjectMHelperClient.writeAll(socket: writer, baseAddress: address, count: $0.count)
            }
            written.fulfill()
        }
        await fulfillment(of: [written], timeout: 5)
        for _ in 0..<100 {
            guard let lease = client.socketLease() else { return }
            close(lease.socket)
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Oversized response did not disconnect")
    }

    func testRepeatedSenderRestartAndDeinitialization() async {
        let queue = DispatchQueue(label: "ProjectMHelperClientTests.restart")
        for _ in 0..<32 {
            autoreleasepool {
                let client = ProjectMHelperClient(ipcQueue: queue)
                client.startAudioSending()
                client.startAudioSending()
                client.stopAudioSending()
                client.stopAudioSending()
            }
        }
        let drained = expectation(description: "Restart cancellation queue drained")
        queue.asyncAfter(deadline: .now() + .milliseconds(50)) { drained.fulfill() }
        await fulfillment(of: [drained], timeout: 2)
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
