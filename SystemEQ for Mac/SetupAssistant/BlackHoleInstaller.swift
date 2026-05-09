//
//  BlackHoleInstaller.swift
//  SystemEQ for Mac
//
//  Centralized helper for installing/updating BlackHole.
//  Supports two paths: Homebrew (if available) and direct .pkg download.
//

import AppKit
import Foundation

enum BlackHoleInstaller {
    enum Method {
        case homebrew
        case directDownload
    }

    /// Returns true if `brew` CLI is available on the user's PATH.
    static func isHomebrewAvailable() -> Bool {
        let candidates = [
            "/opt/homebrew/bin/brew",
            "/usr/local/bin/brew"
        ]
        return candidates.contains { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Preferred method based on environment.
    static func preferredMethod() -> Method {
        isHomebrewAvailable() ? .homebrew : .directDownload
    }

    /// Opens the direct .pkg download from existential.audio CDN.
    static func openDirectDownload() {
        guard let url = URL(string: AppConstants.URLs.blackHole2chPkg) else { return }
        NSWorkspace.shared.open(url)
    }

    /// Opens Terminal.app and prefills the Homebrew install command.
    /// User still needs to press Return — we never execute privileged commands silently.
    static func openHomebrewInTerminal() {
        let command = AppConstants.BlackHole.homebrewCommand
        let script = """
        tell application "Terminal"
            activate
            do script "\(command)"
        end tell
        """
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }

    /// Opens Homebrew cask page in browser (fallback for users without Terminal access).
    static func openHomebrewInfoPage() {
        guard let url = URL(string: AppConstants.URLs.blackHoleHomebrewInfo) else { return }
        NSWorkspace.shared.open(url)
    }
}
