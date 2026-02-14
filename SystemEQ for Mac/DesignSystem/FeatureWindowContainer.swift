//
//  FeatureWindowContainer.swift
//  SystemEQ for Mac
//
//  Уніфікований контейнер для всіх feature-вікон
//  Забезпечує консистентний дизайн, структуру та поведінку
//

import SwiftUI

// MARK: - Window Size Configuration

struct WindowSize {
    let minWidth: CGFloat
    let minHeight: CGFloat
    let maxWidth: CGFloat
    let maxHeight: CGFloat

    // Стандартні розміри для різних типів вікон
    static let standard = WindowSize(minWidth: 800, minHeight: 600, maxWidth: 1200, maxHeight: 1000)
    static let large = WindowSize(minWidth: 900, minHeight: 700, maxWidth: 1400, maxHeight: 1000)
    static let compact = WindowSize(minWidth: 700, minHeight: 600, maxWidth: 900, maxHeight: 900)
    static let wide = WindowSize(minWidth: 900, minHeight: 600, maxWidth: 1600, maxHeight: 1200)
    static let equalizer = WindowSize(minWidth: 600, minHeight: 450, maxWidth: 1200, maxHeight: 800)
}

// MARK: - Tab Item Protocol

protocol FeatureTab: Hashable, CaseIterable, Identifiable {
    func localizedTitle(_ localization: LocalizationManager) -> String
}

// MARK: - Feature Window Container

struct FeatureWindowContainer<Content: View, Tab: FeatureTab>: View {
    // Configuration
    let title: LocalizedString
    let subtitle: LocalizedString?
    let windowSize: WindowSize
    let hasScrollView: Bool
    let showDividerAfterHeader: Bool

    // Tab navigation (optional)
    @Binding var selectedTab: Tab?
    let showTabSelector: Bool

    /// Content
    let content: (Tab?) -> Content

    /// Localization
    @ObservedObject private var localization = LocalizationManager.shared

    /// State for forcing initial layout
    @State private var isReady = false

    // MARK: - Initializers

    /// Ініціалізатор для вікон БЕЗ табів
    init(
        title: LocalizedString,
        subtitle: LocalizedString? = nil,
        windowSize: WindowSize = .standard,
        hasScrollView: Bool = true,
        showDividerAfterHeader: Bool = true,
        @ViewBuilder content: @escaping () -> Content
    ) where Tab == NeverTab {
        self.title = title
        self.subtitle = subtitle
        self.windowSize = windowSize
        self.hasScrollView = hasScrollView
        self.showDividerAfterHeader = showDividerAfterHeader
        self._selectedTab = .constant(nil)
        self.showTabSelector = false
        self.content = { _ in content() }
    }

    /// Ініціалізатор для вікон З табами
    init(
        title: LocalizedString,
        subtitle: LocalizedString? = nil,
        windowSize: WindowSize = .standard,
        hasScrollView: Bool = true,
        showDividerAfterHeader: Bool = true,
        selectedTab: Binding<Tab>,
        @ViewBuilder content: @escaping (Tab) -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.windowSize = windowSize
        self.hasScrollView = hasScrollView
        self.showDividerAfterHeader = showDividerAfterHeader
        self._selectedTab = Binding(
            get: { Optional(selectedTab.wrappedValue) },
            set: { if let newValue = $0 { selectedTab.wrappedValue = newValue } }
        )
        self.showTabSelector = true
        self.content = { tab in
            if let tab {
                content(tab)
            } else {
                content(Tab.allCases.first ?? Tab.allCases[Tab.allCases.startIndex])
            }
        }
    }

    var body: some View {
        ZStack {
            // Background layer - always visible immediately (no opacity animation)
            ZStack {
                // Main glass background (original style with transparency)
                GlassCard(padding: 0, topCornersOnly: true) {
                    Color.clear
                }

                // Dark title bar area only (top ~28px where traffic lights are)
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(Color(NSColor.windowBackgroundColor).opacity(0.9))
                        .frame(height: 28)
                    Spacer()
                }
            }
            .ignoresSafeArea(.all)

            // Content layer - fades in after layout is ready
            VStack(spacing: 0) {
                // MARK: - Header Section

                headerSection

                if showDividerAfterHeader {
                    Divider()
                }

                // MARK: - Tab Selector (якщо є)

                if showTabSelector, let tab = selectedTab {
                    tabSelectorSection(currentTab: tab)
                    Divider()
                }

                // MARK: - Content Section

                if hasScrollView {
                    ScrollView {
                        contentSection
                    }
                } else {
                    contentSection
                }
            }
            .opacity(isReady ? 1 : 0)
        }
        .frame(
            minWidth: windowSize.minWidth,
            minHeight: windowSize.minHeight
        )
        .frame(
            maxWidth: windowSize.maxWidth,
            maxHeight: windowSize.maxHeight
        )
        .onAppear {
            // Force layout calculation before showing content to prevent visual glitch
            // Small delay allows window to fully initialize its geometry
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                withAnimation(.easeIn(duration: 0.1)) {
                    isReady = true
                }
            }
        }
        .blurOnLanguageChange()
    }

    // MARK: - Header Section

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(localization.localized(title))
                    .font(AppTypography.heading1)

                if let subtitle {
                    Text(localization.localized(subtitle))
                        .font(AppTypography.bodySmall)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding(.top, showTabSelector ? 28 : 52)
        .padding(.horizontal, AppSpacing.lg)
        .padding(.bottom, AppSpacing.md)
    }

    // MARK: - Tab Selector Section

    private func tabSelectorSection(currentTab: Tab) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(Tab.allCases), id: \.self) { tab in
                Button(action: {
                    selectedTab = tab
                }) {
                    Text(tab.localizedTitle(localization))
                        .font(.system(size: 13, weight: currentTab == tab ? .semibold : .regular))
                        .foregroundColor(currentTab == tab ? .primary : .secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            currentTab == tab ?
                                Color.blue.opacity(0.1) : Color.clear
                        )
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Content Section

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            content(selectedTab)
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.top, showTabSelector ? AppSpacing.lg : AppSpacing.xxl)
        .padding(.bottom, AppSpacing.xxxl + AppSpacing.lg) // Extra padding for bottom content visibility
    }
}

// MARK: - Never Tab (для вікон без табів)

enum NeverTab: FeatureTab {
    func localizedTitle(_ localization: LocalizationManager) -> String {
        ""
    }

    var id: String {
        ""
    }

    static var allCases: [NeverTab] {
        []
    }
}

// MARK: - Preview Helper

#if DEBUG
    struct FeatureWindowContainer_Previews: PreviewProvider {
        static var previews: some View {
            // Вікно без табів
            FeatureWindowContainer(
                title: .settingsTitle,
                subtitle: .settingsHeaderSubtitle,
                windowSize: .standard
            ) {
                VStack {
                    Text("Content without tabs")
                        .font(AppTypography.body)
                }
            }
            .previewDisplayName("Without Tabs")

            // Вікно з табами
            FeatureWindowContainer(
                title: .calibrationTitle,
                subtitle: .calibrationSubtitle,
                windowSize: .large,
                selectedTab: .constant(PreviewTab.first)
            ) { tab in
                VStack {
                    Text("Content for \(tab.rawValue)")
                        .font(AppTypography.body)
                }
            }
            .previewDisplayName("With Tabs")
        }

        enum PreviewTab: String, FeatureTab {
            case first = "First"
            case second = "Second"

            var id: String {
                rawValue
            }

            func localizedTitle(_ localization: LocalizationManager) -> String {
                rawValue
            }
        }
    }
#endif
