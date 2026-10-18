@testable import SystemEQ_for_Mac
import XCTest

@MainActor
final class AutoEQStateTests: XCTestCase {
    private final class Harness {
        var mode = EQBandMode.tenBand
        var gains = [Float](repeating: 0, count: 10)
        var preamp: Float = 0
        var enabled = true
        var limit: Float? = -3
        var uid: String? = "A"
        var rate = 48000.0
        var applyCount = 0
        var records: [(DevicePresetRecord, String?)] = []
        var saved: [(EQBandMode, [Float], Float, Float)] = []

        var engine: AutoEQState.Engine {
            AutoEQState.Engine(
                mode: { self.mode },
                setMode: { self.mode = $0 },
                gains: { self.gains },
                preamp: { self.preamp },
                setPreamp: { self.preamp = $0 },
                headroom: { _, _ in self.limit },
                apply: { self.gains = $0; self.applyCount += 1 },
                enabled: { self.enabled },
                enable: { self.enabled = true }
            )
        }
    }

    private actor PreparationGate {
        private var continuation: CheckedContinuation<AutoEQPreparedPreset, Error>?
        private(set) var started = false

        func prepare() async throws -> AutoEQPreparedPreset {
            try await withCheckedThrowingContinuation {
                continuation = $0
                started = true
            }
        }

        func complete(_ prepared: AutoEQPreparedPreset) {
            continuation?.resume(returning: prepared)
            continuation = nil
        }

        func fail() {
            continuation?.resume(throwing: AutoEQImportError.invalidSource)
            continuation = nil
        }
    }

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "AutoEQStateTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private func owner(
        _ harness: Harness,
        bassBoost: Double = 0,
        prepare: @escaping @Sendable (AutoEQImportedPreset, Double) async throws -> AutoEQPreparedPreset = {
            AutoEQStateTests.prepared($0, rate: $1)
        }
    ) -> AutoEQState {
        AutoEQState(
            engine: harness.engine,
            defaults: defaults,
            outputUID: { harness.uid },
            sampleRate: { harness.rate },
            initialBassBoost: bassBoost,
            persist: { harness.saved.append(($0, $1, $2, $3)) },
            recordApply: { harness.records.append(($0, $1)) },
            prepare: prepare
        )
    }

    private func input() throws -> AutoEQImportedPreset {
        try AutoEQImportParser.parse("Preamp: -4 dB\nFilter 1: ON PK Fc 1000 Hz Gain 1 dB Q 1")
    }

    private func identity(_ name: String) -> AutoEQState.Identity {
        AutoEQState.Identity(name: name, source: "Custom", path: nil, rawText: "Preamp: -4 dB")
    }

    nonisolated private static func prepared(
        _ input: AutoEQImportedPreset,
        rate: Double = 48000,
        gain: Float = 1,
        requiresReview: Bool = false
    ) -> AutoEQPreparedPreset {
        func result(_ count: Int) -> AutoEQFitResult {
            AutoEQFitResult(
                gains: [Float](repeating: gain, count: count),
                preamp: -4,
                rms: requiresReview ? 2 : 0,
                maximumError: requiresReview ? 5 : 0,
                sampleRate: rate,
                preampAdjusted: requiresReview
            )
        }
        return AutoEQPreparedPreset(input: input, ten: result(10), thirtyOne: result(31))
    }

    private func waitForImport(_ state: AutoEQState, file: StaticString = #filePath, line: UInt = #line) async throws {
        for _ in 0..<500 {
            if !state.isImporting { return }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("Import did not finish", file: file, line: line)
    }

    private func waitForGate(_ gate: PreparationGate) async throws {
        for _ in 0..<500 {
            if await gate.started { return }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("Preparation did not start")
    }

    private func importPreset(_ state: AutoEQState, name: String = "first", autoApply: Bool = true) async throws {
        try state.startImport(input(), identity: identity(name), autoApply: autoApply, preservePlayback: false)
        try await waitForImport(state)
    }

    private func restoreDevice(
        _ state: AutoEQState,
        harness: Harness,
        uid: String,
        revision: UInt64,
        gains: [Float],
        name: String,
        bassBoost: Float = 0
    ) throws {
        harness.uid = uid
        let context = DevicePresetManager.OutputContext(outputUID: uid, revision: revision)
        state.outputChanged(context)
        harness.gains = gains
        harness.mode = gains.count == 10 ? .tenBand : .thirtyOneBand
        harness.preamp = -5
        let json = try String(decoding: JSONEncoder().encode(identity(name)), as: UTF8.self)
        defaults.set(json, forKey: "lastAppliedPresetJSON")
        state.devicePresetApplied(DevicePresetManager.AppliedPreset(
            context: context,
            record: DevicePresetRecord(
                mode: harness.mode.rawValue,
                appliedGains: gains,
                cleanGains: gains,
                preamp: -5,
                bassBoost: bassBoost,
                descriptorJSON: json
            )
        ))
    }

    func testSameModeDeviceSwitchAdoptsNewGainsAndIdentity() throws {
        let harness = Harness()
        let state = owner(harness)
        try restoreDevice(
            state,
            harness: harness,
            uid: "A",
            revision: 1,
            gains: Array(repeating: 1, count: 10),
            name: "A"
        )
        try restoreDevice(
            state,
            harness: harness,
            uid: "B",
            revision: 2,
            gains: Array(repeating: 3, count: 10),
            name: "B"
        )
        XCTAssertEqual(state.mapped.map(\.gain), Array(repeating: 3, count: 10))
        XCTAssertEqual(state.activePresetName, "B")
        XCTAssertEqual(state.preampDB, -5)
        XCTAssertEqual(harness.applyCount, 0)
    }

    func testSameDescriptorDeviceSwitchStillAdoptsDifferentGains() throws {
        let harness = Harness()
        let state = owner(harness)
        try restoreDevice(
            state,
            harness: harness,
            uid: "A",
            revision: 1,
            gains: Array(repeating: 1, count: 31),
            name: "same"
        )
        try restoreDevice(
            state,
            harness: harness,
            uid: "B",
            revision: 2,
            gains: Array(repeating: -2, count: 31),
            name: "same"
        )
        XCTAssertEqual(state.bandMode, .thirtyOne)
        XCTAssertEqual(state.mapped.map(\.gain), Array(repeating: -2, count: 31))
        XCTAssertEqual(harness.applyCount, 0)
    }

    func testFlatFallbackClearsOldIdentityAndBassWithoutApplyingAgain() throws {
        let harness = Harness()
        let state = owner(harness)
        try restoreDevice(
            state,
            harness: harness,
            uid: "A",
            revision: 1,
            gains: Array(repeating: 4, count: 10),
            name: "A",
            bassBoost: 2
        )
        harness.uid = "B"
        let context = DevicePresetManager.OutputContext(outputUID: "B", revision: 2)
        state.outputChanged(context)
        harness.gains = Array(repeating: 0, count: 10)
        harness.preamp = 0
        defaults.removeObject(forKey: "lastAppliedPresetJSON")
        state.devicePresetApplied(DevicePresetManager.AppliedPreset(context: context, record: nil))
        XCTAssertNil(state.appliedIdentity)
        XCTAssertNil(state.previewIdentity)
        XCTAssertTrue(state.parsed.isEmpty)
        XCTAssertEqual(state.bassBoost, 0)
        XCTAssertEqual(state.mapped.map(\.gain), Array(repeating: 0, count: 10))
        XCTAssertEqual(harness.applyCount, 0)
    }

    func testLatePreparationFromAPreventsReplayAfterSwitchToB() async throws {
        let harness = Harness()
        let gate = PreparationGate()
        let state = owner(harness, prepare: { _, _ in try await gate.prepare() })
        try state.startImport(input(), identity: identity("pending A"), autoApply: true, preservePlayback: false)
        try await waitForGate(gate)
        try restoreDevice(
            state,
            harness: harness,
            uid: "B",
            revision: 1,
            gains: Array(repeating: -2, count: 10),
            name: "B"
        )
        try await gate.complete(Self.prepared(input()))
        try await Task.sleep(nanoseconds: 10_000_000)
        XCTAssertEqual(state.activePresetName, "B")
        XCTAssertEqual(state.mapped.map(\.gain), Array(repeating: -2, count: 10))
        XCTAssertEqual(harness.applyCount, 0)
        XCTAssertFalse(state.isImporting)
    }

    func testPendingDebounceFromAPreventsReplayAfterSwitchToB() async throws {
        let harness = Harness()
        let state = owner(harness)
        try await importPreset(state)
        state.editBand(at: 0, gain: 7)
        state.scheduleApply(delay: 20_000_000)
        let before = harness.applyCount
        try restoreDevice(
            state,
            harness: harness,
            uid: "B",
            revision: 1,
            gains: Array(repeating: 2, count: 10),
            name: "B"
        )
        try await Task.sleep(nanoseconds: 40_000_000)
        XCTAssertEqual(harness.gains, Array(repeating: 2, count: 10))
        XCTAssertEqual(harness.applyCount, before)
    }

    func testDisabledAutoSwitchCancelsPendingWithoutChangingPlaybackIdentity() async throws {
        let harness = Harness()
        let state = owner(harness)
        try await importPreset(state)
        let original = harness.gains
        let originalIdentity = state.appliedIdentity
        let request = state.beginRequest()
        harness.uid = "B"
        state.outputChanged(DevicePresetManager.OutputContext(outputUID: "B", revision: 1))
        XCTAssertFalse(state.isCurrent(request))
        XCTAssertFalse(state.isImporting)
        XCTAssertEqual(harness.gains, original)
        XCTAssertEqual(state.appliedIdentity, originalIdentity)
        XCTAssertEqual(harness.applyCount, 1)
    }

    func testCancelledBassDraftUsesAppliedBassAfterCloseAndDisabledSwitch() async throws {
        for close in [true, false] {
            let harness = Harness()
            let state = owner(harness)
            try await importPreset(state)
            state.setBassBoost(2)
            XCTAssertTrue(state.apply())
            let playback = harness.gains
            let before = harness.applyCount
            state.setBassBoost(6)
            if close {
                state.close()
            } else {
                harness.uid = "B"
                state.outputChanged(DevicePresetManager.OutputContext(outputUID: "B", revision: 1))
            }
            try await Task.sleep(nanoseconds: 65_000_000)
            XCTAssertEqual(state.bassBoost, 2)
            XCTAssertEqual(harness.gains, playback)
            XCTAssertEqual(harness.applyCount, before)
            for gain in state.mapped.map(\.gain) {
                XCTAssertEqual(gain, 1, accuracy: 0.000001)
            }
        }
    }

    func testLostUIDOrChangedRateFinishesStaleFetchWithoutBusyState() {
        let harness = Harness()
        let state = owner(harness)
        var request = state.beginRequest()
        harness.uid = nil
        state.finishFetch(request)
        XCTAssertFalse(state.isImporting)
        XCTAssertFalse(state.isCurrent(request))
        harness.uid = "A"
        request = state.beginRequest()
        harness.rate = 96000
        state.finishFetch(request)
        XCTAssertFalse(state.isImporting)
        XCTAssertFalse(state.isCurrent(request))
    }

    func testNonfiniteRateCannotLeaveImportBusy() throws {
        let harness = Harness()
        harness.rate = .nan
        let state = owner(harness)
        try state.startImport(input(), identity: identity("invalid rate"), autoApply: true, preservePlayback: false)
        XCTAssertFalse(state.isImporting)
        XCTAssertNil(state.previewIdentity)
        XCTAssertEqual(harness.applyCount, 0)
    }

    func testNewRequestIsNotCancelledByOldFetchCompletion() {
        let harness = Harness()
        let state = owner(harness)
        let old = state.beginRequest()
        let current = state.beginRequest()
        state.finishFetch(old)
        XCTAssertTrue(state.isImporting)
        XCTAssertTrue(state.isCurrent(current))
        state.cancelPending()
    }

    func testManualChangeDuringFetchRequiresExplicitApply() async throws {
        let harness = Harness()
        let state = owner(harness)
        let request = state.beginRequest()
        harness.gains[0] = 6
        harness.preamp = -8
        try state.startImport(
            input(),
            identity: identity("new"),
            autoApply: true,
            preservePlayback: false,
            request: request
        )
        try await waitForImport(state)
        XCTAssertTrue(state.importNeedsApply)
        XCTAssertEqual(harness.gains[0], 6)
        XCTAssertEqual(harness.preamp, -8)
        XCTAssertNil(state.appliedIdentity)
        XCTAssertEqual(state.previewIdentity?.name, "new")
        XCTAssertTrue(state.apply())
        XCTAssertEqual(state.activePresetName, "new")
    }

    func testManualMappedEditCancelsPreparationAndKeepsUserGain() async throws {
        let harness = Harness()
        let gate = PreparationGate()
        let state = owner(harness, prepare: { _, _ in try await gate.prepare() })
        try state.startImport(input(), identity: identity("pending"), autoApply: true, preservePlayback: false)
        try await waitForGate(gate)
        state.editBand(at: 0, gain: 6)
        XCTAssertFalse(state.isImporting)
        try await gate.complete(Self.prepared(input()))
        try await Task.sleep(nanoseconds: 45_000_000)
        XCTAssertEqual(harness.gains[0], 6)
        XCTAssertNil(state.appliedIdentity)
        XCTAssertNil(state.previewIdentity)
        XCTAssertEqual(harness.applyCount, 1)
    }

    func testManualBassEditCancelsPreparationAndDoesNotAdoptPendingIdentity() async throws {
        let harness = Harness()
        let gate = PreparationGate()
        let state = owner(harness, prepare: { _, _ in try await gate.prepare() })
        try state.startImport(input(), identity: identity("pending"), autoApply: true, preservePlayback: false)
        try await waitForGate(gate)
        state.setBassBoost(3)
        try await gate.complete(Self.prepared(input()))
        try await Task.sleep(nanoseconds: 65_000_000)
        XCTAssertEqual(state.bassBoost, 3)
        XCTAssertNil(state.appliedIdentity)
        XCTAssertNil(state.previewIdentity)
        XCTAssertGreaterThan(harness.gains[0], 2)
        XCTAssertEqual(harness.applyCount, 1)
    }

    func testRequiresApplyMetadataDoesNotBlockSafeAutoapply() async throws {
        let harness = Harness()
        let state = owner(harness, prepare: { Self.prepared($0, rate: $1, requiresReview: true) })
        try await importPreset(state)
        XCTAssertTrue(try XCTUnwrap(state.preparedImport).ten.requiresApply)
        XCTAssertFalse(state.importNeedsApply)
        XCTAssertEqual(harness.gains, Array(repeating: 1, count: 10))
        XCTAssertEqual(state.activePresetName, "first")
    }

    func testDisabledModeChangeUpdatesEngineModeWithoutApplyingOrEnabling() async throws {
        let harness = Harness()
        let state = owner(harness)
        try await importPreset(state)
        harness.enabled = false
        let before = harness.applyCount
        state.selectBandMode(.thirtyOne)
        XCTAssertEqual(harness.mode, .thirtyOneBand)
        XCTAssertEqual(state.bandMode, .thirtyOne)
        XCTAssertEqual(state.mapped.count, 31)
        XCTAssertTrue(state.importNeedsApply)
        XCTAssertFalse(harness.enabled)
        XCTAssertEqual(harness.applyCount, before)
        harness.gains = Array(repeating: 2, count: 31)
        state.synchronizePlayback()
        XCTAssertEqual(state.mapped.map(\.gain), Array(repeating: 1, count: 31))
        XCTAssertTrue(state.apply())
        XCTAssertEqual(harness.gains, Array(repeating: 1, count: 31))
        XCTAssertTrue(harness.enabled)
    }

    func testModeChangeCannotBypassExistingManualConflictReview() async throws {
        let harness = Harness()
        let state = owner(harness)
        let request = state.beginRequest()
        harness.gains[0] = 8
        try state.startImport(
            input(),
            identity: identity("pending"),
            autoApply: true,
            preservePlayback: false,
            request: request
        )
        try await waitForImport(state)
        XCTAssertTrue(state.importNeedsApply)
        state.selectBandMode(.thirtyOne)
        XCTAssertEqual(state.mapped.count, 31)
        XCTAssertTrue(state.importNeedsApply)
        XCTAssertEqual(harness.gains[0], 8)
        XCTAssertEqual(harness.applyCount, 0)
        XCTAssertNil(state.appliedIdentity)
    }

    func testModeHeadroomFailureKeepsMatchingPreviewBandCount() async throws {
        let harness = Harness()
        let state = owner(harness)
        try await importPreset(state)
        harness.limit = nil
        let before = harness.applyCount
        state.selectBandMode(.thirtyOne)
        XCTAssertEqual(harness.mode, .thirtyOneBand)
        XCTAssertEqual(state.bandMode, .thirtyOne)
        XCTAssertEqual(state.mapped.count, 31)
        XCTAssertTrue(state.importNeedsApply)
        XCTAssertEqual(state.importError, .insufficientHeadroom)
        XCTAssertEqual(harness.applyCount, before)
        XCTAssertEqual(state.activePresetName, "first")
    }

    func testFailedApplyKeepsAppliedIdentityAndPersistenceWhilePreviewIsSeparate() async throws {
        let harness = Harness()
        let state = owner(harness)
        try await importPreset(state)
        let descriptor = defaults.string(forKey: "lastAppliedPresetJSON")
        try await importPreset(state, name: "preview", autoApply: false)
        harness.limit = nil
        XCTAssertFalse(state.apply())
        XCTAssertEqual(state.activePresetName, "first")
        XCTAssertEqual(state.previewIdentity?.name, "preview")
        XCTAssertEqual(defaults.string(forKey: "lastAppliedPresetJSON"), descriptor)
        XCTAssertEqual(harness.applyCount, 1)
        XCTAssertEqual(harness.records.count, 1)
    }

    func testFailedPreparationKeepsAppliedAndEditableState() async throws {
        let harness = Harness()
        let state = owner(harness, prepare: { input, rate in
            if input.preamp == -10 { throw AutoEQImportError.invalidSource }
            return Self.prepared(input, rate: rate)
        })
        try await importPreset(state)
        let before = state.mapped.map(\.gain)
        let invalid = try AutoEQImportParser.parse("Preamp: -10 dB")
        state.startImport(invalid, identity: identity("bad"), autoApply: true, preservePlayback: false)
        try await waitForImport(state)
        XCTAssertEqual(state.activePresetName, "first")
        XCTAssertEqual(state.previewIdentity?.name, "first")
        XCTAssertEqual(state.mapped.map(\.gain), before)
        XCTAssertEqual(state.importError, .invalidSource)
    }

    func testCloseCancelsLateImportAndRestoresAppliedPreview() async throws {
        let harness = Harness()
        let gate = PreparationGate()
        let state = owner(harness, prepare: { _, _ in try await gate.prepare() })
        try state.startImport(input(), identity: identity("late"), autoApply: true, preservePlayback: false)
        try await waitForGate(gate)
        state.close()
        try await gate.complete(Self.prepared(input()))
        try await Task.sleep(nanoseconds: 10_000_000)
        XCTAssertNil(state.appliedIdentity)
        XCTAssertNil(state.previewIdentity)
        XCTAssertFalse(state.isImporting)
        XCTAssertEqual(harness.applyCount, 0)
    }

    func testDeferredFetchAndPreparationCannotStartAfterCloseOrReopen() async throws {
        let harness = Harness()
        let state = owner(harness)
        let oldSession = state.open()
        state.close()
        XCTAssertFalse(state.isOpen(oldSession))
        var started = false
        await state.fetch(session: oldSession) { _ in started = true }
        XCTAssertFalse(started)
        try state.startImport(input(), identity: identity("closed"), autoApply: true, preservePlayback: false)
        XCTAssertFalse(state.isImporting)
        let newSession = state.open()
        XCTAssertNotEqual(oldSession, newSession)
        await state.fetch(session: oldSession) { _ in started = true }
        XCTAssertFalse(started)
        XCTAssertNil(state.previewIdentity)
        try await importPreset(state, name: "current session")
        XCTAssertEqual(state.activePresetName, "current session")
        XCTAssertEqual(harness.applyCount, 1)
    }

    func testExternalResetCancelsUnappliedBassDraftAndSynchronizesPlayback() async throws {
        let harness = Harness()
        let state = owner(harness)
        try await importPreset(state)
        state.setBassBoost(2)
        XCTAssertTrue(state.apply())
        state.setBassBoost(6)
        harness.gains = harness.gains.map { $0 - 0.5 }
        harness.preamp = -9
        state.synchronizePlayback()
        let resetGains = harness.gains
        let before = harness.applyCount
        try await Task.sleep(nanoseconds: 65_000_000)
        XCTAssertEqual(harness.gains, resetGains)
        XCTAssertEqual(harness.applyCount, before)
        XCTAssertEqual(state.bassBoost, 2)
        XCTAssertEqual(state.preampDB, -9)
        for gain in state.mapped.map(\.gain) {
            XCTAssertEqual(gain, 0.5, accuracy: 0.000001)
        }
    }

    func testSampleRateChangeRejectsLateImportAndDebounce() async throws {
        let harness = Harness()
        let gate = PreparationGate()
        let state = owner(harness, prepare: { _, _ in try await gate.prepare() })
        try state.startImport(input(), identity: identity("old rate"), autoApply: true, preservePlayback: false)
        try await waitForGate(gate)
        harness.rate = 96000
        try await gate.complete(Self.prepared(input(), rate: 48000))
        try await waitForImport(state)
        XCTAssertNil(state.previewIdentity)
        XCTAssertEqual(harness.applyCount, 0)
        state.scheduleApply(delay: 10_000_000)
        harness.rate = 48000
        try await Task.sleep(nanoseconds: 25_000_000)
        XCTAssertEqual(harness.applyCount, 0)
    }

    func testBassDoesNotAccumulateInEitherModeOrAfterReopen() async throws {
        for mode in [AutoEQState.BandMode.ten, .thirtyOne] {
            let harness = Harness()
            harness.mode = mode.audioEngineMode
            harness.gains = Array(repeating: 0, count: mode.audioEngineMode.bandCount)
            let state = owner(harness)
            try await importPreset(state)
            state.setBassBoost(3)
            XCTAssertTrue(state.apply())
            let once = harness.gains
            XCTAssertTrue(state.apply())
            XCTAssertEqual(harness.gains, once)
            XCTAssertEqual(harness.saved.last?.1, Array(repeating: 1, count: mode.audioEngineMode.bandCount))
            state.close()
            state.open()
            XCTAssertTrue(state.apply())
            XCTAssertEqual(harness.gains, once)
            XCTAssertEqual(state.activePresetName, "first")
            XCTAssertEqual(harness.saved.last?.1.count, mode.audioEngineMode.bandCount)
        }
    }

    func testForeignAndOldDeviceEventsCannotReplaceCurrentContext() throws {
        let harness = Harness()
        let state = owner(harness)
        try restoreDevice(
            state,
            harness: harness,
            uid: "B",
            revision: 2,
            gains: Array(repeating: 3, count: 10),
            name: "B"
        )
        state.outputChanged(DevicePresetManager.OutputContext(outputUID: "A", revision: 3))
        state.devicePresetApplied(DevicePresetManager.AppliedPreset(
            context: DevicePresetManager.OutputContext(outputUID: "B", revision: 1), record: nil
        ))
        XCTAssertEqual(state.activePresetName, "B")
        XCTAssertEqual(state.mapped.map(\.gain), Array(repeating: 3, count: 10))
    }

    func testRepeatedApplyAndImportBeforeDeviceEventCannotSaveOldStateToNewOutput() async throws {
        for withContext in [false, true] {
            let harness = Harness()
            let state = owner(harness)
            if withContext {
                state.outputChanged(DevicePresetManager.OutputContext(outputUID: "A", revision: 1))
            }
            try await importPreset(state)
            let before = harness.applyCount
            harness.uid = "B"
            XCTAssertFalse(state.apply())
            XCTAssertFalse(state.apply())
            state.close()
            state.open()
            XCTAssertFalse(state.apply())
            try state.startImport(input(), identity: identity("stale B"), autoApply: true, preservePlayback: false)
            XCTAssertFalse(state.isImporting)
            XCTAssertEqual(harness.applyCount, before)
            XCTAssertEqual(harness.records.count, 1)
            XCTAssertEqual(harness.records.first?.1, "A")
            try restoreDevice(
                state,
                harness: harness,
                uid: "B",
                revision: 2,
                gains: Array(repeating: 2, count: 10),
                name: "B"
            )
            XCTAssertTrue(state.apply())
            XCTAssertEqual(harness.records.last?.1, "B")
            XCTAssertEqual(harness.records.last?.0.appliedGains, Array(repeating: 2, count: 10))
        }
    }

    func testHeadroomFailureNeverEnablesOrPersistsPendingPreset() async throws {
        let harness = Harness()
        harness.limit = nil
        harness.enabled = false
        let state = owner(harness)
        try await importPreset(state)
        XCTAssertEqual(state.importError, .insufficientHeadroom)
        XCTAssertNil(state.previewIdentity)
        XCTAssertNil(state.appliedIdentity)
        XCTAssertTrue(harness.saved.isEmpty)
        XCTAssertTrue(harness.records.isEmpty)
        XCTAssertFalse(harness.enabled)
        XCTAssertEqual(harness.applyCount, 0)
    }
}
