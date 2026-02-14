//
//  CandidateCache.swift
//  SystemEQ for Mac
//
//  Created by Denys Zamorniak on 07/10/25.
//

import Foundation

// MARK: - Candidate Cache Types

public struct CandidateCache: Codable {
    public let ts: TimeInterval
    public let items: [CandidateDTO]

    public init(ts: TimeInterval, items: [CandidateDTO]) {
        self.ts = ts
        self.items = items
    }
}

public struct CandidateDTO: Codable {
    public let path: String
    public let name: String
    public let display: String
    public let isParametric: Bool

    public init(path: String, name: String, display: String, isParametric: Bool) {
        self.path = path
        self.name = name
        self.display = display
        self.isParametric = isParametric
    }
}
