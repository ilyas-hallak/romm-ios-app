//
//  ArticleReaderView.swift
//  romm
//
//  Distraction-free reader for a ROM's summary text.
//

import SwiftUI
import UIKit

struct ArticleReaderView: View {
    let title: String
    let subtitle: String?
    let meta: [String]
    let text: String

    @Environment(\.dismiss) private var dismiss

    @AppStorage("article_reader.fontSize") private var fontSizeRaw: String = ArticleReaderFontSize.medium.rawValue
    @AppStorage("article_reader.family") private var familyRaw: String = ArticleReaderFontFamily.serif.rawValue
    @AppStorage("article_reader.theme") private var themeRaw: String = ArticleReaderTheme.system.rawValue

    @State private var showingSettings = false
    @State private var showingShare = false

    private var fontSize: ArticleReaderFontSize {
        ArticleReaderFontSize(rawValue: fontSizeRaw) ?? .medium
    }

    private var family: ArticleReaderFontFamily {
        ArticleReaderFontFamily(rawValue: familyRaw) ?? .serif
    }

    private var theme: ArticleReaderTheme {
        ArticleReaderTheme(rawValue: themeRaw) ?? .system
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    Divider()
                        .padding(.vertical, 4)
                    articleBody
                    Spacer(minLength: 60)
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 40)
                .frame(maxWidth: 680, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .background(theme.backgroundColor.ignoresSafeArea())
            .foregroundColor(theme.textColor)
            .preferredColorScheme(theme.preferredColorScheme)
            .navigationTitle("Reader")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        Button {
                            showingSettings = true
                        } label: {
                            Image(systemName: "textformat.size")
                        }
                        .accessibilityLabel("Reader settings")

                        Button {
                            showingShare = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("Share article")
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                ArticleReaderSettingsSheet(
                    fontSizeRaw: $fontSizeRaw,
                    familyRaw: $familyRaw,
                    themeRaw: $themeRaw
                )
                .presentationDetents([.height(320), .medium])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showingShare) {
                ArticleShareSheet(text: shareText)
            }
        }
    }

    private var shareText: String {
        var parts: [String] = [title]
        if let subtitle, !subtitle.isEmpty {
            parts.append(subtitle)
        }
        parts.append("")
        parts.append(text)
        return parts.joined(separator: "\n")
    }

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !meta.isEmpty {
                Text(meta.joined(separator: " · ").uppercased())
                    .font(.caption)
                    .tracking(1.2)
                    .foregroundColor(theme.secondaryTextColor)
            }

            Text(title)
                .font(family.titleFont(scale: fontSize.scale))
                .fontWeight(.bold)
                .fixedSize(horizontal: false, vertical: true)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(family.subtitleFont(scale: fontSize.scale))
                    .foregroundColor(theme.secondaryTextColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private var articleBody: some View {
        let paragraphs = text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)

        VStack(alignment: .leading, spacing: 18) {
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                Text(paragraph)
                    .font(family.bodyFont(scale: fontSize.scale))
                    .lineSpacing(fontSize.lineSpacing)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Preferences

enum ArticleReaderFontSize: String, CaseIterable, Identifiable {
    case small, medium, large, xlarge

    var id: String { rawValue }

    var label: String {
        switch self {
        case .small: return "S"
        case .medium: return "M"
        case .large: return "L"
        case .xlarge: return "XL"
        }
    }

    var scale: CGFloat {
        switch self {
        case .small: return 0.9
        case .medium: return 1.0
        case .large: return 1.15
        case .xlarge: return 1.3
        }
    }

    var lineSpacing: CGFloat {
        switch self {
        case .small: return 5
        case .medium: return 6
        case .large: return 7
        case .xlarge: return 8
        }
    }
}

enum ArticleReaderFontFamily: String, CaseIterable, Identifiable {
    case serif, sansSerif

    var id: String { rawValue }

    var label: String {
        switch self {
        case .serif: return "Serif"
        case .sansSerif: return "Sans"
        }
    }

    private var systemDesign: Font.Design {
        switch self {
        case .serif: return .serif
        case .sansSerif: return .default
        }
    }

    func titleFont(scale: CGFloat) -> Font {
        .system(size: 30 * scale, weight: .bold, design: systemDesign)
    }

    func subtitleFont(scale: CGFloat) -> Font {
        .system(size: 18 * scale, weight: .regular, design: systemDesign)
    }

    func bodyFont(scale: CGFloat) -> Font {
        .system(size: 18 * scale, weight: .regular, design: systemDesign)
    }
}

enum ArticleReaderTheme: String, CaseIterable, Identifiable {
    case system, light, sepia, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "Auto"
        case .light: return "Light"
        case .sepia: return "Sepia"
        case .dark: return "Dark"
        }
    }

    var backgroundColor: Color {
        switch self {
        case .system: return Color(.systemBackground)
        case .light: return Color(red: 1.0, green: 1.0, blue: 1.0)
        case .sepia: return Color(red: 0.98, green: 0.94, blue: 0.86)
        case .dark: return Color(red: 0.09, green: 0.09, blue: 0.11)
        }
    }

    var textColor: Color {
        switch self {
        case .system: return Color(.label)
        case .light: return Color(red: 0.12, green: 0.12, blue: 0.14)
        case .sepia: return Color(red: 0.28, green: 0.22, blue: 0.14)
        case .dark: return Color(red: 0.92, green: 0.92, blue: 0.94)
        }
    }

    var secondaryTextColor: Color {
        switch self {
        case .system: return Color(.secondaryLabel)
        case .light: return Color(red: 0.42, green: 0.42, blue: 0.45)
        case .sepia: return Color(red: 0.52, green: 0.42, blue: 0.28)
        case .dark: return Color(red: 0.68, green: 0.68, blue: 0.72)
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light, .sepia: return .light
        case .dark: return .dark
        }
    }
}

// MARK: - Share

private struct ArticleShareSheet: UIViewControllerRepresentable {
    let text: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        if let popover = controller.popoverPresentationController {
            popover.sourceView = UIView()
            popover.permittedArrowDirections = .any
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Settings Sheet

private struct ArticleReaderSettingsSheet: View {
    @Binding var fontSizeRaw: String
    @Binding var familyRaw: String
    @Binding var themeRaw: String

    var body: some View {
        NavigationStack {
            Form {
                Section("Text Size") {
                    Picker("Text Size", selection: $fontSizeRaw) {
                        ForEach(ArticleReaderFontSize.allCases) { size in
                            Text(size.label).tag(size.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Font") {
                    Picker("Font", selection: $familyRaw) {
                        ForEach(ArticleReaderFontFamily.allCases) { family in
                            Text(family.label).tag(family.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Theme") {
                    Picker("Theme", selection: $themeRaw) {
                        ForEach(ArticleReaderTheme.allCases) { theme in
                            Text(theme.label).tag(theme.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("Reader Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    ArticleReaderView(
        title: "The Legend of Zelda: A Link to the Past",
        subtitle: "Nintendo · 1991",
        meta: ["Super Nintendo", "Action-Adventure"],
        text: """
        Long ago, in the Kingdom of Hyrule, a land of green fields, thick forests and rugged mountains, there was a legend about a Golden Power.

        Now, the young hero Link must venture forth to save the princess Zelda and defeat the evil sorcerer Agahnim before he can complete his plan to release Ganon from the Dark World.

        Explore two overlapping realms, uncover ancient dungeons, and forge the Master Sword — the only blade capable of turning back the tide of evil.
        """
    )
}
