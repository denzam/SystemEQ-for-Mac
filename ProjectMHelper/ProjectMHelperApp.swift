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
import os
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
        window?.isReleasedWhenClosed = false
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
            ipcServer = IPCServer(controller: controller, showWindow: { [weak self] in
                self?.showVisualizerWindow()
            })
        }
        ipcServer?.start()

        // Monitor parent process
        if parentPID > 0 {
            monitorParentProcess(pid: parentPID)
        }

        print("[ProjectMHelper] Started with frame: \(windowFrame)")
    }

    private func showVisualizerWindow() {
        guard let window else { return }
        if window.isMiniaturized { window.deminiaturize(nil) }
        if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(window.frame) }) {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
                // Check if parent process is still running (only terminate if process no longer exists)
                if kill(pid, 0) != 0, errno == ESRCH {
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

enum PresetWeight: String, CaseIterable, Sendable {
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

struct PresetInfo: Sendable {
    let path: String
    let name: String
    let category: String
    let weight: PresetWeight
    let fileSize: Int
    var fingerprint: String = ""
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
    private final class PlaylistCallbackContext {
        weak var controller: VisualizerController?
        var eventGeneration: UInt64 = 0
        var operationFailed = false

        init(_ controller: VisualizerController) {
            self.controller = controller
        }
    }

    private var playlistCallbackContext: PlaylistCallbackContext?
    // CADisplayLink is macOS 14+; stored as Any? so the property itself doesn't force the availability.
    // Real type is CADisplayLink — cast at use sites inside @available(macOS 14.0, *) blocks.
    private var displayLink: Any?
    private var cvDisplayLink: CVDisplayLink?

    private var currentPresetName: String = "None"
    private var presetCount: Int = 0
    private var isShuffleEnabled: Bool = true
    private var isPresetLocked: Bool = false
    private var allowsAutomaticPresetTransitions: Bool {
        isShuffleEnabled && !isPresetLocked
    }

    // Category and weight filtering
    private var allPresets: [PresetInfo] = []
    private var filteredPresets: [PresetInfo] = []
    private var availableCategories: [String] = []
    private var currentCategory: String = "All"
    private var currentWeight: PresetWeight = .all
    private var filterGeneration: UInt64 = 0
    private var performanceGeneration: UInt64 = 0
    private var performanceObservationTime: TimeInterval?
    private var performanceSampleActive = false
    private var canRecordPresetPerformance: Bool {
        guard let window = openGLView?.window else { return false }
        return window.isVisible && !window.isMiniaturized && window.occlusionState.contains(.visible)
    }
    private var performanceContext: ProjectMPresetPerformance.Context?
    private var performanceRenderer = ""
    private var performanceExcludedPaths: Set<String> = []
    private var performanceExpiration: Date?
    private var performanceObservers: [NSObjectProtocol] = []
    private var presetPerformance = ProjectMPresetPerformance(storageURL: URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library/Application Support/SystemEQ/performance_presets.json"))
    private let performanceHardware: String = {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var model = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &model, &size, nil, 0) == 0 else { return "" }
        return "\(String(cString: model)):\(ProcessInfo.processInfo.processorCount)"
    }()

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

    /// Manual quality override (scales mesh density on top of the auto profile).
    /// Lower mesh = fewer per-pixel equations = higher FPS on heavy presets.
    enum VisualQuality: String {
        case low = "Low"
        case medium = "Medium"
        case high = "High"

        var meshScale: Double {
            switch self {
            case .low: 0.5
            case .medium: 0.75
            case .high: 1.0
            }
        }

        /// Множник роздільності рендеру (фрагментні пікселі) — головне для шейдер-важких пресетів.
        var renderScale: Double {
            switch self {
            case .low: 0.5
            case .medium: 0.75
            case .high: 1.0
            }
        }
    }

    private var currentQuality: VisualQuality = .high

    // Прапор: змінити backing-розмір GL-поверхні на render-треді під замком (без крадіжки контексту).
    private var needsBackingResize = true

    // FPS measurement (updated once per second on the render thread)
    private var fpsFrameCount: Int = 0
    private var fpsWindowStart: CFTimeInterval = CACurrentMediaTime()
    private var measuredFPS: Int = 0
    // Адаптивний render-scale: дуже важкі пресети самі знижують роздільність, щоб тримати ≥30 FPS.
    // Множиться на якість користувача; перераховується раз на секунду на render-треді.
    private var adaptiveFPS = ProjectMAdaptiveFPS()

    private var currentPresetPath: String = ""

    // Broken preset blacklist — filled by preset_switch_failed callback, persisted across sessions
    private var brokenPresets: Set<String> = []
    private let brokenPresetsURL: URL = {
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
        do {
            try presetPerformance.load()
        } catch {
            dlog("Unable to read preset performance cache: \(error)", category: "presets")
        }
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification] {
            performanceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in
                self?.resetPerformanceObservation()
            })
        }
    }

    deinit {
        stopDisplayLink()
        unregisterPlaylistCallbacks()
        removePerformanceObservers()
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
        if let renderer = glGetString(GLenum(GL_RENDERER)) {
            performanceRenderer = String(cString: UnsafeRawPointer(renderer).assumingMemoryBound(to: CChar.self))
        }
        updatePerformanceContext(width: width, height: height)

        // Performance profile — mesh is the dominant CPU cost (per-pixel equation eval scales O(w*h)).
        // Apple Silicon has GL-on-Metal translation overhead; Intel integrated is fill-rate bound.
        let profile = performanceProfile
        projectm_set_window_size(handle, width, height)
        projectm_set_preset_duration(handle, 18.0) // longer = fewer shader recompiles
        projectm_set_soft_cut_duration(handle, 1.5) // shorter = less dual-render cost
        projectm_set_hard_cut_enabled(handle, false) // avoid mid-song shader compile stalls
        projectm_set_hard_cut_sensitivity(handle, 2.0)
        let (mw, mh) = scaledMesh()
        projectm_set_mesh_size(handle, mw, mh)
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

        loadBrokenPresets()

        // Set texture search paths (fixes GLD_TEXTURE_INDEX_2D unloadable warnings)
        let presetsPath = NSHomeDirectory() + "/Library/Application Support/SystemEQ/presets"
        let texturesPath = presetsPath + "/textures"
        var texturePaths: [UnsafePointer<CChar>?] = []
        texturesPath.withCString { ptr in
            texturePaths.append(ptr)
            projectm_set_texture_search_paths(handle, &texturePaths, 1)
        }

        // Create playlist (always needed; will be populated by scanPresets → reloadPlaylist)
        setupPlaylist(handle)

        // Ensure presets exist on disk; download in background on first run if empty.
        ensurePresetsAvailable(at: presetsPath) { [weak self] in
            self?.scanPresetsAsync(at: presetsPath) { [weak self] in
                self?.reloadPlaylist()
            }
        }

        // Start display link
        startDisplayLink()

        print("[ProjectMHelper] projectM initialized: \(width)x\(height)")
    }

    // MARK: - Preset Bootstrap (first-run download)

    private func ensurePresetsAvailable(at basePath: String, completion: @escaping () -> Void) {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(atPath: basePath, withIntermediateDirectories: true)

        if hasMilkPresets(at: basePath) {
            completion()
            return
        }

        let archive: ProjectMPresetArchive
        do {
            archive = try ProjectMPresetArchive(infoDictionary: Bundle.main.infoDictionary)
        } catch {
            dlog(error.localizedDescription, category: "presets")
            completion()
            return
        }

        print("[ProjectMHelper] No presets found at \(basePath) — downloading…")

        URLSession.shared.downloadTask(with: archive.url) { [weak self] tmpURL, response, error in
            guard let self else { return }
            guard let tmpURL, error == nil else {
                print("[ProjectMHelper] Preset download failed: \(error?.localizedDescription ?? "unknown")")
                DispatchQueue.main.async { completion() }
                return
            }

            do {
                try archive.validate(file: tmpURL, statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
            } catch {
                self.dlog(error.localizedDescription, category: "presets")
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

    private func dlog(_ message: String, category: String) {
        Logger(subsystem: "com.denzam.SystemEQ.ProjectMHelper", category: category)
            .error("\(message, privacy: .public)")
    }

    private func hasMilkPresets(at basePath: String) -> Bool {
        guard let enumerator = FileManager.default.enumerator(atPath: basePath) else { return false }
        while let path = enumerator.nextObject() as? String {
            if path.hasSuffix(".milk") {
                return true
            }
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

        // Skip macOS-generated metadata folders (`__MACOSX`) and dotfiles so we don't pick them as the root.
        let fm = FileManager.default
        guard let roots = try? fm.contentsOfDirectory(
            at: stagingDir, includingPropertiesForKeys: [.isDirectoryKey]
        ),
            let archiveRoot = roots.first(where: {
                let name = $0.lastPathComponent
                guard !name.hasPrefix("__"), !name.hasPrefix(".") else { return false }
                return (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            }) else {
            print("[ProjectMHelper] Extracted archive is empty")
            return
        }

        guard let entries = try? fm.contentsOfDirectory(at: archiveRoot, includingPropertiesForKeys: nil)
        else { return }
        let baseURL = URL(fileURLWithPath: basePath)
        guard entries.allSatisfy({ !fm.fileExists(atPath: baseURL.appendingPathComponent($0.lastPathComponent).path) })
        else {
            dlog("Preset installation would replace existing files; preserving them", category: "presets")
            return
        }
        for entry in entries {
            let dest = baseURL.appendingPathComponent(entry.lastPathComponent)
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

    /// Enumerates ~10k preset files and stats each one — ~hundreds of ms even on SSD,
    /// so the I/O runs on a background queue and only the property writes hop to main.
    private func scanPresetsAsync(at basePath: String, completion: @escaping () -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let fileManager = FileManager.default
            var presets: [PresetInfo] = []
            var categories = Set<String>()

            guard let enumerator = fileManager.enumerator(atPath: basePath) else {
                print("[ProjectMHelper] Failed to enumerate presets at \(basePath)")
                DispatchQueue.main.async { completion() }
                return
            }

            while let relativePath = enumerator.nextObject() as? String {
                guard relativePath.hasSuffix(".milk") else { continue }

                let fullPath = (basePath as NSString).appendingPathComponent(relativePath)

                let attrs = try? fileManager.attributesOfItem(atPath: fullPath)
                let fileSize = attrs?[.size] as? Int ?? 0
                let modified = (attrs?[.modificationDate] as? Date)?.timeIntervalSinceReferenceDate
                let fingerprint = modified.map { "\(fileSize):\($0)" } ?? ""

                let pathComponents = relativePath.components(separatedBy: "/")
                let category = pathComponents.count > 1 ? pathComponents[0] : "Uncategorized"
                categories.insert(category)

                let name = (relativePath as NSString).lastPathComponent
                    .replacingOccurrences(of: ".milk", with: "")

                presets.append(PresetInfo(
                    path: fullPath,
                    name: name,
                    category: category,
                    weight: PresetWeight.classify(fileSize: fileSize),
                    fileSize: fileSize,
                    fingerprint: fingerprint
                ))
            }

            let sortedCategories = ["All"] + categories.sorted()
            let lightCount = presets.count(where: { $0.weight == .light })
            let mediumCount = presets.count(where: { $0.weight == .medium })
            let heavyCount = presets.count(where: { $0.weight == .heavy })

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.allPresets = presets
                self.filteredPresets = presets
                self.availableCategories = sortedCategories
                if !sortedCategories.contains(self.currentCategory) {
                    self.currentCategory = "All"
                }
                print(
                    "[ProjectMHelper] Scanned \(presets.count) presets: \(lightCount) light, \(mediumCount) medium, \(heavyCount) heavy"
                )
                print("[ProjectMHelper] Categories: \(sortedCategories)")
                completion()
            }
        }
    }

    // MARK: - Broken preset blacklist

    private func loadBrokenPresets() {
        guard let data = try? Data(contentsOf: brokenPresetsURL),
              let list = try? JSONDecoder().decode([String].self, from: data) else { return }
        brokenPresets = Set(list)
        print("[ProjectMHelper] Loaded \(brokenPresets.count) blacklisted presets")
    }

    private func saveBrokenPresets() {
        guard let data = try? JSONEncoder().encode(Array(brokenPresets)) else { return }
        try? FileManager.default.createDirectory(
            at: brokenPresetsURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? data.write(to: brokenPresetsURL)
    }

    func markPresetBroken(_ path: String, reason: String) {
        guard !brokenPresets.contains(path) else { return }
        brokenPresets.insert(path)
        saveBrokenPresets()
        print("[ProjectMHelper] Blacklisted preset: \((path as NSString).lastPathComponent) — \(reason)")
    }

    private func reloadPlaylist(preserveCurrent: Bool = false) {
        guard playlistHandle != nil else { return }

        refreshPerformanceExclusions()
        filterGeneration &+= 1
        let generation = filterGeneration
        let snapshot = allPresets
        let category = currentCategory
        let weight = currentWeight
        let broken = brokenPresets
        let excluded = performanceExcludedPaths

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let filtered = snapshot.filter { preset in
                let categoryMatch = category == "All" || preset.category == category
                let weightMatch = weight == .all || preset.weight == weight
                return !broken.contains(preset.path) && !excluded.contains(preset.path) && categoryMatch && weightMatch
            }

            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.filterGeneration == generation,
                      self.playlistHandle != nil else { return }
                self.replacePlaylist(with: filtered, preserveCurrent: preserveCurrent)
                print(
                    "[ProjectMHelper] Playlist reloaded: \(self.presetCount) presets (category: \(category), weight: \(weight.rawValue))"
                )
            }
        }
    }

    // MARK: - Filter Control

    func setCategory(_ category: String) {
        guard category == "All" || availableCategories.contains(category) || allPresets.isEmpty else { return }
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

    /// Усі пресети (не лише поточна категорія) як [{name, category, index}].
    /// index == позиція в allPresets → SELECT трактується як глобальний (див. selectPreset).
    func getPresetSnapshot() -> [PresetInfo] {
        allPresets
    }

    private func setupPlaylist(_ handle: OpaquePointer) {
        guard let playlist = projectm_playlist_create(handle) else { return }
        playlistHandle = playlist
        let context = PlaylistCallbackContext(self)
        playlistCallbackContext = context
        let userData = Unmanaged.passUnretained(context).toOpaque()
        projectm_playlist_set_preset_switched_event_callback(playlist, { _, index, userData in
            guard let userData else { return }
            let context = Unmanaged<PlaylistCallbackContext>.fromOpaque(userData).takeUnretainedValue()
            context.controller?.enqueuePlaylistEvent(context, index: index, failure: nil)
        }, userData)
        projectm_playlist_set_preset_switch_failed_event_callback(playlist, { filenamePtr, messagePtr, userData in
            guard let userData, let filenamePtr else { return }
            let filename = String(cString: filenamePtr)
            let message = messagePtr.map { String(cString: $0) } ?? ""
            let context = Unmanaged<PlaylistCallbackContext>.fromOpaque(userData).takeUnretainedValue()
            context.controller?.enqueuePlaylistEvent(context, index: nil, failure: (filename, message))
        }, userData)
    }

    private func enqueuePlaylistEvent(
        _ context: PlaylistCallbackContext,
        index: UInt32?,
        failure: (String, String)?
    ) {
        guard playlistCallbackContext === context, let playlist = playlistHandle else { return }
        if failure != nil {
            context.operationFailed = true
        } else {
            guard !context.operationFailed,
                  let index,
                  index == projectm_playlist_get_position(playlist) else { return }
        }
        context.eventGeneration &+= 1
        let generation = context.eventGeneration
        DispatchQueue.main.async { [weak self, weak context] in
            guard let self, let context,
                  self.playlistCallbackContext === context,
                  self.playlistHandle != nil else { return }
            if let (path, reason) = failure {
                self.markPresetBroken(path, reason: reason)
            } else if context.eventGeneration == generation {
                self.updateCurrentPresetName()
            }
        }
    }

    private func unregisterPlaylistCallbacks() {
        if let playlist = playlistHandle {
            projectm_playlist_set_preset_switched_event_callback(playlist, nil, nil)
            projectm_playlist_set_preset_switch_failed_event_callback(playlist, nil, nil)
            projectm_playlist_connect(playlist, nil)
        }
        playlistCallbackContext = nil
    }

    private func performPresetOperation(_ operation: () -> Void) {
        playlistCallbackContext?.operationFailed = false
        operation()
    }

    func shutdown() {
        stopDisplayLink()
        unregisterPlaylistCallbacks()
        removePerformanceObservers()

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
        if let expiration = performanceExpiration, expiration <= Date() {
            performanceExpiration = nil
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.refreshPerformanceExclusions() { self.reloadPlaylist(preserveCurrent: true) }
            }
        }
        guard let handle = projectMHandle,
              let glView = openGLView,
              let context = glView.openGLContext,
              let cglContext = context.cglContextObj else { return }

        context.makeCurrentContext()
        CGLLockContext(cglContext)

        if needsBackingResize {
            needsBackingResize = false
            applyBackingResizeLocked(glView, handle, cglContext)
        }

        // Feed audio to projectM (lock-free read)
        feedAudioToProjectM()

        // Render frame
        performPresetOperation { projectm_opengl_render_frame(handle) }

        CGLFlushDrawable(cglContext)
        CGLUnlockContext(cglContext)

        // FPS counter — recompute once per second
        fpsFrameCount += 1
        let now = CACurrentMediaTime()
        let elapsed = now - fpsWindowStart
        if elapsed >= 1.0 {
            measuredFPS = Int((Double(fpsFrameCount) / elapsed).rounded())
            fpsFrameCount = 0
            fpsWindowStart = now
            if let renderer = glGetString(GLenum(GL_RENDERER)) {
                let name = String(cString: UnsafeRawPointer(renderer).assumingMemoryBound(to: CChar.self))
                if name != performanceRenderer {
                    performanceRenderer = name
                    let backing = glView.convertToBacking(glView.bounds)
                    updatePerformanceContext(width: Int(backing.width), height: Int(backing.height))
                    return
                }
            }
            adaptRenderScale()
        }
    }

    /// Тримає ≥30 FPS на дуже важких пресетах, знижуючи роздільність рендеру понад вибрану якість.
    /// Лише вниз і лише поки реально потрібно — без осциляції (інакше backing-resize мерехтить).
    /// Повна роздільність повертається при зміні пресета (resetAdaptiveScale), а не за FPS.
    private func adaptRenderScale() {
        let active = canRecordPresetPerformance
        if active != performanceSampleActive {
            resetAdaptiveScale()
            performanceSampleActive = active
        }
        let now = Date().timeIntervalSinceReferenceDate
        if let previous = performanceObservationTime, now < previous || now - previous > 5 {
            resetAdaptiveScale()
        }
        performanceObservationTime = now
        switch adaptiveFPS.observe(
            measuredFPS: measuredFPS,
            presetLocked: !allowsAutomaticPresetTransitions,
            hasPresetPath: !currentPresetPath.isEmpty
        ) {
        case .unchanged:
            return
        case .warmup:
            return
        case .reduceScale:
            needsBackingResize = true
        case .skipPreset:
            let path = currentPresetPath
            let generation = performanceGeneration
            let context = performanceContext
            guard !path.isEmpty else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.currentPresetPath == path,
                      self.performanceGeneration == generation,
                      self.performanceContext == context,
                      self.allowsAutomaticPresetTransitions,
                      self.measuredFPS < ProjectMAdaptiveFPS.targetMinFPS,
                      let playlist = self.playlistHandle else { return }
                if active, self.canRecordPresetPerformance, let context,
                   let preset = self.allPresets.first(where: { $0.path == path }), !preset.fingerprint.isEmpty {
                    do {
                        try self.presetPerformance.record(
                            path: path, fingerprint: preset.fingerprint, context: context, now: Date()
                        )
                        self.refreshPerformanceExclusions()
                        self.replacePlaylist(
                            with: self.filteredPresets.filter { !self.performanceExcludedPaths.contains($0.path) },
                            preserveCurrent: false
                        )
                        return
                    } catch {
                        dlog("Unable to save preset performance cache: \(error)", category: "presets")
                    }
                }
                self.performPresetOperation { _ = projectm_playlist_play_next(playlist, false) }
                self.updateCurrentPresetName()
            }
        }
    }

    private func resetAdaptiveScale() {
        performanceGeneration &+= 1
        performanceObservationTime = nil
        if adaptiveFPS.adaptiveScale != 1.0 {
            adaptiveFPS.reset()
            needsBackingResize = true
        } else {
            adaptiveFPS.reset()
        }
    }

    private func resetPerformanceObservation() {
        resetAdaptiveScale()
        fpsFrameCount = 0
        fpsWindowStart = CACurrentMediaTime()
        measuredFPS = 0
    }

    private func removePerformanceObservers() {
        for observer in performanceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        performanceObservers.removeAll()
    }

    private func updatePerformanceContext(width: Int, height: Int) {
        let marketing = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        let version = marketing.isEmpty || build.isEmpty ? "" : "\(marketing):\(build)"
        let context = ProjectMPresetPerformance.Context(
            hardware: performanceHardware, renderer: performanceRenderer, quality: currentQuality.rawValue,
            width: width, height: height, version: version
        )
        guard performanceContext != context else { return }
        performanceContext = context.isValid ? context : nil
        resetPerformanceObservation()
        if refreshPerformanceExclusions() { reloadPlaylist(preserveCurrent: true) }
    }

    @discardableResult
    private func refreshPerformanceExclusions() -> Bool {
        let now = Date()
        let excluded: Set<String>
        if let context = performanceContext {
            excluded = Set(allPresets.filter {
                presetPerformance.isExcluded(path: $0.path, fingerprint: $0.fingerprint, context: context, now: now)
            }.map(\.path))
            performanceExpiration = presetPerformance.nextExpiration(context: context, now: now)
        } else {
            excluded = []
            performanceExpiration = nil
        }
        let changed = excluded != performanceExcludedPaths
        performanceExcludedPaths = excluded
        return changed
    }

    private func replacePlaylist(with presets: [PresetInfo], preserveCurrent: Bool, selected: PresetInfo? = nil) {
        let presets = presets.filter { !performanceExcludedPaths.contains($0.path) }
        guard let playlist = playlistHandle else { return }
        let current = selected ?? (preserveCurrent ? allPresets.first { $0.path == currentPresetPath } : nil)
        playlistCallbackContext?.eventGeneration &+= 1
        guard populatePlaylist(with: presets) else { return }
        filteredPresets = presets
        presetCount = filteredPresets.count
        projectm_playlist_set_shuffle(playlist, isShuffleEnabled)
        if let handle = projectMHandle {
            projectm_set_preset_locked(handle, !allowsAutomaticPresetTransitions || filteredPresets.isEmpty)
        }
        if let current {
            playSelectedPreset(current)
        } else if !filteredPresets.isEmpty,
                  let position = UInt32(exactly: Int.random(in: filteredPresets.indices)) {
            performPresetOperation { _ = projectm_playlist_set_position(playlist, position, false) }
            updateCurrentPresetName()
        }
    }

    private func populatePlaylist(with presets: [PresetInfo]) -> Bool {
        guard let playlist = playlistHandle else { return false }
        projectm_playlist_clear(playlist)
        for preset in presets {
            guard projectm_playlist_add_preset(playlist, preset.path, false) else {
                dlog("Unable to rebuild preset playlist", category: "presets")
                projectm_playlist_clear(playlist)
                filteredPresets = []
                presetCount = 0
                if let handle = projectMHandle { projectm_set_preset_locked(handle, true) }
                return false
            }
        }
        return true
    }

    private func playSelectedPreset(_ target: PresetInfo) {
        guard let playlist = playlistHandle, !brokenPresets.contains(target.path) else { return }
        if let index = filteredPresets.firstIndex(where: { $0.path == target.path }),
           let position = UInt32(exactly: index) {
            performPresetOperation { _ = projectm_playlist_set_position(playlist, position, true) }
            updateCurrentPresetName()
            return
        }
        let eligible = filteredPresets
        guard populatePlaylist(with: [target] + eligible) else { return }
        performPresetOperation { _ = projectm_playlist_set_position(playlist, 0, true) }
        updateCurrentPresetName()
        let loadedPosition = projectm_playlist_get_position(playlist)
        let loadSucceeded = playlistCallbackContext?.operationFailed != true
        playlistCallbackContext?.eventGeneration &+= 1
        guard populatePlaylist(with: eligible) else { return }
        if loadSucceeded, loadedPosition > 0, Int(loadedPosition) <= filteredPresets.count {
            performPresetOperation { _ = projectm_playlist_set_position(playlist, loadedPosition - 1, false) }
            updateCurrentPresetName()
        }
    }

    // MARK: - Audio (Lock-Free)

    func addAudioSamples(_ samples: UnsafePointer<Float>, count: Int) {
        guard count > 0 else { return }
        let mask = audioBufferSize - 1
        let write = pm_atomic_load(&audioWriteIndex)
        let read = pm_atomic_load(&audioReadIndex)
        let used = Int(UInt32(bitPattern: write) &- UInt32(bitPattern: read))
        let availableCapacity = audioBufferSize - used
        guard availableCapacity > 0 else { return }

        let toWrite = min(count, availableCapacity)
        let base = Int(write)
        for i in 0..<toWrite {
            audioBuffer[(base &+ i) & mask] = samples[i]
        }
        _ = pm_atomic_fetch_add(&audioWriteIndex, Int32(toWrite))
    }

    private func feedAudioToProjectM() {
        guard let handle = projectMHandle else { return }

        // Calculate available samples (handle 32-bit wraparound via unsigned subtraction)
        let write = pm_atomic_load(&audioWriteIndex)
        let read = pm_atomic_load(&audioReadIndex)
        let available = Int(UInt32(bitPattern: write) &- UInt32(bitPattern: read))

        if available < 512 {
            return
        }

        // Stereo: ensure even count so L/R pairs stay aligned.
        // Cap at audioScratchCapacity to avoid overflow of pre-allocated buffer.
        var samplesToRead = min(available, audioScratchCapacity)
        samplesToRead &= ~1

        let mask = audioBufferSize - 1
        let base = Int(read)
        for i in 0..<samplesToRead {
            audioScratch[i] = audioBuffer[(base &+ i) & mask]
        }
        _ = pm_atomic_fetch_add(&audioReadIndex, Int32(samplesToRead))

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
        performPresetOperation { _ = projectm_playlist_play_next(playlist, false) }
        updateCurrentPresetName()
    }

    func previousPreset() {
        guard let playlist = playlistHandle, presetCount > 0 else { return }
        performPresetOperation { _ = projectm_playlist_play_previous(playlist, false) }
        updateCurrentPresetName()
    }

    func randomPreset() {
        guard let playlist = playlistHandle, !filteredPresets.isEmpty else { return }
        let randomIndex = Int.random(in: filteredPresets.indices)
        guard let position = UInt32(exactly: randomIndex) else { return }
        performPresetOperation { _ = projectm_playlist_set_position(playlist, position, true) }
        updateCurrentPresetName()
    }

    /// index — глобальна позиція в allPresets (список у UI показує всі пресети).
    /// Якщо обраний пресет поза поточним фільтром — переходимо на «All», перебудовуємо playlist,
    /// потім граємо саме його за шляхом.
    func selectPreset(at index: Int) {
        guard let playlist = playlistHandle, index >= 0, index < allPresets.count else { return }
        let target = allPresets[index]
        filterGeneration &+= 1

        let matchesFilters = (currentCategory == "All" || target.category == currentCategory)
            && (currentWeight == .all || target.weight == currentWeight)
        if filteredPresets.contains(where: { $0.path == target.path })
            || (performanceExcludedPaths.contains(target.path) && matchesFilters) {
            playSelectedPreset(target)
            return
        }

        // Не у поточному playlist → переключаємось на «All» і граємо після перебудови.
        currentCategory = "All"
        currentWeight = .all
        filterGeneration &+= 1
        let generation = filterGeneration
        let snapshot = allPresets
        let broken = brokenPresets
        let excluded = performanceExcludedPaths
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let filtered = snapshot.filter { !broken.contains($0.path) && !excluded.contains($0.path) }
            DispatchQueue.main.async {
                guard let self,
                      self.filterGeneration == generation,
                      self.playlistHandle == playlist else { return }
                self.replacePlaylist(with: filtered, preserveCurrent: false, selected: target)
            }
        }
    }

    func setShuffle(_ enabled: Bool) {
        if isShuffleEnabled != enabled { resetPerformanceObservation() }
        isShuffleEnabled = enabled
        if let playlist = playlistHandle {
            projectm_playlist_set_shuffle(playlist, enabled)
        }
        // «Авто» вимкнено → пресет не змінюється сам (блокуємо авто-зміну за таймером),
        // доки користувач не переключить вручну. Увімкнено → авто-зміна дозволена.
        if let handle = projectMHandle {
            projectm_set_preset_locked(handle, !allowsAutomaticPresetTransitions || filteredPresets.isEmpty)
        }
    }

    func setPresetLocked(_ locked: Bool) {
        if isPresetLocked != locked { resetPerformanceObservation() }
        isPresetLocked = locked
        if let handle = projectMHandle {
            projectm_set_preset_locked(handle, !allowsAutomaticPresetTransitions || filteredPresets.isEmpty)
        }
    }

    /// Mesh розмір з урахуванням auto-профілю та ручного quality-множника.
    private func scaledMesh() -> (Int, Int) {
        let scale = currentQuality.meshScale
        let w = max(8, Int((Double(performanceProfile.meshW) * scale).rounded()))
        let h = max(6, Int((Double(performanceProfile.meshH) * scale).rounded()))
        return (w, h)
    }

    func setQuality(_ quality: VisualQuality) {
        currentQuality = quality
        needsBackingResize = true
        if let glView = openGLView {
            let backing = glView.convertToBacking(glView.bounds)
            updatePerformanceContext(width: Int(backing.width), height: Int(backing.height))
        }
    }

    /// Застосовується на render-треді під CGLLockContext: змінює backing-розмір GL-поверхні
    /// (менше фрагментних пікселів → прискорює шейдер-важкі пресети) без перестворення контексту.
    private func applyBackingResizeLocked(
        _ glView: ProjectMOpenGLView,
        _ handle: OpaquePointer,
        _ cglContext: CGLContextObj
    ) {
        let backing = glView.convertToBacking(glView.bounds)
        let scale = currentQuality.renderScale * adaptiveFPS.adaptiveScale
        let w = max(64, Int((Double(backing.width) * scale).rounded()))
        let h = max(48, Int((Double(backing.height) * scale).rounded()))

        var dims: [GLint] = [GLint(w), GLint(h)]
        CGLSetParameter(cglContext, kCGLCPSurfaceBackingSize, &dims)
        CGLEnable(cglContext, kCGLCESurfaceBackingSize)

        glViewport(0, 0, GLsizei(w), GLsizei(h))
        projectm_set_window_size(handle, w, h)

        let (mw, mh) = scaledMesh()
        projectm_set_mesh_size(handle, mw, mh)
    }

    func resize(width: Int, height: Int) {
        // Не чіпаємо GL з main-треда (крадіжка контексту → чорний екран). Render-scale + новий
        // backing-розмір застосує renderFrame під замком на render-треді.
        needsBackingResize = true
        updatePerformanceContext(width: width, height: height)
    }

    private func updateCurrentPresetName() {
        guard playlistCallbackContext?.operationFailed != true,
              let playlist = playlistHandle else { return }

        let position = projectm_playlist_get_position(playlist)
        if let pathPtr = projectm_playlist_item(playlist, position) {
            let path = String(cString: pathPtr)
            projectm_free_string(pathPtr)

            let newName = (path as NSString).lastPathComponent
                .replacingOccurrences(of: ".milk", with: "")
            if path != currentPresetPath {
                currentPresetName = newName
                currentPresetPath = path
                fpsFrameCount = 0
                fpsWindowStart = CACurrentMediaTime()
                measuredFPS = 0
                resetAdaptiveScale() // новий пресет стартує з повної якості, далі адаптується під себе
            }
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
            "categories": availableCategories,
            "fps": measuredFPS
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
        guard backing.width > 0, backing.height > 0 else { return }

        // НЕ чіпаємо GL з main-треда (reshape тут на main) — лише сигналимо render-треду
        // перерахувати backing-розмір/viewport під замком.
        controller?.resize(width: Int(backing.width), height: Int(backing.height))
    }
}
