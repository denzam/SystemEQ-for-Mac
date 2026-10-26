import AppKit
import Combine
import CoreAudio
@testable import SystemEQ_for_Mac
import XCTest

@MainActor
final class NativeVolumeControlTests: XCTestCase {
    private final class HUD: NativeVolumeHUDPresenting {
        var states: [NativeVolumeState] = []
        var hides = 0

        func show(state: NativeVolumeState) {
            states.append(state)
        }
        func hide() {
            hides += 1
        }
    }

    private final class Capture: NativeMediaKeyCapturing {
        var allowed = true
        var isEnabled = false
        var enabledAfterStart: Bool?
        var eventHandlers: [(NativeMediaKeyEvent) -> Bool] = []
        var stopped = 0

        var handlers: [(Int, Bool) -> Bool] {
            eventHandlers.map { callback in
                { key, isDown in callback(.init(key: key, isDown: isDown, isRepeat: false)) }
            }
        }

        func start(handler: @escaping (NativeMediaKeyEvent) -> Bool) -> Bool {
            eventHandlers.append(handler)
            isEnabled = enabledAfterStart ?? allowed
            return allowed
        }

        func stop() {
            stopped += 1
            isEnabled = false
        }
    }

    func testHUDOnlyFollowsAcceptedKeyPressesAndHidesOnStop() throws {
        let name = "NativeVolumeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let capture = Capture()
        let hud = HUD()
        var current = true
        let control = NativeVolumeControl(
            defaults: defaults, capture: capture, isCurrentOutput: { _ in current },
            isTrusted: { true }, retryScheduler: { _ in AnyCancellable {} }, recordStatus: { _ in }, hud: hud
        )
        _ = control.prepare(outputID: 1, uid: "fixture", needsSoftwareVolume: true)
        control.activate { _ in }
        let handler = try XCTUnwrap(capture.eventHandlers.first)
        XCTAssertTrue(hud.states.isEmpty)
        XCTAssertTrue(handler(.init(key: 1, isDown: false, isRepeat: false)))
        XCTAssertFalse(handler(.init(key: 99, isDown: true, isRepeat: false)))
        current = false
        XCTAssertFalse(handler(.init(key: 1, isDown: true, isRepeat: false)))
        XCTAssertTrue(hud.states.isEmpty)
        current = true
        XCTAssertTrue(handler(.init(key: 1, isDown: true, isRepeat: false)))
        XCTAssertEqual(hud.states.last?.level, 0.9375)
        XCTAssertTrue(handler(.init(key: 7, isDown: true, isRepeat: false)))
        XCTAssertTrue(hud.states.last?.isMuted == true)
        XCTAssertTrue(handler(.init(key: 7, isDown: true, isRepeat: true)))
        XCTAssertEqual(hud.states.count, 2)
        let hides = hud.hides
        control.stop()
        XCTAssertEqual(hud.hides, hides + 1)
        XCTAssertFalse(handler(.init(key: 1, isDown: true, isRepeat: false)))
        XCTAssertEqual(hud.states.count, 2)
    }

    func testHUDDoesNotAppearOnFailedCaptureOrManualStateChanges() throws {
        let name = "NativeVolumeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let capture = Capture()
        capture.allowed = false
        let hud = HUD()
        let control = NativeVolumeControl(
            defaults: defaults, capture: capture, isCurrentOutput: { _ in true },
            isTrusted: { true }, retryScheduler: { _ in AnyCancellable {} }, recordStatus: { _ in }, hud: hud
        )
        _ = control.prepare(outputID: 1, uid: "fixture", needsSoftwareVolume: true)
        control.activate { _ in }
        XCTAssertFalse(capture.handlers.last?(1, true) == true)
        control.setLevel(0.5)
        control.toggleMute()
        XCTAssertTrue(hud.states.isEmpty)
        _ = control.prepare(outputID: 2, uid: "hardware", needsSoftwareVolume: false)
        control.activate { _ in XCTFail("Hardware volume must not start software capture") }
        XCTAssertTrue(hud.states.isEmpty)
    }

    func testHUDHidesForReplacementOutputAndRejectsOldKeyHandler() throws {
        let name = "NativeVolumeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let capture = Capture()
        let hud = HUD()
        let control = NativeVolumeControl(
            defaults: defaults, capture: capture, isCurrentOutput: { _ in true },
            isTrusted: { true }, retryScheduler: { _ in AnyCancellable {} }, recordStatus: { _ in }, hud: hud
        )
        _ = control.prepare(outputID: 1, uid: "A", needsSoftwareVolume: true)
        control.activate { _ in }
        let old = try XCTUnwrap(capture.handlers.last)
        XCTAssertTrue(old(1, true))
        let hides = hud.hides
        _ = control.prepare(outputID: 2, uid: "B", needsSoftwareVolume: true)
        control.activate { _ in }
        XCTAssertEqual(hud.hides, hides + 1)
        XCTAssertFalse(old(1, true))
        XCTAssertEqual(hud.states.count, 1)
        XCTAssertTrue(capture.handlers.last?(0, true) == true)
        XCTAssertEqual(hud.states.count, 2)
    }

    func testLevelLimitsMuteAndInvalidValuesCannotAmplify() {
        for value: Float in [-1, 0, 0.5, 1, 2, .nan, .infinity, -.infinity] {
            var state = NativeVolumeState(level: value)
            XCTAssertTrue(state.gain.isFinite)
            XCTAssertTrue((0...1).contains(state.gain))
            state.handle(key: 7)
            XCTAssertEqual(state.gain, 0)
            state.handle(key: 7)
            XCTAssertTrue(state.gain.isFinite)
            state.setLevel(.nan)
            XCTAssertEqual(state.gain, 0)
        }
        var state = NativeVolumeState(level: 0.5)
        state.handle(key: 0)
        XCTAssertEqual(state.level, 0.5625)
        state.handle(key: 1)
        XCTAssertEqual(state.level, 0.5)
        state.handle(key: 99)
        XCTAssertEqual(state.level, 0.5)
    }

    func testFailedCaptureCannotConsumeKeysAndStopDisablesInput() throws {
        let name = "NativeVolumeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let capture = Capture()
        capture.allowed = false
        var statuses: [String] = []
        let control = NativeVolumeControl(
            defaults: defaults, capture: capture, isCurrentOutput: { _ in true },
            isTrusted: { true }, retryScheduler: { _ in AnyCancellable {} }, recordStatus: { statuses.append($0) },
            hud: HUD()
        )
        XCTAssertEqual(control.prepare(outputID: 1, uid: "fixture", needsSoftwareVolume: true), 1)
        var gains: [Float] = []
        control.activate { gains.append($0) }
        XCTAssertFalse(control.keyboardEnabled)
        XCTAssertEqual(control.keyboardStatus, .captureUnavailable)
        for _ in 0..<4 {
            control.pollKeyboardCapture()
        }
        XCTAssertEqual(statuses, ["captureUnavailable"])
        XCTAssertFalse(capture.handlers[0](1, true))
        control.setLevel(0.5)
        XCTAssertEqual(gains.last, 0.25)
        control.stop()
        let count = gains.count
        XCTAssertFalse(capture.handlers[0](0, true))
        control.setLevel(1)
        XCTAssertEqual(gains.count, count)
        XCTAssertFalse(control.isAvailable)
    }

    func testKeyReleaseWrongOutputAndStaleCaptureCannotChangeVolume() throws {
        let name = "NativeVolumeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let capture = Capture()
        var current = true
        let control = NativeVolumeControl(
            defaults: defaults, capture: capture, isCurrentOutput: { _ in current },
            isTrusted: { true }, retryScheduler: { _ in AnyCancellable {} }, recordStatus: { _ in }, hud: HUD()
        )
        _ = control.prepare(outputID: 1, uid: "fixture", needsSoftwareVolume: true)
        var gains: [Float] = []
        control.activate { gains.append($0) }
        let old = try XCTUnwrap(capture.handlers.first)
        XCTAssertTrue(old(1, false))
        XCTAssertEqual(control.state.level, 1)
        XCTAssertFalse(old(99, true))
        current = false
        XCTAssertFalse(old(1, true))
        XCTAssertEqual(gains.count, 1)
        current = true
        control.refreshKeyboardCapture()
        XCTAssertFalse(old(1, true))
        XCTAssertTrue(capture.handlers.last?(1, true) == true)
        XCTAssertEqual(control.state.level, 0.9375)
    }

    func testRestartRestoresGainBeforeActivationAndDevicesKeepSeparateState() throws {
        let name = "NativeVolumeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let capture = Capture()
        let control = NativeVolumeControl(
            defaults: defaults, capture: capture, isCurrentOutput: { _ in true },
            isTrusted: { true }, retryScheduler: { _ in AnyCancellable {} }, recordStatus: { _ in }, hud: HUD()
        )
        _ = control.prepare(outputID: 1, uid: "A", needsSoftwareVolume: true)
        control.activate { _ in }
        control.setLevel(0.5)
        control.toggleMute()
        XCTAssertEqual(control.prepare(outputID: 1, uid: "A", needsSoftwareVolume: true), 0)
        XCTAssertEqual(control.state.level, 0.5)
        XCTAssertTrue(control.state.isMuted)
        XCTAssertEqual(control.prepare(outputID: 2, uid: "B", needsSoftwareVolume: true), 1)
        XCTAssertEqual(control.prepare(outputID: 1, uid: "A", needsSoftwareVolume: true), 0)
        XCTAssertEqual(control.prepare(outputID: 3, uid: "hardware", needsSoftwareVolume: false), 1)
        control.activate { _ in XCTFail("Hardware volume must bypass software capture") }
        XCTAssertFalse(control.isAvailable)
        XCTAssertFalse(control.keyboardEnabled)
    }

    func testPermissionGrantRetriesWithoutApplicationActivationAndStopCancelsPolling() throws {
        let name = "NativeVolumeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let capture = Capture()
        var trusted = false
        var retry: (() -> Void)?
        var cancellations = 0
        let control = NativeVolumeControl(
            defaults: defaults, capture: capture, isCurrentOutput: { _ in true },
            isTrusted: { trusted }, retryScheduler: { action in
                retry = action
                return AnyCancellable { cancellations += 1 }
            }, recordStatus: { _ in }, hud: HUD()
        )
        _ = control.prepare(outputID: 1, uid: "fixture", needsSoftwareVolume: true)
        var gains: [Float] = []
        control.activate { gains.append($0) }
        XCTAssertEqual(control.keyboardStatus, .permissionRequired)
        retry?()
        XCTAssertTrue(capture.eventHandlers.isEmpty)
        trusted = true
        retry?()
        XCTAssertTrue(control.keyboardEnabled)
        XCTAssertEqual(control.keyboardStatus, .active)
        XCTAssertTrue(capture.handlers.last?(1, true) == true)
        XCTAssertEqual(gains.last, 0.9375 * 0.9375)
        let handlerCount = capture.eventHandlers.count
        retry?()
        XCTAssertEqual(capture.eventHandlers.count, handlerCount)
        control.stop()
        XCTAssertEqual(cancellations, 1)
        retry?()
        XCTAssertEqual(capture.eventHandlers.count, handlerCount)
        XCTAssertFalse(capture.handlers.last?(1, true) == true)
    }

    func testCancelledRetryCannotStartCaptureForReplacementOutput() throws {
        let name = "NativeVolumeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let capture = Capture()
        var trusted = true
        var retries: [() -> Void] = []
        let control = NativeVolumeControl(
            defaults: defaults, capture: capture, isCurrentOutput: { _ in true },
            isTrusted: { trusted }, retryScheduler: { action in
                retries.append(action)
                return AnyCancellable {}
            }, recordStatus: { _ in }, hud: HUD()
        )
        _ = control.prepare(outputID: 1, uid: "A", needsSoftwareVolume: true)
        control.activate { _ in }
        let old = try XCTUnwrap(retries.first)
        XCTAssertEqual(capture.eventHandlers.count, 1)
        trusted = false
        _ = control.prepare(outputID: 2, uid: "B", needsSoftwareVolume: true)
        control.activate { _ in }
        XCTAssertEqual(control.keyboardStatus, .permissionRequired)
        trusted = true
        old()
        XCTAssertEqual(control.keyboardStatus, .permissionRequired)
        XCTAssertEqual(capture.eventHandlers.count, 1)
        retries.last?()
        XCTAssertEqual(control.keyboardStatus, .active)
        XCTAssertEqual(capture.eventHandlers.count, 2)
        trusted = false
        old()
        XCTAssertEqual(control.keyboardStatus, .active)
    }

    func testDisabledTapCannotApplyGainAndFailedRecoveryRemainsDisabled() throws {
        let name = "NativeVolumeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let capture = Capture()
        let control = NativeVolumeControl(
            defaults: defaults, capture: capture, isCurrentOutput: { _ in true },
            isTrusted: { true }, retryScheduler: { _ in AnyCancellable {} }, recordStatus: { _ in }, hud: HUD()
        )
        _ = control.prepare(outputID: 1, uid: "fixture", needsSoftwareVolume: true)
        control.activate { _ in }
        let old = try XCTUnwrap(capture.handlers.first)
        capture.isEnabled = false
        XCTAssertFalse(control.keyboardEnabled)
        XCTAssertFalse(old(1, true))
        capture.allowed = false
        control.pollKeyboardCapture()
        XCTAssertFalse(control.keyboardEnabled)
        XCTAssertEqual(control.keyboardStatus, .captureUnavailable)
        XCTAssertEqual(control.state.level, 1)
        capture.allowed = true
        control.pollKeyboardCapture()
        XCTAssertTrue(control.keyboardEnabled)
        XCTAssertFalse(old(1, true))
        XCTAssertTrue(capture.handlers.last?(1, true) == true)
    }

    func testCreatedButDisabledTapDoesNotClaimKeyboardIsEnabled() throws {
        let name = "NativeVolumeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let capture = Capture()
        capture.enabledAfterStart = false
        let control = NativeVolumeControl(
            defaults: defaults, capture: capture, isCurrentOutput: { _ in true },
            isTrusted: { true }, retryScheduler: { _ in AnyCancellable {} }, recordStatus: { _ in }, hud: HUD()
        )
        _ = control.prepare(outputID: 1, uid: "fixture", needsSoftwareVolume: true)
        control.activate { _ in }
        XCTAssertFalse(control.keyboardEnabled)
        XCTAssertEqual(control.keyboardStatus, .captureUnavailable)
        XCTAssertFalse(capture.handlers.last?(1, true) == true)
    }

    func testRevokedPermissionStopsCaptureAndRetainsVolume() throws {
        let name = "NativeVolumeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let capture = Capture()
        var trusted = true
        let control = NativeVolumeControl(
            defaults: defaults, capture: capture, isCurrentOutput: { _ in true },
            isTrusted: { trusted }, retryScheduler: { _ in AnyCancellable {} }, recordStatus: { _ in }, hud: HUD()
        )
        _ = control.prepare(outputID: 1, uid: "fixture", needsSoftwareVolume: true)
        control.activate { _ in }
        let old = try XCTUnwrap(capture.handlers.first)
        XCTAssertTrue(old(1, true))
        let level = control.state.level
        trusted = false
        control.pollKeyboardCapture()
        XCTAssertFalse(control.keyboardEnabled)
        XCTAssertFalse(capture.isEnabled)
        XCTAssertEqual(control.keyboardStatus, .permissionRequired)
        XCTAssertFalse(old(1, true))
        XCTAssertEqual(control.state.level, level)
        XCTAssertTrue(control.diagnosticSummary().contains("Accessibility authorized: false"))
    }

    func testVolumeRepeatsButHoldingMuteDoesNotToggleRepeatedly() throws {
        let name = "NativeVolumeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let capture = Capture()
        let control = NativeVolumeControl(
            defaults: defaults, capture: capture, isCurrentOutput: { _ in true },
            isTrusted: { true }, retryScheduler: { _ in AnyCancellable {} }, recordStatus: { _ in }, hud: HUD()
        )
        _ = control.prepare(outputID: 1, uid: "fixture", needsSoftwareVolume: true)
        control.activate { _ in }
        let handler = try XCTUnwrap(capture.eventHandlers.first)
        XCTAssertTrue(handler(.init(key: 1, isDown: true, isRepeat: false)))
        XCTAssertTrue(handler(.init(key: 1, isDown: true, isRepeat: true)))
        XCTAssertEqual(control.state.level, 0.875)
        XCTAssertTrue(handler(.init(key: 7, isDown: true, isRepeat: false)))
        XCTAssertTrue(control.state.isMuted)
        XCTAssertTrue(handler(.init(key: 7, isDown: true, isRepeat: true)))
        XCTAssertTrue(handler(.init(key: 7, isDown: false, isRepeat: false)))
        XCTAssertTrue(control.state.isMuted)
        XCTAssertTrue(handler(.init(key: 7, isDown: true, isRepeat: false)))
        XCTAssertFalse(control.state.isMuted)
        XCTAssertTrue(control.diagnosticSummary().contains("Volume actions applied in current run: 4"))
    }

    private func mediaEvent(key: Int, state: Int, repeatKey: Bool = false, subtype: Int16 = 8) throws -> NSEvent {
        let event = try XCTUnwrap(NSEvent.otherEvent(
            with: .systemDefined, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, subtype: subtype,
            data1: (key << 16) | (state << 8) | (repeatKey ? 1 : 0), data2: 0
        ))
        return try XCTUnwrap(NSEvent(cgEvent: XCTUnwrap(event.cgEvent)))
    }

    func testActualNSEventRoundTripDecodesMuteAndVolumePressReleaseAndRepeat() throws {
        for key in [0, 1, 7] {
            for (state, down) in [(0x0A, true), (0x0B, false)] {
                let decoded = try XCTUnwrap(NativeMediaKeyEvent.decode(mediaEvent(key: key, state: state)))
                XCTAssertEqual(decoded.key, key)
                XCTAssertEqual(decoded.isDown, down)
                XCTAssertFalse(decoded.isRepeat)
            }
        }
        let repeatEvent = try XCTUnwrap(NativeMediaKeyEvent.decode(mediaEvent(key: 1, state: 0x0A, repeatKey: true)))
        XCTAssertTrue(repeatEvent.isRepeat)
        XCTAssertTrue(repeatEvent.isDown)
    }

    func testDecoderRejectsOtherKeysSubtypesAndMalformedStates() throws {
        XCTAssertNil(try NativeMediaKeyEvent.decode(mediaEvent(key: 16, state: 0x0A)))
        XCTAssertNil(try NativeMediaKeyEvent.decode(mediaEvent(key: 1, state: 0x0A, subtype: 0)))
        XCTAssertNil(try NativeMediaKeyEvent.decode(mediaEvent(key: 1, state: 0x09)))
        let functionKey = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
            context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 109
        ))
        XCTAssertNil(NativeMediaKeyEvent.decode(functionKey))
    }

    @available(macOS 14.4, *)
    private func render(_ engine: ProcessTapEngine, samples: [Float], outputFrames: Int) -> [Float] {
        var input = samples
        var output = [Float](repeating: 99, count: outputFrames * 2)
        input.withUnsafeMutableBufferPointer { source in
            output.withUnsafeMutableBufferPointer { destination in
                var inputList = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(
                    mNumberChannels: 2, mDataByteSize: UInt32(source.count * MemoryLayout<Float>.size),
                    mData: source.baseAddress
                ))
                var outputList = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(
                    mNumberChannels: 2, mDataByteSize: UInt32(destination.count * MemoryLayout<Float>.size),
                    mData: destination.baseAddress
                ))
                engine.render(input: &inputList, output: &outputList)
            }
        }
        return output
    }

    func testActualNativeCallbackAppliesVolumeInEQBypassForZeroOneAndUnequalFrames() throws {
        guard #available(macOS 14.4, *) else { throw XCTSkip("Native backend requires macOS 14.4") }
        let processor = CoreAudioEngine()
        processor.setEnabled(false)
        let engine = ProcessTapEngine(processor: processor, initialOutputVolumeGain: 0.5)
        XCTAssertEqual(render(engine, samples: [], outputFrames: 2), [0, 0, 0, 0])
        XCTAssertEqual(render(engine, samples: [0.8, -0.4], outputFrames: 1), [0.4, -0.2])
        XCTAssertEqual(render(engine, samples: [0.8, -0.4], outputFrames: 3), [0.4, -0.2, 0, 0, 0, 0])
        XCTAssertEqual(render(engine, samples: [0.8, -0.4, 1, -1], outputFrames: 1), [0.4, -0.2])
    }

    func testNativeMuteClearsNonFiniteSamplesAndInvalidGainCannotAmplify() throws {
        guard #available(macOS 14.4, *) else { throw XCTSkip("Native backend requires macOS 14.4") }
        let processor = CoreAudioEngine()
        processor.setEnabled(false)
        let engine = ProcessTapEngine(processor: processor, initialOutputVolumeGain: 1)
        engine.setOutputVolumeGain(0)
        XCTAssertEqual(render(engine, samples: [.nan, .infinity], outputFrames: 1), [0, 0])
        engine.setOutputVolumeGain(.nan)
        XCTAssertEqual(render(engine, samples: [1, -1], outputFrames: 1), [0, 0])
        engine.setOutputVolumeGain(9)
        _ = render(engine, samples: [1, -1], outputFrames: 1)
        XCTAssertEqual(render(engine, samples: [1, -1], outputFrames: 1), [1, -1])
    }

    func testConcurrentGainPublicationKeepsRenderFiniteAndBounded() throws {
        guard #available(macOS 14.4, *) else { throw XCTSkip("Native backend requires macOS 14.4") }
        let engine = ProcessTapEngine(processor: CoreAudioEngine())
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            for n in 0..<2000 {
                engine.setOutputVolumeGain(Float(n % 17) / 16)
            }
            group.leave()
        }
        for _ in 0..<100 {
            var left = [Float](repeating: 1, count: 64)
            var right = left
            left.withUnsafeMutableBufferPointer { l in
                right.withUnsafeMutableBufferPointer { r in
                    guard let left = l.baseAddress, let right = r.baseAddress else {
                        XCTFail("Allocated stereo buffers must have storage")
                        return
                    }
                    engine.applyOutputVolume(left: left, right: right, frameCount: l.count)
                }
            }
            XCTAssertTrue(left.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1.001 })
            XCTAssertEqual(left, right)
        }
        XCTAssertEqual(group.wait(timeout: .now() + 5), .success)
    }
}

@MainActor
final class NativeVolumeHUDTests: XCTestCase {
    func testDeferredRenderingRejectsStoppedAndSupersededPresentations() {
        var queued: [@MainActor () -> Void] = []
        var states: [NativeVolumeState] = []
        let hud = NativeVolumeHUD(schedule: { _, _ in AnyCancellable {} }, enqueue: { queued.append($0) }, present: {
            states.append($0)
            return true
        }, dismiss: {})
        hud.show(state: .init(level: 0.25))
        hud.show(state: .init(level: 0.5))
        XCTAssertFalse(hud.isVisible)
        XCTAssertTrue(states.isEmpty)
        queued[0]()
        XCTAssertTrue(states.isEmpty)
        queued[1]()
        XCTAssertEqual(states.map(\.level), [0.5])
        XCTAssertTrue(hud.isVisible)
        hud.show(state: .init(level: 0.75))
        hud.hide()
        queued[2]()
        XCTAssertFalse(hud.isVisible)
        XCTAssertEqual(states.map(\.level), [0.5])
    }

    func testRepeatReschedulesHideAndCancelledCallbacksCannotHideFreshHUD() {
        var timers: [@MainActor () -> Void] = []
        var delays: [TimeInterval] = []
        var cancellations = 0
        var states: [NativeVolumeState] = []
        var hides = 0
        let hud = NativeVolumeHUD(schedule: { delay, action in
            delays.append(delay)
            timers.append(action)
            return AnyCancellable { cancellations += 1 }
        }, enqueue: { $0() }, present: { states.append($0); return true }, dismiss: { hides += 1 })
        hud.show(state: .init(level: 0.25))
        hud.show(state: .init(level: 0.75))
        XCTAssertEqual(states.map(\.level), [0.25, 0.75])
        XCTAssertEqual(delays, [1.25, 1.25])
        XCTAssertEqual(cancellations, 1)
        timers[0]()
        XCTAssertTrue(hud.isVisible)
        XCTAssertEqual(hides, 0)
        timers[1]()
        XCTAssertFalse(hud.isVisible)
        XCTAssertEqual(hides, 1)
        hud.show(state: .init(isMuted: true))
        timers[1]()
        XCTAssertTrue(hud.isVisible)
        XCTAssertEqual(hides, 1)
        XCTAssertTrue(states.last?.isMuted == true)
    }

    func testExplicitHideInvalidatesTimerAcrossNextPresentation() {
        var timers: [@MainActor () -> Void] = []
        var hides = 0
        let hud = NativeVolumeHUD(schedule: { _, action in
            timers.append(action)
            return AnyCancellable {}
        }, enqueue: { $0() }, present: { _ in true }, dismiss: { hides += 1 })
        hud.show(state: .init())
        hud.hide()
        XCTAssertFalse(hud.isVisible)
        hud.show(state: .init(level: 0))
        timers[0]()
        XCTAssertTrue(hud.isVisible)
        XCTAssertEqual(hides, 1)
        hud.hide()
        timers[1]()
        XCTAssertFalse(hud.isVisible)
        XCTAssertEqual(hides, 2)
    }

    func testFailedPresentationCannotRemainVisibleOrScheduleHide() {
        var timers = 0
        var succeeds = true
        var hides = 0
        let hud = NativeVolumeHUD(schedule: { _, _ in
            timers += 1
            return AnyCancellable {}
        }, enqueue: { $0() }, present: { _ in succeeds }, dismiss: { hides += 1 })
        hud.show(state: .init())
        XCTAssertTrue(hud.isVisible)
        succeeds = false
        hud.show(state: .init())
        XCTAssertFalse(hud.isVisible)
        XCTAssertEqual(timers, 1)
        XCTAssertEqual(hides, 1)
    }

    func testGeometryStaysInsideOffsetAndNarrowScreensAndRejectsInvalidBounds() throws {
        for screen in [
            NSRect(x: 0, y: 0, width: 1920, height: 1055),
            NSRect(x: -1440, y: 200, width: 1440, height: 875),
            NSRect(x: 250, y: -900, width: 180, height: 50)
        ] {
            let frame = try XCTUnwrap(NativeVolumeHUD.frame(in: screen))
            XCTAssertTrue(screen.contains(frame))
            XCTAssertEqual(frame.maxX, screen.maxX - 16)
            XCTAssertEqual(frame.maxY, screen.maxY - 10)
        }
        XCTAssertNil(NativeVolumeHUD.frame(in: .zero))
        XCTAssertNil(NativeVolumeHUD.frame(in: NSRect(x: CGFloat.nan, y: 0, width: 100, height: 100)))
        XCTAssertNil(NativeVolumeHUD.frame(in: NSRect(x: 0, y: 0, width: CGFloat.infinity, height: 100)))
    }

    func testGeometryCentersBelowMenuBarAnchor() throws {
        let display = NSRect(x: 0, y: 0, width: 1440, height: 924)
        let available = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let anchor = NSRect(x: 950, y: 900, width: 24, height: 24)
        let frame = try XCTUnwrap(NativeVolumeHUD.frame(in: available, anchor: anchor, screenFrame: display))
        XCTAssertEqual(frame.size, NSSize(width: 290, height: 64))
        XCTAssertEqual(frame.midX, anchor.midX)
        XCTAssertEqual(frame.maxY, anchor.minY - 10)
        XCTAssertTrue(available.contains(frame))
    }

    func testGeometryClampsMenuBarAnchorAtDisplayEdges() throws {
        let display = NSRect(x: -1440, y: 200, width: 1440, height: 900)
        let available = NSRect(x: -1440, y: 200, width: 1440, height: 875)
        for anchor in [
            NSRect(x: -1440, y: 1076, width: 24, height: 24),
            NSRect(x: -24, y: 1076, width: 24, height: 24),
            NSRect(x: -800, y: 200, width: 24, height: 24)
        ] {
            let frame = try XCTUnwrap(NativeVolumeHUD.frame(in: available, anchor: anchor, screenFrame: display))
            XCTAssertTrue(available.contains(frame))
            XCTAssertGreaterThanOrEqual(frame.minX, available.minX + 16)
            XCTAssertLessThanOrEqual(frame.maxX, available.maxX - 16)
            XCTAssertGreaterThanOrEqual(frame.minY, available.minY + 10)
            XCTAssertLessThanOrEqual(frame.maxY, available.maxY - 10)
        }
    }

    func testGeometryRejectsWrongDisplayAndInvalidAnchorsUsingOriginalFallback() throws {
        let display = NSRect(x: 0, y: 0, width: 1440, height: 924)
        let available = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let fallback = try XCTUnwrap(NativeVolumeHUD.frame(in: available))
        for anchor in [
            NSRect(x: -1440, y: 900, width: 24, height: 24),
            NSRect(x: 1430, y: 900, width: 24, height: 24),
            NSRect(x: CGFloat.nan, y: 900, width: 24, height: 24),
            NSRect(x: 950, y: CGFloat.infinity, width: 24, height: 24),
            NSRect(x: 950, y: 900, width: 0, height: 24),
            NSRect(x: 950, y: 900, width: 24, height: -24)
        ] {
            XCTAssertEqual(NativeVolumeHUD.frame(in: available, anchor: anchor, screenFrame: display), fallback)
        }
    }

    func testAccessibilityAnchorConvertsTopLeftCoordinatesForOffsetDisplay() throws {
        let accessibility = NSRect(x: -800, y: -200, width: 24, height: 24)
        let anchor = try XCTUnwrap(NativeVolumeHUD.appKitAnchor(
            fromAccessibility: accessibility,
            primaryScreenTop: 900
        ))
        XCTAssertEqual(anchor, NSRect(x: -800, y: 1076, width: 24, height: 24))
        let display = NSRect(x: -1440, y: 200, width: 1440, height: 900)
        let available = NSRect(x: -1440, y: 200, width: 1440, height: 875)
        let frame = try XCTUnwrap(NativeVolumeHUD.frame(in: available, anchor: anchor, screenFrame: display))
        XCTAssertEqual(frame.midX, anchor.midX)
        XCTAssertEqual(frame.maxY, available.maxY - 10)
        XCTAssertNil(NativeVolumeHUD.appKitAnchor(fromAccessibility: accessibility, primaryScreenTop: .nan))
        XCTAssertNil(NativeVolumeHUD.appKitAnchor(fromAccessibility: .zero, primaryScreenTop: 900))
        XCTAssertNil(NativeVolumeHUD.appKitAnchor(
            fromAccessibility: NSRect(x: 0, y: CGFloat.infinity, width: 24, height: 24), primaryScreenTop: 900
        ))
    }

    func testPanelCannotTakeFocusOrInterceptMouseAndSupportsFullscreenSpaces() {
        let panel = NativeVolumeHUDPanel()
        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertTrue(panel.ignoresMouseEvents)
        XCTAssertFalse(panel.hidesOnDeactivate)
        XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertEqual(panel.level, .statusBar)
        XCTAssertFalse(panel.isVisible)
    }
}
