//
//  AppIconManager.swift
//  SystemEQ for Mac
//

import AppKit
import Combine

// MARK: - App Icon Manager

/// Керує динамічним перемиканням іконки програми (Dock, App Switcher, UI)
/// відповідно до вибраної мови інтерфейсу.
@MainActor
public final class AppIconManager: ObservableObject {
    public static let shared = AppIconManager()

    private var cancellables = Set<AnyCancellable>()

    private init() {
        bindLanguageChanges()
    }

    /// Підписка на зміну мови для автоматичного оновлення іконки Dock
    private func bindLanguageChanges() {
        NotificationCenter.default.publisher(for: .languageChanged)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.applyIcon(for: LocalizationManager.shared.currentLanguage)
            }
            .store(in: &cancellables)
    }

    /// Застосовує іконку обраної мови до Dock (NSApp.applicationIconImage)
    public func applyIcon(for language: AppLanguage) {
        guard !ProcessInfo.processInfo.environment.keys.contains("XCTestConfigurationFilePath") else { return }

        if let image = icon(for: language) {
            NSApp.applicationIconImage = image
            dlog("🎨 Applied Dock icon for language: \(language.displayName)", category: .general)
        } else {
            NSApp.applicationIconImage = nil
            dlog("🎨 Reset Dock icon to default for language: \(language.displayName)", category: .general)
        }
    }

    /// Повертає NSImage для вказаної мови
    public func icon(for language: AppLanguage) -> NSImage? {
        let name = switch language {
        case .english:
            "AppIcon_EN"
        case .italian:
            "AppIcon_IT"
        case .ukrainian:
            "AppIcon_UK"
        }

        // Спершу шукаємо в Asset Catalog
        if let image = NSImage(named: NSImage.Name(name)) {
            return image
        }

        // Перевіряємо бандл класу (корисно для тестів та кастомних середовищ)
        let bundle = Bundle(for: Self.self)
        if let image = bundle.image(forResource: NSImage.Name(name)) {
            return image
        }

        // Fallback до стандартної іконки програми
        return NSImage(named: NSImage.applicationIconName)
    }
}
