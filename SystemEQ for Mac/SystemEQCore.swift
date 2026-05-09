//
//  SystemEQCore.swift
//  SystemEQ for Mac
//
//  Core imports and re-exports for the entire app
//  This file ensures all modules are accessible
//

import Accelerate
import AVFoundation
import Foundation
import SwiftUI

// This file serves as a central import point
// All core functionality should be accessible through proper imports

// MARK: - Type Aliases for Compatibility

// If you see "Cannot find type" errors, make sure:
// 1. The file containing the type is added to the Xcode target
// 2. The type is declared as public (if in a different file)
// 3. You've cleaned and rebuilt the project (Shift+Cmd+K, then Cmd+B)

// Common issues:
// - CalibrationEngine: Check Audio/CalibrationEngine.swift is in target
// - LocalizationManager: Should be in target (check LocalizationManager.swift)
// - AutoEQ types: Check AutoEQ/AutoEQModels.swift is in target

// MARK: - Build Instructions

/*
 If you're seeing compilation errors:

 1. In Xcode, select the project in the navigator
 2. Select the "SystemEQ for Mac" target
 3. Go to "Build Phases" tab
 4. Expand "Compile Sources"
 5. Make sure these files are listed:
    - CalibrationEngine.swift
    - VisualizerEngine.swift
    - LocalizationManager.swift
    - AutoEQModels.swift
    - BiquadFilter.swift
    - All other .swift files

 6. If any are missing, click "+" and add them
 7. Clean Build Folder (Shift+Cmd+K)
 8. Build (Cmd+B)
 */
