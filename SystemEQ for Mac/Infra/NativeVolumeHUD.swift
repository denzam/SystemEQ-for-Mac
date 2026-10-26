import AppKit
import ApplicationServices
import Combine
import SwiftUI

@MainActor
protocol NativeVolumeHUDPresenting: AnyObject {
    func show(state: NativeVolumeState)
    func hide()
}

@MainActor
final class NativeVolumeHUD: NativeVolumeHUDPresenting {
    static let shared = NativeVolumeHUD()

    private(set) var isVisible = false
    private var generation: UInt64 = 0
    private var pendingHide: AnyCancellable?
    private var panel: NativeVolumeHUDPanel?
    private let schedule: (TimeInterval, @escaping @MainActor () -> Void) -> AnyCancellable
    private let enqueue: (@escaping @MainActor () -> Void) -> Void
    private let present: ((NativeVolumeState) -> Bool)?
    private let dismiss: (() -> Void)?
    private let title: @MainActor () -> String

    init(
        schedule: @escaping (TimeInterval, @escaping @MainActor () -> Void) -> AnyCancellable = { delay, action in
            let work = DispatchWorkItem { MainActor.assumeIsolated { action() } }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
            return AnyCancellable { work.cancel() }
        },
        enqueue: @escaping (@escaping @MainActor () -> Void) -> Void = { action in
            DispatchQueue.main.async { action() }
        },
        present: ((NativeVolumeState) -> Bool)? = nil,
        dismiss: (() -> Void)? = nil,
        title: @escaping @MainActor () -> String = {
            AudioRouter.shared.selectedOutputDevice?.name ?? LocalizationManager.shared.localized(.nativeVolumeTitle)
        }
    ) {
        self.schedule = schedule
        self.enqueue = enqueue
        self.present = present
        self.dismiss = dismiss
        self.title = title
    }

    func show(state: NativeVolumeState) {
        generation &+= 1
        let token = generation
        pendingHide?.cancel()
        pendingHide = nil
        enqueue { [weak self] in
            guard let self, generation == token else { return }
            display(state: state, token: token)
        }
    }

    private func display(state: NativeVolumeState, token: UInt64) {
        guard present?(state) ?? showPanel(state: state) else {
            hide()
            return
        }
        isVisible = true
        pendingHide = schedule(1.25) { [weak self] in
            guard let self, generation == token else { return }
            pendingHide = nil
            isVisible = false
            if let dismiss {
                dismiss()
                return
            }
            guard let panel else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.2
                panel.animator().alphaValue = 0
            } completionHandler: { [weak self, weak panel] in
                MainActor.assumeIsolated {
                    guard let self, self.generation == token, !self.isVisible else { return }
                    panel?.orderOut(nil)
                }
            }
        }
    }

    func hide() {
        generation &+= 1
        pendingHide?.cancel()
        pendingHide = nil
        isVisible = false
        if let dismiss {
            dismiss()
        } else {
            panel?.alphaValue = 0
            panel?.orderOut(nil)
        }
    }

    static func frame(in visibleFrame: NSRect, anchor: NSRect? = nil, screenFrame: NSRect? = nil) -> NSRect? {
        guard visibleFrame.origin.x.isFinite, visibleFrame.origin.y.isFinite,
              visibleFrame.size.width.isFinite, visibleFrame.size.height.isFinite,
              visibleFrame.maxX.isFinite, visibleFrame.maxY.isFinite,
              visibleFrame.size.width > 32, visibleFrame.size.height > 20 else { return nil }
        let size = NSSize(width: min(290, visibleFrame.width - 32), height: min(64, visibleFrame.height - 20))
        let bounds = screenFrame ?? visibleFrame
        if let anchor, valid(anchor), valid(bounds), bounds.contains(anchor) {
            return NSRect(
                x: min(visibleFrame.maxX - size.width - 16, max(visibleFrame.minX + 16, anchor.midX - size.width / 2)),
                y: min(
                    visibleFrame.maxY - size.height - 10,
                    max(visibleFrame.minY + 10, anchor.minY - size.height - 10)
                ),
                width: size.width,
                height: size.height
            )
        }
        return NSRect(
            x: visibleFrame.maxX - size.width - 16,
            y: visibleFrame.maxY - size.height - 10,
            width: size.width,
            height: size.height
        )
    }

    static func appKitAnchor(fromAccessibility rect: NSRect, primaryScreenTop: CGFloat) -> NSRect? {
        guard valid(rect), primaryScreenTop.isFinite else { return nil }
        let result = NSRect(x: rect.minX, y: primaryScreenTop - rect.maxY, width: rect.width, height: rect.height)
        return valid(result) ? result : nil
    }

    private static func valid(_ rect: NSRect) -> Bool {
        rect.origin.x.isFinite && rect.origin.y.isFinite && rect.size.width.isFinite && rect.size.height.isFinite &&
            rect.maxX.isFinite && rect.maxY.isFinite && rect.size.width > 0 && rect.size.height > 0
    }

    private static func menuBarAnchor(on screen: NSScreen) -> NSRect? {
        guard AXIsProcessTrusted(), let primary = NSScreen.screens.first else { return nil }
        let deadline = ProcessInfo.processInfo.systemUptime + 0.12
        var fallback: NSRect?

        func attributes(_ element: AXUIElement, _ names: [CFString]) -> [AnyObject]? {
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0,
                  AXUIElementSetMessagingTimeout(element, Float(min(0.03, remaining))) == .success else { return nil }
            var values: CFArray?
            guard AXUIElementCopyMultipleAttributeValues(element, names as CFArray, [], &values) == .success,
                  let result = values as? [AnyObject], result.count == names.count else { return nil }
            return result
        }

        for identifier in ["com.apple.controlcenter", "com.apple.systemuiserver"] {
            guard let application = NSRunningApplication.runningApplications(withBundleIdentifier: identifier).first,
                  let bars = attributes(AXUIElementCreateApplication(application.processIdentifier), [
                      kAXMenuBarAttribute as CFString, kAXExtrasMenuBarAttribute as CFString
                  ]) else { continue }
            for bar in bars where CFGetTypeID(bar) == AXUIElementGetTypeID() {
                guard let children = attributes(
                    unsafeBitCast(bar, to: AXUIElement.self),
                    [kAXChildrenAttribute as CFString]
                )?
                    .first as? [AnyObject] else { continue }
                for child in children.prefix(64) where CFGetTypeID(child) == AXUIElementGetTypeID() {
                    guard let values = attributes(unsafeBitCast(child, to: AXUIElement.self), [
                        kAXIdentifierAttribute as CFString, kAXPositionAttribute as CFString,
                        kAXSizeAttribute as CFString
                    ]), let name = values[0] as? String else { continue }
                    let sound = ["com.apple.menuextra.sound", "com.apple.menuextra.volume"].contains(name.lowercased())
                    guard sound || name.lowercased() == "com.apple.menuextra.controlcenter",
                          CFGetTypeID(values[1]) == AXValueGetTypeID(),
                          CFGetTypeID(values[2]) == AXValueGetTypeID() else { continue }
                    var position = CGPoint.zero
                    var size = CGSize.zero
                    guard AXValueGetValue(unsafeBitCast(values[1], to: AXValue.self), .cgPoint, &position),
                          AXValueGetValue(unsafeBitCast(values[2], to: AXValue.self), .cgSize, &size),
                          let rect = appKitAnchor(
                              fromAccessibility: NSRect(origin: position, size: size),
                              primaryScreenTop: primary.frame.maxY
                          ), screen.frame.contains(rect) else { continue }
                    if sound { return rect }
                    fallback = rect
                }
            }
        }
        return fallback
    }

    private func showPanel(state: NativeVolumeState) -> Bool {
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) })
            ?? NSScreen.main ?? NSScreen.screens.first else { return false }
        var available = screen.visibleFrame
        let safeTop = min(available.maxY, screen.frame.maxY - screen.safeAreaInsets.top)
        available.size.height = max(0, safeTop - available.minY)
        guard let defaultFrame = Self.frame(in: available) else { return false }
        let frame: NSRect = if isVisible, let panel, panel.isVisible, panel.frame.size == defaultFrame.size,
                               available.contains(panel.frame) {
            panel.frame
        } else {
            Self.frame(in: available, anchor: Self.menuBarAnchor(on: screen), screenFrame: screen.frame)
                ?? defaultFrame
        }
        let panel = panel ?? NativeVolumeHUDPanel()
        self.panel = panel
        panel.contentView = NSHostingView(rootView: NativeVolumeHUDView(state: state, title: title()))
        panel.setFrame(frame, display: true)
        if !panel.isVisible { panel.alphaValue = 0 }
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.12
            panel.animator().alphaValue = 1
        }
        return true
    }

    deinit { pendingHide?.cancel() }
}

@MainActor
final class NativeVolumeHUDPanel: NSPanel {
    override var canBecomeKey: Bool {
        false
    }
    override var canBecomeMain: Bool {
        false
    }

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        appearance = NSAppearance(named: .darkAqua)
        hasShadow = true
        hidesOnDeactivate = false
        isFloatingPanel = true
        isReleasedWhenClosed = false
        ignoresMouseEvents = true
        isExcludedFromWindowsMenu = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        level = .statusBar
        animationBehavior = .none
    }
}

@MainActor
struct NativeVolumeHUDView: View {
    let state: NativeVolumeState
    let title: String

    private var content: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
            HStack(spacing: 8) {
                Image(systemName: state.isMuted || state.level == 0 ? "speaker.slash.fill" : "speaker.fill")
                    .frame(width: 10)
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.primary.opacity(0.16))
                        Capsule().fill(.primary)
                            .frame(width: geometry.size.width * CGFloat(state.isMuted ? 0 : state.level))
                    }
                }
                .frame(height: 3)
                Image(systemName: "speaker.wave.3.fill").frame(width: 16)
            }
            .font(.system(size: 12, weight: .medium))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.primary)
        .environment(\.controlActiveState, .active)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(state.isMuted
            ? LocalizationManager.shared.localized(.nativeVolumeMute)
            : state.level.formatted(.percent.precision(.fractionLength(0))))
        .allowsHitTesting(false)
    }

    var body: some View {
        if #available(macOS 26, *) {
            content.glassEffect(.clear, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .environment(\.colorScheme, .dark)
        } else {
            content.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .environment(\.colorScheme, .dark)
        }
    }
}
