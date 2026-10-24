import Foundation
@testable import SystemEQ_for_Mac
import XCTest

@MainActor
final class FeedbackReportTests: XCTestCase {
    private func report(
        version: String = "1.4.6", build: String = "8", backend: String = "native",
        sampleRate: Double = 48000, preamp: Double = -3, outputBoost: Double = 0,
        events: [DiagnosticEvent] = []
    ) -> FeedbackReport {
        FeedbackReport(
            version: version, build: build,
            operatingSystem: OperatingSystemVersion(majorVersion: 14, minorVersion: 4, patchVersion: 1),
            eqEnabled: true, engineRunning: true, bandCount: 31, backend: backend,
            sampleRate: sampleRate, preamp: preamp, outputBoost: outputBoost, events: events
        )
    }

    func testKnownStateAndFailureCodesAreRetained() {
        XCTAssertEqual(FeedbackReport.recipient, "systemeqformac@gmail.com")
        let text = report(events: [
            DiagnosticEvent(timestamp: Date(), name: "engine.start.failed", details: ["inputStatus": "-10851"]),
        ]).text
        for value in ["1.4.6", "macOS: 14.4.1", "Band count: 31", "Backend: native", "48000.00", "inputStatus=-10851"] {
            XCTAssertTrue(text.contains(value), value)
        }
    }

    func testRawErrorsUnknownEventsAndExtraFieldsNeverLeaveReport() {
        let secret = "/Users/private-person/secret-token.txt"
        let text = report(events: [
            DiagnosticEvent(timestamp: Date(), name: "routing.enable.failed", details: [
                "reason": secret, "deviceUID": secret, "deviceName": secret,
            ]),
            DiagnosticEvent(timestamp: Date(), name: "engine.start.failed", details: [
                "inputStatus": "-10851", "outputStatus": secret, "unknownKey": secret,
            ]),
            DiagnosticEvent(timestamp: Date(), name: secret, details: ["status": "0"]),
        ]).text
        XCTAssertFalse(text.contains(secret))
        XCTAssertFalse(text.contains("reason="))
        XCTAssertFalse(text.contains("deviceUID"))
        XCTAssertTrue(text.contains("routing.enable.failed"))
        XCTAssertTrue(text.contains("inputStatus=-10851"))
    }

    func testMalformedMetadataAndNonFiniteNumbersAreOmitted() {
        let text = report(
            version: "1.4.6\n/private/token", build: "secret@example.com", backend: "Personal DAC",
            sampleRate: .infinity, preamp: .nan, outputBoost: 1e100
        ).text
        for value in ["/private/token", "secret@example.com", "Personal DAC", "inf", "nan", "1e+100"] {
            XCTAssertFalse(text.contains(value), value)
        }
        XCTAssertTrue(text.contains("App version: unavailable"))
        XCTAssertTrue(text.contains("Sample rate Hz: unavailable"))
    }

    func testNumericFieldsRejectInjectionAndOverflowAndRemainScopedToEvent() {
        let text = report(events: [
            DiagnosticEvent(timestamp: Date(), name: "engine.setup.stepFailed", details: [
                "status": "0\nsecret", "inputStatus": "123",
            ]),
            DiagnosticEvent(timestamp: Date(), name: "visualizer.ipc.failed", details: ["status": "2147483648"]),
            DiagnosticEvent(timestamp: Date(), name: "engine.stop", details: ["status": "42"]),
        ]).text
        XCTAssertFalse(text.contains("secret"))
        XCTAssertFalse(text.contains("status="))
        XCTAssertFalse(text.contains("inputStatus="))
    }

    func testOnlyLastFiftyKnownEventsAreIncluded() {
        let events = (0..<100).map {
            DiagnosticEvent(timestamp: Date(), name: "visualizer.ipc.failed", details: ["status": String($0)])
        }
        let text = report(events: events).text
        XCTAssertFalse(text.contains("status=49\n"))
        XCTAssertTrue(text.contains("status=50\n"))
        XCTAssertTrue(text.hasSuffix("status=99"))
        XCTAssertEqual(text.components(separatedBy: "visualizer.ipc.failed").count - 1, 50)
    }

    func testDescriptionIsBoundedAndCannotInjectControlCharacters() {
        let message = FeedbackReport.message(
            description: "\u{0}\u{1B}" + String(repeating: "я", count: 3000), diagnostics: "safe diagnostics"
        )
        XCTAssertTrue(message.hasPrefix("safe diagnostics\n\n--- User description ---\n"))
        XCTAssertFalse(message.contains("\u{0}"))
        XCTAssertFalse(message.contains("\u{1B}"))
        XCTAssertEqual(message.filter { $0 == "я" }.count, FeedbackReport.descriptionLimit)
    }
}
