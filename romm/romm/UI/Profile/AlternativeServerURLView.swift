//
//  AlternativeServerURLView.swift
//  romm
//

import SwiftUI

struct AlternativeServerURLView: View {
    @State private var viewModel = AlternativeServerURLViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                TextField("", text: $viewModel.url, prompt: Text(verbatim: "https://romm.example.com"))
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit(save)
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                    Text("Used whenever \(viewModel.primaryURL) can't be reached, for example a public address while you are away from home. Leave it empty to always use the server URL.")
                }
            }
        }
        .navigationTitle("Alternative URL")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if viewModel.isSaving {
                    ProgressView()
                } else {
                    Button("Save", action: save)
                        .disabled(!viewModel.hasChanges)
                }
            }
        }
    }

    private func save() {
        guard viewModel.hasChanges, !viewModel.isSaving else { return }
        Task {
            if await viewModel.save() {
                dismiss()
            }
        }
    }
}

#Preview {
    NavigationStack {
        AlternativeServerURLView()
    }
}
