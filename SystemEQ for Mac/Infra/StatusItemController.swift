import AppKit
import Combine

final class StatusItemController: NSObject {
    static let shared = StatusItemController()

    private var statusItem: NSStatusItem?
    private var menu: NSMenu?

    // swiftlint:disable implicitly_unwrapped_optional
    private var statusLine: NSMenuItem!
    private var blackHoleLine: NSMenuItem!
    private var routingLine: NSMenuItem!
    private var outputLine: NSMenuItem!
    private var presetLine: NSMenuItem!
    private var presetSeparator: NSMenuItem!
    private var toggleEQItem: NSMenuItem!
    private var openMainItem: NSMenuItem!
    private var quitItem: NSMenuItem!
    // swiftlint:enable implicitly_unwrapped_optional

    private var cancellables: Set<AnyCancellable> = []
    private var presetObserver: NSObjectProtocol?
    private var languageObserver: NSObjectProtocol?

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "slider.horizontal.3",
            accessibilityDescription: "SystemEQ"
        )
        let menu = buildMenu()
        item.menu = menu
        self.statusItem = item
        self.menu = menu

        bindUpdates()
        refresh()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        statusLine = makeDisabledItem("")
        blackHoleLine = makeDisabledItem("")
        routingLine = makeDisabledItem("")
        outputLine = makeDisabledItem("")
        presetLine = makeDisabledItem("")
        presetSeparator = NSMenuItem.separator()

        menu.addItem(statusLine)
        menu.addItem(blackHoleLine)
        menu.addItem(routingLine)
        menu.addItem(outputLine)
        menu.addItem(presetSeparator)
        menu.addItem(presetLine)
        menu.addItem(NSMenuItem.separator())

        toggleEQItem = NSMenuItem(
            title: "",
            action: #selector(toggleEQ),
            keyEquivalent: "e"
        )
        toggleEQItem.target = self
        menu.addItem(toggleEQItem)

        openMainItem = NSMenuItem(
            title: "",
            action: #selector(openMain),
            keyEquivalent: "o"
        )
        openMainItem.target = self
        menu.addItem(openMainItem)

        menu.addItem(NSMenuItem.separator())

        quitItem = NSMenuItem(
            title: "",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    private func makeDisabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func bindUpdates() {
        let router = AudioRouter.shared
        let engine = AudioEngine.shared

        Publishers.Merge4(
            router.$blackHoleDetected.map { _ in () },
            router.$isRoutingActive.map { _ in () },
            router.$selectedOutputDevice.map { _ in () },
            engine.$isEnabled.map { _ in () }
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] in self?.refresh() }
        .store(in: &cancellables)

        presetObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshPresetLine()
        }

        languageObserver = NotificationCenter.default.addObserver(
            forName: .languageChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
    }

    private func refresh() {
        let loc = LocalizationManager.shared
        let router = AudioRouter.shared
        let engine = AudioEngine.shared

        if !router.blackHoleDetected {
            statusLine.title = loc.localized(.menuBlackHoleMissing)
        } else {
            statusLine.title = engine.isEnabled
                ? loc.localized(.menuEQEnabled)
                : loc.localized(.menuEQDisabled)
        }

        blackHoleLine.title = router.blackHoleDetected ? "BlackHole: ✓" : "BlackHole: ✗"
        routingLine.title = router.isRoutingActive ? "Routing: active" : "Routing: idle"

        if let out = router.selectedOutputDevice {
            outputLine.title = "Output: \(out.name)"
            outputLine.isHidden = false
        } else {
            outputLine.isHidden = true
        }

        toggleEQItem.title = engine.isEnabled
            ? loc.localized(.disableEQ)
            : loc.localized(.enableEQ)
        openMainItem.title = loc.localized(.menuMain)
        quitItem.title = loc.localized(.menuQuit)

        refreshPresetLine()
    }

    private func refreshPresetLine() {
        let name = UserDefaults.standard.string(forKey: "activePresetName") ?? ""
        if name.isEmpty {
            presetLine.isHidden = true
            presetSeparator.isHidden = true
        } else {
            presetLine.title = "Preset: \(name)"
            presetLine.isHidden = false
            presetSeparator.isHidden = false
        }
    }

    @objc
    private func toggleEQ() {
        // setEnabled already forwards to CoreAudioEngine, drives routing and
        // persists the state under "eqWasEnabled" — the extra call, the unread
        // "eqEnabled" key and the unobserved notifications were all no-ops.
        AudioEngine.shared.setEnabled(!AudioEngine.shared.isEnabled)
    }

    @objc
    private func openMain() {
        NSApp.activate(ignoringOtherApps: true)
        if let win = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }) {
            win.makeKeyAndOrderFront(nil)
        }
    }

    @objc
    private func quit() {
        NSApp.terminate(nil)
    }
}
