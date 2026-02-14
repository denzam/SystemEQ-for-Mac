//
//  WindowTitleManager.swift
//  SystemEQ for Mac
//
//  Dynamic window title localization
//

import AppKit
import Foundation
import SwiftUI

// MARK: - Window Title Manager

class WindowTitleManager {
    static let shared = WindowTitleManager()

    private init() {}

    /// Update window title dynamically
    func updateWindowTitle(id: String, key: LocalizedString) {
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == id }) {
            let newTitle = LocalizationManager.shared.localized(key)
            window.title = newTitle
        }
    }

    /// Setup observer for language changes
    func setupObserver() {
        NotificationCenter.default.addObserver(
            forName: .languageChanged,
            object: nil,
            queue: .main
        ) { _ in
            // Update with slight delay to ensure LocalizationManager has updated
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.updateAllWindowTitles()
            }
        }
    }

    /// Update all known window titles (public for manual triggering)
    func updateAllWindowTitles() {
        // Update all windows
        for window in NSApp.windows {
            guard let id = window.identifier?.rawValue else {
                continue
            }

            if let key = self.getKeyForWindowId(id) {
                let newTitle = LocalizationManager.shared.localized(key)
                window.title = newTitle
            }
        }
    }

    /// Get localization key for window ID
    private func getKeyForWindowId(_ id: String) -> LocalizedString? {
        switch id {
        case "main": .mainWindowTitle
        case FeatureID.equalizer.rawValue: .equalizer
        case FeatureID.calibration.rawValue: .calibration
        case FeatureID.subjectiveRoomTuning.rawValue: .subjectiveRoomTuning
        case FeatureID.resonanceFinder.rawValue: .resonanceFinder
        case FeatureID.autoeq.rawValue: .autoeqPresets
        case FeatureID.personalized.rawValue: .personalized
        case FeatureID.routing.rawValue: .routing
        case FeatureID.settings.rawValue: .settingsTitle
        case FeatureID.visualizer.rawValue: .visualizer
        default: nil
        }
    }
}

// MARK: - SwiftUI View Modifier

struct DynamicWindowTitle: ViewModifier {
    let id: String
    let key: LocalizedString
    @ObservedObject private var localization = LocalizationManager.shared

    func body(content: Content) -> some View {
        content
            .background(WindowTitleUpdater(id: id, key: key, currentLanguage: localization.currentLanguage))
    }
}

/// Helper view that updates window title when language changes
private struct WindowTitleUpdater: NSViewRepresentable {
    let id: String
    let key: LocalizedString
    let currentLanguage: AppLanguage

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        updateTitle()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // This gets called when currentLanguage changes
        updateTitle()
    }

    private func updateTitle() {
        DispatchQueue.main.async {
            // Find window by identifier and update its title
            if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == id }) {
                let newTitle = LocalizationManager.shared.localized(key)
                window.title = newTitle
            }
        }
    }
}

extension View {
    func dynamicWindowTitle(id: String, key: LocalizedString) -> some View {
        modifier(DynamicWindowTitle(id: id, key: key))
    }
}
