import AppKit
import SwiftUI

struct InfoPopoverButton<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        _InfoPopoverAnchor(popoverContent: AnyView(content))
    }
}

private struct _InfoPopoverAnchor: NSViewRepresentable {
    let popoverContent: AnyView

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSButton, context: Context) -> CGSize? {
        CGSize(width: 28, height: 28)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton()
        let config = NSImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        button.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)?
            .withSymbolConfiguration(config)

        button.bezelStyle = .inline
        button.isBordered = false
        button.contentTintColor = .secondaryLabelColor
        button.target = context.coordinator
        button.action = #selector(Coordinator.toggle(_:))
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) {
        context.coordinator.content = popoverContent
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(content: popoverContent)
    }

    final class Coordinator: NSObject, NSPopoverDelegate {
        var content: AnyView
        private var popover: NSPopover?

        init(content: AnyView) {
            self.content = content
        }

        @objc func toggle(_ sender: NSButton) {
            if let popover, popover.isShown {
                popover.close()
                return
            }
            let p = NSPopover()
            p.behavior = .transient
            p.animates = true
            p.delegate = self
            let hostingView = NSHostingView(rootView:
                content
                    .padding(20)
                    .frame(minWidth: 320, maxWidth: 420)
                    .fixedSize(horizontal: false, vertical: true)
            )
            let fittingSize = hostingView.fittingSize
            p.contentSize = fittingSize
            p.contentViewController = NSViewController()
            p.contentViewController?.view = hostingView
            p.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
            self.popover = p
            observeScroll(from: sender)
        }

        private var scrollObserver: Any?

        private func observeScroll(from view: NSView) {
            var v: NSView? = view
            while v != nil {
                if let scrollView = v as? NSScrollView {
                    scrollObserver = NotificationCenter.default.addObserver(
                        forName: NSScrollView.didLiveScrollNotification,
                        object: scrollView,
                        queue: .main
                    ) { [weak self] _ in
                        self?.popover?.close()
                    }
                    return
                }
                v = v?.superview
            }
        }

        func popoverDidClose(_ notification: Notification) {
            if let scrollObserver {
                NotificationCenter.default.removeObserver(scrollObserver)
                self.scrollObserver = nil
            }
        }
    }
}
