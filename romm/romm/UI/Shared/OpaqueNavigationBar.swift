//
//  OpaqueNavigationBar.swift
//  romm
//

import SwiftUI
import UIKit

extension View {
    /// Forces a fully opaque navigation bar for this screen.
    ///
    /// On iOS 26 (Liquid Glass) the default navigation bar is translucent, so content
    /// scrolling underneath shows through — which looks broken next to a pinned section
    /// header. This installs an opaque appearance while the screen is visible and restores
    /// the previous appearance on exit, so pushed screens (e.g. a parallax detail header)
    /// keep their translucent bar.
    func opaqueNavigationBar(_ color: UIColor = .systemGroupedBackground) -> some View {
        background(OpaqueNavBarConfigurator(color: color))
    }
}

private struct OpaqueNavBarConfigurator: UIViewControllerRepresentable {
    let color: UIColor

    func makeUIViewController(context: Context) -> Configurator {
        Configurator(color: color)
    }

    func updateUIViewController(_ uiViewController: Configurator, context: Context) {
        uiViewController.color = color
    }

    final class Configurator: UIViewController {
        var color: UIColor

        private var savedStandard: UINavigationBarAppearance?
        private var savedScrollEdge: UINavigationBarAppearance?
        private var savedCompact: UINavigationBarAppearance?

        init(color: UIColor) {
            self.color = color
            super.init(nibName: nil, bundle: nil)
            view.backgroundColor = .clear
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            guard let bar = navigationController?.navigationBar else { return }

            savedStandard = bar.standardAppearance
            savedScrollEdge = bar.scrollEdgeAppearance
            savedCompact = bar.compactAppearance

            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = color
            bar.standardAppearance = appearance
            bar.scrollEdgeAppearance = appearance
            bar.compactAppearance = appearance
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            guard let bar = navigationController?.navigationBar else { return }

            if let savedStandard { bar.standardAppearance = savedStandard }
            bar.scrollEdgeAppearance = savedScrollEdge
            bar.compactAppearance = savedCompact
        }
    }
}
