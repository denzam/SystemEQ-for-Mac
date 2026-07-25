//
//  ProjectMHelperClient.swift
//  SystemEQ for Mac
//
//  Client for communicating with ProjectMHelper subprocess.
//  Manages helper lifecycle and IPC communication.
//

import AppKit
import Combine
import Foundation

// MARK: - Preset Model

struct VizPreset: Identifiable, Equatable {
    let name: String
    let category: String
    let index: Int
    var id: Int {
        index
    }
}

// MARK: - ProjectM Helper Client

@MainActor
final class ProjectMHelperClient: ObservableObject {
    // MARK: - Singleton

    static let shared = ProjectMHelperClient()

    // MARK: - Published Properties

    @Published private(set) var isRunning = false
    @Published private(set) var currentPresetName: String = "None"
    @Published private(set) var presetCount: Int = 0
    @Published private(set) var availableCategories: [String] = ["All"]
    @Published private(set) var currentCategory: String = "All"
    @Published private(set) var currentWeight: String = "All"
    @Published private(set) var currentFPS: Int = 0
    @Published private(set) var presetList: [VizPreset] = []

    /// Обрані пресети візуалізатора (за назвою). Зберігаються між запусками.
    @Published var favoritePresets: Set<String> = Set(
        UserDefaults.standard.stringArray(forKey: "visualizerFavoritePresets") ?? []
    ) {
        didSet {
            UserDefaults.standard.set(Array(favoritePresets), forKey: "visualizerFavoritePresets")
        }
    }

    func toggleFavorite(_ name: String) {
        if favoritePresets.contains(name) {
            favoritePresets.remove(name)
        } else {
            favoritePresets.insert(name)
        }
    }

    func requestPresetList() {
        sendCommand("LIST")
    }

    @Published var isShuffleEnabled: Bool = true {
        didSet {
            sendCommand("SHUFFLE:\(isShuffleEnabled ? "1" : "0")")
        }
    }

    @Published var isPresetLocked: Bool = false {
        didSet {
            sendCommand("LOCK:\(isPresetLocked ? "1" : "0")")
        }
    }

    @Published var selectedCategory: String = "All" {
        didSet {
            guard selectedCategory != currentCategory else { return }
            sendCommand("CATEGORY:\(selectedCategory)")
        }
    }

    @Published var selectedWeight: String = "All" {
        didSet {
            guard selectedWeight != currentWeight else { return }
            sendCommand("WEIGHT:\(selectedWeight)")
        }
    }

    @Published var selectedQuality: String = UserDefaults.standard
        .string(forKey: "visualizerQuality") ?? "High" {
        didSet {
            guard selectedQuality != oldValue else { return }
            UserDefaults.standard.set(selectedQuality, forKey: "visualizerQuality")
            sendCommand("QUALITY:\(selectedQuality)")
        }
    }

    // MARK: - Private Properties

    private var helperProcess: Process?
    private var helperGeneration: UInt64 = 0
    private var socketPath: String?
    private var readSource: DispatchSourceRead?

    private final class ResponseBuffer {
        var data = Data()
    }

    private final class SocketPathBuffer {
        nonisolated(unsafe) var data = Data()
        nonisolated(unsafe) var foundPath = false
    }

    private let ipcQueue = DispatchQueue(label: "com.systemeq.projectm.ipc", qos: .userInitiated)
    /// Окрема черга для читання відповідей: інакше безперервний потік аудіо-фреймів на ipcQueue
    /// не дає read-handler'у слот, буфер сокета переповнюється і великий LIST (~1 МБ) губиться.
    private let readQueue = DispatchQueue(label: "com.systemeq.projectm.ipc.read", qos: .userInitiated)

    // Thread-safe socket access (nonisolated for background queue access)
    nonisolated(unsafe) private var _clientSocket: Int32 = -1
    nonisolated(unsafe) private var _socketGeneration: UInt64 = 0
    nonisolated private let socketLock = NSLock()

    nonisolated private func socketSnapshot() -> (socket: Int32, generation: UInt64) {
        socketLock.lock()
        defer { socketLock.unlock() }
        return (_clientSocket, _socketGeneration)
    }

    nonisolated private func socketLease() -> (socket: Int32, original: Int32, generation: UInt64)? {
        socketLock.lock()
        defer { socketLock.unlock() }
        guard _clientSocket >= 0 else { return nil }
        let leasedSocket = dup(_clientSocket)
        guard leasedSocket >= 0 else { return nil }
        return (leasedSocket, _clientSocket, _socketGeneration)
    }

    nonisolated private func installSocket(_ value: Int32) -> UInt64 {
        socketLock.lock()
        _socketGeneration &+= 1
        _clientSocket = value
        let generation = _socketGeneration
        socketLock.unlock()
        return generation
    }

    nonisolated private func socketIsCurrent(_ socket: Int32, generation: UInt64) -> Bool {
        socketLock.lock()
        defer { socketLock.unlock() }
        return _clientSocket == socket && _socketGeneration == generation
    }

    nonisolated private func invalidateSocket() -> Int32 {
        socketLock.lock()
        let socket = _clientSocket
        _clientSocket = -1
        _socketGeneration &+= 1
        socketLock.unlock()
        return socket
    }

    nonisolated private static func writeAll(
        socket: Int32,
        baseAddress: UnsafeRawPointer,
        count: Int
    ) -> Bool {
        var sent = 0
        while sent < count {
            let written = Darwin.write(socket, baseAddress.advanced(by: sent), count - sent)
            if written > 0 {
                sent += written
            } else if written < 0, errno == EINTR {
                continue
            } else {
                return false
            }
        }
        return true
    }

    nonisolated private func handleSocketWriteFailure(
        leasedSocket: Int32,
        originalSocket: Int32,
        generation: UInt64
    ) {
        shutdown(leasedSocket, SHUT_RDWR)
        Task { @MainActor [weak self] in
            guard let self,
                  self.socketIsCurrent(originalSocket, generation: generation) else { return }
            self.disconnectSocket()
        }
    }

    private var statusUpdateTimer: Timer?

    // Lock-free ring buffer for audio (written on real-time audio thread, read on ipcQueue)
    private let audioRingCapacity = 8192 // must be power of 2
    nonisolated(unsafe) private var _audioRingBuffer: UnsafeMutablePointer<Float>
    nonisolated(unsafe) private var _audioWriteIdx: SEQAtomicInt32 = seq_atomic_int32_make(0)
    nonisolated(unsafe) private var _audioReadIdx: SEQAtomicInt32 = seq_atomic_int32_make(0)
    private var audioSendTimer: DispatchSourceTimer?

    // Pre-allocated send buffer (only touched from ipcQueue inside audioSendTimer handler)
    private var _sendBuffer: UnsafeMutablePointer<UInt8>?
    private var _sendBufferCapacity: Int = 0

    private init() {
        _audioRingBuffer = UnsafeMutablePointer<Float>.allocate(capacity: 8192)
        _audioRingBuffer.initialize(repeating: 0, count: 8192)
    }

    // MARK: - Lifecycle

    func start(frame: NSRect) {
        guard !isRunning else { return }
        helperGeneration &+= 1
        let generation = helperGeneration

        // Find helper app in bundle
        guard let helperURL = findHelperApp() else {
            dlog("❌ ProjectMHelper not found in bundle", level: .error, category: .audio)
            return
        }

        // Launch helper process
        let process = Process()
        process.executableURL = helperURL
        process.arguments = [
            "--x", String(Int(frame.origin.x)),
            "--y", String(Int(frame.origin.y)),
            "--width", String(Int(frame.width)),
            "--height", String(Int(frame.height)),
            "--parent-pid", String(getpid())
        ]

        // Capture stdout to get socket path
        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
            helperProcess = process
            isRunning = true

            dlog("✅ ProjectMHelper launched (PID: \(process.processIdentifier))", category: .audio)

            // Monitor process termination (user closes window).
            process.terminationHandler = { [weak self] terminatedProcess in
                Task { @MainActor [weak self] in
                    guard let self,
                          self.helperGeneration == generation,
                          self.helperProcess === terminatedProcess else { return }
                    dlog("🛑 ProjectMHelper terminated by user", category: .audio)
                    self.cleanupAfterTermination()
                }
            }

            // Read socket path from helper's stdout
            readSocketPath(from: pipe, generation: generation)

            // Connect to audio engine
            connectToAudioEngine()

            // Start status polling
            startStatusPolling()

        } catch {
            dlog("❌ Failed to launch ProjectMHelper: \(error)", level: .error, category: .audio)
        }
    }

    private func cleanupAfterTermination() {
        helperGeneration &+= 1
        // Stop audio sending
        audioSendTimer?.cancel()
        audioSendTimer = nil

        // Stop status polling
        statusUpdateTimer?.invalidate()
        statusUpdateTimer = nil

        // Disconnect from audio
        disconnectFromAudioEngine()

        disconnectSocket()

        helperProcess = nil
        isRunning = false
        socketPath = nil
    }

    func stop() {
        guard isRunning else { return }
        helperGeneration &+= 1

        // Stop audio sending
        audioSendTimer?.cancel()
        audioSendTimer = nil

        // Stop status polling
        statusUpdateTimer?.invalidate()
        statusUpdateTimer = nil

        // Disconnect from audio
        disconnectFromAudioEngine()

        // Send quit command
        sendCommand("QUIT")

        disconnectSocket()

        // Terminate helper if still running
        if let process = helperProcess, process.isRunning {
            process.terminate()
        }
        helperProcess = nil

        isRunning = false
        socketPath = nil

        dlog("🛑 ProjectMHelper stopped", category: .audio)
    }

    // MARK: - Helper Location

    private func findHelperApp() -> URL? {
        // Look in main bundle's Helpers directory
        if let helpersURL = Bundle.main.builtInPlugInsURL?
            .deletingLastPathComponent()
            .appendingPathComponent("Helpers")
            .appendingPathComponent("ProjectMHelper.app")
            .appendingPathComponent("Contents")
            .appendingPathComponent("MacOS")
            .appendingPathComponent("ProjectMHelper") {
            if FileManager.default.fileExists(atPath: helpersURL.path) {
                return helpersURL
            }
        }

        // Look in Resources
        if let resourceURL = Bundle.main.url(forResource: "ProjectMHelper", withExtension: nil) {
            return resourceURL
        }

        // Development: look in build directory
        if let bundlePath = Bundle.main.bundlePath as NSString? {
            let devPath = (bundlePath.deletingLastPathComponent as NSString)
                .appendingPathComponent("ProjectMHelper.app/Contents/MacOS/ProjectMHelper")
            if FileManager.default.fileExists(atPath: devPath) {
                return URL(fileURLWithPath: devPath)
            }
        }

        return nil
    }

    // MARK: - Socket Connection

    private func disconnectSocket() {
        let source = readSource
        readSource = nil
        let socket = invalidateSocket()
        if socket >= 0 {
            shutdown(socket, SHUT_RDWR)
        }
        if let source {
            source.cancel()
        } else if socket >= 0 {
            close(socket)
        }
    }

    private func readSocketPath(from pipe: Pipe, generation: UInt64) {
        let fileHandle = pipe.fileHandleForReading
        let accumulator = SocketPathBuffer()

        // Use async reading with notification - don't block with readDataToEndOfFile
        fileHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                // EOF reached, stop reading
                handle.readabilityHandler = nil
                return
            }

            accumulator.data.append(data)
            while let newline = accumulator.data.firstIndex(of: 0x0A) {
                let lineData = accumulator.data[..<newline]
                accumulator.data.removeSubrange(...newline)
                guard let line = String(data: lineData, encoding: .utf8),
                      !accumulator.foundPath,
                      line.hasPrefix("SOCKET:") else { continue }
                accumulator.foundPath = true
                let path = String(line.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)

                DispatchQueue.main.async {
                    guard let self,
                          self.helperGeneration == generation,
                          self.helperProcess?.isRunning == true else { return }
                    self.connectToSocket(path: path, generation: generation)
                }
                break
            }
        }
    }

    private func connectToSocket(path: String, generation: UInt64) {
        guard helperGeneration == generation else { return }
        socketPath = path

        ipcQueue.async { [weak self] in
            guard let self else { return }

            // Create socket
            let sock = socket(AF_UNIX, SOCK_STREAM, 0)
            guard sock >= 0 else {
                dlog("❌ Failed to create IPC socket", level: .error, category: .audio)
                return
            }

            // Connect to helper
            var addr = sockaddr_un()
            addr.sun_family = sa_family_t(AF_UNIX)

            // Copy socket path to sun_path (avoiding overlapping access)
            let maxPathLength = MemoryLayout.size(ofValue: addr.sun_path)
            path.withCString { sourcePtr in
                withUnsafeMutablePointer(to: &addr.sun_path) { sunPathPtr in
                    let rawPtr = UnsafeMutableRawPointer(sunPathPtr).assumingMemoryBound(to: CChar.self)
                    strncpy(rawPtr, sourcePtr, maxPathLength - 1)
                    rawPtr[maxPathLength - 1] = 0
                }
            }

            let connectResult = withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                    connect(sock, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }

            guard connectResult == 0 else {
                dlog("❌ Failed to connect to helper socket: \(errno)", level: .error, category: .audio)
                close(sock)
                return
            }

            // Prevent SIGPIPE when helper closes the socket mid-write (crashes the host app otherwise)
            var noSigPipe: Int32 = 1
            setsockopt(sock, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

            DispatchQueue.main.async {
                guard self.helperGeneration == generation,
                      self.helperProcess?.isRunning == true else {
                    close(sock)
                    return
                }
                self.disconnectSocket()
                let generation = self.installSocket(sock)
                self.startReadingResponses(socket: sock, generation: generation)
                self.startAudioSending()
                // Відновити збережену якість (helper стартує з High)
                if self.selectedQuality != "High" {
                    self.sendCommand("QUALITY:\(self.selectedQuality)")
                }
                dlog("✅ Connected to ProjectMHelper IPC", category: .audio)
            }
        }
    }

    private func startReadingResponses(socket: Int32, generation: UInt64) {
        let accumulator = ResponseBuffer()
        let source = DispatchSource.makeReadSource(fileDescriptor: socket, queue: readQueue)
        readSource = source

        source.setEventHandler { [weak self] in
            self?.readResponse(socket: socket, generation: generation, accumulator: accumulator)
        }

        source.setCancelHandler {
            close(socket)
        }

        source.resume()
    }

    private func readResponse(socket: Int32, generation: UInt64, accumulator: ResponseBuffer) {
        guard socketIsCurrent(socket, generation: generation) else { return }
        var connectionClosed = false
        defer {
            if connectionClosed {
                Task { @MainActor [weak self] in
                    guard let self,
                          self.socketIsCurrent(socket, generation: generation) else { return }
                    self.disconnectSocket()
                }
            }
        }
        var buffer = [UInt8](repeating: 0, count: 65536)
        // Дренуємо весь доступний буфер сокета за одну подію: великий LIST (~1 МБ) приходить
        // багатьма чанками, а аудіо на ipcQueue не дає read-події частити.
        while true {
            guard socketIsCurrent(socket, generation: generation) else { return }
            let bytesRead = recv(socket, &buffer, buffer.count, MSG_DONTWAIT)
            if bytesRead < 0, errno == EINTR {
                continue
            }
            if bytesRead < 0, errno == EAGAIN || errno == EWOULDBLOCK {
                break
            }
            guard bytesRead > 0 else {
                connectionClosed = true
                break
            }
            accumulator.data.append(contentsOf: buffer[0..<bytesRead])
            if bytesRead < buffer.count { break }
        }

        guard !accumulator.data.isEmpty else { return }

        // Обробляємо лише завершені рядки (до \n); хвіст лишаємо в буфері.
        while let nl = accumulator.data.firstIndex(of: 0x0A) {
            let lineData = accumulator.data[accumulator.data.startIndex..<nl]
            accumulator.data = Data(accumulator.data[(nl + 1)...])
            if let line = String(data: lineData, encoding: .utf8) {
                processLine(line, socket: socket, generation: generation)
            }
        }
    }

    private func processLine(_ line: String, socket: Int32, generation: UInt64) {
        if line.hasPrefix("STATUS:") {
            let jsonStr = String(line.dropFirst(7))
            guard let data = jsonStr.data(using: .utf8),
                  let status = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.socketIsCurrent(socket, generation: generation) else { return }
                if let name = status["presetName"] as? String { self.currentPresetName = name }
                if let count = status["presetCount"] as? Int { self.presetCount = count }
                if let category = status["category"] as? String { self.currentCategory = category }
                if let weight = status["weight"] as? String { self.currentWeight = weight }
                if let categories = status["categories"] as? [String] { self.availableCategories = categories }
                if let fps = status["fps"] as? Int { self.currentFPS = fps }
            }
        } else if line.hasPrefix("LIST:") {
            let jsonStr = String(line.dropFirst(5))
            guard let data = jsonStr.data(using: .utf8),
                  let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                return
            }
            let list = arr.compactMap { item -> VizPreset? in
                guard let name = item["name"] as? String,
                      let category = item["category"] as? String,
                      let index = item["index"] as? Int else { return nil }
                return VizPreset(name: name, category: category, index: index)
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.socketIsCurrent(socket, generation: generation) else { return }
                self.presetList = list
            }
        }
    }

    // MARK: - Commands

    nonisolated func sendCommand(_ command: String) {
        ipcQueue.async { [weak self] in
            guard let self,
                  let connection = self.socketLease(),
                  let data = (command + "\n").data(using: .utf8) else { return }
            defer { close(connection.socket) }
            data.withUnsafeBytes { buffer in
                guard let baseAddress = buffer.baseAddress else { return }
                guard Self.writeAll(
                    socket: connection.socket,
                    baseAddress: baseAddress,
                    count: buffer.count
                ) else {
                    self.handleSocketWriteFailure(
                        leasedSocket: connection.socket,
                        originalSocket: connection.original,
                        generation: connection.generation
                    )
                    return
                }
            }
        }
    }

    func nextPreset() {
        sendCommand("NEXT")
    }

    func previousPreset() {
        sendCommand("PREV")
    }

    func randomPreset() {
        sendCommand("RAND")
    }

    func selectPreset(at index: Int) {
        sendCommand("SELECT:\(index)")
    }

    func resize(width: Int, height: Int) {
        sendCommand("RESIZE:\(width):\(height)")
    }

    // MARK: - Audio

    private func connectToAudioEngine() {
        CoreAudioEngine.shared.visualizerCallback = { [weak self] leftPtr, rightPtr, frameCount in
            self?.processAudioData(left: leftPtr, right: rightPtr, frameCount: frameCount)
        }
    }

    private func disconnectFromAudioEngine() {
        CoreAudioEngine.shared.visualizerCallback = nil
    }

    /// Called from real-time audio thread — lock-free, no heap allocation
    nonisolated private func processAudioData(
        left: UnsafePointer<Float>,
        right: UnsafePointer<Float>,
        frameCount: Int
    ) {
        let maxSamples = min(frameCount, 1024)
        let mask = Int32(audioRingCapacity - 1)
        let sampleCount = Int32(2 * maxSamples)
        let write = seq_atomic_int32_load(&_audioWriteIdx)
        let read = seq_atomic_int32_load(&_audioReadIdx)
        let used = Int(UInt32(bitPattern: write) &- UInt32(bitPattern: read))
        guard used + Int(sampleCount) <= audioRingCapacity else { return }
        // Single producer: write samples first, publish the index once after —
        // one atomic RMW per callback instead of two per sample.
        let base = write
        for i in 0..<maxSamples {
            let idx = base &+ Int32(2 * i)
            _audioRingBuffer[Int(idx & mask)] = left[i]
            _audioRingBuffer[Int((idx &+ 1) & mask)] = right[i]
        }
        _ = seq_atomic_int32_fetch_add(&_audioWriteIdx, sampleCount)
    }

    private func startAudioSending() {
        audioSendTimer?.cancel()
        audioSendTimer = nil

        // Pre-allocate reusable send buffer: 1 byte marker + 4 bytes length + up to 4096 floats
        let maxFrameBytes = 1 + 4 + 4096 * MemoryLayout<Float>.size
        let sendBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: maxFrameBytes)
        _sendBuffer = sendBuffer
        _sendBufferCapacity = maxFrameBytes

        audioSendTimer = DispatchSource.makeTimerSource(queue: ipcQueue)
        audioSendTimer?.schedule(deadline: .now(), repeating: .milliseconds(16)) // ~60 Hz

        audioSendTimer?.setEventHandler { [weak self] in
            self?.sendAudioBuffer()
        }

        // Deallocate send buffer on ipcQueue after the timer fully stops — guarantees the handler isn't mid-flight.
        audioSendTimer?.setCancelHandler { [weak self] in
            sendBuffer.deallocate()
            guard let self else { return }
            if self._sendBuffer == sendBuffer {
                self._sendBuffer = nil
                self._sendBufferCapacity = 0
            }
        }

        audioSendTimer?.resume()
    }

    /// Binary audio frame format (zero-copy, no base64):
    ///   [0x00 marker][UInt32 LE length in bytes][raw Float samples]
    /// Marker 0x00 cannot appear in UTF-8 text commands so it is unambiguous at the stream level.
    private func sendAudioBuffer() {
        guard let connection = socketLease() else { return }
        defer { close(connection.socket) }
        guard let sendBuf = _sendBuffer else { return }

        let write = seq_atomic_int32_load(&_audioWriteIdx)
        let read = seq_atomic_int32_load(&_audioReadIdx)
        let available = Int(UInt32(bitPattern: write) &- UInt32(bitPattern: read))

        guard available >= 512 else { return }

        let toRead = min(available, 4096)
        let mask = Int32(audioRingCapacity - 1)
        let payloadBytes = toRead * MemoryLayout<Float>.size
        let totalBytes = 1 + 4 + payloadBytes
        guard totalBytes <= _sendBufferCapacity else { return }

        // Header
        sendBuf[0] = 0x00
        let lengthLE = UInt32(payloadBytes).littleEndian
        withUnsafeBytes(of: lengthLE) { lenPtr in
            guard let baseAddr = lenPtr.bindMemory(to: UInt8.self).baseAddress else { return }
            sendBuf.advanced(by: 1).update(from: baseAddr, count: 4)
        }

        // Payload: copy ring → send buffer as raw bytes (payload offset = 5 is not Float-aligned).
        let payloadBase = UnsafeMutableRawPointer(sendBuf.advanced(by: 5))
        let floatSize = MemoryLayout<Float>.size
        for i in 0..<toRead {
            var sample = _audioRingBuffer[Int((read &+ Int32(i)) & mask)]
            payloadBase.advanced(by: i * floatSize).copyMemory(from: &sample, byteCount: floatSize)
        }
        _ = seq_atomic_int32_fetch_add(&_audioReadIdx, Int32(toRead))

        guard socketIsCurrent(connection.original, generation: connection.generation),
              Self.writeAll(
                  socket: connection.socket,
                  baseAddress: UnsafeRawPointer(sendBuf),
                  count: totalBytes
              ) else {
            handleSocketWriteFailure(
                leasedSocket: connection.socket,
                originalSocket: connection.original,
                generation: connection.generation
            )
            return
        }
    }

    // MARK: - Status Polling

    private func startStatusPolling() {
        statusUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.sendCommand("STATUS")
        }
    }
}
