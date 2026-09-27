//
//  LocalizationManager.swift
//  SystemEQ for Mac
//
//  Refactored Language Management - Clean Architecture
//

import Combine
import Foundation

// MARK: - App Language

public enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case italian = "it"
    case ukrainian = "uk"

    public var id: String {
        rawValue
    }

    public var displayName: String {
        switch self {
        case .english: "English"
        case .italian: "Italiano"
        case .ukrainian: "Українська"
        }
    }

    public var flag: String {
        switch self {
        case .english: "🇬🇧"
        case .italian: "🇮🇹"
        case .ukrainian: "🇺🇦"
        }
    }
}

// MARK: - Localization Keys

public enum LocalizedString: String, CaseIterable {
    // Main Window
    case mainWindowTitle
    case mainSubtitle
    case calibration
    case autoeqPresets
    case personalized
    case routing
    case settings
    case visualizer

    // Feature Subtitles
    case featureCalibrationSubtitle
    case featureAutoEQSubtitle
    case featureRoutingSubtitle
    case featureSettingsSubtitle
    case featureVisualizerSubtitle

    // Settings
    case settingsTitle
    case language
    case languageDesc
    case general
    case appUpdates
    case appUpdatesDesc
    case appCurrentVersion
    case checkAppUpdates
    case appUpdateChecking
    case appUpToDate
    case appUpdateAvailable
    case appUpdateOpenRelease
    case appUpdateCheckFailed
    case audioBackend
    case audioBackendDesc
    case audioBackendAutomatic
    case audioBackendNative
    case audioBackendBlackHole
    case launchAtLogin
    case showMenuBarIcon
    case hideDockIcon
    case hideDockIconHelp
    case autoSwitchPresetPerDevice
    case autoSwitchPresetPerDeviceHelp
    case links
    case settingsHeaderSubtitle
    case diagnostics
    case diagnosticsDesc
    case exportDiagnostics
    case diagnosticsExported
    case diagnosticsExportFailed
    case diagnosticsPrivacy
    case revealDiagnostics
    case shareDiagnostics

    // Links
    case linkGitHub
    case linkAutoEQ
    case linkBlackHole
    case linkBuyMeACoffee

    // Routing
    case routingTitle
    case routingDesc
    case systemOutput
    case systemOutputDesc
    case enableEQ
    case disableEQ
    case testTone
    case stopTone
    case audioLevels
    case input
    case output
    case devices
    case status
    case blackHole
    case inputDevice
    case outputDevice
    case installed
    case notInstalled
    case notConfigured
    case download
    case refresh
    case openAudioMIDISetup

    // Equalizer
    case eqShort
    case bandMode
    case reset
    case autoPreamp
    case preamp
    case preampSafetyWarning
    case outputBoost
    case outputBoostDescription
    case limiterActivityDescription
    case bands10
    case bands31
    case cancel
    case save
    case close
    case active
    case profile
    case frequencyHz
    case dB
    case add
    case unlock

    // Welcome
    case welcomeTitle
    case welcomeSubtitle
    case welcomeDesc
    case chooseLanguage

    // Driver Setup
    case driverTitle
    case driverDesc
    case driverFound
    case driverNotFound
    case downloadDriver
    case driverInstructions

    // Privacy
    case privacyTitle
    case privacyDesc
    case privacyPoint1
    case privacyPoint2
    case privacyPoint3
    case privacyPoint4
    case grantPermission
    case permissionGranted

    // Accessibility
    case accessInstructions

    // Buttons
    case back
    case next
    case getStarted

    // Menu Bar
    case menuMain
    case menuEQEnabled
    case menuEQDisabled
    case menuBlackHoleMissing
    case menuQuit

    // AutoEQ
    case autoEQTitle
    case autoEQQuickImport
    case autoEQBandMode
    case autoEQLoad
    case autoEQImport
    case autoEQPreamp
    case autoEQApplyToEQ
    case autoEQEQOn
    case autoEQEQOff
    case autoEQBassBoost
    case searchHeadphonesModel
    case quickImportHelp
    case autoEQImportFile
    case autoEQImportFileHelp
    case autoEQImportFileError
    case autoEQSaveToFavorites
    case removeFromFavorites
    case addToFavorites
    case indexUpdated
    case applyBandsCount
    case indexToday
    case indexYesterday
    case indexDaysAgo
    case indexWeeksAgo
    case indexMonthsAgo
    case updatingIndex
    case buildingIndex
    case httpError

    // Visualizer
    case visualizerTitle

    // EQ Startup Behavior
    case eqStartupRemember
    case eqStartupRestorePreset
    case eqStartupStartClean
    case eqStartupRememberDesc
    case eqStartupRestorePresetDesc
    case eqStartupStartCleanDesc
    case eqStartupBehaviorTitle
    case eqStartupBehaviorDesc

    // EQ Database
    case eqDatabase
    case databaseVersion
    case databaseHeadphones
    case databasePresets
    case databaseSize
    case checkForUpdates
    case downloadUpdate

    // Personalized Calibration
    case personalizedHearingProfile
    case personalizedDesc
    case personalizedSubtitle
    case premium
    case unlockPersonalizedCalibration
    case unlockForPrice
    case selectTestType
    case yourProfiles
    case adjustUntilEquallyLoud
    case quieter
    case louder
    case startCalibration
    case unlockPersonalizedHearingProfile
    case nameYourProfile
    case highPrecision
    case smartLearning
    case universal
    case oneTimePurchase
    case professionalGradeCalibration
    case price

    // Subjective Room Tuning (renamed from Room Calibration)
    case subjectiveRoomTuning
    case subjectiveRoomTuningDesc
    case subjectiveRoomTuningDisclaimer
    case subjectiveRoomTuningDisclaimerTitle

    // Resonance Finder (Sine Sweep tool)
    case resonanceFinder
    case resonanceFinderDesc
    case resonanceFinderSubtitle
    case resonanceStep1
    case resonanceStep2
    case resonanceStep3
    case resonanceNote
    case startSweep
    case stopSweep
    case commonProblemFrequencies
    case playSweepHint

    // Setup Assistant
    case setupRequired
    case systemDiagnostics
    case checkingYourSystem
    case installBlackHole
    case usedByThousands
    case easyToUninstall
    case canBeRemovedAnytime
    case configureSystemAudio
    case testAudioRouting
    case systemeqReady

    // Common UI
    case freeOpenSource
    case mitLicense
    case safeTrusted
    case installationSteps
    case setBlackHoleAsSystemOutput
    case currentSystemOutput
    case configurationSteps
    case verifyAudioRouting
    case troubleshooting
    case setupComplete

    // Calibration
    case calibration31BandsWarning
    case calibration31BandsFinalWarning
    case calibrationTitle
    case calibrationSubtitle
    case equalLoudnessCalibration
    case calibrationDescription

    // BlackHole Setup
    case systemeqRequiresBlackHole
    case blackHoleFreeOpenSource
    case whatIsBlackHole

    // UI Elements
    case setupNow
    case blackHoleNotInstalledShort

    // Room Calibration
    case findRoomResonances
    case applyNotchFilters
    case testWithMusic
    case currentFrequency
    case sweepInProgress
    case sweepSpeed
    case markResonance
    case quickTestCommon
    case manualFrequencyTest
    case testSpecificFrequencies
    case frequency
    case notchFilters
    case abTest
    case addResonance
    case severity
    case mild
    case moderate
    case severe
    case extreme
    case gain
    case saveProfile
    case profileName
    case saveCalibrationProfile
    case compareOriginalVsFiltered
    case detectedResonances
    case noResonancesDetected
    case playFrequency
    case appliedNotchFilters
    case noNotchFiltersApplied
    case addFilter
    case abComparison
    case gainMatching
    case gainMatchingDesc
    case alternatingOriginalFiltered
    case howToUse
    case howToUseStep1
    case howToUseStep2
    case howToUseStep3
    case howToUseStep4
    case clearAll
    case useResonanceFinderHint
    case startABTest
    case stopABTest
    case userDetectedResonance
    case quickTest
    case standardTest
    case extendedTest
    case quickTestDesc
    case standardTestDesc
    case extendedTestDesc
    case adaptsToHearing
    case extendedFrequencyRange
    case improvesOverTime
    case worksWithAnyHeadphones
    case exampleProfileName
    case start

    // Personalized Calibration
    case tooQuiet
    case justRight
    case tooLoud
    case sessions
    case complete

    // CalibrationView - Additional keys
    case equalLoudness
    case profiles
    case abCompare
    case chooseCalibrationMode
    case chooseCalibrationPrecision
    case bands10Time
    case bands31Time
    case recommended
    case advanced
    case forPerfectionists
    case step1SetReference
    case step1SetReferenceDesc
    case step1SetReferenceNote
    case referenceFrequency
    case volumeLevel
    case quiet
    case loud
    case playReference
    case stopReference
    case listenCarefully
    case howToSetupCorrectly
    case sitInUsualPlace
    case closeEyesForFocus
    case volumeShouldBeComfortable
    case rememberThisVolume
    case continueCalibration
    case step2AdjustFrequencies
    case step2AdjustFrequenciesDesc
    case currentFrequencyLabel
    case adjustToReferenceVolume
    case tipCloseEyes
    case levelCorrection
    case quieter2
    case louder2
    case testingFrequency
    case testSignalType
    case pinkNoise
    case pureTone
    case stopTest
    case testFrequency
    case compareAlternating
    case stopComparison
    case alternatingPattern
    case howToAdjustCorrectly
    case pressTestFrequency
    case moveSliderRealtime
    case pressStopWhenDone
    case useCompareForAB
    case progress
    case progressOf
    case previous
    case backToReference
    case nextFrequency
    case saveProfileButton
    case howToApplyCalibration
    case saveCalibrationProfileStep
    case saveCalibrationProfileStepDesc
    case activateProfileHere
    case activateProfileHereDesc
    case enableEQInMainWindow
    case enableEQInMainWindowDesc
    case tipCalibrationWorksOnlyWithEQ
    case noCalibrationProfiles
    case noCalibrationProfilesDesc
    case startCalibrationButton
    case active2
    case activate
    case abProfileComparison
    case profileA
    case profileB
    case compareWithCleanSound
    case compareWithCleanSoundDesc
    case cleanSound
    case warning31Bands
    case warning31BandsButton1
    case warning31BandsButton2
    case warning31BandsFinal
    case warning31BandsFinalButton1
    case warning31BandsFinalButton2
    case deleteProfile2
    case deleteProfileMessage
    case eq

    // VisualizerView
    case visualizerStyleColorsSubtitle
    case waveform

    // CalibrationView - Additional hardcoded strings
    case calibrationCompensateHeadphones
    case calibrationImportantLimitations
    case calibrationWhatWillImprove
    case calibrationMidHighBalance
    case calibrationHearingCompensation
    case calibrationHeadphoneCorrection
    case calibrationLessFatigue
    case calibrationWhatWontFix
    case calibrationDriverLimitations
    case calibrationMethodPrincipleTitle
    case calibrationMethodPrincipleDesc
    case calibrationPreparation
    case calibrationPreparationDesc
    case calibrationReference1000
    case calibrationReference1000Desc
    case calibrationAdjustFrequencies
    case calibrationAdjustFrequenciesDesc
    case calibrationVerification
    case calibrationVerificationDesc
    case calibrationProTips
    case calibrationProTip1
    case calibrationProTip2
    case calibrationProTip3
    case calibrationProTip4
    case calibrationProTip5

    // AutoEQView - Additional hardcoded strings
    case autoEQTypeModelName
    case autoEQFavoritesTitle
    case autoEQFavoritesLink
    case autoEQFavoritesEmpty
    case autoEQMappedPreviewTitle

    // AudioRouter - Alert messages
    case eqRoutingSetupRequired
    case eqRoutingSetupInstructions
    case openAudioMIDISetupButton
    case testAudioButton
    case manualSetupRequired
    case manualSetupInstructions
    case openSystemSettings
    case setBlackHoleAsSystemOutputTitle
    case setBlackHoleAsSystemOutputInstructions
    case blackHoleRequiredForRouting

    // Visualizer (ProjectM)
    case visualizerInSeparateWindow
    case dragProjectMWindowHint
    case launchMilkDrop
    case presetCategoryHelp
    case presetWeightHelp
    case qualityLow
    case qualityMedium
    case qualityHigh
    case visualizerQualityHelp
    case vizFavoriteHelp
    case vizPresetListHelp
    case vizSearchPresets
    case vizShowFavoritesHelp
    case previousPresetHelp
    case nextPresetHelp
    case randomPresetHelp
    case autoLabel
    case autoPresetsHelp
    case lockLabel
    case lockPresetHelp

    // Resonance / Room Tuning
    case automaticSweep
    case sweepInstructions
    case quickFrequencySelect
    case playTone
    case stopPlayback
    case sliderFrequencyHint

    // Add Resonance Sheet
    case whatIsThis
    case resonanceExplanation
    case resonanceStrength
    case resonanceStrengthDesc
    case severityMild
    case severityMildDesc
    case severityModerate
    case severityModerateDesc
    case severitySevere
    case severitySevereDesc
    case severityExtreme
    case severityExtremeDesc

    // Setup Assistant
    case runSetupAssistant
    case launchAtLoginHelp

    /// SubjectiveRoomTuningView tabs
    case tuningTab

    // Calibration Activation Alert
    case calibrationActivatedTitle
    case calibrationActivatedMessage

    // AutoEQ Setup Prompt

    // Glass Design Section (Settings)
    case glassDesignTitle
    case glassDesignDesc

    // Calibration Mode Selector
    case calibrationModeClean
    case calibrationModeCombined
    case calibrationModeCleanDesc
    case calibrationModeCombinedDesc

    // Database Version Check
    case dbUpToDate
    case dbUpdateAvailable
    case dbCheckFailed
    case dbVersionUnavailable

    // Accessibility
    case equalizerCurve
    case equalizerFlat
}

// MARK: - Localization Data Structure

private enum LocalizationData {
    // Use thread-safe lazy initialization
    private static let _queue = DispatchQueue(label: "localization.data", attributes: .concurrent)
    private static var _translations: [LocalizedString: [AppLanguage: String]]?

    static var translations: [LocalizedString: [AppLanguage: String]] {
        _queue.sync {
            if let cached = _translations {
                return cached
            }

            var dict: [LocalizedString: [AppLanguage: String]] = [:]
            dict.reserveCapacity(LocalizedString.allCases.count)

            let en = EnglishTranslations.strings
            let it = ItalianTranslations.strings
            let uk = UkrainianTranslations.strings

            for key in LocalizedString.allCases {
                var entry: [AppLanguage: String] = [:]
                if let s = en[key] { entry[.english] = s }
                if let s = it[key] { entry[.italian] = s }
                if let s = uk[key] { entry[.ukrainian] = s }
                dict[key] = entry
            }
            _translations = dict
            return dict
        }
    }
}

// MARK: - Localization Manager

public final class LocalizationManager: ObservableObject {
    public static let shared = LocalizationManager()

    @Published public var currentLanguage: AppLanguage {
        didSet {
            saveLanguage()
            dlog("🌍 Language changed to: \(currentLanguage.displayName)", category: .general)
        }
    }

    public func setLanguage(_ language: AppLanguage) {
        let apply = { [weak self] in
            guard let self else { return }
            self.currentLanguage = language
            dlog("📢 Posting languageChanged notification...", category: .general)
            NotificationCenter.default.post(name: .languageChanged, object: nil)
            dlog("✅ languageChanged notification posted", category: .general)
        }
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
        }
    }

    private let languageKey = "AppLanguage"

    private init() {
        // Initialize with default value first
        self._currentLanguage = Published(wrappedValue: Self.loadLanguageStatic())
    }

    private static func loadLanguageStatic() -> AppLanguage {
        guard let languageRaw = UserDefaults.standard.string(forKey: "AppLanguage"),
              let language = AppLanguage(rawValue: languageRaw) else {
            return .english // Default language
        }
        return language
    }

    // MARK: - Public Methods

    /// Get localized string for current language
    public func localizedString(for key: LocalizedString) -> String {
        let language = currentLanguage
        guard let translations = LocalizationData.translations[key],
              let localizedString = translations[language] else {
            dlog("⚠️ Missing translation for \(key) in \(language.rawValue)", category: .general)
            return LocalizationData.translations[key]?[.english] ?? String(describing: key)
        }
        return localizedString
    }

    /// Get localized string with arguments
    public func localizedString(for key: LocalizedString, _ arguments: CVarArg...) -> String {
        let format = localizedString(for: key)
        return String(format: format, arguments: arguments)
    }

    /// Get all translations (for internal use)
    public var translations: [LocalizedString: [AppLanguage: String]] {
        LocalizationData.translations
    }

    /// Legacy method for backward compatibility
    public func localized(_ key: LocalizedString) -> String {
        localizedString(for: key)
    }

    /// Check if translation exists for all languages
    public func validateTranslations() -> [LocalizedString: [AppLanguage]] {
        var missing: [LocalizedString: [AppLanguage]] = [:]

        for (key, translations) in LocalizationData.translations {
            let missingLanguages = AppLanguage.allCases.filter { language in
                translations[language] == nil
            }

            if !missingLanguages.isEmpty {
                missing[key] = missingLanguages
            }
        }

        return missing
    }

    /// Generate report of missing translations
    public func generateMissingReport() -> String {
        let missing = validateTranslations()
        var result = "Missing Translations Report\n"
        result += "===========================\n"

        for (key, languages) in missing {
            result += "- \(String(describing: key)): \(languages.map(\.rawValue).joined(separator: ", "))\n"
        }
        return result
    }

    // MARK: - Private Methods

    private func saveLanguage() {
        UserDefaults.standard.set(currentLanguage.rawValue, forKey: languageKey)
    }
}

// MARK: - Helper Extensions

extension LocalizedString {
    /// Get localized string directly
    public func translate(in language: AppLanguage? = nil) -> String {
        let lang = language ?? LocalizationManager.shared.currentLanguage
        guard let translations = LocalizationData.translations[self],
              let localizedString = translations[lang] else {
            return LocalizationData.translations[self]?[.english] ?? String(describing: self)
        }
        return localizedString
    }
}

// MARK: - SwiftUI Integration

#if canImport(SwiftUI)
    import SwiftUI

    extension Text {
        /// Create Text from LocalizedString
        public init(_ key: LocalizedString) {
            self.init(LocalizationManager.shared.localized(key))
        }

        /// Create Text from LocalizedString with arguments
        public init(_ key: LocalizedString, _ arguments: CVarArg...) {
            self.init(LocalizationManager.shared.localizedString(for: key, arguments))
        }
    }

    extension LocalizedString {
        /// Get localized string as Text
        public var text: Text {
            Text(self)
        }

        /// Get localized string
        public var string: String {
            LocalizationManager.shared.localized(self)
        }
    }
#endif

// MARK: - Notification Extension

extension Notification.Name {
    static let languageChanged = Notification.Name("languageChanged")
    static let visualizerToggleFullscreen = Notification.Name("visualizerToggleFullscreen")
    static let visualizerNextPreset = Notification.Name("visualizerNextPreset")
    static let visualizerPrevPreset = Notification.Name("visualizerPrevPreset")
}
