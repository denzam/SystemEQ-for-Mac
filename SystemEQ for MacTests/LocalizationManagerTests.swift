//
//  LocalizationManagerTests.swift
//  SystemEQ for MacTests
//
//  Unit tests for LocalizationManager and translation completeness
//

@testable import SystemEQ_for_Mac
import XCTest

final class LocalizationManagerTests: XCTestCase {
    func testOnboardingFollowsBackendPreferenceAndAvailability() {
        XCTAssertEqual(WelcomeAudioBackend.resolve(preference: .automatic, nativeAvailable: true), .native)
        XCTAssertEqual(WelcomeAudioBackend.resolve(preference: .automatic, nativeAvailable: false), .blackHole)
        XCTAssertEqual(WelcomeAudioBackend.resolve(preference: .native, nativeAvailable: true), .native)
        XCTAssertEqual(WelcomeAudioBackend.resolve(preference: .native, nativeAvailable: false), .nativeUnavailable)
        XCTAssertEqual(WelcomeAudioBackend.resolve(preference: .blackHole, nativeAvailable: true), .blackHole)
        XCTAssertEqual(WelcomeAudioBackend.resolve(preference: .blackHole, nativeAvailable: false), .blackHole)
    }

    func testAllTranslationsAreComplete() {
        let missing = LocalizationManager.shared.validateTranslations()
        XCTAssertTrue(
            missing.isEmpty,
            "Missing translations found: \(LocalizationManager.shared.generateMissingReport())"
        )
    }

    func testAllLanguagesCoverAllKeys() {
        XCTAssertEqual(EnglishTranslations.strings.count, LocalizedString.allCases.count)
        XCTAssertEqual(ItalianTranslations.strings.count, LocalizedString.allCases.count)
        XCTAssertEqual(UkrainianTranslations.strings.count, LocalizedString.allCases.count)
    }

    func testBasicTranslationLookup() {
        let titleEN = LocalizedString.mainWindowTitle.translate(in: .english)
        let titleIT = LocalizedString.mainWindowTitle.translate(in: .italian)
        let titleUK = LocalizedString.mainWindowTitle.translate(in: .ukrainian)

        XCTAssertEqual(titleEN, "SystemEQ for Mac")
        XCTAssertEqual(titleIT, "SystemEQ per Mac")
        XCTAssertEqual(titleUK, "SystemEQ для Mac")
    }

    func testEqualizerCurveAccessibilityTranslations() {
        XCTAssertEqual(LocalizedString.equalizerCurve.translate(in: .english), "Equalizer Curve")
        XCTAssertEqual(LocalizedString.equalizerCurve.translate(in: .italian), "Curva Equalizzatore")
        XCTAssertEqual(LocalizedString.equalizerCurve.translate(in: .ukrainian), "Крива еквалайзера")

        XCTAssertEqual(LocalizedString.equalizerFlat.translate(in: .english), "Flat (all bands at 0 dB)")
        XCTAssertEqual(LocalizedString.equalizerFlat.translate(in: .italian), "Piatto (tutte le bande a 0 dB)")
        XCTAssertEqual(LocalizedString.equalizerFlat.translate(in: .ukrainian), "Лінійна (всі смуги на 0 дБ)")
    }
}
