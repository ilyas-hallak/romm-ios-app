//
//  DownloadFlightOverlay.swift
//  romm
//
//  Cosmetic feedback for "download queued": a ROM cover thumbnail flies in a
//  downward arc from the Download button toward the Downloads tab, shrinking and
//  fading as it arrives so it dissolves into the tab icon. One-shot, then the
//  overlay removes itself. Purely visual, non-interactive.
//

import SwiftUI
import UIKit

struct DownloadFlightOverlay: View {
    let flight: DownloadFlight
    let onFinished: () -> Void

    private let duration: TimeInterval = 0.6

    /// Drives the whole flight (0 → 1). Animated once on appear; it holds at 1
    /// (fully transparent) afterwards — no reset, so nothing re-appears.
    @State private var t: CGFloat = 0
    /// Removes the cover from the tree the instant the animation lands, so a
    /// late image decode or re-render can never flash it back in.
    @State private var finished = false

    var body: some View {
        GeometryReader { geo in
            let start = CGPoint(x: flight.start.midX, y: flight.start.midY)
            let end = landingPoint(screen: geo.size)

            if !finished {
                CachedKFImage(urlString: flight.coverURL) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.accentColor)
                        .overlay(
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundStyle(.white)
                        )
                }
                .frame(width: 64, height: 86)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(.white.opacity(0.25), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
                .modifier(FlightEffect(t: t, start: start, end: end))
                .onAppear {
                    withAnimation(.easeInOut(duration: duration)) {
                        t = 1
                    } completion: {
                        finished = true
                        onFinished()
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }

    /// Where the cover should land. Vertical position comes from the live
    /// tab-bar frame when available (accurate for both states); horizontal
    /// position follows the snapshotted tab-bar state: minimized → the collapsed
    /// pill in the leading corner, expanded → the Downloads icon (right of center).
    private func landingPoint(screen: CGSize) -> CGPoint {
        let y = tabBarFrame?.midY ?? (screen.height - bottomSafeInset - 22)
        let leadingInset = keyWindow?.safeAreaInsets.left ?? 0
        let x = flight.tabBarMinimized
            ? leadingInset + 46          // collapsed pill sits in the leading corner
            : screen.width * 0.62        // Downloads icon slot in the expanded bar
        return CGPoint(x: x, y: y)
    }

    /// The active window's tab bar frame in window (global) coordinates, if any.
    private var tabBarFrame: CGRect? {
        guard let window = keyWindow,
              let bar = Self.findTabBar(in: window) else { return nil }
        return (bar.superview ?? window).convert(bar.frame, to: window)
    }

    private static func findTabBar(in view: UIView) -> UITabBar? {
        if let bar = view as? UITabBar { return bar }
        for sub in view.subviews {
            if let found = findTabBar(in: sub) { return found }
        }
        return nil
    }

    private var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }

    /// Bottom safe-area inset of the active window (fallback tab-bar band).
    private var bottomSafeInset: CGFloat {
        keyWindow?.safeAreaInsets.bottom ?? 0
    }
}

/// Animatable modifier so position (along a bezier arc), scale, and opacity are
/// all resampled every frame from a single progress value `t`.
private struct FlightEffect: ViewModifier, Animatable {
    var t: CGFloat
    let start: CGPoint
    let end: CGPoint

    var animatableData: CGFloat {
        get { t }
        set { t = newValue }
    }

    func body(content: Content) -> some View {
        content
            .scaleEffect(1.0 - 0.85 * t)
            .opacity(opacity)
            .position(position)
    }

    /// Quadratic bezier with a control point lifted above the travel line so the
    /// cover arcs up before dropping toward the tab bar.
    private var position: CGPoint {
        let control = CGPoint(x: (start.x + end.x) / 2, y: min(start.y, end.y) - 140)
        let mt = 1 - t
        return CGPoint(
            x: mt * mt * start.x + 2 * mt * t * control.x + t * t * end.x,
            y: mt * mt * start.y + 2 * mt * t * control.y + t * t * end.y
        )
    }

    /// Opaque during the flight, easing to fully transparent as it arrives.
    private var opacity: Double {
        t <= 0.55 ? 1 : Double(max(0, 1 - (t - 0.55) / 0.45))
    }
}
