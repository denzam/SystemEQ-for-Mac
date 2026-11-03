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
        let generator = SineSweepGenerator()
        let frames: AVAudioFrameCount = 4800
        let buffers = try [
            XCTUnwrap(generator.generateSineSweep(
                startFreq: 20,
                endFreq: 20000,
                duration: 0.1,
                sampleRate: 48000,
                frameCount: frames
            )),
            XCTUnwrap(generator.generateFixedTone(frequency: 1000, duration: 0.1, sampleRate: 48000, frameCount: frames)),
            XCTUnwrap(generator.generateContinuousTone(frequency: 1000, sampleRate: 48000, frameCount: frames)),
        ]
        for buffer in buffers {
            XCTAssertEqual(buffer.format.channelCount, 2)
            XCTAssertEqual(buffer.format.sampleRate, 48000)
            XCTAssertEqual(buffer.frameLength, frames)
        }
    }
}
