import Foundation
@testable import SystemEQ_for_Mac
import XCTest

@MainActor
final class ProfilePersistenceTests: XCTestCase {
    func testPersonalizedCorruptionSurvivesSaveAndDelete() async throws {
        try await withStorage { url, defaults, _ in
            for data in [Data(), Data("{".utf8), Data("null".utf8), Data("[{}]".utf8)] {
                try data.write(to: url)
                let manager = PersonalizedProfileManager(defaults: defaults, profilesURL: url)
                let profile = PersonalizedHearingProfile(name: "New")
                manager.saveProfile(profile)
                manager.deleteProfile(profile)
                XCTAssertEqual(try Data(contentsOf: url), data)
                XCTAssertTrue(manager.profiles.isEmpty)
            }
        }
    }

    func testPersonalizedReadFailureRequiresReloadBeforeWriting() async throws {
        try await withStorage { url, defaults, _ in
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            let manager = PersonalizedProfileManager(defaults: defaults, profilesURL: url)
            try FileManager.default.removeItem(at: url)
            let original = PersonalizedHearingProfile(name: "Original")
            let data = try JSONEncoder().encode([original])
            try data.write(to: url)
            manager.saveProfile(PersonalizedHearingProfile(name: "Blocked"))
            XCTAssertEqual(try Data(contentsOf: url), data)
            XCTAssertTrue(manager.profiles.isEmpty)

            let restored = PersonalizedProfileManager(defaults: defaults, profilesURL: url)
            restored.saveProfile(PersonalizedHearingProfile(name: "New"))
            let saved = try JSONDecoder().decode([PersonalizedHearingProfile].self, from: Data(contentsOf: url))
            XCTAssertEqual(saved.map(\.name), ["Original", "New"])
        }
    }

    func testPersonalizedMissingStorageAllowsRoundTripAndFailedWriteKeepsMemory() async throws {
        try await withStorage { url, defaults, _ in
            let manager = PersonalizedProfileManager(defaults: defaults, profilesURL: url)
            let profile = PersonalizedHearingProfile(name: "New")
            manager.saveProfile(profile)
            let restored = PersonalizedProfileManager(defaults: defaults, profilesURL: url)
            XCTAssertEqual(restored.profiles.map(\.id), [profile.id])
            restored.activeProfile = restored.profiles.first
            try FileManager.default.removeItem(at: url)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            restored.deleteProfile(profile)
            restored.saveProfile(PersonalizedHearingProfile(name: "Blocked"))
            XCTAssertEqual(restored.profiles.map(\.id), [profile.id])
            XCTAssertEqual(restored.activeProfile?.id, profile.id)
            try FileManager.default.removeItem(at: url)
            restored.deleteProfile(profile)
            XCTAssertTrue(restored.profiles.isEmpty)
            XCTAssertNil(restored.activeProfile)
            let saved = try JSONDecoder().decode([PersonalizedHearingProfile].self, from: Data(contentsOf: url))
            XCTAssertTrue(saved.isEmpty)
        }
    }

    func testCalibrationCorruptionSurvivesImmediateMutationFlushAndEdit() async throws {
        try await withStorage { url, _, engine in
            for data in [Data(), Data("{".utf8), Data("null".utf8), Data("[{}]".utf8)] {
                try data.write(to: url)
                let calibration = CalibrationEngine(eqEngine: engine, profilesURL: url)
                let original = calibration.createProfile(name: "New", type: .roomCorrection)
                calibration.flushProfileWrites()
                XCTAssertEqual(try Data(contentsOf: url), data)
                var edited = original
                edited.name = "Edited"
                let saved = await calibration.saveEditedProfile(edited)
                XCTAssertFalse(saved)
                calibration.deleteProfile(original)
                calibration.flushProfileWrites()
                XCTAssertEqual(try Data(contentsOf: url), data)
            }
        }
    }

    func testPersonalizedFailedEncodingPreservesBytesAndExistingPermissions() async throws {
        try await withStorage { url, defaults, _ in
            let manager = PersonalizedProfileManager(defaults: defaults, profilesURL: url)
            let original = PersonalizedHearingProfile(name: "Original")
            manager.saveProfile(original)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            let data = try Data(contentsOf: url)
            var invalid = PersonalizedHearingProfile(name: "Invalid")
            invalid.confidenceScore = .nan
            manager.saveProfile(invalid)
            XCTAssertEqual(try Data(contentsOf: url), data)
            XCTAssertEqual(manager.profiles.map(\.id), [original.id])
            manager.saveProfile(PersonalizedHearingProfile(name: "New"))
            XCTAssertEqual(manager.profiles.count, 2)
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        }
    }

    func testCalibrationReadFailureBlocksLaterWritableTarget() async throws {
        try await withStorage { url, _, engine in
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            let calibration = CalibrationEngine(eqEngine: engine, profilesURL: url)
            calibration.flushProfileWrites()
            try FileManager.default.removeItem(at: url)
            let data = try JSONEncoder().encode([CalibrationProfile(name: "Original", type: .roomCorrection)])
            try data.write(to: url)
            _ = calibration.createProfile(name: "Blocked", type: .roomCorrection)
            calibration.flushProfileWrites()
            XCTAssertEqual(try Data(contentsOf: url), data)
        }
    }

    func testCalibrationMissingAndLoadedStoragePreserveQueuedMutations() async throws {
        try await withStorage { url, _, engine in
            let first = CalibrationEngine(eqEngine: engine, profilesURL: url)
            let original = first.createProfile(name: "Original", type: .roomCorrection)
            first.flushProfileWrites()
            XCTAssertEqual(try JSONDecoder().decode([CalibrationProfile].self, from: Data(contentsOf: url)), [original])

            let restored = CalibrationEngine(eqEngine: engine, profilesURL: url)
            let added = restored.createProfile(name: "New", type: .roomCorrection)
            restored.flushProfileWrites()
            let saved = try JSONDecoder().decode([CalibrationProfile].self, from: Data(contentsOf: url))
            XCTAssertEqual(saved, [original, added])
        }
    }

    private func withStorage(_ test: (URL, UserDefaults, AudioEngine) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProfilePersistenceTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            do { try FileManager.default.removeItem(at: directory) } catch {
                XCTFail("Fixture cleanup failed: \(error)")
            }
        }
        let suite = "ProfilePersistenceTests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let core = CoreAudioEngine()
        let engine = AudioEngine(
            defaults: defaults, coreAudioEngine: core,
            enableRouting: { _ in true }, disableRouting: { _ in }
        )
        try await test(directory.appendingPathComponent("profiles.json"), defaults, engine)
    }
}
