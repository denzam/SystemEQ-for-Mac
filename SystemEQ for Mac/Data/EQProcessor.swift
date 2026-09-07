import Foundation

// MARK: - EQ Processor

/// Процесор для обчислення еквалайзера з параметричного EQ та цільової кривої
enum EQProcessor {
    // MARK: - Filter Types

    enum ProcessorFilterType: String {
        case peaking = "PK"
        case lowShelf = "LSC"
        case highShelf = "HSC"
        case lowPass = "LPF"
        case highPass = "HPF"
    }

    struct ParametricFilter {
        let type: ProcessorFilterType
        let frequency: Double
        let q: Double
        let gain: Double
    }

    // MARK: - Generate Graphic EQ Values

    /// Застосовує JM-1 корекцію до Fixed Band EQ значень (Harman)
    static func applyJM1ToFixedBand(
        fixedBandEQ: [(freq: Double, gain: Double)],
        centerFrequencies: [Double]
    ) -> (bands: [(
        freq: Double,
        gain: Double
    )], preamp: Double) {
        var bands: [(freq: Double, gain: Double)] = []
        var maxGain = 0.0

        for centerFreq in centerFrequencies {
            // Знаходимо Harman gain з Fixed Band EQ таблиці
            let harmanGain = interpolateFixedBand(fixedBandEQ: fixedBandEQ, frequency: centerFreq)

            // Отримуємо target значення
            let harmanTarget = getHarmanTargetGain(frequency: centerFreq)
            let jm1Target = getJM1TargetGain(frequency: centerFreq)

            // Для JM-1: беремо Fixed Band значення і додаємо різницю targets
            let finalGain = harmanGain + (jm1Target - harmanTarget)

            bands.append((freq: centerFreq, gain: finalGain))

            if finalGain > maxGain {
                maxGain = finalGain
            }
        }

        let preamp = -(maxGain + 0.5)
        return (bands: bands, preamp: preamp)
    }

    /// Інтерполює значення з Fixed Band EQ таблиці
    private static func interpolateFixedBand(fixedBandEQ: [(freq: Double, gain: Double)], frequency: Double) -> Double {
        guard let first = fixedBandEQ.first, let last = fixedBandEQ.last else { return 0 }
        // Лінійна інтерполяція
        if frequency <= first.freq {
            return first.gain
        }
        if frequency >= last.freq {
            return last.gain
        }

        for i in 0..<(fixedBandEQ.count - 1) {
            let p1 = fixedBandEQ[i]
            let p2 = fixedBandEQ[i + 1]

            if frequency >= p1.freq, frequency <= p2.freq {
                let t = (frequency - p1.freq) / (p2.freq - p1.freq)
                return p1.gain + t * (p2.gain - p1.gain)
            }
        }

        return 0.0
    }

    /// Генерує значення для графічного еквалайзера (10 або 31 смуга) з параметричного EQ (Harman) та корекції JM-1
    static func generateGraphicEQ(filters: [ParametricFilter], centerFrequencies: [Double]) -> (bands: [(
        freq: Double,
        gain: Double
    )], preamp: Double) {
        var bands: [(freq: Double, gain: Double)] = []
        var maxGain = 0.0

        for (index, centerFreq) in centerFrequencies.enumerated() {
            // DEBUG: тільки для першої частоти
            let isFirst = index == 0

            // ПРОСТІШЕ: параметричні фільтри вже дають Harman корекцію
            // Обчислюємо їх response на центральній частоті смуги
            let harmanCorrection = calculateFrequencyResponse(filters: filters, frequency: centerFreq)
            let harmanTarget = getHarmanTargetGain(frequency: centerFreq)
            let jm1Target = getJM1TargetGain(frequency: centerFreq)

            // DEBUG
            if isFirst {}

            // Для JM-1: беремо Harman корекцію і додаємо різницю targets
            let finalGain = harmanCorrection + (jm1Target - harmanTarget)

            bands.append((freq: centerFreq, gain: finalGain))

            if finalGain > maxGain {
                maxGain = finalGain
            }
        }

        // Додатковий smoothing для усунення різких переходів
        bands = applySmoothingToBands(bands: bands)

        // Перераховуємо maxGain після smoothing
        maxGain = bands.map(\.gain).max() ?? 0.0
        let preamp = -(maxGain + 0.5)

        return (bands: bands, preamp: preamp)
    }

    /// Застосовує легкий smoothing для усунення різких переходів між смугами
    private static func applySmoothingToBands(bands: [(freq: Double, gain: Double)]) -> [(freq: Double, gain: Double)] {
        guard bands.count > 2 else { return bands }

        var smoothed: [(freq: Double, gain: Double)] = []

        for i in 0..<bands.count {
            let current = bands[i]

            // Для першої та останньої смуги не застосовуємо smoothing
            if i == 0 || i == bands.count - 1 {
                smoothed.append(current)
                continue
            }

            // Легкий smoothing: 70% поточне значення + 15% попереднє + 15% наступне
            let prev = bands[i - 1]
            let next = bands[i + 1]

            let smoothedGain = current.gain * 0.70 + prev.gain * 0.15 + next.gain * 0.15

            smoothed.append((freq: current.freq, gain: smoothedGain))
        }

        return smoothed
    }

    /// Генерує значення для графічного еквалайзера з сирих вимірювань та JM-1 target
    static func generateGraphicEQFromRaw(
        rawMeasurements: [(freq: Double, raw: Double)],
        centerFrequencies: [Double]
    ) -> (bands: [(
        freq: Double,
        gain: Double
    )], preamp: Double) {
        var bands: [(freq: Double, gain: Double)] = []
        var maxGain = 0.0

        for centerFreq in centerFrequencies {
            // Інтерполюємо сире вимірювання
            let rawValue = interpolateRaw(measurements: rawMeasurements, frequency: centerFreq)

            // Отримуємо JM-1 target
            let jm1Target = getJM1TargetGain(frequency: centerFreq)

            // Формула AutoEQ: EQ = target - raw
            let finalGain = jm1Target - rawValue

            bands.append((freq: centerFreq, gain: finalGain))

            if finalGain > maxGain {
                maxGain = finalGain
            }
        }

        let preamp = -(maxGain + 0.5)

        return (bands: bands, preamp: preamp)
    }

    /// Інтерполює сире вимірювання для заданої частоти
    private static func interpolateRaw(measurements: [(freq: Double, raw: Double)], frequency: Double) -> Double {
        guard let first = measurements.first, let last = measurements.last else { return 0 }
        // Якщо частота за межами діапазону, повертаємо крайні значення
        if frequency <= first.freq {
            return first.raw
        }
        if frequency >= last.freq {
            return last.raw
        }

        // Лінійна інтерполяція
        for i in 0..<(measurements.count - 1) {
            let m1 = measurements[i]
            let m2 = measurements[i + 1]

            if frequency >= m1.freq, frequency <= m2.freq {
                let t = (frequency - m1.freq) / (m2.freq - m1.freq)
                return m1.raw + t * (m2.raw - m1.raw)
            }
        }

        return 0.0
    }

    // MARK: - Frequency Response Calculation

    /// Обчислює частотну характеристику для заданої частоти з урахуванням всіх фільтрів
    static func calculateFrequencyResponse(filters: [ParametricFilter], frequency: Double) -> Double {
        var totalGain = 0.0

        for filter in filters {
            switch filter.type {
            case .peaking:
                totalGain += calculatePeakingEQ(f: frequency, fc: filter.frequency, q: filter.q, gain: filter.gain)
            case .lowShelf:
                totalGain += calculateLowShelf(f: frequency, fc: filter.frequency, q: filter.q, gain: filter.gain)
            case .highShelf:
                totalGain += calculateHighShelf(f: frequency, fc: filter.frequency, q: filter.q, gain: filter.gain)
            case .lowPass:
                totalGain += calculateLowPass(f: frequency, fc: filter.frequency, q: filter.q)
            case .highPass:
                totalGain += calculateHighPass(f: frequency, fc: filter.frequency, q: filter.q)
            }
        }

        return totalGain
    }

    /// Peaking EQ (bell filter) - ТОЧНА ФОРМУЛА З AutoEQ
    private static func calculatePeakingEQ(f: Double, fc: Double, q: Double, gain: Double) -> Double {
        let sampleRate = 48000.0
        let w0 = 2.0 * .pi * fc / sampleRate
        let w = 2.0 * .pi * f / sampleRate
        let A = pow(10.0, gain / 40.0)
        let alpha = sin(w0) / (2.0 * q)

        // Biquad coefficients (як в AutoEQ - БЕЗ нормалізації)
        let a0 = 1.0 + alpha / A
        var a1 = -2.0 * cos(w0)
        var a2 = 1.0 - alpha / A

        let b0 = 1.0 + alpha * A
        let b1 = -2.0 * cos(w0)
        let b2 = 1.0 - alpha * A

        // Інвертуємо знак a1, a2 (як в AutoEQ)
        a1 *= -1.0
        a2 *= -1.0

        // Frequency response з phi формулою (ТОЧНО як в AutoEQ)
        let phi = 4.0 * pow(sin(w / 2.0), 2.0)

        let numerator = pow(b0 + b1 + b2, 2.0) +
            (b0 * b2 * phi - (b1 * (b0 + b2) + 4.0 * b0 * b2)) * phi
        let denominator = pow(a0 + a1 + a2, 2.0) +
            (a0 * a2 * phi - (a1 * (a0 + a2) + 4.0 * a0 * a2)) * phi

        // DEBUG для першого виклику
        if f == 31.5, fc == 105.0 {}

        guard numerator > 0, denominator > 0 else { return 0.0 }

        let result = 10.0 * log10(numerator) - 10.0 * log10(denominator)

        // DEBUG
        if f == 31.5, fc == 105.0 {}

        return result
    }

    /// Low Shelf filter - ТОЧНА ФОРМУЛА З AutoEQ
    private static func calculateLowShelf(f: Double, fc: Double, q: Double, gain: Double) -> Double {
        let sampleRate = 48000.0
        let w0 = 2.0 * .pi * fc / sampleRate
        let w = 2.0 * .pi * f / sampleRate
        let A = pow(10.0, gain / 40.0)
        let alpha = sin(w0) / (2.0 * q)

        // Biquad coefficients (БЕЗ нормалізації)
        let a0 = (A + 1) + (A - 1) * cos(w0) + 2 * sqrt(A) * alpha
        var a1 = -2 * ((A - 1) + (A + 1) * cos(w0))
        var a2 = (A + 1) + (A - 1) * cos(w0) - 2 * sqrt(A) * alpha

        let b0 = A * ((A + 1) - (A - 1) * cos(w0) + 2 * sqrt(A) * alpha)
        let b1 = 2 * A * ((A - 1) - (A + 1) * cos(w0))
        let b2 = A * ((A + 1) - (A - 1) * cos(w0) - 2 * sqrt(A) * alpha)

        // Інвертуємо знак
        a1 *= -1.0
        a2 *= -1.0

        // Frequency response з phi формулою
        let phi = 4.0 * pow(sin(w / 2.0), 2.0)

        let numerator = pow(b0 + b1 + b2, 2.0) +
            (b0 * b2 * phi - (b1 * (b0 + b2) + 4.0 * b0 * b2)) * phi
        let denominator = pow(a0 + a1 + a2, 2.0) +
            (a0 * a2 * phi - (a1 * (a0 + a2) + 4.0 * a0 * a2)) * phi

        // DEBUG
        if f == 31.5, fc == 105.0 {}

        guard numerator > 0, denominator > 0 else { return 0.0 }

        let result = 10.0 * log10(numerator) - 10.0 * log10(denominator)

        if f == 31.5, fc == 105.0 {}

        return result
    }

    /// High Shelf filter - ТОЧНА ФОРМУЛА З AutoEQ
    private static func calculateHighShelf(f: Double, fc: Double, q: Double, gain: Double) -> Double {
        let sampleRate = 48000.0
        let w0 = 2.0 * .pi * fc / sampleRate
        let w = 2.0 * .pi * f / sampleRate
        let A = pow(10.0, gain / 40.0)
        let alpha = sin(w0) / (2.0 * q)

        // Biquad coefficients (БЕЗ нормалізації)
        let a0 = (A + 1) - (A - 1) * cos(w0) + 2 * sqrt(A) * alpha
        var a1 = 2 * ((A - 1) - (A + 1) * cos(w0))
        var a2 = (A + 1) - (A - 1) * cos(w0) - 2 * sqrt(A) * alpha

        let b0 = A * ((A + 1) + (A - 1) * cos(w0) + 2 * sqrt(A) * alpha)
        let b1 = -2 * A * ((A - 1) + (A + 1) * cos(w0))
        let b2 = A * ((A + 1) + (A - 1) * cos(w0) - 2 * sqrt(A) * alpha)

        // Інвертуємо знак
        a1 *= -1.0
        a2 *= -1.0

        // Frequency response з phi формулою
        let phi = 4.0 * pow(sin(w / 2.0), 2.0)

        let numerator = pow(b0 + b1 + b2, 2.0) +
            (b0 * b2 * phi - (b1 * (b0 + b2) + 4.0 * b0 * b2)) * phi
        let denominator = pow(a0 + a1 + a2, 2.0) +
            (a0 * a2 * phi - (a1 * (a0 + a2) + 4.0 * a0 * a2)) * phi

        guard numerator > 0, denominator > 0 else { return 0.0 }

        return 10.0 * log10(numerator) - 10.0 * log10(denominator)
    }

    /// Low Pass filter - ТОЧНА ФОРМУЛА З AutoEQ
    private static func calculateLowPass(f: Double, fc: Double, q: Double) -> Double {
        let sampleRate = 48000.0
        let w0 = 2.0 * .pi * fc / sampleRate
        let w = 2.0 * .pi * f / sampleRate
        let alpha = sin(w0) / (2.0 * q)

        // Biquad coefficients (БЕЗ нормалізації)
        let a0 = 1 + alpha
        var a1 = -2 * cos(w0)
        var a2 = 1 - alpha

        let b0 = (1 - cos(w0)) / 2
        let b1 = 1 - cos(w0)
        let b2 = (1 - cos(w0)) / 2

        // Інвертуємо знак
        a1 *= -1.0
        a2 *= -1.0

        // Frequency response з phi формулою
        let phi = 4.0 * pow(sin(w / 2.0), 2.0)

        let numerator = pow(b0 + b1 + b2, 2.0) +
            (b0 * b2 * phi - (b1 * (b0 + b2) + 4.0 * b0 * b2)) * phi
        let denominator = pow(a0 + a1 + a2, 2.0) +
            (a0 * a2 * phi - (a1 * (a0 + a2) + 4.0 * a0 * a2)) * phi

        guard numerator > 0, denominator > 0 else { return 0.0 }

        return 10.0 * log10(numerator) - 10.0 * log10(denominator)
    }

    /// High Pass filter - ТОЧНА ФОРМУЛА З AutoEQ
    private static func calculateHighPass(f: Double, fc: Double, q: Double) -> Double {
        let sampleRate = 48000.0
        let w0 = 2.0 * .pi * fc / sampleRate
        let w = 2.0 * .pi * f / sampleRate
        let alpha = sin(w0) / (2.0 * q)

        // Biquad coefficients (БЕЗ нормалізації)
        let a0 = 1 + alpha
        var a1 = -2 * cos(w0)
        var a2 = 1 - alpha

        let b0 = (1 + cos(w0)) / 2
        let b1 = -(1 + cos(w0))
        let b2 = (1 + cos(w0)) / 2

        // Інвертуємо знак
        a1 *= -1.0
        a2 *= -1.0

        // Frequency response з phi формулою
        let phi = 4.0 * pow(sin(w / 2.0), 2.0)

        let numerator = pow(b0 + b1 + b2, 2.0) +
            (b0 * b2 * phi - (b1 * (b0 + b2) + 4.0 * b0 * b2)) * phi
        let denominator = pow(a0 + a1 + a2, 2.0) +
            (a0 * a2 * phi - (a1 * (a0 + a2) + 4.0 * a0 * a2)) * phi

        guard numerator > 0, denominator > 0 else { return 0.0 }

        return 10.0 * log10(numerator) - 10.0 * log10(denominator)
    }

    // MARK: - Target Curves

    /// JM-1 target curve - ТОЧНІ ЗНАЧЕННЯ З AutoEQ
    static func getJM1TargetGain(frequency: Double) -> Double {
        // Точні значення з JM-1 with Harman filters.csv (кожна 5-та точка для оптимізації)
        let jm1Points: [(freq: Double, gain: Double)] = [
            (20.0, 4.538), (25.0, 4.563), (30.0, 4.570), (35.0, 4.563), (40.0, 4.536),
            (45.0, 4.483), (50.0, 4.399), (55.0, 4.273), (60.0, 4.121), (65.0, 3.927),
            (70.0, 3.698), (75.0, 3.437), (80.0, 3.152), (85.0, 2.850), (90.0, 2.539),
            (95.0, 2.225), (100.0, 1.917), (106.0, 1.559), (112.0, 1.224), (118.0, 0.916),
            (125.0, 0.595), (132.0, 0.314), (140.0, 0.041), (150.0, -0.235), (160.0, -0.445),
            (170.0, -0.602), (180.0, -0.718), (190.0, -0.798), (200.0, -0.855), (212.0, -0.898),
            (227.0, -0.917), (243.0, -0.912), (262.0, -0.883), (280.0, -0.839), (300.0, -0.781),
            (325.0, -0.689), (350.0, -0.598), (375.0, -0.499), (400.0, -0.392), (425.0, -0.277),
            (450.0, -0.157), (475.0, -0.034), (500.0, 0.090), (530.0, 0.236), (560.0, 0.379),
            (590.0, 0.512), (622.0, 0.640), (650.0, 0.742), (680.0, 0.839), (710.0, 0.926),
            (740.0, 1.004), (775.0, 1.085), (812.0, 1.164), (850.0, 1.242), (885.0, 1.315),
            (925.0, 1.407), (962.0, 1.506), (1000.0, 1.623), (1044.0, 1.780), (1090.0, 1.961),
            (1138.0, 2.164), (1180.0, 2.347), (1220.0, 2.525), (1265.0, 2.726), (1315.0, 2.951),
            (1360.0, 3.152), (1400.0, 3.330), (1450.0, 3.553), (1500.0, 3.776), (1550.0, 4.001),
            (1600.0, 4.230), (1650.0, 4.463), (1700.0, 4.702), (1750.0, 4.948), (1800.0, 5.203),
            (1850.0, 5.470), (1900.0, 5.750), (1950.0, 6.041), (2000.0, 6.342), (2060.0, 6.707),
            (2120.0, 7.067), (2180.0, 7.412), (2240.0, 7.733), (2300.0, 8.025), (2360.0, 8.284),
            (2430.0, 8.548), (2500.0, 8.774), (2580.0, 8.995), (2650.0, 9.166), (2720.0, 9.323),
            (2800.0, 9.488), (2900.0, 9.671), (3000.0, 9.815), (3110.0, 9.911), (3200.0, 9.930),
            (3300.0, 9.891), (3400.0, 9.792), (3500.0, 9.645), (3600.0, 9.460), (3700.0, 9.248),
            (3820.0, 8.970), (3950.0, 8.654), (4060.0, 8.384), (4180.0, 8.093), (4310.0, 7.789),
            (4440.0, 7.500), (4550.0, 7.271), (4680.0, 7.021), (4820.0, 6.776), (4940.0, 6.588),
            (5080.0, 6.393), (5220.0, 6.223), (5380.0, 6.057), (5520.0, 5.935), (5700.0, 5.806),
            (5900.0, 5.697), (6080.0, 5.628), (6300.0, 5.576), (6500.0, 5.556), (6700.0, 5.559),
            (6900.0, 5.577), (7100.0, 5.603), (7300.0, 5.628), (7500.0, 5.637), (7750.0, 5.599),
            (8000.0, 5.477), (8250.0, 5.254), (8500.0, 4.951), (8750.0, 4.598), (9000.0, 4.221),
            (9250.0, 3.836), (9500.0, 3.448), (9750.0, 3.061), (10000.0, 2.676), (10300.0, 2.220),
            (10600.0, 1.773), (10900.0, 1.341), (11200.0, 0.928), (11500.0, 0.539), (11800.0, 0.180),
            (12200.0, -0.251), (12500.0, -0.537), (12800.0, -0.790), (13200.0, -1.092), (13600.0, -1.361),
            (14000.0, -1.611), (14500.0, -1.911), (15000.0, -2.214), (15500.0, -2.530), (16000.0, -2.864),
            (16500.0, -3.218), (17000.0, -3.589), (17500.0, -3.971), (18000.0, -4.354), (18500.0, -4.732),
            (19000.0, -5.111), (19500.0, -5.771), (20000.0, -7.158)
        ]

        // Linear interpolation
        guard let first = jm1Points.first, let last = jm1Points.last else { return 0 }
        if frequency <= first.freq {
            return first.gain
        }
        if frequency >= last.freq {
            return last.gain
        }

        for i in 0..<(jm1Points.count - 1) {
            let p1 = jm1Points[i]
            let p2 = jm1Points[i + 1]

            if frequency >= p1.freq, frequency <= p2.freq {
                let t = (frequency - p1.freq) / (p2.freq - p1.freq)
                return p1.gain + t * (p2.gain - p1.gain)
            }
        }

        return 0.0
    }

    /// Harman target curve - ТОЧНІ ЗНАЧЕННЯ З AutoEQ
    static func getHarmanTargetGain(frequency: Double) -> Double {
        // Точні значення з Harman over-ear 2018.csv (кожна 10-та точка для оптимізації)
        let harmanPoints: [(freq: Double, gain: Double)] = [
            (20.0, 3.86), (30.0, 3.96), (40.0, 3.70), (50.0, 3.30), (60.0, 2.88),
            (70.0, 2.43), (80.0, 1.96), (90.0, 1.50), (100.0, 1.04), (110.0, 0.55),
            (120.0, 0.07), (130.0, -0.34), (140.0, -0.66), (150.0, -0.92), (160.0, -1.16),
            (170.0, -1.39), (180.0, -1.62), (190.0, -1.82), (200.0, -1.96), (210.0, -2.05),
            (220.0, -2.08), (230.0, -2.08), (240.0, -2.06), (250.0, -2.02), (260.0, -1.95),
            (270.0, -1.87), (280.0, -1.79), (290.0, -1.73), (300.0, -1.67), (310.0, -1.60),
            (320.0, -1.50), (330.0, -1.44), (340.0, -1.38), (350.0, -1.32), (360.0, -1.27),
            (370.0, -1.22), (380.0, -1.17), (390.0, -1.14), (400.0, -1.13), (410.0, -1.11),
            (420.0, -1.08), (430.0, -1.06), (440.0, -1.02), (450.0, -1.00), (460.0, -0.96),
            (470.0, -0.93), (480.0, -0.90), (490.0, -0.86), (500.0, -0.83), (520.0, -0.76),
            (540.0, -0.69), (560.0, -0.64), (580.0, -0.58), (600.0, -0.52), (620.0, -0.48),
            (640.0, -0.42), (660.0, -0.37), (680.0, -0.34), (700.0, -0.30), (720.0, -0.27),
            (740.0, -0.24), (760.0, -0.22), (780.0, -0.20), (800.0, -0.18), (820.0, -0.16),
            (840.0, -0.15), (860.0, -0.14), (880.0, -0.13), (900.0, -0.11), (920.0, -0.09),
            (940.0, -0.08), (960.0, -0.06), (980.0, -0.03), (1000.0, 0.00), (1020.0, 0.04),
            (1040.0, 0.08), (1060.0, 0.12), (1080.0, 0.18), (1100.0, 0.24), (1120.0, 0.31),
            (1140.0, 0.40), (1160.0, 0.48), (1180.0, 0.53), (1200.0, 0.63), (1220.0, 0.74),
            (1240.0, 0.79), (1260.0, 0.91), (1280.0, 0.97), (1300.0, 1.10), (1320.0, 1.17),
            (1340.0, 1.24), (1360.0, 1.38), (1380.0, 1.46), (1400.0, 1.60), (1420.0, 1.67),
            (1440.0, 1.82), (1460.0, 1.89), (1480.0, 2.03), (1500.0, 2.11), (1520.0, 2.20),
            (1540.0, 2.37), (1560.0, 2.46), (1580.0, 2.55), (1600.0, 2.73), (1620.0, 2.83),
            (1640.0, 2.93), (1660.0, 3.14), (1680.0, 3.24), (1700.0, 3.35), (1720.0, 3.46),
            (1740.0, 3.58), (1760.0, 3.69), (1780.0, 3.81), (1800.0, 4.04), (1820.0, 4.16),
            (1840.0, 4.29), (1860.0, 4.41), (1880.0, 4.53), (1900.0, 4.65), (1920.0, 4.78),
            (1940.0, 4.91), (1960.0, 5.04), (1980.0, 5.16), (2000.0, 5.29), (2040.0, 5.50),
            (2080.0, 5.71), (2120.0, 5.92), (2160.0, 6.13), (2200.0, 6.33), (2240.0, 6.54),
            (2280.0, 6.63), (2320.0, 6.83), (2360.0, 7.01), (2400.0, 7.16), (2440.0, 7.31),
            (2480.0, 7.46), (2520.0, 7.52), (2560.0, 7.65), (2600.0, 7.71), (2640.0, 7.77),
            (2680.0, 7.88), (2720.0, 7.94), (2760.0, 8.04), (2800.0, 8.09), (2840.0, 8.13),
            (2880.0, 8.20), (2920.0, 8.23), (2960.0, 8.30), (3000.0, 8.33), (3040.0, 8.37),
            (3080.0, 8.44), (3120.0, 8.47), (3160.0, 8.50), (3200.0, 8.51), (3240.0, 8.54),
            (3280.0, 8.56), (3320.0, 8.57), (3360.0, 8.58), (3400.0, 8.58), (3440.0, 8.57),
            (3480.0, 8.57), (3520.0, 8.57), (3560.0, 8.56), (3600.0, 8.53), (3640.0, 8.49),
            (3680.0, 8.46), (3720.0, 8.44), (3760.0, 8.40), (3800.0, 8.36), (3840.0, 8.32),
            (3880.0, 8.28), (3920.0, 8.25), (3960.0, 8.21), (4000.0, 8.16), (4040.0, 8.10),
            (4080.0, 8.04), (4120.0, 7.99), (4160.0, 7.93), (4200.0, 7.87), (4240.0, 7.81),
            (4280.0, 7.73), (4320.0, 7.65), (4360.0, 7.58), (4400.0, 7.50), (4440.0, 7.42),
            (4480.0, 7.34), (4520.0, 7.25), (4560.0, 7.17), (4600.0, 7.08), (4640.0, 6.99),
            (4680.0, 6.91), (4720.0, 6.81), (4760.0, 6.72), (4800.0, 6.63), (4840.0, 6.53),
            (4880.0, 6.44), (4920.0, 6.36), (4960.0, 6.28), (5000.0, 6.21), (5040.0, 6.13),
            (5080.0, 6.05), (5120.0, 5.97), (5160.0, 5.89), (5200.0, 5.81), (5240.0, 5.74),
            (5280.0, 5.66), (5320.0, 5.58), (5360.0, 5.52), (5400.0, 5.45), (5440.0, 5.39),
            (5480.0, 5.33), (5520.0, 5.27), (5560.0, 5.21), (5600.0, 5.14), (5640.0, 5.06),
            (5680.0, 4.97), (5720.0, 4.88), (5760.0, 4.79), (5800.0, 4.70), (5840.0, 4.62),
            (5880.0, 4.54), (5920.0, 4.47), (5960.0, 4.39), (6000.0, 4.31), (6040.0, 4.23),
            (6080.0, 4.15), (6120.0, 4.06), (6160.0, 3.96), (6200.0, 3.87), (6240.0, 3.78),
            (6280.0, 3.69), (6320.0, 3.59), (6360.0, 3.48), (6400.0, 3.37), (6440.0, 3.26),
            (6480.0, 3.15), (6520.0, 3.04), (6560.0, 2.94), (6600.0, 2.84), (6640.0, 2.74),
            (6680.0, 2.64), (6720.0, 2.54), (6760.0, 2.44), (6800.0, 2.33), (6840.0, 2.22),
            (6880.0, 2.10), (6920.0, 1.99), (6960.0, 1.88), (7000.0, 1.77), (7040.0, 1.64),
            (7080.0, 1.51), (7120.0, 1.38), (7160.0, 1.25), (7200.0, 1.12), (7240.0, 1.00),
            (7280.0, 0.85), (7320.0, 0.70), (7360.0, 0.55), (7400.0, 0.41), (7440.0, 0.26),
            (7480.0, 0.10), (7520.0, -0.08), (7560.0, -0.25), (7600.0, -0.43), (7640.0, -0.60),
            (7680.0, -0.77), (7720.0, -0.94), (7760.0, -1.11), (7800.0, -1.28), (7840.0, -1.45),
            (7880.0, -1.62), (7920.0, -1.80), (7960.0, -2.00), (8000.0, -2.19), (8040.0, -2.39),
            (8080.0, -2.59), (8120.0, -2.78), (8160.0, -3.00), (8200.0, -3.22), (8240.0, -3.43),
            (8280.0, -3.65), (8320.0, -3.87), (8360.0, -4.06), (8400.0, -4.26), (8440.0, -4.45),
            (8480.0, -4.64), (8520.0, -4.83), (8560.0, -5.02), (8600.0, -5.21), (8640.0, -5.40),
            (8680.0, -5.59), (8720.0, -5.78), (8760.0, -5.97), (8800.0, -6.15), (8840.0, -6.30),
            (8880.0, -6.46), (8920.0, -6.62), (8960.0, -6.78), (9000.0, -6.94), (9040.0, -7.09),
            (9080.0, -7.22), (9120.0, -7.36), (9160.0, -7.50), (9200.0, -7.63), (9240.0, -7.77),
            (9280.0, -7.91), (9320.0, -8.08), (9360.0, -8.26), (9400.0, -8.44), (9440.0, -8.63),
            (9480.0, -8.81), (9520.0, -8.99), (9560.0, -9.20), (9600.0, -9.49), (9640.0, -9.78),
            (9680.0, -10.07), (9720.0, -10.36), (9760.0, -10.65), (9800.0, -10.96), (9840.0, -11.44),
            (9880.0, -11.91), (9920.0, -12.39), (9960.0, -12.86), (10000.0, -13.34), (10200.0, -15.39),
            (10400.0, -16.88), (10600.0, -18.66), (10800.0, -19.73), (11000.0, -20.79), (11200.0, -21.86),
            (11400.0, -22.92), (12000.0, -22.92), (15000.0, -22.92), (20000.0, -22.92)
        ]

        // Linear interpolation
        guard let first = harmanPoints.first, let last = harmanPoints.last else { return 0 }
        if frequency <= first.freq {
            return first.gain
        }
        if frequency >= last.freq {
            return last.gain
        }

        for i in 0..<(harmanPoints.count - 1) {
            let p1 = harmanPoints[i]
            let p2 = harmanPoints[i + 1]

            if frequency >= p1.freq, frequency <= p2.freq {
                let t = (frequency - p1.freq) / (p2.freq - p1.freq)
                return p1.gain + t * (p2.gain - p1.gain)
            }
        }

        return 0.0
    }
}
