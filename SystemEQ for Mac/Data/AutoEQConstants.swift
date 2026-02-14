//
//  AutoEQConstants.swift
//  SystemEQ for Mac
//
//  Created by Denys Zamorniak on 07/10/25.
//

import Foundation

public enum BandMode: String, CaseIterable {
    case ten = "10"
    case thirtyOne = "31"
}

public enum AutoEQConstants {
    public static let tenBandFrequencies: [Float] = [
        31.5, 63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000
    ]

    public static let thirtyOneBandFrequencies: [Float] = [
        20, 25, 31.5, 40, 50, 63, 80, 100, 125, 160,
        200, 250, 315, 400, 500, 630, 800, 1000, 1250, 1600,
        2000, 2500, 3150, 4000, 5000, 6300, 8000, 10000, 12500, 16000,
        20000
    ]

    public static let thirtyOneCenters: [Float] = thirtyOneBandFrequencies
}
