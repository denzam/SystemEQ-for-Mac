import AppKit
import SwiftUI

/// Custom NSView that calls callback immediately when added to window
class WindowConfigView: NSView {
    var configureCallback: (() -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            configureCallback?()
        }
    }
}

final class WindowCoordinator {
    static let shared = WindowCoordinator()
    private init() {}

    private var windows: [String: NSWindow] = [:]

    func register(window: NSWindow, id: String) {
        windows[id] = window
    }

    @discardableResult
    func focus(id: String) -> Bool {
        if let w = windows[id] {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return true
        }
        return false
    }
}

struct WindowAccessor: NSViewRepresentable {
    let id: String
    var localizationKey: LocalizedString?

    func makeNSView(context: Context) -> NSView {
        let view = WindowConfigView()
        view.configureCallback = { [self] in
            self.configureWindow(view: view, context: context)
        }
        context.coordinator.view = view

        // Try to configure immediately on next run loop (before first render)
        DispatchQueue.main.async {
            self.configureWindow(view: view, context: context)
        }

        return view
    }

    private func configureWindow(view: NSView, context: Context) {
        guard let window = view.window else { return }

        // Prevent duplicate configuration
        guard context.coordinator.window !== window else { return }

        // Set window identifier for proper title updates
        window.identifier = NSUserInterfaceItemIdentifier(rawValue: id)
        WindowCoordinator.shared.register(window: window, id: id)
        context.coordinator.window = window

        // Configure window for glass effect transparency
        window.isOpaque = false
        window.backgroundColor = NSColor.windowBackgroundColor
        window.hasShadow = true

        // Configure transparent title bar for all windows
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        window.styleMask.insert(.resizable) // Required for fullscreen support

        // Enable fullscreen support - remove transient behavior
        window.collectionBehavior = [.fullScreenPrimary, .managed]

        // Force a layout pass after style-mask changes to avoid title-bar
        // glitch, but defer it: this method runs inside viewDidMoveToWindow,
        // which is part of AppKit's active layout pass. Calling
        // layoutIfNeeded synchronously triggers NSDetectedLayoutRecursion.
        DispatchQueue.main.async { [weak window] in
            window?.layoutIfNeeded()
        }

        // Set localized title (hidden but used for accessibility)
        if let key = localizationKey {
            let localizedTitle = LocalizationManager.shared.localized(key)
            window.title = localizedTitle
        }

        // Setup observer for language changes (only once)
        if let key = localizationKey, !context.coordinator.isObserverSetup {
            context.coordinator.setupObserver(key: key, id: id)
            context.coordinator.isObserverSetup = true
        }
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Force update title on every view update to prevent SwiftUI from overwriting it
        if let window = nsView.window, let key = localizationKey {
            let localizedTitle = LocalizationManager.shared.localized(key)
            if window.title != localizedTitle {
                window.title = localizedTitle
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        private var observer: NSObjectProtocol?
        var isObserverSetup = false
        weak var window: NSWindow?
        weak var view: NSView?

        func setupObserver(key: LocalizedString, id: String) {
            // Remove existing observer if any
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }

            // Add observer for language changes
            observer = NotificationCenter.default.addObserver(
                forName: .languageChanged,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self, let window = self.window else { return }

                // Update immediately
                let localizedTitle = LocalizationManager.shared.localized(key)
                window.title = localizedTitle

                // Force update again after delay to ensure LocalizationManager has fully updated
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                    guard let self, let window = self.window else { return }
                    let updatedTitle = LocalizationManager.shared.localized(key)
                    if window.title != updatedTitle {
                        window.title = updatedTitle
                    }
                }
            }
        }

        deinit {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }
}
