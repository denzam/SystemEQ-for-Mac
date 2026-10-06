//
//  AudioEngineBandModeTests.swift
//  SystemEQ for MacTests
//
//  Regression tests for applying EQ values right after a band-mode switch:
//  bandMode's didSet rebuilds `bands` only on the next main-loop turn, so a
//  same-turn applyEQValues used to see the stale array and bail out.
//

import AVFoundation
import CoreAudio
import Darwin
@testable import SystemEQ_for_Mac
import XCTest

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
        let original = calibration.createProfile(name: "Original", type: .equalLoudness)
        calibration.activateProfile(original)
        core.setEnabled(false)
        var changed = original
        changed.name = "Changed"
        changed.bands[17] = 4
        let failed = await calibration.saveEditedProfile(changed)
        XCTAssertFalse(failed)
        XCTAssertEqual(calibration.profiles.first, original)
        XCTAssertEqual(calibration.activeProfile, original)
        XCTAssertEqual(core.getBandGain(index: 5), 2)
        XCTAssertFalse(core.isEnabled)
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

    private func measuredGain(_ core: CoreAudioEngine, frequency: Double) throws -> Double {
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
                    try filter.processStereo(XCTUnwrap(l.baseAddress), XCTUnwrap(r.baseAddress), frameCount: 512)
                }
            }
            if block > 7 {
                inputEnergy += source.reduce(0) { $0 + Double($1 * $1) }
                outputEnergy += left.reduce(0) { $0 + Double($1 * $1) }
            }
        }
        return 10 * log10(outputEnergy / inputEnergy)
    }

    private func renderedEnergy(_ audio: AVAudioEngine) throws -> Double {
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: audio.manualRenderingFormat, frameCapacity: 1024))
        var remaining = 96000
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

    func testReferenceLoopsExposeLiveVolumeAndOneShotResetsGain() throws {
        for noise in [false, true] {
            let audio = AVAudioEngine()
            let player = AVAudioPlayerNode()
            let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2))
            audio.attach(player)
            audio.connect(player, to: audio.mainMixerNode, format: format)
            try audio.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 1024)
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
