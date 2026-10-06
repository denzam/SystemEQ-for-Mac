import AppKit
import Darwin
import Foundation

struct PresetInfo {
    let name: String
    let category: String
}

final class VisualizerController {
    enum VisualQuality: String { case low = "Low", medium = "Medium", high = "High" }
    func nextPreset() {}
    func previousPreset() {}
    func randomPreset() {}
    func selectPreset(at _: Int) {}
    func setShuffle(_: Bool) {}
    func setPresetLocked(_: Bool) {}
    func resize(width _: Int, height _: Int) {}
    func setCategory(_: String) {}
    func setWeight(_: String) {}
    func setQuality(_: VisualQuality) {}
    func getStatus() -> [String: Any] {
        [:]
    }
    func getCategories() -> [String] {
        []
    }
    func getPresetSnapshot() -> [PresetInfo] {
        []
    }
    func addAudioSamples(_: UnsafePointer<Float>, count _: Int) {}
}

@main
struct IPCServerTests {
    struct Failure: LocalizedError {
        let errorDescription: String?
    }

    final class Received {
        var data = Data()
    }

    static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw Failure(errorDescription: message) }
    }

    static func pair() throws -> [Int32] {
        var sockets: [Int32] = [-1, -1]
        try require(socketpair(AF_UNIX, SOCK_STREAM, 0, &sockets) == 0, "socketpair failed")
        for socket in sockets {
            var value: Int32 = 1
            setsockopt(socket, SOL_SOCKET, SO_NOSIGPIPE, &value, socklen_t(MemoryLayout<Int32>.size))
            value = 1024
            setsockopt(socket, SOL_SOCKET, SO_SNDBUF, &value, socklen_t(MemoryLayout<Int32>.size))
        }
        return sockets
    }

    static func testDescriptorReuse() throws {
        for _ in 0..<32 {
            let original = try pair()
            let replacement = try pair()
            let server = IPCServer(controller: VisualizerController())
            let generation = server.replaceClient(with: original[0])
            var replacementGeneration: UInt64 = 0
            var replacementInstalled = false
            var duplicateResult: Int32 = -1
            var written = -1
            defer {
                server.finishClient(
                    socket: original[0], generation: replacementInstalled ? replacementGeneration : generation
                )
                close(original[1])
                close(replacement[0])
                close(replacement[1])
            }
            let leased = server.withClientLease(socket: original[0], generation: generation) { lease in
                server.finishClient(socket: original[0], generation: generation)
                duplicateResult = dup2(replacement[0], original[0])
                replacementGeneration = server.replaceClient(with: original[0])
                replacementInstalled = true
                written = Data("STATUS:old\n".utf8).withUnsafeBytes { write(lease, $0.baseAddress, $0.count) }
            }
            try require(leased && duplicateResult == original[0], "Could not force descriptor reuse")
            try require(written == 11, "Leased writer did not retain the original connection")
            var buffer = [UInt8](repeating: 0, count: 32)
            let oldRead = recv(original[1], &buffer, buffer.count, MSG_DONTWAIT)
            try require(
                oldRead == 11 && Data(buffer.prefix(11)) == Data("STATUS:old\n".utf8),
                "Wrong old connection response"
            )
            let replacementRead = recv(replacement[1], &buffer, buffer.count, MSG_DONTWAIT)
            try require(
                replacementRead == -1 && (errno == EAGAIN || errno == EWOULDBLOCK),
                "Replacement received stale response"
            )
            try require(
                !server.withClientLease(socket: original[0], generation: generation) { _ in },
                "Stale generation accepted"
            )
        }
    }

    static func testLargePartialResponse() throws {
        let sockets = try pair()
        let server = IPCServer(controller: VisualizerController())
        let generation = server.replaceClient(with: sockets[0])
        defer {
            server.finishClient(socket: sockets[0], generation: generation)
            close(sockets[1])
        }
        let message = "LIST:" + String(repeating: "Пресет🎵;", count: 80000)
        let expected = Data((message + "\n").utf8)
        let received = Received()
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            var buffer = [UInt8](repeating: 0, count: 8192)
            while received.data.count < expected.count {
                let count = read(sockets[1], &buffer, buffer.count)
                guard count > 0 else { break }
                received.data.append(contentsOf: buffer.prefix(count))
            }
            done.signal()
        }
        server.writeResponse(message, socket: sockets[0], generation: generation)
        try require(done.wait(timeout: .now() + 5) == .success, "Large response reader stalled")
        try require(received.data == expected, "Partial write truncated the response")
    }

    static func testStopUnblocksWriter() throws {
        let sockets = try pair()
        let server = IPCServer(controller: VisualizerController())
        let generation = server.replaceClient(with: sockets[0])
        defer {
            server.finishClient(socket: sockets[0], generation: generation)
            close(sockets[1])
        }
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            server.writeResponse(String(repeating: "x", count: 1024 * 1024), socket: sockets[0], generation: generation)
            done.signal()
        }
        try require(done.wait(timeout: .now() + .milliseconds(50)) == .timedOut, "Expected blocked writer")
        server.stop()
        try require(done.wait(timeout: .now() + 2) == .success, "stop did not unblock writer")
    }

    static func testShowWindowRequests() throws {
        let original = try pair()
        let replacement = try pair()
        var shows = 0
        var onMainThread = true
        let server = IPCServer(controller: VisualizerController(), showWindow: {
            shows += 1
            onMainThread = onMainThread && Thread.isMainThread
        })
        let oldGeneration = server.replaceClient(with: original[0])
        var generation = oldGeneration
        defer {
            server.finishClient(socket: original[0], generation: oldGeneration)
            server.finishClient(socket: replacement[0], generation: generation)
            close(original[1])
            close(replacement[1])
        }
        for command in ["SHOW", "SHOW:", "SHOW:invalid", "SHOW:-1", "SHOW:18446744073709551616"] {
            server.processMessage(command, socket: original[0], generation: oldGeneration)
        }
        let drained = DispatchSemaphore(value: 0)
        DispatchQueue.main.async { drained.signal() }
        let parserDeadline = Date().addingTimeInterval(2)
        var parserDrained = false
        while Date() < parserDeadline {
            if drained.wait(timeout: .now()) == .success { parserDrained = true; break }
            _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        try require(parserDrained && shows == 0, "Current client accepted malformed SHOW")
        server.processMessage("SHOW:1", socket: original[0], generation: oldGeneration)
        generation = server.replaceClient(with: replacement[0])
        server.processMessage("SHOW:2", socket: replacement[0], generation: generation)
        server.processMessage("SHOW:3", socket: replacement[0], generation: generation)
        let deadline = Date().addingTimeInterval(2)
        while shows < 2, Date() < deadline {
            _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        try require(shows == 2 && onMainThread, "SHOW accepted invalid/stale requests or used wrong thread")
        var response = Data()
        var buffer = [UInt8](repeating: 0, count: 128)
        while response.count < 16, Date() < deadline {
            let count = recv(replacement[1], &buffer, buffer.count, MSG_DONTWAIT)
            if count > 0 { response.append(contentsOf: buffer.prefix(count)) }
            else { usleep(1000) }
        }
        try require(response == Data("SHOWN:2\nSHOWN:3\n".utf8), "SHOW acknowledgments missing or wrong")
        server.processMessage("SHOW:4", socket: replacement[0], generation: generation)
        server.stop()
        _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        try require(shows == 2, "Stopped helper accepted a queued SHOW")
    }

    static func main() {
        do {
            try testDescriptorReuse()
            try testLargePartialResponse()
            try testStopUnblocksWriter()
            try testShowWindowRequests()
            try FileHandle.standardOutput.write(contentsOf: Data("IPC server: 4 tests passed\n".utf8))
        } catch {
            try? FileHandle.standardError.write(contentsOf: Data("\(error.localizedDescription)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }
}
