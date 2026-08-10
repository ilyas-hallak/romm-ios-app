//
//  View+SearchableWhen.swift
//  romm
//

import SwiftUI

extension View {
    /// Attaches a search field only when `condition` is true.
    /// Used to show a per-list search once a list grows past a small threshold.
    @ViewBuilder
    func searchableWhen(_ condition: Bool, text: Binding<String>, prompt: String) -> some View {
        if condition {
            self.searchable(text: text, prompt: Text(prompt))
        } else {
            self
        }
    }
}
