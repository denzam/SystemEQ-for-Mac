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
    private let imageProvider: (String) -> NSImage?
    private let iconSetter: (NSImage?) -> Void

    private convenience init() {
        self.init(imageProvider: { name in
            NSImage(named: NSImage.Name(name)) ?? Bundle(for: AppIconManager.self)
                .image(forResource: NSImage.Name(name))
        }, iconSetter: { NSApp.applicationIconImage = $0 })
    }

    init(
        imageProvider: @escaping (String) -> NSImage?,
        iconSetter: @escaping (NSImage?) -> Void,
        observesLanguageChanges: Bool = true
    ) {
        self.imageProvider = imageProvider
        self.iconSetter = iconSetter
        if observesLanguageChanges { bindLanguageChanges() }
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
        if let image = icon(for: language) {
            iconSetter(image)
            dlog("🎨 Applied Dock icon for language: \(language.displayName)", category: .general)
        } else {
            iconSetter(nil)
            dlog("🎨 Reset Dock icon to default for language: \(language.displayName)", category: .general)
        }
    }

    /// Повертає NSImage для вказаної мови
    public func icon(for language: AppLanguage) -> NSImage? {
        localizedIcon(for: language) ?? imageProvider(NSImage.applicationIconName)
    }

    func localizedIcon(for language: AppLanguage) -> NSImage? {
        let name = switch language {
        case .english:
            "AppIcon_EN"
        case .italian:
            "AppIcon_IT"
        case .ukrainian:
            "AppIcon_UK"
        }

        return imageProvider(name)
    }
}
