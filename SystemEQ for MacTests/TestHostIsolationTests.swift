import AppKit
@testable import SystemEQ_for_Mac
import XCTest

@MainActor
final class TestHostIsolationTests: XCTestCase {
    private let protectedKeys = [
        "lastPlayback.snapshot", "eqWasEnabled", "originalSystemOutputUID",
        "originalDeviceSampleRates", "audioRoutingBackend", "hasCompletedSetup"
    ]

    private func protectedDefaults() -> NSDictionary {
        let defaults = UserDefaults.standard
        return NSDictionary(dictionary: protectedKeys.reduce(into: [String: Any]()) { values, key in
            values[key] = defaults.object(forKey: key)
        })
    }

    func testTestHostDetectionFailsClosedForPresentMarkers() {
        XCTAssertFalse(TestHostRuntime.detect(environment: [:]))
        XCTAssertFalse(TestHostRuntime.detect(environment: ["UNRELATED": "1"]))
        for marker in [
            "SYSTEMEQ_TEST_HOST", "XCTestConfigurationFilePath", "XCTestBundlePath", "XCTestSessionIdentifier"
        ] {
            XCTAssertTrue(TestHostRuntime.detect(environment: [marker: ""]))
            XCTAssertTrue(TestHostRuntime.detect(environment: [marker: "0"]))
        }
        XCTAssertTrue(TestHostRuntime.detect(environment: [
            "SYSTEMEQ_TEST_HOST": "0", "XCTestConfigurationFilePath": "/test/configuration"
        ]))
    }

    func testExecutingHostIsExplicitlyIsolated() {
        XCTAssertTrue(TestHostRuntime.isActive)
        XCTAssertTrue(TestHostRuntime.detect(environment: ProcessInfo.processInfo.environment))
        XCTAssertTrue(TestHostRuntime.detect(environment: ProcessInfo.processInfo.environment.filter {
            $0.key != "SYSTEMEQ_TEST_HOST"
        }))
        XCTAssertTrue(NSApplication.shared.windows.allSatisfy { !$0.isVisible })
    }

    func testLaunchAndTerminationSuppressApplicationActions() async {
        var launches = 0
        var terminations = 0
        let before = protectedDefaults()
        let delegate = AppDelegate(
            isTestHost: true, launch: { launches += 1 }, terminate: { terminations += 1 }
        )
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        await AppStartup.run()
        XCTAssertEqual(delegate.applicationShouldTerminate(.shared), .terminateNow)
        XCTAssertEqual(launches, 0)
        XCTAssertEqual(terminations, 0)
        XCTAssertEqual(protectedDefaults(), before)
    }

    func testApplicationLifecycleControlInvokesInjectedActions() {
        var launches = 0
        var terminations = 0
        let delegate = AppDelegate(
            isTestHost: false, launch: { launches += 1 }, terminate: { terminations += 1 }
        )
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        XCTAssertEqual(delegate.applicationShouldTerminate(.shared), .terminateNow)
        XCTAssertEqual(launches, 1)
        XCTAssertEqual(terminations, 1)
    }

    func testIsolatedRouterRejectsObserversAndAllSystemEvents() {
        var registrations = 0
        var handled: [AudioRouter.SystemEvent] = []
        let before = protectedDefaults()
        let router = AudioRouter(
            isTestHost: true, installObservers: { _ in registrations += 1 }, handleEvent: { handled.append($0) }
        )
        for event in AudioRouter.SystemEvent.allCases {
            router.handleSystemEvent(event)
        }
        XCTAssertEqual(registrations, 0)
        XCTAssertTrue(handled.isEmpty)
        XCTAssertEqual(protectedDefaults(), before)
    }

    func testApplicationRouterControlRegistersAndDispatchesToFakeAdapters() {
        var registrations = 0
        var handled: [AudioRouter.SystemEvent] = []
        let router = AudioRouter(
            isTestHost: false, installObservers: { _ in registrations += 1 }, handleEvent: { handled.append($0) }
        )
        for event in AudioRouter.SystemEvent.allCases {
            router.handleSystemEvent(event)
        }
        XCTAssertEqual(registrations, 1)
        XCTAssertEqual(handled, AudioRouter.SystemEvent.allCases)
    }

    func testIsolatedRouterRejectsDirectRoutingAndDefaultWrites() async {
        let before = protectedDefaults()
        let router = AudioRouter(isTestHost: true, installObservers: { _ in XCTFail("Unexpected observer") })
        let preference = router.backendPreference
        let device = AudioDevice(
            id: UInt32.max, name: "Isolated test device", uid: "test-only",
            isInput: true, isOutput: true
        )
        router.setBackendPreference(preference == .native ? .blackHole : .native)
        router.selectInputDevice(device)
        router.selectOutputDevice(device)
        await router.refreshDevices()
        XCTAssertFalse(router.enableEQRouting(forceRestart: true))
        router.testAudioRouting()
        router.disableEQRouting()
        router.setAsDefaultOutputDevice(device)
        router.restoreOriginalSystemOutputDevice()
        router.openBlackHoleDownload()
        router.openAudioMIDISetup()
        XCTAssertEqual(router.backendPreference, preference)
        XCTAssertNil(router.selectedInputDevice)
        XCTAssertNil(router.selectedOutputDevice)
        XCTAssertTrue(router.inputDevices.isEmpty)
        XCTAssertTrue(router.outputDevices.isEmpty)
        XCTAssertFalse(router.isRoutingOwned)
        XCTAssertEqual(router.activeBackend, .none)
        XCTAssertEqual(router.diagnosticSummary(), "Test host routing is isolated")
        XCTAssertEqual(protectedDefaults(), before)
    }

    func testSharedRouterAlsoRejectsPhysicalRouting() async {
        let before = protectedDefaults()
        await AudioRouter.shared.refreshDevices()
        XCTAssertFalse(AudioRouter.shared.enableEQRouting())
        AudioRouter.shared.disableEQRouting()
        XCTAssertFalse(AudioRouter.shared.isRoutingOwned)
        XCTAssertEqual(protectedDefaults(), before)
    }
}
