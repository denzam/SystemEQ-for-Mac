import Combine
import Foundation

@MainActor
final class AutoEQState: ObservableObject {
    enum BandMode: String, CaseIterable, Identifiable {
        case ten = "10"
        case thirtyOne = "31"

        var id: String {
            rawValue
        }

        init(audioEngineMode: EQBandMode) {
            self = audioEngineMode == .tenBand ? .ten : .thirtyOne
        }

        var audioEngineMode: EQBandMode {
            self == .ten ? .tenBand : .thirtyOneBand
        }
    }

    struct Identity: Codable, Equatable {
        let name: String?
        let source: String?
        let path: String?
        let rawText: String?
        var target: String?
    }

    struct Engine {
        let mode: () -> EQBandMode
        let setMode: (EQBandMode) -> Void
        let gains: () -> [Float]
        let preamp: () -> Float
        let setPreamp: (Float) -> Void
        let headroom: (EQBandMode, [Float]) -> Float?
        let apply: ([Float]) -> Void
        let enabled: () -> Bool
        let enable: () -> Void
    }

    struct Request: Equatable {
        let generation: UUID
        let session: UUID
        let outputUID: String?
        let revision: UInt64
        let sampleRate: Double
        fileprivate let previousPlayback: Playback
    }

    fileprivate struct Playback: Equatable {
        let mode: EQBandMode
        let gains: [Float]
        let preamp: Float
    }

    static let shared: AutoEQState = {
        let engine = AudioEngine.shared
        let owner = AutoEQState(
            engine: Engine(
                mode: { engine.bandMode },
                setMode: { engine.bandMode = $0 },
                gains: { engine.getCurrentEQValues() },
                preamp: { engine.preampGain },
                setPreamp: { engine.setPreampGain($0) },
                headroom: { engine.importPreampLimit(mode: $0, gains: $1) },
                apply: { engine.applyEQValues($0) },
                enabled: { engine.isEnabled },
                enable: { engine.setEnabled(true) }
            ),
            defaults: .standard,
            outputUID: { AudioRouter.shared.selectedOutputDevice?.uid },
            sampleRate: { CoreAudioEngine.shared.processingSampleRate },
            initialBassBoost: Double(PresetPersistence.load()?.bassBoost ?? 0),
            persist: { PresetPersistence.save(mode: $0, gains: $1, preamp: $2, bassBoost: $3) },
            recordApply: { DevicePresetManager.shared.recordApply($0, outputUID: $1) }
        )
        owner.bind(to: DevicePresetManager.shared)
        Publishers.Merge3(
            engine.$bandMode.map { _ in () },
            engine.$bands.map { _ in () },
            engine.$preampGain.map { _ in () }
        )
        .sink { [weak owner] in
            DispatchQueue.main.async { owner?.synchronizePlayback() }
        }
        .store(in: &owner.cancellables)
        CoreAudioEngine.shared.$isRunning.sink { [weak owner] _ in
            DispatchQueue.main.async { owner?.environmentChanged() }
        }
        .store(in: &owner.cancellables)
        return owner
    }()

    @Published private(set) var appliedIdentity: Identity?
    @Published private(set) var previewIdentity: Identity?
    @Published private(set) var preparedImport: AutoEQPreparedPreset?
    @Published private(set) var parsed: [ParsedBand] = []
    @Published private(set) var bandMode: BandMode
    @Published private(set) var mapped: [MappedBand] = []
    @Published private(set) var bassBoost: Double
    @Published private(set) var preampDB: Double?
    @Published private(set) var importNeedsApply = false
    @Published private(set) var importCurveEdited = false
    @Published private(set) var isImporting = false
    @Published private(set) var importError: AutoEQImportError?

    private let engine: Engine
    private let defaults: UserDefaults
    private let outputUID: () -> String?
    private let sampleRate: () -> Double
    private let persist: (EQBandMode, [Float], Float, Float) -> Void
    private let recordApply: (DevicePresetRecord, String?) -> Void
    private let prepare: @Sendable (AutoEQImportedPreset, Double) async throws -> AutoEQPreparedPreset
    private var generation = UUID()
    private var session = UUID()
    private var isActive = true
    private var context: DevicePresetManager.OutputContext?
    private var fetchTask: Task<Void, Never>?
    private var prepareTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private var currentRequest: Request?
    private var lastPlayback: Playback
    private var appliedBassBoost: Double
    private var playbackUID: String?
    private var cancellables = Set<AnyCancellable>()

    init(
        engine: Engine,
        defaults: UserDefaults,
        outputUID: @escaping () -> String?,
        sampleRate: @escaping () -> Double,
        initialBassBoost: Double = 0,
        persist: @escaping (EQBandMode, [Float], Float, Float) -> Void,
        recordApply: @escaping (DevicePresetRecord, String?) -> Void,
        prepare: @escaping @Sendable (AutoEQImportedPreset, Double) async throws
            -> AutoEQPreparedPreset = { input, rate in
                let worker = Task
                    .detached(priority: .userInitiated) { try EQConverter(sampleRate: rate).prepare(input) }
                return try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: { worker.cancel() }
            }
    ) {
        self.engine = engine
        self.defaults = defaults
        self.outputUID = outputUID
        self.sampleRate = sampleRate
        self.persist = persist
        self.recordApply = recordApply
        self.prepare = prepare
        bandMode = BandMode(audioEngineMode: engine.mode())
        bassBoost = initialBassBoost.isFinite ? initialBassBoost : 0
        appliedBassBoost = initialBassBoost.isFinite ? initialBassBoost : 0
        playbackUID = outputUID()
        lastPlayback = Playback(mode: engine.mode(), gains: engine.gains(), preamp: engine.preamp())
        restorePlayback()
    }

    func bind(to manager: DevicePresetManager) {
        manager.$outputContext.compactMap(\.self).sink { [weak self] in self?.outputChanged($0) }
            .store(in: &cancellables)
        manager.$appliedPreset.compactMap(\.self).sink { [weak self] in self?.devicePresetApplied($0) }
            .store(in: &cancellables)
    }

    var activePresetName: String? {
        appliedIdentity?.name
    }
    var activePresetSource: String? {
        appliedIdentity?.source
    }
    var activePresetTarget: String? {
        appliedIdentity?.target
    }
    var activePresetPath: String? {
        appliedIdentity?.path
    }
    var appliedText: String {
        appliedIdentity?.rawText ?? ""
    }

    private func playback() -> Playback {
        Playback(mode: engine.mode(), gains: engine.gains(), preamp: engine.preamp())
    }

    private var hasCurrentOutputContext: Bool {
        playbackUID == outputUID() && (context == nil || context?.outputUID == outputUID())
    }

    @discardableResult
    func beginRequest() -> Request {
        cancelPending()
        let request = Request(
            generation: generation,
            session: session,
            outputUID: outputUID(),
            revision: context?.revision ?? 0,
            sampleRate: sampleRate(),
            previousPlayback: playback()
        )
        currentRequest = request
        isImporting = isActive && hasCurrentOutputContext
        importError = nil
        return request
    }

    func isCurrent(_ request: Request) -> Bool {
        isActive && hasCurrentOutputContext && request.session == session && request.generation == generation &&
            request.outputUID == outputUID() &&
            request.revision == (context?.revision ?? 0) && sampleRate().isFinite &&
            abs(request.sampleRate - sampleRate()) < 1
    }

    func fetch(session expectedSession: UUID? = nil, _ operation: @escaping (Request) async -> Void) async {
        guard isActive, hasCurrentOutputContext, expectedSession == nil || expectedSession == session else { return }
        let request = beginRequest()
        let task = Task { await operation(request) }
        fetchTask = task
        await task.value
        finishFetch(request)
    }

    func finishFetch(_ request: Request) {
        guard request.generation == generation else { return }
        if !isCurrent(request) {
            cancelPending()
        } else if prepareTask == nil {
            isImporting = false
        }
    }

    func report(_ error: Error, request: Request? = nil) {
        if let request, !isCurrent(request) { return }
        importError = error as? AutoEQImportError ?? .invalidSource
    }

    func startImport(
        _ input: AutoEQImportedPreset,
        identity: Identity,
        autoApply: Bool,
        preservePlayback: Bool,
        request existingRequest: Request? = nil
    ) {
        let request = existingRequest ?? beginRequest()
        guard isCurrent(request) else { finishInvalidRequest(request); return }
        prepareTask?.cancel()
        debounceTask?.cancel()
        isImporting = true
        importError = nil
        let prepare = prepare
        prepareTask = Task { [weak self] in
            do {
                let prepared = try await prepare(input, request.sampleRate)
                try Task.checkCancellation()
                guard let self, isCurrent(request) else { self?.finishInvalidRequest(request); return }
                let result = prepared.result(for: bandMode.audioEngineMode)
                let safePreamp: Double
                if preservePlayback {
                    safePreamp = Double(engine.preamp())
                    bassBoost = appliedBassBoost
                } else {
                    guard let safe = preparedPreamp(result) else { throw AutoEQImportError.insufficientHeadroom }
                    safePreamp = safe
                }
                preparedImport = prepared
                previewIdentity = identity
                importCurveEdited = preservePlayback
                parsed = input.displayBands.isEmpty ? [ParsedBand(freq: 1000, gain: 0)] : input.displayBands
                preampDB = safePreamp
                mapped = preservePlayback ? playbackMapping() : fittedMapping()
                importNeedsApply = !preservePlayback && playback() != request.previousPlayback
                isImporting = false
                prepareTask = nil
                if autoApply, !importNeedsApply { apply() }
            } catch is CancellationError {
                self?.finishInvalidRequest(request)
            } catch {
                guard let self else { return }
                if isCurrent(request) {
                    report(error, request: request)
                    isImporting = false
                    prepareTask = nil
                } else {
                    finishInvalidRequest(request)
                }
            }
        }
    }

    private func finishInvalidRequest(_ request: Request) {
        guard request.generation == generation else { return }
        cancelPending()
    }

    func cancelPending() {
        generation = UUID()
        fetchTask?.cancel()
        prepareTask?.cancel()
        debounceTask?.cancel()
        fetchTask = nil
        prepareTask = nil
        debounceTask = nil
        currentRequest = nil
        isImporting = false
    }

    func close() {
        isActive = false
        session = UUID()
        cancelPending()
        restorePlayback()
    }

    @discardableResult
    func open() -> UUID {
        isActive = true
        session = UUID()
        return session
    }

    var sessionToken: UUID {
        session
    }

    func isOpen(_ expectedSession: UUID) -> Bool {
        isActive && expectedSession == session
    }

    func environmentChanged() {
        if let currentRequest, !isCurrent(currentRequest) { cancelPending() }
    }

    func outputChanged(_ newContext: DevicePresetManager.OutputContext) {
        guard newContext.outputUID == outputUID(), context != newContext else { return }
        context = newContext
        playbackUID = newContext.outputUID
        cancelPending()
        restorePlayback()
    }

    func devicePresetApplied(_ event: DevicePresetManager.AppliedPreset) {
        guard event.context == context, event.context.outputUID == outputUID() else { return }
        cancelPending()
        appliedBassBoost = Double(event.record?.bassBoost ?? 0)
        restorePlayback(descriptorJSON: event.record?.descriptorJSON ?? "")
    }

    func restorePlayback(descriptorJSON: String? = nil) {
        let json = descriptorJSON ?? defaults.string(forKey: "lastAppliedPresetJSON") ?? ""
        appliedIdentity = json.data(using: .utf8).flatMap { try? JSONDecoder().decode(Identity.self, from: $0) }
        previewIdentity = appliedIdentity
        preparedImport = nil
        importNeedsApply = false
        importCurveEdited = true
        bassBoost = appliedBassBoost
        bandMode = BandMode(audioEngineMode: engine.mode())
        preampDB = Double(engine.preamp())
        mapped = playbackMapping()
        parsed = appliedIdentity == nil ? [] : [ParsedBand(freq: 1000, gain: 0)]
        lastPlayback = playback()
    }

    func synchronizePlayback() {
        environmentChanged()
        let current = playback()
        guard current != lastPlayback else { return }
        lastPlayback = current
        guard !isImporting, !importNeedsApply else { return }
        debounceTask?.cancel()
        bassBoost = appliedBassBoost
        bandMode = BandMode(audioEngineMode: current.mode)
        preampDB = Double(current.preamp)
        mapped = playbackMapping()
        importCurveEdited = true
    }

    private func playbackMapping() -> [MappedBand] {
        let mode = engine.mode()
        let values = engine.gains()
        guard values.count == mode.bandCount else { return [] }
        return zip(mode.frequencies, values).map { frequency, gain in
            let center = Double(frequency)
            return MappedBand(
                center: center,
                gain: Double(gain) - BassBoostCurve.gain(at: center, amount: appliedBassBoost)
            )
        }
    }

    private func fittedMapping() -> [MappedBand] {
        guard let preparedImport else { return [] }
        return zip(bandMode.audioEngineMode.frequencies, preparedImport.result(for: bandMode.audioEngineMode).gains)
            .map { MappedBand(center: Double($0.0), gain: Double($0.1)) }
    }

    private func preparedPreamp(_ result: AutoEQFitResult) -> Double? {
        let mode = bandMode.audioEngineMode
        let gains = zip(mode.frequencies, result.gains).map {
            $0.1 + Float(BassBoostCurve.gain(at: Double($0.0), amount: bassBoost))
        }
        guard let limit = engine.headroom(mode, gains) else { return nil }
        let value = min(Double(result.preamp), Double(limit))
        return value.isFinite && value >= -20 ? value : nil
    }

    func selectBandMode(_ mode: BandMode) {
        guard isActive, bandMode != mode else { return }
        if isImporting { cancelPending() }
        debounceTask?.cancel()
        let needsReview = importNeedsApply
        bandMode = mode
        engine.setMode(mode.audioEngineMode)
        if let preparedImport {
            let result = preparedImport.result(for: mode.audioEngineMode)
            mapped = fittedMapping()
            preampDB = Double(result.preamp)
            importCurveEdited = false
            guard let safe = preparedPreamp(result) else {
                importNeedsApply = true
                report(AutoEQImportError.insufficientHeadroom)
                return
            }
            preampDB = safe
            importNeedsApply = needsReview || !engine.enabled()
            if !importNeedsApply { apply() }
        }
    }

    func setBassBoost(_ value: Double) {
        guard isActive, value.isFinite, value != bassBoost else { return }
        if isImporting { cancelPending() }
        bassBoost = min(6, max(0, value))
        scheduleApply(delay: 50_000_000)
    }

    func editBand(at index: Int, gain: Double) {
        guard isActive, mapped.indices.contains(index), gain.isFinite, mapped[index].gain != gain else { return }
        if isImporting { cancelPending() }
        importCurveEdited = true
        mapped[index].gain = gain
        scheduleApply()
    }

    func scheduleApply(delay: UInt64 = 30_000_000) {
        guard isActive, !importNeedsApply, !isImporting else { return }
        debounceTask?.cancel()
        let request = Request(
            generation: generation,
            session: session,
            outputUID: outputUID(),
            revision: context?.revision ?? 0,
            sampleRate: sampleRate(),
            previousPlayback: playback()
        )
        debounceTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: delay) } catch { return }
            guard let self, isCurrent(request), !Task.isCancelled else { return }
            apply()
        }
    }

    @discardableResult
    func apply() -> Bool {
        guard isActive, !isImporting, !mapped.isEmpty else { return false }
        guard hasCurrentOutputContext else {
            cancelPending()
            return false
        }
        if !importCurveEdited, let preparedImport,
           abs(preparedImport.ten.sampleRate - sampleRate()) >= 1 {
            guard let previewIdentity else { return false }
            startImport(preparedImport.input, identity: previewIdentity, autoApply: true, preservePlayback: false)
            return false
        }
        let mode = bandMode.audioEngineMode
        let clean = mapped.map { Float($0.gain) }
        let values = mapped.map { Float($0.gain + BassBoostCurve.gain(at: $0.center, amount: bassBoost)) }
        guard values.count == mode.bandCount, clean.allSatisfy(\.isFinite), bassBoost.isFinite,
              let limit = engine.headroom(mode, values) else {
            report(AutoEQImportError.insufficientHeadroom)
            return false
        }
        let attenuation = min(Float(preampDB ?? 0), limit)
        guard attenuation.isFinite, attenuation >= -20 else {
            report(AutoEQImportError.insufficientHeadroom)
            return false
        }
        let identity = previewIdentity
        let descriptorJSON = identity.flatMap { try? JSONEncoder().encode($0) }.flatMap { String(
            data: $0,
            encoding: .utf8
        ) }
        engine.setMode(mode)
        engine.setPreamp(attenuation)
        engine.apply(values)
        preampDB = Double(attenuation)
        importNeedsApply = false
        appliedBassBoost = bassBoost
        appliedIdentity = identity
        if let descriptorJSON {
            defaults.set(descriptorJSON, forKey: "lastAppliedPresetJSON")
            recordApply(DevicePresetRecord(
                mode: mode.rawValue,
                appliedGains: values,
                cleanGains: clean,
                preamp: attenuation,
                bassBoost: Float(bassBoost),
                descriptorJSON: descriptorJSON
            ), outputUID())
        }
        if identity?.source == "Custom" {
            defaults.set(identity?.rawText ?? "", forKey: "lastCustomPresetText")
            defaults.set(identity?.name ?? "", forKey: "lastCustomPresetName")
        }
        persist(mode, clean, attenuation, Float(bassBoost))
        lastPlayback = playback()
        if !engine.enabled() { engine.enable() }
        return true
    }
}
