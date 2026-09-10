import SwiftUI

struct RetroAchievementsCredentialsView: View {
    @State private var viewModel = RetroAchievementsCredentialsViewModel()

    var body: some View {
        @Bindable var viewModel = viewModel

        Form {
            Section {
                TextField("Username", text: $viewModel.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("API key", text: $viewModel.apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("RetroAchievements Credentials")
            } footer: {
                Text("Generate an API key in your RetroAchievements account settings. It is stored only in this device's Keychain.")
            }

            if let errorMessage = viewModel.errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button("Save credentials") {
                    viewModel.save()
                }
                .disabled(viewModel.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if viewModel.isConfigured {
                    Button("Remove credentials", role: .destructive) {
                        viewModel.clear()
                    }
                }
            }
        }
        .navigationTitle("RetroAchievements")
    }
}
