//
//  EQDatabaseTest.swift
//  SystemEQ for Mac
//
//  Test suite for EQDatabase
//

import Foundation

#if DEBUG
    class EQDatabaseTest {
        static func runTests() {
            dlog("Testing EQDatabase...", category: .database)

            // Check if database is available
            guard EQDatabase.shared.isAvailable else {
                dlog("EQDatabase not available - skipping tests", level: .warning, category: .database)
                return
            }

            // Test 1: Database stats
            let stats = EQDatabase.shared.getDatabaseStats()
            dlog(
                "Database loaded: \(stats.headphones) headphones, \(stats.presets) presets, \(stats.sizeMB) MB",
                category: .database
            )

            // Test 2: Search
            let results = EQDatabase.shared.searchHeadphones("Sennheiser HD 600")
            dlog("Search results: \(results.count) found", category: .database)
            if let first = results.first {
                dlog("First result: \(first.displayName)", category: .database)
            }

            // Test 3: Get presets
            if let headphone = results.first {
                let presets = EQDatabase.shared.getPresets(for: headphone.id)
                dlog("Presets for \(headphone.displayName): \(presets.count)", category: .database)

                if let preset = presets.first {
                    dlog("Preset: \(preset.displayName), Preamp: \(preset.preampGain) dB", category: .database)

                    // Test 4: Get EQ bands
                    let bands10 = EQDatabase.shared.getFixedBand10(presetId: preset.id)
                    dlog("10-band EQ: \(bands10.count) bands", category: .database)

                    let bands31 = EQDatabase.shared.getGraphicEQ31(presetId: preset.id)
                    dlog("31-band EQ: \(bands31.count) bands", category: .database)
                }
            }

            dlog("All EQDatabase tests passed!", level: .info, category: .database)
        }
    }
#endif
