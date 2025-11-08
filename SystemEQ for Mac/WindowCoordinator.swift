import SwiftUI
import AppKit

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

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                WindowCoordinator.shared.register(window: window, id: id)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
