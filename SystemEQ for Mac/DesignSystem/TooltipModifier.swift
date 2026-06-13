import AppKit
import SwiftUI

// MARK: - Native Tooltip

/// Нативний macOS tooltip (системна жовта плашка) з затримкою при наведенні.
/// Використання: `.tooltip("повний текст")`
extension View {
    func tooltip(_ text: String) -> some View {
        overlay(TooltipView(text: text))
    }

    /// Версія для опційного тексту — нічого не показує якщо nil/порожньо.
    func tooltip(_ text: String?) -> some View {
        overlay(Group {
            if let text, !text.isEmpty {
                TooltipView(text: text)
            }
        })
    }
}

private struct TooltipView: NSViewRepresentable {
    let text: String

    func makeNSView(context _: Context) -> NSView {
        let view = PassthroughTooltipView()
        view.toolTip = text
        return view
    }

    func updateNSView(_ nsView: NSView, context _: Context) {
        nsView.toolTip = text
    }
}

/// Overlay-перехоплює лише hover для toolTip, але пропускає кліки до SwiftUI під ним.
private final class PassthroughTooltipView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
