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
    case equalizer
    case calibration
    case autoeqPresets
    case personalized
    case routing
    case settings
    case visualizer

    // Feature Subtitles
    case featureEqualizerSubtitle
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
    case appearance
    case accessibility
    case accessibilityDesc
    case accessibilityStatusNotGranted
    case accessibilityStatusGranted
    case accessibilityRequestButton
    case accessibilityOpenSettingsButton
    case accessibilityTroubleshootHint
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
    case supportDevelopment
    case supportDesc
    case supportThankYou
    case supportKofiDesc
    case supportBmcDesc
    case supportGitHubDesc

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
    case multiOutput
    case status
    case blackHole
    case inputDevice
    case outputDevice
    case installed
    case notInstalled
    case configured
    case notConfigured
    case download
    case refresh
    case openAudioMIDISetup
    case eqActive
    case eqInactive
    case testToneHintWhenDisabled
    case blackHoleRequiredHint
    case noDevicesFound
    case overallStatus

    // Equalizer
    case equalizerTitle
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
    case testTone1k
    case cancel
    case save
    case apply
    case close
    case active
    case resetEQ
    case pureSound
    case profile
    case resetAll
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
    case accessTitle
    case accessDesc
    case accessExplanation
    case grantAccess
    case accessEnabled
    case accessInstructions

    // Buttons
    case back
    case next
    case getStarted

    // Menu Bar
    case menuStatus
    case menuQuickControls
    case menuMainGain
    case menuCustomPresets
    case menuNoPresetsYet
    case menuWindows
    case menuMain
    case menuEQEnabled
    case menuEQDisabled
    case menuCoreAudioRunning
    case menuWaitingForRouting
    case menuProcessingBypassed
    case menuRoutingActive
    case menuRoutingIdle
    case menuBlackHoleDetected
    case menuBlackHoleMissing
    case menuVirtualLoopbackReady
    case menuInstallBlackHole
    case menuMediaKeysAuthorized
    case menuAccessibilityRequired
    case menuSystemEQCanListenKeys
    case menuEnableInAccessibility
    case menuAutoEQIdle
    case menuAutoEQStarting
    case menuAutoEQReady
    case menuAutoEQError
    case menuServerNotRunning
    case menuSpinningUpBackend
    case menuLocalServerHealthy
    case menuUnmute
    case menuMute
    case menuStopTone
    case menuApply
    case menuQuit

    // AutoEQ
    case autoEQTitle
    case autoEQSearchPlaceholder
    case autoEQQuickImport
    case autoEQBandMode
    case autoEQFavorites
    case autoEQHide
    case autoEQShow
    case autoEQLoad
    case autoEQImport
    case autoEQMappedPreview
    case autoEQView
    case autoEQBars
    case autoEQCurve
    case autoEQPreamp
    case autoEQApplyToEQ
    case autoEQBypass
    case autoEQEnable
    case autoEQApplyBands
    case autoEQEQOn
    case autoEQEQOff
    case autoEQBassBoost
    case autoEQRemoveFromFavorites
    case autoEQAddToFavorites
    case searchHeadphonesModel
    case quickImportHelp
    case autoEQImportFile
    case autoEQImportFileHelp
    case autoEQImportFileError
    case autoEQImportFileSuccess
    case autoEQSaveToFavorites
    case autoEQShowSaved
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
    case visualizerStyleColors
    case visualizerStyle
    case visualizerSpectrum
    case visualizerWaveform
    case visualizerParticles
    case visualizerPsychedelic
    case visualizerIntensity
    case visualizerPreview
    case visualizerActive
    case visualizerInactive
    case noAudioSignal
    case startPlaybackToVisualize

    // EQ Startup Behavior
    case eqStartupBehavior
    case eqStartupDesc
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
    case databaseUpToDate
    case databaseUpdateAvailable
    case databaseCheckFailed

    // Personalized Calibration
    case personalizedHearingProfile
    case personalizedTitle
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
    case sineSweepMethod
    case stepOne

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
    case lastCheck
    case blackHoleInstallation
    case ago
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
    case canBeRemovedAnytimeDesc
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
    case deleteProfileConfirmation
    case calibrationTitle
    case calibrationSubtitle
    case equalLoudnessCalibration
    case calibrationDescription
    case calibrationImportantNote
    case calibrationWillImprove
    case calibrationWillImprove1
    case calibrationWillImprove2
    case calibrationWillImprove3
    case calibrationWillImprove4
    case calibrationWontFix
    case calibrationWontFix1
    case calibrationWontFix2
    case calibrationWontFix3
    case calibrationWontFix4
    case calibrationForFullResult
    case calibrationMethodPrinciple
    case calibrationMethodDescription
    case calibrationStep1
    case calibrationStep1Desc
    case calibrationStep2
    case calibrationStep2Desc
    case calibrationStep3
    case calibrationStep3Desc
    case calibrationStep4
    case calibrationStep4Desc

    // BlackHole Setup
    case blackHoleNotInstalled
    case systemeqRequiresBlackHole
    case blackHoleFreeOpenSource
    case whatIsBlackHole

    // UI Elements
    case launchAtLoginEmoji
    case supportThankYouEmoji
    case setupNow
    case blackHoleNotInstalledShort

    // Room Calibration
    case findRoomResonances
    case startSineSweepAndListen
    case markFrequenciesThatBoomOrRing
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
    case sineSweep
    case manual
    case notchFilters
    case abTest
    case addResonance
    case resonanceFrequency
    case severity
    case mild
    case moderate
    case severe
    case extreme
    case addNotchFilter
    case gain
    case qFactor
    case saveProfile
    case profileName
    case saveCalibrationProfile
    case compareOriginalVsFiltered
    case hearingTestDifference
    case filtersActive
    case noFiltersAdded
    case notchFilterDescription
    case resonanceDescription
    case roomCalibrationHelp
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
    case spectrum
    case waveform
    case particles
    case psychedelic
    case intensity
    case preview

    // CalibrationView - Additional hardcoded strings
    case calibrationCompensateRoom
    case calibrationCompensateHeadphones
    case calibrationImportantLimitations
    case calibrationWhatWillImprove
    case calibrationMidHighBalance
    case calibrationHearingCompensation
    case calibrationSpeakerCorrection
    case calibrationHeadphoneCorrection
    case calibrationLessFatigue
    case calibrationWhatWontFix
    case calibrationBassResonances
    case calibrationEchoReverb
    case calibrationRoomUnevenness
    case calibrationNeedsMicrophone
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
    case calibrationOptimalConditions
    case calibrationOptimalCondition1
    case calibrationOptimalCondition2
    case calibrationOptimalCondition3
    case calibrationOptimalCondition4
    case calibrationOptimalCondition5
    case calibrationEqualLoudnessVsRoom
    case calibrationEqualLoudnessMethod
    case calibrationEqualLoudnessDesc1
    case calibrationEqualLoudnessDesc2
    case calibrationEqualLoudnessDesc3
    case calibrationRoomCorrectionMethod
    case calibrationRoomCorrectionDesc1
    case calibrationRoomCorrectionDesc2
    case calibrationRoomCorrectionDesc3

    // AutoEQView - Additional hardcoded strings
    case autoEQTypeModelName
    case autoEQFavoritesTitle
    case autoEQMappedPreviewTitle
    case autoEQSetupTitle
    case autoEQSetupDesc1
    case autoEQSetupDesc2

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
    case neverAsk
    case later
    case installNow

    // Glass Design Section (Settings)
    case glassDesignTitle
    case glassDesignDesc
    case glassDesignStyle
    case glassDesignCustomOpacity
    case glassDesignOpacity
    case glassDesignPreview
    case glassDesignPreviewLabel

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

            let dict: [LocalizedString: [AppLanguage: String]] = [
                // Main Window
                .mainWindowTitle: [
                    .english: "SystemEQ for Mac",
                    .italian: "SystemEQ per Mac",
                    .ukrainian: "SystemEQ для Mac"
                ],
                .mainSubtitle: [
                    .english: "Professional Audio Equalizer",
                    .italian: "Equalizzatore Audio Professionale",
                    .ukrainian: "Професійний Аудіо Еквалайзер"
                ],
                .equalizer: [
                    .english: "Equalizer",
                    .italian: "Equalizzatore",
                    .ukrainian: "Еквалайзер"
                ],
                .calibration: [
                    .english: "Calibration",
                    .italian: "Calibrazione",
                    .ukrainian: "Калібрування"
                ],
                .autoeqPresets: [
                    .english: "AutoEQ presets",
                    .italian: "Preset AutoEQ",
                    .ukrainian: "Пресети AutoEQ"
                ],
                .personalized: [
                    .english: "Personalized",
                    .italian: "Personalizzato",
                    .ukrainian: "Персоналізований"
                ],
                .routing: [
                    .english: "Routing",
                    .italian: "Routing",
                    .ukrainian: "Маршрутизація"
                ],
                .settings: [
                    .english: "Settings",
                    .italian: "Impostazioni",
                    .ukrainian: "Налаштування"
                ],
                .visualizer: [
                    .english: "Visualizer",
                    .italian: "Visualizzatore",
                    .ukrainian: "Візуалізатор"
                ],

                // Feature Subtitles
                .featureEqualizerSubtitle: [
                    .english: "10 or 31 band EQ",
                    .italian: "EQ a 10 o 31 bande",
                    .ukrainian: "Еквалайзер на 10 або 31 смугу"
                ],
                .featureCalibrationSubtitle: [
                    .english: "Room & headphone calibration",
                    .italian: "Calibrazione stanza & cuffie",
                    .ukrainian: "Калібрування кімнати та навушників"
                ],
                .featureAutoEQSubtitle: [
                    .english: "AutoEQ presets library",
                    .italian: "Libreria preset AutoEQ",
                    .ukrainian: "Бібліотека пресетів AutoEQ"
                ],
                .featureRoutingSubtitle: [
                    .english: "Audio device routing",
                    .italian: "Routing dispositivi audio",
                    .ukrainian: "Маршрутизація аудіо пристроїв"
                ],
                .featureSettingsSubtitle: [
                    .english: "App preferences",
                    .italian: "Preferenze app",
                    .ukrainian: "Налаштування програми"
                ],
                .featureVisualizerSubtitle: [
                    .english: "Real-time spectrum",
                    .italian: "Spettro in tempo reale",
                    .ukrainian: "Спектр в реальному часі"
                ],

                // Settings
                .settingsTitle: [
                    .english: "Settings",
                    .italian: "Impostazioni",
                    .ukrainian: "Налаштування"
                ],
                .language: [
                    .english: "Language",
                    .italian: "Lingua",
                    .ukrainian: "Мова"
                ],
                .languageDesc: [
                    .english: "Choose your preferred language for the app interface",
                    .italian: "Scegli la lingua preferita per l'interfaccia dell'app",
                    .ukrainian: "Оберіть бажану мову інтерфейсу програми"
                ],
                .general: [
                    .english: "General",
                    .italian: "Generale",
                    .ukrainian: "Загальне"
                ],
                .audioBackend: [
                    .english: "Audio Engine",
                    .italian: "Motore audio",
                    .ukrainian: "Аудіорушій"
                ],
                .audioBackendDesc: [
                    .english: "Automatic uses the native macOS engine when available and keeps BlackHole as a fallback.",
                    .italian: "Automatico usa il motore nativo di macOS quando disponibile e mantiene BlackHole come alternativa.",
                    .ukrainian: "Автоматичний режим використовує нативний рушій macOS, а BlackHole лишає як резервний."
                ],
                .audioBackendAutomatic: [
                    .english: "Automatic",
                    .italian: "Automatico",
                    .ukrainian: "Автоматично"
                ],
                .audioBackendNative: [
                    .english: "Native (Process Tap)",
                    .italian: "Nativo (Process Tap)",
                    .ukrainian: "Нативний (Process Tap)"
                ],
                .audioBackendBlackHole: [
                    .english: "BlackHole",
                    .italian: "BlackHole",
                    .ukrainian: "BlackHole"
                ],
                .launchAtLogin: [
                    .english: "Launch at Login",
                    .italian: "Avvia al login",
                    .ukrainian: "Запускати при вході"
                ],
                .showMenuBarIcon: [
                    .english: "Show Menu Bar Icon",
                    .italian: "Mostra icona barra menu",
                    .ukrainian: "Показувати іконку в меню"
                ],
                .hideDockIcon: [
                    .english: "Hide Dock Icon",
                    .italian: "Nascondi icona dal Dock",
                    .ukrainian: "Ховати іконку з Dock"
                ],
                .hideDockIconHelp: [
                    .english: "Keeps the menu bar icon on so the app stays reachable",
                    .italian: "Mantiene l'icona nella barra dei menu per accedere all'app",
                    .ukrainian: "Іконка в рядку меню лишається, щоб застосунок був доступний"
                ],
                .autoSwitchPresetPerDevice: [
                    .english: "Auto-Switch Preset per Output",
                    .italian: "Cambio preset automatico per uscita",
                    .ukrainian: "Авто-пресет для кожного виводу"
                ],
                .autoSwitchPresetPerDeviceHelp: [
                    .english: "Remembers the preset applied on each output device and re-applies it when you switch outputs",
                    .italian: "Ricorda il preset applicato su ogni uscita e lo riapplica quando cambi dispositivo",
                    .ukrainian: "Пам'ятає пресет кожного пристрою виводу і сам застосовує його при перемиканні"
                ],
                .links: [
                    .english: "Links",
                    .italian: "Link",
                    .ukrainian: "Посилання"
                ],
                .appearance: [
                    .english: "Appearance",
                    .italian: "Aspetto",
                    .ukrainian: "Зовнішній вигляд"
                ],
                .accessibility: [
                    .english: "Accessibility",
                    .italian: "Accessibilità",
                    .ukrainian: "Доступність"
                ],
                .accessibilityDesc: [
                    .english: "Enable access so SystemEQ can respond to media keys (F10/F11/F12) for volume control.",
                    .italian: "Abilita l'accesso per permettere a SystemEQ di rispondere ai tasti multimediali (F10/F11/F12) per il controllo volume.",
                    .ukrainian: "Увімкніть доступ, щоб SystemEQ міг реагувати на медіа-клавіші (F10/F11/F12) для керування гучністю."
                ],
                .accessibilityStatusNotGranted: [
                    .english: "⚠️ Access not granted",
                    .italian: "⚠️ Accesso non concesso",
                    .ukrainian: "⚠️ Доступ не надано"
                ],
                .accessibilityStatusGranted: [
                    .english: "✅ Access granted",
                    .italian: "✅ Accesso concesso",
                    .ukrainian: "✅ Доступ надано"
                ],
                .accessibilityRequestButton: [
                    .english: "Request Access",
                    .italian: "Richiedi Accesso",
                    .ukrainian: "Запитати доступ"
                ],
                .accessibilityOpenSettingsButton: [
                    .english: "Open Settings",
                    .italian: "Apri Impostazioni",
                    .ukrainian: "Відкрити Налаштування"
                ],
                .accessibilityTroubleshootHint: [
                    .english: "If you already enabled the checkbox in System Settings, restart SystemEQ or click Refresh after reopening this window.",
                    .italian: "Se hai già abilitato la casella nelle Impostazioni di Sistema, riavvia SystemEQ o clicca Aggiorna dopo aver riaperto questa finestra.",
                    .ukrainian: "Якщо ви вже увімкнули прапорець у Системних Налаштуваннях, перезапустіть SystemEQ або натисніть Оновити після повторного відкриття цього вікна."
                ],
                .settingsHeaderSubtitle: [
                    .english: "General • Language • Diagnostics • Links",
                    .italian: "Generale • Lingua • Diagnostica • Link",
                    .ukrainian: "Загальне • Мова • Діагностика • Посилання"
                ],
                .diagnostics: [
                    .english: "Diagnostics",
                    .italian: "Diagnostica",
                    .ukrainian: "Діагностика"
                ],
                .diagnosticsDesc: [
                    .english: "Export the current SystemEQ state and recent privacy-safe routing events.",
                    .italian: "Esporta lo stato attuale di SystemEQ e gli eventi di routing recenti senza dati personali.",
                    .ukrainian: "Експортує поточний стан SystemEQ і недавні події роутингу без приватних даних."
                ],
                .exportDiagnostics: [
                    .english: "Export Diagnostic Report",
                    .italian: "Esporta report diagnostico",
                    .ukrainian: "Експортувати звіт діагностики"
                ],
                .diagnosticsExported: [
                    .english: "Report saved.",
                    .italian: "Report salvato.",
                    .ukrainian: "Звіт збережено."
                ],
                .diagnosticsExportFailed: [
                    .english: "Could not save the report.",
                    .italian: "Impossibile salvare il report.",
                    .ukrainian: "Не вдалося зберегти звіт."
                ],
                .diagnosticsPrivacy: [
                    .english: "No audio, media metadata, device names, UIDs, file paths, or automatic upload are included.",
                    .italian: "Non include audio, metadati multimediali, nomi o UID dei dispositivi, percorsi di file o caricamenti automatici.",
                    .ukrainian: "Звіт не містить аудіо, метаданих медіа, назв чи UID пристроїв, шляхів до файлів або автоматичного надсилання."
                ],
                .revealDiagnostics: [
                    .english: "Show in Finder",
                    .italian: "Mostra nel Finder",
                    .ukrainian: "Показати у Finder"
                ],
                .shareDiagnostics: [
                    .english: "Share…",
                    .italian: "Condividi…",
                    .ukrainian: "Поділитися…"
                ],

                // Links
                .linkGitHub: [
                    .english: "GitHub Repository",
                    .italian: "Repository GitHub",
                    .ukrainian: "Репозиторій GitHub"
                ],
                .linkAutoEQ: [
                    .english: "AutoEQ Database",
                    .italian: "Database AutoEQ",
                    .ukrainian: "База даних AutoEQ"
                ],
                .linkBlackHole: [
                    .english: "BlackHole Download",
                    .italian: "Download BlackHole",
                    .ukrainian: "Завантажити BlackHole"
                ],
                .linkBuyMeACoffee: [
                    .english: "Buy Me a Coffee",
                    .italian: "Buy Me a Coffee",
                    .ukrainian: "Buy Me a Coffee"
                ],
                .supportDevelopment: [
                    .english: "Support Development",
                    .italian: "Supporta Sviluppo",
                    .ukrainian: "Підтримати розробку"
                ],
                .supportDesc: [
                    .english: "SystemEQ is free and open-source. If you find it useful, consider supporting development.",
                    .italian: "SystemEQ è gratuito e open-source. Se lo trovi utile, considera di supportare lo sviluppo.",
                    .ukrainian: "SystemEQ безкоштовний з відкритим кодом. Якщо ви вважаєте його корисним, підтримайте розробку."
                ],
                .supportThankYou: [
                    .english: "Every donation helps keep this project alive. Thank you! ❤️",
                    .italian: "Ogni donazione aiuta a mantenere vivo questo progetto. Grazie! ❤️",
                    .ukrainian: "Кожна пожертва допомагає підтримувати цей проект. Дякуємо! ❤️"
                ],
                .supportKofiDesc: [
                    .english: "One-time donation, 0% fees",
                    .italian: "Donazione una tantum, 0% commissioni",
                    .ukrainian: "Разова пожертва, 0% комісія"
                ],
                .supportBmcDesc: [
                    .english: "Buy me a coffee, 0% fees",
                    .italian: "Offrimi un caffè, 0% commissioni",
                    .ukrainian: "Купіть мені каву, 0% комісія"
                ],
                .supportGitHubDesc: [
                    .english: "Monthly sponsorship, 0% fees",
                    .italian: "Sponsorizzazione mensile, 0% commissioni",
                    .ukrainian: "Щомісячна спонсорська підтримка, 0% комісія"
                ],

                // Routing
                .routingTitle: [
                    .english: "Audio Routing",
                    .italian: "Routing Audio",
                    .ukrainian: "Маршрутизація аудіо"
                ],
                .routingDesc: [
                    .english: "Configure audio devices and routing",
                    .italian: "Configura dispositivi audio e routing",
                    .ukrainian: "Налаштуйте аудіо пристрої та маршрутизацію"
                ],
                .systemOutput: [
                    .english: "System Output",
                    .italian: "Uscita Sistema",
                    .ukrainian: "Системний вивід"
                ],
                .systemOutputDesc: [
                    .english: "Manage system default audio device",
                    .italian: "Gestisci dispositivo audio predefinito di sistema",
                    .ukrainian: "Керуйте системним аудіо пристроєм за замовчуванням"
                ],
                .enableEQ: [
                    .english: "Enable EQ",
                    .italian: "Abilita EQ",
                    .ukrainian: "Увімкнути EQ"
                ],
                .disableEQ: [
                    .english: "Disable EQ",
                    .italian: "Disabilita EQ",
                    .ukrainian: "Вимкнути EQ"
                ],
                .testTone: [
                    .english: "Test Tone (440 Hz)",
                    .italian: "Tono di Test (440 Hz)",
                    .ukrainian: "Тестовий сигнал (440 Гц)"
                ],
                .stopTone: [
                    .english: "Stop Tone",
                    .italian: "Ferma Tono",
                    .ukrainian: "Зупинити сигнал"
                ],
                .audioLevels: [
                    .english: "Audio Levels",
                    .italian: "Livelli Audio",
                    .ukrainian: "Рівні аудіо"
                ],
                .input: [
                    .english: "Input",
                    .italian: "Ingresso",
                    .ukrainian: "Вхід"
                ],
                .output: [
                    .english: "Output",
                    .italian: "Uscita",
                    .ukrainian: "Вихід"
                ],
                .devices: [
                    .english: "Devices",
                    .italian: "Dispositivi",
                    .ukrainian: "Пристрої"
                ],
                .multiOutput: [
                    .english: "Multi-Output",
                    .italian: "Multi-Uscita",
                    .ukrainian: "Багатоканальний вивід"
                ],
                .status: [
                    .english: "Status",
                    .italian: "Stato",
                    .ukrainian: "Статус"
                ],
                .blackHole: [
                    .english: "BlackHole",
                    .italian: "BlackHole",
                    .ukrainian: "BlackHole"
                ],
                .inputDevice: [
                    .english: "Input Device",
                    .italian: "Dispositivo Ingresso",
                    .ukrainian: "Вхідний пристрій"
                ],
                .outputDevice: [
                    .english: "Output Device",
                    .italian: "Dispositivo Uscita",
                    .ukrainian: "Вихідний пристрій"
                ],
                .installed: [
                    .english: "Installed",
                    .italian: "Installato",
                    .ukrainian: "Встановлено"
                ],
                .notInstalled: [
                    .english: "Not installed",
                    .italian: "Non installato",
                    .ukrainian: "Не встановлено"
                ],
                .configured: [
                    .english: "Configured",
                    .italian: "Configurato",
                    .ukrainian: "Налаштовано"
                ],
                .notConfigured: [
                    .english: "Not configured",
                    .italian: "Non configurato",
                    .ukrainian: "Не налаштовано"
                ],
                .download: [
                    .english: "Download",
                    .italian: "Download",
                    .ukrainian: "Завантажити"
                ],
                .refresh: [
                    .english: "Refresh",
                    .italian: "Aggiorna",
                    .ukrainian: "Оновити"
                ],
                .openAudioMIDISetup: [
                    .english: "Open Audio MIDI Setup",
                    .italian: "Apri Configurazione Audio MIDI",
                    .ukrainian: "Відкрити Аудіо MIDI Налаштування"
                ],
                .eqActive: [
                    .english: "EQ Active",
                    .italian: "EQ Attivo",
                    .ukrainian: "EQ Активний"
                ],
                .eqInactive: [
                    .english: "EQ Inactive",
                    .italian: "EQ Inattivo",
                    .ukrainian: "EQ Неактивний"
                ],
                .testToneHintWhenDisabled: [
                    .english: "💡 Test Tone available only when EQ is enabled",
                    .italian: "💡 Tono di test disponibile solo quando EQ è abilitato",
                    .ukrainian: "💡 Тестовий сигнал доступний лише коли EQ увімкнено"
                ],
                .blackHoleRequiredHint: [
                    .english: "BlackHole is required for system-wide audio routing. Download and install it, then restart this app.",
                    .italian: "BlackHole è richiesto per il routing audio di sistema. Scarica e installalo, quindi riavvia questa app.",
                    .ukrainian: "BlackHole потрібен для системної маршрутизації аудіо. Завантажте, встановіть його та перезапустіть застосунок."
                ],
                .noDevicesFound: [
                    .english: "No devices found",
                    .italian: "Nessun dispositivo trovato",
                    .ukrainian: "Пристроїв не знайдено"
                ],
                .overallStatus: [
                    .english: "Overall Status",
                    .italian: "Stato Generale",
                    .ukrainian: "Загальний статус"
                ],

                // Equalizer
                .equalizerTitle: [
                    .english: "Equalizer",
                    .italian: "Equalizzatore",
                    .ukrainian: "Еквалайзер"
                ],
                .bandMode: [
                    .english: "Mode",
                    .italian: "Modalità",
                    .ukrainian: "Режим"
                ],
                .reset: [
                    .english: "Reset",
                    .italian: "Ripristina",
                    .ukrainian: "Скинути"
                ],
                .autoPreamp: [
                    .english: "Normalize",
                    .italian: "Normalizza",
                    .ukrainian: "Нормалізувати"
                ],
                .preamp: [
                    .english: "Preset headroom",
                    .italian: "Margine del preset",
                    .ukrainian: "Запас пресету"
                ],
                .preampSafetyWarning: [
                    .english: "Recommended safe headroom: %@. Higher levels can compress transients; watch the LIMIT indicator.",
                    .italian: "Margine sicuro consigliato: %@. Livelli più alti possono comprimere i transienti; controlla LIMIT.",
                    .ukrainian: "Рекомендований безпечний запас: %@. Вищий рівень може стискати транзієнти; стежте за LIMIT."
                ],
                .outputBoost: [
                    .english: "Gain",
                    .italian: "Guadagno",
                    .ukrainian: "Підсилення"
                ],
                .outputBoostDescription: [
                    .english: "Adds loudness after EQ, up to +12 dB. On loud material, extra gain can compress dynamics instead of making it louder.",
                    .italian: "Aggiunge volume dopo l'EQ, fino a +12 dB. Su materiale già forte, il guadagno extra può comprimere la dinamica invece di aumentare il volume.",
                    .ukrainian: "Додає гучність після EQ, до +12 дБ. На вже гучному матеріалі додаткове підсилення може стискати динаміку замість збільшення гучності."
                ],
                .limiterActivityDescription: [
                    .english: "Green: no reduction. Yellow: up to 3 dB. Red: more than 3 dB of real gain reduction.",
                    .italian: "Verde: nessuna riduzione. Giallo: fino a 3 dB. Rosso: oltre 3 dB di riduzione reale.",
                    .ukrainian: "Зелений: без зменшення. Жовтий: до 3 дБ. Червоний: понад 3 дБ фактичного зменшення."
                ],
                .bands10: [
                    .english: "10 Bands",
                    .italian: "10 Bande",
                    .ukrainian: "10 Смуг"
                ],
                .bands31: [
                    .english: "31 Bands",
                    .italian: "31 Bande",
                    .ukrainian: "31 Смуга"
                ],
                .testTone1k: [
                    .english: "Test 1kHz",
                    .italian: "Test 1kHz",
                    .ukrainian: "Тест 1кГц"
                ],
                .cancel: [
                    .english: "Cancel",
                    .italian: "Annulla",
                    .ukrainian: "Скасувати"
                ],
                .save: [
                    .english: "Save",
                    .italian: "Salva",
                    .ukrainian: "Зберегти"
                ],
                .apply: [
                    .english: "Apply",
                    .italian: "Applica",
                    .ukrainian: "Застосувати"
                ],
                .close: [
                    .english: "Close",
                    .italian: "Chiudi",
                    .ukrainian: "Закрити"
                ],
                .active: [
                    .english: "Active",
                    .italian: "Attivo",
                    .ukrainian: "Активний"
                ],
                .resetEQ: [
                    .english: "Reset EQ",
                    .italian: "Ripristina EQ",
                    .ukrainian: "Скинути EQ"
                ],
                .pureSound: [
                    .english: "Pure Sound",
                    .italian: "Suono Puro",
                    .ukrainian: "Чистий звук"
                ],
                .profile: [
                    .english: "Profile",
                    .italian: "Profilo",
                    .ukrainian: "Профіль"
                ],
                .resetAll: [
                    .english: "Reset All",
                    .italian: "Ripristina Tutto",
                    .ukrainian: "Скинути все"
                ],
                .frequencyHz: [
                    .english: "Hz",
                    .italian: "Hz",
                    .ukrainian: "Гц"
                ],
                .dB: [
                    .english: "dB",
                    .italian: "dB",
                    .ukrainian: "дБ"
                ],
                .add: [
                    .english: "Add",
                    .italian: "Aggiungi",
                    .ukrainian: "Додати"
                ],
                .unlock: [
                    .english: "Unlock",
                    .italian: "Sblocca",
                    .ukrainian: "Розблокувати"
                ],

                // Welcome
                .welcomeTitle: [
                    .english: "Welcome to SystemEQ",
                    .italian: "Benvenuto in SystemEQ",
                    .ukrainian: "Ласкаво просимо до SystemEQ"
                ],
                .welcomeSubtitle: [
                    .english: "Professional System-Wide Equalizer for Mac",
                    .italian: "Equalizzatore Professionale di Sistema per Mac",
                    .ukrainian: "Професійний Системний Еквалайзер для Mac"
                ],
                .welcomeDesc: [
                    .english: "To give you the best audio experience, we need to set up a few things properly. This will only take a minute.",
                    .italian: "Per offrirti la migliore esperienza audio, dobbiamo configurare alcune cose. Ci vorrà solo un minuto.",
                    .ukrainian: "Щоб забезпечити найкращий звук, нам потрібно налаштувати кілька речей. Це займе лише хвилину."
                ],
                .chooseLanguage: [
                    .english: "Choose Language",
                    .italian: "Scegli la Lingua",
                    .ukrainian: "Оберіть Мову"
                ],

                // Driver Setup
                .driverTitle: [
                    .english: "Step 1: Audio Driver",
                    .italian: "Passo 1: Driver Audio",
                    .ukrainian: "Крок 1: Аудіо Драйвер"
                ],
                .driverDesc: [
                    .english: "SystemEQ requires the BlackHole virtual audio driver to capture system sound. It acts as a virtual cable between your apps and our equalizer.",
                    .italian: "SystemEQ richiede il driver audio virtuale BlackHole per catturare il suono di sistema. Agisce come un cavo virtuale tra le tue app e il nostro equalizzatore.",
                    .ukrainian: "SystemEQ потребує віртуальний драйвер BlackHole для захоплення системного звуку. Він діє як віртуальний кабель між вашими програмами та нашим еквалайзером."
                ],
                .driverFound: [
                    .english: "BlackHole is installed!",
                    .italian: "BlackHole è installato!",
                    .ukrainian: "BlackHole встановлено!"
                ],
                .driverNotFound: [
                    .english: "BlackHole not found",
                    .italian: "BlackHole non trovato",
                    .ukrainian: "BlackHole не знайдено"
                ],
                .downloadDriver: [
                    .english: "Download BlackHole Installer",
                    .italian: "Download Installatore BlackHole",
                    .ukrainian: "Завантажити інсталятор BlackHole"
                ],
                .driverInstructions: [
                    .english: "Download and run the installer, then click Refresh.",
                    .italian: "Download ed esegui l'installatore, quindi clicca Aggiorna.",
                    .ukrainian: "Завантажте та запустіть інсталятор, потім натисніть Оновити."
                ],

                // Privacy
                .privacyTitle: [
                    .english: "Step 2: Audio Permissions",
                    .italian: "Passo 2: Permessi Audio",
                    .ukrainian: "Крок 2: Дозвіл на Аудіо"
                ],
                .privacyDesc: [
                    .english: "macOS classifies any audio capture as 'Microphone Usage'.",
                    .italian: "macOS classifica qualsiasi cattura audio come 'Uso del Microfono'.",
                    .ukrainian: "macOS класифікує будь-яке захоплення аудіо як 'Використання мікрофона'."
                ],
                .privacyPoint1: [
                    .english: "We connect to the virtual BlackHole driver.",
                    .italian: "Ci connettiamo al driver virtuale BlackHole.",
                    .ukrainian: "Ми підключаємось до віртуального драйвера BlackHole."
                ],
                .privacyPoint2: [
                    .english: "We process music/system audio.",
                    .italian: "Elaboriamo musica/audio di sistema.",
                    .ukrainian: "Ми обробляємо музику та системні звуки."
                ],
                .privacyPoint3: [
                    .english: "We DO NOT record your physical microphone.",
                    .italian: "NON registriamo il tuo microfono fisico.",
                    .ukrainian: "Ми НЕ записуємо ваш фізичний мікрофон."
                ],
                .privacyPoint4: [
                    .english: "Your voice is never recorded or transmitted.",
                    .italian: "La tua voce non viene mai registrata o trasmessa.",
                    .ukrainian: "Ваш голос ніколи не записується і не передається."
                ],
                .grantPermission: [
                    .english: "Grant Audio Permission",
                    .italian: "Concedi Permesso Audio",
                    .ukrainian: "Надати дозвіл на аудіо"
                ],
                .permissionGranted: [
                    .english: "Permission Granted",
                    .italian: "Permesso Concesso",
                    .ukrainian: "Дозвіл надано"
                ],

                // Accessibility
                .accessTitle: [
                    .english: "Step 3: Volume Controls",
                    .italian: "Passo 3: Controlli Volume",
                    .ukrainian: "Крок 3: Керування Гучністю"
                ],
                .accessDesc: [
                    .english: "When using an equalizer, macOS disables the standard F10/F11/F12 volume keys.",
                    .italian: "Quando usi un equalizzatore, macOS disabilita i tasti volume standard F10/F11/F12.",
                    .ukrainian: "При використанні еквалайзера macOS вимикає стандартні клавіші гучності F10/F11/F12."
                ],
                .accessExplanation: [
                    .english: "To fix this, SystemEQ needs Accessibility Access to detect volume key presses and adjust the volume manually.",
                    .italian: "Per risolvere, SystemEQ necessita di Accesso Universale per rilevare la pressione dei tasti volume e regolare il volume manualmente.",
                    .ukrainian: "Щоб виправити це, SystemEQ потрібен дозвіл 'Спеціальні можливості' для виявлення натискання клавіш та ручної зміни гучності."
                ],
                .grantAccess: [
                    .english: "Grant Accessibility Access",
                    .italian: "Concedi Accesso Universale",
                    .ukrainian: "Надати дозвіл Accessibility"
                ],
                .accessEnabled: [
                    .english: "Accessibility Enabled",
                    .italian: "Accesso Universale Abilitato",
                    .ukrainian: "Дозвіл Accessibility надано"
                ],
                .accessInstructions: [
                    .english: "Clicking this will open System Settings. Enable the toggle for SystemEQ.",
                    .italian: "Cliccando questo aprirà le Impostazioni di Sistema. Abilita l'interruttore per SystemEQ.",
                    .ukrainian: "Натискання відкриє Системні Параметри. Увімкніть перемикач для SystemEQ."
                ],

                // Buttons
                .back: [
                    .english: "Back",
                    .italian: "Indietro",
                    .ukrainian: "Назад"
                ],
                .next: [
                    .english: "Next",
                    .italian: "Avanti",
                    .ukrainian: "Далі"
                ],
                .getStarted: [
                    .english: "Get Started",
                    .italian: "Inizia",
                    .ukrainian: "Почати"
                ],

                // Menu Bar
                .menuStatus: [
                    .english: "Status",
                    .italian: "Stato",
                    .ukrainian: "Статус"
                ],
                .menuQuickControls: [
                    .english: "Quick Controls",
                    .italian: "Controlli Veloce",
                    .ukrainian: "Швидке керування"
                ],
                .menuMainGain: [
                    .english: "Main Gain",
                    .italian: "Guadagno Principale",
                    .ukrainian: "Основне посилення"
                ],
                .menuCustomPresets: [
                    .english: "Custom Presets",
                    .italian: "Preset Personalizzati",
                    .ukrainian: "Власні пресети"
                ],
                .menuNoPresetsYet: [
                    .english: "No custom presets yet",
                    .italian: "Nessun preset personalizzato ancora",
                    .ukrainian: "Ще немає власних пресетів"
                ],
                .menuWindows: [
                    .english: "Windows",
                    .italian: "Finestre",
                    .ukrainian: "Вікна"
                ],
                .menuMain: [
                    .english: "Main",
                    .italian: "Principale",
                    .ukrainian: "Головне"
                ],
                .menuEQEnabled: [
                    .english: "EQ Enabled",
                    .italian: "EQ Abilitato",
                    .ukrainian: "EQ Увімкнено"
                ],
                .menuEQDisabled: [
                    .english: "EQ Disabled",
                    .italian: "EQ Disabilitato",
                    .ukrainian: "EQ Вимкнено"
                ],
                .menuCoreAudioRunning: [
                    .english: "Core Audio running",
                    .italian: "Core Audio in esecuzione",
                    .ukrainian: "Core Audio працює"
                ],
                .menuWaitingForRouting: [
                    .english: "Waiting for routing",
                    .italian: "In attesa di routing",
                    .ukrainian: "Очікування маршрутизації"
                ],
                .menuProcessingBypassed: [
                    .english: "Processing bypassed",
                    .italian: "Elaborazione ignorata",
                    .ukrainian: "Обробку обійдено"
                ],
                .menuRoutingActive: [
                    .english: "Routing Active",
                    .italian: "Routing Attivo",
                    .ukrainian: "Маршрутизація активна"
                ],
                .menuRoutingIdle: [
                    .english: "Routing Idle",
                    .italian: "Routing Inattivo",
                    .ukrainian: "Маршрутизація неактивна"
                ],
                .menuBlackHoleDetected: [
                    .english: "BlackHole detected",
                    .italian: "BlackHole rilevato",
                    .ukrainian: "BlackHole виявлено"
                ],
                .menuBlackHoleMissing: [
                    .english: "BlackHole missing",
                    .italian: "BlackHole mancante",
                    .ukrainian: "BlackHole відсутній"
                ],
                .menuVirtualLoopbackReady: [
                    .english: "Virtual loopback ready",
                    .italian: "Loopback virtuale pronto",
                    .ukrainian: "Віртуальний loopback готовий"
                ],
                .menuInstallBlackHole: [
                    .english: "Install BlackHole for routing",
                    .italian: "Installa BlackHole per il routing",
                    .ukrainian: "Встановіть BlackHole для маршрутизації"
                ],
                .menuMediaKeysAuthorized: [
                    .english: "Media keys authorized",
                    .italian: "Tasti multimediali autorizzati",
                    .ukrainian: "Медіа-клавіші авторизовано"
                ],
                .menuAccessibilityRequired: [
                    .english: "Accessibility required",
                    .italian: "Accessibilità richiesta",
                    .ukrainian: "Потрібен Accessibility"
                ],
                .menuSystemEQCanListenKeys: [
                    .english: "SystemEQ can listen to keys",
                    .italian: "SystemEQ può ascoltare i tasti",
                    .ukrainian: "SystemEQ може слухати клавіші"
                ],
                .menuEnableInAccessibility: [
                    .english: "Enable in Settings → Accessibility",
                    .italian: "Abilita in Impostazioni → Accessibilità",
                    .ukrainian: "Увімкнути в Налаштування → Доступність"
                ],
                .menuAutoEQIdle: [
                    .english: "AutoEQ idle",
                    .italian: "AutoEQ inattivo",
                    .ukrainian: "AutoEQ неактивний"
                ],
                .menuAutoEQStarting: [
                    .english: "AutoEQ starting",
                    .italian: "AutoEQ in avvio",
                    .ukrainian: "AutoEQ запускається"
                ],
                .menuAutoEQReady: [
                    .english: "AutoEQ ready",
                    .italian: "AutoEQ pronto",
                    .ukrainian: "AutoEQ готовий"
                ],
                .menuAutoEQError: [
                    .english: "AutoEQ error",
                    .italian: "Errore AutoEQ",
                    .ukrainian: "Помилка AutoEQ"
                ],
                .menuServerNotRunning: [
                    .english: "Server not running",
                    .italian: "Server non in esecuzione",
                    .ukrainian: "Сервер не запущено"
                ],
                .menuSpinningUpBackend: [
                    .english: "Spinning up Python backend",
                    .italian: "Avvio backend Python",
                    .ukrainian: "Запуск Python бекенду"
                ],
                .menuLocalServerHealthy: [
                    .english: "Local server healthy",
                    .italian: "Server locale sano",
                    .ukrainian: "Локальний сервер здоровий"
                ],
                .menuUnmute: [
                    .english: "Unmute",
                    .italian: "Attiva audio",
                    .ukrainian: "Увімкнути звук"
                ],
                .menuMute: [
                    .english: "Mute",
                    .italian: "Silenzia",
                    .ukrainian: "Вимкнути звук"
                ],
                .menuStopTone: [
                    .english: "Stop Tone",
                    .italian: "Ferma Tono",
                    .ukrainian: "Зупинити сигнал"
                ],
                .menuApply: [
                    .english: "Apply",
                    .italian: "Applica",
                    .ukrainian: "Застосувати"
                ],
                .menuQuit: [
                    .english: "Quit",
                    .italian: "Esci",
                    .ukrainian: "Вийти"
                ],

                // AutoEQ
                .autoEQTitle: [
                    .english: "AutoEQ",
                    .italian: "AutoEQ",
                    .ukrainian: "AutoEQ"
                ],
                .autoEQSearchPlaceholder: [
                    .english: "Type a model name to search",
                    .italian: "Digita un nome modello per cercare",
                    .ukrainian: "Введіть назву моделі для пошуку"
                ],
                .autoEQQuickImport: [
                    .english: "⚡ Quick Import",
                    .italian: "⚡ Importazione Rapida",
                    .ukrainian: "⚡ Швидкий імпорт"
                ],
                .autoEQBandMode: [
                    .english: "Band Mode",
                    .italian: "Modalità Bande",
                    .ukrainian: "Режим смуг"
                ],
                .autoEQFavorites: [
                    .english: "⭐ Favorites",
                    .italian: "⭐ Preferiti",
                    .ukrainian: "⭐ Обране"
                ],
                .autoEQHide: [
                    .english: "Hide",
                    .italian: "Nascondi",
                    .ukrainian: "Приховати"
                ],
                .autoEQShow: [
                    .english: "Show",
                    .italian: "Mostra",
                    .ukrainian: "Показати"
                ],
                .autoEQLoad: [
                    .english: "Load",
                    .italian: "Carica",
                    .ukrainian: "Завантажити"
                ],
                .autoEQImport: [
                    .english: "Import",
                    .italian: "Importa",
                    .ukrainian: "Імпорт"
                ],
                .autoEQMappedPreview: [
                    .english: "Mapped Preview",
                    .italian: "Anteprima Mappata",
                    .ukrainian: "Попередній перегляд мапи"
                ],
                .autoEQView: [
                    .english: "View",
                    .italian: "Visualizza",
                    .ukrainian: "Переглянути"
                ],
                .autoEQBars: [
                    .english: "Bars",
                    .italian: "Barre",
                    .ukrainian: "Стовпці"
                ],
                .autoEQCurve: [
                    .english: "Curve",
                    .italian: "Curva",
                    .ukrainian: "Крива"
                ],
                .autoEQPreamp: [
                    .english: "Preamp",
                    .italian: "Preamp",
                    .ukrainian: "Підсилювач"
                ],
                .autoEQApplyToEQ: [
                    .english: "Apply to EQ",
                    .italian: "Applica a EQ",
                    .ukrainian: "Застосувати до EQ"
                ],
                .autoEQBypass: [
                    .english: "Bypass",
                    .italian: "Bypass",
                    .ukrainian: "Обійти"
                ],
                .autoEQEnable: [
                    .english: "Enable",
                    .italian: "Abilita",
                    .ukrainian: "Увімкнути"
                ],
                .autoEQApplyBands: [
                    .english: "Apply %d bands",
                    .italian: "Applica %d bande",
                    .ukrainian: "Застосувати %d смуг"
                ],
                .autoEQEQOn: [
                    .english: "EQ ON",
                    .italian: "EQ ON",
                    .ukrainian: "EQ УВІМК."
                ],
                .autoEQEQOff: [
                    .english: "EQ OFF",
                    .italian: "EQ OFF",
                    .ukrainian: "EQ ВИМК."
                ],
                .autoEQBassBoost: [
                    .english: "Bass Boost",
                    .italian: "Potenziamento Bassi",
                    .ukrainian: "Підсилення басів"
                ],
                .autoEQRemoveFromFavorites: [
                    .english: "Remove from favorites",
                    .italian: "Rimuovi dai preferiti",
                    .ukrainian: "Видалити з обраних"
                ],
                .autoEQAddToFavorites: [
                    .english: "Add to favorites",
                    .italian: "Aggiungi ai preferiti",
                    .ukrainian: "Додати до обраних"
                ],
                .searchHeadphonesModel: [
                    .english: "Search headphones model...",
                    .italian: "Cerca modello cuffie...",
                    .ukrainian: "Пошук моделі навушників..."
                ],

                // Visualizer
                .visualizerTitle: [
                    .english: "Visualizer",
                    .italian: "Visualizzatore",
                    .ukrainian: "Візуалізатор"
                ],
                .visualizerStyleColors: [
                    .english: "Style • Colors • Sensitivity",
                    .italian: "Stile • Colori • Sensibilità",
                    .ukrainian: "Стиль • Кольори • Чутливість"
                ],
                .visualizerStyle: [
                    .english: "Style",
                    .italian: "Stile",
                    .ukrainian: "Стиль"
                ],
                .visualizerSpectrum: [
                    .english: "Spectrum",
                    .italian: "Spettro",
                    .ukrainian: "Спектр"
                ],
                .visualizerWaveform: [
                    .english: "Waveform",
                    .italian: "Forma d'onda",
                    .ukrainian: "Хвиля"
                ],
                .visualizerParticles: [
                    .english: "Particles",
                    .italian: "Particelle",
                    .ukrainian: "Частинки"
                ],
                .visualizerPsychedelic: [
                    .english: "Psychedelic",
                    .italian: "Psichedelico",
                    .ukrainian: "Психоделічний"
                ],
                .visualizerIntensity: [
                    .english: "Intensity",
                    .italian: "Intensità",
                    .ukrainian: "Інтенсивність"
                ],
                .visualizerPreview: [
                    .english: "Preview",
                    .italian: "Anteprima",
                    .ukrainian: "Попередній перегляд"
                ],
                .visualizerActive: [
                    .english: "Active",
                    .italian: "Attivo",
                    .ukrainian: "Активний"
                ],
                .visualizerInactive: [
                    .english: "Inactive",
                    .italian: "Inattivo",
                    .ukrainian: "Неактивний"
                ],
                .noAudioSignal: [
                    .english: "No Audio Signal",
                    .italian: "Nessun Segnale Audio",
                    .ukrainian: "Немає аудіо сигналу"
                ],
                .startPlaybackToVisualize: [
                    .english: "Start playback to see visualization",
                    .italian: "Avvia la riproduzione per vedere la visualizzazione",
                    .ukrainian: "Почніть відтворення для візуалізації"
                ],

                // EQ Startup Behavior
                .eqStartupBehavior: [
                    .english: "EQ Startup Behavior",
                    .italian: "Comportamento Avvio EQ",
                    .ukrainian: "Поведінка EQ при запуску"
                ],
                .eqStartupDesc: [
                    .english: "Choose how SystemEQ should behave when launched",
                    .italian: "Scegli come SystemEQ dovrebbe comportarsi all'avvio",
                    .ukrainian: "Оберіть, як SystemEQ повинен поводитися при запуску"
                ],
                .eqStartupRemember: [
                    .english: "Restore Last State",
                    .italian: "Ripristina Ultimo Stato",
                    .ukrainian: "Відновити останній стан"
                ],
                .eqStartupRestorePreset: [
                    .english: "Restore Preset, EQ Off",
                    .italian: "Ripristina Preset, EQ Off",
                    .ukrainian: "Відновити пресет, EQ вимк"
                ],
                .eqStartupStartClean: [
                    .english: "Start Clean",
                    .italian: "Inizia Pulito",
                    .ukrainian: "Почати з чистого аркуша"
                ],
                .eqStartupRememberDesc: [
                    .english: "Restore last preset and EQ on/off state from previous session",
                    .italian: "Ripristina l'ultimo preset e lo stato EQ on/off dalla sessione precedente",
                    .ukrainian: "Відновити останній пресет та стан EQ з попередньої сесії"
                ],
                .eqStartupRestorePresetDesc: [
                    .english: "Load last preset but keep EQ disabled until you enable it manually",
                    .italian: "Carica l'ultimo preset ma mantieni EQ disabilitato finché non lo abiliti manualmente",
                    .ukrainian: "Завантажити останній пресет, але залишити EQ вимкненим доки не увімкнете вручну"
                ],
                .eqStartupStartCleanDesc: [
                    .english: "Start with no preset loaded and EQ disabled (flat response)",
                    .italian: "Inizia senza preset caricato e EQ disabilitato (risposta piatta)",
                    .ukrainian: "Почати без завантажених пресетів та з вимкненим EQ (пласка відповідь)"
                ],
                .eqStartupBehaviorTitle: [
                    .english: "EQ Startup Behavior",
                    .italian: "Comportamento Avvio EQ",
                    .ukrainian: "Поведінка EQ при запуску"
                ],
                .eqStartupBehaviorDesc: [
                    .english: "Choose how SystemEQ should behave when launched",
                    .italian: "Scegli come SystemEQ dovrebbe comportarsi all'avvio",
                    .ukrainian: "Оберіть, як SystemEQ повинен поводитися при запуску"
                ],

                // EQ Database
                .eqDatabase: [
                    .english: "EQ Database",
                    .italian: "Database EQ",
                    .ukrainian: "База даних EQ"
                ],
                .databaseVersion: [
                    .english: "Version",
                    .italian: "Versione",
                    .ukrainian: "Версія"
                ],
                .databaseHeadphones: [
                    .english: "Headphones",
                    .italian: "Cuffie",
                    .ukrainian: "Навушники"
                ],
                .databasePresets: [
                    .english: "Presets",
                    .italian: "Preset",
                    .ukrainian: "Пресети"
                ],
                .databaseSize: [
                    .english: "Size",
                    .italian: "Dimensione",
                    .ukrainian: "Розмір"
                ],
                .checkForUpdates: [
                    .english: "Check for Updates",
                    .italian: "Verifica Aggiornamenti",
                    .ukrainian: "Перевірити оновлення"
                ],
                .downloadUpdate: [
                    .english: "Download Update",
                    .italian: "Scarica Aggiornamento",
                    .ukrainian: "Завантажити оновлення"
                ],
                .databaseUpToDate: [
                    .english: "Database is up to date",
                    .italian: "Database aggiornato",
                    .ukrainian: "База даних актуальна"
                ],
                .databaseUpdateAvailable: [
                    .english: "Update available",
                    .italian: "Aggiornamento disponibile",
                    .ukrainian: "Доступне оновлення"
                ],
                .databaseCheckFailed: [
                    .english: "Could not check for updates",
                    .italian: "Impossibile verificare aggiornamenti",
                    .ukrainian: "Не вдалося перевірити оновлення"
                ],

                // Personalized Calibration
                .personalizedHearingProfile: [
                    .english: "Personalized Hearing Profile",
                    .italian: "Profilo Uditivo Personalizzato",
                    .ukrainian: "Персоналізований слуховий профіль"
                ],
                .personalizedTitle: [
                    .english: "Personalized",
                    .italian: "Personalizzato",
                    .ukrainian: "Персоналізований"
                ],
                .personalizedDesc: [
                    .english: "Create your unique hearing signature for perfect headphone calibration",
                    .italian: "Crea la tua firma uditiva unica per una calibrazione perfetta delle cuffie",
                    .ukrainian: "Створіть унікальний слуховий профіль для ідеальної калібрування навушників"
                ],
                .personalizedSubtitle: [
                    .english: "Get a hearing profile tailored specifically to you",
                    .italian: "Ottieni un profilo uditivo personalizzato appositamente per te",
                    .ukrainian: "Отримайте слуховий профіль, розроблений спеціально для вас"
                ],
                .premium: [
                    .english: "PREMIUM",
                    .italian: "PREMIUM",
                    .ukrainian: "ПРЕМІУМ"
                ],
                .unlockPersonalizedCalibration: [
                    .english: "Unlock Personalized Calibration",
                    .italian: "Sblocca Calibrazione Personalizzata",
                    .ukrainian: "Розблокувати персоналізовану калібрування"
                ],
                .unlockForPrice: [
                    .english: "Unlock for $9.99",
                    .italian: "Sblocca per €9,99",
                    .ukrainian: "Розблокувати за $9.99"
                ],
                .selectTestType: [
                    .english: "Select Test Type",
                    .italian: "Seleziona Tipo Test",
                    .ukrainian: "Оберіть тип тесту"
                ],
                .yourProfiles: [
                    .english: "Your Profiles",
                    .italian: "I Tuoi Profili",
                    .ukrainian: "Ваші профілі"
                ],
                .adjustUntilEquallyLoud: [
                    .english: "Adjust until it sounds equally loud",
                    .italian: "Regola fino a quando non suona ugualmente forte",
                    .ukrainian: "Налаштуйте, доки не звучить однаково гучно"
                ],
                .quieter: [
                    .english: "Quieter",
                    .italian: "Più piano",
                    .ukrainian: "Тихіше"
                ],
                .louder: [
                    .english: "Louder",
                    .italian: "Più forte",
                    .ukrainian: "Гучніше"
                ],
                .startCalibration: [
                    .english: "Start Calibration",
                    .italian: "Inizia Calibrazione",
                    .ukrainian: "Почати калібрування"
                ],
                .unlockPersonalizedHearingProfile: [
                    .english: "Unlock Personalized Hearing Profile",
                    .italian: "Sblocca Profilo Uditivo Personalizzato",
                    .ukrainian: "Розблокувати персоналізований слуховий профіль"
                ],
                .nameYourProfile: [
                    .english: "Name Your Profile",
                    .italian: "Nome del Profilo",
                    .ukrainian: "Назвіть ваш профіль"
                ],
                .highPrecision: [
                    .english: "High Precision",
                    .italian: "Alta Precisione",
                    .ukrainian: "Висока точність"
                ],
                .smartLearning: [
                    .english: "Smart Learning",
                    .italian: "Apprendimento Intelligente",
                    .ukrainian: "Розумне навчання"
                ],
                .universal: [
                    .english: "Universal",
                    .italian: "Universale",
                    .ukrainian: "Універсальний"
                ],
                .oneTimePurchase: [
                    .english: "One-time purchase",
                    .italian: "Acquisto una tantum",
                    .ukrainian: "Разова покупка"
                ],
                .professionalGradeCalibration: [
                    .english: "Get professional-grade headphone calibration tailored to your unique hearing.",
                    .italian: "Ottieni una calibrazione professionale per cuffie personalizzata per il tuo udito unico.",
                    .ukrainian: "Отримайте професійну калібрування навушників, адаптовану до вашого унікального слуху."
                ],
                .price: [
                    .english: "$9.99",
                    .italian: "9.99€",
                    .ukrainian: "9.99$"
                ],

                // Subjective Room Tuning (renamed from Room Calibration)
                .subjectiveRoomTuning: [
                    .english: "Subjective Room Tuning",
                    .italian: "Regolazione Soggettiva Stanza",
                    .ukrainian: "Суб'єктивне налаштування кімнати"
                ],
                .subjectiveRoomTuningDesc: [
                    .english: "Personal room tuning based on your hearing",
                    .italian: "Regolazione personale della stanza basata sul tuo udito",
                    .ukrainian: "Персональне налаштування кімнати на основі вашого слуху"
                ],
                .subjectiveRoomTuningDisclaimerTitle: [
                    .english: "⚠️ Important Limitations",
                    .italian: "⚠️ Limitazioni Importanti",
                    .ukrainian: "⚠️ Важливі обмеження"
                ],
                .subjectiveRoomTuningDisclaimer: [
                    .english: "This is NOT professional room correction. Results depend on your hearing, room acoustics, and listening position. For accurate room measurement, use a calibrated microphone. This tool helps you tune the sound to YOUR personal preference.",
                    .italian: "Questa NON è una correzione professionale della stanza. I risultati dipendono dal tuo udito, dall'acustica della stanza e dalla posizione di ascolto. Per una misurazione accurata della stanza, usa un microfono calibrato. Questo strumento ti aiuta a regolare il suono secondo le TUE preferenze personali.",
                    .ukrainian: "Це НЕ професійна корекція кімнати. Результати залежать від вашого слуху, акустики кімнати та позиції прослуховування. Для точного вимірювання кімнати використовуйте калібрований мікрофон. Цей інструмент допомагає налаштувати звук під ВАШІ особисті вподобання."
                ],
                .sineSweepMethod: [
                    .english: "Sine Sweep Method",
                    .italian: "Metodo Sine Sweep",
                    .ukrainian: "Метод Sine Sweep"
                ],
                .stepOne: [
                    .english: "1️⃣",
                    .italian: "1️⃣",
                    .ukrainian: "1️⃣"
                ],

                // Resonance Finder (Sine Sweep tool)
                .resonanceFinder: [
                    .english: "Resonance Finder",
                    .italian: "Trova Risonanze",
                    .ukrainian: "Пошук резонансів"
                ],
                .resonanceFinderDesc: [
                    .english: "Identify room resonances with Sine Sweep",
                    .italian: "Identifica le risonanze della stanza con Sine Sweep",
                    .ukrainian: "Виявлення резонансів кімнати за допомогою Sine Sweep"
                ],
                .resonanceFinderSubtitle: [
                    .english: "Listen for booming or ringing frequencies",
                    .italian: "Ascolta le frequenze che rimbombano o risuonano",
                    .ukrainian: "Слухайте частоти, що гудять або дзвенять"
                ],
                .resonanceStep1: [
                    .english: "Play sine sweep through your speakers",
                    .italian: "Riproduci il sine sweep attraverso gli altoparlanti",
                    .ukrainian: "Відтворіть синусоїдальну розгортку через динаміки"
                ],
                .resonanceStep2: [
                    .english: "Listen for frequencies that boom or ring",
                    .italian: "Ascolta le frequenze che rimbombano o risuonano",
                    .ukrainian: "Слухайте частоти, які гудять або дзвенять"
                ],
                .resonanceStep3: [
                    .english: "Mark problematic frequencies for reference",
                    .italian: "Segna le frequenze problematiche per riferimento",
                    .ukrainian: "Позначте проблемні частоти для довідки"
                ],
                .resonanceNote: [
                    .english: "This tool helps you **identify** resonances. To fix them, use acoustic treatment or the Subjective Room Tuning feature.",
                    .italian: "Questo strumento ti aiuta a **identificare** le risonanze. Per correggerle, usa il trattamento acustico o la funzione Sintonizzazione Soggettiva della Stanza.",
                    .ukrainian: "Цей інструмент допомагає **виявити** резонанси. Щоб їх виправити, використовуйте акустичну обробку або функцію Суб'єктивне налаштування кімнати."
                ],
                .startSweep: [
                    .english: "Start Sweep",
                    .italian: "Avvia Sweep",
                    .ukrainian: "Почати розгортку"
                ],
                .stopSweep: [
                    .english: "Stop Sweep",
                    .italian: "Ferma Sweep",
                    .ukrainian: "Зупинити розгортку"
                ],
                .commonProblemFrequencies: [
                    .english: "Common problem frequencies in rooms (bass region)",
                    .italian: "Frequenze problematiche comuni nelle stanze (regione bassi)",
                    .ukrainian: "Типові проблемні частоти в кімнатах (басовий діапазон)"
                ],
                .playSweepHint: [
                    .english: "Play the sweep and mark frequencies that sound too loud or boomy",
                    .italian: "Riproduci lo sweep e segna le frequenze che suonano troppo forti o rimbombanti",
                    .ukrainian: "Відтворіть розгортку і позначте частоти, які звучать занадто гучно або гудять"
                ],

                // Setup Assistant
                .setupRequired: [
                    .english: "Setup Required",
                    .italian: "Configurazione Richiesta",
                    .ukrainian: "Потребує налаштування"
                ],
                .systemDiagnostics: [
                    .english: "System Diagnostics",
                    .italian: "Diagnostica del Sistema",
                    .ukrainian: "Діагностика системи"
                ],
                .lastCheck: [
                    .english: "Last check: %@ ago",
                    .italian: "Ultimo controllo: %@ fa",
                    .ukrainian: "Остання перевірка: %@ тому"
                ],
                .blackHoleInstallation: [
                    .english: "BlackHole Installation",
                    .italian: "Installazione BlackHole",
                    .ukrainian: "Встановлення BlackHole"
                ],
                .ago: [
                    .english: "ago",
                    .italian: "fa",
                    .ukrainian: "тому"
                ],
                .checkingYourSystem: [
                    .english: "Checking Your System",
                    .italian: "Controllo del Sistema",
                    .ukrainian: "Перевірка вашої системи"
                ],
                .installBlackHole: [
                    .english: "Install BlackHole",
                    .italian: "Installa BlackHole",
                    .ukrainian: "Встановити BlackHole"
                ],
                .usedByThousands: [
                    .english: "Used by thousands of audio professionals",
                    .italian: "Utilizzato da migliaia di professionisti audio",
                    .ukrainian: "Використовується тисячами аудіо професіоналів"
                ],
                .easyToUninstall: [
                    .english: "Easy to Uninstall",
                    .italian: "Facile da Disinstallare",
                    .ukrainian: "Легко видалити"
                ],
                .canBeRemovedAnytime: [
                    .english: "Can be removed anytime from System Settings",
                    .italian: "Può essere rimosso in qualsiasi momento dalle Impostazioni di Sistema",
                    .ukrainian: "Можна видалити в будь-який час через Системні налаштування"
                ],
                .configureSystemAudio: [
                    .english: "Configure System Audio",
                    .italian: "Configura Audio di Sistema",
                    .ukrainian: "Налаштувати системне аудіо"
                ],
                .testAudioRouting: [
                    .english: "Test Audio Routing",
                    .italian: "Test Routing Audio",
                    .ukrainian: "Тест маршрутизації аудіо"
                ],
                .systemeqReady: [
                    .english: "SystemEQ is ready to use",
                    .italian: "SystemEQ è pronto per l'uso",
                    .ukrainian: "SystemEQ готовий до використання"
                ],

                // Common UI
                .freeOpenSource: [
                    .english: "Free & Open-Source",
                    .italian: "Gratuito & Open-Source",
                    .ukrainian: "Безкоштовний та з відкритим кодом"
                ],
                .mitLicense: [
                    .english: "MIT License, 10,000+ GitHub stars",
                    .italian: "Licenza MIT, 10.000+ stelle su GitHub",
                    .ukrainian: "Ліцензія MIT, 10,000+ зірок на GitHub"
                ],
                .safeTrusted: [
                    .english: "Safe & Trusted",
                    .italian: "Sicuro & Affidabile",
                    .ukrainian: "Безпечний та надійний"
                ],
                .canBeRemovedAnytimeDesc: [
                    .english: "Can be removed anytime from System Settings",
                    .italian: "Può essere rimosso in qualsiasi momento dalle Impostazioni di Sistema",
                    .ukrainian: "Можна видалити в будь-який час через Системні налаштування"
                ],
                .installationSteps: [
                    .english: "Installation Steps:",
                    .italian: "Passaggi di installazione:",
                    .ukrainian: "Кроки встановлення:"
                ],
                .setBlackHoleAsSystemOutput: [
                    .english: "Set BlackHole as your system output device so SystemEQ can process all audio.",
                    .italian: "Imposta BlackHole come dispositivo di uscita di sistema in modo che SystemEQ possa elaborare tutto l'audio.",
                    .ukrainian: "Встановіть BlackHole як пристрій виводу системи, щоб SystemEQ міг обробляти все аудіо."
                ],
                .currentSystemOutput: [
                    .english: "Current System Output:",
                    .italian: "Uscita di sistema attuale:",
                    .ukrainian: "Поточний системний вивід:"
                ],
                .configurationSteps: [
                    .english: "Configuration Steps:",
                    .italian: "Passaggi di configurazione:",
                    .ukrainian: "Кроки налаштування:"
                ],
                .verifyAudioRouting: [
                    .english: "Let's verify that audio routing is working correctly.",
                    .italian: "Verifichiamo che il routing audio funzioni correttamente.",
                    .ukrainian: "Перевіримо, чи правильно працює маршрутизація аудіо."
                ],
                .troubleshooting: [
                    .english: "Troubleshooting:",
                    .italian: "Risoluzione problemi:",
                    .ukrainian: "Вирішення проблем:"
                ],
                .setupComplete: [
                    .english: "Setup Complete!",
                    .italian: "Configurazione completata!",
                    .ukrainian: "Налаштування завершено!"
                ],

                // Calibration
                .calibration31BandsWarning: [
                    .english: "31 bands = ~15 minutes of pure time! 🥱\n\nMaybe better to start with 10 bands?\nThey give 90% result in 5 minutes.",
                    .italian: "31 bande = ~15 minuti di tempo puro! 🥱\n\nForse è meglio iniziare con 10 bande?\nDanno il 90% del risultato in 5 minuti.",
                    .ukrainian: "31 смуга = ~15 хвилин чистого часу! 🥱\n\nМожливо, краще почати з 10 смуг?\nВони дають 90% результату за 5 хвилин."
                ],
                .calibration31BandsFinalWarning: [
                    .english: "Last chance to reconsider!\n\n31 bands is a real marathon. 🏃‍♂️\nMake coffee ☕️ and be patient.\n\nOr just choose 10 bands and get great results in 5 minutes! 😊",
                    .italian: "Ultima occasione per ripensarci!\n\n31 bande è una vera maratona. 🏃‍♂️\nPrepara il caffè ☕️ e sii paziente.\n\nOppure scegli 10 bande e ottieni ottimi risultati in 5 minuti! 😊",
                    .ukrainian: "Останній шанс передумати!\n\n31 смуги - це справжній марафон. 🏃‍♂️\nЗробіть каву ☕️ і будьте терплячими.\n\nАбо просто оберіть 10 смуг і отримайте чудові результати за 5 хвилин! 😊"
                ],
                .deleteProfileConfirmation: [
                    .english: "Are you sure you want to delete '%@'?",
                    .italian: "Sei sicuro di voler eliminare '%@'?",
                    .ukrainian: "Ви впевнені, що хочете видалити '%@'?"
                ],
                .calibrationTitle: [
                    .english: "Calibration",
                    .italian: "Calibrazione",
                    .ukrainian: "Калібрування"
                ],
                .calibrationSubtitle: [
                    .english: "Equal Loudness • Speaker & Room Compensation",
                    .italian: "Equal Loudness • Compensazione Altoparlanti & Stanza",
                    .ukrainian: "Рівна гучність • Компенсація Колонок та Кімнати"
                ],
                .equalLoudnessCalibration: [
                    .english: "Equal Loudness Calibration",
                    .italian: "Calibrazione Equal Loudness",
                    .ukrainian: "Калібрування рівної гучності"
                ],
                .calibrationDescription: [
                    .english: "Calibration Description",
                    .italian: "Descrizione Calibrazione",
                    .ukrainian: "Опис калібрування"
                ],
                .calibrationImportantNote: [
                    .english: "Important Note",
                    .italian: "Nota Importante",
                    .ukrainian: "Важлива примітка"
                ],
                .calibrationWillImprove: [
                    .english: "Calibration will improve:",
                    .italian: "La calibrazione migliorerà:",
                    .ukrainian: "Калібрування покращить:"
                ],
                .calibrationWillImprove1: [
                    .english: "• Frequency response accuracy",
                    .italian: "• Accuratezza risposta in frequenza",
                    .ukrainian: "• Точність частотної характеристики"
                ],
                .calibrationWillImprove2: [
                    .english: "• Speaker and room interaction",
                    .italian: "• Interazione altoparlanti e stanza",
                    .ukrainian: "• Взаємодію колонок та кімнати"
                ],
                .calibrationWillImprove3: [
                    .english: "• Overall sound quality",
                    .italian: "• Qualità audio generale",
                    .ukrainian: "• Загальну якість звуку"
                ],
                .calibrationWillImprove4: [
                    .english: "• Listening experience",
                    .italian: "• Esperienza di ascolto",
                    .ukrainian: "• Враження від прослуховування"
                ],
                .calibrationWontFix: [
                    .english: "Calibration won't fix:",
                    .italian: "La calibrazione non risolverà:",
                    .ukrainian: "Калібрування не виправить:"
                ],
                .calibrationWontFix1: [
                    .english: "• Poor source quality",
                    .italian: "• Scarsa qualità sorgente",
                    .ukrainian: "• Погану якість джерела"
                ],
                .calibrationWontFix2: [
                    .english: "• Damaged equipment",
                    .italian: "• Attrezzatura danneggiata",
                    .ukrainian: "• Пошкоджене обладнання"
                ],
                .calibrationWontFix3: [
                    .english: "• Room acoustics completely",
                    .italian: "• Acustica della stanza completamente",
                    .ukrainian: "• Акустику кімнати повністю"
                ],
                .calibrationWontFix4: [
                    .english: "• Personal preference",
                    .italian: "• Preferenza personale",
                    .ukrainian: "• Особисті переваги"
                ],
                .calibrationForFullResult: [
                    .english: "For full results:",
                    .italian: "Per risultati completi:",
                    .ukrainian: "Для повного результату:"
                ],
                .calibrationMethodPrinciple: [
                    .english: "Method Principle",
                    .italian: "Principio del Metodo",
                    .ukrainian: "Принцип методу"
                ],
                .calibrationMethodDescription: [
                    .english: "Method Description",
                    .italian: "Descrizione del Metodo",
                    .ukrainian: "Опис методу"
                ],
                .calibrationStep1: [
                    .english: "Step 1",
                    .italian: "Passo 1",
                    .ukrainian: "Крок 1"
                ],
                .calibrationStep1Desc: [
                    .english: "Step 1 Description",
                    .italian: "Descrizione Passo 1",
                    .ukrainian: "Опис кроку 1"
                ],
                .calibrationStep2: [
                    .english: "Step 2",
                    .italian: "Passo 2",
                    .ukrainian: "Крок 2"
                ],
                .calibrationStep2Desc: [
                    .english: "Step 2 Description",
                    .italian: "Descrizione Passo 2",
                    .ukrainian: "Опис кроку 2"
                ],
                .calibrationStep3: [
                    .english: "Step 3",
                    .italian: "Passo 3",
                    .ukrainian: "Крок 3"
                ],
                .calibrationStep3Desc: [
                    .english: "Step 3 Description",
                    .italian: "Descrizione Passo 3",
                    .ukrainian: "Опис кроку 3"
                ],
                .calibrationStep4: [
                    .english: "Step 4",
                    .italian: "Passo 4",
                    .ukrainian: "Крок 4"
                ],
                .calibrationStep4Desc: [
                    .english: "Step 4 Description",
                    .italian: "Descrizione Passo 4",
                    .ukrainian: "Опис кроку 4"
                ],

                // BlackHole Setup
                .blackHoleNotInstalled: [
                    .english: "BlackHole is not installed",
                    .italian: "BlackHole non è installato",
                    .ukrainian: "BlackHole не встановлено"
                ],
                .systemeqRequiresBlackHole: [
                    .english: "SystemEQ requires BlackHole",
                    .italian: "SystemEQ richiede BlackHole",
                    .ukrainian: "SystemEQ потребує BlackHole"
                ],
                .blackHoleFreeOpenSource: [
                    .english: "BlackHole is free and open-source",
                    .italian: "BlackHole è gratuito e open-source",
                    .ukrainian: "BlackHole - безкоштовний з відкритим кодом"
                ],
                .whatIsBlackHole: [
                    .english: "What is BlackHole?",
                    .italian: "Cos'è BlackHole?",
                    .ukrainian: "Що таке BlackHole?"
                ],

                // UI Elements
                .launchAtLoginEmoji: [
                    .english: "🚀",
                    .italian: "🚀",
                    .ukrainian: "🚀"
                ],
                .supportThankYouEmoji: [
                    .english: "☕",
                    .italian: "☕",
                    .ukrainian: "☕"
                ],
                .setupNow: [
                    .english: "Setup Now",
                    .italian: "Configura Ora",
                    .ukrainian: "Налаштувати зараз"
                ],
                .blackHoleNotInstalledShort: [
                    .english: "BlackHole not installed",
                    .italian: "BlackHole non installato",
                    .ukrainian: "BlackHole не встановлено"
                ],

                // Room Calibration
                .findRoomResonances: [
                    .english: "Find room resonances with sine sweep test",
                    .italian: "Trova le risonanze della stanza con test sine sweep",
                    .ukrainian: "Знайдіть резонанси кімнати за допомогою sine sweep тесту"
                ],
                .startSineSweepAndListen: [
                    .english: "Start sine sweep and listen carefully",
                    .italian: "Avvia il sine sweep e ascolta attentamente",
                    .ukrainian: "Запустіть sine sweep та слухайте уважно"
                ],
                .markFrequenciesThatBoomOrRing: [
                    .english: "Mark frequencies that 'boom' or 'ring'",
                    .italian: "Segna le frequenze che 'booming' o 'ringing'",
                    .ukrainian: "Позначте частоти, які 'гудуть' або 'дзвенять'"
                ],
                .applyNotchFilters: [
                    .english: "Apply notch filters to suppress resonances",
                    .italian: "Applica filtri notch per sopprimere le risonanze",
                    .ukrainian: "Застосуйте notch фільтри для придушення резонансів"
                ],
                .testWithMusic: [
                    .english: "Test with music to verify improvement",
                    .italian: "Testa con la musica per verificare il miglioramento",
                    .ukrainian: "Перевірте з музикою для підтвердження покращення"
                ],
                .currentFrequency: [
                    .english: "Current Frequency",
                    .italian: "Frequenza Corrente",
                    .ukrainian: "Поточна частота"
                ],
                .sweepInProgress: [
                    .english: "🔊 Sweep in progress - listen for peaks!",
                    .italian: "🔊 Sweep in corso - ascolta i picchi!",
                    .ukrainian: "🔊 Sweep виконується - слухайте піки!"
                ],
                .sweepSpeed: [
                    .english: "Sweep Speed",
                    .italian: "Velocità Sweep",
                    .ukrainian: "Швидкість sweep"
                ],
                .markResonance: [
                    .english: "Mark Resonance",
                    .italian: "Segna Risonanza",
                    .ukrainian: "Позначити резонанс"
                ],
                .quickTestCommon: [
                    .english: "Quick Test - Common Problem Frequencies",
                    .italian: "Test Rapido - Frequenze Problematiche Comuni",
                    .ukrainian: "Швидкий тест - Типові проблемні частоти"
                ],
                .manualFrequencyTest: [
                    .english: "Manual Frequency Test",
                    .italian: "Test Frequenza Manuale",
                    .ukrainian: "Ручний тест частоти"
                ],
                .testSpecificFrequencies: [
                    .english: "Test specific frequencies manually and add resonances",
                    .italian: "Testa frequenze specifiche manualmente e aggiungi risonanze",
                    .ukrainian: "Тестуйте конкретні частоти вручну та додавайте резонанси"
                ],
                .frequency: [
                    .english: "Frequency",
                    .italian: "Frequenza",
                    .ukrainian: "Частота"
                ],
                .sineSweep: [
                    .english: "Sine Sweep",
                    .italian: "Sine Sweep",
                    .ukrainian: "Sine Sweep"
                ],
                .manual: [
                    .english: "Manual",
                    .italian: "Manuale",
                    .ukrainian: "Вручну"
                ],
                .tuningTab: [
                    .english: "Tuning",
                    .italian: "Regolazione",
                    .ukrainian: "Налаштування"
                ],
                .notchFilters: [
                    .english: "Notch Filters",
                    .italian: "Filtri Notch",
                    .ukrainian: "Notch фільтри"
                ],
                .abTest: [
                    .english: "A/B Test",
                    .italian: "Test A/B",
                    .ukrainian: "A/B тест"
                ],
                .addResonance: [
                    .english: "Add Resonance",
                    .italian: "Aggiungi Risonanza",
                    .ukrainian: "Додати резонанс"
                ],
                .resonanceFrequency: [
                    .english: "Resonance Frequency",
                    .italian: "Frequenza Risonanza",
                    .ukrainian: "Частота резонансу"
                ],
                .severity: [
                    .english: "Severity",
                    .italian: "Severità",
                    .ukrainian: "Рівень"
                ],
                .mild: [
                    .english: "Mild",
                    .italian: "Leggero",
                    .ukrainian: "Легкий"
                ],
                .moderate: [
                    .english: "Moderate",
                    .italian: "Moderato",
                    .ukrainian: "Помірний"
                ],
                .severe: [
                    .english: "Severe",
                    .italian: "Severo",
                    .ukrainian: "Сильний"
                ],
                .extreme: [
                    .english: "Extreme",
                    .italian: "Estremo",
                    .ukrainian: "Дуже сильний"
                ],
                .addNotchFilter: [
                    .english: "Add Notch Filter",
                    .italian: "Aggiungi Filtro Notch",
                    .ukrainian: "Додати notch фільтр"
                ],
                .gain: [
                    .english: "Gain",
                    .italian: "Guadagno",
                    .ukrainian: "Підсилення"
                ],
                .qFactor: [
                    .english: "Q Factor",
                    .italian: "Fattore Q",
                    .ukrainian: "Фактор Q"
                ],
                .saveProfile: [
                    .english: "Save Profile",
                    .italian: "Salva Profilo",
                    .ukrainian: "Зберегти профіль"
                ],
                .profileName: [
                    .english: "Profile Name",
                    .italian: "Nome Profilo",
                    .ukrainian: "Назва профілю"
                ],
                .saveCalibrationProfile: [
                    .english: "Save Calibration Profile",
                    .italian: "Salva Profilo di Calibrazione",
                    .ukrainian: "Зберегти профіль калібрування"
                ],
                .compareOriginalVsFiltered: [
                    .english: "Compare Original vs Filtered",
                    .italian: "Confronta Originale vs Filtrato",
                    .ukrainian: "Порівняти оригінал з відфільтрованим"
                ],
                .hearingTestDifference: [
                    .english: "Hearing test - can you notice the difference?",
                    .italian: "Test uditivo - riesci a notare la differenza?",
                    .ukrainian: "Слуховий тест - помічаєте різницю?"
                ],
                .filtersActive: [
                    .english: "Filters Active",
                    .italian: "Filtri Attivi",
                    .ukrainian: "Фільтри активні"
                ],
                .noFiltersAdded: [
                    .english: "No filters added yet",
                    .italian: "Nessun filtro aggiunto ancora",
                    .ukrainian: "Фільтри ще не додано"
                ],
                .notchFilterDescription: [
                    .english: "Notch filters target specific problem frequencies",
                    .italian: "I filtri notch colpiscono frequenze problematiche specifiche",
                    .ukrainian: "Notch фільтри націлені на конкретні проблемні частоти"
                ],
                .resonanceDescription: [
                    .english: "Room resonances cause certain frequencies to sound louder",
                    .italian: "Le risonanze della stanza fanno sembrare alcune frequenze più alte",
                    .ukrainian: "Резонанси кімнати змушують певні частоти звучати гучніше"
                ],
                .roomCalibrationHelp: [
                    .english: "Room calibration helps identify and reduce room resonances that cause uneven bass response.",
                    .italian: "La calibrazione della stanza aiuta a identificare e ridurre le risonanze della stanza che causano una risposta dei bassi non uniforme.",
                    .ukrainian: "Калібрування кімнати допомагає виявити та зменшити резонанси, що викликають нерівномірний бас."
                ],
                .detectedResonances: [
                    .english: "Detected Resonances",
                    .italian: "Risonanze Rilevate",
                    .ukrainian: "Виявлені резонанси"
                ],
                .noResonancesDetected: [
                    .english: "No resonances detected yet. Use Sine Sweep to find problem frequencies.",
                    .italian: "Nessuna risonanza rilevata ancora. Usa lo Sweep Sinusoidale per trovare frequenze problematiche.",
                    .ukrainian: "Резонанси ще не виявлено. Використайте синусоїдний розгортання для пошуку проблемних частот."
                ],
                .playFrequency: [
                    .english: "Play {frequency} Hz",
                    .italian: "Riproduci {frequency} Hz",
                    .ukrainian: "Відтворити {frequency} Гц"
                ],
                .appliedNotchFilters: [
                    .english: "Applied Notch Filters",
                    .italian: "Filtri Notch Applicati",
                    .ukrainian: "Застосовані фільтри Notch"
                ],
                .noNotchFiltersApplied: [
                    .english: "No notch filters applied yet.",
                    .italian: "Nessun filtro notch applicato ancora.",
                    .ukrainian: "Фільтри notch ще не застосовані."
                ],
                .addFilter: [
                    .english: "Add Filter",
                    .italian: "Aggiungi Filtro",
                    .ukrainian: "Додати фільтр"
                ],
                .abComparison: [
                    .english: "A/B Comparison",
                    .italian: "Confronto A/B",
                    .ukrainian: "Порівняння A/B"
                ],
                .gainMatching: [
                    .english: "Gain Matching",
                    .italian: "Gain Matching",
                    .ukrainian: "Вирівнювання гучності"
                ],
                .gainMatchingDesc: [
                    .english: "Automatically compensates for volume differences so you can judge quality, not loudness.",
                    .italian: "Compensa automaticamente le differenze di volume in modo da poter giudicare la qualità, non la loudness.",
                    .ukrainian: "Автоматично компенсує різницю гучності, щоб ви могли оцінювати якість, а не гучність."
                ],
                .alternatingOriginalFiltered: [
                    .english: "Alternating: Original → Filtered",
                    .italian: "Alternanza: Originale → Filtrato",
                    .ukrainian: "Чергування: Оригінал → Відфільтрований"
                ],
                .howToUse: [
                    .english: "How to use",
                    .italian: "Come usare",
                    .ukrainian: "Як користуватися"
                ],
                .howToUseStep1: [
                    .english: "Use **Resonance Finder** to identify problem frequencies",
                    .italian: "Usa **Resonance Finder** per identificare le frequenze problematiche",
                    .ukrainian: "Використовуйте **Пошук резонансів** для виявлення проблемних частот"
                ],
                .howToUseStep2: [
                    .english: "Come back here to add notch filters for those frequencies",
                    .italian: "Torna qui per aggiungere filtri notch per quelle frequenze",
                    .ukrainian: "Поверніться сюди, щоб додати режекторні фільтри для цих частот"
                ],
                .howToUseStep3: [
                    .english: "Fine-tune filter settings to your preference",
                    .italian: "Regola le impostazioni del filtro secondo le tue preferenze",
                    .ukrainian: "Налаштуйте параметри фільтрів на свій смак"
                ],
                .howToUseStep4: [
                    .english: "Use A/B Test to compare before/after",
                    .italian: "Usa il test A/B per confrontare prima/dopo",
                    .ukrainian: "Використовуйте A/B тест для порівняння до/після"
                ],
                .clearAll: [
                    .english: "Clear All",
                    .italian: "Cancella tutto",
                    .ukrainian: "Очистити все"
                ],
                .useResonanceFinderHint: [
                    .english: "Use Resonance Finder or manually add frequencies below",
                    .italian: "Usa Resonance Finder o aggiungi manualmente le frequenze qui sotto",
                    .ukrainian: "Використовуйте Пошук резонансів або додайте частоти вручну нижче"
                ],
                .startABTest: [
                    .english: "Start A/B Test",
                    .italian: "Avvia test A/B",
                    .ukrainian: "Почати A/B тест"
                ],
                .stopABTest: [
                    .english: "Stop Comparison",
                    .italian: "Ferma confronto",
                    .ukrainian: "Зупинити порівняння"
                ],
                .userDetectedResonance: [
                    .english: "User-detected resonance",
                    .italian: "Risonanza rilevata dall'utente",
                    .ukrainian: "Резонанс, виявлений користувачем"
                ],
                .quickTest: [
                    .english: "Quick Test (5 min)",
                    .italian: "Test rapido (5 min)",
                    .ukrainian: "Швидкий тест (5 хв)"
                ],
                .standardTest: [
                    .english: "Standard Test (15 min)",
                    .italian: "Test standard (15 min)",
                    .ukrainian: "Стандартний тест (15 хв)"
                ],
                .extendedTest: [
                    .english: "Extended Test (30 min)",
                    .italian: "Test esteso (30 min)",
                    .ukrainian: "Розширений тест (30 хв)"
                ],
                .quickTestDesc: [
                    .english: "10 frequencies, basic calibration",
                    .italian: "10 frequenze, calibrazione base",
                    .ukrainian: "10 частот, базова калібрація"
                ],
                .standardTestDesc: [
                    .english: "31 frequencies, detailed calibration",
                    .italian: "31 frequenze, calibrazione dettagliata",
                    .ukrainian: "31 частота, детальна калібрація"
                ],
                .extendedTestDesc: [
                    .english: "Full spectrum, professional accuracy",
                    .italian: "Spettro completo, precisione professionale",
                    .ukrainian: "Повний спектр, професійна точність"
                ],
                .adaptsToHearing: [
                    .english: "Adapts to your unique hearing",
                    .italian: "Si adatta al tuo udito unico",
                    .ukrainian: "Адаптується до вашого слуху"
                ],
                .extendedFrequencyRange: [
                    .english: "Extended frequency range",
                    .italian: "Gamma di frequenze estesa",
                    .ukrainian: "Розширений діапазон частот"
                ],
                .improvesOverTime: [
                    .english: "Improves over time",
                    .italian: "Migliora nel tempo",
                    .ukrainian: "Покращується з часом"
                ],
                .worksWithAnyHeadphones: [
                    .english: "Works with any headphones",
                    .italian: "Funziona con qualsiasi cuffia",
                    .ukrainian: "Працює з будь-якими навушниками"
                ],
                .exampleProfileName: [
                    .english: "e.g., My Hearing Profile",
                    .italian: "es., Il mio profilo uditivo",
                    .ukrainian: "напр., Мій профіль слуху"
                ],
                .start: [
                    .english: "Start",
                    .italian: "Avvia",
                    .ukrainian: "Почати"
                ],

                // Personalized Calibration
                .tooQuiet: [
                    .english: "Too Quiet",
                    .italian: "Troppo Piano",
                    .ukrainian: "Занадто тихо"
                ],
                .justRight: [
                    .english: "Just Right",
                    .italian: "Giusto",
                    .ukrainian: "В нормі"
                ],
                .tooLoud: [
                    .english: "Too Loud",
                    .italian: "Troppo Alto",
                    .ukrainian: "Занадто гучно"
                ],
                .sessions: [
                    .english: "Sessions",
                    .italian: "Sessioni",
                    .ukrainian: "Сесії"
                ],
                .complete: [
                    .english: "Complete",
                    .italian: "Completo",
                    .ukrainian: "Завершено"
                ],

                // CalibrationView - Additional translations
                .equalLoudness: [
                    .english: "Equal Loudness",
                    .italian: "Equal Loudness",
                    .ukrainian: "Рівна гучність"
                ],
                .profiles: [
                    .english: "Profiles",
                    .italian: "Profili",
                    .ukrainian: "Профілі"
                ],
                .abCompare: [
                    .english: "A/B Compare",
                    .italian: "Confronto A/B",
                    .ukrainian: "Порівняння A/B"
                ],
                .chooseCalibrationMode: [
                    .english: "Choose Calibration Mode",
                    .italian: "Scegli Modalità Calibrazione",
                    .ukrainian: "Оберіть режим калібрування"
                ],
                .chooseCalibrationPrecision: [
                    .english: "Choose Calibration Precision",
                    .italian: "Scegli Precisione Calibrazione",
                    .ukrainian: "Оберіть точність калібрування"
                ],
                .bands10Time: [
                    .english: "10 Bands (5 min)",
                    .italian: "10 Bande (5 min)",
                    .ukrainian: "10 Смуг (5 хв)"
                ],
                .bands31Time: [
                    .english: "31 Bands (15 min)",
                    .italian: "31 Bande (15 min)",
                    .ukrainian: "31 Смуга (15 хв)"
                ],
                .recommended: [
                    .english: "✅ Recommended",
                    .italian: "✅ Consigliato",
                    .ukrainian: "✅ Рекомендовано"
                ],
                .advanced: [
                    .english: "⚠️ Advanced",
                    .italian: "⚠️ Avanzato",
                    .ukrainian: "⚠️ Для досвідчених"
                ],
                .forPerfectionists: [
                    .english: "🐌 For perfectionists",
                    .italian: "🐌 Per perfezionisti",
                    .ukrainian: "🐌 Для перфекціоністів"
                ],
                .step1SetReference: [
                    .english: "Step 1: Set Reference Level",
                    .italian: "Passo 1: Imposta Livello di Riferimento",
                    .ukrainian: "Крок 1: Встановіть референсний рівень"
                ],
                .step1SetReferenceDesc: [
                    .english: "Turn on the 1000 Hz tone and adjust to a comfortable listening volume",
                    .italian: "Accendi il tono da 1000 Hz e regola a un volume di ascolto confortevole",
                    .ukrainian: "Включіть тон 1000 Гц і налаштуйте комфортну гучність для слухання"
                ],
                .step1SetReferenceNote: [
                    .english: "This will be your reference - all other frequencies should sound equally loud",
                    .italian: "Questo sarà il tuo riferimento - tutte le altre frequenze dovrebbero suonare ugualmente forti",
                    .ukrainian: "Це буде ваш орієнтир - всі інші частоти повинні звучати так само гучно"
                ],
                .referenceFrequency: [
                    .english: "Reference Frequency",
                    .italian: "Frequenza di Riferimento",
                    .ukrainian: "Референсна частота"
                ],
                .volumeLevel: [
                    .english: "Volume Level",
                    .italian: "Livello Volume",
                    .ukrainian: "Рівень гучності"
                ],
                .quiet: [
                    .english: "Quiet",
                    .italian: "Silenzioso",
                    .ukrainian: "Тихо"
                ],
                .loud: [
                    .english: "Loud",
                    .italian: "Forte",
                    .ukrainian: "Гучно"
                ],
                .playReference: [
                    .english: "Play Reference",
                    .italian: "Riproduci Riferimento",
                    .ukrainian: "Включити референс"
                ],
                .stopReference: [
                    .english: "Stop",
                    .italian: "Ferma",
                    .ukrainian: "Зупинити"
                ],
                .listenCarefully: [
                    .english: "🎧 Listen for 2-3 seconds, close your eyes",
                    .italian: "🎧 Ascolta per 2-3 secondi, chiudi gli occhi",
                    .ukrainian: "🎧 Слухайте 2-3 секунди, закрийте очі"
                ],
                .howToSetupCorrectly: [
                    .english: "How to set up correctly:",
                    .italian: "Come configurare correttamente:",
                    .ukrainian: "Як правильно налаштувати:"
                ],
                .sitInUsualPlace: [
                    .english: "Sit in your usual listening position",
                    .italian: "Siediti nella tua posizione di ascolto abituale",
                    .ukrainian: "Сядьте у звичне місце прослуховування"
                ],
                .closeEyesForFocus: [
                    .english: "Close your eyes for better focus",
                    .italian: "Chiudi gli occhi per una migliore concentrazione",
                    .ukrainian: "Закрийте очі для кращої концентрації"
                ],
                .volumeShouldBeComfortable: [
                    .english: "Volume should be comfortable, not tiring",
                    .italian: "Il volume dovrebbe essere confortevole, non stancante",
                    .ukrainian: "Гучність має бути комфортною, не втомлювати"
                ],
                .rememberThisVolume: [
                    .english: "Remember this volume - it's your reference",
                    .italian: "Ricorda questo volume - è il tuo riferimento",
                    .ukrainian: "Запам'ятайте цю гучність - це ваш еталон"
                ],
                .continueCalibration: [
                    .english: "Continue Calibration",
                    .italian: "Continua Calibrazione",
                    .ukrainian: "Продовжити калібрування"
                ],
                .step2AdjustFrequencies: [
                    .english: "Step 2: Adjust Frequencies",
                    .italian: "Passo 2: Regola Frequenze",
                    .ukrainian: "Крок 2: Налаштування частот"
                ],
                .step2AdjustFrequenciesDesc: [
                    .english: "Adjust each frequency to sound as loud as 1000 Hz",
                    .italian: "Regola ogni frequenza per suonare forte come 1000 Hz",
                    .ukrainian: "Налаштуйте кожну частоту так, щоб вона звучала так само гучно як 1000 Гц"
                ],
                .currentFrequencyLabel: [
                    .english: "Current Frequency",
                    .italian: "Frequenza Corrente",
                    .ukrainian: "Поточна частота"
                ],
                .adjustToReferenceVolume: [
                    .english: "Adjust to reference 1000 Hz volume",
                    .italian: "Regola al volume di riferimento 1000 Hz",
                    .ukrainian: "Налаштуйте до гучності референсу 1000 Гц"
                ],
                .tipCloseEyes: [
                    .english: "Tip: close your eyes and compare by ear only",
                    .italian: "Suggerimento: chiudi gli occhi e confronta solo con l'udito",
                    .ukrainian: "Хитрість: закрийте очі і порівнюйте тільки на слух"
                ],
                .levelCorrection: [
                    .english: "Level Correction",
                    .italian: "Correzione Livello",
                    .ukrainian: "Корекція рівня"
                ],
                .quieter2: [
                    .english: "Quieter",
                    .italian: "Più silenzioso",
                    .ukrainian: "Тише"
                ],
                .louder2: [
                    .english: "Louder",
                    .italian: "Più forte",
                    .ukrainian: "Гучніше"
                ],
                .testingFrequency: [
                    .english: "Testing Frequency",
                    .italian: "Test Frequenza",
                    .ukrainian: "Тестування частоти"
                ],
                .testSignalType: [
                    .english: "Test Signal Type:",
                    .italian: "Tipo Segnale Test:",
                    .ukrainian: "Тип тестового сигналу:"
                ],
                .pinkNoise: [
                    .english: "Pink Noise",
                    .italian: "Rumore Rosa",
                    .ukrainian: "Pink Noise"
                ],
                .pureTone: [
                    .english: "Pure Tone",
                    .italian: "Tono Puro",
                    .ukrainian: "Pure Tone"
                ],
                .stopTest: [
                    .english: "Stop",
                    .italian: "Ferma",
                    .ukrainian: "Зупинити"
                ],
                .testFrequency: [
                    .english: "Test Frequency",
                    .italian: "Test Frequenza",
                    .ukrainian: "Тестувати частоту"
                ],
                .compareAlternating: [
                    .english: "Compare (Alternating)",
                    .italian: "Confronta (Alternato)",
                    .ukrainian: "Порівняти (чергування)"
                ],
                .stopComparison: [
                    .english: "Stop Comparison",
                    .italian: "Ferma Confronto",
                    .ukrainian: "Зупинити порівняння"
                ],
                .alternatingPattern: [
                    .english: "⏱ Alternating: 1000 Hz → Frequency → 1000 Hz",
                    .italian: "⏱ Alternanza: 1000 Hz → Frequenza → 1000 Hz",
                    .ukrainian: "⏱ Чергування: 1000 Гц → Частота → 1000 Гц"
                ],
                .howToAdjustCorrectly: [
                    .english: "How to adjust correctly:",
                    .italian: "Come regolare correttamente:",
                    .ukrainian: "Як правильно налаштовувати:"
                ],
                .pressTestFrequency: [
                    .english: "Press 'Test Frequency' - sound plays continuously",
                    .italian: "Premi 'Test Frequenza' - il suono viene riprodotto continuamente",
                    .ukrainian: "Натисніть 'Тестувати частоту' - звук грає безперервно"
                ],
                .moveSliderRealtime: [
                    .english: "Move slider in real-time to adjust volume",
                    .italian: "Muovi il cursore in tempo reale per regolare il volume",
                    .ukrainian: "Рухайте слайдер в реальному часі для налаштування гучності"
                ],
                .pressStopWhenDone: [
                    .english: "Press 'Stop' when finished",
                    .italian: "Premi 'Ferma' quando hai finito",
                    .ukrainian: "Натисніть 'Зупинити' коли завершите"
                ],
                .useCompareForAB: [
                    .english: "Use 'Compare' for A/B check with reference",
                    .italian: "Usa 'Confronta' per controllo A/B con riferimento",
                    .ukrainian: "Використовуйте 'Порівняти' для A/B перевірки з референсом"
                ],
                .progress: [
                    .english: "Progress:",
                    .italian: "Progresso:",
                    .ukrainian: "Прогрес:"
                ],
                .progressOf: [
                    .english: "of",
                    .italian: "di",
                    .ukrainian: "з"
                ],
                .previous: [
                    .english: "Previous",
                    .italian: "Precedente",
                    .ukrainian: "Попередня"
                ],
                .backToReference: [
                    .english: "Back to Reference",
                    .italian: "Torna al Riferimento",
                    .ukrainian: "Назад до референсу"
                ],
                .nextFrequency: [
                    .english: "Next",
                    .italian: "Successivo",
                    .ukrainian: "Наступна"
                ],
                .saveProfileButton: [
                    .english: "Save Profile",
                    .italian: "Salva Profilo",
                    .ukrainian: "Зберегти профіль"
                ],
                .howToApplyCalibration: [
                    .english: "📋 How to Apply Calibration",
                    .italian: "📋 Come Applicare la Calibrazione",
                    .ukrainian: "📋 Як застосувати калібровку"
                ],
                .saveCalibrationProfileStep: [
                    .english: "Save calibration profile",
                    .italian: "Salva profilo di calibrazione",
                    .ukrainian: "Збережіть профіль калібровки"
                ],
                .saveCalibrationProfileStepDesc: [
                    .english: "Complete the test and save the result",
                    .italian: "Completa il test e salva il risultato",
                    .ukrainian: "Пройдіть тест та збережіть результат"
                ],
                .activateProfileHere: [
                    .english: "Activate profile here",
                    .italian: "Attiva profilo qui",
                    .ukrainian: "Активуйте профіль тут"
                ],
                .activateProfileHereDesc: [
                    .english: "Press 'Activate' next to the profile",
                    .italian: "Premi 'Attiva' accanto al profilo",
                    .ukrainian: "Натисніть 'Activate' біля профілю"
                ],
                .enableEQInMainWindow: [
                    .english: "Enable EQ in main window",
                    .italian: "Abilita EQ nella finestra principale",
                    .ukrainian: "Увімкніть EQ в головному вікні"
                ],
                .enableEQInMainWindowDesc: [
                    .english: "Close this window and enable 'Enable EQ'",
                    .italian: "Chiudi questa finestra e abilita 'Abilita EQ'",
                    .ukrainian: "Закрийте це вікно та увімкніть 'Enable EQ'"
                ],
                .tipCalibrationWorksOnlyWithEQ: [
                    .english: "💡 Tip: Calibration only works when EQ is enabled in the main window!",
                    .italian: "💡 Suggerimento: La calibrazione funziona solo quando EQ è abilitato nella finestra principale!",
                    .ukrainian: "💡 Порада: Калібровка працює тільки коли увімкнений EQ в головному вікні!"
                ],
                .noCalibrationProfiles: [
                    .english: "No Calibration Profiles",
                    .italian: "Nessun Profilo di Calibrazione",
                    .ukrainian: "Немає профілів калібровки"
                ],
                .noCalibrationProfilesDesc: [
                    .english: "Complete Equal Loudness calibration to create your first profile",
                    .italian: "Completa la calibrazione Equal Loudness per creare il tuo primo profilo",
                    .ukrainian: "Пройдіть калібрування Equal Loudness, щоб створити перший профіль"
                ],
                .startCalibrationButton: [
                    .english: "Start Calibration",
                    .italian: "Inizia Calibrazione",
                    .ukrainian: "Почати калібрування"
                ],
                .active2: [
                    .english: "Active",
                    .italian: "Attivo",
                    .ukrainian: "Active"
                ],
                .activate: [
                    .english: "Activate",
                    .italian: "Attiva",
                    .ukrainian: "Activate"
                ],
                .abProfileComparison: [
                    .english: "A/B Profile Comparison",
                    .italian: "Confronto Profili A/B",
                    .ukrainian: "Порівняння профілів A/B"
                ],
                .profileA: [
                    .english: "Profile A",
                    .italian: "Profilo A",
                    .ukrainian: "Профіль A"
                ],
                .profileB: [
                    .english: "Profile B",
                    .italian: "Profilo B",
                    .ukrainian: "Профіль B"
                ],
                .compareWithCleanSound: [
                    .english: "Compare with Clean Sound",
                    .italian: "Confronta con Suono Pulito",
                    .ukrainian: "Порівняти з чистим звуком"
                ],
                .compareWithCleanSoundDesc: [
                    .english: "Listen to the original unprocessed audio to compare with calibrated profiles",
                    .italian: "Ascolta l'audio originale non elaborato per confrontare con i profili calibrati",
                    .ukrainian: "Слухайте оригінальне необроблене аудіо для порівняння з каліброваними профілями"
                ],
                .cleanSound: [
                    .english: "Clean Sound",
                    .italian: "Suono Pulito",
                    .ukrainian: "Чистий звук"
                ],
                .warning31Bands: [
                    .english: "⏰ This will take VERY long!",
                    .italian: "⏰ Questo richiederà MOLTO tempo!",
                    .ukrainian: "⏰ Це буде ДУЖЕ довго!"
                ],
                .warning31BandsButton1: [
                    .english: "Changed my mind, give me 10 bands",
                    .italian: "Ho cambiato idea, dammi 10 bande",
                    .ukrainian: "Передумав, дай 10 смуг"
                ],
                .warning31BandsButton2: [
                    .english: "Continue",
                    .italian: "Continua",
                    .ukrainian: "Продовжити"
                ],
                .warning31BandsFinal: [
                    .english: "🤔 Are you really sure?",
                    .italian: "🤔 Sei davvero sicuro?",
                    .ukrainian: "🤔 Ти точно впевнений?"
                ],
                .warning31BandsFinalButton1: [
                    .english: "No, give me 10 bands!",
                    .italian: "No, dammi 10 bande!",
                    .ukrainian: "Ні, дай 10 смуг!"
                ],
                .warning31BandsFinalButton2: [
                    .english: "Yes, I'm patient! 💪",
                    .italian: "Sì, sono paziente! 💪",
                    .ukrainian: "Так, я терплячий! 💪"
                ],
                .deleteProfile2: [
                    .english: "Delete Profile",
                    .italian: "Elimina Profilo",
                    .ukrainian: "Видалити профіль"
                ],
                .deleteProfileMessage: [
                    .english: "Are you sure you want to delete '%@'?",
                    .italian: "Sei sicuro di voler eliminare '%@'?",
                    .ukrainian: "Ви впевнені, що хочете видалити '%@'?"
                ],
                .eq: [
                    .english: "EQ",
                    .italian: "EQ",
                    .ukrainian: "EQ"
                ],

                // CalibrationView - Additional hardcoded strings
                .calibrationCompensateRoom: [
                    .english: "Compensate room acoustics, speaker characteristics and your hearing through ear-based calibration",
                    .italian: "Compensa l'acustica della stanza, le caratteristiche degli altoparlanti e il tuo udito attraverso la calibrazione basata sull'orecchio",
                    .ukrainian: "Компенсуйте акустику кімнати, характеристики колонок та ваш слух за допомогою калібрування на слух"
                ],
                .calibrationCompensateHeadphones: [
                    .english: "Compensate headphone characteristics and your hearing through ear-based calibration",
                    .italian: "Compensa le caratteristiche delle cuffie e il tuo udito attraverso la calibrazione basata sull'orecchio",
                    .ukrainian: "Компенсуйте характеристики навушників та ваш слух за допомогою калібрування на слух"
                ],
                .calibrationImportantLimitations: [
                    .english: "Important: Calibration Limitations",
                    .italian: "Importante: Limitazioni della Calibrazione",
                    .ukrainian: "Важливо: Обмеження калібрування"
                ],
                .calibrationWhatWillImprove: [
                    .english: "✅ What will improve:",
                    .italian: "✅ Cosa migliorerà:",
                    .ukrainian: "✅ Що покращиться:"
                ],
                .calibrationMidHighBalance: [
                    .english: "• Mid and high frequency balance",
                    .italian: "• Bilanciamento frequenze medie e alte",
                    .ukrainian: "• Баланс середніх та високих частот"
                ],
                .calibrationHearingCompensation: [
                    .english: "• Compensation for your hearing characteristics",
                    .italian: "• Compensazione per le caratteristiche del tuo udito",
                    .ukrainian: "• Компенсація особливостей вашого слуху"
                ],
                .calibrationSpeakerCorrection: [
                    .english: "• Speaker frequency response correction",
                    .italian: "• Correzione risposta in frequenza altoparlanti",
                    .ukrainian: "• Корекція АЧХ колонок"
                ],
                .calibrationHeadphoneCorrection: [
                    .english: "• Headphone frequency response correction",
                    .italian: "• Correzione risposta in frequenza cuffie",
                    .ukrainian: "• Корекція АЧХ навушників"
                ],
                .calibrationLessFatigue: [
                    .english: "• Less listening fatigue",
                    .italian: "• Meno affaticamento all'ascolto",
                    .ukrainian: "• Менша втомлюваність слуху"
                ],
                .calibrationWhatWontFix: [
                    .english: "⚠️ What WON'T be fixed without a microphone:",
                    .italian: "⚠️ Cosa NON verrà risolto senza un microfono:",
                    .ukrainian: "⚠️ Що НЕ виправиться без мікрофона:"
                ],
                .calibrationBassResonances: [
                    .english: "• Bass peaks/dips from standing waves",
                    .italian: "• Picchi/avvallamenti dei bassi da onde stazionarie",
                    .ukrainian: "• Басові піки/провали від стоячих хвиль"
                ],
                .calibrationEchoReverb: [
                    .english: "• Echo and room reverberation",
                    .italian: "• Eco e riverbero della stanza",
                    .ukrainian: "• Ехо та реверберація кімнати"
                ],
                .calibrationRoomUnevenness: [
                    .english: "• Unevenness at different room positions",
                    .italian: "• Irregolarità in diverse posizioni della stanza",
                    .ukrainian: "• Нерівномірність в різних точках кімнати"
                ],
                .calibrationNeedsMicrophone: [
                    .english: "💡 For 100% results you need Room Correction with a measurement microphone",
                    .italian: "💡 Per risultati al 100% hai bisogno di Room Correction con un microfono di misurazione",
                    .ukrainian: "💡 Для 100% результату потрібна Room Correction з вимірювальним мікрофоном"
                ],
                .calibrationDriverLimitations: [
                    .english: "• Physical driver limitations (distortion at extremes)",
                    .italian: "• Limitazioni fisiche dei driver (distorsione agli estremi)",
                    .ukrainian: "• Фізичні обмеження драйверів (спотворення на крайніх частотах)"
                ],
                .calibrationMethodPrincipleTitle: [
                    .english: "Method Principle",
                    .italian: "Principio del Metodo",
                    .ukrainian: "Принцип методу"
                ],
                .calibrationMethodPrincipleDesc: [
                    .english: "Adjust all frequencies so they sound equally loud as the 1000 Hz reference",
                    .italian: "Regola tutte le frequenze in modo che suonino ugualmente forti come il riferimento di 1000 Hz",
                    .ukrainian: "Налаштуйте всі частоти так, щоб вони звучали однаково гучно як референс 1000 Гц"
                ],
                .calibrationPreparation: [
                    .english: "Preparation",
                    .italian: "Preparazione",
                    .ukrainian: "Підготовка"
                ],
                .calibrationPreparationDesc: [
                    .english: "Sit in your usual place, close your eyes, relax your hearing",
                    .italian: "Siediti nel tuo posto abituale, chiudi gli occhi, rilassa il tuo udito",
                    .ukrainian: "Сядьте у звичне місце, закрийте очі, розслабте слух"
                ],
                .calibrationReference1000: [
                    .english: "Reference 1000 Hz",
                    .italian: "Riferimento 1000 Hz",
                    .ukrainian: "Референс 1000 Гц"
                ],
                .calibrationReference1000Desc: [
                    .english: "Set comfortable volume - this is your reference point",
                    .italian: "Imposta il volume confortevole - questo è il tuo punto di riferimento",
                    .ukrainian: "Встановіть комфортну гучність - це ваш орієнтир"
                ],
                .calibrationAdjustFrequencies: [
                    .english: "Frequency Adjustment",
                    .italian: "Regolazione Frequenze",
                    .ukrainian: "Налаштування частот"
                ],
                .calibrationAdjustFrequenciesDesc: [
                    .english: "Make each frequency as loud as 1000 Hz",
                    .italian: "Rendi ogni frequenza forte come 1000 Hz",
                    .ukrainian: "Кожну частоту зробіть такою ж гучкою як 1000 Гц"
                ],
                .calibrationVerification: [
                    .english: "Verification",
                    .italian: "Verifica",
                    .ukrainian: "Перевірка"
                ],
                .calibrationVerificationDesc: [
                    .english: "Pink noise should sound balanced, without preferences",
                    .italian: "Il rumore rosa dovrebbe suonare bilanciato, senza preferenze",
                    .ukrainian: "Рожевий шум має звучати збалансовано, без переваг"
                ],
                .calibrationProTips: [
                    .english: "💡 Professional Tips:",
                    .italian: "💡 Consigli Professionali:",
                    .ukrainian: "💡 Професійні поради:"
                ],
                .calibrationProTip1: [
                    .english: "Calibrate at comfortable volume (not too loud/quiet)",
                    .italian: "Calibra a volume confortevole (non troppo alto/basso)",
                    .ukrainian: "Калібруйте при комфортній гучності (не занадто гучно/тихо)"
                ],
                .calibrationProTip2: [
                    .english: "Close your eyes - hearing is better than sight for calibration",
                    .italian: "Chiudi gli occhi - l'udito è migliore della vista per la calibrazione",
                    .ukrainian: "Закрийте очі - слух кращий за зір для калібрування"
                ],
                .calibrationProTip3: [
                    .english: "Listen 2-3 seconds on each frequency, don't rush",
                    .italian: "Ascolta 2-3 secondi su ogni frequenza, non affrettarti",
                    .ukrainian: "Слухайте 2-3 секунди на кожній частоті, не поспішайте"
                ],
                .calibrationProTip4: [
                    .english: "Use A/B comparison with 1000 Hz reference",
                    .italian: "Usa il confronto A/B con il riferimento di 1000 Hz",
                    .ukrainian: "Використовуйте A/B порівняння з референсом 1000 Гц"
                ],
                .calibrationProTip5: [
                    .english: "Take a break every 10 minutes to rest your hearing",
                    .italian: "Fai una pausa ogni 10 minuti per riposare il tuo udito",
                    .ukrainian: "Робіть перерву кожні 10 хвилин, щоб слух відпочив"
                ],
                .calibrationOptimalConditions: [
                    .english: "🏠 Optimal Calibration Conditions:",
                    .italian: "🏠 Condizioni Ottimali di Calibrazione:",
                    .ukrainian: "🏠 Оптимальні умови для калібрування:"
                ],
                .calibrationOptimalCondition1: [
                    .english: "📍 Always sit in the same place",
                    .italian: "📍 Siediti sempre nello stesso posto",
                    .ukrainian: "📍 Сідайте завжди на одному й тому ж місці"
                ],
                .calibrationOptimalCondition2: [
                    .english: "📏 Optimal distance to speakers: 1.5-2.5 meters",
                    .italian: "📏 Distanza ottimale dagli altoparlanti: 1,5-2,5 metri",
                    .ukrainian: "📏 Оптимальна відстань до колонок: 1.5-2.5 метри"
                ],
                .calibrationOptimalCondition3: [
                    .english: "🔊 Speakers should be at ear level",
                    .italian: "🔊 Gli altoparlanti dovrebbero essere all'altezza delle orecchie",
                    .ukrainian: "🔊 Колонки повинні бути на рівні вух"
                ],
                .calibrationOptimalCondition4: [
                    .english: "🎵 Use 10-band mode for untreated rooms",
                    .italian: "🎵 Usa la modalità a 10 bande per stanze non trattate",
                    .ukrainian: "🎵 Використовуйте 10-band режим для необроблених кімнат"
                ],
                .calibrationOptimalCondition5: [
                    .english: "⚠️ Limit bass correction to ±6 dB below 200 Hz",
                    .italian: "⚠️ Limita la correzione dei bassi a ±6 dB sotto i 200 Hz",
                    .ukrainian: "⚠️ Обмежте корекцію баса до ±6 дБ нижче 200 Гц"
                ],
                .calibrationEqualLoudnessVsRoom: [
                    .english: "📚 Equal Loudness vs Room Correction:",
                    .italian: "📚 Equal Loudness vs Room Correction:",
                    .ukrainian: "📚 Equal Loudness vs Room Correction:"
                ],
                .calibrationEqualLoudnessMethod: [
                    .english: "🎧 Equal Loudness (our method):",
                    .italian: "🎧 Equal Loudness (il nostro metodo):",
                    .ukrainian: "🎧 Equal Loudness (наш метод):"
                ],
                .calibrationEqualLoudnessDesc1: [
                    .english: "• Calibrates by ear (subjective, but natural)",
                    .italian: "• Calibra ad orecchio (soggettivo, ma naturale)",
                    .ukrainian: "• Калібрує на слух (суб'єктивно, але природно)"
                ],
                .calibrationEqualLoudnessDesc2: [
                    .english: "• Compensates hearing + speakers + partially room",
                    .italian: "• Compensa udito + altoparlanti + parzialmente stanza",
                    .ukrainian: "• Компенсує слух + колонки + частково кімнату"
                ],
                .calibrationEqualLoudnessDesc3: [
                    .english: "• Fast and without additional equipment",
                    .italian: "• Veloce e senza attrezzatura aggiuntiva",
                    .ukrainian: "• Швидко і без додаткового обладнання"
                ],
                .calibrationRoomCorrectionMethod: [
                    .english: "🎤 Room Correction (with microphone):",
                    .italian: "🎤 Room Correction (con microfono):",
                    .ukrainian: "🎤 Room Correction (з мікрофоном):"
                ],
                .calibrationRoomCorrectionDesc1: [
                    .english: "• Measures objectively (accurate data)",
                    .italian: "• Misura oggettivamente (dati accurati)",
                    .ukrainian: "• Вимірює об'єктивно (точні дані)"
                ],
                .calibrationRoomCorrectionDesc2: [
                    .english: "• Fixes standing waves and reverberation",
                    .italian: "• Corregge onde stazionarie e riverbero",
                    .ukrainian: "• Виправляє стоячі хвилі та реверберацію"
                ],
                .calibrationRoomCorrectionDesc3: [
                    .english: "• Requires measurement microphone",
                    .italian: "• Richiede microfono di misurazione",
                    .ukrainian: "• Потрібен вимірювальний мікрофон"
                ],

                // AutoEQView - Additional hardcoded strings
                .autoEQTypeModelName: [
                    .english: "Type a model name to search",
                    .italian: "Digita un nome modello per cercare",
                    .ukrainian: "Введіть назву моделі для пошуку"
                ],
                .autoEQFavoritesTitle: [
                    .english: "⭐ Favorites",
                    .italian: "⭐ Preferiti",
                    .ukrainian: "⭐ Обрані"
                ],
                .autoEQMappedPreviewTitle: [
                    .english: "Mapped Preview",
                    .italian: "Anteprima Mappata",
                    .ukrainian: "Попередній перегляд"
                ],
                .autoEQSetupTitle: [
                    .english: "AutoEQ Setup",
                    .italian: "Configurazione AutoEQ",
                    .ukrainian: "Встановлення AutoEQ"
                ],
                .autoEQSetupDesc1: [
                    .english: "For the most accurate results, we recommend installing AutoEQ.",
                    .italian: "Per i risultati più accurati, consigliamo di installare AutoEQ.",
                    .ukrainian: "Для найточніших результатів рекомендуємо встановити AutoEQ."
                ],
                .autoEQSetupDesc2: [
                    .english: "This takes ~2 minutes and requires Python 3.",
                    .italian: "Questo richiede ~2 minuti e richiede Python 3.",
                    .ukrainian: "Це займе ~2 хвилини та вимагає Python 3."
                ],
                .quickImportHelp: [
                    .english: "Import directly from database (instant!)",
                    .italian: "Importa direttamente dal database (istantaneo!)",
                    .ukrainian: "Імпорт безпосередньо з бази даних (миттєво!)"
                ],
                .autoEQImportFile: [
                    .english: "Import .txt",
                    .italian: "Importa .txt",
                    .ukrainian: "Імпорт .txt"
                ],
                .autoEQImportFileHelp: [
                    .english: "Import your own preset (.txt) — AutoEQ, EqualizerAPO, REW, spinorama formats",
                    .italian: "Importa il tuo preset (.txt) — formati AutoEQ, EqualizerAPO, REW, spinorama",
                    .ukrainian: "Імпортувати власний пресет (.txt) — формати AutoEQ, EqualizerAPO, REW, spinorama"
                ],
                .autoEQImportFileError: [
                    .english: "Unrecognized preset format",
                    .italian: "Formato preset non riconosciuto",
                    .ukrainian: "Невідомий формат пресету"
                ],
                .autoEQImportFileSuccess: [
                    .english: "Imported %d filters",
                    .italian: "Importati %d filtri",
                    .ukrainian: "Імпортовано %d фільтрів"
                ],
                .autoEQSaveToFavorites: [
                    .english: "Save to favorites",
                    .italian: "Salva nei preferiti",
                    .ukrainian: "Зберегти в обране"
                ],
                .autoEQShowSaved: [
                    .english: "Show saved presets",
                    .italian: "Mostra preset salvati",
                    .ukrainian: "Показати збережені пресети"
                ],
                .removeFromFavorites: [
                    .english: "Remove from favorites",
                    .italian: "Rimuovi dai preferiti",
                    .ukrainian: "Видалити з обраного"
                ],
                .addToFavorites: [
                    .english: "Add to favorites",
                    .italian: "Aggiungi ai preferiti",
                    .ukrainian: "Додати до обраного"
                ],
                .indexUpdated: [
                    .english: "Index: %d (updated %@)",
                    .italian: "Indice: %d (aggiornato %@)",
                    .ukrainian: "Індекс: %d (оновлено %@)"
                ],
                .applyBandsCount: [
                    .english: "Apply %d bands • %@",
                    .italian: "Applica %d bande • %@",
                    .ukrainian: "Застосувати %d смуг • %@"
                ],
                .indexToday: [
                    .english: "today",
                    .italian: "oggi",
                    .ukrainian: "сьогодні"
                ],
                .indexYesterday: [
                    .english: "yesterday",
                    .italian: "ieri",
                    .ukrainian: "вчора"
                ],
                .indexDaysAgo: [
                    .english: "%d days ago",
                    .italian: "%d giorni fa",
                    .ukrainian: "%d дн. тому"
                ],
                .indexWeeksAgo: [
                    .english: "%d weeks ago",
                    .italian: "%d settimane fa",
                    .ukrainian: "%d тижн. тому"
                ],
                .indexMonthsAgo: [
                    .english: "%d months ago",
                    .italian: "%d mesi fa",
                    .ukrainian: "%d міс. тому"
                ],
                .updatingIndex: [
                    .english: "Updating index...",
                    .italian: "Aggiornamento indice...",
                    .ukrainian: "Оновлення індексу..."
                ],
                .buildingIndex: [
                    .english: "Building index…",
                    .italian: "Costruzione indice…",
                    .ukrainian: "Побудова індексу…"
                ],
                .httpError: [
                    .english: "HTTP error (INDEX.md)",
                    .italian: "Errore HTTP (INDEX.md)",
                    .ukrainian: "Помилка HTTP (INDEX.md)"
                ],

                // VisualizerView
                .visualizerStyleColorsSubtitle: [
                    .english: "Style • Colors • Sensitivity",
                    .italian: "Stile • Colori • Sensibilità",
                    .ukrainian: "Стиль • Кольори • Чутливість"
                ],
                .spectrum: [
                    .english: "Spectrum",
                    .italian: "Spettro",
                    .ukrainian: "Спектр"
                ],
                .waveform: [
                    .english: "Waveform",
                    .italian: "Forma d'onda",
                    .ukrainian: "Форма хвилі"
                ],
                .particles: [
                    .english: "Particles",
                    .italian: "Particelle",
                    .ukrainian: "Частинки"
                ],
                .psychedelic: [
                    .english: "Psychedelic",
                    .italian: "Psichedelico",
                    .ukrainian: "Психоделічний"
                ],
                .intensity: [
                    .english: "Intensity",
                    .italian: "Intensità",
                    .ukrainian: "Інтенсивність"
                ],
                .preview: [
                    .english: "Preview",
                    .italian: "Anteprima",
                    .ukrainian: "Попередній перегляд"
                ],

                // AudioRouter - Alert messages
                .eqRoutingSetupRequired: [
                    .english: "EQ Routing Setup Required",
                    .italian: "Configurazione Routing EQ Richiesta",
                    .ukrainian: "Потрібне налаштування маршрутизації EQ"
                ],
                .eqRoutingSetupInstructions: [
                    .english: "To enable system-wide EQ with CoreAudioEngine, set System Output to BlackHole 2ch and keep SystemEQ running.\n\nSteps:\n1. Open Audio MIDI Setup (Applications → Utilities → Audio MIDI Setup)\n2. Right-click \"BlackHole 2ch\" → \"Use This Device for Sound Output\"\n3. In SystemEQ, click \"Enable EQ\" or \"Test Audio\"\n\nAudio flow: System → BlackHole → CoreAudioEngine (EQ) → %@",
                    .italian: "Per abilitare l'EQ di sistema con CoreAudioEngine, imposta l'uscita di sistema su BlackHole 2ch e mantieni SystemEQ in esecuzione.\n\nPassaggi:\n1. Apri Configurazione Audio MIDI (Applicazioni → Utility → Configurazione Audio MIDI)\n2. Fai clic destro su \"BlackHole 2ch\" → \"Usa questo dispositivo per l'uscita audio\"\n3. In SystemEQ, fai clic su \"Abilita EQ\" o \"Test Audio\"\n\nFlusso audio: Sistema → BlackHole → CoreAudioEngine (EQ) → %@",
                    .ukrainian: "Щоб увімкнути системний EQ з CoreAudioEngine, встановіть системний вивід на BlackHole 2ch і тримайте SystemEQ запущеним.\n\nКроки:\n1. Відкрийте Audio MIDI Setup (Програми → Утиліти → Audio MIDI Setup)\n2. Клацніть правою кнопкою \"BlackHole 2ch\" → \"Використовувати цей пристрій для виводу звуку\"\n3. У SystemEQ натисніть \"Увімкнути EQ\" або \"Тест аудіо\"\n\nПотік аудіо: Система → BlackHole → CoreAudioEngine (EQ) → %@"
                ],
                .openAudioMIDISetupButton: [
                    .english: "Open Audio MIDI Setup",
                    .italian: "Apri Configurazione Audio MIDI",
                    .ukrainian: "Відкрити Audio MIDI Setup"
                ],
                .testAudioButton: [
                    .english: "Test Audio",
                    .italian: "Test Audio",
                    .ukrainian: "Тест аудіо"
                ],
                .manualSetupRequired: [
                    .english: "Manual Setup Required",
                    .italian: "Configurazione Manuale Richiesta",
                    .ukrainian: "Потрібне ручне налаштування"
                ],
                .manualSetupInstructions: [
                    .english: "SystemEQ couldn't automatically switch your system output to %@.\n\nPlease manually switch:\n1. Open System Settings → Sound\n2. Select '%@' as Output Device\n\nOr use Audio MIDI Setup:\n• Right-click '%@' → \"Use This Device for Sound Output\"\n\nAfter switching, audio will flow:\nSystem → %@ → SystemEQ (with EQ) → Your speakers",
                    .italian: "SystemEQ non è riuscito a cambiare automaticamente l'uscita di sistema su %@.\n\nCambia manualmente:\n1. Apri Impostazioni di Sistema → Suono\n2. Seleziona '%@' come dispositivo di uscita\n\nOppure usa Configurazione Audio MIDI:\n• Fai clic destro su '%@' → \"Usa questo dispositivo per l'uscita audio\"\n\nDopo il cambio, l'audio fluirà:\nSistema → %@ → SystemEQ (con EQ) → I tuoi altoparlanti",
                    .ukrainian: "SystemEQ не зміг автоматично перемкнути системний вивід на %@.\n\nБудь ласка, перемкніть вручну:\n1. Відкрийте Системні Параметри → Звук\n2. Виберіть '%@' як вихідний пристрій\n\nАбо використайте Audio MIDI Setup:\n• Клацніть правою кнопкою '%@' → \"Використовувати цей пристрій для виводу звуку\"\n\nПісля перемикання аудіо буде йти:\nСистема → %@ → SystemEQ (з EQ) → Ваші колонки"
                ],
                .openSystemSettings: [
                    .english: "Open System Settings",
                    .italian: "Apri Impostazioni di Sistema",
                    .ukrainian: "Відкрити Системні Параметри"
                ],
                .setBlackHoleAsSystemOutputTitle: [
                    .english: "Set BlackHole as System Output",
                    .italian: "Imposta BlackHole come Uscita di Sistema",
                    .ukrainian: "Встановити BlackHole як системний вивід"
                ],
                .setBlackHoleAsSystemOutputInstructions: [
                    .english: "For EQ to work, set \"BlackHole 2ch\" as the system output device.\n\nSteps:\n1. Open Audio MIDI Setup\n2. Right-click \"BlackHole 2ch\" → \"Use This Device for Sound Output\"\n3. Return to SystemEQ and click \"Enable EQ\" or \"Test Audio\"",
                    .italian: "Per far funzionare l'EQ, imposta \"BlackHole 2ch\" come dispositivo di uscita di sistema.\n\nPassaggi:\n1. Apri Configurazione Audio MIDI\n2. Fai clic destro su \"BlackHole 2ch\" → \"Usa questo dispositivo per l'uscita audio\"\n3. Torna a SystemEQ e fai clic su \"Abilita EQ\" o \"Test Audio\"",
                    .ukrainian: "Щоб EQ працював, встановіть \"BlackHole 2ch\" як системний вихідний пристрій.\n\nКроки:\n1. Відкрийте Audio MIDI Setup\n2. Клацніть правою кнопкою \"BlackHole 2ch\" → \"Використовувати цей пристрій для виводу звуку\"\n3. Поверніться до SystemEQ і натисніть \"Увімкнути EQ\" або \"Тест аудіо\""
                ],
                .blackHoleRequiredForRouting: [
                    .english: "BlackHole is required for system-wide audio routing. Download and install it, then restart this app.",
                    .italian: "BlackHole è richiesto per il routing audio di sistema. Scaricalo e installalo, quindi riavvia questa app.",
                    .ukrainian: "BlackHole потрібен для системної маршрутизації аудіо. Завантажте та встановіть його, потім перезапустіть програму."
                ],

                // Visualizer (ProjectM)
                .visualizerInSeparateWindow: [
                    .english: "Visualization in a separate window",
                    .italian: "Visualizzazione in una finestra separata",
                    .ukrainian: "Візуалізація в окремому вікні"
                ],
                .dragProjectMWindowHint: [
                    .english: "Drag the projectM window next to it",
                    .italian: "Trascina la finestra projectM accanto",
                    .ukrainian: "Перетягніть вікно projectM поруч"
                ],
                .launchMilkDrop: [
                    .english: "Launch MilkDrop",
                    .italian: "Avvia MilkDrop",
                    .ukrainian: "Запустити MilkDrop"
                ],
                .presetCategoryHelp: [
                    .english: "Preset category",
                    .italian: "Categoria preset",
                    .ukrainian: "Категорія пресетів"
                ],
                .presetWeightHelp: [
                    .english: "Preset weight (GPU load)",
                    .italian: "Peso del preset (carico GPU)",
                    .ukrainian: "Вага пресетів (GPU навантаження)"
                ],
                .qualityLow: [
                    .english: "Quality: Low",
                    .italian: "Qualità: Bassa",
                    .ukrainian: "Якість: Низька"
                ],
                .qualityMedium: [
                    .english: "Quality: Medium",
                    .italian: "Qualità: Media",
                    .ukrainian: "Якість: Середня"
                ],
                .qualityHigh: [
                    .english: "Quality: High",
                    .italian: "Qualità: Alta",
                    .ukrainian: "Якість: Висока"
                ],
                .visualizerQualityHelp: [
                    .english: "Render quality — lower for smooth 60 FPS on heavy presets",
                    .italian: "Qualità di rendering — più bassa per 60 FPS fluidi sui preset pesanti",
                    .ukrainian: "Якість рендеру — нижча для плавних 60 FPS на важких пресетах"
                ],
                .vizFavoriteHelp: [
                    .english: "Add current preset to favorites",
                    .italian: "Aggiungi il preset corrente ai preferiti",
                    .ukrainian: "Додати поточний пресет в обране"
                ],
                .vizPresetListHelp: [
                    .english: "Browse all presets",
                    .italian: "Sfoglia tutti i preset",
                    .ukrainian: "Переглянути всі пресети"
                ],
                .vizSearchPresets: [
                    .english: "Search presets…",
                    .italian: "Cerca preset…",
                    .ukrainian: "Пошук пресетів…"
                ],
                .vizShowFavoritesHelp: [
                    .english: "Show favorites only",
                    .italian: "Mostra solo i preferiti",
                    .ukrainian: "Лише обрані"
                ],
                .previousPresetHelp: [
                    .english: "Previous preset",
                    .italian: "Preset precedente",
                    .ukrainian: "Попередній пресет"
                ],
                .nextPresetHelp: [
                    .english: "Next preset",
                    .italian: "Preset successivo",
                    .ukrainian: "Наступний пресет"
                ],
                .randomPresetHelp: [
                    .english: "Random preset",
                    .italian: "Preset casuale",
                    .ukrainian: "Випадковий пресет"
                ],
                .autoLabel: [
                    .english: "Auto",
                    .italian: "Auto",
                    .ukrainian: "Авто"
                ],
                .autoPresetsHelp: [
                    .english: "Auto-change presets every 30 seconds",
                    .italian: "Cambia preset automaticamente ogni 30 secondi",
                    .ukrainian: "Автоматична зміна пресетів кожні 30 секунд"
                ],
                .lockLabel: [
                    .english: "Lock",
                    .italian: "Blocca",
                    .ukrainian: "Блок"
                ],
                .lockPresetHelp: [
                    .english: "Lock current preset",
                    .italian: "Blocca il preset corrente",
                    .ukrainian: "Заблокувати поточний пресет"
                ],

                // Resonance / Room Tuning
                .automaticSweep: [
                    .english: "Automatic sweep",
                    .italian: "Sweep automatico",
                    .ukrainian: "Автоматичний sweep"
                ],
                .sweepInstructions: [
                    .english: "Sweep automatically runs through all frequencies. When you hear a resonance — click 'Mark'.",
                    .italian: "Lo sweep passa automaticamente per tutte le frequenze. Quando senti una risonanza — clicca 'Segna'.",
                    .ukrainian: "Sweep автоматично проходить через всі частоти. Коли почуєте резонанс — натисніть 'Позначити'."
                ],
                .quickFrequencySelect: [
                    .english: "Quick frequency selection",
                    .italian: "Selezione rapida della frequenza",
                    .ukrainian: "Швидкий вибір частоти"
                ],
                .playTone: [
                    .english: "Play",
                    .italian: "Riproduci",
                    .ukrainian: "Відтворити"
                ],
                .stopPlayback: [
                    .english: "Stop",
                    .italian: "Stop",
                    .ukrainian: "Зупинити"
                ],
                .sliderFrequencyHint: [
                    .english: "Move the slider or press frequency buttons — sound will update automatically",
                    .italian: "Muovi il cursore o premi i pulsanti delle frequenze — il suono si aggiorna automaticamente",
                    .ukrainian: "Рухайте повзунок або натискайте кнопки частот — звук оновиться автоматично"
                ],

                // Add Resonance Sheet
                .whatIsThis: [
                    .english: "What is this?",
                    .italian: "Cos'è questo?",
                    .ukrainian: "Що це?"
                ],
                .resonanceExplanation: [
                    .english: "A resonance is a frequency at which your room amplifies sound. Add a resonance to create a notch filter to suppress it.",
                    .italian: "Una risonanza è una frequenza alla quale la tua stanza amplifica il suono. Aggiungi una risonanza per creare un filtro notch che la sopprima.",
                    .ukrainian: "Резонанс — це частота, на якій ваша кімната підсилює звук. Додайте резонанс, щоб потім створити notch-фільтр для його придушення."
                ],
                .resonanceStrength: [
                    .english: "Resonance strength",
                    .italian: "Intensità della risonanza",
                    .ukrainian: "Сила резонансу"
                ],
                .resonanceStrengthDesc: [
                    .english: "Select how strongly this frequency stands out:",
                    .italian: "Seleziona quanto questa frequenza si distingue:",
                    .ukrainian: "Оберіть наскільки сильно ця частота виділяється:"
                ],
                .severityMild: [
                    .english: "Mild",
                    .italian: "Lieve",
                    .ukrainian: "Легкий"
                ],
                .severityMildDesc: [
                    .english: "Barely noticeable resonance",
                    .italian: "Risonanza appena percettibile",
                    .ukrainian: "Ледь помітний резонанс"
                ],
                .severityModerate: [
                    .english: "Moderate",
                    .italian: "Moderato",
                    .ukrainian: "Помірний"
                ],
                .severityModerateDesc: [
                    .english: "Noticeable but not critical",
                    .italian: "Percettibile ma non critico",
                    .ukrainian: "Помітний, але не критичний"
                ],
                .severitySevere: [
                    .english: "Severe",
                    .italian: "Grave",
                    .ukrainian: "Сильний"
                ],
                .severitySevereDesc: [
                    .english: "Clearly interferes with sound",
                    .italian: "Interferisce chiaramente con il suono",
                    .ukrainian: "Явно заважає звучанню"
                ],
                .severityExtreme: [
                    .english: "Very severe",
                    .italian: "Molto grave",
                    .ukrainian: "Дуже сильний"
                ],
                .severityExtremeDesc: [
                    .english: "Critical resonance",
                    .italian: "Risonanza critica",
                    .ukrainian: "Критичний резонанс"
                ],

                // Setup Assistant
                .runSetupAssistant: [
                    .english: "Run Setup Assistant",
                    .italian: "Avvia Assistente di Configurazione",
                    .ukrainian: "Запустити помічника налаштування"
                ],
                .launchAtLoginHelp: [
                    .english: "Automatically start SystemEQ when you log in",
                    .italian: "Avvia automaticamente SystemEQ all'accesso",
                    .ukrainian: "Автоматично запускати SystemEQ при вході"
                ],

                // Calibration Activation Alert
                .calibrationActivatedTitle: [
                    .english: "Calibration activated!",
                    .italian: "Calibrazione attivata!",
                    .ukrainian: "Калібровку активовано!"
                ],
                .calibrationActivatedMessage: [
                    .english: "Now enable EQ in the main window:\n\n1. Close the calibration window\n2. Enable 'Enable EQ'\n\nOnly then will calibration apply to system audio.",
                    .italian: "Ora abilita l'EQ nella finestra principale:\n\n1. Chiudi la finestra di calibrazione\n2. Abilita 'Abilita EQ'\n\nSolo allora la calibrazione verrà applicata all'audio di sistema.",
                    .ukrainian: "Тепер увімкніть EQ в головному вікні:\n\n1. Закрийте вікно калібровки\n2. Увімкніть 'Enable EQ'\n\nТільки тоді калібровка почне діяти на системний звук."
                ],

                // AutoEQ Setup Prompt
                .neverAsk: [
                    .english: "Never ask again",
                    .italian: "Non chiedere più",
                    .ukrainian: "Ніколи не питати"
                ],
                .later: [
                    .english: "Later",
                    .italian: "Più tardi",
                    .ukrainian: "Пізніше"
                ],
                .installNow: [
                    .english: "Install now",
                    .italian: "Installa ora",
                    .ukrainian: "Встановити зараз"
                ],

                // Glass Design Section (Settings)
                .glassDesignTitle: [
                    .english: "Glass Design",
                    .italian: "Design in Vetro",
                    .ukrainian: "Скляний дизайн"
                ],
                .glassDesignDesc: [
                    .english: "Customize the appearance of glass UI elements",
                    .italian: "Personalizza l'aspetto degli elementi dell'interfaccia in vetro",
                    .ukrainian: "Налаштуйте вигляд скляних елементів інтерфейсу"
                ],
                .glassDesignStyle: [
                    .english: "Style",
                    .italian: "Stile",
                    .ukrainian: "Стиль"
                ],
                .glassDesignCustomOpacity: [
                    .english: "Custom Opacity",
                    .italian: "Opacità Personalizzata",
                    .ukrainian: "Власна прозорість"
                ],
                .glassDesignOpacity: [
                    .english: "Opacity",
                    .italian: "Opacità",
                    .ukrainian: "Прозорість"
                ],
                .glassDesignPreview: [
                    .english: "Preview",
                    .italian: "Anteprima",
                    .ukrainian: "Попередній перегляд"
                ],
                .glassDesignPreviewLabel: [
                    .english: "Glass Effect Preview",
                    .italian: "Anteprima Effetto Vetro",
                    .ukrainian: "Попередній перегляд ефекту скла"
                ],

                // Calibration Mode Selector
                .calibrationModeClean: [
                    .english: "Clean Calibration",
                    .italian: "Calibrazione Pulita",
                    .ukrainian: "Чиста Калібровка"
                ],
                .calibrationModeCombined: [
                    .english: "Combined Calibration",
                    .italian: "Calibrazione Combinata",
                    .ukrainian: "Комбінована Калібровка"
                ],
                .calibrationModeCleanDesc: [
                    .english: "Calibrate pure speakers/headphones (EQ will be disabled)",
                    .italian: "Calibra altoparlanti/cuffie puri (l'EQ verrà disabilitato)",
                    .ukrainian: "Калібрувати чисті динаміки/навушники (EQ буде вимкнено)"
                ],
                .calibrationModeCombinedDesc: [
                    .english: "Calibrate with current EQ preset active",
                    .italian: "Calibra con il preset EQ attuale attivo",
                    .ukrainian: "Калібрувати з активним поточним пресетом EQ"
                ],

                // Database Version Check (use String(format:) for %@ substitutions)
                .dbUpToDate: [
                    .english: "✅ Database is up to date (version %@)",
                    .italian: "✅ Database aggiornato (versione %@)",
                    .ukrainian: "✅ База даних актуальна (версія %@)"
                ],
                .dbUpdateAvailable: [
                    .english: "🔄 Update available: %@ → %@",
                    .italian: "🔄 Aggiornamento disponibile: %@ → %@",
                    .ukrainian: "🔄 Доступне оновлення: %@ → %@"
                ],
                .dbCheckFailed: [
                    .english: "⚠️ Could not check: %@",
                    .italian: "⚠️ Impossibile verificare: %@",
                    .ukrainian: "⚠️ Не вдалося перевірити: %@"
                ],
                .dbVersionUnavailable: [
                    .english: "could not read the local database version",
                    .italian: "impossibile leggere la versione del database locale",
                    .ukrainian: "не вдалося прочитати версію локальної бази"
                ]
            ]

            _translations = dict
            return dict
        }
    }
}

// MARK: - Localization Manager

public final class LocalizationManager: ObservableObject {
    /// ... rest of the code remains the same ...
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

    /// ... rest of the code remains the same ...
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
