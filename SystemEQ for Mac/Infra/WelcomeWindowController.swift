import AppKit
import SwiftUI

final class WelcomeWindowController: NSWindowController, NSWindowDelegate {
    static let shared = WelcomeWindowController()

    private var hostingController: NSHostingController<AnyView>?
    private var isPresentedBinding: Bool = false

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 800),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = ""
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showWelcome() {
        guard let window else { return }

        let binding = Binding<Bool>(
            get: { [weak self] in self?.isPresentedBinding ?? false },
            set: { [weak self] newValue in
                self?.isPresentedBinding = newValue
                if !newValue {
                    DispatchQueue.main.async { [weak self] in
                        self?.close()
                    }
                }
            }
        )
        isPresentedBinding = true

        let root = WelcomeScreen(isPresented: binding)
            .environmentObject(LocalizationManager.shared)
            .environmentObject(AudioRouter.shared)

        let host = NSHostingController(rootView: AnyView(root))
        hostingController = host
        window.contentViewController = host
        window.setContentSize(NSSize(width: 640, height: 800))

        let targetScreen = NSScreen.main ?? NSScreen.screens.first
        if let screen = targetScreen {
            let visible = screen.visibleFrame
            let size = window.frame.size
            let origin = NSPoint(
                x: visible.midX - size.width / 2,
                y: visible.midY - size.height / 2
            )
            window.setFrameOrigin(origin)
        } else {
            window.center()
        }

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.level = .floating
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak window] in
            window?.level = .normal
        }
    }

    func windowWillClose(_ notification: Notification) {
        UserDefaults.standard.set(true, forKey: "hasCompletedSetup")
        hostingController = nil
    }
}
