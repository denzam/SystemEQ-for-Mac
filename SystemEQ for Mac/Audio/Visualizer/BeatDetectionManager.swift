//
//  BeatDetectionManager.swift
//  SystemEQ for Mac
//
//  MilkDrop-style beat detection for auto-changing visualizations
//

import Foundation
import QuartzCore

// MARK: - Beat Detection Mode

enum BeatDetectionMode: String, CaseIterable, Identifiable {
    case off = "Off"
    case hardcut1 = "Bass Reactive (Fast)"
    case hardcut2 = "Treble Reactive (Medium)"
    case hardcut3 = "Treble Reactive (Slow)"
    case hardcut4 = "Treble Reactive (Very Slow)"
    case hardcut5 = "Treble Reactive (Ultra Slow)"
    case hardcut6 = "Bass Reactive + Flash"

    var id: String {
        rawValue
    }

    var description: String {
        switch self {
        case .off:
            "Manual control only"
        case .hardcut1:
            "Changes on strong bass (>1.5), 0.2s delay"
        case .hardcut2:
            "Changes on treble peaks (>2.9), 0.5s delay"
        case .hardcut3:
            "Changes on treble peaks (>2.9), 1s delay"
        case .hardcut4:
            "Changes on treble peaks (>2.9), 3s delay or extreme treble (>8)"
        case .hardcut5:
            "Changes on treble peaks (>2.9), 5s delay"
        case .hardcut6:
            "Changes on strong bass (>1.5), 0.2s delay + white flash on extreme bass (>4.9)"
        }
    }
}

// MARK: - Beat Detection Manager

final class BeatDetectionManager {
    var mode: BeatDetectionMode = .off
    private var lastChangeTime: TimeInterval = 0

    /// Check if visualization should change based on beat detection
    /// - Parameters:
    ///   - bass: Current bass level (0-1+)
    ///   - treble: Current treble level (0-1+)
    ///   - currentTime: Current time in seconds
    /// - Returns: True if should change visualization
    func checkBeatDetection(bass: Float, treble: Float, currentTime: TimeInterval) -> Bool {
        let timeSinceChange = currentTime - lastChangeTime

        switch mode {
        case .off:
            return false

        case .hardcut1:
            // Bass reactive (fast) - bass > 1.5, delay 0.2s
            if bass > 1.5, timeSinceChange > 0.2 {
                lastChangeTime = currentTime
                return true
            }

        case .hardcut2:
            // Treble reactive (medium) - treble > 2.9, delay 0.5s
            if treble > 2.9, timeSinceChange > 0.5 {
                lastChangeTime = currentTime
                return true
            }

        case .hardcut3:
            // Treble reactive (slow) - treble > 2.9, delay 1s
            if treble > 2.9, timeSinceChange > 1.0 {
                lastChangeTime = currentTime
                return true
            }

        case .hardcut4:
            // Treble reactive (very slow) - treble > 2.9, delay 3s OR extreme treble > 8
            if (treble > 2.9 && timeSinceChange > 3.0) || treble > 8.0 {
                lastChangeTime = currentTime
                return true
            }

        case .hardcut5:
            // Treble reactive (ultra slow) - treble > 2.9, delay 5s
            if treble > 2.9, timeSinceChange > 5.0 {
                lastChangeTime = currentTime
                return true
            }

        case .hardcut6:
            if bass > 1.5, timeSinceChange > 0.2 {
                lastChangeTime = currentTime
                return true
            }
        }

        return false
    }

    /// Reset the timer (useful when manually changing visualization)
    func resetTimer() {
        lastChangeTime = CACurrentMediaTime()
    }
}
