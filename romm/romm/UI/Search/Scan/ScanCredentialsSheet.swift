//
//  ScanCredentialsSheet.swift
//  romm
//
//  Created by Ilyas Hallak on 12.09.26.
//

import SwiftUI

/// Asked for once when the app signed in with a token or in the browser: the
/// server only lets a scan start from a real session, and a session needs a
/// username and password.
struct ScanCredentialsSheet: View {
    @Bindable var viewModel: LibraryScanViewModel

    @State private var username = ""
    @State private var password = ""
    @FocusState private var focusedField: Field?

    private enum Field {
        case username
        case password
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Username", text: $username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .username)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .password }

                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .focused($focusedField, equals: .password)
                        .submitLabel(.go)
                        .onSubmit(submit)
                } header: {
                    Text("RomM account")
                } footer: {
                    Text("Starting a scan needs a server session, which the server only hands out for a username and password. They are stored in the keychain and used for nothing else.")
                }

                if let notice = viewModel.credentialsNotice {
                    Section {
                        Label(notice, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundColor(.orange)
                    }
                }
            }
            .navigationTitle("Sign In to Scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.dismissCredentialsPrompt()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start Scan", action: submit)
                        .fontWeight(.semibold)
                        .disabled(!canSubmit)
                }
            }
            .onAppear {
                focusedField = .username
            }
        }
    }

    private var canSubmit: Bool {
        !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
    }

    private func submit() {
        guard canSubmit else { return }
        viewModel.submitCredentials(username: username, password: password)
        password = ""
    }
}
