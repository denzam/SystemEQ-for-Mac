import Foundation

struct ProjectMAdaptiveFPS {
    enum Decision: Equatable {
        case warmup
        case unchanged
        case reduceScale(to: Double)
        case skipPreset
    }

    static let minScale = 0.25
    static let targetMinFPS = 30
    static let lowFPSSecondsToSkip = 2

    private(set) var adaptiveScale = 1.0
    private var lowFPSSeconds = 0
    private var isWarmup = true

    mutating func observe(
        measuredFPS: Int,
        presetLocked: Bool,
        hasPresetPath: Bool
    ) -> Decision {
        if isWarmup {
            isWarmup = false
            return .warmup
        }
        guard measuredFPS > 0 else { return .unchanged }

        if measuredFPS < Self.targetMinFPS {
            if adaptiveScale > Self.minScale {
                adaptiveScale = max(Self.minScale, adaptiveScale - 0.25)
                lowFPSSeconds = 0
                return .reduceScale(to: adaptiveScale)
            }

            lowFPSSeconds += 1
            if lowFPSSeconds >= Self.lowFPSSecondsToSkip, !presetLocked, hasPresetPath {
                lowFPSSeconds = 0
                return .skipPreset
            }
        } else {
            lowFPSSeconds = 0
        }

        return .unchanged
    }

    mutating func reset() {
        adaptiveScale = 1.0
        lowFPSSeconds = 0
        isWarmup = true
    }
}
