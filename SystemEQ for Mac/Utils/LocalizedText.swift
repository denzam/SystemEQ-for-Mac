//
//  LocalizedText.swift
//  SystemEQ for Mac
//
//  Text with smooth language transition animations
//

import SwiftUI

// MARK: - Localized Text with Animation

struct LocalizedText: View {
    let key: LocalizedString
    let localization: LocalizationManager

    @State private var currentText: String = ""
    @State private var isAnimating = false

    init(_ key: LocalizedString, localization: LocalizationManager = .shared) {
        self.key = key
        self.localization = localization
    }

    var body: some View {
        Text(currentText)
            .contentTransition(.opacity) // Use opacity transition for macOS 13 compatibility
            .onReceive(NotificationCenter.default.publisher(for: .languageChanged)) { _ in
                withAnimation(.easeInOut(duration: 0.3)) {
                    updateText()
                }
            }
            .onAppear {
                updateText()
            }
            .onChange(of: localization.currentLanguage) { _ in
                withAnimation(.easeInOut(duration: 0.3)) {
                    updateText()
                }
            }
    }

    private func updateText() {
        let newText = localization.localized(key)
        if newText != currentText {
            currentText = newText
        }
    }
}

// MARK: - Alternative: Smooth Fade Text

struct SmoothFadeText: View {
    let key: LocalizedString
    let localization: LocalizationManager

    @State private var opacity: Double = 1.0
    @State private var currentText: String = ""

    init(_ key: LocalizedString, localization: LocalizationManager = .shared) {
        self.key = key
        self.localization = localization
    }

    var body: some View {
        Text(currentText)
            .opacity(opacity)
            .onReceive(NotificationCenter.default.publisher(for: .languageChanged)) { _ in
                // Fade out
                withAnimation(.easeInOut(duration: 0.3)) {
                    opacity = 0.0
                }

                // Change text and fade in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    currentText = localization.localized(key)
                    withAnimation(.easeInOut(duration: 0.3)) {
                        opacity = 1.0
                    }
                }
            }
            .onAppear {
                currentText = localization.localized(key)
            }
    }
}

// MARK: - Slide Transition Text

struct SlideText: View {
    let key: LocalizedString
    let localization: LocalizationManager

    @State private var offset: CGFloat = 0
    @State private var currentText: String = ""

    init(_ key: LocalizedString, localization: LocalizationManager = .shared) {
        self.key = key
        self.localization = localization
    }

    var body: some View {
        Text(currentText)
            .offset(y: offset)
            .clipped()
            .onReceive(NotificationCenter.default.publisher(for: .languageChanged)) { _ in
                // Slide up
                withAnimation(.easeInOut(duration: 0.2)) {
                    offset = -20
                }

                // Change text and slide from bottom
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    currentText = localization.localized(key)
                    offset = 20
                    withAnimation(.easeInOut(duration: 0.2)) {
                        offset = 0
                    }
                }
            }
            .onAppear {
                currentText = localization.localized(key)
            }
    }
}

// MARK: - Morph Text (Beautiful transition without fade)

struct MorphText: View {
    let key: LocalizedString
    let localization: LocalizationManager

    @State private var offset: CGFloat = 0
    @State private var scale: CGFloat = 1.0
    @State private var currentText: String = ""

    init(_ key: LocalizedString, localization: LocalizationManager = .shared) {
        self.key = key
        self.localization = localization
    }

    var body: some View {
        Text(currentText)
            .offset(y: offset)
            .scaleEffect(scale)
            .onReceive(NotificationCenter.default.publisher(for: .languageChanged)) { _ in
                // Scale down and slide up
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    scale = 0.85
                    offset = -10
                }

                // Change text and spring back
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    currentText = localization.localized(key)
                    offset = 10
                    scale = 0.85

                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        offset = 0
                        scale = 1.0
                    }
                }
            }
            .onAppear {
                currentText = localization.localized(key)
            }
    }
}

// MARK: - Crossfade Text (Smooth blur transition)

struct CrossfadeText: View {
    let key: LocalizedString
    @ObservedObject var localization: LocalizationManager

    @State private var currentText: String = ""
    @State private var opacity: Double = 1.0

    init(_ key: LocalizedString, localization: LocalizationManager = .shared) {
        self.key = key
        self.localization = localization
    }

    var body: some View {
        Text(currentText)
            .opacity(opacity)
            .onReceive(NotificationCenter.default.publisher(for: .languageChanged)) { _ in
                updateTextWithAnimation()
            }
            .onChange(of: localization.currentLanguage) { _ in
                updateTextWithAnimation()
            }
            .onAppear {
                currentText = localization.localized(key)
            }
    }

    private func updateTextWithAnimation() {
        // Fade out
        withAnimation(.easeInOut(duration: 0.15)) {
            opacity = 0.0
        }

        // Change text and fade in
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            currentText = localization.localized(key)
            withAnimation(.easeInOut(duration: 0.15)) {
                opacity = 1.0
            }
        }
    }
}

// MARK: - View Blur Modifier (Blur entire view on language change)

struct ViewBlurModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
    }
}

extension View {
    func blurOnLanguageChange() -> some View {
        self.modifier(ViewBlurModifier())
    }
}
