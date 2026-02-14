//
//  MediaKeyMonitor.swift
//  SystemEQ for Mac
//
//  Media key monitoring for volume control
//  Intercepts F10/F11/F12 keys for mute, volume down, and volume up
//  Requires Accessibility permission for system-wide key capture
//

import AppKit
import Foundation

final class MediaKeyMonitor {
    static let shared = MediaKeyMonitor()

    private var globalMonitor: Any?
    private var localMonitor: Any?

    // NX key types (from IOKit/hidsystem/ev_keymap.h)
    private let NX_KEYTYPE_SOUND_UP: Int = 0
    private let NX_KEYTYPE_SOUND_DOWN: Int = 1
    private let NX_KEYTYPE_MUTE: Int = 7

    private let stepDb: Float = 2.0

    private init() {}

    func start() {
        guard globalMonitor == nil else { return }

        // Global monitor for systemDefined events
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .systemDefined) { [weak self] event in
            self?.handleSystemDefined(event: event)
        }

        // Local monitor as a fallback when app is key window
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .systemDefined) { [weak self] event in
            _ = self?.handleSystemDefined(event: event)
            return event
        }
        dlog("MediaKey monitor started", level: .info, category: .audio)
    }

    func stop() {
        if let gm = globalMonitor { NSEvent.removeMonitor(gm); globalMonitor = nil }
        if let lm = localMonitor { NSEvent.removeMonitor(lm); localMonitor = nil }
        dlog("MediaKey monitor stopped", level: .info, category: .audio)
    }

    @discardableResult
    private func handleSystemDefined(event: NSEvent) -> Bool {
        guard event.type == .systemDefined, event.subtype.rawValue == 8 else { return false }

        let data1 = event.data1
        let keyCode = (data1 & 0xFFFF_0000) >> 16
        let keyFlags = (data1 & 0x0000_FFFF)
        // 0xA = keyDown, 0xB = keyUp (empirical)
        let keyState = (keyFlags & 0xFF00) >> 8
        guard keyState == 0x0A else { return false }

        let engine = CoreAudioEngine.shared
        switch keyCode {
        case NX_KEYTYPE_MUTE:
            engine.setMuted(!engine.muted)
            persistMainGain(engine.mainGainDb)
            return true
        case NX_KEYTYPE_SOUND_UP:
            engine.setMuted(false)
            engine.setMainGainDb(engine.mainGainDb + stepDb)
            persistMainGain(engine.mainGainDb)
            return true
        case NX_KEYTYPE_SOUND_DOWN:
            engine.setMuted(false)
            engine.setMainGainDb(engine.mainGainDb - stepDb)
            persistMainGain(engine.mainGainDb)
            return true
        default:
            return false
        }
    }

    private func persistMainGain(_ gainDb: Float) {
        UserDefaults.standard.set(Double(gainDb), forKey: "outputGain")
    }
}
