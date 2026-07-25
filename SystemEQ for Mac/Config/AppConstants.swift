//
//  AppConstants.swift
//  SystemEQ for Mac
//
//  Централізовані константи додатку
//

import Foundation

public enum AppConstants {
    // MARK: - URLs

    public enum URLs {
        // AutoEQ
        public static let autoEQRepo = "https://github.com/jaakkopasanen/AutoEq"
        public static let autoEQRawBase = "https://raw.githubusercontent.com/jaakkopasanen/AutoEq/master/"
        public static let autoEQIndex = "https://raw.githubusercontent.com/jaakkopasanen/AutoEq/master/results/INDEX.md"
        public static let autoEQWebApp = "https://autoeq.app/equalize"

        // BlackHole
        // ⚠️ Єдине джерело істини: оновлюй тільки BlackHole.bundledVersion нижче.
        public static let blackHoleRepo = "https://github.com/ExistentialAudio/BlackHole"
        public static let blackHoleReleases = "https://github.com/ExistentialAudio/BlackHole/releases"
        public static let blackHoleLatest = "https://github.com/ExistentialAudio/BlackHole/releases/latest"
        public static let blackHoleWebsite = "https://existential.audio/blackhole/"
        public static let blackHoleHomebrewInfo = "https://formulae.brew.sh/cask/blackhole-2ch"

        /// Прямий URL до .pkg для закріпленої версії BlackHole (official CDN).
        public static var blackHole2chPkg: String {
            "https://existential.audio/downloads/BlackHole2ch-\(BlackHole.bundledVersion).pkg"
        }

        /// Project
        public static let projectRepo = "https://github.com/denzam/SystemEQ-for-Mac"
        public static let buyMeACoffee = "https://buymeacoffee.com/denzam"

        // Local Server
        public static let localAutoEQServer = "http://127.0.0.1:5555"
        public static let localAutoEQServerAlt = "http://127.0.0.1:8000/equalize"
    }

    // MARK: - BlackHole

    public enum BlackHole {
        /// Закріплена версія BlackHole, з якою протестовано застосунок.
        /// Оновлення: запусти `Scripts/check_blackhole_updates.sh` і зміни цей рядок.
        public static let bundledVersion = "0.7.1"

        /// Мінімальна версія, яка точно працює з CoreAudioEngine.
        public static let minimumSupportedVersion = "0.5.0"

        /// Команда Homebrew для установки.
        public static let homebrewCommand = "brew install blackhole-2ch"

        /// Homebrew cask ідентифікатор.
        public static let homebrewCask = "blackhole-2ch"
    }

    // MARK: - Audio Configuration

    public enum Audio {
        // Sample Rates
        public static let preferredSampleRate: Double = 48000.0
        public static let fallbackSampleRate: Double = 44100.0

        // FFT Configuration
        public static let fftSize = 2048
        public static let maxFrames = 512
        public static let maxFramesPerSlice: UInt32 = 4096

        /// Buffer Configuration
        public static let defaultBufferSize: UInt32 = 512
    }

    // MARK: - Device Names

    public enum DeviceNames {
        // Virtual Audio Drivers
        public static let blackHole = "BlackHole"
        public static let blackHoleLowercase = "blackhole"

        /// Priority Audio Interfaces (для автовибору)
        public static let priorityDevices = [
            "scarlett",
            "focusrite",
            "universal audio",
            "apogee",
            "motu",
            "rme"
        ]
    }

    // MARK: - EQ Configuration

    public enum EQ {
        /// Default target profile for AutoEQ
        public static let defaultTarget = "JM-1 with Harman filters"

        /// Fixed band configuration
        public static let fixedBandConfig = "10_BAND_GRAPHIC_EQ"

        /// Sample rate for EQ calculations
        public static let calculationSampleRate = 48000.0
    }
}
