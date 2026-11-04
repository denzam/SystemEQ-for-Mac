//
//  SineSweepGeneratorTests.swift
//  SystemEQ for MacTests
//
//  Regression: buffers were built in the hardware channel count, which returns a nil
//  format for >2-channel interfaces and crashed AVAudioPlayerNode.scheduleBuffer.
//

import AVFoundation
@testable import SystemEQ_for_Mac
import XCTest

final class SineSweepGeneratorTests: XCTestCase {
    // MARK: - Buffers

    func testGeneratedBuffersAreValidStereo() throws {
        let frames: AVAudioFrameCount = 4800
        for buffer in try generatedBuffers(frameCount: frames) {
            XCTAssertEqual(buffer.format.channelCount, 2)
            XCTAssertEqual(buffer.format.sampleRate, 48000)
            XCTAssertEqual(buffer.frameLength, frames)
            let channels = try XCTUnwrap(buffer.floatChannelData)
            var energy: Float = 0
            for frame in 0..<Int(frames) {
                let sample = channels[0][frame]
                XCTAssertTrue(sample.isFinite)
                XCTAssertLessThanOrEqual(abs(sample), 0.300001)
                XCTAssertEqual(channels[1][frame], sample)
                energy += sample * sample
            }
            XCTAssertGreaterThan(energy, 0)
        }
    }

    func testPlaybackFormatAvoidsUnspecifiedMultichannelLayout() throws {
        XCTAssertNil(AVAudioFormat(standardFormatWithSampleRate: 96000, channels: 16))
        XCTAssertEqual(SineSweepGenerator.playbackChannelCount, 2)
        let format = try XCTUnwrap(AVAudioFormat(
            standardFormatWithSampleRate: 48000,
            channels: SineSweepGenerator.playbackChannelCount
        ))
        for buffer in try generatedBuffers(frameCount: 4800) {
            XCTAssertEqual(buffer.format, format)
        }
    }

    func testZeroAndSingleFrameBuffersRemainValid() throws {
        for frames: AVAudioFrameCount in [0, 1] {
            for buffer in try generatedBuffers(frameCount: frames) {
                XCTAssertEqual(buffer.frameLength, frames)
                XCTAssertEqual(buffer.frameCapacity, frames)
                XCTAssertEqual(buffer.format.channelCount, 2)
                if frames == 1 {
                    let channels = try XCTUnwrap(buffer.floatChannelData)
                    XCTAssertEqual(channels[0][0], 0)
                    XCTAssertEqual(channels[1][0], 0)
                }
            }
        }
    }

    func testMixerConvertsStereo48kHzToMono441kHzOffline() throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1))
        try assertOfflineConversion(to: format)
    }

    func testMixerConvertsStereo48kHzTo16Channels96kHzOffline() throws {
        let layout = try XCTUnwrap(AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | 16))
        let format = AVAudioFormat(standardFormatWithSampleRate: 96000, channelLayout: layout)
        try assertOfflineConversion(to: format)
    }

    private func generatedBuffers(frameCount frames: AVAudioFrameCount) throws -> [AVAudioPCMBuffer] {
        let generator = SineSweepGenerator()
        return try [
            XCTUnwrap(generator.generateSineSweep(
                startFreq: 20,
                endFreq: 20000,
                duration: 0.1,
                sampleRate: 48000,
                frameCount: frames
            )),
            XCTUnwrap(generator.generateFixedTone(
                frequency: 1000,
                duration: 0.1,
                sampleRate: 48000,
                frameCount: frames
            )),
            XCTUnwrap(generator.generateContinuousTone(frequency: 1000, sampleRate: 48000, frameCount: frames)),
        ]
    }

    private func assertOfflineConversion(to format: AVAudioFormat) throws {
        for source in try generatedBuffers(frameCount: 4800) {
            let engine = AVAudioEngine()
            let player = AVAudioPlayerNode()
            defer {
                player.stop()
                engine.stop()
            }
            engine.attach(player)
            let playbackFormat = try XCTUnwrap(AVAudioFormat(
                standardFormatWithSampleRate: 48000,
                channels: SineSweepGenerator.playbackChannelCount
            ))
            engine.connect(player, to: engine.mainMixerNode, format: playbackFormat)
            try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 1024)
            let output = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 1024))
            player.scheduleBuffer(source, at: nil, options: .loops)
            try engine.start()
            player.play()

            XCTAssertEqual(player.outputFormat(forBus: 0), source.format)
            XCTAssertEqual(engine.manualRenderingFormat.channelCount, format.channelCount)
            XCTAssertEqual(engine.manualRenderingFormat.sampleRate, format.sampleRate)
            var energy: Float = 0
            for _ in 0..<8 {
                let status = try engine.renderOffline(1024, to: output)
                XCTAssertEqual(status, .success)
                guard status == .success else { return }
                XCTAssertEqual(output.frameLength, 1024)
                let channels = try XCTUnwrap(output.floatChannelData)
                for channel in 0..<Int(output.format.channelCount) {
                    for frame in 0..<Int(output.frameLength) {
                        let sample = channels[channel][frame]
                        XCTAssertTrue(sample.isFinite)
                        energy += sample * sample
                    }
                }
            }
            XCTAssertGreaterThan(energy, 0)
        }
    }
}
