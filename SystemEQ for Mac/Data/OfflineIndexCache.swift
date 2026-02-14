//
//  OfflineIndexCache.swift
//  SystemEQ for Mac
//
//  Created by Denys Zamorniak on 07/10/25.
//

import Foundation

public struct OfflineIndexCache: Codable {
    public let version: Int
    public let entries: [OfflineIndexEntry]
    public let lastUpdate: TimeInterval

    public init(version: Int, entries: [OfflineIndexEntry], lastUpdate: TimeInterval) {
        self.version = version
        self.entries = entries
        self.lastUpdate = lastUpdate
    }
}
