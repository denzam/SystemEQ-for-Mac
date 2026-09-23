import Foundation
import MachO

// MARK: - Diagnostic Build

enum DiagnosticBuild {
    static var configuration: String {
        #if DEBUG
            "Debug"
        #else
            "Release"
        #endif
    }

    static var executableUUID: String {
        guard let header = _dyld_get_image_header(0), header.pointee.magic == MH_MAGIC_64 else {
            return "unavailable"
        }
        let start = UnsafeRawPointer(header).advanced(by: MemoryLayout<mach_header_64>.size)
        var offset = 0
        let size = Int(header.pointee.sizeofcmds)
        for _ in 0..<header.pointee.ncmds {
            guard offset <= size - MemoryLayout<load_command>.size else { break }
            let command = start.advanced(by: offset).load(as: load_command.self)
            let commandSize = Int(command.cmdsize)
            guard commandSize >= MemoryLayout<load_command>.size, commandSize <= size - offset else { break }
            if command.cmd == LC_UUID, commandSize >= MemoryLayout<uuid_command>.size {
                return UUID(uuid: start.advanced(by: offset).load(as: uuid_command.self).uuid).uuidString
            }
            offset += commandSize
        }
        return "unavailable"
    }
}

// MARK: - Diagnostic Events

struct DiagnosticEvent: Codable, Equatable {
    let timestamp: Date
    let name: String
    let details: [String: String]
}

nonisolated final class DiagnosticEventStore: @unchecked Sendable {
    static let shared = DiagnosticEventStore(persistenceURL: defaultPersistenceURL())

    private struct PersistedSession: Codable {
        let started: Date
        let cleanExit: Bool
        let events: [DiagnosticEvent]
        let discardedEvents: UInt64
    }

    private struct PersistedHistory: Codable {
        let sessions: [PersistedSession]
    }

    private let capacity: Int
    private let lock = NSLock()
    private var events: [DiagnosticEvent] = []
    private var discardedEvents: UInt64 = 0
    private let sessionStarted = Date()
    private let persistenceURL: URL?
    private let persistenceQueue = DispatchQueue(label: "SystemEQ.diagnostics.persistence")
    private var previousSessions: [PersistedSession] = []
    private var sessionStartedPersisted = false
    private var cleanExit = false
    private var persistenceFailed = false
    private var eventRevision: UInt64 = 0
    private var persistenceScheduled = false

    init(capacity: Int = 100, persistenceURL: URL? = nil) {
        self.capacity = min(max(capacity, 1), 100)
        self.persistenceURL = persistenceURL
    }

    private static func defaultPersistenceURL() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("SystemEQ for Mac", isDirectory: true)
            .appendingPathComponent("diagnostics-session.json")
    }

    func startSession() {
        lock.lock()
        guard !sessionStartedPersisted else {
            lock.unlock()
            return
        }
        if let persistenceURL,
           let data = try? Data(contentsOf: persistenceURL) {
            if let history = try? JSONDecoder().decode(PersistedHistory.self, from: data) {
                previousSessions = Self.boundedSessions(history.sessions)
            } else if let session = try? JSONDecoder().decode(PersistedSession.self, from: data) {
                previousSessions = [session]
            }
        }
        sessionStartedPersisted = true
        lock.unlock()
        persistenceQueue.sync { persist() }
    }

    func finishSession() {
        lock.lock()
        cleanExit = true
        lock.unlock()
        persistenceQueue.sync { persist() }
    }

    func record(_ name: String, details: [String: String] = [:]) {
        var boundedDetails: [String: String] = [:]
        for (key, value) in details.prefix(16) {
            boundedDetails[Self.boundedText(key, bytes: 128)] = Self.boundedText(value, bytes: 512)
        }
        let event = DiagnosticEvent(
            timestamp: Date(),
            name: Self.boundedText(name, bytes: 128),
            details: boundedDetails
        )
        var shouldPersist = false
        lock.lock()
        events.append(event)
        eventRevision &+= 1
        if events.count > capacity {
            discardedEvents &+= UInt64(events.count - capacity)
            events.removeFirst(events.count - capacity)
        }
        if persistenceURL != nil, sessionStartedPersisted, !persistenceScheduled {
            persistenceScheduled = true
            shouldPersist = true
        }
        lock.unlock()
        if shouldPersist {
            persistenceQueue.async { [self] in persistPendingEvents() }
        }
    }

    func snapshot() -> [DiagnosticEvent] {
        lock.lock()
        let snapshot = events
        lock.unlock()
        return snapshot
    }

    func reportText() -> String {
        lock.lock()
        let events = events
        let discarded = discardedEvents
        let previous = previousSessions
        let persistenceFailed = persistenceFailed
        lock.unlock()

        let formatter = ISO8601DateFormatter()
        let header = """
        Retention: newest \(capacity) events per session; up to 8 persisted sessions including current, plus loaded prior sessions in this report
        Persistent diagnostics available: \(persistenceURL != nil && !persistenceFailed)
        Entry limits: 16 fields; name/key 128 UTF-8 bytes; value 512 UTF-8 bytes (truncated if longer)
        Diagnostic session started: \(formatter.string(from: sessionStarted))
        Retained events: \(events.count); discarded older events: \(discarded)
        """
        let prior = previous.isEmpty ? "\nPrevious sessions: unavailable" : previous.map { session in
            "\nPrevious session started: \(formatter.string(from: session.started))" +
                "\nPrevious session clean exit: \(session.cleanExit)" +
                "\nPrevious session retained events: \(session.events.count)" +
                "\nPrevious session discarded older events: \(session.discardedEvents)" +
                "\n" + formatEvents(session.events, formatter: formatter)
        }.joined(separator: "\n")
        guard !events.isEmpty
        else { return header + prior + "\nNo SystemEQ diagnostic events were recorded in this session." }
        return header + prior + "\nCurrent session events:\n" + formatEvents(events, formatter: formatter)
    }

    private func formatEvents(_ events: [DiagnosticEvent], formatter: ISO8601DateFormatter) -> String {
        events.map { event in
            let details = event.details
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: ", ")
            return details.isEmpty
                ? "\(formatter.string(from: event.timestamp)) \(event.name)"
                : "\(formatter.string(from: event.timestamp)) \(event.name): \(details)"
        }.joined(separator: "\n")
    }

    private func persist() {
        guard let persistenceURL else { return }
        lock.lock()
        let session = PersistedSession(
            started: sessionStarted,
            cleanExit: cleanExit,
            events: events,
            discardedEvents: discardedEvents
        )
        let history = PersistedHistory(sessions: Self.boundedSessions(previousSessions + [session]))
        lock.unlock()
        do {
            try FileManager.default.createDirectory(
                at: persistenceURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try JSONEncoder().encode(history).write(to: persistenceURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: persistenceURL.path)
            lock.lock()
            persistenceFailed = false
            lock.unlock()
        } catch {
            lock.lock()
            persistenceFailed = true
            lock.unlock()
        }
    }

    private static func boundedSessions(_ sessions: [PersistedSession]) -> [PersistedSession] {
        var result = sessions
        while result.count > 8 {
            if let cleanIndex = result.dropLast().firstIndex(where: { $0.cleanExit }) {
                result.remove(at: cleanIndex)
            } else {
                result.removeFirst()
            }
        }
        return result
    }

    private func persistPendingEvents() {
        while true {
            lock.lock()
            let revision = eventRevision
            lock.unlock()
            persist()
            lock.lock()
            guard eventRevision != revision else {
                persistenceScheduled = false
                lock.unlock()
                return
            }
            lock.unlock()
        }
    }

    private static func boundedText(_ text: String, bytes: Int) -> String {
        var prefix = text.utf8.prefix(bytes)
        while String(bytes: prefix, encoding: .utf8) == nil {
            prefix = prefix.dropLast()
        }
        return String(decoding: prefix, as: UTF8.self)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }
}

nonisolated final class MainThreadHealthMonitor: @unchecked Sendable {
    static let shared = MainThreadHealthMonitor()

    private let queue = DispatchQueue(label: "SystemEQ.diagnostics.mainThread")
    private var timer: DispatchSourceTimer?
    private var pendingSince: UInt64?
    private var active = false

    func start() {
        queue.async { [self] in
            guard !active else { return }
            active = true
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + 2, repeating: 2)
            timer.setEventHandler { [self] in ping() }
            self.timer = timer
            timer.resume()
        }
    }

    func stop() {
        queue.sync {
            active = false
            pendingSince = nil
            timer?.cancel()
            timer = nil
        }
    }

    private func ping() {
        guard active, pendingSince == nil else { return }
        pendingSince = DispatchTime.now().uptimeNanoseconds
        DispatchQueue.main.async { [self] in
            queue.async { [self] in
                guard active, let pendingSince else { return }
                self.pendingSince = nil
                let elapsed = DispatchTime.now().uptimeNanoseconds &- pendingSince
                guard elapsed >= 5_000_000_000 else { return }
                DiagnosticEventStore.shared.record("app.mainThreadStall", details: [
                    "durationSeconds": String(format: "%.1f", Double(elapsed) / 1_000_000_000)
                ])
            }
        }
    }
}

// MARK: - Debug Logger

// Централізована система логування для SystemEQ
// В Release build весь код повністю видаляється компілятором

#if DEBUG

    /// Категорії логування для фільтрації
    enum LogCategory: String {
        case audio = "🔊 Audio"
        case engine = "⚙️ Engine"
        case routing = "🔀 Routing"
        case eq = "📊 EQ"
        case preset = "💾 Preset"
        case ui = "🖼️ UI"
        case network = "🌐 Network"
        case database = "🗄️ Database"
        case calibration = "🎯 Calibration"
        case general = "📝 General"
    }

    /// Рівні важливості
    enum LogLevel: Int, Comparable {
        case verbose = 0 // Детальна інформація (рідко потрібна)
        case debug = 1 // Debug інформація
        case info = 2 // Загальна інформація
        case warning = 3 // Попередження
        case error = 4 // Помилки

        nonisolated var prefix: String {
            switch self {
            case .verbose: "💬"
            case .debug: "🔍"
            case .info: "ℹ️"
            case .warning: "⚠️"
            case .error: "❌"
            }
        }

        nonisolated static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    /// Централізований логер (thread-safe)
    nonisolated final class DebugLogger: @unchecked Sendable {
        static let shared = DebugLogger()

        /// Мінімальний рівень для виводу (можна змінювати під час debug)
        nonisolated(unsafe) var minimumLevel: LogLevel = .debug

        /// Увімкнені категорії (nil = всі)
        nonisolated(unsafe) var enabledCategories: Set<LogCategory>?

        /// Чи показувати timestamp
        nonisolated(unsafe) var showTimestamp: Bool = true

        /// Чи показувати file/line
        nonisolated(unsafe) var showLocation: Bool = true

        private let dateFormatter: DateFormatter = {
            let df = DateFormatter()
            df.dateFormat = "HH:mm:ss.SSS"
            return df
        }()

        private init() {}

        nonisolated func log(
            _ message: @autoclosure () -> String,
            level: LogLevel = .debug,
            category: LogCategory = .general,
            file: String = #file,
            function: String = #function,
            line: Int = #line
        ) {
            // Перевірка рівня
            guard level >= minimumLevel else { return }

            // Перевірка категорії
            if let enabled = enabledCategories, !enabled.contains(category) {
                return
            }

            // Формування повідомлення
            var output = ""

            if showTimestamp {
                output += "[\(dateFormatter.string(from: Date()))] "
            }

            output += "\(level.prefix) \(category.rawValue)"

            if showLocation {
                let fileName = (file as NSString).lastPathComponent
                output += " [\(fileName):\(line)]"
            }

            output += " \(message())"

            print(output)
        }

        // MARK: - Convenience Methods

        func verbose(
            _ message: @autoclosure () -> String,
            category: LogCategory = .general,
            file: String = #file,
            function: String = #function,
            line: Int = #line
        ) {
            log(message(), level: .verbose, category: category, file: file, function: function, line: line)
        }

        func debug(
            _ message: @autoclosure () -> String,
            category: LogCategory = .general,
            file: String = #file,
            function: String = #function,
            line: Int = #line
        ) {
            log(message(), level: .debug, category: category, file: file, function: function, line: line)
        }

        func info(
            _ message: @autoclosure () -> String,
            category: LogCategory = .general,
            file: String = #file,
            function: String = #function,
            line: Int = #line
        ) {
            log(message(), level: .info, category: category, file: file, function: function, line: line)
        }

        func warning(
            _ message: @autoclosure () -> String,
            category: LogCategory = .general,
            file: String = #file,
            function: String = #function,
            line: Int = #line
        ) {
            log(message(), level: .warning, category: category, file: file, function: function, line: line)
        }

        func error(
            _ message: @autoclosure () -> String,
            category: LogCategory = .general,
            file: String = #file,
            function: String = #function,
            line: Int = #line
        ) {
            log(message(), level: .error, category: category, file: file, function: function, line: line)
        }
    }

    // MARK: - Global Functions (для зручності)

    /// Швидке логування
    func dlog(
        _ message: @autoclosure () -> String,
        level: LogLevel = .debug,
        category: LogCategory = .general,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        DebugLogger.shared.log(message(), level: level, category: category, file: file, function: function, line: line)
    }

    /// Audio-specific logging (НЕ для render callback!)
    func audioLog(
        _ message: @autoclosure () -> String,
        level: LogLevel = .debug,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        DebugLogger.shared.log(message(), level: level, category: .audio, file: file, function: function, line: line)
    }

    /// Engine-specific logging
    func engineLog(
        _ message: @autoclosure () -> String,
        level: LogLevel = .debug,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        DebugLogger.shared.log(message(), level: level, category: .engine, file: file, function: function, line: line)
    }

    /// EQ-specific logging
    func eqLog(
        _ message: @autoclosure () -> String,
        level: LogLevel = .debug,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        DebugLogger.shared.log(message(), level: level, category: .eq, file: file, function: function, line: line)
    }

    /// Error logging (завжди показується)
    nonisolated func errorLog(
        _ message: @autoclosure () -> String,
        category: LogCategory = .general,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        DebugLogger.shared.log(message(), level: .error, category: category, file: file, function: function, line: line)
    }

#else

    import os

    // MARK: - Release Build Stubs

    // В Release stub'и приймають ті ж типи що й DEBUG — інакше Swift не резолвить `.audio` / `.error`
    // на call-site (бо `Any?` не має member'ів enum). Debug/info — no-op (optimizer видаляє виклики),
    // але warning/error йдуть у os.Logger, щоб bug-репорти користувачів мали діагностику.

    // 🔧 os.Logger is thread-safe; the global would otherwise be inferred
    // MainActor-isolated and unreachable from the nonisolated log functions.
    nonisolated private let releaseLogger = Logger(
        subsystem: "com.denzam.SystemEQ",
        category: "SystemEQ"
    )

    enum LogCategory: String {
        case audio
        case engine
        case routing
        case eq
        case preset
        case ui
        case network
        case database
        case calibration
        case general
    }

    enum LogLevel: Int {
        case verbose
        case debug
        case info
        case warning
        case error
    }

    @inline(__always)
    func dlog(
        _ message: @autoclosure () -> String,
        level: LogLevel = .debug,
        category: LogCategory = .general,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        // Only surface warnings and errors in Release; debug/info stay no-ops.
        guard level.rawValue >= LogLevel.warning.rawValue else { return }
        let text = message() // evaluate here: os.Logger interpolation is escaping
        if level == .error {
            releaseLogger.error("\(text, privacy: .public)")
        } else {
            releaseLogger.warning("\(text, privacy: .public)")
        }
    }

    @inline(__always)
    func audioLog(
        _ message: @autoclosure () -> String,
        level: LogLevel = .debug,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        dlog(message(), level: level, category: .audio, file: file, function: function, line: line)
    }
    @inline(__always)
    func engineLog(
        _ message: @autoclosure () -> String,
        level: LogLevel = .debug,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        dlog(message(), level: level, category: .engine, file: file, function: function, line: line)
    }
    @inline(__always)
    func eqLog(
        _ message: @autoclosure () -> String,
        level: LogLevel = .debug,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        dlog(message(), level: level, category: .eq, file: file, function: function, line: line)
    }
    @inline(__always)
    nonisolated func errorLog(
        _ message: @autoclosure () -> String,
        category: LogCategory = .general,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        let text = message() // evaluate here: os.Logger interpolation is escaping
        releaseLogger.error("\(text, privacy: .public)")
    }

#endif
