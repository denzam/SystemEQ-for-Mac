//
//  AudioRouter.swift
//  SystemEQ for Mac
//
//  Audio Device Management and Routing
//  Handles device enumeration, BlackHole setup, and system audio routing
//

import AppKit
import AVFoundation
import Combine
import CoreAudio
import Foundation
import SwiftUI

// MARK: - Audio Device

public struct AudioDevice: Identifiable, Equatable {
    public let id: AudioDeviceID
    public let name: String
    public let uid: String
    public let isInput: Bool
    public let isOutput: Bool

    public init(id: AudioDeviceID, name: String, uid: String, isInput: Bool, isOutput: Bool) {
        self.id = id
        self.name = name
        self.uid = uid
        self.isInput = isInput
        self.isOutput = isOutput
    }
}

// MARK: - Audio Router

public final class AudioRouter: ObservableObject {
    // MARK: - Published Properties

    @Published public var inputDevices: [AudioDevice] = []
    @Published public var outputDevices: [AudioDevice] = []

    @Published public var selectedInputDevice: AudioDevice?
    @Published public var selectedOutputDevice: AudioDevice?

    @Published public var blackHoleDetected: Bool = false

    @Published public var statusMessage: String = "Checking devices..."
    @Published public var isRoutingActive: Bool = false

    // MARK: - Private Properties

    private var originalSystemOutputDevice: AudioDevice?
    private var deviceChangeDebounceTask: Task<Void, Never>?

    /// UID of the real (non-BlackHole) system output, persisted so a crash that
    /// left the system on BlackHole can still be recovered on next launch.
    private let originalOutputUIDKey = "originalSystemOutputUID"

    /// UIDs of the devices the engine is currently routing through. A UID survives
    /// unplug/replug, an AudioDeviceID does not — so this is what we validate
    /// against whenever the device list changes.
    private var activeInputUID: String?
    private var activeOutputUID: String?

    /// Set when sleep interrupted an active routing session, so wake restores it.
    private var wasRoutingBeforeSleep = false
    private var wakeRestartTask: Task<Void, Never>?

    /// Whether we are the reason the system default output is BlackHole — true even
    /// while the engine is stopped (between sleep and the wake restart, or after a
    /// restart that failed). Quitting in that window must still restore the real
    /// output, which `CoreAudioEngine.isRunning` alone would not catch.
    public var isRoutingOwned: Bool {
        activeInputUID != nil || CoreAudioEngine.shared.isRunning
    }

    public static let shared = AudioRouter()

    // MARK: - Initialization

    private init() {
        // Setup listeners first to catch any device changes.
        // The initial device refresh is now handled asynchronously from the UI layer.
        setupDeviceChangeListener()
        setupNotificationObservers()
        setupSleepWakeObservers()
    }

    private func setupNotificationObservers() {
        // Listen for device changes from UI
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDeviceChanged),
            name: NSNotification.Name("AudioDeviceChanged"),
            object: nil
        )
    }

    @objc
    private func handleDeviceChanged(_ notification: Notification) {
        // Handle device changes if needed
        guard let userInfo = notification.userInfo else { return }

        if let inputID = userInfo["inputDeviceID"] as? AudioDeviceID,
           let outputID = userInfo["outputDeviceID"] as? AudioDeviceID {
            dlog("Audio devices changed: input=\(inputID), output=\(outputID)", category: .routing)
        }
    }

    // MARK: - Device Enumeration

    public func refreshDevices() async {
        // Perform blocking CoreAudio calls on a background thread.
        let (rawInputs, rawOutputs) = await Task.detached {
            let inputs = AudioRouter.getDevices(isInput: true)
            let outputs = AudioRouter.getDevices(isOutput: true)
            return (inputs, outputs)
        }.value

        // Update the UI and published properties on the Main Actor.
        await MainActor.run {
            // Construct AudioDevice values on the MainActor to satisfy Swift concurrency.
            self.inputDevices = rawInputs.map { info in
                AudioDevice(
                    id: info.id,
                    name: info.name,
                    uid: info.uid,
                    isInput: info.hasInput,
                    isOutput: info.hasOutput
                )
            }
            self.outputDevices = rawOutputs.map { info in
                AudioDevice(
                    id: info.id,
                    name: info.name,
                    uid: info.uid,
                    isInput: info.hasInput,
                    isOutput: info.hasOutput
                )
            }

            self.detectBlackHole()

            // Save the original system output, but only on the first run.
            if self.originalSystemOutputDevice == nil {
                self.saveCurrentSystemOutputDevice()
            }

            // Auto-select devices if they haven't been selected yet.
            if self.selectedInputDevice == nil,
               let blackHole = self.inputDevices
               .first(where: { $0.name.contains(AppConstants.DeviceNames.blackHole) }) {
                self.selectedInputDevice = blackHole
            }

            if self.selectedOutputDevice == nil {
                self.selectedOutputDevice = self.findBestPhysicalOutputDevice()
            }

            self.updateStatus()
        }
    }

    /// Internal representation used by the nonisolated CoreAudio helper.
    private struct RawDeviceInfo {
        let id: AudioDeviceID
        let name: String
        let uid: String
        let hasInput: Bool
        let hasOutput: Bool
    }

    nonisolated private static func getDevices(isInput: Bool = false, isOutput: Bool = false) -> [RawDeviceInfo] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )

        guard status == noErr else {
            errorLog("Failed to get device list size: \(status)", category: .routing)
            return []
        }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )

        guard status == noErr else {
            errorLog("Failed to get device list: \(status)", category: .routing)
            return []
        }

        return deviceIDs.compactMap { deviceID -> RawDeviceInfo? in
            guard let name = AudioRouter.getDeviceName(deviceID),
                  let uid = AudioRouter.getDeviceUID(deviceID) else {
                return nil
            }

            let hasInput = AudioRouter.hasInputStreams(deviceID)
            let hasOutput = AudioRouter.hasOutputStreams(deviceID)

            // Filter based on request
            if isInput, !hasInput {
                return nil
            }
            if isOutput, !hasOutput {
                return nil
            }

            return RawDeviceInfo(
                id: deviceID,
                name: name,
                uid: uid,
                hasInput: hasInput,
                hasOutput: hasOutput
            )
        }
    }

    // MARK: - Device Properties

    nonisolated private static func getDeviceName(_ deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var name: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>>.size)

        let status = withUnsafeMutablePointer(to: &name) { pointer in
            AudioObjectGetPropertyData(
                deviceID,
                &propertyAddress,
                0,
                nil,
                &dataSize,
                pointer
            )
        }

        guard status == noErr, let unmanagedName = name else { return nil }
        return unmanagedName.takeUnretainedValue() as String
    }

    nonisolated private static func getDeviceUID(_ deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var uid: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>>.size)

        let status = withUnsafeMutablePointer(to: &uid) { pointer in
            AudioObjectGetPropertyData(
                deviceID,
                &propertyAddress,
                0,
                nil,
                &dataSize,
                pointer
            )
        }

        guard status == noErr, let unmanagedUID = uid else { return nil }
        return unmanagedUID.takeUnretainedValue() as String
    }

    nonisolated private static func hasInputStreams(_ deviceID: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize
        )

        return status == noErr && dataSize > 0
    }

    nonisolated private static func hasOutputStreams(_ deviceID: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize
        )

        return status == noErr && dataSize > 0
    }

    // MARK: - Device Selection

    func selectInputDevice(_ device: AudioDevice) {
        selectedInputDevice = device
        dlog("Selected input: \(device.name)", category: .routing)

        // Повідомляємо про зміну пристрою через NotificationCenter
        NotificationCenter.default.post(
            name: NSNotification.Name("AudioDeviceChanged"),
            object: nil,
            userInfo: ["inputDeviceID": device.id, "outputDeviceID": selectedOutputDevice?.id as Any]
        )

        updateStatus()
    }

    func selectOutputDevice(_ device: AudioDevice) {
        selectedOutputDevice = device
        dlog("Selected output: \(device.name)", category: .routing)

        // Повідомляємо про зміну пристрою через NotificationCenter
        NotificationCenter.default.post(
            name: NSNotification.Name("AudioDeviceChanged"),
            object: nil,
            userInfo: ["inputDeviceID": selectedInputDevice?.id as Any, "outputDeviceID": device.id]
        )

        updateStatus()
    }

    func setupBlackHoleRouting() {
        guard let blackHoleInput = inputDevices
            .first(where: { $0.name.lowercased().contains(AppConstants.DeviceNames.blackHoleLowercase) }),
            let physicalOutput = findBestPhysicalOutputDevice() else {
            dlog("Cannot setup BlackHole routing - missing devices", level: .warning, category: .routing)
            return
        }

        dlog("Setting up BlackHole routing with CoreAudio...", category: .routing)

        // Setup CoreAudioEngine with BlackHole input and physical output
        CoreAudioEngine.shared.setup(
            inputDevice: blackHoleInput.id,
            outputDevice: physicalOutput.id
        )

        // Start CoreAudioEngine
        CoreAudioEngine.shared.start()

        // Ensure system output is BlackHole to avoid parallel unprocessed path to Scarlett
        setAsDefaultOutputDevice(blackHoleInput)
        dlog(
            "BlackHole routing configured: System → BlackHole → CoreAudio → \(physicalOutput.name)",
            level: .info,
            category: .routing
        )
    }

    private func findBestPhysicalOutputDevice() -> AudioDevice? {
        // Пріоритетні аудіо інтерфейси
        let priorityDevices = AppConstants.DeviceNames.priorityDevices

        // Спочатку шукаємо пріоритетні пристрої
        for priority in priorityDevices {
            if let device = outputDevices.first(where: {
                !$0.name.lowercased().contains(AppConstants.DeviceNames.blackHoleLowercase) &&
                    $0.name.lowercased().contains(priority)
            }) {
                dlog("Found priority device: \(device.name)", category: .routing)
                return device
            }
        }

        // Якщо пріоритетних немає, шукаємо будь-який USB аудіо інтерфейс
        if let usbDevice = outputDevices.first(where: {
            !$0.name.lowercased().contains(AppConstants.DeviceNames.blackHoleLowercase) &&
                ($0.name.lowercased().contains("usb") || $0.uid.lowercased().contains("usb"))
        }) {
            dlog("Found USB device: \(usbDevice.name)", category: .routing)
            return usbDevice
        }

        // Якщо USB немає, беремо перший не-BlackHole пристрій
        if let firstDevice = outputDevices
            .first(where: { !$0.name.lowercased().contains(AppConstants.DeviceNames.blackHoleLowercase) }) {
            dlog("Using first available device: \(firstDevice.name)", category: .routing)
            return firstDevice
        }

        return nil
    }

    /// Output device the engine should feed. Prefers the one we were already
    /// routing through (matched by UID, because a replug hands it a new
    /// AudioDeviceID) and only auto-picks when that device is really gone.
    private func preferredOutputDevice() -> AudioDevice? {
        if let uid = activeOutputUID,
           let previous = outputDevices.first(where: { $0.uid == uid }) {
            return previous
        }
        return findBestPhysicalOutputDevice()
    }

    /// - Parameter forceRestart: rebuild the AudioUnits even when the engine looks
    ///   like it is already running on these device IDs. Needed after sleep and
    ///   after a replug, where the IDs can match while the units are already dead.
    func enableEQRouting(forceRestart: Bool = false) {
        // Get physical output device
        guard let physicalOutput = preferredOutputDevice() else {
            errorLog("No physical output device found!", category: .routing)
            return
        }

        // Check if BlackHole is available
        guard let blackHoleDevice = inputDevices
            .first(where: { $0.name.lowercased().contains(AppConstants.DeviceNames.blackHoleLowercase) }) else {
            errorLog("BlackHole not found! Install from: \(AppConstants.URLs.blackHoleWebsite)", category: .routing)
            return
        }

        activeInputUID = blackHoleDevice.uid
        activeOutputUID = physicalOutput.uid

        // ⚡ OPTIMIZATION: Skip full restart if engine is already running with same devices
        let engine = CoreAudioEngine.shared
        if !forceRestart,
           engine.isRunning,
           engine.currentInputDeviceID == blackHoleDevice.id,
           engine.currentOutputDeviceID == physicalOutput.id {
            dlog("EQ routing already active, skipping restart", category: .routing)
            return
        }

        dlog("EQ routing setup - CORE AUDIO APPROACH", level: .info, category: .routing)
        dlog(
            "Found: BlackHole (\(blackHoleDevice.id)), Output: \(physicalOutput.name) (\(physicalOutput.id))",
            category: .routing
        )

        // Route system output to BlackHole first
        setAsDefaultOutputDevice(blackHoleDevice)

        // Setup Core Audio Engine
        dlog("Configuring Core Audio Engine...", category: .routing)

        // Stop if already running
        engine.stop()

        // Setup with new devices
        engine.setup(
            inputDevice: blackHoleDevice.id,
            outputDevice: physicalOutput.id
        )

        // Start Core Audio Engine
        engine.start()

        dlog(
            "EQ routing active: System → BlackHole → CoreAudio+EQ → \(physicalOutput.name) (~20-25ms latency)",
            level: .info,
            category: .routing
        )
    }

    private func showSetupInstructions(blackHole: AudioDevice, scarlett: AudioDevice) {
        let alert = NSAlert()
        alert.messageText = LocalizationManager.shared.localized(.eqRoutingSetupRequired)
        alert.informativeText = String(
            format: LocalizationManager.shared.localized(.eqRoutingSetupInstructions),
            scarlett.name
        )
        alert.alertStyle = .informational
        alert.addButton(withTitle: LocalizationManager.shared.localized(.openAudioMIDISetupButton))
        alert.addButton(withTitle: LocalizationManager.shared.localized(.testAudioButton))
        alert.addButton(withTitle: LocalizationManager.shared.localized(.cancel))

        let response = alert.runModal()

        switch response {
        case .alertFirstButtonReturn:
            // Відкриваємо Audio MIDI Setup
            let audioMIDIURL = URL(fileURLWithPath: "/Applications/Utilities/Audio MIDI Setup.app")
            dlog("🔧 Opening Audio MIDI Setup at: \(audioMIDIURL.path)", category: .general)

            // Метод 1: NSWorkspace.shared.open
            let success = NSWorkspace.shared.open(audioMIDIURL)
            if success {
                dlog("✅ Audio MIDI Setup opened successfully", category: .general)
            } else {
                dlog("❌ NSWorkspace failed", category: .general)

                // Метод 2: Process з /usr/bin/open
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                process.arguments = ["-a", "Audio MIDI Setup"]

                do {
                    try process.run()
                    process.waitUntilExit()
                    if process.terminationStatus == 0 {
                        dlog("✅ Audio MIDI Setup opened via /usr/bin/open", category: .general)
                    } else {
                        dlog("❌ /usr/bin/open failed with status: \(process.terminationStatus)", category: .general)
                    }
                } catch {
                    dlog("❌ Process failed: \(error)", category: .general)

                    // Метод 3: Прямий шлях до .app
                    let directProcess = Process()
                    directProcess.executableURL = audioMIDIURL
                    do {
                        try directProcess.run()
                        dlog("✅ Audio MIDI Setup opened via direct execution", category: .general)
                    } catch {
                        dlog("❌ Direct execution failed: \(error)", category: .general)
                        dlog("💡 Please manually open: Applications → Utilities → Audio MIDI Setup", category: .general)
                    }
                }
            }

        case .alertSecondButtonReturn:
            // Тестуємо аудіо
            testAudioRouting()

        default:
            break
        }
    }

    func testAudioRouting() {
        dlog("🔊 Testing audio routing...", category: .general)

        Task { @MainActor in
            // Refresh device list
            dlog("🔄 Refreshing device list...", category: .general)
            await refreshDevices()

            // Find BlackHole and a physical output
            guard let blackHoleInput = inputDevices.first(where: { $0.name.lowercased().contains("blackhole") }) else {
                dlog("❌ BlackHole not found. Please install BlackHole 2ch.", category: .general)
                return
            }
            guard let physicalOutput = findBestPhysicalOutputDevice() else {
                dlog("❌ No physical output device found.", category: .general)
                return
            }

            // Route system output to BlackHole and start CoreAudioEngine
            setAsDefaultOutputDevice(blackHoleInput)
            CoreAudioEngine.shared.setup(
                inputDevice: blackHoleInput.id,
                outputDevice: physicalOutput.id
            )
            CoreAudioEngine.shared.start()

            dlog("🎛️ Test routing configured", category: .general)
            dlog("   Audio flows: System → BlackHole → CoreAudioEngine → \(physicalOutput.name)", category: .general)
        }
    }

    // MARK: - Diagnostics: Route to Built-in Output

    func routeToBuiltInOutput() {
        dlog("🔊 Route to Built-in Output (diagnostic)", category: .general)
        Task { @MainActor in
            await refreshDevices()

            guard let blackHoleInput = inputDevices.first(where: { $0.name.lowercased().contains("blackhole") }) else {
                dlog("❌ BlackHole not found. Please install BlackHole 2ch.", category: .general)
                return
            }

            // Try common names for built-in speakers/output
            let builtInCandidates = outputDevices.filter { device in
                let n = device.name.lowercased()
                return !n
                    .contains("blackhole") &&
                    (n.contains("built-in") || n.contains("internal") || n.contains("speakers") || n
                        .contains("macbook"))
            }
            guard let builtIn = builtInCandidates.first ?? outputDevices
                .first(where: { $0.name.lowercased().contains("built-in") }) else {
                dlog("❌ Built-in output not found", category: .general)
                return
            }

            // Route system output to BlackHole, process to Built-in
            setAsDefaultOutputDevice(blackHoleInput)
            CoreAudioEngine.shared.setup(
                inputDevice: blackHoleInput.id,
                outputDevice: builtIn.id
            )
            CoreAudioEngine.shared.start()

            // Reflect selection in UI
            selectOutputDevice(builtIn)

            dlog("🎛️ Diagnostic routing configured", category: .general)
            dlog("   Audio flows: System → BlackHole → CoreAudioEngine → \(builtIn.name)", category: .general)
            dlog("   Use 'Start Test Tone' to verify output path", category: .general)
        }
    }

    func disableEQRouting() {
        dlog(
            "Disabling EQ routing, restoring to: \(originalSystemOutputDevice?.name ?? "Unknown")",
            level: .info,
            category: .routing
        )

        // Drop any pending wake restart — routing is off on purpose now.
        wakeRestartTask?.cancel()
        wakeRestartTask = nil
        wasRoutingBeforeSleep = false
        activeInputUID = nil
        activeOutputUID = nil

        // Stop CoreAudioEngine
        CoreAudioEngine.shared.stop()

        // Put devices back to the sample rate the user had before we forced 48k.
        CoreAudioEngine.shared.restoreDeviceSampleRates()

        // Restore original output
        restoreOriginalSystemOutputDevice()
    }

    func setAsDefaultOutputDevice(_ device: AudioDevice) {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID = device.id
        let dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)

        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            dataSize,
            &deviceID
        )

        if status == noErr {
            dlog("Set default output to: \(device.name)", category: .routing)

            // Verify the change actually happened
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                var checkAddress = AudioObjectPropertyAddress(
                    mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                    mScope: kAudioObjectPropertyScopeGlobal,
                    mElement: kAudioObjectPropertyElementMain
                )
                var currentDeviceID: AudioDeviceID = 0
                var size = UInt32(MemoryLayout<AudioDeviceID>.size)

                if AudioObjectGetPropertyData(
                    AudioObjectID(kAudioObjectSystemObject),
                    &checkAddress,
                    0,
                    nil,
                    &size,
                    &currentDeviceID
                ) == noErr {
                    if currentDeviceID != device.id {
                        dlog(
                            "System output did NOT switch to \(device.name) (got \(currentDeviceID), expected \(device.id))",
                            level: .warning,
                            category: .routing
                        )
                        self.showManualSetupAlert(targetDevice: device.name)
                    } else {
                        dlog("Verified: System output is now \(device.name)", category: .routing)
                    }
                }
            }
        } else {
            errorLog("Failed to set default output: \(status)", category: .routing)
            self.showManualSetupAlert(targetDevice: device.name)
        }
    }

    // MARK: - System Output Device Management

    private func saveCurrentSystemOutputDevice() {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID: AudioDeviceID = 0
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceID
        )

        guard status == noErr,
              let device = outputDevices.first(where: { $0.id == deviceID }) else { return }

        // Never save BlackHole as the "original" output. If a previous session
        // crashed while routing, the system default is already BlackHole, and
        // saving it would make restore a no-op — leaving the user with no sound.
        if device.name.lowercased().contains(AppConstants.DeviceNames.blackHoleLowercase) {
            dlog("System default is BlackHole; recovering original from persisted UID", category: .routing)
            if let savedUID = UserDefaults.standard.string(forKey: originalOutputUIDKey),
               let recovered = outputDevices.first(where: { $0.uid == savedUID }) {
                originalSystemOutputDevice = recovered
            }
            return
        }

        originalSystemOutputDevice = device
        UserDefaults.standard.set(device.uid, forKey: originalOutputUIDKey)
        dlog("Saved original system output: \(device.name)", category: .routing)
    }

    func restoreOriginalSystemOutputDevice() {
        if let originalDevice = originalSystemOutputDevice {
            dlog("Restoring original system output: \(originalDevice.name)", category: .routing)
            setAsDefaultOutputDevice(originalDevice)
            return
        }

        // Fallback: recover by persisted UID (e.g. after a crash left no in-memory value).
        if let savedUID = UserDefaults.standard.string(forKey: originalOutputUIDKey),
           let recovered = outputDevices.first(where: {
               $0.uid == savedUID &&
                   !$0.name.lowercased().contains(AppConstants.DeviceNames.blackHoleLowercase)
           }) {
            dlog("Restoring original system output by UID: \(recovered.name)", category: .routing)
            setAsDefaultOutputDevice(recovered)
            return
        }

        // Last resort: any non-BlackHole physical output so the user keeps hearing sound.
        if let physical = findBestPhysicalOutputDevice() {
            dlog(
                "No saved original; falling back to physical output: \(physical.name)",
                level: .warning,
                category: .routing
            )
            setAsDefaultOutputDevice(physical)
        } else {
            dlog(
                "No original system output device saved and no physical fallback found",
                level: .warning,
                category: .routing
            )
        }
    }

    // MARK: - BlackHole Detection

    private func detectBlackHole() {
        let wasDetected = blackHoleDetected
        blackHoleDetected = outputDevices.contains { device in
            device.name.lowercased().contains("blackhole")
        }

        // Only log when state changes
        if blackHoleDetected != wasDetected {
            if blackHoleDetected {
                dlog("BlackHole detected", category: .routing)
            } else {
                dlog("BlackHole not found", level: .warning, category: .routing)
            }
        }
    }

    // MARK: - Status Update

    private func updateStatus() {
        if blackHoleDetected, selectedInputDevice != nil, selectedOutputDevice != nil {
            statusMessage = "✅ Ready for routing"
            isRoutingActive = true
        } else if !blackHoleDetected {
            statusMessage = "⚠️ BlackHole not installed"
            isRoutingActive = false
        } else if selectedInputDevice == nil {
            statusMessage = "⚠️ Select input device"
            isRoutingActive = false
        } else if selectedOutputDevice == nil {
            statusMessage = "⚠️ Select output device"
            isRoutingActive = false
        } else {
            statusMessage = "ℹ️ Configure routing"
            isRoutingActive = false
        }
    }

    // MARK: - Device Change Listener

    private func setupDeviceChangeListener() {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let listenerBlock: AudioObjectPropertyListenerBlock = { _, _ in
            Task { @MainActor in
                let router = AudioRouter.shared
                router.deviceChangeDebounceTask?.cancel()
                router.deviceChangeDebounceTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 500_000_000) // 500ms debounce
                    guard !Task.isCancelled else { return }
                    await router.refreshDevices()
                    guard !Task.isCancelled else { return }
                    router.handleDeviceTopologyChange()
                }
            }
        }

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            DispatchQueue.main,
            listenerBlock
        )
    }

    /// Runs after every debounced device-list change. Catches the states that kill
    /// audio silently while routing is active: a device that vanished, and a device
    /// that came back under a new AudioDeviceID (the units still point at the old
    /// one, which renders as permanent silence rather than an error).
    @MainActor
    private func handleDeviceTopologyChange() {
        let engine = CoreAudioEngine.shared
        guard engine.isRunning,
              let inputUID = activeInputUID,
              let outputUID = activeOutputUID else { return }

        // BlackHole gone (driver uninstalled or reset) — nothing left to capture.
        guard let input = inputDevices.first(where: { $0.uid == inputUID }) else {
            dlog("BlackHole disappeared while routing — disabling EQ", level: .warning, category: .routing)
            disableEQRouting()
            return
        }

        guard let output = outputDevices.first(where: { $0.uid == outputUID }) else {
            // Output unplugged: forget it so preferredOutputDevice() auto-picks
            // whatever is left, then rebuild onto that device.
            activeOutputUID = nil
            guard let fallback = findBestPhysicalOutputDevice() else {
                dlog(
                    "Active output disappeared and no fallback exists — disabling EQ",
                    level: .warning,
                    category: .routing
                )
                disableEQRouting()
                return
            }
            dlog(
                "Active output disappeared — rebuilding onto \(fallback.name)",
                level: .warning,
                category: .routing
            )
            enableEQRouting(forceRestart: true)
            return
        }

        if input.id != engine.currentInputDeviceID || output.id != engine.currentOutputDeviceID {
            dlog(
                "Device IDs changed (in \(engine.currentInputDeviceID)→\(input.id), " +
                    "out \(engine.currentOutputDeviceID)→\(output.id)) — rebuilding engine",
                level: .warning,
                category: .routing
            )
            enableEQRouting(forceRestart: true)
        }
    }

    // MARK: - Sleep / Wake

    private func setupSleepWakeObservers() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            self,
            selector: #selector(handleWillSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(handleDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    @objc
    private func handleWillSleep(_ notification: Notification) {
        guard CoreAudioEngine.shared.isRunning else { return }
        wasRoutingBeforeSleep = true

        // Only the AudioUnits go down. The system default stays on BlackHole, so
        // nothing leaks out unprocessed and restoring is a plain restart.
        CoreAudioEngine.shared.stop()
        dlog("Sleep — engine stopped, routing will be restored on wake", level: .info, category: .routing)
    }

    @objc
    private func handleDidWake(_ notification: Notification) {
        guard wasRoutingBeforeSleep else { return }
        wasRoutingBeforeSleep = false

        wakeRestartTask?.cancel()
        wakeRestartTask = Task { @MainActor in
            // USB and Bluetooth outputs reappear a couple of seconds after wake,
            // often with a different AudioDeviceID, so refresh before rebuilding.
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            await self.refreshDevices()
            guard !Task.isCancelled else { return }
            dlog("Wake — restoring EQ routing", level: .info, category: .routing)
            self.enableEQRouting(forceRestart: true)
        }
    }

    // MARK: - Manual Setup Alert

    private func showManualSetupAlert(targetDevice: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = LocalizationManager.shared.localized(.manualSetupRequired)
            alert.informativeText = String(
                format: LocalizationManager.shared.localized(.manualSetupInstructions),
                targetDevice,
                targetDevice,
                targetDevice,
                targetDevice
            )
            alert.alertStyle = .informational
            alert.addButton(withTitle: LocalizationManager.shared.localized(.openSystemSettings))
            alert.addButton(withTitle: LocalizationManager.shared.localized(.openAudioMIDISetupButton))
            alert.addButton(withTitle: "OK")

            let response = alert.runModal()

            switch response {
            case .alertFirstButtonReturn:
                // Open System Settings → Sound
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.sound") {
                    NSWorkspace.shared.open(url)
                }
            case .alertSecondButtonReturn:
                // Open Audio MIDI Setup
                self.openAudioMIDISetup()
            default:
                break
            }
        }
    }

    // MARK: - External Links

    func openBlackHoleDownload() {
        if let url = URL(string: AppConstants.URLs.blackHoleReleases) {
            NSWorkspace.shared.open(url)
        }
    }

    func openAudioMIDISetup() {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Audio MIDI Setup.app")
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            if let error {
                dlog("❌ Failed to open Audio MIDI Setup: \(error.localizedDescription)", category: .general)
            }
        }
    }

    // MARK: - Multi-Output Device Management

    func createMultiOutputDevice() {
        dlog("🔧 Opening Audio MIDI Setup to set BlackHole as System Output…", category: .general)
        openAudioMIDISetup()

        // Інструкції для користувача (BlackHole-only)
        dlog("Instructions: Set BlackHole as System Output via Audio MIDI Setup", category: .routing)

        // Показуємо діалог з інструкціями BlackHole-only
        let alert = NSAlert()
        alert.messageText = LocalizationManager.shared.localized(.setBlackHoleAsSystemOutputTitle)
        alert.informativeText = LocalizationManager.shared.localized(.setBlackHoleAsSystemOutputInstructions)
        alert.alertStyle = .informational
        alert.addButton(withTitle: LocalizationManager.shared.localized(.openAudioMIDISetupButton))
        alert.addButton(withTitle: LocalizationManager.shared.localized(.testAudioButton))
        alert.addButton(withTitle: LocalizationManager.shared.localized(.cancel))

        let response = alert.runModal()

        switch response {
        case .alertFirstButtonReturn:
            openAudioMIDISetup()
        case .alertSecondButtonReturn:
            testAudioRouting()
        default:
            break
        }
    }
}
