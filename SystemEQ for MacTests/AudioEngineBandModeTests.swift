//
//  AudioEngineBandModeTests.swift
//  SystemEQ for MacTests
//
//  Regression tests for applying EQ values right after a band-mode switch:
//  bandMode's didSet rebuilds `bands` only on the next main-loop turn, so a
//  same-turn applyEQValues used to see the stale array and bail out.
//

import AVFoundation
import Combine
import CoreAudio
import Darwin
@testable import SystemEQ_for_Mac
import XCTest

@MainActor
final class AudioDiagnosticAgeTests: XCTestCase {
    func testNeverObservedRemainsUnavailable() {
        XCTAssertEqual(CoreAudioEngine.ageDescription(0, now: 1_000_000), "not observed")
    }

    func testPastTimestampReportsElapsedSeconds() {
        let timestamp: UInt64 = 100
        let now = timestamp + AudioConvertNanosToHostTime(5_000_000_000)
        XCTAssertEqual(
            CoreAudioEngine.ageDescription(Int64(bitPattern: timestamp), now: now),
            "5.0 seconds ago"
        )
    }

    func testTimestampPublishedAfterSnapshotDoesNotWrap() {
        XCTAssertEqual(CoreAudioEngine.ageDescription(1_000_001, now: 1_000_000), "0.0 seconds ago")
        XCTAssertEqual(CoreAudioEngine.ageDescription(Int64(bitPattern: UInt64.max), now: 1), "0.0 seconds ago")
    }

    func testSignedStoragePreservesValidUnsignedHostTime() {
        let timestamp = (UInt64(1) << 63) + 1
        let now = timestamp + AudioConvertNanosToHostTime(5_000_000_000)
        XCTAssertEqual(
            CoreAudioEngine.ageDescription(Int64(bitPattern: timestamp), now: now),
            "5.0 seconds ago"
        )
    }

    func testEqualTimestampReportsZeroAge() {
        XCTAssertEqual(CoreAudioEngine.ageDescription(123, now: 123), "0.0 seconds ago")
    }
}

final class BufferSizeNegotiationTests: XCTestCase {
    private struct Request: Equatable {
        let device: AudioDeviceID
        let frames: UInt32
    }

    private final class Devices {
        let input: AudioDeviceID = 11
        let output: AudioDeviceID = 22
        var frames: [AudioDeviceID: UInt32] = [11: 512, 22: 512]
        var rejected: [AudioDeviceID: Set<UInt32>] = [:]
        var clamped: [AudioDeviceID: UInt32] = [:]
        var unreadableReads: [AudioDeviceID: Set<Int>] = [:]
        var zeroReads: [AudioDeviceID: Set<Int>] = [:]
        var readCounts: [AudioDeviceID: Int] = [:]
        var requests: [Request] = []
        var afterSet: ((AudioDeviceID, UInt32) -> Void)?

        func resolve() -> AudioBufferSizeNegotiation.Configuration? {
            AudioBufferSizeNegotiation.resolve(
                inputDevice: input,
                outputDevice: output,
                read: { device in
                    self.readCounts[device, default: 0] += 1
                    let count = self.readCounts[device, default: 0]
                    if self.unreadableReads[device]?.contains(count) == true { return nil }
                    if self.zeroReads[device]?.contains(count) == true { return 0 }
                    return self.frames[device]
                },
                set: { device, frames in
                    self.requests.append(Request(device: device, frames: frames))
                    guard self.rejected[device]?.contains(frames) != true else { return false }
                    self.frames[device] = self.clamped[device] ?? frames
                    self.afterSet?(device, frames)
                    return true
                }
            )
        }
    }

    func testBothDevicesAcceptPreferredSizeWithoutFallback() throws {
        let devices = Devices()
        let result = try XCTUnwrap(devices.resolve())
        XCTAssertEqual(result.inputFrames, 256)
        XCTAssertEqual(result.outputFrames, 256)
        XCTAssertTrue(result.inputRequestConfirmed)
        XCTAssertTrue(result.outputRequestConfirmed)
        XCTAssertEqual(devices.requests, [
            Request(device: devices.input, frames: 256), Request(device: devices.output, frames: 256)
        ])
    }

    func testFixedDeviceDoesNotIncreaseOtherDevicesBuffer() throws {
        for fixedDevice: AudioDeviceID in [11, 22] {
            let devices = Devices()
            devices.rejected[fixedDevice] = [256, 512]
            let result = try XCTUnwrap(devices.resolve())
            XCTAssertEqual(result.inputFrames, fixedDevice == devices.input ? 512 : 256)
            XCTAssertEqual(result.outputFrames, fixedDevice == devices.output ? 512 : 256)
            XCTAssertEqual(result.inputRequestConfirmed, fixedDevice != devices.input)
            XCTAssertEqual(result.outputRequestConfirmed, fixedDevice != devices.output)
            XCTAssertEqual(devices.requests, [
                Request(device: devices.input, frames: 256), Request(device: devices.output, frames: 256),
                Request(device: fixedDevice, frames: 512)
            ])
        }
    }

    func testSuccessfulSetterWithClampedReadbackFallsBackOnlyThatDevice() throws {
        let devices = Devices()
        devices.clamped[devices.output] = 512
        let result = try XCTUnwrap(devices.resolve())
        XCTAssertEqual(result.inputFrames, 256)
        XCTAssertEqual(result.outputFrames, 512)
        XCTAssertTrue(result.outputRequestConfirmed)
        XCTAssertEqual(devices.requests.last, Request(device: devices.output, frames: 512))
        XCTAssertEqual(devices.requests.count, 3)
    }

    func testUnknownPreferredReadbackCannotConfirmPreferredSize() throws {
        let devices = Devices()
        devices.unreadableReads[devices.output] = [1]
        let result = try XCTUnwrap(devices.resolve())
        XCTAssertEqual(result.inputFrames, 256)
        XCTAssertEqual(result.outputFrames, 512)
        XCTAssertEqual(devices.requests.last, Request(device: devices.output, frames: 512))
        XCTAssertEqual(devices.requests.count, 3)
    }

    func testRejectedPreferredRequestStillRequiresFallbackWhenReadbackMatches() throws {
        let devices = Devices()
        devices.frames[devices.output] = 256
        devices.rejected[devices.output] = [256]
        let result = try XCTUnwrap(devices.resolve())
        XCTAssertEqual(result.inputFrames, 256)
        XCTAssertEqual(result.outputFrames, 512)
        XCTAssertTrue(result.outputRequestConfirmed)
        XCTAssertEqual(devices.requests.last, Request(device: devices.output, frames: 512))
    }

    func testBothDevicesCanRejectRequestsAndKeepDifferentSupportedSizes() throws {
        let devices = Devices()
        devices.frames[devices.input] = 512
        devices.frames[devices.output] = 1024
        devices.rejected = [devices.input: [256, 512], devices.output: [256, 512]]
        let result = try XCTUnwrap(devices.resolve())
        XCTAssertEqual(result.inputFrames, 512)
        XCTAssertEqual(result.outputFrames, 1024)
        XCTAssertFalse(result.inputRequestConfirmed)
        XCTAssertFalse(result.outputRequestConfirmed)
        XCTAssertEqual(devices.requests.count, 4)
    }

    func testMissingOrZeroFinalReadbackFailsNegotiation() {
        for invalidDevice: AudioDeviceID in [11, 22] {
            let unreadable = Devices()
            unreadable.unreadableReads[invalidDevice] = [2]
            XCTAssertNil(unreadable.resolve())
            let zero = Devices()
            zero.zeroReads[invalidDevice] = [2]
            XCTAssertNil(zero.resolve())
        }
    }

    func testFinalReadbackIncludesCrossDeviceChangesDuringFallback() throws {
        let devices = Devices()
        devices.clamped[devices.output] = 512
        devices.afterSet = { device, frames in
            if device == 22, frames == 512 { devices.frames[11] = 512 }
        }
        defer { devices.afterSet = nil }
        let result = try XCTUnwrap(devices.resolve())
        XCTAssertEqual(result.inputFrames, 512)
        XCTAssertEqual(result.outputFrames, 512)
        XCTAssertFalse(result.inputRequestConfirmed)
        XCTAssertTrue(result.outputRequestConfirmed)
    }
}

final class SampleRateNegotiationTests: XCTestCase {
    func testAsynchronousHardwareChangeMustSettleBeforeSuccess() {
        var output = 96000.0
        var pending: Double?
        var pauses = 0
        let result = AudioSampleRateNegotiation.resolve(
            preferredRate: 48000,
            read: { .init(input: 48000, output: output) },
            setInput: { _ in XCTFail("Input already matches"); return false },
            setOutput: { pending = $0; return true },
            pause: {
                pauses += 1
                if pauses == 5, let pending { output = pending }
            }
        )
        XCTAssertEqual(try? result.get(), 48000)
        XCTAssertGreaterThanOrEqual(pauses, 7)
        XCTAssertEqual(output, 48000)
    }

    func testRejectedSettersCannotConfirmMismatchedRates() {
        var writes = 0
        let result = AudioSampleRateNegotiation.resolve(
            read: { .init(input: 48000, output: 96000) },
            setInput: { _ in writes += 1; return false },
            setOutput: { _ in writes += 1; return false },
            pause: { XCTFail("Rejected setters must not be awaited") }
        )
        XCTAssertEqual(result, .failure(.setterRejected))
        XCTAssertGreaterThan(writes, 0)
    }

    func testSuccessfulSetterWithUnchangedReadbackTimesOut() {
        var pauses = 0
        let result = AudioSampleRateNegotiation.resolve(
            maximumReads: 5,
            read: { .init(input: 48000, output: 96000) },
            setInput: { _ in true },
            setOutput: { _ in true },
            pause: { pauses += 1 }
        )
        XCTAssertEqual(result, .failure(.didNotSettle))
        XCTAssertEqual(pauses, 12)
    }

    func testMissingAndInvalidMetadataCannotWriteOrInvent48k() {
        let cases: [AudioSampleRateNegotiation.Rates?] = [
            nil, .init(input: .nan, output: 48000), .init(input: 48000, output: .infinity),
            .init(input: 0, output: 48000), .init(input: 48000, output: -1)
        ]
        for rates in cases {
            let result = AudioSampleRateNegotiation.resolve(
                read: { rates },
                setInput: { _ in XCTFail("Invalid metadata must not mutate hardware"); return true },
                setOutput: { _ in XCTFail("Invalid metadata must not mutate hardware"); return true },
                pause: { XCTFail("Invalid metadata must fail immediately") }
            )
            XCTAssertEqual(result, .failure(.invalidMetadata))
        }
    }

    func testReadFailureAfterSetterIsNotSuccess() {
        var readable = true
        let result = AudioSampleRateNegotiation.resolve(
            read: { readable ? .init(input: 48000, output: 96000) : nil },
            setInput: { _ in true },
            setOutput: { _ in readable = false; return true },
            pause: {}
        )
        XCTAssertEqual(result, .failure(.invalidMetadata))
    }

    func testTransientMatchingReadbackDoesNotCountAsSettled() {
        var reads = 0
        let result = AudioSampleRateNegotiation.waitForRate(48000, maximumReads: 8, read: {
            reads += 1
            return .init(input: 48000, output: reads % 3 == 0 ? 96000 : 48000)
        }, pause: {})
        XCTAssertEqual(result, .failure(.didNotSettle))
        XCTAssertEqual(reads, 8)
    }

    func testExternalRateChoiceIsAppliedToBothDevices() {
        var input = 48000.0
        var output = 44100.0
        var requests: [Double] = []
        let result = AudioSampleRateNegotiation.resolve(
            preferredRate: 44100,
            read: { .init(input: input, output: output) },
            setInput: { input = $0; requests.append($0); return true },
            setOutput: { output = $0; requests.append($0); return true },
            pause: {}
        )
        XCTAssertEqual(try? result.get(), 44100)
        XCTAssertEqual(requests, [44100])
        XCTAssertEqual(input, output)
    }

    func testFixedMatchingHardwareCanUseItsSupportedRate() {
        let result = AudioSampleRateNegotiation.resolve(
            read: { .init(input: 96000, output: 96000) },
            setInput: { _ in false },
            setOutput: { _ in false },
            pause: {}
        )
        XCTAssertEqual(try? result.get(), 96000)
    }

    func testLastUnchangedDeviceEventCannotHideOtherDeviceRateChange() {
        let rates = AudioSampleRateNegotiation.Rates(input: 44100, output: 48000)
        XCTAssertFalse(rates.matches(48000))
        XCTAssertEqual(rates.recoveryRate(current: 48000, changed: 48000), 44100)
        XCTAssertNil(AudioSampleRateNegotiation.Rates(input: 48000, output: 48000).recoveryRate(
            current: 48000,
            changed: 48000
        ))
    }

    func testRollbackCaptureRequiresUIDAndValidOriginalRate() {
        XCTAssertNil(AudioSampleRateNegotiation.originalRate(uid: nil, saved: [:], read: {
            XCTFail("Missing UID must stop capture before reading a rate")
            return 96000
        }))
        XCTAssertNil(AudioSampleRateNegotiation.originalRate(uid: "", saved: [:], read: { 96000 }))
        XCTAssertNil(AudioSampleRateNegotiation.originalRate(uid: "device", saved: [:], read: { nil }))
        XCTAssertNil(AudioSampleRateNegotiation.originalRate(uid: "device", saved: [:], read: { .nan }))
        XCTAssertNil(AudioSampleRateNegotiation.originalRate(
            uid: "device",
            saved: ["device": .infinity],
            read: { 48000 }
        ))
        let captured = AudioSampleRateNegotiation.originalRate(uid: "device", saved: [:], read: { 96000 })
        XCTAssertEqual(captured?.uid, "device")
        XCTAssertEqual(captured?.rate, 96000)
        let preserved = AudioSampleRateNegotiation.originalRate(
            uid: "device",
            saved: ["device": 44100],
            read: { 48000 }
        )
        XCTAssertEqual(preserved?.rate, 44100)
    }

    func testPhysicalOutputRateIsPreservedBeforeTryingFallbackRates() {
        for rate in [44100.0, 96000.0] {
            var input = 48000.0
            var inputWrites: [Double] = []
            let result = AudioSampleRateNegotiation.resolve(
                read: { .init(input: input, output: rate) },
                setInput: { input = $0; inputWrites.append($0); return true },
                setOutput: { _ in XCTFail("Physical output must retain its current rate"); return false },
                pause: {}
            )
            XCTAssertEqual(try? result.get(), rate)
            XCTAssertEqual(inputWrites, [rate])
        }
    }

    func testExplicitRateRecoveryTakesPriorityOverCurrentOutputRate() {
        var input = 44100.0
        var output = 48000.0
        let result = AudioSampleRateNegotiation.resolve(
            preferredRate: 96000,
            read: { .init(input: input, output: output) },
            setInput: { input = $0; return true },
            setOutput: { output = $0; return true },
            pause: {}
        )
        XCTAssertEqual(try? result.get(), 96000)
        XCTAssertEqual(input, 96000)
        XCTAssertEqual(output, 96000)
    }

    func testRejectedOutputRateCanFallBackToFixedInputRate() {
        var output = 44100.0
        let result = AudioSampleRateNegotiation.resolve(
            read: { .init(input: 48000, output: output) },
            setInput: { _ in false },
            setOutput: { output = $0; return true },
            pause: {}
        )
        XCTAssertEqual(try? result.get(), 48000)
        XCTAssertEqual(output, 48000)
    }
}

final class SampleRateRestorationTests: XCTestCase {
    func testDeviceQueryFailureIsNotTreatedAsDisconnection() {
        let result = AudioSampleRateNegotiation.restore(
            saved: ["output": 44100],
            resolveDevice: { _ in throw AudioSampleRateNegotiation.Failure.invalidMetadata },
            read: { _ in XCTFail("Failed device query must stop restoration"); return nil },
            set: { _, _ in XCTFail("Failed device query must not write"); return false },
            pause: {}
        )
        XCTAssertEqual(result.pending, ["output": 44100])
        XCTAssertEqual(result.failures, ["output": .invalidMetadata])
    }

    func testPartialRestorationRetainsRejectedInvalidAndDisconnectedSnapshots() {
        var rates: [AudioDeviceID: Double] = [1: 48000, 2: 48000]
        let result = AudioSampleRateNegotiation.restore(
            saved: ["restored": 44100, "rejected": 44100, "disconnected": 44100, "invalid": .nan],
            resolveDevice: { ["restored": 1, "rejected": 2][$0] },
            read: { rates[$0] },
            set: { device, rate in
                guard device == 1 else { return false }
                rates[device] = rate
                return true
            },
            pause: {}
        )
        XCTAssertNil(result.pending["restored"])
        XCTAssertEqual(rates[1], 44100)
        XCTAssertEqual(result.pending.count, 3)
        XCTAssertEqual(result.failures, [
            "rejected": .setterRejected, "disconnected": .deviceUnavailable, "invalid": .invalidMetadata
        ])
    }

    func testAcceptedSetterWithStaleReadbackKeepsSnapshot() {
        let result = AudioSampleRateNegotiation.restore(
            saved: ["output": 44100],
            resolveDevice: { _ in 1 },
            read: { _ in 48000 },
            set: { _, _ in true },
            pause: {}
        )
        XCTAssertEqual(result.pending, ["output": 44100])
        XCTAssertEqual(result.failures, ["output": .didNotSettle])
    }

    func testMissingOrInvalidReadbackCannotMutateDeviceOrClearSnapshot() {
        for observed: Double? in [nil, .nan, .infinity, 0, -1] {
            let result = AudioSampleRateNegotiation.restore(
                saved: ["output": 44100],
                resolveDevice: { _ in 1 },
                read: { _ in observed },
                set: { _, _ in XCTFail("Invalid metadata must not write"); return true },
                pause: { XCTFail("Invalid metadata must fail immediately") }
            )
            XCTAssertEqual(result.pending, ["output": 44100])
            XCTAssertEqual(result.failures, ["output": .invalidMetadata])
        }
    }

    func testMatchingRateNeedsStableReadbackWithoutSetter() {
        var reads = 0
        let result = AudioSampleRateNegotiation.restore(
            saved: ["output": 44100],
            resolveDevice: { _ in 1 },
            read: { _ in reads += 1; return 44100 },
            set: { _, _ in XCTFail("Matching rate must not be written again"); return false },
            pause: {}
        )
        XCTAssertTrue(result.pending.isEmpty)
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertEqual(reads, 4)
    }

    func testReadFailureAfterSetterRetainsOriginalRate() {
        var readable = true
        let result = AudioSampleRateNegotiation.restore(
            saved: ["output": 44100],
            resolveDevice: { _ in 1 },
            read: { _ in readable ? 48000 : nil },
            set: { _, _ in readable = false; return true },
            pause: {}
        )
        XCTAssertEqual(result.pending, ["output": 44100])
        XCTAssertEqual(result.failures, ["output": .invalidMetadata])
    }

    func testDisconnectedDeviceCanBeRestoredAfterReturningWithNewID() {
        let deferred = AudioSampleRateNegotiation.restore(
            saved: ["output": 44100], resolveDevice: { _ in nil },
            read: { _ in XCTFail("Disconnected device must not be read"); return nil },
            set: { _, _ in XCTFail("Disconnected device must not be written"); return false }, pause: {}
        )
        XCTAssertEqual(deferred.pending, ["output": 44100])
        var rate = 48000.0
        let restored = AudioSampleRateNegotiation.restore(
            saved: deferred.pending, resolveDevice: { _ in 99 },
            read: { device in XCTAssertEqual(device, 99); return rate },
            set: { device, value in XCTAssertEqual(device, 99); rate = value; return true }, pause: {}
        )
        XCTAssertTrue(restored.pending.isEmpty)
        XCTAssertTrue(restored.failures.isEmpty)
        XCTAssertEqual(rate, 44100)
    }
}

final class NativeRoutingPreparationTests: XCTestCase {
    func testFailedPreparationBlocksNativeAndAutomaticFallback() {
        for preference in [AudioRoutingBackendPreference.native, .automatic] {
            var preparations = 0
            XCTAssertFalse(AudioRoutingStartPolicy.start(
                preference: preference, persistEnabledStateOnFailure: true,
                prepareNative: { preparations += 1; return false },
                native: { _ in XCTFail("Native cannot start after failed cleanup or restoration"); return true },
                blackHole: { _ in XCTFail("Failed handoff must not force BlackHole again"); return true },
                onFallback: { XCTFail("Preparation failure must remain observable") }
            ))
            XCTAssertEqual(preparations, 1)
        }
    }

    func testBlackHoleRecoveryDoesNotRunNativePreparation() {
        XCTAssertTrue(AudioRoutingStartPolicy.start(
            preference: .blackHole, persistEnabledStateOnFailure: false,
            prepareNative: { XCTFail("BlackHole recovery must retain the requested sample rate"); return false },
            native: { _ in XCTFail("Native must not start"); return false },
            blackHole: { _ in true }, onFallback: { XCTFail("No fallback requested") }
        ))
    }

    func testPreparationPrecedesNativeAndOrdinaryStartupFailureStillFallsBack() {
        var events: [String] = []
        XCTAssertTrue(AudioRoutingStartPolicy.start(
            preference: .automatic, persistEnabledStateOnFailure: true,
            prepareNative: { events.append("prepare"); return true },
            native: { persist in XCTAssertFalse(persist); events.append("native"); return false },
            blackHole: { persist in XCTAssertTrue(persist); events.append("blackHole"); return true },
            onFallback: { events.append("fallback") }
        ))
        XCTAssertEqual(events, ["prepare", "native", "fallback", "blackHole"])
    }
}

final class AudioClientFormatValidationTests: XCTestCase {
    private var expected: AudioStreamBasicDescription {
        AudioStreamBasicDescription(
            mSampleRate: 48000, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
            mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0
        )
    }

    func testExactFloat32PlanarAndInterleavedLayoutsAreAccepted() {
        XCTAssertTrue(AudioClientFormatValidation.matches(expected, expected: expected))
        var interleaved = expected
        interleaved.mFormatFlags &= ~kAudioFormatFlagIsNonInterleaved
        interleaved.mBytesPerFrame = 8
        interleaved.mBytesPerPacket = 8
        XCTAssertTrue(AudioClientFormatValidation.matches(interleaved, expected: interleaved))
    }

    func testInt16ReadbackWithMatchingRateAndChannelsIsRejected() {
        var actual = expected
        actual
            .mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked |
            kAudioFormatFlagIsNonInterleaved
        actual.mBitsPerChannel = 16
        actual.mBytesPerFrame = 2
        actual.mBytesPerPacket = 2
        XCTAssertFalse(AudioClientFormatValidation.matches(actual, expected: expected))
    }

    func testCompressedReadbackWithMatchingRateAndChannelsIsRejected() {
        var actual = expected
        actual.mFormatID = kAudioFormatMPEG4AAC
        XCTAssertFalse(AudioClientFormatValidation.matches(actual, expected: expected))
    }

    func testDifferentInterleavingIsRejected() {
        var actual = expected
        actual.mFormatFlags &= ~kAudioFormatFlagIsNonInterleaved
        actual.mBytesPerFrame = 8
        actual.mBytesPerPacket = 8
        XCTAssertFalse(AudioClientFormatValidation.matches(actual, expected: expected))
    }

    func testMalformedPacketLayoutAndNonfiniteRateAreRejected() {
        var actual = expected
        actual.mBytesPerPacket = 0
        XCTAssertFalse(AudioClientFormatValidation.matches(actual, expected: expected))
        for rate in [Double.nan, .infinity, 0] {
            actual = expected
            actual.mSampleRate = rate
            XCTAssertFalse(AudioClientFormatValidation.matches(actual, expected: expected))
        }
    }

    func testShortOrEmptyHardwareMetadataCannotInventMono() {
        let size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        XCTAssertTrue(AudioClientFormatValidation.isValidHardwareFormat(expected, size: size))
        XCTAssertFalse(AudioClientFormatValidation.isValidHardwareFormat(expected, size: 8))
        XCTAssertFalse(AudioClientFormatValidation.isValidHardwareFormat(AudioStreamBasicDescription(), size: size))
        var actual = expected
        actual.mChannelsPerFrame = 0
        XCTAssertFalse(AudioClientFormatValidation.isValidHardwareFormat(actual, size: size))
        actual = expected
        actual.mSampleRate = .nan
        XCTAssertFalse(AudioClientFormatValidation.isValidHardwareFormat(actual, size: size))
    }
}

@MainActor
final class RoutingRateChangeRecoveryTests: XCTestCase {
    private final class Gate {
        let entered = XCTestExpectation(description: "rate-change delay entered")
        private var continuation: CheckedContinuation<Void, Never>?

        func wait() async {
            await withCheckedContinuation {
                continuation = $0
                entered.fulfill()
            }
        }

        func release() {
            continuation?.resume()
            continuation = nil
        }
    }

    func testDisableDuringDelayRejectsPendingRestartAndStaleNotification() async {
        let recovery = RoutingSampleRateRecovery()
        let gate = Gate()
        let oldGeneration = recovery.generation
        var restarts = 0
        let task = recovery.schedule(generation: oldGeneration, wait: { await gate.wait() }) { restarts += 1 }
        await fulfillment(of: [gate.entered], timeout: 2)
        recovery.cancel()
        gate.release()
        await task?.value
        XCTAssertNil(recovery.schedule(generation: oldGeneration, wait: {}) { restarts += 1 })
        XCTAssertEqual(restarts, 0)
    }

    func testRepeatedNotificationsCoalesceAndOldTaskCannotRestart() async {
        let recovery = RoutingSampleRateRecovery()
        let first = Gate()
        let second = Gate()
        var restarts = 0
        let firstTask = recovery
            .schedule(generation: recovery.generation, wait: { await first.wait() }) { restarts += 1 }
        await fulfillment(of: [first.entered], timeout: 2)
        let secondTask = recovery
            .schedule(generation: recovery.generation, wait: { await second.wait() }) { restarts += 1 }
        await fulfillment(of: [second.entered], timeout: 2)
        first.release()
        await firstTask?.value
        XCTAssertEqual(restarts, 0)
        second.release()
        await secondTask?.value
        XCTAssertEqual(restarts, 1)
    }

    func testBackendOrDeviceReplacementRejectsOldGeneration() async {
        let recovery = RoutingSampleRateRecovery()
        let oldGeneration = recovery.generation
        recovery.cancel()
        var restarts = 0
        XCTAssertNil(recovery.schedule(generation: oldGeneration, wait: {}) { restarts += 100 })
        let task = recovery.schedule(generation: recovery.generation, wait: {}) { restarts += 1 }
        await task?.value
        XCTAssertEqual(restarts, 1)
    }

    func testFailedDelayCannotRestart() async {
        let recovery = RoutingSampleRateRecovery()
        var restarts = 0
        let task = recovery
            .schedule(generation: recovery.generation, wait: { throw CancellationError() }) { restarts += 1 }
        await task?.value
        XCTAssertEqual(restarts, 0)
    }

    func testInitialReconciliationCatchesDriftWithoutADeviceNotification() {
        let recovery = RoutingSampleRateRecovery()
        var restarts = 0
        XCTAssertTrue(recovery
            .reconcile(rates: .init(input: 96000, output: 48000), currentRate: 48000) { restarts += 1 })
        XCTAssertEqual(restarts, 1)
    }

    func testInitialReconciliationRejectsMissingOrInvalidMetadata() {
        let recovery = RoutingSampleRateRecovery()
        XCTAssertFalse(recovery
            .reconcile(rates: nil, currentRate: 48000) { XCTFail("Invalid metadata cannot start recovery") })
        XCTAssertFalse(recovery.reconcile(rates: .init(input: .nan, output: 48000), currentRate: 48000) {
            XCTFail("Invalid metadata cannot start recovery")
        })
    }

    func testInitialReconciliationLeavesMatchingRatesAlone() {
        let recovery = RoutingSampleRateRecovery()
        XCTAssertTrue(recovery.reconcile(rates: .init(input: 48000, output: 48000), currentRate: 48000) {
            XCTFail("Stable startup must not restart")
        })
    }
}

final class CoreAudioOutputTests: XCTestCase {
    private func checkLayout(channels: [UInt32], frames: Int) {
        let ring = SPSCRingBuffer()
        ring.allocate(capacityFrames: 256)
        let left = [Float](repeating: 0.75, count: frames)
        let right = [Float](repeating: -0.25, count: frames)
        _ = ring.write(inL: left, inR: right, frameCount: frames)
        let size = MemoryLayout<AudioBufferList>.size + (channels.count - 1) * MemoryLayout<AudioBuffer>.stride
        guard let memory = malloc(size) else { XCTFail("Audio buffer allocation failed"); return }
        let list = UnsafeMutableAudioBufferListPointer(memory.bindMemory(to: AudioBufferList.self, capacity: 1))
        list.unsafeMutablePointer.pointee.mNumberBuffers = UInt32(channels.count)
        let scratchLeft = UnsafeMutablePointer<Float>.allocate(capacity: max(1, frames))
        let scratchRight = UnsafeMutablePointer<Float>.allocate(capacity: max(1, frames))
        var allocations: [UnsafeMutablePointer<Float>] = []
        for index in channels.indices {
            let count = frames * Int(channels[index])
            let pointer = UnsafeMutablePointer<Float>.allocate(capacity: count + 2)
            pointer.initialize(repeating: -999, count: count + 2)
            allocations.append(pointer)
            list[index] = AudioBuffer(
                mNumberChannels: channels[index], mDataByteSize: UInt32(count * MemoryLayout<Float>.stride),
                mData: pointer.advanced(by: 1)
            )
        }
        defer {
            allocations.forEach { $0.deallocate() }
            scratchLeft.deallocate()
            scratchRight.deallocate()
            free(list.unsafeMutablePointer)
        }
        XCTAssertEqual(CoreAudioOutput.render(
            ring: ring, buffers: list, frames: frames, capacity: frames, targetFill: 0,
            scratchLeft: scratchLeft, scratchRight: scratchRight
        ), noErr)
        for index in channels.indices {
            let count = frames * Int(channels[index])
            XCTAssertEqual(allocations[index][0], -999)
            XCTAssertEqual(allocations[index][count + 1], -999)
            XCTAssertEqual(list[index].mDataByteSize, UInt32(count * MemoryLayout<Float>.stride))
            for sample in 0..<count {
                let expected: Float = channels == [1] ? 0.25 :
                    (channels == [2] ? (sample.isMultiple(of: 2) ? 0.75 : -0.25) : (index == 0 ? 0.75 : -0.25))
                XCTAssertEqual(allocations[index][sample + 1], expected, accuracy: 0.0001)
            }
        }
    }

    func testMonoAndStereoLayoutsPreserveBounds() {
        for frames in [0, 1, 7, 128] {
            for channels: [UInt32] in [[1], [2], [1, 1]] {
                checkLayout(channels: channels, frames: frames)
            }
        }
    }

    func testInvalidBufferDoesNotConsumeAudio() {
        let ring = SPSCRingBuffer()
        ring.allocate(capacityFrames: 256)
        _ = ring.write(inL: [0.75], inR: [-0.25], frameCount: 1)
        var output: Float = -999
        var list = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(
            mNumberChannels: 1, mDataByteSize: 0, mData: nil
        ))
        withUnsafeMutablePointer(to: &output) { pointer in
            list.mBuffers.mData = UnsafeMutableRawPointer(pointer)
            withUnsafeMutablePointer(to: &list) { listPointer in
                let buffers = UnsafeMutableAudioBufferListPointer(listPointer)
                XCTAssertEqual(CoreAudioOutput.render(
                    ring: ring, buffers: buffers, frames: 1, capacity: 1, targetFill: 0,
                    scratchLeft: nil, scratchRight: nil
                ), kAudio_ParamError)
            }
        }
        XCTAssertEqual(output, -999)
        var left: Float = 0
        var right: Float = 0
        ring.readNonInterleaved(outL: &left, outR: &right, framesRequested: 1)
        XCTAssertEqual(left, 0.75)
        XCTAssertEqual(right, -0.25)
    }

    func testMonoPeakDoesNotReadPastAdvertisedBytes() throws {
        let page = Int(getpagesize())
        let memory = try XCTUnwrap(mmap(nil, page * 2, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0))
        XCTAssertNotEqual(memory, MAP_FAILED)
        guard memory != MAP_FAILED else { return }
        defer { munmap(memory, page * 2) }
        XCTAssertEqual(mprotect(memory.advanced(by: page), page, PROT_NONE), 0)
        let pointer = memory.advanced(by: page - 4 * MemoryLayout<Float>.stride).assumingMemoryBound(to: Float.self)
        pointer.initialize(repeating: -0.25, count: 4)
        var list = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(
            mNumberChannels: 1, mDataByteSize: 4 * UInt32(MemoryLayout<Float>.stride), mData: pointer
        ))
        withUnsafeMutablePointer(to: &list) {
            XCTAssertEqual(CoreAudioOutput.peak(buffers: UnsafeMutableAudioBufferListPointer($0), frames: 8), 0.25)
        }
    }

    func testNilDataFallbackPreservesMonoAndStereoLayoutsAcrossCallbackSizes() {
        let capacity = 128
        let left = UnsafeMutablePointer<Float>.allocate(capacity: capacity * 2)
        let right = UnsafeMutablePointer<Float>.allocate(capacity: capacity)
        defer { left.deallocate(); right.deallocate() }
        for channels: [UInt32] in [[1], [2], [1, 1]] {
            let size = MemoryLayout<AudioBufferList>.size + (channels.count - 1) * MemoryLayout<AudioBuffer>.stride
            guard let memory = malloc(size) else { XCTFail("Buffer allocation failed"); return }
            defer { free(memory) }
            let pointer = memory.bindMemory(to: AudioBufferList.self, capacity: 1)
            pointer.pointee.mNumberBuffers = UInt32(channels.count)
            let buffers = UnsafeMutableAudioBufferListPointer(pointer)
            for frames in [1, 7, capacity] {
                for index in channels.indices {
                    buffers[index] = AudioBuffer(mNumberChannels: channels[index], mDataByteSize: 0, mData: nil)
                }
                XCTAssertEqual(
                    CoreAudioOutput.provideFallback(buffers: buffers, capacity: capacity, left: left, right: right),
                    noErr
                )
                XCTAssertEqual(buffers.map(\.mNumberChannels), channels)
                let ring = SPSCRingBuffer()
                ring.allocate(capacityFrames: 256)
                _ = ring.write(
                    inL: [Float](repeating: 0.75, count: frames),
                    inR: [Float](repeating: -0.25, count: frames),
                    frameCount: frames
                )
                XCTAssertEqual(CoreAudioOutput.render(
                    ring: ring, buffers: buffers, frames: frames, capacity: capacity, targetFill: 0,
                    scratchLeft: left, scratchRight: right
                ), noErr)
                XCTAssertEqual(left[0], channels == [1] ? 0.25 : 0.75)
                if channels == [2] { XCTAssertEqual(left[1], -0.25) }
                if channels == [1, 1] { XCTAssertEqual(right[0], -0.25) }
                XCTAssertEqual(buffers[0].mDataByteSize, UInt32(frames * Int(channels[0]) * MemoryLayout<Float>.stride))
            }
        }
    }
}

@MainActor
final class RoutingWakeRecoveryTests: XCTestCase {
    func testAutomaticRecoveryFailuresPreserveEnabledIntentAcrossBackends() throws {
        try withRoutingDefaults { defaults in
            for reason in RoutingRequestReason.allCases where reason != .request {
                for preference in [AudioRoutingBackendPreference.native, .blackHole, .automatic] {
                    for initialIntent in [false, true] {
                        for requestedPersistence in [false, true] {
                            defaults.set(initialIntent, forKey: "eqWasEnabled")
                            var enabled = true
                            var running = true
                            var active = true
                            var attempts: [Bool] = []
                            var cleanup: [Bool] = []
                            var rateCleanupCalls = 0
                            let failure: (Bool) -> Bool = { persist in
                                attempts.append(persist)
                                running = false
                                active = false
                                if persist { defaults.set(false, forKey: "eqWasEnabled") }
                                return false
                            }
                            let result = AudioRoutingRequestPolicy.start(
                                reason: reason,
                                persistEnabledStateOnFailure: requestedPersistence,
                                operation: { persist in
                                    AudioRoutingStartPolicy.start(
                                        preference: preference,
                                        persistEnabledStateOnFailure: persist,
                                        native: failure, blackHole: failure, onFallback: {}
                                    )
                                },
                                cleanup: { persist in
                                    cleanup.append(persist)
                                    enabled = false
                                    running = false
                                    active = false
                                    if persist { defaults.set(false, forKey: "eqWasEnabled") }
                                },
                                restoreSampleRates: { rateCleanupCalls += 1 },
                                preservedOutputIsCurrent: { false },
                                restoreOutput: { XCTFail("Unexpected output restoration") }
                            )
                            XCTAssertFalse(result)
                            XCTAssertFalse(enabled)
                            XCTAssertFalse(running)
                            XCTAssertFalse(active)
                            XCTAssertFalse(attempts.isEmpty)
                            XCTAssertTrue(attempts.allSatisfy { !$0 })
                            XCTAssertEqual(cleanup, [false])
                            XCTAssertEqual(rateCleanupCalls, 1)
                            XCTAssertEqual(defaults.bool(forKey: "eqWasEnabled"), initialIntent)
                        }
                    }
                }
            }
        }
    }

    func testRecoveryPreflightFailureStopsBeforeRestoringPreservedOutput() {
        var enabled = true
        var rateDebt = true
        var output = "virtual"
        var calls: [String] = []
        let result = AudioRoutingRequestPolicy.start(
            reason: .sampleRateChanged,
            persistEnabledStateOnFailure: true,
            operation: { persist in calls.append("operation:\(persist)"); return false },
            cleanup: { persist in
                calls.append("cleanup:\(persist)")
                enabled = false
            },
            restoreSampleRates: {
                XCTAssertFalse(enabled)
                calls.append("restoreRates")
                rateDebt = false
            },
            preservedOutputIsCurrent: {
                XCTAssertFalse(enabled)
                calls.append("probe")
                return output == "virtual"
            },
            restoreOutput: {
                calls.append("restore")
                output = "physical"
            }
        )
        XCTAssertFalse(result)
        XCTAssertFalse(rateDebt)
        XCTAssertEqual(output, "physical")
        XCTAssertEqual(calls, ["operation:false", "cleanup:false", "restoreRates", "probe", "restore"])
    }

    func testNativeRecoveryFailurePreservesBackendRestoredPhysicalOutput() {
        var output = "attemptedPhysical"
        var cleanups = 0
        let result = AudioRoutingRequestPolicy.start(
            reason: .deviceRecovery,
            persistEnabledStateOnFailure: true,
            operation: { _ in output = "previousPhysical"; return false },
            cleanup: { persist in
                XCTAssertFalse(persist)
                cleanups += 1
            },
            restoreSampleRates: {},
            preservedOutputIsCurrent: { output == "virtual" },
            restoreOutput: { output = "wrongPhysical"; XCTFail("Must retain backend recovery output") }
        )
        XCTAssertFalse(result)
        XCTAssertEqual(cleanups, 1)
        XCTAssertEqual(output, "previousPhysical")
    }

    func testRecoveryFallbackSuccessDoesNotRunFinalCleanup() {
        for nativeSucceeds in [false, true] {
            var calls: [String] = []
            let result = AudioRoutingRequestPolicy.start(
                reason: .backendPreferenceChanged,
                persistEnabledStateOnFailure: true,
                operation: { persist in
                    AudioRoutingStartPolicy.start(
                        preference: .automatic,
                        persistEnabledStateOnFailure: persist,
                        native: { calls.append("native:\($0)"); return nativeSucceeds },
                        blackHole: { calls.append("blackHole:\($0)"); return true },
                        onFallback: { calls.append("fallback") }
                    )
                },
                cleanup: { _ in XCTFail("Successful route must remain running") },
                restoreSampleRates: { XCTFail("No rate restoration after success") },
                preservedOutputIsCurrent: { XCTFail("No output probe after success"); return true },
                restoreOutput: { XCTFail("No restoration after success") }
            )
            XCTAssertTrue(result)
            XCTAssertEqual(calls, nativeSucceeds ? ["native:false"] : ["native:false", "fallback", "blackHole:false"])
        }
    }

    func testManualRequestsRetainExplicitFailurePersistence() throws {
        try withRoutingDefaults { defaults in
            for persist in [false, true] {
                defaults.set(true, forKey: "eqWasEnabled")
                var observed: [Bool] = []
                let result = AudioRoutingRequestPolicy.start(
                    reason: .request,
                    persistEnabledStateOnFailure: persist,
                    operation: { effective in
                        observed.append(effective)
                        if effective { defaults.set(false, forKey: "eqWasEnabled") }
                        return false
                    },
                    cleanup: { _ in XCTFail("Manual caller owns its failure policy") },
                    restoreSampleRates: { XCTFail("Manual rate handling changed") },
                    preservedOutputIsCurrent: { XCTFail("Manual output handling changed"); return true },
                    restoreOutput: { XCTFail("Manual output handling changed") }
                )
                XCTAssertFalse(result)
                XCTAssertEqual(observed, [persist])
                XCTAssertEqual(defaults.bool(forKey: "eqWasEnabled"), !persist)
            }
        }
    }

    func testDeviceLossStopsRuntimeWithoutChangingSavedIntent() throws {
        try withRoutingDefaults { defaults in
            for initialIntent in [false, true] {
                defaults.set(initialIntent, forKey: "eqWasEnabled")
                var enabled = true
                var running = true
                var calls: [Bool] = []
                AudioRoutingRequestPolicy.stop { persist in
                    calls.append(persist)
                    enabled = false
                    running = false
                    if persist { defaults.set(false, forKey: "eqWasEnabled") }
                }
                XCTAssertFalse(enabled)
                XCTAssertFalse(running)
                XCTAssertEqual(calls, [false])
                XCTAssertEqual(defaults.bool(forKey: "eqWasEnabled"), initialIntent)
            }
        }
    }

    private func withRoutingDefaults(_ body: (UserDefaults) -> Void) throws {
        let suite = "RoutingRequestPolicyTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        body(defaults)
    }

    func testRoutingStartSelectsBackendAndPreservesFailurePersistence() {
        typealias Scenario = (AudioRoutingBackendPreference, Bool, Bool, Bool, Bool, [String])
        let scenarios: [Scenario] = [
            (.automatic, true, false, true, true, ["native:false"]),
            (.automatic, false, true, true, true, ["native:false", "fallback", "blackHole:true"]),
            (.automatic, false, false, true, false, ["native:false", "fallback", "blackHole:true"]),
            (.automatic, false, false, false, false, ["native:false", "fallback", "blackHole:false"]),
            (.native, false, true, true, false, ["native:true"]),
            (.native, false, true, false, false, ["native:false"]),
            (.blackHole, true, true, true, true, ["blackHole:true"]),
            (.blackHole, true, false, false, false, ["blackHole:false"])
        ]
        for (preference, nativeSucceeds, blackHoleSucceeds, persist, expectedResult, expectedCalls) in scenarios {
            var calls: [String] = []
            let result = AudioRoutingStartPolicy.start(
                preference: preference,
                persistEnabledStateOnFailure: persist,
                native: { calls.append("native:\($0)"); return nativeSucceeds },
                blackHole: { calls.append("blackHole:\($0)"); return blackHoleSucceeds },
                onFallback: { calls.append("fallback") }
            )
            XCTAssertEqual(result, expectedResult)
            XCTAssertEqual(calls, expectedCalls)
        }
    }

    func testNativeTapPermissionFailureFallsBackWithoutClearingEnabledIntent() throws {
        guard #available(macOS 14.4, *) else { throw XCTSkip("Process Tap requires macOS 14.4") }
        let suite = "RoutingWakeRecoveryTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "eqWasEnabled")
        let denied = OSStatus(0x7065_726D)
        var tapAttempts = 0
        let engine = ProcessTapEngine(deviceUIDProvider: { _ in "test-output" }, createTap: { _, tapID in
            XCTAssertEqual(tapID, kAudioObjectUnknown)
            tapAttempts += 1
            return denied
        })
        var attempts: [String] = []
        var activeBackend: ActiveAudioRoutingBackend = .none
        var processingPrepared = false
        let result = AudioRoutingStartPolicy.start(
            preference: .automatic,
            persistEnabledStateOnFailure: true,
            native: { persistFailure in
                attempts.append("native")
                let start = engine.start(outputDeviceID: 1) { _, _ in processingPrepared = true }
                guard case let .failure(error) = start else {
                    XCTFail("Expected permission failure")
                    return true
                }
                XCTAssertEqual(error, .createTap(denied))
                engine.stop()
                if persistFailure { defaults.set(false, forKey: "eqWasEnabled") }
                return false
            },
            blackHole: { _ in
                attempts.append("blackHole")
                XCTAssertTrue(defaults.bool(forKey: "eqWasEnabled"))
                activeBackend = .blackHole
                return true
            },
            onFallback: { attempts.append("fallback") }
        )
        engine.stop()
        XCTAssertTrue(result)
        XCTAssertEqual(attempts, ["native", "fallback", "blackHole"])
        XCTAssertEqual(activeBackend, .blackHole)
        XCTAssertEqual(tapAttempts, 1)
        XCTAssertFalse(processingPrepared)
        XCTAssertTrue(defaults.bool(forKey: "eqWasEnabled"))
    }

    private final class Gate {
        let entered: XCTestExpectation
        private var continuation: CheckedContinuation<Void, Never>?

        init(name: String) {
            entered = XCTestExpectation(description: name + " entered")
        }

        func wait() async {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                entered.fulfill()
            }
        }

        func release() {
            continuation?.resume()
            continuation = nil
        }
    }

    func testDisableDuringWakeDelayDoesNotRefreshOrRestart() async {
        let recovery = RoutingWakeRecovery()
        let gate = Gate(name: "delay")
        var refreshes = 0
        var restarts = 0
        XCTAssertTrue(recovery.suspend(isActive: true))
        let pending = recovery.resume(
            wait: { await gate.wait() },
            refresh: { refreshes += 1 },
            restart: { restarts += 1 }
        )
        await fulfillment(of: [gate.entered], timeout: 2)
        recovery.cancel()
        gate.release()
        await pending?.value
        XCTAssertEqual(refreshes, 0)
        XCTAssertEqual(restarts, 0)
        XCTAssertFalse(recovery.isPending)
        XCTAssertFalse(recovery.shouldResume)
    }

    func testSecondSleepPreservesIntentAndRejectsStaleWake() async {
        let recovery = RoutingWakeRecovery()
        let first = Gate(name: "first")
        let second = Gate(name: "second")
        let restarted = expectation(description: "new wake restarted")
        var restarts = 0
        XCTAssertTrue(recovery.suspend(isActive: true))
        let firstTask = recovery.resume(wait: { await first.wait() }, refresh: {}, restart: { restarts += 1 })
        await fulfillment(of: [first.entered], timeout: 2)
        XCTAssertTrue(recovery.suspend(isActive: false))
        let secondTask = recovery.resume(
            wait: { await second.wait() },
            refresh: {},
            restart: { restarts += 1; restarted.fulfill() }
        )
        await fulfillment(of: [second.entered], timeout: 2)
        first.release()
        await firstTask?.value
        XCTAssertTrue(recovery.isPending)
        XCTAssertEqual(restarts, 0)
        second.release()
        await fulfillment(of: [restarted], timeout: 2)
        await secondTask?.value
        XCTAssertEqual(restarts, 1)
        XCTAssertFalse(recovery.isPending)
    }

    func testDisableDuringDeviceRefreshDoesNotRestart() async {
        let recovery = RoutingWakeRecovery()
        let refresh = Gate(name: "refresh")
        var restarts = 0
        XCTAssertTrue(recovery.suspend(isActive: true))
        let pending = recovery.resume(wait: {}, refresh: { await refresh.wait() }, restart: { restarts += 1 })
        await fulfillment(of: [refresh.entered], timeout: 2)
        recovery.cancel()
        refresh.release()
        await pending?.value
        XCTAssertEqual(restarts, 0)
        XCTAssertFalse(recovery.isPending)
    }
}

final class AudioEngineBandModeTests: XCTestCase {
    private let coreAudioEngine = CoreAudioEngine()
    private let suiteName = "AudioEngineBandModeTests.\(UUID().uuidString)"
    private var isolatedEngine: AudioEngine?
    private var originalPlaybackSnapshot: Data?

    override func setUpWithError() throws {
        try super.setUpWithError()
        originalPlaybackSnapshot = UserDefaults.standard.data(forKey: "lastPlayback.snapshot")
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        isolatedEngine = AudioEngine(
            defaults: defaults,
            coreAudioEngine: self.coreAudioEngine,
            enableRouting: { _ in true },
            disableRouting: { _ in }
        )
    }

    override func tearDown() {
        if let engine = isolatedEngine {
            engine.bandMode = .tenBand
            engine.syncBandsToMode()
            engine.setPreampGain(0)
            engine.setOutputBoostGain(0)
            engine.resetAllBands()
        }
        isolatedEngine = nil
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        self.coreAudioEngine.setEnabled(false)
        XCTAssertEqual(UserDefaults.standard.data(forKey: "lastPlayback.snapshot"), originalPlaybackSnapshot)
        super.tearDown()
    }

    // MARK: - Same-turn mode switch + apply

    func testAutoEQBandModeMatchesRestoredAudioEngineMode() {
        XCTAssertEqual(AutoEQView.BandMode(audioEngineMode: .tenBand), .ten)
        XCTAssertEqual(AutoEQView.BandMode(audioEngineMode: .thirtyOneBand), .thirtyOne)
        XCTAssertEqual(AutoEQView.BandMode.ten.audioEngineMode, .tenBand)
        XCTAssertEqual(AutoEQView.BandMode.thirtyOne.audioEngineMode, .thirtyOneBand)
    }

    func testApplyEQValues_rightAfterSwitchTo31Band_appliesAll31() throws {
        let engine = try XCTUnwrap(isolatedEngine)
        engine.bandMode = .tenBand
        engine.syncBandsToMode()

        let values = (0..<31).map { Float($0 % 5) - 2 }

        // Same main-loop turn as the mode switch — the didSet rebuild has not run yet
        engine.bandMode = .thirtyOneBand
        engine.applyEQValues(values)

        XCTAssertEqual(engine.bands.count, 31, "bands must be rebuilt before applying")
        XCTAssertEqual(engine.bands.map(\.gain), values, "all 31 gains must be applied")
    }

    func testApplyEQValues_rightAfterSwitchBackTo10Band_appliesAll10() throws {
        let engine = try XCTUnwrap(isolatedEngine)
        engine.bandMode = .thirtyOneBand
        engine.syncBandsToMode()

        let values: [Float] = [1, -1, 2, -2, 3, -3, 4, -4, 5, -5]

        engine.bandMode = .tenBand
        engine.applyEQValues(values)

        XCTAssertEqual(engine.bands.count, 10, "bands must be rebuilt before applying")
        XCTAssertEqual(engine.bands.map(\.gain), values, "all 10 gains must be applied")
    }

    func testApplyEQValues_countMismatch_stillRejected() throws {
        let engine = try XCTUnwrap(isolatedEngine)
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
            defaults: defaults, coreAudioEngine: self.coreAudioEngine,
            enableRouting: { _ in true },
            disableRouting: { _ in }
        )
        engine.resetAllBands()
        engine.setPreampGain(0)
        engine.setPreampGain(6)

        let filter = try XCTUnwrap(self.coreAudioEngine.vdspFilter)
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

    func testCoreAudioRenderBypassFollowsEnabledState() throws {
        let audioEngine = try XCTUnwrap(isolatedEngine)
        let coreEngine = self.coreAudioEngine
        audioEngine.bandMode = .tenBand
        audioEngine.syncBandsToMode()
        audioEngine.resetAllBands()
        audioEngine.setOutputBoostGain(0)
        audioEngine.setPreampGain(6)
        defer {
            coreEngine.setEnabled(false)
            audioEngine.setPreampGain(0)
        }

        var left = [Float](repeating: 0.25, count: 64)
        var right = [Float](repeating: 0.25, count: 64)

        coreEngine.setEnabled(false)
        left.withUnsafeMutableBufferPointer { leftBuffer in
            right.withUnsafeMutableBufferPointer { rightBuffer in
                guard let leftAddress = leftBuffer.baseAddress,
                      let rightAddress = rightBuffer.baseAddress else { return XCTFail("Missing test buffers") }
                coreEngine.processStereoInPlace(
                    left: leftAddress,
                    right: rightAddress,
                    frameCount: leftBuffer.count
                )
            }
        }
        XCTAssertEqual(left, [Float](repeating: 0.25, count: 64))
        XCTAssertEqual(right, [Float](repeating: 0.25, count: 64))

        coreEngine.setEnabled(true)
        left = [Float](repeating: 0.25, count: 64)
        right = [Float](repeating: 0.25, count: 64)
        left.withUnsafeMutableBufferPointer { leftBuffer in
            right.withUnsafeMutableBufferPointer { rightBuffer in
                guard let leftAddress = leftBuffer.baseAddress,
                      let rightAddress = rightBuffer.baseAddress else { return XCTFail("Missing test buffers") }
                coreEngine.processStereoInPlace(
                    left: leftAddress,
                    right: rightAddress,
                    frameCount: leftBuffer.count
                )
            }
        }
        let expected = Float(0.25 * pow(10.0, 6.0 / 20.0))
        XCTAssertEqual(left[0], expected, accuracy: 0.0001)
        XCTAssertEqual(right[0], expected, accuracy: 0.0001)
    }

    func testConcurrentFilterSwapAndRenderStress() {
        let coreEngine = self.coreAudioEngine
        coreEngine.setEnabled(true)
        coreEngine.applyFixedBandEQ(Array(repeating: 0, count: 10))
        let renderFinished = expectation(description: "Concurrent render finished")

        DispatchQueue.global(qos: .userInitiated).async {
            var left = [Float](repeating: 0.05, count: 128)
            var right = [Float](repeating: 0.05, count: 128)
            for _ in 0..<2000 {
                left.withUnsafeMutableBufferPointer { leftBuffer in
                    right.withUnsafeMutableBufferPointer { rightBuffer in
                        guard let leftAddress = leftBuffer.baseAddress,
                              let rightAddress = rightBuffer.baseAddress else { return }
                        coreEngine.processStereoInPlace(
                            left: leftAddress,
                            right: rightAddress,
                            frameCount: leftBuffer.count
                        )
                    }
                }
            }
            renderFinished.fulfill()
        }

        for iteration in 0..<250 {
            let gain = Float(iteration % 7) - 3
            coreEngine.applyFixedBandEQ(Array(repeating: gain, count: 10))
        }

        wait(for: [renderFinished], timeout: 10)
        coreEngine.clearEQ()
    }

    func testConcurrentRoomFilterSwapAndRenderStress() {
        let engine = self.coreAudioEngine
        engine.setEnabled(true)
        engine.applyFixedBandEQ([Float](repeating: 0, count: 10))
        defer {
            engine.clearRoomNotchFilters()
            engine.clearEQ()
        }
        let rendered = expectation(description: "Room render finished")
        DispatchQueue.global(qos: .userInitiated).async {
            for _ in 0..<2000 {
                var left = [Float](repeating: 0.01, count: 128)
                var right = left
                left.withUnsafeMutableBufferPointer { l in
                    right.withUnsafeMutableBufferPointer { r in
                        guard let left = l.baseAddress, let right = r.baseAddress else {
                            XCTFail("Missing audio buffer")
                            return
                        }
                        engine.processStereoInPlace(left: left, right: right, frameCount: 128)
                    }
                }
                XCTAssertTrue(left.allSatisfy(\.isFinite))
                XCTAssertTrue(right.allSatisfy(\.isFinite))
            }
            rendered.fulfill()
        }
        for iteration in 0..<250 {
            if iteration.isMultiple(of: 3) {
                engine.clearRoomNotchFilters()
            } else {
                engine.applyRoomNotchFilters([(frequency: 125, gain: -6, q: Float(iteration % 8 + 1))])
            }
        }
        wait(for: [rendered], timeout: 10)
    }

    func testOutputBoostIsClampedAndPersisted() throws {
        let suiteName = "AudioEngineBandModeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let engine = AudioEngine(
            defaults: defaults, coreAudioEngine: self.coreAudioEngine,
            enableRouting: { _ in true },
            disableRouting: { _ in }
        )

        engine.setOutputBoostGain(20)

        XCTAssertEqual(engine.outputBoostGain, 12)
        XCTAssertEqual(defaults.float(forKey: "outputBoostGain"), 12)
    }

    func testCoreAudioOutputBoostUsesSharedMaximum() {
        XCTAssertEqual(CoreAudioEngine.sanitizedOutputBoost(12), 12)
        XCTAssertEqual(CoreAudioEngine.sanitizedOutputBoost(20), OutputSafetyProcessor.maximumBoostDB)
        XCTAssertEqual(CoreAudioEngine.sanitizedOutputBoost(.nan), 0)
    }

    func testAutoPreampUsesCombinedFilterResponse() {
        var gains = [Float](repeating: 0, count: 10)
        gains[5] = 6
        gains[6] = 6

        let recommended = FixedBandAutoPreamp.recommendedGain(mode: .tenBand, gains: gains)

        XCTAssertLessThan(recommended, -6)
        XCTAssertGreaterThan(recommended, -12)
    }

    func testAutoPreampLeavesFlatEQAtUnity() {
        let recommended = FixedBandAutoPreamp.recommendedGain(
            mode: .thirtyOneBand,
            gains: [Float](repeating: 0, count: 31)
        )

        XCTAssertEqual(recommended, 0, accuracy: 0.0001)
    }

    func testManualPreampIsPersisted() throws {
        let suiteName = "AudioEngineBandModeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let engine = AudioEngine(
            defaults: defaults, coreAudioEngine: self.coreAudioEngine,
            enableRouting: { _ in true },
            disableRouting: { _ in }
        )

        engine.setPreampGain(-7.5)

        XCTAssertEqual(PresetPersistence.loadPlaybackState(in: defaults)?.preamp, -7.5)
    }

    func testRestorePresetDefaultsRestoresBandsBassBoostAndPreamp() throws {
        let suiteName = "AudioEngineBandModeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let previousDefaults = PresetPersistence.defaults
        PresetPersistence.defaults = defaults
        defer {
            PresetPersistence.defaults = previousDefaults
            defaults.removePersistentDomain(forName: suiteName)
        }
        let presetGains = (0..<10).map { Float($0) - 5 }
        PresetPersistence.save(mode: .tenBand, gains: presetGains, preamp: -4.5, bassBoost: 6)
        let engine = AudioEngine(
            defaults: defaults, coreAudioEngine: self.coreAudioEngine,
            enableRouting: { _ in true },
            disableRouting: { _ in }
        )
        engine.bandMode = .thirtyOneBand
        engine.syncBandsToMode()
        engine.applyEQValues([Float](repeating: 12, count: 31))
        engine.setPreampGain(8)

        XCTAssertTrue(engine.restorePresetDefaults())

        let expected = zip(presetGains, EQBandMode.tenBand.frequencies).map { gain, frequency in
            gain + Float(BassBoostCurve.gain(at: Double(frequency), amount: 6))
        }
        XCTAssertEqual(engine.bandMode, .tenBand)
        XCTAssertEqual(engine.bands.map(\.gain), expected)
        XCTAssertEqual(engine.preampGain, -4.5)
        XCTAssertEqual(PresetPersistence.loadPlaybackState(in: defaults)?.gains, expected)
    }

    func testRestorePresetDefaultsWithoutPresetLeavesCurrentValuesUntouched() throws {
        let suiteName = "AudioEngineBandModeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let previousDefaults = PresetPersistence.defaults
        PresetPersistence.defaults = defaults
        defer {
            PresetPersistence.defaults = previousDefaults
            defaults.removePersistentDomain(forName: suiteName)
        }
        let engine = AudioEngine(
            defaults: defaults, coreAudioEngine: self.coreAudioEngine,
            enableRouting: { _ in true },
            disableRouting: { _ in }
        )
        let customGains = (0..<10).map { Float($0) }
        engine.applyEQValues(customGains)
        engine.setPreampGain(3)

        XCTAssertFalse(engine.restorePresetDefaults())
        XCTAssertEqual(engine.bands.map(\.gain), customGains)
        XCTAssertEqual(engine.preampGain, 3)
    }

    // MARK: - CoreAudioEngine guard rails

    // Раніше frequencies[index] за масивом з 31 значення падав out-of-bounds.
    func testApplyFixedBandEQ_oversizedGains_doesNotCrash() {
        let gains = [Float](repeating: 1.0, count: 31)

        self.coreAudioEngine.applyFixedBandEQ(gains, preamp: 0)

        // Повернути конфіг у чистий 10-band стан
        self.coreAudioEngine.applyFixedBandEQ([Float](repeating: 0, count: 10), preamp: 0)
    }

    // MARK: - Startup state persistence

    func testSetEnabled_routingFailureWithoutPersistence_preservesIntent() throws {
        let suiteName = "AudioEngineBandModeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: "eqWasEnabled")
        var routerPersistence: Bool?
        let engine = AudioEngine(
            defaults: defaults, coreAudioEngine: self.coreAudioEngine,
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
        XCTAssertFalse(self.coreAudioEngine.isEnabled)
    }

    func testSetEnabled_routingFailureFromUserAction_disablesFutureRestore() throws {
        let suiteName = "AudioEngineBandModeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: "eqWasEnabled")
        let engine = AudioEngine(
            defaults: defaults, coreAudioEngine: self.coreAudioEngine,
            enableRouting: { _ in false },
            disableRouting: { _ in }
        )

        let succeeded = engine.setEnabled(true, persistState: true)

        XCTAssertFalse(succeeded)
        XCTAssertFalse(defaults.bool(forKey: "eqWasEnabled"))
        XCTAssertFalse(self.coreAudioEngine.isEnabled)
    }

    func testSetEnabled_routingSuccessFromUserAction_persistsEnabledState() throws {
        let suiteName = "AudioEngineBandModeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(false, forKey: "eqWasEnabled")
        var routerPersistence: Bool?
        let engine = AudioEngine(
            defaults: defaults, coreAudioEngine: self.coreAudioEngine,
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
        XCTAssertTrue(self.coreAudioEngine.isEnabled)
    }

    func testRoutingControlsDelegateToAudioEngine() throws {
        let suiteName = "AudioEngineBandModeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var enableRequests: [Bool] = []
        var disableRequests: [Bool] = []
        let engine = AudioEngine(
            defaults: defaults, coreAudioEngine: self.coreAudioEngine,
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
        XCTAssertFalse(self.coreAudioEngine.isEnabled)
    }

    func testSetEnabled_reappliesFiltersAfterRoutingStarts() throws {
        let suiteName = "AudioEngineBandModeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let engine = AudioEngine(
            defaults: defaults, coreAudioEngine: self.coreAudioEngine,
            enableRouting: { _ in
                self.coreAudioEngine.clearEQ()
                return true
            },
            disableRouting: { _ in }
        )
        engine.setPreampGain(6)

        XCTAssertTrue(engine.setEnabled(true))

        let filter = try XCTUnwrap(self.coreAudioEngine.vdspFilter)
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
            defaults: defaults, coreAudioEngine: self.coreAudioEngine,
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
            defaults: defaults, coreAudioEngine: self.coreAudioEngine,
            enableRouting: { _ in true },
            disableRouting: { routerPersistence = $0 }
        )

        let succeeded = engine.setEnabled(false, persistState: false)

        XCTAssertTrue(succeeded)
        XCTAssertEqual(routerPersistence, false)
        XCTAssertTrue(defaults.bool(forKey: "eqWasEnabled"))
        XCTAssertFalse(self.coreAudioEngine.isEnabled)
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

    func testNewDefaultOutputRequestInvalidatesPreviousVerification() {
        XCTAssertFalse(DefaultOutputVerificationPolicy.shouldVerify(
            requestGeneration: 1,
            currentGeneration: 2
        ))
        XCTAssertTrue(DefaultOutputVerificationPolicy.shouldVerify(
            requestGeneration: 2,
            currentGeneration: 2
        ))
    }

    func testNativeAggregateCannotWinOutputPreferenceOrFallback() {
        let internalDevice = AudioDevice(
            id: 1, name: "Scarlett USB", uid: "com.denzam.SystemEQ.native.test",
            isInput: true, isOutput: true
        )
        let physical = AudioDevice(id: 2, name: "Speakers", uid: "physical", isInput: false, isOutput: true)
        let devices = [internalDevice, physical]
        XCTAssertTrue(AudioDevice.isInternalNativeDevice(uid: internalDevice.uid))
        XCTAssertFalse(internalDevice.canBeProcessedOutput)
        XCTAssertEqual(AudioOutputSelectionPolicy.bestAvailable(in: devices), physical)
        for preferred in [internalDevice.uid, nil] {
            for selected in [internalDevice.uid, nil] {
                XCTAssertEqual(AudioOutputSelectionPolicy.preferred(
                    in: devices, preferredUID: preferred, selectedUID: selected, activeUID: internalDevice.uid
                ), physical)
            }
        }
    }

    func testOutputSelectionFailsClosedWithoutEligibleDevices() {
        let devices = [
            AudioDevice(
                id: 1,
                name: "SystemEQ Native",
                uid: "com.denzam.SystemEQ.native.old",
                isInput: true,
                isOutput: true
            ),
            AudioDevice(id: 2, name: "Renamed virtual device", uid: "BlackHole2ch_UID", isInput: true, isOutput: true),
            AudioDevice(id: 3, name: "Microphone", uid: "microphone", isInput: true, isOutput: false),
            AudioDevice(id: 0, name: "Unknown", uid: "unknown", isInput: false, isOutput: true),
            AudioDevice(id: 4, name: "Missing UID", uid: "", isInput: false, isOutput: true)
        ]
        XCTAssertTrue(devices.allSatisfy { !$0.canBeProcessedOutput })
        XCTAssertNil(AudioOutputSelectionPolicy.bestAvailable(in: devices))
        for device in devices {
            XCTAssertNil(AudioOutputSelectionPolicy.preferred(
                in: devices, preferredUID: device.uid, selectedUID: device.uid, activeUID: device.uid
            ))
        }
    }

    func testValidOutputPreferencesAndPhysicalDeviceNameRemainSupported() {
        let wanted = AudioDevice(id: 1, name: "SystemEQ Native", uid: "physical-uid", isInput: false, isOutput: true)
        let usb = AudioDevice(id: 2, name: "USB Output", uid: "usb-device", isInput: false, isOutput: true)
        XCTAssertTrue(wanted.canBeProcessedOutput)
        XCTAssertEqual(AudioOutputSelectionPolicy.preferred(
            in: [usb, wanted], preferredUID: wanted.uid, selectedUID: usb.uid, activeUID: usb.uid
        ), wanted)
        XCTAssertEqual(AudioOutputSelectionPolicy.preferred(
            in: [usb, wanted], preferredUID: "disconnected", selectedUID: wanted.uid, activeUID: usb.uid
        ), wanted)
        XCTAssertEqual(AudioOutputSelectionPolicy.preferred(
            in: [usb, wanted], preferredUID: "disconnected", selectedUID: nil, activeUID: wanted.uid
        ), wanted)
    }

    func testRoutingEQIndicatorFollowsProcessingAndBypassState() {
        let core = CoreAudioEngine()
        defer { core.stop() }
        XCTAssertFalse(RoutingView.isEQActive(engine: core))
        core.prepareProcessTap(sampleRate: 48000, outputDeviceID: 1, bufferFrames: 64)
        core.markProcessTapStarted()
        XCTAssertTrue(RoutingView.isEQActive(engine: core))
        core.setEnabled(false)
        XCTAssertFalse(RoutingView.isEQActive(engine: core))
        core.setEnabled(true)
        XCTAssertTrue(RoutingView.isEQActive(engine: core))
        core.stop()
        XCTAssertFalse(RoutingView.isEQActive(engine: core))
    }

    func testFailedNativeStartRestoresPreviousPhysicalOutputOnly() {
        let previous = AudioDevice(
            id: 1,
            name: "Built-in Output",
            uid: "previous",
            isInput: false,
            isOutput: true
        )
        let attempted = AudioDevice(
            id: 2,
            name: "USB Output",
            uid: "attempted",
            isInput: false,
            isOutput: true
        )
        let blackHole = AudioDevice(
            id: 3,
            name: "BlackHole 2ch",
            uid: "blackhole",
            isInput: true,
            isOutput: true
        )

        let physicalRecovery = NativeRoutingFailureRecoveryPolicy.recovery(
            previous: previous,
            attempted: attempted,
            previousWasVirtual: false
        )
        guard case let .restore(device) = physicalRecovery else {
            return XCTFail("Expected previous physical output to be restored")
        }
        XCTAssertEqual(device.id, previous.id)
        XCTAssertEqual(device.uid, previous.uid)

        let unchangedRecovery = NativeRoutingFailureRecoveryPolicy.recovery(
            previous: attempted,
            attempted: attempted,
            previousWasVirtual: false
        )
        guard case .none = unchangedRecovery else {
            return XCTFail("Expected no restore when output did not change")
        }

        let virtualRecovery = NativeRoutingFailureRecoveryPolicy.recovery(
            previous: blackHole,
            attempted: attempted,
            previousWasVirtual: true
        )
        guard case .recoverPhysicalOutput = virtualRecovery else {
            return XCTFail("Expected physical-output recovery from BlackHole")
        }
    }

    func testProcessTapTestToneRestartResetsPhaseAndStopBypassesGeneration() {
        let engine = self.coreAudioEngine
        engine.stop()
        engine.prepareProcessTap(sampleRate: 48000, outputDeviceID: 1, bufferFrames: 64)
        engine.markProcessTapStarted()
        defer { engine.stop() }

        var left = [Float](repeating: -1, count: 64)
        var right = [Float](repeating: -1, count: 64)

        engine.startTestTone(440)
        left.withUnsafeMutableBufferPointer { leftBuffer in
            right.withUnsafeMutableBufferPointer { rightBuffer in
                guard let leftAddress = leftBuffer.baseAddress,
                      let rightAddress = rightBuffer.baseAddress else { return XCTFail("Missing test buffers") }
                engine.generateProcessTapTestToneIfNeeded(
                    left: leftAddress,
                    right: rightAddress,
                    frameCount: leftBuffer.count
                )
            }
        }
        let sampleAt440Hz = left[1]
        XCTAssertEqual(left[0], 0, accuracy: 0.000_001)
        XCTAssertEqual(left, right)

        engine.startTestTone(880)
        left.withUnsafeMutableBufferPointer { leftBuffer in
            right.withUnsafeMutableBufferPointer { rightBuffer in
                guard let leftAddress = leftBuffer.baseAddress,
                      let rightAddress = rightBuffer.baseAddress else { return XCTFail("Missing test buffers") }
                engine.generateProcessTapTestToneIfNeeded(
                    left: leftAddress,
                    right: rightAddress,
                    frameCount: leftBuffer.count
                )
            }
        }
        XCTAssertEqual(left[0], 0, accuracy: 0.000_001)
        XCTAssertGreaterThan(abs(left[1]), abs(sampleAt440Hz))

        engine.stopTestTone()
        left = [Float](repeating: 0.25, count: 64)
        right = [Float](repeating: -0.25, count: 64)
        left.withUnsafeMutableBufferPointer { leftBuffer in
            right.withUnsafeMutableBufferPointer { rightBuffer in
                guard let leftAddress = leftBuffer.baseAddress,
                      let rightAddress = rightBuffer.baseAddress else { return XCTFail("Missing test buffers") }
                engine.generateProcessTapTestToneIfNeeded(
                    left: leftAddress,
                    right: rightAddress,
                    frameCount: leftBuffer.count
                )
            }
        }
        XCTAssertEqual(left, [Float](repeating: 0.25, count: 64))
        XCTAssertEqual(right, [Float](repeating: -0.25, count: 64))
    }

    func testBlackHoleGainStagingUsesOneVolumeStage() throws {
        let physical = AudioDeviceID(1)
        let virtual = AudioDeviceID(2)
        var states: [AudioDeviceID: OutputVolumeState] = try [
            physical: XCTUnwrap(OutputVolumeState(scalar: 0.181, isMuted: false)),
            virtual: XCTUnwrap(OutputVolumeState(scalar: 1, isMuted: false))
        ]
        let read: (AudioDeviceID) -> OutputVolumeState? = { states[$0] }
        let write: (OutputVolumeState, AudioDeviceID) -> Bool = { state, deviceID in
            states[deviceID] = state
            return true
        }

        XCTAssertTrue(BlackHoleGainStaging.prepareVirtualOutput(
            physicalDevice: physical,
            virtualDevice: virtual,
            read: read,
            write: write
        ))
        XCTAssertEqual(try XCTUnwrap(states[virtual]).scalar, 0.181, accuracy: 0.0001)
        XCTAssertTrue(BlackHoleGainStaging.setPhysicalOutputToUnity(
            physical,
            read: read,
            write: write
        ))
        let physicalState = try XCTUnwrap(states[physical])
        XCTAssertEqual(physicalState.scalar, 1)
        XCTAssertEqual(physicalState.isMuted, false)
    }

    func testBlackHoleRateRestartPreservesVolumeAndMuteOverPhysicalUnity() throws {
        let physical = AudioDeviceID(1)
        let virtual = AudioDeviceID(2)
        let preserved = try XCTUnwrap(OutputVolumeState(scalar: 0.37, isMuted: true))
        var states: [AudioDeviceID: OutputVolumeState] = try [
            physical: XCTUnwrap(OutputVolumeState(scalar: 1, isMuted: false)),
            virtual: XCTUnwrap(OutputVolumeState(scalar: 0.226, isMuted: false))
        ]
        var writes: [AudioDeviceID] = []

        XCTAssertTrue(BlackHoleGainStaging.prepareVirtualOutput(
            physicalDevice: physical,
            virtualDevice: virtual,
            preserving: preserved,
            read: { states[$0] },
            write: { state, deviceID in
                writes.append(deviceID)
                states[deviceID] = state
                return true
            }
        ))
        XCTAssertEqual(states[virtual], preserved)
        XCTAssertEqual(states[physical]?.scalar, 1)
        XCTAssertEqual(writes, [virtual])
    }

    func testBlackHoleRateRestartPreservesVolumeWithoutPhysicalVolumeControl() throws {
        let preserved = try XCTUnwrap(OutputVolumeState(scalar: 0.48, isMuted: false))
        var observed = try XCTUnwrap(OutputVolumeState(scalar: 1, isMuted: false))

        XCTAssertTrue(BlackHoleGainStaging.prepareVirtualOutput(
            physicalDevice: 1,
            virtualDevice: 2,
            preserving: preserved,
            read: { $0 == 2 ? observed : nil },
            write: { state, deviceID in
                XCTAssertEqual(deviceID, 2)
                observed = state
                return true
            }
        ))
        XCTAssertEqual(observed, preserved)
    }

    func testBlackHoleRateRestartRejectsFailedVolumeWrite() throws {
        let preserved = try XCTUnwrap(OutputVolumeState(scalar: 0.48, isMuted: false))
        let observed = try XCTUnwrap(OutputVolumeState(scalar: 1, isMuted: false))

        XCTAssertFalse(BlackHoleGainStaging.prepareVirtualOutput(
            physicalDevice: 1,
            virtualDevice: 2,
            preserving: preserved,
            read: { $0 == 2 ? observed : nil },
            write: { _, _ in false }
        ))
    }

    func testBlackHoleRateRestartRejectsMissingVolumeReadback() throws {
        let preserved = try XCTUnwrap(OutputVolumeState(scalar: 0.48, isMuted: false))

        XCTAssertFalse(BlackHoleGainStaging.prepareVirtualOutput(
            physicalDevice: 1,
            virtualDevice: 2,
            preserving: preserved,
            read: { _ in nil },
            write: { _, _ in true }
        ))
    }

    func testBlackHoleRateRestartRejectsUnchangedVolumeOrMute() throws {
        let preserved = try XCTUnwrap(OutputVolumeState(scalar: 0.48, isMuted: true))
        let wrongStates = try [
            XCTUnwrap(OutputVolumeState(scalar: 1, isMuted: true)),
            XCTUnwrap(OutputVolumeState(scalar: 0.48, isMuted: false))
        ]

        for observed in wrongStates {
            XCTAssertFalse(BlackHoleGainStaging.prepareVirtualOutput(
                physicalDevice: 1,
                virtualDevice: 2,
                preserving: preserved,
                read: { $0 == 2 ? observed : nil },
                write: { _, _ in true }
            ))
        }
    }

    func testBlackHoleGainStagingRejectsUnverifiedPhysicalUnity() throws {
        let physical = AudioDeviceID(1)
        let state = try XCTUnwrap(OutputVolumeState(scalar: 0.181, isMuted: false))

        let result = BlackHoleGainStaging.setPhysicalOutputToUnity(
            physical,
            read: { _ in state },
            write: { _, _ in true }
        )

        XCTAssertFalse(result)
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

    func testBlackHoleInputResetEchoDoesNotBecomeUserVolume() throws {
        let reset = try XCTUnwrap(OutputVolumeState(scalar: 0.226, isMuted: false))
        let expected = try XCTUnwrap(OutputVolumeState(scalar: 0.5, isMuted: false))
        var echo = BlackHoleInputVolumeEchoGuard()
        echo.record(reset, at: 0)

        for scopes: Set<AudioObjectPropertyScope> in [
            [kAudioObjectPropertyScopeOutput],
            [kAudioObjectPropertyScopeInput, kAudioObjectPropertyScopeOutput]
        ] {
            guard case .restoreExpected = BlackHoleVolumeChangePolicy.action(
                for: scopes, observed: reset, rejectedInput: echo.state(at: 35_000_000)
            ) else { return XCTFail("The rejected input gain must not become the expected output gain") }
        }
        guard case .acceptObserved = BlackHoleVolumeChangePolicy.action(
            for: [kAudioObjectPropertyScopeOutput], observed: expected, rejectedInput: echo.state(at: 35_000_000)
        ) else { return XCTFail("The recovery acknowledgement must retain the restored value") }
    }

    func testBlackHoleInputEchoGuardAcceptsDifferentUserVolumeAndMute() throws {
        let reset = try XCTUnwrap(OutputVolumeState(scalar: 0.226, isMuted: false))
        var echo = BlackHoleInputVolumeEchoGuard()
        echo.record(reset, at: 0)
        let changes = try [
            XCTUnwrap(OutputVolumeState(scalar: 0.375, isMuted: false)),
            XCTUnwrap(OutputVolumeState(scalar: 0.226, isMuted: true))
        ]

        for observed in changes {
            guard case .acceptObserved = BlackHoleVolumeChangePolicy.action(
                for: [kAudioObjectPropertyScopeInput, kAudioObjectPropertyScopeOutput],
                observed: observed, rejectedInput: echo.state(at: 35_000_000)
            ) else { return XCTFail("A different user volume or mute must be accepted") }
        }
    }

    func testBlackHoleInputEchoGuardExpiresAndClearsAcrossRoutes() throws {
        let reset = try XCTUnwrap(OutputVolumeState(scalar: 0.226, isMuted: false))
        var echo = BlackHoleInputVolumeEchoGuard()
        echo.record(reset, at: 100)
        XCTAssertEqual(echo.state(at: 99_999_999), reset)
        XCTAssertNil(echo.state(at: 100_000_100))
        guard case .acceptObserved = BlackHoleVolumeChangePolicy.action(
            for: [kAudioObjectPropertyScopeOutput], observed: reset, rejectedInput: echo.state(at: 100_000_100)
        ) else { return XCTFail("The guard must not fight volume keys after expiry") }
        echo.reset()
        XCTAssertNil(echo.state(at: 101))
    }

    func testBlackHoleCoalescedResetDuringRateRecoveryRetainsExpectedVolume() throws {
        let reset = try XCTUnwrap(OutputVolumeState(scalar: 0.226, isMuted: false))
        var echo = BlackHoleInputVolumeEchoGuard()
        echo.beginRecovery(at: 0)
        XCTAssertNil(echo.state(at: 35_000_000))
        guard case .restoreExpected = BlackHoleVolumeChangePolicy.action(
            for: [kAudioObjectPropertyScopeInput, kAudioObjectPropertyScopeOutput], observed: reset,
            rejectedInput: echo.state(at: 35_000_000), preservingMixedScopes: echo.isRecovering(at: 35_000_000)
        ) else { return XCTFail("The first coalesced rate-reset notification must retain the expected volume") }
    }

    func testBlackHoleRateRecoveryStillAcceptsOutputOnlyAdjustment() throws {
        let userVolume = try XCTUnwrap(OutputVolumeState(scalar: 0.375, isMuted: false))
        var echo = BlackHoleInputVolumeEchoGuard()
        echo.beginRecovery(at: 0)
        guard case .acceptObserved = BlackHoleVolumeChangePolicy.action(
            for: [kAudioObjectPropertyScopeOutput], observed: userVolume,
            preservingMixedScopes: echo.isRecovering(at: 35_000_000)
        ) else { return XCTFail("Output-only user volume changes must remain available during recovery") }
    }

    func testBlackHoleMixedVolumeKeysResumeAfterRateRecoveryWindow() {
        var echo = BlackHoleInputVolumeEchoGuard()
        echo.beginRecovery(at: 0)
        XCTAssertFalse(echo.isRecovering(at: 100_000_000))
        guard case .acceptObserved = BlackHoleVolumeChangePolicy.action(
            for: [kAudioObjectPropertyScopeInput, kAudioObjectPropertyScopeOutput],
            preservingMixedScopes: echo.isRecovering(at: 100_000_000)
        ) else { return XCTFail("The settling guard must not permanently suppress mixed-scope volume keys") }
        echo.reset()
        XCTAssertFalse(echo.isRecovering(at: 1))
    }

    func testBlackHoleUserAdjustmentKeepsRateRecoveryDeadline() throws {
        let reset = try XCTUnwrap(OutputVolumeState(scalar: 0.226, isMuted: false))
        var echo = BlackHoleInputVolumeEchoGuard()
        echo.beginRecovery(at: 0)
        echo.record(reset, at: 1)
        echo.acceptOutputChange()
        XCTAssertNil(echo.state(at: 15_000_000))
        XCTAssertTrue(echo.isRecovering(at: 15_000_000))
        guard case .restoreExpected = BlackHoleVolumeChangePolicy.action(
            for: [kAudioObjectPropertyScopeInput, kAudioObjectPropertyScopeOutput], observed: reset,
            rejectedInput: echo.state(at: 15_000_000), preservingMixedScopes: echo.isRecovering(at: 15_000_000)
        )
        else {
            return XCTFail("A later reset must restore the latest user choice within the original recovery deadline")
        }
        XCTAssertFalse(echo.isRecovering(at: 100_000_000))
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

    func testPeakMeterLevelSnapshotRoundTrip() {
        let packed = PeakMeter.packLevels(input: 0.25, output: 0.75)
        let unpacked = PeakMeter.unpackLevels(packed)

        XCTAssertEqual(unpacked.input, 0.25)
        XCTAssertEqual(unpacked.output, 0.75)
    }

    func testLimiterIndicatorUsesActualGainReductionThresholds() {
        XCTAssertEqual(LimiterIndicatorState.state(for: 0), .normal)
        XCTAssertEqual(LimiterIndicatorState.state(for: 0.1), .mild)
        XCTAssertEqual(LimiterIndicatorState.state(for: 2.9), .mild)
        XCTAssertEqual(LimiterIndicatorState.state(for: 3), .heavy)
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
        XCTAssertTrue(store.reportText().contains("discarded older events: 1"))
    }

    func testDiagnosticHistoryRemainsBoundedWithLargeUnicodeEntries() {
        let store = DiagnosticEventStore(capacity: 1000)
        let text = String(repeating: "🎵\n", count: 1000)
        let details = Dictionary(uniqueKeysWithValues: (0..<40).map { ("field\($0)", text) })
        for _ in 0..<110 {
            store.record(text, details: details)
        }

        let events = store.snapshot()
        XCTAssertEqual(events.count, 100)
        for event in events {
            XCTAssertLessThanOrEqual(event.name.utf8.count, 128)
            XCTAssertFalse(event.name.contains("\n"))
            XCTAssertLessThanOrEqual(event.details.count, 16)
            for (key, value) in event.details {
                XCTAssertLessThanOrEqual(key.utf8.count, 128)
                XCTAssertLessThanOrEqual(value.utf8.count, 512)
                XCTAssertFalse(value.contains("\n"))
                XCTAssertFalse(value.contains("�"))
            }
        }
        XCTAssertTrue(store.reportText().contains("discarded older events: 10"))
    }

    func testDiagnosticSessionDistinguishesInterruptedAndCleanExit() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("diagnostics.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let interrupted = DiagnosticEventStore(persistenceURL: url)
        interrupted.startSession()
        let recovered = DiagnosticEventStore(capacity: 2, persistenceURL: url)
        recovered.startSession()
        XCTAssertTrue(recovered.reportText().contains("Previous session clean exit: false"))
        recovered.record("routing.enable.request")
        recovered.record("engine.setup.ready")
        recovered.record("routing.enable.succeeded")
        recovered.finishSession()

        let clean = DiagnosticEventStore(persistenceURL: url)
        clean.startSession()
        XCTAssertTrue(clean.reportText().contains("Previous session clean exit: true"))
        XCTAssertTrue(clean.reportText().contains("routing.enable.succeeded"))
        XCTAssertTrue(clean.reportText().contains("Previous session discarded older events: 1"))
        clean.finishSession()
    }

    func testInterruptedSessionSurvivesRepeatedCleanRelaunches() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("diagnostics.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let interrupted = DiagnosticEventStore(persistenceURL: url)
        interrupted.startSession()
        for _ in 0..<10 {
            let clean = DiagnosticEventStore(persistenceURL: url)
            clean.startSession()
            clean.finishSession()
        }
        let report = DiagnosticEventStore(persistenceURL: url)
        report.startSession()
        XCTAssertTrue(report.reportText().contains("Previous session clean exit: false"))
        XCTAssertEqual(report.reportText().components(separatedBy: "Previous session started:").count - 1, 8)
        report.finishSession()
    }

    func testNewestCleanSessionSurvivesFullInterruptedHistory() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("diagnostics.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        for _ in 0..<8 {
            DiagnosticEventStore(persistenceURL: url).startSession()
        }
        let clean = DiagnosticEventStore(persistenceURL: url)
        clean.startSession()
        clean.finishSession()

        let report = DiagnosticEventStore(persistenceURL: url)
        report.startSession()
        XCTAssertTrue(report.reportText().contains("Previous session clean exit: true"))
        XCTAssertEqual(report.reportText().components(separatedBy: "Previous session started:").count - 1, 8)
        report.finishSession()
    }

    func testDiagnosticExecutableIdentityIsAvailable() {
        XCTAssertNotNil(UUID(uuidString: DiagnosticBuild.executableUUID))
    }

    func testRingDiagnosticsDescribeReadAndResetWithoutChangingAudio() {
        let ring = SPSCRingBuffer()
        ring.allocate(capacityFrames: 1024)
        let input = UnsafeMutablePointer<Float>.allocate(capacity: 1025)
        input.initialize(repeating: 0.25, count: 1025)
        let left = UnsafeMutablePointer<Float>.allocate(capacity: 1025)
        let right = UnsafeMutablePointer<Float>.allocate(capacity: 1025)
        defer {
            input.deallocate()
            left.deallocate()
            right.deallocate()
        }
        XCTAssertEqual(ring.write(inL: input, inR: input, frameCount: 1025), 1024)
        ring.readNonInterleaved(outL: left, outR: right, framesRequested: 1025)
        let health = ring.snapshotAndResetDiag()
        XCTAssertEqual(health.fill, 1024)
        XCTAssertEqual(health.requested, 1025)
        XCTAssertEqual(health.capacity, 1024)
        XCTAssertEqual(health.underruns, 1)
        XCTAssertEqual(health.overruns, 1)
        XCTAssertGreaterThanOrEqual(health.intervalSeconds, 0)
        XCTAssertEqual(left[0], 0.25)
        XCTAssertEqual(right[1023], 0.25)
        XCTAssertEqual(left[1024], 0)
        let next = ring.snapshotAndResetDiag()
        XCTAssertEqual(next.underruns, 0)
        XCTAssertEqual(next.overruns, 0)
        let lifetime = ring.lifetimeDiagnostics()
        XCTAssertEqual(lifetime.underruns, 1)
        XCTAssertEqual(lifetime.overruns, 1)
        XCTAssertGreaterThan(lifetime.lastUnderrun, 0)
        XCTAssertGreaterThan(lifetime.lastOverrun, 0)
        ring.reset()
        XCTAssertEqual(ring.snapshotAndResetDiag().requested, 0)
        XCTAssertEqual(ring.lifetimeDiagnostics().underruns, 1)
    }

    func testConcurrentRingDiagnosticSamplingPreservesUnderrunCount() {
        let ring = SPSCRingBuffer()
        ring.allocate(capacityFrames: 1024)
        let finished = expectation(description: "Ring reads completed")
        DispatchQueue.global(qos: .userInitiated).async {
            let left = UnsafeMutablePointer<Float>.allocate(capacity: 1)
            let right = UnsafeMutablePointer<Float>.allocate(capacity: 1)
            defer {
                left.deallocate()
                right.deallocate()
            }
            for _ in 0..<100_000 {
                ring.readNonInterleaved(outL: left, outR: right, framesRequested: 1)
            }
            finished.fulfill()
        }
        var total: Int64 = 0
        for _ in 0..<1000 {
            total += Int64(ring.snapshotAndResetDiag().underruns)
        }
        wait(for: [finished], timeout: 10)
        total += Int64(ring.snapshotAndResetDiag().underruns)
        XCTAssertEqual(total, 100_000)
    }

    func testNativeDiagnosticReportDoesNotClaimBlackHoleHealth() {
        let report = self.coreAudioEngine.diagnosticSummary(backend: .native)
        XCTAssertTrue(report.contains("not applicable"))
        XCTAssertFalse(report.contains("Underruns in interval"))
    }

    func testProcessTapInputSelectsUniqueStereoTapStream() {
        let tap = processTapFormat(sampleRate: 48000, channels: 2)
        let mono = processTapFormat(sampleRate: 48000, channels: 1)

        let selection = ProcessTapInputSelection.select(
            tapFormat: tap,
            aggregateFormats: [mono, tap],
            aggregateChannelCounts: [1, 2],
            aggregateStartingChannels: [1, 2],
            physicalInputChannelCount: 1
        )

        XCTAssertEqual(selection, ProcessTapInputSelection(bufferIndex: 1))
    }

    func testProcessTapInputUsesChannelBoundaryForAmbiguousDeviceInput() {
        let tap = processTapFormat(sampleRate: 48000, channels: 2)

        let selection = ProcessTapInputSelection.select(
            tapFormat: tap,
            aggregateFormats: [tap, tap],
            aggregateChannelCounts: [2, 2],
            aggregateStartingChannels: [1, 3],
            physicalInputChannelCount: 2
        )

        XCTAssertEqual(selection, ProcessTapInputSelection(bufferIndex: 1))
    }

    func testProcessTapInputRejectsNonFloatTapFormat() {
        var tap = processTapFormat(sampleRate: 48000, channels: 2)
        tap.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked

        XCTAssertNil(ProcessTapInputSelection.select(
            tapFormat: tap,
            aggregateFormats: [tap],
            aggregateChannelCounts: [2],
            aggregateStartingChannels: [1],
            physicalInputChannelCount: 0
        ))
    }

    func testAppDeclaresSystemAudioCaptureUsageDescription() {
        let description = Bundle.main.object(forInfoDictionaryKey: "NSAudioCaptureUsageDescription") as? String

        XCTAssertFalse(description?.isEmpty ?? true)
    }

    private func processTapFormat(sampleRate: Double, channels: UInt32) -> AudioStreamBasicDescription {
        AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: channels * 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: channels * 4,
            mChannelsPerFrame: channels,
            mBitsPerChannel: 32,
            mReserved: 0
        )
    }
}

@MainActor
final class CalibrationProfileTests: XCTestCase {
    func testRoomABAttenuatesBypassAndRestoresNotchesWithoutChangingAutoEQ() throws {
        for mode in [EQBandMode.tenBand, .thirtyOneBand] {
            try withProfile(mode: mode) { engine, _, core, defaults in
                core.setEnabled(true)
                let baseFilter = core.vdspFilter
                let gains = engine.bands.map(\.gain)
                let snapshot = defaults.data(forKey: "lastPlayback.snapshot")
                let id = try XCTUnwrap(core.beginRoomABComparison([(125, -8, 4)]))
                let offset = try XCTUnwrap(core.roomABGainMatchOffset(for: id))
                XCTAssertLessThan(offset, 0)
                XCTAssertGreaterThan(offset, -8)
                XCTAssertEqual(
                    try measuredGain(core, frequency: 125, includingRoom: true) - measuredGain(core, frequency: 125),
                    -8, accuracy: 0.2
                )
                XCTAssertTrue(core.setRoomABComparisonPhase(id, filtered: false))
                for frequency in [125.0, 1000.0, 8000.0] {
                    XCTAssertEqual(
                        try measuredGain(core, frequency: frequency, includingRoom: true) - measuredGain(
                            core,
                            frequency: frequency
                        ),
                        Double(offset), accuracy: 0.05
                    )
                }
                core.endRoomABComparison(id)
                XCTAssertNil(core.roomABGainMatchOffset(for: id))
                XCTAssertEqual(
                    try measuredGain(core, frequency: 125, includingRoom: true) - measuredGain(core, frequency: 125),
                    -8, accuracy: 0.2
                )
                XCTAssertTrue(core.vdspFilter === baseFilter)
                XCTAssertEqual(engine.bands.map(\.gain), gains)
                XCTAssertEqual(defaults.data(forKey: "lastPlayback.snapshot"), snapshot)
            }
        }
    }

    func testRoomABBroadbandEstimateMatchesRenderedLogSpacedTones() throws {
        for rate in [48000.0, 96000.0] {
            let core = CoreAudioEngine()
            core.prepareProcessTap(sampleRate: rate, outputDeviceID: 0, bufferFrames: 512)
            let id = try XCTUnwrap(core.beginRoomABComparison([(500, -12, 0.7), (3500, -8, 1)]))
            let filtered = try renderedRoomEnergy(core, sampleRate: rate)
            XCTAssertTrue(core.setRoomABComparisonPhase(id, filtered: false))
            let bypassed = try renderedRoomEnergy(core, sampleRate: rate)
            XCTAssertEqual(10 * log10(filtered / bypassed), 0, accuracy: 0.2, "sample rate \(rate)")
        }
    }

    func testRoomABRejectsMalformedStartsWithoutReplacingCurrentSession() throws {
        let core = CoreAudioEngine()
        let id = try XCTUnwrap(core.beginRoomABComparison([(125, -6, 4)]))
        let original = core.roomFilter
        let invalid: [[(Float, Float, Float)]] = [
            [], [(0, -6, 4)], [(.nan, -6, 4)], [(.infinity, -6, 4)],
            [(125, .nan, 4)], [(125, .infinity, 4)], [(125, 1, 4)], [(125, -61, 4)],
            [(125, -6, 0)], [(125, -6, .nan)], [(125, -6, .infinity)],
            [(125, -6, 4), (250, -4, -1)]
        ]
        for filters in invalid {
            XCTAssertNil(core.beginRoomABComparison(filters))
            XCTAssertTrue(core.roomFilter === original)
            XCTAssertNotNil(core.roomABGainMatchOffset(for: id))
        }
        for rate in [Double.nan, .infinity, 0, -1, Double.greatestFiniteMagnitude] {
            XCTAssertNil(CoreAudioEngine.roomABBypassGain(notchFilters: [(125, -6, 4)], sampleRate: rate))
        }
    }

    func testRoomABStaleSessionsCannotChangeReplacementOrClearedProfile() throws {
        let core = CoreAudioEngine()
        let first = try XCTUnwrap(core.beginRoomABComparison([(125, -6, 4)]))
        XCTAssertTrue(core.setRoomABComparisonPhase(first, filtered: false))
        let second = try XCTUnwrap(core.beginRoomABComparison([(250, -10, 3)]))
        let replacement = core.roomFilter
        XCTAssertFalse(core.setRoomABComparisonPhase(first, filtered: false))
        core.endRoomABComparison(first)
        XCTAssertTrue(core.roomFilter === replacement)
        XCTAssertNotNil(core.roomABGainMatchOffset(for: second))
        XCTAssertTrue(core.setRoomABComparisonPhase(second, filtered: false))
        core.applyRoomNotchFilters([(500, -4, 2)])
        let profile = core.roomFilter
        XCTAssertFalse(core.setRoomABComparisonPhase(second, filtered: true))
        core.endRoomABComparison(second)
        XCTAssertTrue(core.roomFilter === profile)
        let third = try XCTUnwrap(core.beginRoomABComparison([(125, -6, 4)]))
        core.clearRoomNotchFilters()
        core.endRoomABComparison(third)
        XCTAssertFalse(core.setRoomABComparisonPhase(third, filtered: false))
        XCTAssertNil(core.roomFilter)
    }

    func testRoomABRateRebuildAndStopWithoutRestoreRemoveTemporaryGain() throws {
        let core = CoreAudioEngine()
        let id = try XCTUnwrap(core.beginRoomABComparison([(16000, -8, 2)]))
        XCTAssertTrue(core.setRoomABComparisonPhase(id, filtered: false))
        core.rebuildRoomFilter(sampleRate: 24000)
        XCTAssertEqual(core.roomFilter?.sampleRate, 24000)
        XCTAssertEqual(try XCTUnwrap(core.roomABGainMatchOffset(for: id)), 0, accuracy: 0.0001)
        core.rebuildRoomFilter(sampleRate: 96000)
        XCTAssertEqual(core.roomFilter?.sampleRate, 96000)
        XCTAssertLessThan(try XCTUnwrap(core.roomABGainMatchOffset(for: id)), 0)
        core.endRoomABComparison(id, restoreFilters: false)
        XCTAssertNil(core.roomFilter)
        XCTAssertFalse(core.setRoomABComparisonPhase(id, filtered: true))
        core.rebuildRoomFilter(sampleRate: 48000)
        XCTAssertNil(core.roomFilter)
    }

    func testRoomABBypassProcessesZeroOneAndUnequalBlockSizes() throws {
        let core = CoreAudioEngine()
        let id = try XCTUnwrap(core.beginRoomABComparison([(125, -6, 4)]))
        XCTAssertTrue(core.setRoomABComparisonPhase(id, filtered: false))
        let offset = try XCTUnwrap(core.roomABGainMatchOffset(for: id))
        let scalar = pow(10, offset / 20)
        let room = try XCTUnwrap(core.roomFilter)
        for count in [0, 1, 127, 513] {
            var left = [Float](repeating: 0.001, count: count + 1)
            var right = [Float](repeating: -0.002, count: count + 1)
            try left.withUnsafeMutableBufferPointer { l in
                try right.withUnsafeMutableBufferPointer { r in
                    _ = try room.processStereo(XCTUnwrap(l.baseAddress), XCTUnwrap(r.baseAddress), frameCount: count)
                }
            }
            for value in left.prefix(count) {
                XCTAssertEqual(value, 0.001 * scalar, accuracy: 0.0000001)
            }
            for value in right.prefix(count) {
                XCTAssertEqual(value, -0.002 * scalar, accuracy: 0.0000001)
            }
            XCTAssertEqual(left[count], 0.001)
            XCTAssertEqual(right[count], -0.002)
        }
    }

    private func renderedRoomEnergy(_ core: CoreAudioEngine, sampleRate: Double) throws -> Double {
        let period = 65536
        let count = period * 2
        var source = [Float](repeating: 0, count: period)
        var bins = Set<Int>()
        for tone in 0..<128 {
            let target = 20 * exp(log(1000) * Double(tone) / 127)
            let bin = Int((target * Double(period) / sampleRate).rounded())
            guard bins.insert(bin).inserted else { continue }
            for index in source.indices {
                source[index] += Float(0.00004 * sin(2 * .pi * Double(bin * index) / Double(period) + Double(tone)))
            }
        }
        var left = source + source, right = source + source
        let room = try XCTUnwrap(core.roomFilter)
        try left.withUnsafeMutableBufferPointer { l in
            try right.withUnsafeMutableBufferPointer { r in
                _ = try room.processStereo(XCTUnwrap(l.baseAddress), XCTUnwrap(r.baseAddress), frameCount: count)
            }
        }
        return left.dropFirst(period).reduce(0.0) { $0 + Double($1) * Double($1) }
    }

    func testRoomProfileRoundTripLegacyDecodingAndDraftPreserveNotches() throws {
        let profile = CalibrationProfile(
            name: "Room", type: .roomCorrection, notes: "Saved room",
            notchFilters: [.init(frequency: 63.5, gain: -6, q: 3.5), .init(frequency: 201.25, gain: -4, q: 7)]
        )
        let data = try JSONEncoder().encode(profile)
        XCTAssertEqual(try JSONDecoder().decode(CalibrationProfile.self, from: data), profile)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "notchFilters")
        let old = try JSONDecoder().decode(
            CalibrationProfile.self, from: JSONSerialization.data(withJSONObject: legacy)
        )
        XCTAssertTrue(old.notchFilters.isEmpty)
        XCTAssertEqual(old.id, profile.id)
        XCTAssertEqual(old.createdAt, profile.createdAt)
        XCTAssertEqual(old.bands, profile.bands)
        XCTAssertEqual(old.notes, profile.notes)
        XCTAssertTrue(old.isValid)
        for invalid: Any in [
            NSNull(), "not filters", [["frequency": 63.5, "gain": -6]],
            [["frequency": 0, "gain": -6, "q": 4]],
            [["frequency": -1, "gain": -6, "q": 4]],
            [["frequency": 63.5, "gain": -6, "q": -1]],
            [["frequency": 63.5, "gain": -6, "q": 4], ["frequency": 125, "gain": -6, "q": 0]]
        ] {
            legacy["notchFilters"] = invalid
            XCTAssertThrowsError(try JSONDecoder().decode(
                CalibrationProfile.self, from: JSONSerialization.data(withJSONObject: legacy)
            ))
        }
        var draft = CalibrationProfileDraft(profile)
        draft.name = "Edited room"
        draft.bandInputs[0] = "2"
        let edited = try XCTUnwrap(draft.updatedProfile)
        XCTAssertEqual(edited.notchFilters, profile.notchFilters)
        XCTAssertEqual(edited.id, profile.id)
        XCTAssertEqual(edited.createdAt, profile.createdAt)
    }

    func testSavedRoomProfileLoadsAndAppliesToPlaybackWithoutChangingBaseEQ() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            do { try FileManager.default.removeItem(at: directory) } catch { XCTFail("Cleanup failed: \(error)") }
        }
        let url = directory.appendingPathComponent("profiles.json")
        let suite = "RoomProfileTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let core = CoreAudioEngine()
        let engine = AudioEngine(
            defaults: defaults, coreAudioEngine: core,
            enableRouting: { _ in core.clearEQ(); return true }, disableRouting: { _ in }
        )
        engine.applyEQValues([Float](repeating: 2, count: 10))
        let profile = CalibrationProfile(
            name: "Room", type: .roomCorrection, notchFilters: [.init(frequency: 125, gain: -8, q: 4)]
        )
        let writer = CalibrationEngine(eqEngine: engine, profilesURL: url, loadStoredProfiles: false)
        writer.profiles.append(profile)
        XCTAssertTrue(writer.updateProfile(profile))
        writer.flushProfileWrites()
        XCTAssertNil(core.roomFilter)
        XCTAssertEqual(try JSONDecoder().decode([CalibrationProfile].self, from: Data(contentsOf: url)), [profile])
        let restored = CalibrationEngine(eqEngine: engine, profilesURL: url)
        defer { restored.flushProfileWrites() }
        let loaded = expectation(description: "Room profile loaded")
        let subscription = restored.$profiles.dropFirst().sink { values in
            if values.count == 1 { loaded.fulfill() }
        }
        defer { subscription.cancel() }
        await fulfillment(of: [loaded], timeout: 3)
        XCTAssertEqual(restored.profiles, [profile])
        XCTAssertNil(restored.activeProfile)
        try restored.activateProfile(XCTUnwrap(restored.profiles.first))
        XCTAssertEqual(
            try measuredGain(core, frequency: 125, includingRoom: true) - measuredGain(core, frequency: 125),
            -8, accuracy: 0.2
        )
        XCTAssertTrue(engine.setEnabled(false))
        XCTAssertTrue(engine.setEnabled(true))
        core.rebuildActiveEQFilter(sampleRate: 96000)
        core.rebuildRoomFilter(sampleRate: 96000)
        XCTAssertEqual(core.roomFilter?.sampleRate, 96000)
        XCTAssertEqual(
            try measuredGain(core, frequency: 125, includingRoom: true) - measuredGain(core, frequency: 125),
            -8, accuracy: 0.2
        )
        XCTAssertEqual(restored.activeProfile?.notchFilters, profile.notchFilters)
        XCTAssertEqual(engine.bands.map(\.gain), [Float](repeating: 2, count: 10))
        XCTAssertEqual(PresetPersistence.loadPlaybackState(in: defaults)?.gains, [Float](repeating: 2, count: 10))
    }

    func testRoomProfileSwitchesReplaceFiltersAndEmptyDeactivateDeleteClearThem() throws {
        for mode in [EQBandMode.tenBand, .thirtyOneBand] {
            try withProfile(mode: mode) { _, calibration, core, _ in
                let first = CalibrationProfile(
                    name: "First", type: .roomCorrection, notchFilters: [.init(frequency: 125, gain: -6, q: 4)]
                )
                var second = CalibrationProfile(
                    name: "Second", type: .roomCorrection, notchFilters: [.init(frequency: 250, gain: -10, q: 7)]
                )
                calibration.profiles = [first, second]
                for _ in 0..<3 {
                    calibration.activateProfile(first)
                }
                XCTAssertEqual(
                    try measuredGain(core, frequency: 125, includingRoom: true) - measuredGain(core, frequency: 125),
                    -6, accuracy: 0.2
                )
                let firstFilter = core.roomFilter
                second.notchFilters[0].q = 5
                XCTAssertTrue(calibration.updateProfile(second))
                XCTAssertTrue(core.roomFilter === firstFilter)
                calibration.activateProfile(second)
                XCTAssertEqual(
                    try measuredGain(core, frequency: 250, includingRoom: true) - measuredGain(core, frequency: 250),
                    -10, accuracy: 0.2
                )
                let reference = CoreAudioEngine()
                if mode == .tenBand {
                    reference.applyFixedBandEQ([Float](repeating: 2, count: 10))
                } else {
                    reference.applyGraphicEQ31([Float](repeating: 2, count: 31))
                }
                reference.applyRoomNotchFilters([(frequency: 250, gain: -10, q: 5)])
                reference.setEnabled(true)
                XCTAssertEqual(
                    try measuredGain(core, frequency: 125, includingRoom: true),
                    try measuredGain(reference, frequency: 125, includingRoom: true), accuracy: 0.05
                )
                for type in [CalibrationType.equalLoudness, .roomCorrection] {
                    calibration.activateProfile(CalibrationProfile(name: "No notches", type: type))
                    XCTAssertNil(core.roomFilter)
                    calibration.activateProfile(first)
                    XCTAssertNotNil(core.roomFilter)
                }
                calibration.deactivateProfile()
                XCTAssertNil(core.roomFilter)
                XCTAssertNil(calibration.activeProfile)
                calibration.activateProfile(first)
                calibration.deleteProfile(first)
                XCTAssertNil(core.roomFilter)
                XCTAssertNil(calibration.activeProfile)
                XCTAssertEqual(core.getBandGain(index: 0), 2)
            }
        }
    }

    func testInvalidRoomProfileDoesNotPartiallyChangeActiveDSPOrPersistence() throws {
        try withProfile { _, calibration, core, defaults in
            let original = CalibrationProfile(
                name: "Original", type: .roomCorrection, notchFilters: [.init(frequency: 125, gain: -6, q: 4)]
            )
            calibration.profiles.append(original)
            XCTAssertTrue(calibration.updateProfile(original))
            calibration.activateProfile(original)
            calibration.flushProfileWrites()
            core.setEnabled(false)
            let room = core.roomFilter
            let eq = core.vdspFilter
            let playback = defaults.data(forKey: "lastPlayback.snapshot")
            let invalid: [CalibrationProfile.NotchFilter] = [
                .init(frequency: 0, gain: -6, q: 4), .init(frequency: -1, gain: -6, q: 4),
                .init(frequency: .nan, gain: -6, q: 4), .init(frequency: .infinity, gain: -6, q: 4),
                .init(frequency: Float(Double.greatestFiniteMagnitude), gain: -6, q: 4),
                .init(frequency: 125, gain: .nan, q: 4), .init(frequency: 125, gain: .infinity, q: 4),
                .init(frequency: 125, gain: -6, q: 0), .init(frequency: 125, gain: -6, q: -1),
                .init(frequency: 125, gain: -6, q: .nan), .init(frequency: 125, gain: -6, q: .infinity)
            ]
            for notch in invalid {
                var changed = original
                changed.bands[0] = 7
                changed.notchFilters = [original.notchFilters[0], notch]
                XCTAssertFalse(changed.isValid)
                XCTAssertFalse(calibration.updateProfile(changed))
                calibration.activateProfile(changed)
                XCTAssertEqual(calibration.activeProfile, original)
                XCTAssertEqual(calibration.profiles, [original])
                XCTAssertTrue(core.roomFilter === room)
                XCTAssertTrue(core.vdspFilter === eq)
                XCTAssertFalse(core.isEnabled)
                XCTAssertEqual(defaults.data(forKey: "lastPlayback.snapshot"), playback)
            }
        }
    }

    func testRoomNotchesSurviveTemporaryNyquistBypass() throws {
        try withProfile { _, calibration, core, _ in
            let profile = CalibrationProfile(
                name: "High notch", type: .roomCorrection, notchFilters: [.init(frequency: 16000, gain: -6, q: 4)]
            )
            calibration.activateProfile(profile)
            core.rebuildActiveEQFilter(sampleRate: 24000)
            core.rebuildRoomFilter(sampleRate: 24000)
            XCTAssertEqual(
                try measuredGain(core, frequency: 4000, includingRoom: true) - measuredGain(core, frequency: 4000),
                0, accuracy: 0.1
            )
            XCTAssertEqual(calibration.activeProfile?.notchFilters, profile.notchFilters)
            core.rebuildActiveEQFilter(sampleRate: 48000)
            core.rebuildRoomFilter(sampleRate: 48000)
            XCTAssertEqual(
                try measuredGain(core, frequency: 16000, includingRoom: true) - measuredGain(core, frequency: 16000),
                -6, accuracy: 0.2
            )
        }
    }

    func testEditorReportsDiskFailureRollsBackAndCanRetry() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let profileURL = directory.appendingPathComponent("profiles.json")
        let suite = "CalibrationSaveTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defer {
            if FileManager.default.fileExists(atPath: directory.path) {
                do { try FileManager.default.removeItem(at: directory) } catch {
                    XCTFail("Fixture cleanup failed: \(error)")
                }
            }
        }
        let core = CoreAudioEngine()
        let engine = AudioEngine(
            defaults: defaults,
            coreAudioEngine: core,
            enableRouting: { _ in true },
            disableRouting: { _ in }
        )
        engine.applyEQValues([Float](repeating: 2, count: 10))
        let calibration = CalibrationEngine(eqEngine: engine, profilesURL: profileURL, loadStoredProfiles: false)
        defer { calibration.flushProfileWrites() }
        var original = calibration.createProfile(name: "Original", type: .roomCorrection)
        original.notchFilters = [.init(frequency: 125, gain: -6, q: 4)]
        XCTAssertTrue(calibration.updateProfile(original))
        calibration.activateProfile(original)
        let originalRoom = try measuredGain(core, frequency: 125, includingRoom: true)
        core.setEnabled(false)
        var changed = original
        changed.name = "Changed"
        changed.bands[17] = 4
        changed.notchFilters = [.init(frequency: 250, gain: -10, q: 7)]
        let failed = await calibration.saveEditedProfile(changed)
        XCTAssertFalse(failed)
        XCTAssertEqual(calibration.profiles.first, original)
        XCTAssertEqual(calibration.activeProfile, original)
        XCTAssertEqual(core.getBandGain(index: 5), 2)
        XCTAssertFalse(core.isEnabled)
        core.setEnabled(true)
        XCTAssertEqual(try measuredGain(core, frequency: 125, includingRoom: true), originalRoom, accuracy: 0.2)
        core.setEnabled(false)
        XCTAssertFalse(FileManager.default.fileExists(atPath: profileURL.path))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let saved = await calibration.saveEditedProfile(changed)
        XCTAssertTrue(saved)
        let data = try Data(contentsOf: profileURL)
        let decoded = try JSONDecoder().decode([CalibrationProfile].self, from: data)
        XCTAssertEqual(decoded, [changed])
        XCTAssertEqual(calibration.activeProfile, changed)
        XCTAssertEqual(core.getBandGain(index: 5), 6)
        XCTAssertFalse(core.isEnabled)
        core.setEnabled(true)
        XCTAssertEqual(
            try measuredGain(core, frequency: 250, includingRoom: true) - measuredGain(core, frequency: 250),
            -10, accuracy: 0.2
        )
        core.setEnabled(false)
        var draft = CalibrationProfileDraft(changed)
        draft.name = "Cancelled"
        draft.bandInputs[17] = "8"
        calibration.flushProfileWrites()
        XCTAssertEqual(try Data(contentsOf: profileURL), data)
        var invalid = changed
        invalid.bands = []
        let rejected = await calibration.saveEditedProfile(invalid)
        XCTAssertFalse(rejected)
        XCTAssertEqual(try Data(contentsOf: profileURL), data)
        calibration.deleteProfile(changed)
        calibration.flushProfileWrites()
        let deletedData = try Data(contentsOf: profileURL)
        let stale = await calibration.saveEditedProfile(changed)
        XCTAssertFalse(stale)
        XCTAssertEqual(try Data(contentsOf: profileURL), deletedData)
        XCTAssertTrue(calibration.profiles.isEmpty)
    }

    func testCalibrationStepsSkipReferenceAndPreserve31StoredBands() throws {
        try withProfile { _, calibration, _, _ in
            let ten = calibration.calibrationBandIndices(mode: .tenBand)
            let thirtyOne = calibration.calibrationBandIndices(mode: .thirtyOneBand)
            XCTAssertEqual(ten.count, 9)
            XCTAssertEqual(Array(ten[4...5]), [14, 20])
            XCTAssertEqual(thirtyOne.count, 30)
            XCTAssertEqual(Array(thirtyOne[16...17]), [16, 18])
            XCTAssertEqual(thirtyOne.last, 30)
            XCTAssertFalse(ten.contains(17))
            XCTAssertFalse(thirtyOne.contains(17))
            let profile = try XCTUnwrap(calibration.equalLoudnessProfile(
                name: " Test ", bands: [Float](repeating: 3, count: 31), notes: "notes"
            ))
            XCTAssertEqual(profile.bands.count, 31)
            XCTAssertEqual(profile.bands[17], 0)
            XCTAssertEqual(profile.bands[18], 3)
            XCTAssertEqual(profile.name, "Test")
            XCTAssertNil(calibration.equalLoudnessProfile(name: " ", bands: [], notes: ""))
        }
    }

    func testProfileDraftCancelValidationAndMetadataPreservation() throws {
        var original = CalibrationProfile(
            name: "Original",
            type: .custom,
            bands: [Float](repeating: 25.123456, count: 31)
        )
        original.createdAt = Date(timeIntervalSince1970: 12345)
        var draft = CalibrationProfileDraft(original, locale: Locale(identifier: "it_IT"))
        draft.name = " Changed "
        draft.notes = "new notes"
        draft.bandInputs[2] = "-2,5"
        let updated = try XCTUnwrap(draft.updatedProfile)
        XCTAssertEqual(updated.id, original.id)
        XCTAssertEqual(updated.createdAt, original.createdAt)
        XCTAssertEqual(updated.type, original.type)
        XCTAssertEqual(updated.name, "Changed")
        XCTAssertEqual(updated.bands[2], -2.5)
        XCTAssertEqual(updated.bands[0], original.bands[0])
        XCTAssertEqual(original.name, "Original")
        XCTAssertEqual(original.bands[2], 25.123456)
        for input in ["", "nan", "inf", "3bad", "1,2,3", "1e100"] {
            draft.bandInputs[2] = input
            XCTAssertNil(draft.updatedProfile)
        }
        draft = CalibrationProfileDraft(original)
        draft.name = " \n "
        XCTAssertNil(draft.updatedProfile)
        for bands in [
            [],
            [Float](repeating: 0, count: 30),
            [Float](repeating: 0, count: 32),
            [Float](repeating: .nan, count: 31)
        ] {
            original.bands = bands
            XCTAssertNil(CalibrationProfileDraft(original).updatedProfile)
        }
    }

    func testActiveProfileEditsRefreshCorrectionWithoutEnablingRouting() throws {
        try withProfile { _, calibration, core, _ in
            var profile = calibration.createProfile(name: "Original", type: .equalLoudness)
            calibration.activateProfile(profile)
            core.setEnabled(false)
            profile.name = "Changed"
            profile.bands[17] = 4
            XCTAssertTrue(calibration.updateProfile(profile))
            XCTAssertFalse(core.isEnabled)
            XCTAssertEqual(calibration.activeProfile, profile)
            XCTAssertEqual(core.getBandGain(index: 5), 6)
            var invalid = profile
            invalid.bands = []
            XCTAssertFalse(calibration.updateProfile(invalid))
            XCTAssertEqual(calibration.activeProfile, profile)
            XCTAssertEqual(core.getBandGain(index: 5), 6)
            calibration.deleteProfile(profile)
            XCTAssertFalse(calibration.updateProfile(profile))
            XCTAssertTrue(calibration.profiles.isEmpty)
            XCTAssertNil(calibration.activeProfile)
        }
    }

    func testInactiveProfileEditsDoNotApplyAndDraftDoesNotMutatePersistence() throws {
        try withProfile { _, calibration, core, defaults in
            var profile = calibration.createProfile(name: "Original", type: .custom)
            calibration.flushProfileWrites()
            let snapshot = defaults.data(forKey: "lastPlayback.snapshot")
            var draft = CalibrationProfileDraft(profile)
            draft.name = "Uncommitted"
            draft.bandInputs[0] = "8"
            XCTAssertEqual(calibration.profiles.first?.name, "Original")
            XCTAssertEqual(core.getBandGain(index: 0), 2)
            core.setEnabled(false)
            profile.notes = "saved notes"
            profile.bands[0] = 6
            XCTAssertTrue(calibration.updateProfile(profile))
            XCTAssertNil(calibration.activeProfile)
            XCTAssertFalse(core.isEnabled)
            XCTAssertEqual(core.getBandGain(index: 0), 2)
            XCTAssertEqual(defaults.data(forKey: "lastPlayback.snapshot"), snapshot)
            calibration.flushProfileWrites()
        }
    }

    private func measuredGain(
        _ core: CoreAudioEngine, frequency: Double, includingRoom: Bool = false
    ) throws -> Double {
        let filter = try XCTUnwrap(core.vdspFilter)
        let rate = Double(filter.sampleRate)
        var inputEnergy = 0.0
        var outputEnergy = 0.0
        for block in 0..<32 {
            let source = (0..<512).map { index in
                Float(0.001 * sin(2 * .pi * frequency * Double(block * 512 + index) / rate))
            }
            var left = source
            var right = source
            _ = try left.withUnsafeMutableBufferPointer { l in
                try right.withUnsafeMutableBufferPointer { r in
                    if includingRoom {
                        try core.processStereoInPlace(
                            left: XCTUnwrap(l.baseAddress), right: XCTUnwrap(r.baseAddress), frameCount: 512
                        )
                    } else {
                        _ = try filter.processStereo(
                            XCTUnwrap(l.baseAddress),
                            XCTUnwrap(r.baseAddress),
                            frameCount: 512
                        )
                    }
                }
            }
            if block > 7 {
                inputEnergy += source.reduce(0) { $0 + Double($1 * $1) }
                outputEnergy += left.reduce(0) { $0 + Double($1 * $1) }
            }
        }
        return 10 * log10(outputEnergy / inputEnergy)
    }

    private func renderedEnergy(_ audio: AVAudioEngine, frames: Int = 96000) throws -> Double {
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: audio.manualRenderingFormat, frameCapacity: 1024))
        var remaining = frames
        var energy = 0.0
        while remaining > 0 {
            let count = AVAudioFrameCount(min(remaining, 1024))
            XCTAssertEqual(try audio.renderOffline(count, to: buffer), .success)
            let samples = try XCTUnwrap(buffer.floatChannelData)[0]
            for index in 0..<Int(buffer.frameLength) {
                energy += Double(samples[index] * samples[index])
            }
            remaining -= Int(count)
        }
        return energy
    }

    private func withProfile(
        mode: EQBandMode = .tenBand,
        _ test: (AudioEngine, CalibrationEngine, CoreAudioEngine, UserDefaults) throws -> Void
    ) throws {
        let suite = "CalibrationProfileTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            do { try FileManager.default.removeItem(at: directory) } catch {
                XCTFail("Temporary profile cleanup failed: \(error)")
            }
        }
        let core = CoreAudioEngine()
        let engine = AudioEngine(
            defaults: defaults,
            coreAudioEngine: core,
            enableRouting: { _ in core.clearEQ(); return true },
            disableRouting: { _ in }
        )
        engine.bandMode = mode
        engine.applyEQValues([Float](repeating: 2, count: mode.bandCount))
        let calibration = CalibrationEngine(
            eqEngine: engine,
            profilesURL: directory.appendingPathComponent("profiles.json"),
            loadStoredProfiles: false
        )
        defer { calibration.flushProfileWrites() }
        try test(engine, calibration, core, defaults)
    }

    func testProfileSurvivesToggleAndRoutingReapplyWithoutChangingBaseSnapshot() throws {
        try withProfile { engine, calibration, core, defaults in
            let profile = CalibrationProfile(
                name: "Test",
                type: .equalLoudness,
                bands: [Float](repeating: 3, count: 31)
            )
            calibration.activateProfile(profile)
            XCTAssertEqual(core.getBandGain(index: 5), 5)
            XCTAssertTrue(engine.setEnabled(false))
            XCTAssertTrue(engine.setEnabled(true))
            XCTAssertEqual(core.getBandGain(index: 5), 5)
            core.clearEQ()
            engine.reapplyCurrentFilters()
            XCTAssertEqual(core.getBandGain(index: 5), 5)
            XCTAssertEqual(calibration.activeProfile?.id, profile.id)
            XCTAssertEqual(engine.bands.map(\.gain), [Float](repeating: 2, count: 10))
            XCTAssertEqual(PresetPersistence.loadPlaybackState(in: defaults)?.gains, [Float](repeating: 2, count: 10))
        }
    }

    func testSwitchingProfilesAndDeactivationDoNotAccumulateCorrection() throws {
        try withProfile { engine, calibration, core, _ in
            let a = CalibrationProfile(name: "A", type: .equalLoudness, bands: [Float](repeating: 3, count: 31))
            let b = CalibrationProfile(name: "B", type: .equalLoudness, bands: [Float](repeating: -1, count: 31))
            for profile in [a, b, a] {
                calibration.activateProfile(profile)
                XCTAssertEqual(core.getBandGain(index: 0), 2 + profile.bands[2])
            }
            engine.applyEQValues([Float](repeating: 4, count: 10))
            XCTAssertEqual(core.getBandGain(index: 0), 7)
            calibration.deactivateProfile()
            XCTAssertEqual(core.getBandGain(index: 0), 4)
            calibration.activateProfile(a)
            calibration.deleteProfile(a)
            XCTAssertNil(calibration.activeProfile)
            XCTAssertEqual(core.getBandGain(index: 0), 4)
        }
    }

    func testProfileChangesActualDSPResponseAfterToggleAndSampleRateChange() throws {
        try withProfile { engine, calibration, core, _ in
            var base = [Float](repeating: 0, count: 10)
            base[5] = 3
            engine.applyEQValues(base)
            var correction = [Float](repeating: 0, count: 31)
            correction[17] = 6
            calibration.activateProfile(CalibrationProfile(name: "DSP", type: .equalLoudness, bands: correction))
            XCTAssertEqual(try measuredGain(core, frequency: 1000), 9, accuracy: 0.05)
            XCTAssertTrue(engine.setEnabled(false))
            XCTAssertTrue(engine.setEnabled(true))
            XCTAssertEqual(try measuredGain(core, frequency: 1000), 9, accuracy: 0.05)
            core.rebuildActiveEQFilter(sampleRate: 96000)
            XCTAssertEqual(try measuredGain(core, frequency: 1000), 9, accuracy: 0.05)
            calibration.deactivateProfile()
            XCTAssertEqual(try measuredGain(core, frequency: 1000), 3, accuracy: 0.05)
        }
    }

    func testProfilePreserves31BandModeAcrossRateAndModeChanges() throws {
        try withProfile(mode: .thirtyOneBand) { engine, calibration, core, _ in
            var gains = [Float](repeating: 1, count: 31)
            gains[30] = 6
            calibration.activateProfile(CalibrationProfile(name: "31", type: .equalLoudness, bands: gains))
            XCTAssertEqual(core.vdspFilter?.activeFilterCount, 31)
            XCTAssertEqual(core.getBandGain(index: 30), 8)
            core.rebuildActiveEQFilter(sampleRate: 96000)
            XCTAssertEqual(core.vdspFilter?.activeFilterCount, 31)
            XCTAssertEqual(core.vdspFilter?.sampleRate, 96000)
            engine.bandMode = .tenBand
            engine.reapplyCurrentFilters()
            XCTAssertEqual(core.vdspFilter?.activeFilterCount, 10)
            engine.bandMode = .thirtyOneBand
            engine.reapplyCurrentFilters()
            XCTAssertEqual(core.getBandGain(index: 30), 8)
            XCTAssertEqual(core.vdspFilter?.activeFilterCount, 31)
        }
    }

    func testMalformedProfilesLeaveActiveCorrectionUnchanged() throws {
        try withProfile { _, calibration, core, _ in
            let valid = CalibrationProfile(name: "Valid", type: .equalLoudness, bands: [Float](repeating: 3, count: 31))
            calibration.activateProfile(valid)
            for bands in [
                [],
                [Float](repeating: 1, count: 30),
                [Float](repeating: .nan, count: 31),
                [Float](repeating: .infinity, count: 31)
            ] {
                calibration.activateProfile(CalibrationProfile(name: "Invalid", type: .equalLoudness, bands: bands))
                XCTAssertEqual(calibration.activeProfile?.id, valid.id)
                XCTAssertEqual(core.getBandGain(index: 5), 5)
            }
        }
    }

    func testBandEditsKeepExplicit31BandModeAndRejectInvalidValues() {
        let core = CoreAudioEngine()
        core.applyGraphicEQ31([Float](repeating: 1, count: 31))
        core.setEQBand(index: 30, gain: 6)
        XCTAssertEqual(core.vdspFilter?.activeFilterCount, 31)
        core.setEQBand(index: -1, gain: 3)
        core.setEQBand(index: 31, gain: 3)
        core.setEQBand(index: 30, gain: .nan)
        XCTAssertEqual(core.getBandGain(index: 30), 6)
        core.setAllBands([Float](repeating: 2, count: 31))
        core.rebuildActiveEQFilter(sampleRate: 192_000)
        XCTAssertEqual(core.vdspFilter?.activeFilterCount, 31)
        XCTAssertEqual(core.getBandGain(index: 30), 2)
        core.applyFixedBandEQ([Float](repeating: 1, count: 31))
        core.rebuildActiveEQFilter(sampleRate: 48000)
        XCTAssertEqual(core.vdspFilter?.activeFilterCount, 10)
    }

    func testLoopVolumeChangesImmediatelyAndStoppedUpdatesDoNotStartAudio() {
        let player = AVAudioPlayerNode()
        let calibration = CalibrationEngine(playerNode: player, loadStoredProfiles: false)
        player.volume = 0.2
        calibration.updateLoopAmplitude(0.8)
        XCTAssertEqual(player.volume, 0.2)
        XCTAssertFalse(player.isPlaying)
        calibration.isPlayingLoop = true
        calibration.updateLoopAmplitude(0.05)
        XCTAssertEqual(player.volume, 0.05)
        calibration.updatePinkNoiseLoopAmplitude(0.4)
        XCTAssertEqual(player.volume, 0.4)
        for invalid in [Float.nan, .infinity, -1] {
            calibration.updateLoopAmplitude(invalid)
            XCTAssertEqual(player.volume, 0)
        }
        calibration.updateLoopAmplitude(2)
        XCTAssertEqual(player.volume, 1)
    }

    func testProfileModeLevelAndRecalibrationPreserveIdentityAndHiddenBands() throws {
        var original = CalibrationProfile(
            name: "Ten", type: .equalLoudness, notes: "Original", sourceBandMode: .tenBand, overallGainDB: -5
        )
        original.bands[0] = 3
        original.bands[17] = 2
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(CalibrationProfile.self, from: data), original)
        var draft = CalibrationProfileDraft(original)
        XCTAssertEqual(draft.visibleBandIndices.count, 10)
        XCTAssertFalse(draft.visibleBandIndices.contains(0))
        draft.bandInputs[2] = "6"
        draft.overallGainDB = -7
        let edited = try XCTUnwrap(draft.updatedProfile)
        XCTAssertEqual(edited.bands[0], 3)
        XCTAssertEqual(edited.overallGainDB, -7)
        let calibration = CalibrationEngine(loadStoredProfiles: false)
        let resumed = try XCTUnwrap(calibration.equalLoudnessProfile(
            name: "Revised", bands: edited.bands, notes: "Revised notes", sourceBandMode: .tenBand, replacing: edited
        ))
        XCTAssertEqual(resumed.id, original.id)
        XCTAssertEqual(resumed.createdAt, original.createdAt)
        XCTAssertEqual(resumed.overallGainDB, -7)
        XCTAssertEqual(resumed.bands[17], 2)
        XCTAssertEqual(resumed.bands[2], 6)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "sourceBandMode")
        legacy.removeValue(forKey: "overallGainDB")
        let decoded = try JSONDecoder().decode(
            CalibrationProfile.self,
            from: JSONSerialization.data(withJSONObject: legacy)
        )
        XCTAssertNil(decoded.sourceBandMode)
        XCTAssertEqual(decoded.overallGainDB, 0)
        XCTAssertEqual(CalibrationProfileDraft(decoded).visibleBandIndices.count, 31)
        for invalid: Any in [NSNull(), "bad", 1, -21] {
            legacy["overallGainDB"] = invalid
            XCTAssertThrowsError(try JSONDecoder().decode(
                CalibrationProfile.self,
                from: JSONSerialization.data(withJSONObject: legacy)
            ))
        }
        legacy["overallGainDB"] = 0
        legacy["sourceBandMode"] = "unknown"
        XCTAssertThrowsError(try JSONDecoder().decode(
            CalibrationProfile.self,
            from: JSONSerialization.data(withJSONObject: legacy)
        ))
        for invalid: Float in [.nan, .infinity, 1, -21] {
            draft.overallGainDB = invalid
            XCTAssertNil(draft.updatedProfile)
        }
    }

    func testAutoPreampUsesEffectiveCalibrationGainsAndProfileLevel() throws {
        for mode in EQBandMode.allCases {
            try withProfile(mode: mode) { engine, calibration, core, _ in
                engine.applyEQValues(Array(repeating: 0, count: mode.bandCount))
                XCTAssertEqual(engine.recommendedPreampGain(), 0, accuracy: 0.001)
                var gains = [Float](repeating: 0, count: 31)
                gains[2] = 10
                let profile = CalibrationProfile(name: "Bass", type: .equalLoudness, bands: gains, overallGainDB: -5)
                calibration.activateProfile(profile)
                let effective = mode.frequencies.map { $0 == 31.5 ? Float(10) : 0 }
                let expected = min(0, FixedBandAutoPreamp.recommendedGain(
                    mode: mode, gains: effective, sampleRate: Float(core.processingSampleRate)
                ) + 5)
                XCTAssertEqual(engine.recommendedPreampGain(), expected, accuracy: 0.001)
                XCTAssertLessThan(expected, -4)
                engine.applyAutoPreamp()
                XCTAssertEqual(engine.preampGain, expected, accuracy: 0.001)
                calibration.deactivateProfile()
                XCTAssertEqual(engine.recommendedPreampGain(), 0, accuracy: 0.001)
            }
        }
    }

    func testCalibrationChangesInvalidateObservedHeadroom() throws {
        try withProfile { engine, _, _, _ in
            var changes = 0
            let observation = engine.objectWillChange.sink { changes += 1 }
            defer { observation.cancel() }
            var gains = [Float](repeating: 0, count: 31)
            gains[2] = 10
            let before = engine.recommendedPreampGain()
            XCTAssertTrue(engine.setCalibrationAdjustments(gains, overallGainDB: -5))
            XCTAssertGreaterThan(changes, 0)
            XCTAssertLessThan(engine.recommendedPreampGain(), before)
            let accepted = changes
            XCTAssertFalse(engine.setCalibrationAdjustments(gains, overallGainDB: .nan))
            XCTAssertEqual(changes, accepted)
            XCTAssertTrue(engine.setCalibrationAdjustments(nil))
            XCTAssertGreaterThan(changes, accepted)
            XCTAssertEqual(engine.recommendedPreampGain(), before, accuracy: 0.001)
        }
    }

    func testProfileOverallLevelIsScalarAndSurvivesRebuildAndDeactivation() throws {
        for mode in EQBandMode.allCases {
            try withProfile(mode: mode) { engine, calibration, core, _ in
                engine.applyEQValues(Array(repeating: 0, count: mode.bandCount))
                engine.setPreampGain(-20)
                let profile = CalibrationProfile(name: "Quiet", type: .equalLoudness, overallGainDB: -5)
                calibration.activateProfile(profile)
                for frequency: Double in [63, 1000, 8000] {
                    XCTAssertEqual(try measuredGain(core, frequency: frequency), -25, accuracy: 0.05)
                }
                core.rebuildActiveEQFilter(sampleRate: 96000)
                XCTAssertEqual(try measuredGain(core, frequency: 1000), -25, accuracy: 0.05)
                engine.reapplyCurrentFilters()
                XCTAssertEqual(try measuredGain(core, frequency: 1000), -25, accuracy: 0.05)
                for invalid: Float in [.nan, .infinity, 1, -21] {
                    XCTAssertFalse(engine.setCalibrationAdjustments(profile.bands, overallGainDB: invalid))
                    XCTAssertEqual(try measuredGain(core, frequency: 1000), -25, accuracy: 0.05)
                }
                calibration.deactivateProfile()
                XCTAssertEqual(engine.preampGain, -20)
                XCTAssertEqual(try measuredGain(core, frequency: 1000), -20, accuracy: 0.05)
            }
        }
    }

    func testComparisonVolumeChangesCurrentBufferWithoutChangingReference() async throws {
        for noise in [false, true] {
            let audio = AVAudioEngine()
            let player = AVAudioPlayerNode()
            let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2))
            audio.attach(player)
            try audio.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 1024)
            audio.connect(player, to: audio.mainMixerNode, format: format)
            try audio.start()
            defer { player.stop(); audio.stop() }
            let calibration = CalibrationEngine(audioEngine: audio, playerNode: player, loadStoredProfiles: false)
            calibration.useFilteredNoise = noise
            calibration.comparisonMode = true
            calibration.playComparisonSignal(frequency: 1000, level: -20, isReference: true)
            let referenceVolume = player.volume
            calibration.updateComparisonTestLevel(-10)
            XCTAssertEqual(player.volume, referenceVolume)
            calibration.playComparisonSignal(frequency: 500, level: -20, isReference: false)
            _ = try renderedEnergy(audio, frames: 4800)
            let initial = try renderedEnergy(audio, frames: 4800)
            XCTAssertGreaterThan(initial, 0)
            calibration.updateComparisonTestLevel(-13.9794)
            let louder = try renderedEnergy(audio, frames: 4800)
            XCTAssertEqual(sqrt(louder / initial), 2, accuracy: noise ? 0.35 : 0.05)
            for invalid: Float in [.nan, .infinity, -.infinity] {
                calibration.updateComparisonTestLevel(invalid)
                XCTAssertEqual(player.volume, 0)
            }
            calibration.updateComparisonTestLevel(-20)
            XCTAssertEqual(player.volume, referenceVolume, accuracy: 0.00001)
            calibration.updateComparisonTestLevel(100)
            XCTAssertEqual(player.volume, 1)
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
            XCTAssertTrue(calibration.isTestTonePlaying)
            XCTAssertFalse(calibration.isPlayingReference)
            calibration.stopComparisonMode()
            let stopped = player.volume
            calibration.updateComparisonTestLevel(-20)
            XCTAssertEqual(player.volume, stopped)
            XCTAssertFalse(player.isPlaying)
        }
    }

    func testReferenceLoopsExposeLiveVolumeAndOneShotResetsGain() throws {
        for noise in [false, true] {
            let audio = AVAudioEngine()
            let player = AVAudioPlayerNode()
            let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2))
            audio.attach(player)
            try audio.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 1024)
            audio.connect(player, to: audio.mainMixerNode, format: format)
            try audio.start()
            defer { player.stop(); audio.stop() }
            let calibration = CalibrationEngine(audioEngine: audio, playerNode: player, loadStoredProfiles: false)
            calibration.useFilteredNoise = noise
            calibration.referenceFrequency = 1250
            calibration.referenceLevel = -20
            calibration.playReferenceTone()
            XCTAssertTrue(calibration.isPlayingLoop)
            XCTAssertEqual(calibration.currentTestFrequency, 1250)
            XCTAssertEqual(player.volume, 0.03, accuracy: 0.00001)
            let initialEnergy = try renderedEnergy(audio)
            XCTAssertGreaterThan(initialEnergy, 0)
            calibration.updateLoopAmplitude(0.15)
            XCTAssertEqual(player.volume, 0.15)
            XCTAssertTrue(player.isPlaying)
            let louderEnergy = try renderedEnergy(audio)
            XCTAssertEqual(sqrt(louderEnergy / initialEnergy), 5, accuracy: 0.3)
            calibration.playCalibrationSignal(frequency: 500, amplitude: 0.2)
            XCTAssertEqual(player.volume, 1)
            XCTAssertFalse(calibration.isPlayingLoop)
        }
    }
}
