//
//  RoomCalibrationLocalization.swift
//  SystemEQ for Mac
//
//  Localization for Room Calibration View
//

import Foundation

enum RoomCalibrationLocalization: String, CaseIterable {
    /// Main description
    case findRoomResonances = "Find room resonances by sweeping through frequencies 20Hz-20kHz. Listen for frequencies that sound significantly louder than others - these are your room's problem frequencies."

    // Instructions
    case startSineSweep = "Start sine sweep and listen carefully"
    case markFrequencies = "Mark frequencies that 'boom' or 'ring'"
    case applyNotchFilters = "Apply notch filters to suppress resonances"
    case testWithMusic = "Test with music to verify improvement"

    // UI Labels
    case currentFrequency = "Current Frequency"
    case sweepSpeed = "Sweep Speed"
    case markResonance = "Mark Resonance"
    case quickTest = "Quick Test - Common Problem Frequencies"
    case manualFrequencyTest = "Manual Frequency Test"
    case testSpecificFrequencies = "Test specific frequencies manually and add resonances"
    case frequency = "Frequency"
    case playFrequency = "Play %d Hz"
    case addAsResonance = "Add as Resonance"
    case detectedResonances = "Detected Resonances"
    case noResonancesDetected = "No resonances detected yet. Use Sine Sweep to find problem frequencies."
    case addFilter = "Add Filter"
    case appliedNotchFilters = "Applied Notch Filters"
    case noNotchFiltersApplied = "No notch filters applied yet."
    case compareSound = "Compare original sound with filtered sound (with gain matching)"
    case gainMatching = "Gain Matching"
    case gainMatchingDesc = "Automatically compensates for volume differences so you can judge quality, not loudness."
    case saveProfile = "Save Profile"
    case addResonance = "Add Resonance"
    case severity = "Severity"
    case mild = "Mild (-2dB)"
    case moderate = "Moderate (-4dB)"
    case severe = "Severe (-6dB)"
}

/// Italian localization
extension RoomCalibrationLocalization {
    var italian: String {
        switch self {
        case .findRoomResonances: "Trova le risonanze della stanza scansionando le frequenze 20Hz-20kHz. Ascolta le frequenze che suonano significativamente più alte di altre - queste sono le frequenze problematiche della tua stanza."
        case .startSineSweep: "Avvia la scansione sinusoidale e ascolta attentamente"
        case .markFrequencies: "Segna le frequenze che 'booming' o 'ringing'"
        case .applyNotchFilters: "Applica filtri notch per sopprimere le risonanze"
        case .testWithMusic: "Testa con musica per verificare il miglioramento"
        case .currentFrequency: "Frequenza Corrente"
        case .sweepSpeed: "Velocità Scansione"
        case .markResonance: "Segna Risonanza"
        case .quickTest: "Test Rapido - Frequenze Problematiche Comuni"
        case .manualFrequencyTest: "Test Frequenza Manuale"
        case .testSpecificFrequencies: "Testa frequenze specifiche manualmente e aggiungi risonanze"
        case .frequency: "Frequenza"
        case .playFrequency: "Riproduci %d Hz"
        case .addAsResonance: "Aggiungi come Risonanza"
        case .detectedResonances: "Risonanze Rilevate"
        case .noResonancesDetected: "Nessuna risonanza rilevata ancora. Usa la Scansione Sinusoidale per trovare le frequenze problematiche."
        case .addFilter: "Aggiungi Filtro"
        case .appliedNotchFilters: "Filtri Notch Applicati"
        case .noNotchFiltersApplied: "Nessun filtro notch applicato ancora."
        case .compareSound: "Confronta il suono originale con quello filtrato (con equalizzazione del guadagno)"
        case .gainMatching: "Equalizzazione Guadagno"
        case .gainMatchingDesc: "Compensa automaticamente le differenze di volume in modo da poter giudicare la qualità, non la loudness."
        case .saveProfile: "Salva Profilo"
        case .addResonance: "Aggiungi Risonanza"
        case .severity: "Severità"
        case .mild: "Leggero (-2dB)"
        case .moderate: "Moderato (-4dB)"
        case .severe: "Forte (-6dB)"
        }
    }
}

/// Ukrainian localization
extension RoomCalibrationLocalization {
    var ukrainian: String {
        switch self {
        case .findRoomResonances: "Знайдіть резонанси кімнати, скануючи частоти 20Гц-20кГц. Слухайте частоти, що звучать значно голосніше за інші - це проблемні частоти вашої кімнати."
        case .startSineSweep: "Почніть синусоїдну розгортку і слухайте уважно"
        case .markFrequencies: "Позначте частоти, що 'гудуть' або 'дзвенять'"
        case .applyNotchFilters: "Застосуйте notch-фільтри для придушення резонансів"
        case .testWithMusic: "Протестуйте музикою для перевірки покращення"
        case .currentFrequency: "Поточна частота"
        case .sweepSpeed: "Швидкість розгортки"
        case .markResonance: "Позначити резонанс"
        case .quickTest: "Швидкий тест - Типові проблемні частоти"
        case .manualFrequencyTest: "Ручний тест частоти"
        case .testSpecificFrequencies: "Протестуйте конкретні частоти вручну і додайте резонанси"
        case .frequency: "Частота"
        case .playFrequency: "Грати %d Гц"
        case .addAsResonance: "Додати як резонанс"
        case .detectedResonances: "Виявлені резонанси"
        case .noResonancesDetected: "Ще не виявлено резонансів. Використайте синусоїдну розгортку для пошуку проблемних частот."
        case .addFilter: "Додати фільтр"
        case .appliedNotchFilters: "Застосовані notch-фільтри"
        case .noNotchFiltersApplied: "Ще не застосовано notch-фільтрів."
        case .compareSound: "Порівняйте оригінальний звук з відфільтрованим (з вирівнюванням гучності)"
        case .gainMatching: "Вирівнювання гучності"
        case .gainMatchingDesc: "Автоматично компенсує різниці в гучності, щоб ви могли оцінювати якість, а не гучність."
        case .saveProfile: "Зберегти профіль"
        case .addResonance: "Додати резонанс"
        case .severity: "Рівень"
        case .mild: "Легкий (-2дБ)"
        case .moderate: "Помірний (-4дБ)"
        case .severe: "Сильний (-6дБ)"
        }
    }
}
