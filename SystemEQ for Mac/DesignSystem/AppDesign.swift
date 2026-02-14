//
//  AppDesign.swift
//  SystemEQ for Mac
//
//  Design System - єдиний стиль для всього додатку
//

import Combine
import SwiftUI

// MARK: - Glass Design Settings

enum GlassStyle: String, CaseIterable, Identifiable {
    case defaultStyle = "default"
    case subtle
    case medium
    case strong

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .defaultStyle: "Default"
        case .subtle: "Subtle"
        case .medium: "Medium"
        case .strong: "Strong (iOS-like)"
        }
    }

    var material: Material {
        switch self {
        case .defaultStyle: .ultraThinMaterial
        case .subtle: .ultraThinMaterial
        case .medium: .thinMaterial
        case .strong: .regularMaterial
        }
    }

    var baseOpacity: Double {
        switch self {
        case .defaultStyle: 0.75
        case .subtle: 0.85
        case .medium: 0.65
        case .strong: 0.55
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .defaultStyle: 12
        case .subtle: 12
        case .medium: 16
        case .strong: 20
        }
    }

    var hasGradient: Bool {
        switch self {
        case .defaultStyle,
             .subtle: false
        case .medium,
             .strong: true
        }
    }

    var shadowRadius: CGFloat {
        switch self {
        case .defaultStyle,
             .subtle: 8
        case .medium: 16
        case .strong: 24
        }
    }
}

class GlassDesignManager: ObservableObject {
    static let shared = GlassDesignManager()

    @Published var style: GlassStyle {
        didSet {
            DispatchQueue.main.async {
                UserDefaults.standard.set(self.style.rawValue, forKey: "glassStyle")
            }
        }
    }

    @Published var customOpacity: Double {
        didSet {
            DispatchQueue.main.async {
                UserDefaults.standard.set(self.customOpacity, forKey: "glassCustomOpacity")
            }
        }
    }

    @Published var useCustomOpacity: Bool {
        didSet {
            DispatchQueue.main.async {
                UserDefaults.standard.set(self.useCustomOpacity, forKey: "glassUseCustomOpacity")
            }
        }
    }

    private init() {
        let savedStyle = UserDefaults.standard.string(forKey: "glassStyle") ?? GlassStyle.defaultStyle.rawValue
        self.style = GlassStyle(rawValue: savedStyle) ?? .defaultStyle

        let savedOpacity = UserDefaults.standard.double(forKey: "glassCustomOpacity")
        self.customOpacity = savedOpacity == 0 ? 0.75 : savedOpacity

        self.useCustomOpacity = UserDefaults.standard.bool(forKey: "glassUseCustomOpacity")
    }

    var effectiveOpacity: Double {
        useCustomOpacity ? customOpacity : style.baseOpacity
    }
}

// MARK: - Colors

enum AppColors {
    // Primary Colors
    static let accent = Color.accentColor
    static let primary = Color.primary
    static let secondary = Color.secondary

    // Semantic Colors
    static let success = Color.green
    static let warning = Color.orange
    static let error = Color.red
    static let info = Color.blue

    // Background Colors
    static let background = Color(nsColor: .controlBackgroundColor)
    static let secondaryBackground = Color(nsColor: .windowBackgroundColor)
    static let tertiaryBackground = Color(nsColor: .underPageBackgroundColor)

    // Surface Colors (для карток, панелей)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let surfaceElevated = Color(nsColor: .windowBackgroundColor)

    // Border Colors
    static let border = Color.secondary.opacity(0.2)
    static let borderFocused = Color.accentColor.opacity(0.5)

    // EQ Specific
    static let eqActive = Color.green
    static let eqInactive = Color.gray
    static let eqPositiveGain = Color.blue
    static let eqNegativeGain = Color.orange

    // Favorites
    static let favoriteActive = Color.yellow
    static let favoriteInactive = Color.secondary
}

// MARK: - Typography

enum AppTypography {
    // Display (великі заголовки)
    static let displayLarge = Font.system(size: 34, weight: .bold)
    static let displayMedium = Font.system(size: 28, weight: .bold)
    static let displaySmall = Font.system(size: 24, weight: .bold)

    // Headings
    static let heading1 = Font.system(size: 22, weight: .semibold)
    static let heading2 = Font.system(size: 18, weight: .semibold)
    static let heading3 = Font.system(size: 16, weight: .semibold)

    // Body
    static let bodyLarge = Font.system(size: 15, weight: .regular)
    static let body = Font.system(size: 13, weight: .regular)
    static let bodySmall = Font.system(size: 12, weight: .regular)

    // Labels
    static let label = Font.system(size: 11, weight: .medium)
    static let labelSmall = Font.system(size: 10, weight: .medium)

    // Monospace (для значень dB, Hz)
    static let monoLarge = Font.system(size: 15, weight: .regular, design: .monospaced)
    static let mono = Font.system(size: 13, weight: .regular, design: .monospaced)
    static let monoSmall = Font.system(size: 11, weight: .regular, design: .monospaced)
}

// MARK: - Spacing

enum AppSpacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 48
}

// MARK: - Corner Radius

enum AppRadius {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 6
    static let md: CGFloat = 8
    static let lg: CGFloat = 12
    static let xl: CGFloat = 16
    static let full: CGFloat = 9999
}

// MARK: - Shadows

enum AppShadow {
    static let small = Shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
    static let medium = Shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
    static let large = Shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
}

struct Shadow {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

// MARK: - Custom Button Styles

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTypography.body)
            .foregroundColor(.white)
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.sm)
            .background(AppColors.accent)
            .cornerRadius(AppRadius.md)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTypography.body)
            .foregroundColor(AppColors.primary)
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.sm)
            .background(AppColors.surface)
            .cornerRadius(AppRadius.md)
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.md)
                    .stroke(AppColors.border, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct DestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTypography.body)
            .foregroundColor(.white)
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.sm)
            .background(AppColors.error)
            .cornerRadius(AppRadius.md)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Special Effects Colors (for glassmorphism, vibrancy)

enum AppSpecialEffects {
    static let glassBackground = Color("GlassBackgroundColor")
    static let vibrant = Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
    static let vibrantSecondary = Color(nsColor: .unemphasizedSelectedTextBackgroundColor)
}

// MARK: - Card Component

struct GlassCard<Content: View>: View {
    let content: Content
    let padding: CGFloat
    let topCornersOnly: Bool
    @ObservedObject private var glassManager = GlassDesignManager.shared

    init(padding: CGFloat = AppSpacing.lg, topCornersOnly: Bool = false, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.topCornersOnly = topCornersOnly
        self.content = content()
    }

    private var cornerShape: UnevenRoundedRectangle {
        if topCornersOnly {
            // No top corners (for windows with title bar), rounded bottom
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: glassManager.style.cornerRadius,
                bottomTrailingRadius: glassManager.style.cornerRadius,
                topTrailingRadius: 0
            )
        } else {
            // All corners rounded equally
            UnevenRoundedRectangle(
                topLeadingRadius: glassManager.style.cornerRadius,
                bottomLeadingRadius: glassManager.style.cornerRadius,
                bottomTrailingRadius: glassManager.style.cornerRadius,
                topTrailingRadius: glassManager.style.cornerRadius
            )
        }
    }

    var body: some View {
        ZStack {
            // Background material for the "frost" effect
            cornerShape
                .fill(.clear)
                .background(glassManager.style.material, in: cornerShape)

            // Custom color overlay with dynamic opacity
            cornerShape
                .fill(glassBackgroundColor)

            // Optional gradient overlay for medium/strong styles
            if glassManager.style.hasGradient {
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.15),
                        Color.white.opacity(0.05)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(cornerShape)
            }

            // The actual content
            content
                .padding(padding)
        }
        .compositingGroup()
        .overlay(
            cornerShape
                .strokeBorder(borderGradient, lineWidth: 1)
        )
        .shadow(
            color: .black.opacity(0.15),
            radius: glassManager.style.shadowRadius,
            x: 0,
            y: glassManager.style.shadowRadius / 3
        )
    }

    private var glassBackgroundColor: Color {
        if glassManager.style == .defaultStyle {
            return AppSpecialEffects.glassBackground
        }

        let baseColor = if #available(macOS 14.0, *) {
            Color(nsColor: .controlBackgroundColor)
        } else {
            Color(nsColor: .windowBackgroundColor)
        }

        return baseColor.opacity(glassManager.effectiveOpacity)
    }

    private var borderGradient: LinearGradient {
        if glassManager.style.hasGradient {
            LinearGradient(
                colors: [
                    Color.white.opacity(0.3),
                    Color.white.opacity(0.1)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            LinearGradient(
                colors: [AppColors.border.opacity(0.5)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

// MARK: - Section Header

struct SectionHeader: View {
    let title: String
    let subtitle: String?
    let action: (() -> Void)?
    let actionLabel: String?

    init(
        _ title: String,
        subtitle: String? = nil,
        actionLabel: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.actionLabel = actionLabel
        self.action = action
    }

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(title)
                    .font(AppTypography.heading2)
                    .foregroundColor(AppColors.primary)

                if let subtitle {
                    Text(subtitle)
                        .font(AppTypography.bodySmall)
                        .foregroundColor(AppColors.secondary)
                }
            }

            Spacer()

            if let action, let label = actionLabel {
                Button(action: action) {
                    Text(label)
                        .font(AppTypography.label)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.bottom, AppSpacing.sm)
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    let text: String
    let color: Color

    init(_ text: String, color: Color = AppColors.success) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(AppTypography.labelSmall)
            .foregroundColor(.white)
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, AppSpacing.xxs)
            .background(color)
            .cornerRadius(AppRadius.xs)
    }
}

// MARK: - Divider

struct AppDivider: View {
    var body: some View {
        Rectangle()
            .fill(AppColors.border)
            .frame(height: 1)
    }
}

// MARK: - Window Container

struct WindowContainer<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background)
    }
}

// MARK: - Empty State

struct EmptyState: View {
    let icon: String
    let title: String
    let message: String
    let actionLabel: String?
    let action: (() -> Void)?

    init(
        icon: String,
        title: String,
        message: String,
        actionLabel: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.actionLabel = actionLabel
        self.action = action
    }

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(AppColors.secondary)

            VStack(spacing: AppSpacing.xs) {
                Text(title)
                    .font(AppTypography.heading2)
                    .foregroundColor(AppColors.primary)

                Text(message)
                    .font(AppTypography.body)
                    .foregroundColor(AppColors.secondary)
                    .multilineTextAlignment(.center)
            }

            if let action, let label = actionLabel {
                Button(action: action) {
                    Text(label)
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(AppSpacing.xxl)
        .frame(maxWidth: 400)
    }
}

// MARK: - Loading Indicator

struct LoadingIndicator: View {
    let message: String?

    init(message: String? = nil) {
        self.message = message
    }

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            ProgressView()
                .controlSize(.large)

            if let message {
                Text(message)
                    .font(AppTypography.body)
                    .foregroundColor(AppColors.secondary)
            }
        }
        .padding(AppSpacing.xl)
    }
}

// MARK: - Toggle Row

struct ToggleRow: View {
    let title: String
    let subtitle: String?
    @Binding var isOn: Bool

    init(_ title: String, subtitle: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.subtitle = subtitle
        self._isOn = isOn
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(title)
                    .font(AppTypography.body)
                    .foregroundColor(AppColors.primary)

                if let subtitle {
                    Text(subtitle)
                        .font(AppTypography.bodySmall)
                        .foregroundColor(AppColors.secondary)
                }
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
        .padding(.vertical, AppSpacing.xs)
    }
}

// MARK: - Value Row (для відображення значень)

struct ValueRow: View {
    let label: String
    let value: String
    let valueColor: Color?

    init(_ label: String, value: String, valueColor: Color? = nil) {
        self.label = label
        self.value = value
        self.valueColor = valueColor
    }

    var body: some View {
        HStack {
            Text(label)
                .font(AppTypography.body)
                .foregroundColor(AppColors.secondary)

            Spacer()

            Text(value)
                .font(AppTypography.mono)
                .foregroundColor(valueColor ?? AppColors.primary)
        }
        .padding(.vertical, AppSpacing.xs)
    }
}

// MARK: - Icon Button

struct IconButton: View {
    let icon: String
    let action: () -> Void
    let color: Color?

    init(icon: String, color: Color? = nil, action: @escaping () -> Void) {
        self.icon = icon
        self.color = color
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .foregroundColor(color ?? AppColors.primary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Feature Button (для головного меню)

struct FeatureButton: View {
    let title: String
    let icon: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.md) {
                // Icon
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(AppColors.accent)
                    .frame(width: 32, height: 32)
                    .background(AppColors.accent.opacity(0.15))
                    .cornerRadius(AppRadius.sm)

                // Text
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text(title)
                        .font(AppTypography.body)
                        .foregroundColor(AppColors.primary)

                    Text(subtitle)
                        .font(AppTypography.labelSmall)
                        .foregroundColor(AppColors.secondary)
                }

                Spacer()

                // Arrow
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppColors.secondary)
            }
            .padding(AppSpacing.md)
            .background(AppSpecialEffects.vibrant.opacity(0.5))
            .cornerRadius(AppRadius.md)
        }
        .buttonStyle(.plain)
    }
}
