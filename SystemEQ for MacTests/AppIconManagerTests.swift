//
//  AppIconManagerTests.swift
//  SystemEQ for MacTests
//

@testable import SystemEQ_for_Mac
import XCTest

@MainActor
final class AppIconManagerTests: XCTestCase {
    func testIconRetrievalForAllLanguages() {
        let manager = AppIconManager.shared

        for language in AppLanguage.allCases {
            let icon = manager.icon(for: language)
            XCTAssertNotNil(icon, "Icon should not be nil for \(language.displayName)")
            if let image = icon {
                XCTAssertGreaterThan(image.size.width, 0, "Icon width should be positive for \(language.displayName)")
                XCTAssertGreaterThan(image.size.height, 0, "Icon height should be positive for \(language.displayName)")
            }
        }
    }

    func testApplyIconDoesNotCrash() {
        let manager = AppIconManager.shared
        // Verification that applyIcon executes cleanly for each language
        for language in AppLanguage.allCases {
            manager.applyIcon(for: language)
        }
    }
}
