//
//  CalibrationLocalization.swift
//  SystemEQ for Mac
//
//  Localization for Calibration View
//

import Foundation

enum CalibrationLocalization: String, CaseIterable {
    // Header
    case equalLoudnessCalibration = "Equal Loudness Calibration"
    case calibrationDescription = "Compensate room acoustics, speaker characteristics, and your hearing with hearing-based calibration"

    // Important Note
    case importantNote = "Important: Calibration Limitations"
    case willImprove = "✅ What will improve:"
    case willImprove1 = "• Balance of mid and high frequencies"
    case willImprove2 = "• Compensation for your hearing characteristics"
    case willImprove3 = "• Speaker frequency response correction"
    case willImprove4 = "• Less listening fatigue"
    case wontFix = "⚠️ What won't fix without microphone:"
    case wontFix1 = "• Bass peaks/nulls from standing waves"
    case wontFix2 = "• Room echo and reverberation"
    case wontFix3 = "• Non-uniformity at different room positions"
    case forFullResult = "💡 For 100% result, Room Correction with measurement microphone is needed"

    // Method
    case methodPrinciple = "Method Principle"
    case methodDescription = "Adjust all frequencies to sound equally loud as the 1000 Hz reference"

    // Steps
    case step1 = "1️⃣"
    case step1Title = "Preparation"
    case step1Desc = "Sit in your usual place, close your eyes, relax your hearing"
    case step2 = "2️⃣"
    case step2Title = "Reference 1000 Hz"
    case step2Desc = "Set a comfortable volume - this is your reference"
    case step3 = "3️⃣"
    case step3Title = "Frequency Adjustment"
    case step3Desc = "Make each frequency as loud as 1000 Hz"
    case step4 = "4️⃣"
    case step4Title = "Verification"
    case step4Desc = "Pink noise should sound balanced, without emphasis"

    // Alert
    case deleteProfile = "Delete Profile"
    case deleteConfirmation = "Are you sure you want to delete '%@'?"
    case cancel = "Cancel"
    case delete = "Delete"
}

/// Italian localization
extension CalibrationLocalization {
    var italian: String {
        switch self {
        case .equalLoudnessCalibration: "Calibrazione Equal Loudness"
        case .calibrationDescription: "Compensa l'acustica della stanza, le caratteristiche degli altoparlanti e il tuo udito con la calibrazione basata sull'udito"
        case .importantNote: "Importante: Limitazioni della calibrazione"
        case .willImprove: "✅ Cosa migliorerà:"
        case .willImprove1: "• Equilibrio delle medie e alte frequenze"
        case .willImprove2: "• Compensazione delle caratteristiche del tuo udito"
        case .willImprove3: "• Correzione della risposta in frequenza degli altoparlanti"
        case .willImprove4: "• Meno fatica d'ascolto"
        case .wontFix: "⚠️ Cosa non si correggerà senza microfono:"
        case .wontFix1: "• Picchi/null di bassi dalle onde stazionarie"
        case .wontFix2: "• Eco e riverbero della stanza"
        case .wontFix3: "• Non uniformità in diverse posizioni della stanza"
        case .forFullResult: "💡 Per il 100% del risultato, serve Room Correction con microfono di misura"
        case .methodPrinciple: "Principio del metodo"
        case .methodDescription: "Regola tutte le frequenze in modo che suonino ugualmente forti come il riferimento 1000 Hz"
        case .step1: "1️⃣"
        case .step1Title: "Preparazione"
        case .step1Desc: "Siediti nel tuo posto abituale, chiudi gli occhi, rilassa l'udito"
        case .step2: "2️⃣"
        case .step2Title: "Riferimento 1000 Hz"
        case .step2Desc: "Imposta un volume confortevole - questo è il tuo riferimento"
        case .step3: "3️⃣"
        case .step3Title: "Regolazione frequenze"
        case .step3Desc: "Rendi ogni frequenza tanto forte quanto 1000 Hz"
        case .step4: "4️⃣"
        case .step4Title: "Verifica"
        case .step4Desc: "Il rumore rosa dovrebbe suonare bilanciato, senza enfasi"
        case .deleteProfile: "Elimina Profilo"
        case .deleteConfirmation: "Sei sicuro di voler eliminare '%@'?"
        case .cancel: "Annulla"
        case .delete: "Elimina"
        }
    }
}

/// Ukrainian localization
extension CalibrationLocalization {
    var ukrainian: String {
        switch self {
        case .equalLoudnessCalibration: "Калібрування Equal Loudness"
        case .calibrationDescription: "Компенсуйте акустику кімнати, характеристики колонок та ваш слух за допомогою калібрування на слух"
        case .importantNote: "Важливо: Обмеження калібрування"
        case .willImprove: "✅ Що покращиться:"
        case .willImprove1: "• Баланс середніх та високих частот"
        case .willImprove2: "• Компенсація особливостей вашого слуху"
        case .willImprove3: "• Корекція АЧХ колонок"
        case .willImprove4: "• Менша втомлюваність слуху"
        case .wontFix: "⚠️ Що НЕ виправиться без мікрофона:"
        case .wontFix1: "• Басові піки/провали від стоячих хвиль"
        case .wontFix2: "• Ехо та реверберація кімнати"
        case .wontFix3: "• Нерівномірність в різних точках кімнати"
        case .forFullResult: "💡 Для 100% результату потрібна Room Correction з вимірювальним мікрофоном"
        case .methodPrinciple: "Принцип методу"
        case .methodDescription: "Налаштуйте всі частоти так, щоб вони звучали однаково гучно як референс 1000 Гц"
        case .step1: "1️⃣"
        case .step1Title: "Підготовка"
        case .step1Desc: "Сядьте у звичне місце, закрийте очі, розслабте слух"
        case .step2: "2️⃣"
        case .step2Title: "Референс 1000 Гц"
        case .step2Desc: "Встановіть комфортну гучність - це ваш орієнтир"
        case .step3: "3️⃣"
        case .step3Title: "Налаштування частот"
        case .step3Desc: "Кожну частоту зробіть такою ж гучкою як 1000 Гц"
        case .step4: "4️⃣"
        case .step4Title: "Перевірка"
        case .step4Desc: "Рожевий шум має звучати збалансовано, без переваг"
        case .deleteProfile: "Видалити профіль"
        case .deleteConfirmation: "Ви впевнені, що хочете видалити '%@'?"
        case .cancel: "Скасувати"
        case .delete: "Видалити"
        }
    }
}
