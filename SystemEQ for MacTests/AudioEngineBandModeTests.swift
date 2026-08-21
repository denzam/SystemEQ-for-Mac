//
//  AudioEngineBandModeTests.swift
//  SystemEQ for MacTests
//
//  Regression tests for applying EQ values right after a band-mode switch:
//  bandMode's didSet rebuilds `bands` only on the next main-loop turn, so a
//  same-turn applyEQValues used to see the stale array and bail out.
//

import CoreAudio
@testable import SystemEQ_for_Mac
import XCTest

final class AudioEngineBandModeTests: XCTestCase {
    override func tearDown() {
        let engine = AudioEngine.shared
        engine.bandMode = .tenBand
        engine.syncBandsToMode()
        engine.setPreampGain(0)
        engine.setOutputBoostGain(0)
        engine.resetAllBands()
        CoreAudioEngine.shared.setEnabled(false)
        super.tearDown()
    }

    // MARK: - Same-turn mode switch + apply

    func testApplyEQValues_rightAfterSwitchTo31Band_appliesAll31() {
        let engine = AudioEngine.shared
        engine.bandMode = .tenBand
        engine.syncBandsToMode()

        let values = (0..<31).map { Float($0 % 5) - 2 }

        // Same main-loop turn as the mode switch — the didSet rebuild has not run yet
        engine.bandMode = .thirtyOneBand
        engine.applyEQValues(values)

        XCTAssertEqual(engine.bands.count, 31, "bands must be rebuilt before applying")
        XCTAssertEqual(engine.bands.map(\.gain), values, "all 31 gains must be applied")
    }

    func testApplyEQValues_rightAfterSwitchBackTo10Band_appliesAll10() {
        let engine = AudioEngine.shared
        engine.bandMode = .thirtyOneBand
        engine.syncBandsToMode()

        let values: [Float] = [1, -1, 2, -2, 3, -3, 4, -4, 5, -5]

        engine.bandMode = .tenBand
        engine.applyEQValues(values)

        XCTAssertEqual(engine.bands.count, 10, "bands must be rebuilt before applying")
        XCTAssertEqual(engine.bands.map(\.gain), values, "all 10 gains must be applied")
    }

    func testApplyEQValues_countMismatch_stillRejected() {
        let engine = AudioEngine.shared
        engine.bandMode = .tenBand
        engine.syncBandsToMode()
        engine.resetAllBands()

        engine.applyEQValues([1, 2, 3])

        XCTAssertEqual(engine.bands.map(\.gain), Array(repeating: Float(0), count: 10))
    }

    func testSetPreampGainRebuildsTheActiveFilter() throws {
        let suiteName = "AudioEngineBandModeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let engine = AudioEngine(
            defaults: defaults,
            enableRouting: { _ in true },
            disableRouting: { _ in }
        )
        engine.resetAllBands()
        engine.setPreampGain(0)
        engine.setPreampGain(6)

        let filter = try XCTUnwrap(CoreAudioEngine.shared.vdspFilter)
        var left = [Float](repeating: 0.25, count: 64)
        var right = [Float](repeating: 0.25, count: 64)
        let frameCount = left.count
        left.withUnsafeMutableBufferPointer { leftBuffer in
            right.withUnsafeMutableBufferPointer { rightBuffer in
                guard let leftAddress = leftBuffer.baseAddress,
                      let rightAddress = rightBuffer.baseAddress else { return }
                filter.processStereo(leftAddress, rightAddress, frameCount: frameCount)
            }
        }

        XCTAssertEqual(left[0], Float(0.25 * pow(10.0, 6.0 / 20.0)), accuracy: 0.0001)
        XCTAssertEqual(right[0], Float(0.25 * pow(10.0, 6.0 / 20.0)), accuracy: 0.0001)
    }

    func testOutputBoostIsClampedAndPersisted() throws {
        let suiteName = "AudioEngineBandModeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let engine = AudioEngine(
            defaults: defaults,
            enableRouting: { _ in true },
            disableRouting: { _ in }
        )

        engine.setOutputBoostGain(10)

        XCTAssertEqual(engine.outputBoostGain, 3)
        XCTAssertEqual(defaults.float(forKey: "outputBoostGain"), 3)
    }

    // MARK: - CoreAudioEngine guard rails

    // Раніше frequencies[index] за масивом з 31 значення падав out-of-bounds.
    func testApplyFixedBandEQ_oversizedGains_doesNotCrash() {
        let gains = [Float](repeating: 1.0, count: 31)

        CoreAudioEngine.shared.applyFixedBandEQ(gains, preamp: 0)

        // Повернути конфіг у чистий 10-band стан
        CoreAudioEngine.shared.applyFixedBandEQ([Float](repeating: 0, count: 10), preamp: 0)
    }

    // MARK: - Startup state persistence

    func testSetEnabled_routingFailureWithoutPersistence_preservesIntent() throws {
        let suiteName = "AudioEngineBandModeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: "eqWasEnabled")
        var routerPersistence: Bool?
        let engine = AudioEngine(
            defaults: defaults,
            enableRouting: {
                routerPersistence = $0
                return false
            },
            disableRouting: { _ in }
        )

        let succeeded = engine.setEnabled(true, persistState: false)

        XCTAssertFalse(succeeded)
        XCTAssertEqual(routerPersistence, false)
        XCTAssertTrue(defaults.bool(forKey: "eqWasEnabled"))
        XCTAssertFalse(CoreAudioEngine.shared.isEnabled)
    }

    func testSetEnabled_routingFailureFromUserAction_disablesFutureRestore() throws {
        let suiteName = "AudioEngineBandModeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: "eqWasEnabled")
        let engine = AudioEngine(
            defaults: defaults,
            enableRouting: { _ in false },
            disableRouting: { _ in }
        )

        let succeeded = engine.setEnabled(true, persistState: true)

        XCTAssertFalse(succeeded)
        XCTAssertFalse(defaults.bool(forKey: "eqWasEnabled"))
        XCTAssertFalse(CoreAudioEngine.shared.isEnabled)
    }

    func testSetEnabled_routingSuccessFromUserAction_persistsEnabledState() throws {
        let suiteName = "AudioEngineBandModeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(false, forKey: "eqWasEnabled")
        var routerPersistence: Bool?
        let engine = AudioEngine(
            defaults: defaults,
            enableRouting: {
                routerPersistence = $0
                return true
            },
            disableRouting: { _ in }
        )

        let succeeded = engine.setEnabled(true, persistState: true)

        XCTAssertTrue(succeeded)
        XCTAssertEqual(routerPersistence, false)
        XCTAssertTrue(defaults.bool(forKey: "eqWasEnabled"))
        XCTAssertTrue(CoreAudioEngine.shared.isEnabled)
    }

    func testRoutingControlsDelegateToAudioEngine() throws {
        let suiteName = "AudioEngineBandModeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var enableRequests: [Bool] = []
        var disableRequests: [Bool] = []
        let engine = AudioEngine(
            defaults: defaults,
            enableRouting: {
                enableRequests.append($0)
                return true
            },
            disableRouting: { disableRequests.append($0) }
        )

        RoutingView.setEQEnabled(true, engine: engine)
        RoutingView.setEQEnabled(false, engine: engine)

        XCTAssertEqual(enableRequests, [false])
        XCTAssertEqual(disableRequests, [false])
        XCTAssertFalse(CoreAudioEngine.shared.isEnabled)
    }

    func testSetEnabled_reappliesFiltersAfterRoutingStarts() throws {
        let suiteName = "AudioEngineBandModeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let engine = AudioEngine(
            defaults: defaults,
            enableRouting: { _ in
                CoreAudioEngine.shared.clearEQ()
                return true
            },
            disableRouting: { _ in }
        )
        engine.setPreampGain(6)

        XCTAssertTrue(engine.setEnabled(true))

        let filter = try XCTUnwrap(CoreAudioEngine.shared.vdspFilter)
        var left = [Float](repeating: 0.25, count: 64)
        var right = [Float](repeating: 0.25, count: 64)
        let frameCount = left.count
        left.withUnsafeMutableBufferPointer { leftBuffer in
            right.withUnsafeMutableBufferPointer { rightBuffer in
                guard let leftAddress = leftBuffer.baseAddress,
                      let rightAddress = rightBuffer.baseAddress else { return }
                filter.processStereo(leftAddress, rightAddress, frameCount: frameCount)
            }
        }

        XCTAssertEqual(left[0], Float(0.25 * pow(10.0, 6.0 / 20.0)), accuracy: 0.0001)
        XCTAssertEqual(right[0], Float(0.25 * pow(10.0, 6.0 / 20.0)), accuracy: 0.0001)
    }

    func testManualBandChangePersistsPlaybackState() throws {
        let suiteName = "AudioEngineBandModeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let engine = AudioEngine(
            defaults: defaults,
            enableRouting: { _ in true },
            disableRouting: { _ in }
        )
        let persisted = expectation(description: "manual band gain persisted")

        engine.updateBandGain(bandId: 3, gain: 4.5)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            let playback = PresetPersistence.loadPlaybackState(in: defaults)
            XCTAssertEqual(playback?.mode, .tenBand)
            XCTAssertEqual(playback?.gains[3], 4.5)
            XCTAssertEqual(playback?.preamp, 0)
            persisted.fulfill()
        }

        wait(for: [persisted], timeout: 1)
    }

    func testSetEnabled_startupDisable_preservesSavedIntent() throws {
        let suiteName = "AudioEngineBandModeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: "eqWasEnabled")
        var routerPersistence: Bool?
        let engine = AudioEngine(
            defaults: defaults,
            enableRouting: { _ in true },
            disableRouting: { routerPersistence = $0 }
        )

        let succeeded = engine.setEnabled(false, persistState: false)

        XCTAssertTrue(succeeded)
        XCTAssertEqual(routerPersistence, false)
        XCTAssertTrue(defaults.bool(forKey: "eqWasEnabled"))
        XCTAssertFalse(CoreAudioEngine.shared.isEnabled)
    }

    func testOutputVolumeTransferCopiesAvailableState() {
        let state = OutputVolumeState(scalar: 0.75, isMuted: true)
        var readDevice: AudioDeviceID?
        var writtenState: OutputVolumeState?
        var writtenDevice: AudioDeviceID?

        let transferred = OutputVolumeTransfer.transfer(
            from: 1,
            to: 2,
            read: {
                readDevice = $0
                return state
            },
            write: {
                writtenState = $0
                writtenDevice = $1
                return true
            }
        )

        XCTAssertTrue(transferred)
        XCTAssertEqual(readDevice, 1)
        XCTAssertEqual(writtenState, state)
        XCTAssertEqual(writtenDevice, 2)
    }

    func testOutputVolumeTransferSkipsMissingState() {
        var didWrite = false
        let transferred = OutputVolumeTransfer.transfer(
            from: 1,
            to: 2,
            read: { _ in nil },
            write: { _, _ in
                didWrite = true
                return true
            }
        )

        XCTAssertFalse(transferred)
        XCTAssertFalse(didWrite)
    }

    func testOutputVolumeTransferUsesFallbackForFixedVolumeDevice() {
        let fallback = OutputVolumeState(scalar: 1, isMuted: nil)
        var writtenState: OutputVolumeState?

        let transferred = OutputVolumeTransfer.transfer(
            from: 1,
            to: 2,
            read: { _ in nil },
            write: { state, _ in
                writtenState = state
                return true
            },
            fallback: fallback
        )

        XCTAssertTrue(transferred)
        XCTAssertEqual(writtenState, fallback)
    }

    func testBlackHoleInputVolumeChangeRestoresExpectedOutput() {
        guard case .restoreExpected = BlackHoleVolumeChangePolicy.action(
            for: [kAudioObjectPropertyScopeInput]
        ) else {
            return XCTFail("Input-only changes must restore the expected output volume")
        }
    }

    func testBlackHoleOutputVolumeChangeAcceptsKeyboardAdjustment() {
        guard case .acceptObserved = BlackHoleVolumeChangePolicy.action(
            for: [kAudioObjectPropertyScopeOutput]
        ) else {
            return XCTFail("Output changes must become the new expected volume")
        }
        guard case .acceptObserved = BlackHoleVolumeChangePolicy.action(
            for: [kAudioObjectPropertyScopeInput, kAudioObjectPropertyScopeOutput]
        ) else {
            return XCTFail("Output changes must win when both scopes are reported")
        }
    }

    func testBlackHoleRecoveryWritesOnlyChangedProperties() {
        guard let expected = OutputVolumeState(scalar: 1, isMuted: false),
              let volumeOnlyChange = OutputVolumeState(scalar: 0.226, isMuted: false),
              let muteOnlyChange = OutputVolumeState(scalar: 1, isMuted: true) else {
            return XCTFail("Finite volume states must be valid")
        }

        XCTAssertTrue(BlackHoleVolumeChangePolicy.needsVolumeWrite(from: volumeOnlyChange, to: expected))
        XCTAssertFalse(BlackHoleVolumeChangePolicy.needsMuteWrite(from: volumeOnlyChange, to: expected))
        XCTAssertFalse(BlackHoleVolumeChangePolicy.needsVolumeWrite(from: muteOnlyChange, to: expected))
        XCTAssertTrue(BlackHoleVolumeChangePolicy.needsMuteWrite(from: muteOnlyChange, to: expected))
    }

    func testPeakMeterAndRoutingMeterDiscardNonFiniteValues() {
        XCTAssertEqual(PeakMeter.sanitizedPeak(.nan), 0)
        XCTAssertEqual(PeakMeter.sanitizedPeak(-0.25), 0)
        XCTAssertEqual(RoutingView.normalizedPeak(.infinity), 0)

        let smoothedPeak = RoutingView.nextSmoothedPeak(
            current: .nan,
            incoming: 0.25,
            smoothingFactor: 0.3
        )

        XCTAssertTrue(smoothedPeak.isFinite)
        XCTAssertEqual(smoothedPeak, 0.25)
    }

    func testRoutingMeterTreatsDecayedSilenceAsZero() {
        XCTAssertEqual(RoutingView.normalizedPeak(0.00005), 0)
        XCTAssertEqual(RoutingView.nextSmoothedPeak(current: 0.00005, incoming: 0, smoothingFactor: 0.3), 0)
    }

    func testDiagnosticEventStoreKeepsOnlyNewestEvents() {
        let store = DiagnosticEventStore(capacity: 2)
        store.record("routing.enable.request", details: ["outputKind": "usbAudio"])
        store.record("routing.volumeTransfer", details: ["requestedScalar": "1.000"])
        store.record("engine.start.succeeded")

        let events = store.snapshot()

        XCTAssertEqual(events.map(\.name), ["routing.volumeTransfer", "engine.start.succeeded"])
        XCTAssertFalse(store.reportText().contains("routing.enable.request"))
        XCTAssertTrue(store.reportText().contains("requestedScalar=1.000"))
    }
}
