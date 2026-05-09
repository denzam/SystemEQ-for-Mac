//
//  IPCServer.swift
//  ProjectMHelper
//
//  Unix domain socket server for IPC communication with main SystemEQ app.
//  Handles commands (next/prev preset, settings) and receives audio data.
//

import AppKit
import Foundation

// MARK: - IPC Protocol

enum IPCCommand: String {
    case nextPreset = "NEXT"
    case previousPreset = "PREV"
    case randomPreset = "RAND"
    case selectPreset = "SELECT" // SELECT:index
    case setShuffle = "SHUFFLE" // SHUFFLE:0 or SHUFFLE:1
    case setLocked = "LOCK" // LOCK:0 or LOCK:1
    case getStatus = "STATUS"
    case resize = "RESIZE" // RESIZE:width:height
    case setCategory = "CATEGORY" // CATEGORY:name
    case setWeight = "WEIGHT" // WEIGHT:Light|Medium|Heavy|All
    case getCategories = "CATEGORIES"
    case quit = "QUIT"
}

// MARK: - IPC Server

class IPCServer {
    private let socketPath: String
    private var serverSocket: Int32 = -1
    private var clientSocket: Int32 = -1
    private var isRunning = false
    private let controller: VisualizerController

    private let listenQueue = DispatchQueue(label: "com.systemeq.projectm.ipc.listen", qos: .userInitiated)
    private let readQueue = DispatchQueue(label: "com.systemeq.projectm.ipc.read", qos: .userInitiated)

    init(controller: VisualizerController) {
        self.controller = controller
        self.socketPath = "/tmp/systemeq_projectm_\(getpid()).sock"
    }

    deinit {
        stop()
    }

    func start() {
        // Remove existing socket file
        unlink(socketPath)

        // Create socket
        serverSocket = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverSocket >= 0 else {
            print("[IPCServer] Failed to create socket: \(errno)")
            return
        }

        // Bind to path
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        // Prepare a CChar array for the socket path
        let maxPathLength = MemoryLayout.size(ofValue: addr.sun_path)
        socketPath.withCString { sourcePtr in
            withUnsafeMutablePointer(to: &addr.sun_path) { sunPathPtr in
                let rawPtr = UnsafeMutableRawPointer(sunPathPtr).assumingMemoryBound(to: CChar.self)
                strncpy(rawPtr, sourcePtr, maxPathLength - 1)
                rawPtr[maxPathLength - 1] = 0
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                bind(serverSocket, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard bindResult == 0 else {
            print("[IPCServer] Failed to bind: \(errno)")
            close(serverSocket)
            return
        }

        // Listen
        guard listen(serverSocket, 1) == 0 else {
            print("[IPCServer] Failed to listen: \(errno)")
            close(serverSocket)
            return
        }

        isRunning = true
        print("[IPCServer] Listening on \(socketPath)")

        // Print socket path to stdout for parent process
        print("SOCKET:\(socketPath)")
        fflush(stdout)

        // Accept connections in background
        listenQueue.async { [weak self] in
            self?.acceptLoop()
        }
    }

    func stop() {
        isRunning = false

        if clientSocket >= 0 {
            close(clientSocket)
            clientSocket = -1
        }

        if serverSocket >= 0 {
            close(serverSocket)
            serverSocket = -1
        }

        unlink(socketPath)
    }

    private func acceptLoop() {
        while isRunning {
            var clientAddr = sockaddr_un()
            var clientAddrLen = socklen_t(MemoryLayout<sockaddr_un>.size)

            let newClient = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                    accept(serverSocket, sockaddrPtr, &clientAddrLen)
                }
            }

            guard newClient >= 0 else {
                if isRunning {
                    print("[IPCServer] Accept failed: \(errno)")
                }
                continue
            }

            // Close previous client if any
            if clientSocket >= 0 {
                close(clientSocket)
            }

            clientSocket = newClient
            print("[IPCServer] Client connected")

            // Handle client in read queue
            readQueue.async { [weak self] in
                self?.readLoop()
            }
        }
    }

    private func readLoop() {
        var buffer = [UInt8](repeating: 0, count: 65536)
        var messageBuffer = Data()

        while isRunning, clientSocket >= 0 {
            let bytesRead = read(clientSocket, &buffer, buffer.count)

            if bytesRead <= 0 {
                print("[IPCServer] Client disconnected")
                close(clientSocket)
                clientSocket = -1
                break
            }

            messageBuffer.append(contentsOf: buffer[0..<bytesRead])

            // Guard against unbounded buffer growth (e.g. malicious client without newlines)
            if messageBuffer.count > 4 * 1024 * 1024 {
                print("[IPCServer] Message buffer too large, dropping connection")
                close(clientSocket)
                clientSocket = -1
                break
            }

            // Frame parser: stream is a mix of text commands (UTF-8 terminated by \n)
            // and binary audio frames ([0x00][UInt32 LE length][length bytes of Float samples]).
            // Byte 0x00 never appears in UTF-8 text, so we can disambiguate at the start of every frame.
            parseFrames(&messageBuffer)
        }
    }

    private func parseFrames(_ messageBuffer: inout Data) {
        while !messageBuffer.isEmpty {
            let firstByte = messageBuffer[messageBuffer.startIndex]

            if firstByte == 0x00 {
                // Binary audio frame — need 5 byte header at minimum
                guard messageBuffer.count >= 5 else { return }

                let lengthBytes = messageBuffer[messageBuffer.startIndex + 1..<messageBuffer.startIndex + 5]
                let payloadLength = lengthBytes.withUnsafeBytes { raw -> Int in
                    let le = raw.loadUnaligned(as: UInt32.self).littleEndian
                    return Int(le)
                }

                // Sanity: max 4096 floats * 4 bytes = 16384
                guard payloadLength <= 16384, payloadLength % MemoryLayout<Float>.size == 0 else {
                    print("[IPCServer] Invalid audio frame length: \(payloadLength) — dropping connection")
                    close(clientSocket)
                    clientSocket = -1
                    return
                }

                let totalFrameSize = 5 + payloadLength
                guard messageBuffer.count >= totalFrameSize else { return } // wait for rest

                let payloadStart = messageBuffer.startIndex + 5
                let payloadEnd = payloadStart + payloadLength
                let floatCount = payloadLength / MemoryLayout<Float>.size

                messageBuffer[payloadStart..<payloadEnd].withUnsafeBytes { raw in
                    if let floatPtr = raw.baseAddress?.assumingMemoryBound(to: Float.self) {
                        controller.addAudioSamples(floatPtr, count: floatCount)
                    }
                }

                messageBuffer = Data(messageBuffer[payloadEnd...])
            } else {
                // Text command — find \n
                guard let newlineIndex = messageBuffer.firstIndex(of: 0x0A) else { return }
                let messageData = messageBuffer[messageBuffer.startIndex..<newlineIndex]
                messageBuffer = Data(messageBuffer[(newlineIndex + 1)...])

                if let message = String(data: messageData, encoding: .utf8) {
                    processMessage(message)
                }
            }
        }
    }

    private func processMessage(_ message: String) {
        let parts = message.split(separator: ":", maxSplits: 1)
        guard let commandStr = parts.first else { return }

        let argument = parts.count > 1 ? String(parts[1]) : nil

        switch commandStr {
        case "NEXT":
            DispatchQueue.main.async { [weak self] in
                self?.controller.nextPreset()
            }

        case "PREV":
            DispatchQueue.main.async { [weak self] in
                self?.controller.previousPreset()
            }

        case "RAND":
            DispatchQueue.main.async { [weak self] in
                self?.controller.randomPreset()
            }

        case "SELECT":
            if let arg = argument, let index = Int(arg) {
                DispatchQueue.main.async { [weak self] in
                    self?.controller.selectPreset(at: index)
                }
            }

        case "SHUFFLE":
            if let arg = argument {
                let enabled = arg == "1"
                DispatchQueue.main.async { [weak self] in
                    self?.controller.setShuffle(enabled)
                }
            }

        case "LOCK":
            if let arg = argument {
                let locked = arg == "1"
                DispatchQueue.main.async { [weak self] in
                    self?.controller.setPresetLocked(locked)
                }
            }

        case "RESIZE":
            if let arg = argument {
                let dims = arg.split(separator: ":")
                if dims.count == 2, let w = Int(dims[0]), let h = Int(dims[1]) {
                    DispatchQueue.main.async { [weak self] in
                        self?.controller.resize(width: w, height: h)
                    }
                }
            }

        case "STATUS":
            let status = controller.getStatus()
            if let jsonData = try? JSONSerialization.data(withJSONObject: status),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                sendResponse("STATUS:\(jsonString)")
            }

        case "CATEGORY":
            if let arg = argument {
                DispatchQueue.main.async { [weak self] in
                    self?.controller.setCategory(arg)
                }
            }

        case "WEIGHT":
            if let arg = argument {
                DispatchQueue.main.async { [weak self] in
                    self?.controller.setWeight(arg)
                }
            }

        case "CATEGORIES":
            let categories = controller.getCategories()
            if let jsonData = try? JSONSerialization.data(withJSONObject: categories),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                sendResponse("CATEGORIES:\(jsonString)")
            }

        case "QUIT":
            DispatchQueue.main.async {
                NSApplication.shared.terminate(nil)
            }

        default:
            print("[IPCServer] Unknown command: \(commandStr)")
        }
    }

    private func sendResponse(_ message: String) {
        guard clientSocket >= 0 else { return }

        let data = (message + "\n").data(using: .utf8)!
        _ = data.withUnsafeBytes { buffer in
            write(clientSocket, buffer.baseAddress, buffer.count)
        }
    }
}
