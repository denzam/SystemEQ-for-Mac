//
//  EQStartupMode.swift
//  SystemEQ for Mac
//
//  EQ Startup behavior configuration
//  Defines how the app should behave on launch regarding EQ state
//

import Foundation

/// Defines how the app should restore EQ state on launch
public enum EQStartupMode: String, CaseIterable, Codable {
    /// Restore last EQ state (preset + enabled/disabled)
    case restoreLastState = "restore_last_state"

    /// Restore preset but keep EQ disabled (user must enable manually)
    case restorePresetOnly = "restore_preset_only"

    /// Start with flat EQ and disabled (clean slate)
    case startClean = "start_clean"

    /// Display name for UI
    var displayName: String {
        switch self {
        case .restoreLastState:
            LocalizationManager.shared.localized(.eqStartupRemember)
        case .restorePresetOnly:
            LocalizationManager.shared.localized(.eqStartupRestorePreset)
        case .startClean:
            LocalizationManager.shared.localized(.eqStartupStartClean)
        }
    }

    /// Description for UI
    var description: String {
        switch self {
        case .restoreLastState:
            LocalizationManager.shared.localized(.eqStartupRememberDesc)
        case .restorePresetOnly:
            LocalizationManager.shared.localized(.eqStartupRestorePresetDesc)
        case .startClean:
            LocalizationManager.shared.localized(.eqStartupStartCleanDesc)
        }
    }

    /// Icon for UI
    var icon: String {
        switch self {
        case .restoreLastState:
            "arrow.clockwise.circle.fill"
        case .restorePresetOnly:
            "waveform.circle"
        case .startClean:
            "sparkles"
        }
    }

    /// Color for UI
    var color: String {
        switch self {
        case .restoreLastState:
            "blue"
        case .restorePresetOnly:
            "orange"
        case .startClean:
            "green"
        }
    }
}
