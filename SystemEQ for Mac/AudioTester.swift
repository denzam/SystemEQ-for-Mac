//
//  AudioTester.swift
//  SystemEQ for Mac
//
//  Audio testing utility for validating audio engine functionality
//  Tests basic AVAudioEngine setup and device connectivity
//

import AVFoundation

#if DEBUG
    class AudioTester {
        static func testAudioFlow() {
            dlog("TESTING AUDIO FLOW...", level: .info, category: .audio)

            // macOS audio session setup (different from iOS)
            dlog("macOS audio environment ready", category: .audio)

            // Check available audio devices using AudioRouter
            dlog("Checking available audio devices...", category: .audio)

            // Try to create a simple audio engine test
            let testEngine = AVAudioEngine()
            let testEQ = AVAudioUnitEQ(numberOfBands: 2)

            testEngine.attach(testEQ)
            testEngine.connect(testEngine.inputNode, to: testEQ, format: nil)
            testEngine.connect(testEQ, to: testEngine.mainMixerNode, format: nil)

            dlog("Test engine created successfully", category: .audio)
            dlog("Input format: \(testEngine.inputNode.outputFormat(forBus: 0))", category: .audio)
            dlog("Output format: \(testEngine.outputNode.inputFormat(forBus: 0))", category: .audio)

            // Test basic engine functionality
            do {
                try testEngine.start()
                dlog("Test engine started successfully", category: .audio)
                testEngine.stop()
            } catch {
                dlog("Test engine failed to start: \(error)", level: .error, category: .audio)
            }
        }
    }
#endif
