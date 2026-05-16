//
//  ProjectMHelperApp.swift
//  ProjectMHelper
//
//  Standalone helper app for projectM visualization rendering.
//  Runs in a separate process to isolate OpenGL from main SystemEQ UI.
//

import AppKit
import CoreVideo
import Foundation
import QuartzCore

@main
struct ProjectMHelperApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow?
    private var visualizerController: VisualizerController?
    private var ipcServer: IPCServer?
    private var doubleClickMonitor: Any?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Parse command line arguments
        let args = CommandLine.arguments
        var windowFrame = NSRect(x: 100, y: 100, width: 800, height: 600)
        var parentPID: Int32 = 0

        for i in 0..<args.count {
            switch args[i] {
            case "--x":
                if i + 1 < args.count, let x = Double(args[i + 1]) {
                    windowFrame.origin.x = x
                }
            case "--y":
                if i + 1 < args.count, let y = Double(args[i + 1]) {
                    windowFrame.origin.y = y
                }
            case "--width":
                if i + 1 < args.count, let w = Double(args[i + 1]) {
                    windowFrame.size.width = w
                }
            case "--height":
                if i + 1 < args.count, let h = Double(args[i + 1]) {
                    windowFrame.size.height = h
                }
            case "--parent-pid":
                if i + 1 < args.count, let pid = Int32(args[i + 1]) {
                    parentPID = pid
                }
            default:
                break
            }
        }

        // Create window with title bar for moving/resizing/fullscreen
        window = NSWindow(
            contentRect: windowFrame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window?.title = "ProjectM Visualizer"
        window?.backgroundColor = .black
        window?.isOpaque = true
        window?.hasShadow = true
        window?.level = .normal
        window?.titlebarAppearsTransparent = true
        window?.titleVisibility = .hidden
        window?.isMovableByWindowBackground = true
        window?.collectionBehavior = [.canJoinAllSpaces, .fullScreenPrimary]

        // Create visualizer controller
        visualizerController = VisualizerController()
        window?.contentView = visualizerController?.view

        // Set window delegate for fullscreen support
        window?.delegate = self

        // Add double-click gesture for fullscreen toggle
        setupDoubleClickFullscreen()
        setupFullscreenExitMonitors()

        // Show window and make it key for fullscreen support
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Start IPC server
        if let controller = visualizerController {
            ipcServer = IPCServer(controller: controller)
        }
        ipcServer?.start()

        // Monitor parent process
        if parentPID > 0 {
            monitorParentProcess(pid: parentPID)
        }

        print("[ProjectMHelper] Started with frame: \(windowFrame)")
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = doubleClickMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
        }
        visualizerController?.shutdown()
        ipcServer?.stop()
        print("[ProjectMHelper] Terminated")
    }

    // MARK: - Double-Click Fullscreen

    private var keyMonitor: Any?

    private func setupDoubleClickFullscreen() {
        // Monitor for double-clicks on the window
        doubleClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self, let window = self.window else { return event }

            // In fullscreen: single click exits
            if window.styleMask.contains(.fullScreen) {
                self.exitFullscreen()
                return nil // Consume the event
            }

            // Not in fullscreen: double-click enters
            if event.clickCount == 2 {
                if event.window == window {
                    self.enterFullscreen()
                }
            }
            return event
        }
    }

    private func setupFullscreenExitMonitors() {
        // Monitor for any key press to exit fullscreen
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window else { return event }

            if window.styleMask.contains(.fullScreen) {
                // Arrow keys change presets, don't exit
                if event.keyCode == 123 { // Left arrow
                    self.visualizerController?.previousPreset()
                    return nil
                } else if event.keyCode == 124 { // Right arrow
                    self.visualizerController?.nextPreset()
                    return nil
                }
                // Modifier-only events (Cmd/Option/Shift/Ctrl held with no
                // character) are generated when the user holds a modifier
                // before pressing an arrow — ignore them so we don't exit.
                if event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                    .isDisjoint(with: [.command, .option, .control]) == false {
                    return nil
                }
                // Auto-repeat events fire when a key is held; ignore so we
                // don't exit mid-navigation.
                if event.isARepeat {
                    return nil
                }
                // Only Escape and Return exit fullscreen explicitly.
                if event.keyCode == 53 /* Esc */ || event.keyCode == 36 /* Return */ {
                    self.exitFullscreen()
                    return nil
                }
                // Swallow any other key so a stray press doesn't kick us out.
                return nil
            }
            return event
        }
    }

    private func enterFullscreen() {
        guard let window, !window.styleMask.contains(.fullScreen) else { return }
        window.toggleFullScreen(nil)
    }

    private func exitFullscreen() {
        guard let window, window.styleMask.contains(.fullScreen) else { return }
        window.toggleFullScreen(nil)
    }

    // MARK: - NSWindowDelegate

    func windowWillEnterFullScreen(_ notification: Notification) {
        print("[ProjectMHelper] Entering fullscreen")
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        print("[ProjectMHelper] Entered fullscreen")
        // Backing pixel size — respects wantsBestResolutionOpenGLSurface automatically.
        if let contentView = window?.contentView {
            let backing = contentView.convertToBacking(contentView.bounds)
            visualizerController?.resize(width: Int(backing.width), height: Int(backing.height))
        }
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        print("[ProjectMHelper] Exited fullscreen")
        if let contentView = window?.contentView {
            let backing = contentView.convertToBacking(contentView.bounds)
            visualizerController?.resize(width: Int(backing.width), height: Int(backing.height))
        }
    }

    private func monitorParentProcess(pid: Int32) {
        DispatchQueue.global(qos: .utility).async {
            while true {
                // Check if parent process is still running
                if kill(pid, 0) != 0 {
                    // Parent died, exit helper
                    DispatchQueue.main.async {
                        NSApplication.shared.terminate(nil)
                    }
                    break
                }
                Thread.sleep(forTimeInterval: 1.0)
            }
        }
    }
}

// MARK: - Preset Weight Classification

enum PresetWeight: String, CaseIterable {
    case light = "Light"
    case medium = "Medium"
    case heavy = "Heavy"
    case all = "All"

    /// Classify by file size (bytes)
    static func classify(fileSize: Int) -> PresetWeight {
        if fileSize < 5000 {
            .light
        } else if fileSize < 15000 {
            .medium
        } else {
            .heavy
        }
    }
}

// MARK: - Preset Info

struct PresetInfo {
    let path: String
    let name: String
    let category: String
    let weight: PresetWeight
    let fileSize: Int
}

// MARK: - Performance Profile

struct PerformanceProfile {
    let name: String
    let meshW: Int
    let meshH: Int
    /// If true, clamp internal render size below Retina native to save fill rate
    let capRenderScale: Bool
    /// Max logical pixels for render target (applied when capRenderScale=true)
    let maxRenderDimension: Int

    static func autoDetect() -> PerformanceProfile {
        // Detect Apple Silicon vs Intel via `machdep.cpu.brand_string` (works on all macOS)
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var brand = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &brand, &size, nil, 0)
        let brandStr = String(cString: brand)
        let isAppleSilicon = brandStr.contains("Apple")

        // Physical core count — also a good proxy for low-end vs high-end
        var coreCount: Int32 = 0
        var coreSize = MemoryLayout<Int32>.size
        sysctlbyname("hw.physicalcpu", &coreCount, &coreSize, nil, 0)

        if isAppleSilicon, coreCount >= 8 {
            // M1 Pro/Max/Ultra, M2+, M3+ — can handle high mesh
            return PerformanceProfile(
                name: "AS-High",
                meshW: 48,
                meshH: 36,
                capRenderScale: false,
                maxRenderDimension: 4096
            )
        } else if isAppleSilicon {
            // M1/M2 base (8 cores total, but 4 perf) — medium
            return PerformanceProfile(
                name: "AS-Mid",
                meshW: 32,
                meshH: 24,
                capRenderScale: true,
                maxRenderDimension: 2560
            )
        } else {
            // Intel — always fill-rate bound on integrated GPUs, cap hard
            return PerformanceProfile(
                name: "Intel",
                meshW: 24,
                meshH: 16,
                capRenderScale: true,
                maxRenderDimension: 1920
            )
        }
    }
}

// MARK: - Visualizer Controller

class VisualizerController: NSObject {
    let view: NSView
    private var openGLView: ProjectMOpenGLView?
    private var projectMHandle: OpaquePointer?
    private var playlistHandle: OpaquePointer?
    // CADisplayLink is macOS 14+; stored as Any? so the property itself doesn't force the availability.
    // Real type is CADisplayLink — cast at use sites inside @available(macOS 14.0, *) blocks.
    private var displayLink: Any?
    private var cvDisplayLink: CVDisplayLink?

    private var currentPresetName: String = "None"
    private var presetCount: Int = 0
    private var isShuffleEnabled: Bool = true
    private var isPresetLocked: Bool = false

    // Category and weight filtering
    private var allPresets: [PresetInfo] = []
    private var filteredPresets: [PresetInfo] = []
    private var availableCategories: [String] = []
    private var currentCategory: String = "All"
    private var currentWeight: PresetWeight = .all

    // Lock-free audio ring buffer
    private let audioBufferSize = 8192
    private var audioBuffer: UnsafeMutablePointer<Float>
    private var audioWriteIndex: PMAtomicInt32 = pm_atomic_make(0)
    private var audioReadIndex: PMAtomicInt32 = pm_atomic_make(0)

    // Reusable audio scratch buffer (only touched from render thread inside feedAudioToProjectM)
    private let audioScratchCapacity = 2048
    private var audioScratch: UnsafeMutablePointer<Float>

    // Performance profile + App Nap disable token
    private var performanceProfile: PerformanceProfile = .autoDetect()
    private var activityToken: NSObjectProtocol?

    // Broken preset blacklist — filled by preset_switch_failed callback, persisted across sessions
    private var brokenPresets: Set<String> = []
    private let blacklistURL: URL = {
        let dir = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/SystemEQ")
        return dir.appendingPathComponent("broken_presets.json")
    }()

    override init() {
        // Allocate audio buffer
        audioBuffer = UnsafeMutablePointer<Float>.allocate(capacity: audioBufferSize)
        audioBuffer.initialize(repeating: 0, count: audioBufferSize)

        // Pre-allocate scratch buffer for projectm_pcm_add_float (zero alloc per frame)
        audioScratch = UnsafeMutablePointer<Float>.allocate(capacity: audioScratchCapacity)
        audioScratch.initialize(repeating: 0, count: audioScratchCapacity)

        // Create OpenGL view
        let attributes: [NSOpenGLPixelFormatAttribute] = [
            UInt32(NSOpenGLPFAOpenGLProfile), UInt32(NSOpenGLProfileVersion3_2Core),
            UInt32(NSOpenGLPFAColorSize), 24,
            UInt32(NSOpenGLPFAAlphaSize), 8,
            UInt32(NSOpenGLPFADepthSize), 24,
            UInt32(NSOpenGLPFADoubleBuffer),
            UInt32(NSOpenGLPFAAccelerated),
            0
        ]

        if let pixelFormat = NSOpenGLPixelFormat(attributes: attributes),
           let glView = ProjectMOpenGLView(frame: .zero, pixelFormat: pixelFormat) {
            openGLView = glView
            view = glView
        } else {
            view = NSView()
            view.wantsLayer = true
            view.layer?.backgroundColor = NSColor.red.cgColor
        }

        super.init()

        openGLView?.controller = self
    }

    deinit {
        stopDisplayLink()
        if let token = activityToken {
            ProcessInfo.processInfo.endActivity(token)
        }
        audioBuffer.deallocate()
        audioScratch.deallocate()
    }

    func setupProjectM(width: Int, height: Int) {
        guard let context = openGLView?.openGLContext else { return }

        context.makeCurrentContext()

        // Create projectM instance
        projectMHandle = projectm_create()
        guard let handle = projectMHandle else {
            print("[ProjectMHelper] Failed to create projectM")
            return
        }

        // Performance profile — mesh is the dominant CPU cost (per-pixel equation eval scales O(w*h)).
        // Apple Silicon has GL-on-Metal translation overhead; Intel integrated is fill-rate bound.
        let profile = performanceProfile
        projectm_set_window_size(handle, width, height)
        projectm_set_preset_duration(handle, 45.0) // longer = fewer shader recompiles
        projectm_set_soft_cut_duration(handle, 1.5) // shorter = less dual-render cost
        projectm_set_hard_cut_enabled(handle, false) // avoid mid-song shader compile stalls
        projectm_set_hard_cut_sensitivity(handle, 2.0)
        projectm_set_mesh_size(handle, profile.meshW, profile.meshH)
        projectm_set_fps(handle, 60)
        projectm_set_aspect_correction(handle, true)
        print(
            "[ProjectMHelper] Profile: \(profile.name), mesh=\(profile.meshW)x\(profile.meshH), render=\(width)x\(height)"
        )

        // Disable App Nap so 60Hz is sustained when the window is backgrounded / another app is focused
        if activityToken == nil {
            activityToken = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical],
                reason: "Realtime audio visualization"
            )
        }

        // Load blacklist + register preset-fail callback for runtime blacklisting
        loadBrokenPresets()
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        projectm_set_preset_switch_failed_event_callback(handle, { filenamePtr, messagePtr, userData in
            guard let userData, let filenamePtr else { return }
            let filename = String(cString: filenamePtr)
            let message = messagePtr.map { String(cString: $0) } ?? ""
            let controller = Unmanaged<VisualizerController>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async {
                controller.markPresetBroken(filename, reason: message)
            }
        }, selfPtr)

        // Set texture search paths (fixes GLD_TEXTURE_INDEX_2D unloadable warnings)
        let presetsPath = NSHomeDirectory() + "/Library/Application Support/SystemEQ/presets"
        let texturesPath = presetsPath + "/textures"
        var texturePaths: [UnsafePointer<CChar>?] = []
        texturesPath.withCString { ptr in
            texturePaths.append(ptr)
            projectm_set_texture_search_paths(handle, &texturePaths, 1)
        }

        // Create playlist (always needed; will be populated by scanPresets → reloadPlaylist)
        if let playlist = projectm_playlist_create(handle) {
            playlistHandle = playlist
        }

        // Ensure presets exist on disk; download in background on first run if empty.
        ensurePresetsAvailable(at: presetsPath) { [weak self] in
            guard let self else { return }
            self.scanPresets(at: presetsPath)
            self.reloadPlaylist()
        }

        // Start display link
        startDisplayLink()

        print("[ProjectMHelper] projectM initialized: \(width)x\(height)")
    }

    // MARK: - Preset Bootstrap (first-run download)

    private static let presetsArchiveURL = URL(
        string: "https://github.com/projectM-visualizer/presets-cream-of-the-crop/archive/refs/heads/master.zip"
    )!

    private func ensurePresetsAvailable(at basePath: String, completion: @escaping () -> Void) {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(atPath: basePath, withIntermediateDirectories: true)

        if hasMilkPresets(at: basePath) {
            completion()
            return
        }

        print("[ProjectMHelper] No presets found at \(basePath) — downloading…")

        URLSession.shared.downloadTask(with: VisualizerController.presetsArchiveURL) { [weak self] tmpURL, _, error in
            guard let self else { return }
            guard let tmpURL, error == nil else {
                print("[ProjectMHelper] Preset download failed: \(error?.localizedDescription ?? "unknown")")
                DispatchQueue.main.async { completion() }
                return
            }

            let zipURL = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("systemeq-presets-\(UUID().uuidString).zip")
            do {
                try FileManager.default.moveItem(at: tmpURL, to: zipURL)
            } catch {
                print("[ProjectMHelper] Failed to stage preset archive: \(error)")
                DispatchQueue.main.async { completion() }
                return
            }

            self.extractPresetArchive(zipURL: zipURL, into: basePath)
            try? FileManager.default.removeItem(at: zipURL)

            DispatchQueue.main.async { completion() }
        }.resume()
    }

    private func hasMilkPresets(at basePath: String) -> Bool {
        guard let enumerator = FileManager.default.enumerator(atPath: basePath) else { return false }
        while let path = enumerator.nextObject() as? String {
            if path.hasSuffix(".milk") { return true }
        }
        return false
    }

    private func extractPresetArchive(zipURL: URL, into basePath: String) {
        let stagingDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("systemeq-presets-extract-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: stagingDir) }

        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzip.arguments = ["-q", zipURL.path, "-d", stagingDir.path]
        do {
            try unzip.run()
            unzip.waitUntilExit()
        } catch {
            print("[ProjectMHelper] unzip failed to launch: \(error)")
            return
        }
        guard unzip.terminationStatus == 0 else {
            print("[ProjectMHelper] unzip exited with status \(unzip.terminationStatus)")
            return
        }

        // Archive root is `presets-cream-of-the-crop-master/` — move its contents into basePath.
        let fm = FileManager.default
        guard let roots = try? fm.contentsOfDirectory(at: stagingDir, includingPropertiesForKeys: nil),
              let archiveRoot = roots.first else {
            print("[ProjectMHelper] Extracted archive is empty")
            return
        }

        guard let entries = try? fm.contentsOfDirectory(at: archiveRoot, includingPropertiesForKeys: nil)
        else { return }
        let baseURL = URL(fileURLWithPath: basePath)
        for entry in entries {
            let dest = baseURL.appendingPathComponent(entry.lastPathComponent)
            try? fm.removeItem(at: dest)
            do {
                try fm.moveItem(at: entry, to: dest)
            } catch {
                print("[ProjectMHelper] Failed to install \(entry.lastPathComponent): \(error)")
            }
        }

        let installed = (try? fm.contentsOfDirectory(atPath: basePath).count) ?? 0
        print("[ProjectMHelper] Presets installed (\(installed) entries) at \(basePath)")
    }

    // MARK: - Preset Scanning

    private func scanPresets(at basePath: String) {
        let fileManager = FileManager.default
        allPresets = []
        var categories = Set<String>()

        guard let enumerator = fileManager.enumerator(atPath: basePath) else {
            print("[ProjectMHelper] Failed to enumerate presets at \(basePath)")
            return
        }

        while let relativePath = enumerator.nextObject() as? String {
            guard relativePath.hasSuffix(".milk") else { continue }

            let fullPath = (basePath as NSString).appendingPathComponent(relativePath)

            // Get file size for weight classification
            var fileSize = 0
            if let attrs = try? fileManager.attributesOfItem(atPath: fullPath),
               let size = attrs[.size] as? Int {
                fileSize = size
            }

            // Extract category from path (first directory component)
            let pathComponents = relativePath.components(separatedBy: "/")
            let category = pathComponents.count > 1 ? pathComponents[0] : "Uncategorized"
            categories.insert(category)

            // Extract preset name
            let name = (relativePath as NSString).lastPathComponent
                .replacingOccurrences(of: ".milk", with: "")

            let preset = PresetInfo(
                path: fullPath,
                name: name,
                category: category,
                weight: PresetWeight.classify(fileSize: fileSize),
                fileSize: fileSize
            )
            allPresets.append(preset)
        }

        availableCategories = ["All"] + categories.sorted()
        filteredPresets = allPresets

        // Count by weight
        let lightCount = allPresets.count(where: { $0.weight == .light })
        let mediumCount = allPresets.count(where: { $0.weight == .medium })
        let heavyCount = allPresets.count(where: { $0.weight == .heavy })

        print(
            "[ProjectMHelper] Scanned \(allPresets.count) presets: \(lightCount) light, \(mediumCount) medium, \(heavyCount) heavy"
        )
        print("[ProjectMHelper] Categories: \(availableCategories)")
    }

    // MARK: - Broken preset blacklist

    private func loadBrokenPresets() {
        guard let data = try? Data(contentsOf: blacklistURL),
              let list = try? JSONDecoder().decode([String].self, from: data) else { return }
        brokenPresets = Set(list)
        print("[ProjectMHelper] Loaded \(brokenPresets.count) blacklisted presets")
    }

    private func saveBrokenPresets() {
        guard let data = try? JSONEncoder().encode(Array(brokenPresets)) else { return }
        try? FileManager.default.createDirectory(
            at: blacklistURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? data.write(to: blacklistURL)
    }

    func markPresetBroken(_ path: String, reason: String) {
        guard !brokenPresets.contains(path) else { return }
        brokenPresets.insert(path)
        saveBrokenPresets()
        print("[ProjectMHelper] Blacklisted preset: \((path as NSString).lastPathComponent) — \(reason)")
        // Skip forward so we're not stuck on the broken one
        if let playlist = playlistHandle {
            projectm_playlist_play_next(playlist, false)
            updateCurrentPresetName()
        }
    }

    private func reloadPlaylist() {
        guard playlistHandle != nil else { return }

        let snapshot = allPresets
        let category = currentCategory
        let weight = currentWeight
        let broken = brokenPresets

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let filtered = snapshot.filter { preset in
                let categoryMatch = category == "All" || preset.category == category
                let weightMatch = weight == .all || preset.weight == weight
                return !broken.contains(preset.path) && categoryMatch && weightMatch
            }

            DispatchQueue.main.async { [weak self] in
                guard let self, let playlist = self.playlistHandle else { return }
                projectm_playlist_clear(playlist)
                for preset in filtered {
                    projectm_playlist_add_preset(playlist, preset.path, false)
                }
                self.filteredPresets = filtered
                self.presetCount = filtered.count
                if self.presetCount > 0 {
                    projectm_playlist_set_shuffle(playlist, self.isShuffleEnabled)
                    let randomIndex = Int.random(in: 0..<self.presetCount)
                    projectm_playlist_set_position(playlist, randomIndex, false)
                    self.updateCurrentPresetName()
                }
                print(
                    "[ProjectMHelper] Playlist reloaded: \(self.presetCount) presets (category: \(category), weight: \(weight.rawValue))"
                )
            }
        }
    }

    // MARK: - Filter Control

    func setCategory(_ category: String) {
        guard availableCategories.contains(category) else { return }
        currentCategory = category
        reloadPlaylist()
    }

    func setWeight(_ weight: String) {
        guard let w = PresetWeight(rawValue: weight) else { return }
        currentWeight = w
        reloadPlaylist()
    }

    func getCategories() -> [String] {
        availableCategories
    }

    func shutdown() {
        stopDisplayLink()

        if let playlist = playlistHandle {
            projectm_playlist_destroy(playlist)
            playlistHandle = nil
        }

        if let handle = projectMHandle {
            projectm_destroy(handle)
            projectMHandle = nil
        }
    }

    // MARK: - Display Link

    private func startDisplayLink() {
        // NSView.displayLink(target:selector:) requires macOS 14+. Fall back to CVDisplayLink on 13.
        if #available(macOS 14.0, *), let glView = openGLView {
            guard displayLink == nil else { return }
            let link = glView.displayLink(target: self, selector: #selector(displayLinkCallback(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 60)
            link.add(to: .main, forMode: .common)
            displayLink = link
        } else {
            guard cvDisplayLink == nil else { return }
            // CVDisplayLink is deprecated in macOS 15 but needed for macOS 13 fallback
            // (NSView.displayLink requires macOS 14+). Deprecation warnings intentionally suppressed.
            var link: CVDisplayLink?
            // swiftlint:disable deprecated_api
            _ = CVDisplayLinkCreateWithActiveCGDisplays(&link)
            guard let link else { return }
            let selfPtr = Unmanaged.passUnretained(self).toOpaque()
            _ = CVDisplayLinkSetOutputCallback(link, { _, _, _, _, _, userData in
                guard let userData else { return kCVReturnSuccess }
                let controller = Unmanaged<VisualizerController>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { controller.renderFrame() }
                return kCVReturnSuccess
            }, selfPtr)
            _ = CVDisplayLinkStart(link)
            // swiftlint:enable deprecated_api
            cvDisplayLink = link
        }
    }

    @objc
    private func displayLinkCallback(_ sender: Any) {
        renderFrame()
    }

    private func stopDisplayLink() {
        if #available(macOS 14.0, *), let link = displayLink as? CADisplayLink {
            link.invalidate()
        }
        displayLink = nil
        if let link = cvDisplayLink {
            CVDisplayLinkStop(link)
            cvDisplayLink = nil
        }
    }

    fileprivate func renderFrame() {
        guard let handle = projectMHandle,
              let glView = openGLView,
              let context = glView.openGLContext,
              let cglContext = context.cglContextObj else { return }

        context.makeCurrentContext()
        CGLLockContext(cglContext)

        // Feed audio to projectM (lock-free read)
        feedAudioToProjectM()

        // Render frame
        projectm_opengl_render_frame(handle)

        CGLFlushDrawable(cglContext)
        CGLUnlockContext(cglContext)
    }

    // MARK: - Audio (Lock-Free)

    func addAudioSamples(_ samples: UnsafePointer<Float>, count: Int) {
        // Lock-free write to ring buffer
        for i in 0..<count {
            let writeIdx = Int(pm_atomic_fetch_add(&audioWriteIndex, 1)) % audioBufferSize
            audioBuffer[writeIdx] = samples[i]
        }
    }

    private func feedAudioToProjectM() {
        guard let handle = projectMHandle else { return }

        // Calculate available samples (handle 32-bit wraparound via unsigned subtraction)
        let write = pm_atomic_load(&audioWriteIndex)
        let read = pm_atomic_load(&audioReadIndex)
        let available = Int(UInt32(bitPattern: write) &- UInt32(bitPattern: read))

        if available < 512 { return }

        // Stereo: ensure even count so L/R pairs stay aligned.
        // Cap at audioScratchCapacity to avoid overflow of pre-allocated buffer.
        var samplesToRead = min(available, audioScratchCapacity)
        samplesToRead &= ~1

        for i in 0..<samplesToRead {
            let readIdx = Int(pm_atomic_fetch_add(&audioReadIndex, 1)) % audioBufferSize
            audioScratch[i] = audioBuffer[readIdx]
        }

        projectm_pcm_add_float(handle, audioScratch, UInt32(samplesToRead / 2), PROJECTM_STEREO)
    }

    /// Caps render target to profile.maxRenderDimension on the long edge, preserving aspect ratio.
    /// On 4K Retina this halves pixel count; warp/comp shaders are fill-rate bound so the win is large.
    private func cappedRenderSize(width: Int, height: Int, profile: PerformanceProfile) -> (Int, Int) {
        guard profile.capRenderScale, width > 0, height > 0 else {
            return (width, height)
        }
        let longEdge = max(width, height)
        guard longEdge > profile.maxRenderDimension else {
            return (width, height)
        }
        let scale = Double(profile.maxRenderDimension) / Double(longEdge)
        let w = max(256, Int(Double(width) * scale))
        let h = max(256, Int(Double(height) * scale))
        return (w, h)
    }

    // MARK: - Preset Control

    func nextPreset() {
        guard let playlist = playlistHandle, presetCount > 0 else { return }
        projectm_playlist_play_next(playlist, false)
        updateCurrentPresetName()
    }

    func previousPreset() {
        guard let playlist = playlistHandle, presetCount > 0 else { return }
        projectm_playlist_play_previous(playlist, false)
        updateCurrentPresetName()
    }

    func randomPreset() {
        guard presetCount > 0 else { return }
        let randomIndex = Int.random(in: 0..<presetCount)
        selectPreset(at: randomIndex)
    }

    func selectPreset(at index: Int) {
        guard let playlist = playlistHandle, index >= 0, index < presetCount else { return }
        projectm_playlist_set_position(playlist, index, false)
        updateCurrentPresetName()
    }

    func setShuffle(_ enabled: Bool) {
        isShuffleEnabled = enabled
        if let playlist = playlistHandle {
            projectm_playlist_set_shuffle(playlist, enabled)
        }
    }

    func setPresetLocked(_ locked: Bool) {
        isPresetLocked = locked
        if let handle = projectMHandle {
            projectm_set_preset_locked(handle, locked)
        }
    }

    func resize(width: Int, height: Int) {
        guard let handle = projectMHandle,
              let context = openGLView?.openGLContext else { return }

        context.makeCurrentContext()

        // Clear framebuffer to prevent ghost image artifacts
        glClearColor(0.0, 0.0, 0.0, 1.0)
        glClear(GLbitfield(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT))

        // Viewport + projectM window must match — projectM renders directly into the default
        // framebuffer. Downscaling is done by capping the backing store resolution
        // (wantsBestResolutionOpenGLSurface on the view), not by mismatching sizes.
        glViewport(0, 0, GLsizei(width), GLsizei(height))
        projectm_set_window_size(handle, width, height)

        // Flush to ensure changes take effect
        glFlush()
        context.flushBuffer()

        print("[ProjectMHelper] Resized to \(width)x\(height)")
    }

    private func updateCurrentPresetName() {
        guard let playlist = playlistHandle else { return }

        let position = projectm_playlist_get_position(playlist)
        if let pathPtr = projectm_playlist_item(playlist, position) {
            let path = String(cString: pathPtr)
            projectm_free_string(pathPtr)

            currentPresetName = (path as NSString).lastPathComponent
                .replacingOccurrences(of: ".milk", with: "")
        }
    }

    func getStatus() -> [String: Any] {
        [
            "presetName": currentPresetName,
            "presetCount": presetCount,
            "shuffle": isShuffleEnabled,
            "locked": isPresetLocked,
            "category": currentCategory,
            "weight": currentWeight.rawValue,
            "categories": availableCategories
        ]
    }
}

// MARK: - OpenGL View

class ProjectMOpenGLView: NSOpenGLView {
    weak var controller: VisualizerController?

    override func prepareOpenGL() {
        super.prepareOpenGL()

        var swapInterval: GLint = 1
        openGLContext?.setValues(&swapInterval, for: .swapInterval)

        // On profiles that cap render scale, force 1x backing store to halve pixel count on Retina.
        // Trade-off: slight softness vs much higher framerate. Full-res is kept for Apple Silicon high-end.
        let profile = PerformanceProfile.autoDetect()
        wantsBestResolutionOpenGLSurface = !profile.capRenderScale

        let backing = convertToBacking(bounds)
        controller?.setupProjectM(width: max(Int(backing.width), 100), height: max(Int(backing.height), 100))
    }

    override func reshape() {
        super.reshape()

        let backing = convertToBacking(bounds)
        let width = Int(backing.width)
        let height = Int(backing.height)

        guard width > 0, height > 0 else { return }

        openGLContext?.makeCurrentContext()

        // Clear framebuffer to prevent ghost image artifacts during resize
        glClearColor(0.0, 0.0, 0.0, 1.0)
        glClear(GLbitfield(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT))

        glViewport(0, 0, GLsizei(width), GLsizei(height))
        controller?.resize(width: width, height: height)

        // Flush to ensure changes take effect immediately
        glFlush()
        openGLContext?.flushBuffer()
    }
}
