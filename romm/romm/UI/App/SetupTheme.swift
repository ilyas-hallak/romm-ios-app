//
//  SetupTheme.swift
//  romm
//
//  Visual theme for the RomM setup / login screen.
//  Dark, glassy purple look with a coral accent.
//

import SwiftUI

// MARK: - Color hex helper

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: alpha
        )
    }
}

// MARK: - Palette

enum SetupTheme {
    // Background
    static let bgTop = Color(hex: 0x43377c)
    static let bgMid = Color(hex: 0x382d68)
    static let bgBottom = Color(hex: 0x2f2758)
    static let blobPurple = Color(hex: 0x806cca)

    // Accents
    static let coralLight = Color(hex: 0xf9ac8d)
    static let coralDark = Color(hex: 0xee7c5e)
    static let onAccent = Color(hex: 0x3a2352)

    static let amberLight = Color(hex: 0xf6c07a)
    static let amberDark = Color(hex: 0xef9a45)
    static let amber = Color(hex: 0xf6b25a)

    static let green = Color(hex: 0x63dca7)
    static let greenText = Color(hex: 0x6fe0b0)

    static let errorBorder = Color(hex: 0xff6b6b)
    static let errorIcon = Color(hex: 0xff8f8f)
    static let errorText = Color(hex: 0xff9c9c)

    // Text
    static let label = Color(hex: 0xb6acd8)
    static let subtitle = Color(hex: 0xb6acd8)

    // Gradients
    static var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [bgTop, bgMid, bgBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var coralGradient: LinearGradient {
        LinearGradient(
            colors: [coralLight, coralDark],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var amberGradient: LinearGradient {
        LinearGradient(
            colors: [amberLight, amberDark],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Background

struct SetupBackground: View {
    var body: some View {
        ZStack {
            SetupTheme.backgroundGradient

            // Purple glow, top-left
            Circle()
                .fill(
                    RadialGradient(
                        colors: [SetupTheme.blobPurple.opacity(0.6), SetupTheme.blobPurple.opacity(0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: 230
                    )
                )
                .frame(width: 460, height: 560)
                .offset(x: -170, y: -240)

            // Coral blob, bottom-right
            Ellipse()
                .fill(SetupTheme.coralGradient)
                .frame(width: 420, height: 460)
                .opacity(0.9)
                .blur(radius: 6)
                .offset(x: 160, y: 320)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Glass field container

enum SetupFieldState {
    case normal
    case focused
    case error

    var fill: Color {
        switch self {
        case .normal, .focused: return .white.opacity(0.05)
        case .error: return SetupTheme.errorBorder.opacity(0.08)
        }
    }

    var border: Color {
        switch self {
        case .normal: return .white.opacity(0.13)
        case .focused: return SetupTheme.coralLight.opacity(0.55)
        case .error: return SetupTheme.errorBorder.opacity(0.6)
        }
    }

    var lineWidth: CGFloat {
        self == .normal ? 1 : 1.5
    }

    var glow: Color {
        switch self {
        case .normal: return .clear
        case .focused: return SetupTheme.coralLight.opacity(0.12)
        case .error: return SetupTheme.errorBorder.opacity(0.1)
        }
    }
}

extension View {
    /// Applies the glassy input-field chrome used across the setup form.
    func setupField(_ state: SetupFieldState = .normal) -> some View {
        self
            .frame(height: 50)
            .padding(.horizontal, 13)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(state.fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(state.border, lineWidth: state.lineWidth)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(state.glow, lineWidth: 3)
                    .blur(radius: 2)
                    .padding(-1)
            )
    }
}

// MARK: - Field label

struct SetupFieldLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12.5, weight: .bold))
            .foregroundStyle(SetupTheme.label)
            .kerning(0.3)
    }
}
