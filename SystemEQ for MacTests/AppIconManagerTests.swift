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
            let icon = manager.localizedIcon(for: language)
            XCTAssertNotNil(icon, "Icon should not be nil for \(language.displayName)")
            if let image = icon {
                XCTAssertGreaterThan(image.size.width, 0, "Icon width should be positive for \(language.displayName)")
                XCTAssertGreaterThan(image.size.height, 0, "Icon height should be positive for \(language.displayName)")
            }
        }
    }

    func testApplyIconUsesRequestedLanguageImage() {
        let images = [
            "AppIcon_EN": NSImage(size: NSSize(width: 16, height: 16)),
            "AppIcon_IT": NSImage(size: NSSize(width: 32, height: 32)),
            "AppIcon_UK": NSImage(size: NSSize(width: 64, height: 64))
        ]
        var applied: [NSImage?] = []
        let manager = AppIconManager(
            imageProvider: { images[$0] },
            iconSetter: { applied.append($0) },
            observesLanguageChanges: false
        )
        for language in AppLanguage.allCases {
            manager.applyIcon(for: language)
        }
        XCTAssertEqual(applied.count, 3)
        XCTAssertTrue(applied[0] === images["AppIcon_EN"])
        XCTAssertTrue(applied[1] === images["AppIcon_IT"])
        XCTAssertTrue(applied[2] === images["AppIcon_UK"])
    }

    func testMissingLanguageAssetDoesNotMasqueradeAsLocalizedAsset() {
        let fallback = NSImage(size: NSSize(width: 16, height: 16))
        var applied: NSImage?
        let manager = AppIconManager(
            imageProvider: { $0 == NSImage.applicationIconName ? fallback : nil },
            iconSetter: { applied = $0 }, observesLanguageChanges: false
        )
        XCTAssertNil(manager.localizedIcon(for: .ukrainian))
        manager.applyIcon(for: .ukrainian)
        XCTAssertTrue(applied === fallback)
    }
}
