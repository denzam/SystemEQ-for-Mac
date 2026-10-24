import Foundation

nonisolated struct FeedbackReport {
    static let recipient = "systemeqformac@gmail.com"
    static let descriptionLimit = 2000

    let version: String
    let build: String
    let operatingSystem: OperatingSystemVersion
    let eqEnabled: Bool
    let engineRunning: Bool
    let bandCount: Int
    let backend: String
    let sampleRate: Double
    let preamp: Double
    let outputBoost: Double
    let events: [DiagnosticEvent]

    private static let eventNames: Set<String> = [
        "eq.enabled", "eq.disabled", "routing.enable.deferred", "routing.enable.request",
        "routing.enable.skipped", "routing.enable.failed", "routing.enable.succeeded",
        "routing.native.fallback", "routing.blackHoleGainStaging", "routing.disable.request",
        "routing.defaultOutput.requested", "routing.defaultOutput.verified",
        "routing.originalOutput.recovered", "routing.originalOutput.saved", "routing.volumeTransfer",
        "routing.blackHoleInputVolumeOverride", "routing.blackHoleAvailability",
        "routing.sleep", "routing.wake.scheduled", "engine.restoreRate.failed",
        "engine.setup.stepFailed", "engine.setup.request", "engine.setup.failed",
        "engine.setup.format", "engine.setup.bufferMismatch", "engine.setup.ready",
        "engine.start.failed", "engine.start.succeeded", "engine.audioHealth", "engine.stop",
        "engine.testTone.started", "engine.testTone.stopped", "visualizer.start.request",
        "visualizer.start.failed", "visualizer.helper.launched", "visualizer.helper.terminated",
        "visualizer.stop", "visualizer.ipc.failed", "visualizer.ipc.connected", "visualizer.ipc.disconnected",
    ]

    private static let statusKeys: [String: [String]] = [
        "engine.setup.stepFailed": ["status"],
        "engine.start.failed": ["inputStatus", "outputStatus"],
        "routing.defaultOutput.requested": ["status"],
        "visualizer.helper.terminated": ["status"],
        "visualizer.ipc.failed": ["status"],
    ]

    var text: String {
        let backend = ["none", "native", "blackHole"].contains(backend) ? backend : "unavailable"
        let bands = [10, 31].contains(bandCount) ? String(bandCount) : "unavailable"
        let recent = events.lazy.filter { Self.eventNames.contains($0.name) }.suffix(50).map { event in
            let fields = (Self.statusKeys[event.name] ?? []).compactMap { key -> String? in
                guard let raw = event.details[key], raw.utf8.count <= 12, let status = Int32(raw) else { return nil }
                return "\(key)=\(status)"
            }
            return ([event.name] + fields).joined(separator: " ")
        }.joined(separator: "\n")
        return """
        SystemEQ feedback diagnostics
        Report format: 1
        App version: \(Self.versionToken(version))
        App build: \(Self.versionToken(build))
        macOS: \(operatingSystem.majorVersion).\(operatingSystem.minorVersion).\(operatingSystem.patchVersion)
        EQ enabled: \(eqEnabled)
        Engine running: \(engineRunning)
        Band count: \(bands)
        Backend: \(backend)
        Sample rate Hz: \(Self.number(sampleRate, range: 1...768_000))
        Preamp dB: \(Self.number(preamp, range: -120...60))
        Output boost dB: \(Self.number(outputBoost, range: -120...60))

        Recent known events (up to 50, oldest first; only numeric failure codes):
        \(recent.isEmpty ? "unavailable" : recent)
        """
    }

    static func message(description: String, diagnostics: String) -> String {
        let description = description.unicodeScalars.filter {
            !CharacterSet.controlCharacters.contains($0) || $0 == "\n" || $0 == "\t"
        }
        let bounded = String(String.UnicodeScalarView(description)).prefix(descriptionLimit)
        return diagnostics + "\n\n--- User description ---\n" + String(bounded)
    }

    private static func versionToken(_ value: String) -> String {
        guard !value.isEmpty, value.utf8.count <= 32,
              value.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "0123456789.-").contains($0) })
        else { return "unavailable" }
        return value
    }

    private static func number(_ value: Double, range: ClosedRange<Double>) -> String {
        guard value.isFinite, range.contains(value) else { return "unavailable" }
        return String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}
