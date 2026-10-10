//
//  RomUploadSheet.swift
//  romm
//
//  Presented when a ROM file is opened into the app ("Open In" from Files,
//  a share sheet target). Lets the user pick which platform it belongs to,
//  then hands it to `RomUploadQueueManager` and gets out of the way: the
//  actual transfer and its progress live on the Sync screen.
//

import SwiftUI

struct RomUploadSheet: View {
    @State private var viewModel: RomUploadSheetViewModel
    @Environment(\.dismiss) private var dismiss

    init(viewModel: RomUploadSheetViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("File", value: viewModel.file.fileName)
                    LabeledContent("Size", value: ByteCountFormatter.string(fromByteCount: viewModel.file.fileSize, countStyle: .file))
                }

                if viewModel.isLoading {
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Checking this server…")
                                .foregroundStyle(.secondary)
                        }
                    }
                } else if let message = viewModel.unavailableMessage {
                    Section {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(message)
                        }
                        if viewModel.canSignInAgain {
                            Button("Sign In Again") {
                                viewModel.signInAgain()
                                dismiss()
                            }
                        }
                    }
                } else {
                    Section {
                        Picker("Platform", selection: $viewModel.selectedPlatformId) {
                            Text("Select a platform").tag(nil as Int?)
                            ForEach(viewModel.platforms) { platform in
                                Text(platform.name).tag(platform.id as Int?)
                            }
                        }
                    } footer: {
                        Text("The server scans for this file after the upload finishes and adds it to your library.")
                    }
                }
            }
            .navigationTitle("Upload ROM")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Upload") {
                        viewModel.upload()
                        dismiss()
                    }
                    .disabled(!viewModel.canUpload)
                }
            }
            .task { await viewModel.load() }
            .onDisappear { viewModel.discardIfNotUploaded() }
        }
    }
}
