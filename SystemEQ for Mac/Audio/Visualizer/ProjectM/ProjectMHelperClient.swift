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

    // MARK: - Private Properties

    private var helperProcess: Process?
    private var socketPath: String?
    private var readSource: DispatchSourceRead?

    private let ipcQueue = DispatchQueue(label: "com.systemeq.projectm.ipc", qos: .userInitiated)

    // Thread-safe socket access (nonisolated for background queue access)
    nonisolated(unsafe) private var _clientSocket: Int32 = -1
    nonisolated private let socketLock = NSLock()

    nonisolated private func getSocket() -> Int32 {
        socketLock.lock()
        defer { socketLock.unlock() }
        return _clientSocket
    }

    nonisolated private func setSocket(_ value: Int32) {
        socketLock.lock()
        _clientSocket = value
        socketLock.unlock()
    }

    private var statusUpdateTimer: Timer?

    // Lock-free ring buffer for audio (written on real-time audio thread, read on ipcQueue)
    private let audioRingCapacity = 8192 // must be power of 2
    nonisolated(unsafe) private var _audioRingBuffer: UnsafeMutablePointer<Float>
    nonisolated(unsafe) private var _audioWriteIdx: SEQAtomicInt32 = seq_atomic_int32_make(0)
    private var _audioReadIdx: Int32 = 0 // only accessed from ipcQueue
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
            // Close socket synchronously so pending writes fail fast instead of blocking/retrying.
            // SO_NOSIGPIPE already prevents the fatal signal; this just avoids wasted work until MainActor cleanup
            // runs.
            process.terminationHandler = { [weak self] _ in
                if let self {
                    let sock = self.getSocket()
                    if sock >= 0 {
                        close(sock)
                        self.setSocket(-1)
                    }
                }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    dlog("🛑 ProjectMHelper terminated by user", category: .audio)
                    self.cleanupAfterTermination()
                }
            }

            // Read socket path from helper's stdout
            readSocketPath(from: pipe)

            // Connect to audio engine
            connectToAudioEngine()

            // Start status polling
            startStatusPolling()

        } catch {
            dlog("❌ Failed to launch ProjectMHelper: \(error)", level: .error, category: .audio)
        }
    }

    private func cleanupAfterTermination() {
        // Stop audio sending
        audioSendTimer?.cancel()
        audioSendTimer = nil

        // Stop status polling
        statusUpdateTimer?.invalidate()
        statusUpdateTimer = nil

        // Disconnect from audio
        disconnectFromAudioEngine()

        // Close socket
        let sock = getSocket()
        if sock >= 0 {
            close(sock)
            setSocket(-1)
        }

        helperProcess = nil
        isRunning = false
        socketPath = nil
    }

    func stop() {
        guard isRunning else { return }

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

        // Close socket
        let sock = getSocket()
        if sock >= 0 {
            close(sock)
            setSocket(-1)
        }

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

    private func readSocketPath(from pipe: Pipe) {
        let fileHandle = pipe.fileHandleForReading

        // Use async reading with notification - don't block with readDataToEndOfFile
        fileHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                // EOF reached, stop reading
                handle.readabilityHandler = nil
                return
            }

            guard let output = String(data: data, encoding: .utf8) else { return }

            // Parse SOCKET: line
            for line in output.components(separatedBy: "\n") where line.hasPrefix("SOCKET:") {
                let path = String(line.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
                handle.readabilityHandler = nil // Stop reading after we get socket path

                DispatchQueue.main.async {
                    self?.connectToSocket(path: path)
                }
                break
            }
        }
    }

    private func connectToSocket(path: String) {
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
                self.setSocket(sock)
                self.startReadingResponses()
                self.startAudioSending()
                dlog("✅ Connected to ProjectMHelper IPC", category: .audio)
            }
        }
    }

    private func startReadingResponses() {
        let sock = getSocket()
        guard sock >= 0 else { return }

        readSource = DispatchSource.makeReadSource(fileDescriptor: sock, queue: ipcQueue)

        readSource?.setEventHandler { [weak self] in
            self?.readResponse()
        }

        readSource?.setCancelHandler { [weak self] in
            if let self, self.getSocket() >= 0 {
                close(self.getSocket())
            }
            self?.setSocket(-1)
        }

        readSource?.resume()
    }

    private func readResponse() {
        let sock = getSocket()
        guard sock >= 0 else { return }
        var buffer = [UInt8](repeating: 0, count: 4096)
        let bytesRead = read(sock, &buffer, buffer.count)

        guard bytesRead > 0 else { return }

        if let response = String(bytes: buffer[0..<bytesRead], encoding: .utf8) {
            processResponse(response)
        }
    }

    private func processResponse(_ response: String) {
        for line in response.components(separatedBy: "\n") where line.hasPrefix("STATUS:") {
            let jsonStr = String(line.dropFirst(7))
            if let data = jsonStr.data(using: .utf8),
               let status = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                DispatchQueue.main.async { [weak self] in
                    if let name = status["presetName"] as? String {
                        self?.currentPresetName = name
                    }
                    if let count = status["presetCount"] as? Int {
                        self?.presetCount = count
                    }
                    if let category = status["category"] as? String {
                        self?.currentCategory = category
                    }
                    if let weight = status["weight"] as? String {
                        self?.currentWeight = weight
                    }
                    if let categories = status["categories"] as? [String] {
                        self?.availableCategories = categories
                    }
                }
            }
        }
    }

    // MARK: - Commands

    nonisolated func sendCommand(_ command: String) {
        let sock = getSocket()
        guard sock >= 0 else { return }

        ipcQueue.async {
            guard let data = (command + "\n").data(using: .utf8) else { return }
            data.withUnsafeBytes { buffer in
                if let baseAddress = buffer.baseAddress {
                    write(sock, baseAddress, buffer.count)
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
        for i in 0..<maxSamples {
            let wi = seq_atomic_int32_fetch_add(&_audioWriteIdx, 1)
            _audioRingBuffer[Int(wi & mask)] = left[i]
            let wi2 = seq_atomic_int32_fetch_add(&_audioWriteIdx, 1)
            _audioRingBuffer[Int(wi2 & mask)] = right[i]
        }
    }

    private func startAudioSending() {
        // Pre-allocate reusable send buffer: 1 byte marker + 4 bytes length + up to 4096 floats
        let maxFrameBytes = 1 + 4 + 4096 * MemoryLayout<Float>.size
        _sendBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: maxFrameBytes)
        _sendBufferCapacity = maxFrameBytes

        audioSendTimer = DispatchSource.makeTimerSource(queue: ipcQueue)
        audioSendTimer?.schedule(deadline: .now(), repeating: .milliseconds(16)) // ~60 Hz

        audioSendTimer?.setEventHandler { [weak self] in
            self?.sendAudioBuffer()
        }

        // Deallocate send buffer on ipcQueue after the timer fully stops — guarantees the handler isn't mid-flight.
        audioSendTimer?.setCancelHandler { [weak self] in
            guard let self else { return }
            if let buf = self._sendBuffer {
                buf.deallocate()
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
        let sock = getSocket()
        guard sock >= 0 else { return }
        guard let sendBuf = _sendBuffer else { return }

        let write = seq_atomic_int32_load(&_audioWriteIdx)
        let read = _audioReadIdx
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
            var sample = _audioRingBuffer[Int(_audioReadIdx & mask)]
            _audioReadIdx &+= 1
            payloadBase.advanced(by: i * floatSize).copyMemory(from: &sample, byteCount: floatSize)
        }

        // Single write() — kernel handles partial writes by buffering in socket sndbuf.
        // For SOCK_STREAM on AF_UNIX with this size (~16KB max) this is effectively atomic.
        var bytesSent = 0
        while bytesSent < totalBytes {
            let n = Darwin.write(sock, sendBuf.advanced(by: bytesSent), totalBytes - bytesSent)
            if n <= 0 { break } // EPIPE/EAGAIN — helper gone or socket full; drop frame
            bytesSent += n
        }
    }

    // MARK: - Status Polling

    private func startStatusPolling() {
        statusUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.sendCommand("STATUS")
        }
    }
}
