import Darwin
@testable import SystemEQ_for_Mac
import XCTest

@MainActor
final class ProjectMHelperClientTests: XCTestCase {
    func testWindowRequestWaitsForCurrentAcknowledgmentAndReplaysAfterConnection() async throws {
        let queue = DispatchQueue(label: "ProjectMHelperClientTests.window-show")
        let client = ProjectMHelperClient(ipcQueue: queue)
        client.showWindow()
        await withCheckedContinuation { continuation in queue.async { continuation.resume() } }
        XCTAssertEqual(client.pendingWindowShow, 1)
        var sockets: [Int32] = [-1, -1]
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &sockets), 0)
        var noSigPipe: Int32 = 1
        for socket in sockets {
            XCTAssertEqual(
                setsockopt(socket, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size)),
                0
            )
        }
        let generation = client.installSocket(sockets[0])
        defer { client.disconnectSocket(); close(sockets[1]) }
        client.replayWindowShowIfNeeded()
        await withCheckedContinuation { continuation in queue.async { continuation.resume() } }
        var buffer = [UInt8](repeating: 0, count: 128)
        let first = recv(sockets[1], &buffer, buffer.count, MSG_DONTWAIT)
        XCTAssertEqual(first, 7)
        XCTAssertEqual(Data(buffer.prefix(max(first, 0))), Data("SHOW:1\n".utf8))
        client.showWindow()
        await withCheckedContinuation { continuation in queue.async { continuation.resume() } }
        let second = recv(sockets[1], &buffer, buffer.count, MSG_DONTWAIT)
        XCTAssertEqual(second, 7)
        XCTAssertEqual(Data(buffer.prefix(max(second, 0))), Data("SHOW:2\n".utf8))
        client.startReadingResponses(socket: sockets[0], generation: generation)
        let old = Data("SHOWN:1\n".utf8)
        XCTAssertEqual(old.withUnsafeBytes { write(sockets[1], $0.baseAddress, $0.count) }, old.count)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(client.pendingWindowShow, 2)
        let current = Data("SHOWN:2\n".utf8)
        XCTAssertEqual(current.withUnsafeBytes { write(sockets[1], $0.baseAddress, $0.count) }, current.count)
        let deadline = Date().addingTimeInterval(1)
        while client.pendingWindowShow != nil, Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertNil(client.pendingWindowShow)
        client.showWindow()
        client.stop()
        XCTAssertNil(client.pendingWindowShow)
    }

    private final class ClientHolder: @unchecked Sendable {
        nonisolated(unsafe) var client: ProjectMHelperClient?

        init(_ client: ProjectMHelperClient) {
            self.client = client
        }
    }

    func testStopInterruptsBlockedAudioSend() async throws {
        var sockets: [Int32] = [-1, -1]
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &sockets), 0)
        let queue = DispatchQueue(label: "ProjectMHelperClientTests.blocked-send")
        let client = ProjectMHelperClient(ipcQueue: queue)
        client.installSocket(sockets[0])
        var sendSize: Int32 = 1024
        var noSigPipe: Int32 = 1
        setsockopt(sockets[0], SOL_SOCKET, SO_SNDBUF, &sendSize, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(sockets[0], SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        defer {
            client.disconnectSocket()
            client.stopAudioSending()
            close(sockets[1])
        }
        client.connectToAudioEngine()
        let callback = try XCTUnwrap(CoreAudioEngine.shared.visualizerCallback)
        let left = [Float](repeating: 0.25, count: 1024)
        let right = [Float](repeating: -0.25, count: 1024)
        left.withUnsafeBufferPointer { l in
            right.withUnsafeBufferPointer { r in
                guard let left = l.baseAddress, let right = r.baseAddress else { return }
                for _ in 0..<4 {
                    callback(left, right, 1024)
                }
            }
        }
        client.startAudioSending()
        var byte: UInt8 = 0
        var received = 0
        for _ in 0..<100 {
            received = recv(sockets[1], &byte, 1, MSG_PEEK | MSG_DONTWAIT)
            if received > 0 { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertGreaterThan(received, 0)
        let drained = expectation(description: "Blocked sender queue drained")
        let idle = DispatchSemaphore(value: 0)
        queue.async {
            idle.signal()
            drained.fulfill()
        }
        XCTAssertEqual(idle.wait(timeout: .now() + .milliseconds(50)), .timedOut)
        client.stop()
        await fulfillment(of: [drained], timeout: 3)
        XCTAssertNil(client.socketLease())
    }

    func testAudioCallbackZeroOneAndFullRingPreserveStereoSamples() throws {
        var sockets: [Int32] = [-1, -1]
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &sockets), 0)
        let client = ProjectMHelperClient()
        client.installSocket(sockets[0])
        defer {
            client.stop()
            close(sockets[1])
        }
        client.connectToAudioEngine()
        let callback = try XCTUnwrap(CoreAudioEngine.shared.visualizerCallback)
        let left = [Float](repeating: 0.25, count: 1024)
        let right = [Float](repeating: -0.25, count: 1024)
        left.withUnsafeBufferPointer { l in
            right.withUnsafeBufferPointer { r in
                guard let left = l.baseAddress, let right = r.baseAddress else { return }
                callback(left, right, 0)
                callback(left, right, 1)
                for _ in 0..<4 {
                    callback(left, right, 1024)
                }
            }
        }
        client.startAudioSending()
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(sockets[1], SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var packetSizes: [Int] = []
        for expectedCount in [4096, 2050] {
            var header = [UInt8](repeating: 0, count: 5)
            XCTAssertEqual(recv(sockets[1], &header, 5, MSG_WAITALL), 5)
            XCTAssertEqual(header[0], 0)
            let byteCount = header.dropFirst().enumerated()
                .reduce(UInt32(0)) { $0 | UInt32($1.element) << ($1.offset * 8) }
            XCTAssertEqual(byteCount, UInt32(expectedCount * MemoryLayout<Float>.size))
            var samples = [Float](repeating: 0, count: expectedCount)
            let read = samples.withUnsafeMutableBytes { recv(sockets[1], $0.baseAddress, $0.count, MSG_WAITALL) }
            XCTAssertEqual(read, Int(byteCount))
            for (index, sample) in samples.enumerated() {
                XCTAssertEqual(sample, index.isMultiple(of: 2) ? 0.25 : -0.25)
            }
            packetSizes.append(samples.count)
        }
        XCTAssertEqual(packetSizes, [4096, 2050])
    }

    func testBackgroundReleaseCleansMainThreadResources() async throws {
        let holder = ClientHolder(ProjectMHelperClient())
        holder.client?.connectToAudioEngine()
        holder.client?.startStatusPolling()
        let timer = try XCTUnwrap(holder.client?.statusUpdateTimer)
        let released = expectation(description: "Background owner released")
        DispatchQueue.global().async {
            holder.client = nil
            released.fulfill()
        }
        await fulfillment(of: [released], timeout: 2)
        XCTAssertFalse(timer.isValid)
        XCTAssertNil(CoreAudioEngine.shared.visualizerCallback)
    }

    func testDeinitializationTerminatesOwnedHelperAndClearsOutputHandler() async throws {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["30"]
        process.standardOutput = output
        try process.run()
        defer { if process.isRunning { process.terminate() } }
        autoreleasepool {
            let client = ProjectMHelperClient()
            client.monitorHelperProcess(process, output: output)
            XCTAssertNotNil(output.fileHandleForReading.readabilityHandler)
        }
        XCTAssertNil(output.fileHandleForReading.readabilityHandler)
        let exited = expectation(description: "Owned helper terminated")
        DispatchQueue.global().async {
            process.waitUntilExit()
            exited.fulfill()
        }
        await fulfillment(of: [exited], timeout: 5)
        XCTAssertEqual(process.terminationReason, .uncaughtSignal)
    }

    func testHelperExitCleansSocketPollingAndAudioCallback() async throws {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["0.2"]
        process.standardOutput = output
        try process.run()
        let client = ProjectMHelperClient()
        client.monitorHelperProcess(process, output: output)
        client.connectToAudioEngine()
        client.startStatusPolling()
        let timer = try XCTUnwrap(client.statusUpdateTimer)
        var sockets: [Int32] = [-1, -1]
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &sockets), 0)
        let generation = client.installSocket(sockets[0])
        client.startReadingResponses(socket: sockets[0], generation: generation)
        client.startAudioSending()
        defer {
            client.stop()
            close(sockets[1])
            if process.isRunning { process.terminate() }
        }
        for _ in 0..<200 {
            if !client.isRunning { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertFalse(client.isRunning)
        XCTAssertFalse(timer.isValid)
        XCTAssertNil(client.socketLease())
        XCTAssertNil(CoreAudioEngine.shared.visualizerCallback)
        XCTAssertNil(output.fileHandleForReading.readabilityHandler)
    }

    func testDeinitializationDisconnectsOwnedCallback() {
        let engine = CoreAudioEngine.shared
        autoreleasepool {
            let client = ProjectMHelperClient()
            client.connectToAudioEngine()
            XCTAssertNotNil(engine.visualizerCallback)
        }
        XCTAssertNil(engine.visualizerCallback)
    }

    func testOldClientCannotDisconnectReplacementCallback() {
        let engine = CoreAudioEngine.shared
        let replacement = ProjectMHelperClient()
        autoreleasepool {
            let original = ProjectMHelperClient()
            original.connectToAudioEngine()
            replacement.connectToAudioEngine()
            original.stop()
        }
        XCTAssertNotNil(engine.visualizerCallback)
        replacement.stop()
        XCTAssertNil(engine.visualizerCallback)
    }

    func testStopCleansResourcesBeforeHelperLaunch() throws {
        var sockets: [Int32] = [-1, -1]
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &sockets), 0)
        let client = ProjectMHelperClient()
        let generation = client.installSocket(sockets[0])
        client.startReadingResponses(socket: sockets[0], generation: generation)
        client.startStatusPolling()
        let firstTimer = try XCTUnwrap(client.statusUpdateTimer)
        client.startStatusPolling()
        XCTAssertFalse(firstTimer.isValid)
        let timer = try XCTUnwrap(client.statusUpdateTimer)
        client.startAudioSending()
        client.stop()
        client.stop()
        XCTAssertFalse(timer.isValid)
        XCTAssertNil(client.socketLease())
        defer { close(sockets[1]) }
        var byte: UInt8 = 0
        XCTAssertEqual(recv(sockets[1], &byte, 1, MSG_DONTWAIT), 0)
    }

    func testDeinitializationInvalidatesPollingAndDisconnectsSocket() throws {
        var sockets: [Int32] = [-1, -1]
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &sockets), 0)
        var timer: Timer?
        autoreleasepool {
            let client = ProjectMHelperClient()
            let generation = client.installSocket(sockets[0])
            client.startReadingResponses(socket: sockets[0], generation: generation)
            client.startStatusPolling()
            client.startAudioSending()
            timer = client.statusUpdateTimer
        }
        XCTAssertFalse(try XCTUnwrap(timer).isValid)
        defer { close(sockets[1]) }
        var byte: UInt8 = 0
        XCTAssertEqual(recv(sockets[1], &byte, 1, MSG_DONTWAIT), 0)
    }

    func testActiveAudioCallbackSurvivesClientDeinitialization() async throws {
        let engine = CoreAudioEngine.shared
        let entered = DispatchSemaphore(value: 0)
        let resume = DispatchSemaphore(value: 0)
        let rendered = expectation(description: "In-flight callback completed")
        var client: ProjectMHelperClient? = ProjectMHelperClient()
        weak var released = client
        client?.connectToAudioEngine()
        let callback = try XCTUnwrap(engine.visualizerCallback)
        engine.visualizerCallback = { left, right, count in
            entered.signal()
            _ = resume.wait(timeout: .now() + 3)
            callback(left, right, count)
        }
        defer {
            engine.visualizerCallback = nil
            resume.signal()
        }
        DispatchQueue.global().async {
            var left = [Float](repeating: 0.25, count: 1024)
            var right = [Float](repeating: -0.25, count: 1024)
            left.withUnsafeMutableBufferPointer { l in
                right.withUnsafeMutableBufferPointer { r in
                    guard let left = l.baseAddress, let right = r.baseAddress else { return }
                    engine.processStereoInPlace(left: left, right: right, frameCount: 1024)
                }
            }
            rendered.fulfill()
        }
        XCTAssertEqual(entered.wait(timeout: .now() + 2), .success)
        engine.visualizerCallback = nil
        client = nil
        XCTAssertNil(released)
        resume.signal()
        await fulfillment(of: [rendered], timeout: 5)
    }

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
