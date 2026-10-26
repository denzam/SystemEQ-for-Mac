import AppKit
import ApplicationServices
import AudioToolbox
import Combine
import CoreAudio

nonisolated struct NativeVolumeState {
    private(set) var level: Float
    private(set) var isMuted: Bool

    init(level: Float = 1, isMuted: Bool = false) {
        self.level = level.isFinite ? min(max(level, 0), 1) : 0
        self.isMuted = isMuted
    }

    var gain: Float {
        isMuted ? 0 : level * level
    }

    mutating func setLevel(_ value: Float) {
        level = value.isFinite ? min(max(value, 0), 1) : 0
        isMuted = false
    }

    mutating func handle(key: Int) {
        switch key {
        case 0: setLevel(level + 1 / 16)
        case 1: setLevel(level - 1 / 16)
        case 7: isMuted.toggle()
        default: break
        }
    }
}

nonisolated struct NativeMediaKeyEvent {
    let key: Int
    let isDown: Bool
    let isRepeat: Bool

    static func decode(_ event: NSEvent) -> Self? {
        guard event.type == .systemDefined, event.subtype.rawValue == 8 else { return nil }
        let key = (event.data1 >> 16) & 0xFFFF
        let state = (event.data1 >> 8) & 0xFF
        guard key == 0 || key == 1 || key == 7, state == 0x0A || state == 0x0B else { return nil }
        return Self(key: key, isDown: state == 0x0A, isRepeat: (event.data1 & 1) != 0)
    }
}

protocol NativeMediaKeyCapturing: AnyObject {
    var isEnabled: Bool { get }
    func start(handler: @escaping (NativeMediaKeyEvent) -> Bool) -> Bool
    func stop()
}

private final class NativeMediaKeyCapture: NativeMediaKeyCapturing {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var handler: ((NativeMediaKeyEvent) -> Bool)?

    var isEnabled: Bool {
        tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false
    }

    func start(handler: @escaping (NativeMediaKeyEvent) -> Bool) -> Bool {
        stop()
        guard AXIsProcessTrusted() else { return false }
        self.handler = handler
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1) << NSEvent.EventType.systemDefined.rawValue,
            callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let capture = Unmanaged<NativeMediaKeyCapture>.fromOpaque(context).takeUnretainedValue()
                let consumed = MainActor.assumeIsolated {
                    capture.handle(type: type, event: event)
                }
                return consumed ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            self.handler = nil
            return false
        }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            self.handler = nil
            return false
        }
        self.tap = tap
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        guard CGEvent.tapIsEnabled(tap: tap) else {
            stop()
            return false
        }
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap, AXIsProcessTrusted() {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return false
        }
        guard let keyEvent = NSEvent(cgEvent: event), let decoded = NativeMediaKeyEvent.decode(keyEvent) else {
            return false
        }
        return handler?(decoded) == true
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        handler = nil
    }

    deinit { stop() }
}

final class NativeVolumeControl: ObservableObject {
    enum KeyboardStatus: String {
        case inactive
        case permissionRequired
        case captureUnavailable
        case active
    }

    static let shared = NativeVolumeControl()

    @Published private(set) var isAvailable = false
    @Published private(set) var keyboardStatus: KeyboardStatus = .inactive
    @Published private(set) var state = NativeVolumeState()

    private let defaults: UserDefaults
    private let capture: any NativeMediaKeyCapturing
    private let isCurrentOutput: (AudioDeviceID) -> Bool
    private let isTrusted: () -> Bool
    private let retryScheduler: (@escaping () -> Void) -> AnyCancellable
    private let recordStatus: (String) -> Void
    private let hud: any NativeVolumeHUDPresenting
    private var outputID = AudioDeviceID(kAudioObjectUnknown)
    private var stateKey: String?
    private var gainChange: ((Float) -> Void)?
    private var activationObserver: NSObjectProtocol?
    private var captureGeneration: UInt64 = 0
    private var retryGeneration: UInt64 = 0
    private var retryTimer: AnyCancellable?
    private var keyDownEvents: UInt64 = 0
    private var appliedKeyActions: UInt64 = 0
    private var captureReady = false

    var keyboardEnabled: Bool {
        captureReady && keyboardStatus == .active && capture.isEnabled
    }

    init(
        defaults: UserDefaults = .standard,
        capture: (any NativeMediaKeyCapturing)? = nil,
        isCurrentOutput: @escaping (AudioDeviceID) -> Bool = NativeVolumeControl.matchesDefaultOutput,
        isTrusted: @escaping () -> Bool = AXIsProcessTrusted,
        retryScheduler: @escaping (@escaping () -> Void) -> AnyCancellable = { action in
            Timer.publish(every: 1, on: .main, in: .common).autoconnect().sink { _ in
                MainActor.assumeIsolated { action() }
            }
        },
        recordStatus: @escaping (String) -> Void = { status in
            DiagnosticEventStore.shared.record("routing.nativeVolume.keyboard", details: ["status": status])
        },
        hud: (any NativeVolumeHUDPresenting)? = nil
    ) {
        self.defaults = defaults
        self.capture = capture ?? NativeMediaKeyCapture()
        self.isCurrentOutput = isCurrentOutput
        self.isTrusted = isTrusted
        self.retryScheduler = retryScheduler
        self.recordStatus = recordStatus
        self.hud = hud ?? NativeVolumeHUD.shared
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.refreshKeyboardCapture() }
    }

    func prepare(outputID: AudioDeviceID, uid: String, needsSoftwareVolume: Bool) -> Float {
        stop()
        guard needsSoftwareVolume else { return 1 }
        self.outputID = outputID
        stateKey = "nativeVolume." + uid
        let saved = stateKey.flatMap { defaults.dictionary(forKey: $0) }
        state = NativeVolumeState(
            level: (saved?["level"] as? NSNumber)?.floatValue ?? 1,
            isMuted: saved?["muted"] as? Bool ?? false
        )
        isAvailable = true
        keyDownEvents = 0
        appliedKeyActions = 0
        return state.gain
    }

    func activate(gainChange: @escaping (Float) -> Void) {
        guard isAvailable else { return }
        retryGeneration &+= 1
        let generation = retryGeneration
        retryTimer?.cancel()
        self.gainChange = gainChange
        gainChange(state.gain)
        refreshKeyboardCapture()
        retryTimer = retryScheduler { [weak self] in
            guard let self, retryGeneration == generation else { return }
            pollKeyboardCapture()
        }
    }

    func refreshKeyboardCapture() {
        capture.stop()
        captureGeneration &+= 1
        let generation = captureGeneration
        captureReady = false
        guard isAvailable, gainChange != nil else {
            setKeyboardStatus(.inactive)
            return
        }
        guard isTrusted() else {
            setKeyboardStatus(.permissionRequired)
            return
        }
        let started = capture.start { [weak self] event in
            guard event.key == 0 || event.key == 1 || event.key == 7,
                  let self, captureGeneration == generation, isAvailable, keyboardEnabled,
                  gainChange != nil else { return false }
            if event.isDown { keyDownEvents &+= 1 }
            guard isCurrentOutput(outputID) else { return false }
            if event.isDown, event.key != 7 || !event.isRepeat {
                state.handle(key: event.key)
                publishGain()
                appliedKeyActions &+= 1
                hud.show(state: state)
            }
            return true
        }
        if started, capture.isEnabled {
            setKeyboardStatus(.active)
        } else {
            capture.stop()
            setKeyboardStatus(.captureUnavailable)
        }
    }

    func pollKeyboardCapture() {
        guard isAvailable, gainChange != nil else { return }
        if !isTrusted() {
            if keyboardStatus != .permissionRequired || capture.isEnabled { refreshKeyboardCapture() }
        } else if !keyboardEnabled || !capture.isEnabled {
            refreshKeyboardCapture()
        }
    }

    private func setKeyboardStatus(_ status: KeyboardStatus) {
        captureReady = status == .active
        guard keyboardStatus != status else { return }
        keyboardStatus = status
        recordStatus(status.rawValue)
    }

    func requestKeyboardAccess() {
        guard isAvailable else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        if !trusted,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"),
           !NSWorkspace.shared.open(url) {
            dlog("Could not open Accessibility settings for volume keys", level: .warning, category: .routing)
        }
        refreshKeyboardCapture()
    }

    func setLevel(_ level: Float) {
        guard isAvailable else { return }
        state.setLevel(level)
        publishGain()
    }

    func toggleMute() {
        guard isAvailable else { return }
        state.handle(key: 7)
        publishGain()
    }

    func stop() {
        hud.hide()
        retryGeneration &+= 1
        retryTimer?.cancel()
        retryTimer = nil
        captureGeneration &+= 1
        capture.stop()
        setKeyboardStatus(.inactive)
        isAvailable = false
        gainChange = nil
        outputID = AudioDeviceID(kAudioObjectUnknown)
        stateKey = nil
    }

    func diagnosticSummary() -> String {
        """
        Software volume available: \(isAvailable)
        Keyboard capture status: \(keyboardStatus.rawValue)
        Accessibility authorized: \(isTrusted())
        Event tap enabled: \(capture.isEnabled)
        Output is system default: \(isAvailable && isCurrentOutput(outputID))
        Volume key-down events in current run: \(keyDownEvents)
        Volume actions applied in current run: \(appliedKeyActions)
        Software volume scalar: \(String(format: "%.3f", state.level))
        Software volume muted: \(state.isMuted)
        """
    }

    private func publishGain() {
        gainChange?(state.gain)
        if let stateKey {
            defaults.set(["level": state.level, "muted": state.isMuted], forKey: stateKey)
        }
    }

    private static func writableVolume(
        _ deviceID: AudioDeviceID,
        selector: AudioObjectPropertySelector,
        element: AudioObjectPropertyElement
    ) -> Bool? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioDevicePropertyScopeOutput, mElement: element
        )
        guard AudioObjectHasProperty(deviceID, &address) else { return false }
        var writable = DarwinBoolean(false)
        guard AudioObjectIsPropertySettable(deviceID, &address, &writable) == noErr else { return nil }
        guard writable.boolValue else { return false }
        var volume: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume) == noErr,
              size == MemoryLayout<Float32>.size, volume.isFinite else { return nil }
        return true
    }

    static func needsSoftwareVolume(_ deviceID: AudioDeviceID) -> Bool {
        guard deviceID != kAudioObjectUnknown else { return false }
        for selector in [kAudioDevicePropertyVolumeScalar, kAudioHardwareServiceDeviceProperty_VirtualMainVolume] {
            guard let writable = writableVolume(
                deviceID,
                selector: selector,
                element: kAudioObjectPropertyElementMain
            ) else { return false }
            if writable { return false }
        }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr,
              size >= MemoryLayout<AudioBufferList>.size else { return false }
        let storage = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { storage.deallocate() }
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, storage) == noErr else { return false }
        let channels = UnsafeMutableAudioBufferListPointer(
            storage.assumingMemoryBound(to: AudioBufferList.self)
        ).reduce(0) { $0 + $1.mNumberChannels }
        guard channels > 0, channels <= 256 else { return false }
        for channel in 1...channels {
            guard let writable = writableVolume(
                deviceID,
                selector: kAudioDevicePropertyVolumeScalar,
                element: channel
            ) else { return false }
            if writable { return false }
        }
        return true
    }

    static func matchesDefaultOutput(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain
        )
        var current = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        return AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &current
        ) == noErr && current == deviceID
    }

    deinit {
        retryTimer?.cancel()
        capture.stop()
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
    }
}
