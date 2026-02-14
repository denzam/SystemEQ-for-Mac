//
//  AnimatedText.swift
//  SystemEQ for Mac
//
//  Animated text transitions for language changes
//

import SwiftUI

// MARK: - Custom Blur Transition

extension AnyTransition {
    static var blur: AnyTransition {
        .modifier(active: BlurModifier(radius: 10), identity: BlurModifier(radius: 0))
    }
}

struct BlurModifier: ViewModifier {
    let radius: CGFloat

    func body(content: Content) -> some View {
        content.blur(radius: radius)
    }
}

// MARK: - Animated Text View

struct AnimatedText: View {
    let text: String
    let animation: Animation

    @State private var opacity: Double = 1.0
    @State private var blurRadius: CGFloat = 0

    init(_ text: String, animation: Animation = .easeInOut(duration: 0.1)) {
        self.text = text
        self.animation = animation
    }

    var body: some View {
        Text(text)
            .opacity(opacity)
            .blur(radius: blurRadius)
            .onAppear {
                withAnimation(animation) {
                    opacity = 1.0
                    blurRadius = 0
                }
            }
            .onChange(of: text) { _ in
                // Blur and fade out, then fade in with new text
                withAnimation(.easeInOut(duration: 0.1)) {
                    opacity = 0.0
                    blurRadius = 10
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.easeInOut(duration: 0.1)) {
                        opacity = 1.0
                        blurRadius = 0
                    }
                }
            }
    }
}

// MARK: - View Extension for Animation Duration

extension Animation {
    var duration: TimeInterval {
        switch self {
        case .easeInOut:
            0.3
        case .linear:
            0.3
        case .spring:
            0.5
        default:
            0.3
        }
    }
}

// MARK: - View Extension for animatedLocalization

extension View {
    func animatedLocalization() -> some View {
        self.modifier(AnimatedLocalizationModifier())
    }
}

struct AnimatedLocalizationModifier: ViewModifier {
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            .id(id)
            .onReceive(NotificationCenter.default.publisher(for: .languageChanged)) { _ in
                dlog("AnimatedLocalizationModifier received language change", category: .ui)
                // Force view recreation with transaction
                withTransaction(Transaction(animation: .easeInOut(duration: 0.3))) {
                    id = UUID()
                }
            }
    }
}
