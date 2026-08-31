//
//  SetupView.swift
//  romm
//
//  Created by Ilyas Hallak on 07.08.25.
//

import SwiftUI

// MARK: - Focus State

enum SetupField: Hashable {
    case url, username, password, token
}

struct SetupView: View {
    let appViewModel: AppViewModel
    @State private var viewModel: SetupViewModel

    // Focus
    @FocusState private var focusedField: SetupField?

    /// Question the help opens on, set by whichever error offered it.
    @State private var helpTopic: HelpTopic?

    private var connectionLogger: ConnectionLogger { ConnectionLogger.shared }

    init(appViewModel: AppViewModel) {
        self.appViewModel = appViewModel
        let vm = SetupViewModel()
        // Wire the view model's outputs to the app root — the VM itself stays
        // decoupled from AppViewModel.
        vm.onAuthenticated = { await appViewModel.checkInitialState() }
        vm.onAcknowledgeVersion = { appViewModel.acknowledgeServerVersion($0) }
        self._viewModel = State(wrappedValue: vm)
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            SetupBackground()

            ScrollView {
                VStack(spacing: 0) {
                    // Small "Setup" label at top
                    Text("Setup")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white.opacity(0.72))
                        .kerning(0.8)
                        .padding(.top, 56)
                        .padding(.bottom, 28)

                    // Header: logo + title + subtitle
                    VStack(spacing: 14) {
                        Image("romm_logo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 86, height: 86)

                        Text("RomM")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(.white)

                        Text("ROM Management System")
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(SetupTheme.subtitle)
                    }
                    .padding(.bottom, 32)

                    // Glass card
                    glassCard
                        .padding(.horizontal, 40)

                    // Footer
                    VStack(spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.shield")
                                .font(.caption)
                            Text("Your credentials will be stored securely")
                                .font(.caption)
                        }
                        Text("Password will not be stored locally")
                            .font(.caption)
                    }
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .padding(.top, 20)
                    .padding(.horizontal, 24)

                    // Connection Debug Panel (TestFlight & Debug only)
                    if (Bundle.main.isTestFlightBuild || Bundle.main.isDebugBuild),
                       !connectionLogger.logs.isEmpty || connectionLogger.isConnecting {
                        ConnectionDebugPanel(
                            logs: connectionLogger.logs,
                            isExpanded: $viewModel.showConnectionDetails
                        )
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                    }

                    Spacer().frame(height: 40)
                }
                .frame(maxWidth: 460)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .preferredColorScheme(.dark)
        .tint(SetupTheme.coralLight)
        .onAppear {
            viewModel.seedUITestLoginStateIfNeeded()
            viewModel.preloadLastServerURL()
        }
        .onDisappear {
            viewModel.deviceFlowTask?.cancel()
        }
        .onTapGesture {
            viewModel.hideKeyboard()
        }
        .onChange(of: focusedField) { _, newValue in
            // Auto-validate when URL field loses focus
            if newValue != .url && !viewModel.serverURL.isEmpty && !viewModel.serverValidated && !viewModel.isConnecting {
                Task { await viewModel.validateServer() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .clientTokenPairingCode)) { notification in
            if let code = notification.userInfo?["code"] as? String {
                Task {
                    await viewModel.performClientTokenPairing(code: code)
                }
            }
        }
        .sheet(isPresented: $viewModel.showQRScanner) {
            QRScannerView { code in
                viewModel.showQRScanner = false
                Task {
                    await viewModel.performClientTokenPairing(code: code)
                }
            }
        }
        .sheet(item: $helpTopic) { topic in
            HelpView(highlightedQuestion: topic.question)
        }
    }

    // MARK: - Glass Card

    private var glassCard: some View {
        VStack(spacing: 16) {
            // Server URL field
            urlFieldSection

            // Version warning banner
            if viewModel.isVersionWarning, let title = viewModel.versionWarningTitle {
                versionWarningBanner(title: title, details: viewModel.versionWarningDetails)
            }

            // Sign-in options only appear once the server has been checked and is
            // reachable — no point offering a login before we know it works.
            if viewModel.serverValidated {
                // Primary: browser device-flow sign-in
                if viewModel.showDeviceFlowPrimary {
                    deviceFlowSection
                }

                // Fallback methods (username/password, API token)
                otherOptionsSection
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(SetupTheme.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.45), radius: 24, x: 0, y: 8)
    }

    // MARK: - URL Field Section

    private var urlFieldSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SetupFieldLabel(text: "Server URL")

            // Field row
            let urlState: SetupFieldState = viewModel.connectionError != nil ? .error : (focusedField == .url ? .focused : .normal)

            HStack(spacing: 10) {
                Image(systemName: "link")
                    .font(.system(size: 15))
                    .foregroundStyle(viewModel.serverValidated ? .white.opacity(0.55) : .white.opacity(0.4))
                    .frame(width: 20)

                TextField("", text: $viewModel.serverURL, prompt: Text(verbatim: "https://romm.example.com")
                    .foregroundColor(.white.opacity(0.3)))
                    .font(.system(size: 14.5))
                    .foregroundStyle(.white)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .focused($focusedField, equals: .url)
                    .onSubmit {
                        Task {
                            await viewModel.validateServer()
                            focusedField = .username
                        }
                    }
                    .onChange(of: viewModel.serverURL) { _, _ in
                        if viewModel.serverValidated || viewModel.isVersionWarning || viewModel.connectionError != nil {
                            viewModel.resetServerValidation()
                        }
                    }

                // Version badge (shown when validated or version warning)
                if (viewModel.serverValidated || viewModel.isVersionWarning), let version = viewModel.detectedServerVersion {
                    versionBadge(version: version)
                }

                // Spinner while connecting
                if viewModel.isConnecting {
                    ProgressView()
                        .scaleEffect(0.75)
                        .tint(.white.opacity(0.6))
                }
            }
            .setupField(urlState)

            // Quick input chips — only when not validated and no error/warning
            if !viewModel.serverValidated && viewModel.connectionError == nil && !viewModel.isVersionWarning {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        QuickInputChip(text: "192.168.", action: { viewModel.insertText("192.168.") })
                        QuickInputChip(text: "http://", action: { viewModel.insertText("http://") })
                        QuickInputChip(text: "https://", action: { viewModel.insertText("https://") })
                        QuickInputChip(text: ":8080", action: { viewModel.insertText(":8080") })
                        QuickInputChip(text: ".com", action: { viewModel.insertText(".com") })
                        QuickInputChip(text: ".de", action: { viewModel.insertText(".de") })
                    }
                    .padding(.vertical, 2)
                }
            }

            // Connection error banner (hard error only — not version warning)
            if viewModel.connectionError != nil && !viewModel.isVersionWarning {
                connectionErrorBanner
            }
        }
    }

    // MARK: - Version Badge

    private func versionBadge(version: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: viewModel.isVersionWarning ? "exclamationmark.triangle.fill" : "checkmark")
                .font(.system(size: 9, weight: .bold))
            Text("v\(version)")
                .font(.system(size: 10.5, weight: .semibold))
        }
        .foregroundStyle(viewModel.isVersionWarning ? SetupTheme.amber : SetupTheme.greenText)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(viewModel.isVersionWarning ? SetupTheme.amber.opacity(0.15) : SetupTheme.green.opacity(0.15))
        )
        .overlay(
            Capsule()
                .strokeBorder(viewModel.isVersionWarning ? SetupTheme.amber.opacity(0.4) : SetupTheme.green.opacity(0.4), lineWidth: 1)
        )
    }

    // MARK: - Connection Error Banner

    private var connectionErrorBanner: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.isErrorExpanded.toggle()
                }
            } label: {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(SetupTheme.errorIcon)
                        .font(.system(size: 13))

                    Text(viewModel.connectionError ?? "")
                        .font(.system(size: 12.5))
                        .foregroundStyle(SetupTheme.errorText)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)

                    Spacer()

                    if viewModel.connectionErrorDetails != nil {
                        Image(systemName: viewModel.isErrorExpanded ? "chevron.up" : "chevron.down")
                            .foregroundStyle(.white.opacity(0.4))
                            .font(.caption)
                    }
                }
            }
            .buttonStyle(.plain)

            if viewModel.isErrorExpanded, let details = viewModel.connectionErrorDetails {
                Text(details)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.leading, 21)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // The error most users actually hit: the server cannot be reached,
            // typically a missing scheme or a local address iOS has not been
            // allowed to talk to yet.
            helpLink(for: Self.reachServerHelpQuestion)
                .padding(.leading, 21)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(SetupTheme.errorBorder.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(SetupTheme.errorBorder.opacity(0.4), lineWidth: 1)
        )
    }

    // MARK: - Version Warning Banner

    private func versionWarningBanner(title: String, details: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(SetupTheme.amber)
                    .font(.system(size: 13))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
            }
            if let details {
                Text(details)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.75))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(SetupTheme.amber.opacity(0.18))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(SetupTheme.amber.opacity(0.45), lineWidth: 1)
        )
    }

    // MARK: - Auth Method Picker

    private var authMethodPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            SetupFieldLabel(text: "Authentication Method")

            Picker("Auth Method", selection: $viewModel.selectedAuthMethod) {
                ForEach(viewModel.otherMethods, id: \.self) { method in
                    Label(method.displayName, systemImage: method.iconName)
                        .tag(method)
                }
            }
            .pickerStyle(.segmented)

            Text(viewModel.selectedAuthMethod.description)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    // MARK: - Classic Auth Fields

    private var classicAuthFields: some View {
        VStack(spacing: 16) {
            // Username
            VStack(alignment: .leading, spacing: 8) {
                SetupFieldLabel(text: "Username")

                HStack(spacing: 10) {
                    Image(systemName: "person")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.4))
                        .frame(width: 20)

                    TextField("", text: $viewModel.username, prompt: Text("Username")
                        .foregroundColor(.white.opacity(0.3)))
                        .font(.system(size: 14.5))
                        .foregroundStyle(.white)
                        .textContentType(.username)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .focused($focusedField, equals: .username)
                        .onSubmit { focusedField = .password }
                }
                .setupField(focusedField == .username ? .focused : .normal)
            }

            // Password
            VStack(alignment: .leading, spacing: 8) {
                SetupFieldLabel(text: "Password")

                let pwState: SetupFieldState = viewModel.hasLoginError ? .error : (focusedField == .password ? .focused : .normal)

                HStack(spacing: 10) {
                    Image(systemName: "lock")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.4))
                        .frame(width: 20)

                    Group {
                        if viewModel.showPassword {
                            TextField("", text: $viewModel.password, prompt: Text("Password")
                                .foregroundColor(.white.opacity(0.3)))
                        } else {
                            SecureField("", text: $viewModel.password, prompt: Text("Password")
                                .foregroundColor(.white.opacity(0.3)))
                        }
                    }
                    .font(.system(size: 14.5))
                    .foregroundStyle(.white)
                    .textContentType(.password)
                    .focused($focusedField, equals: .password)
                    .onSubmit {
                        Task { await viewModel.handlePrimaryAction() }
                    }

                    Button {
                        viewModel.showPassword.toggle()
                    } label: {
                        Image(systemName: viewModel.showPassword ? "eye.slash" : "eye")
                            .font(.system(size: 15))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                }
                .setupField(pwState)

                // Login error hint
                if let errorMessage = viewModel.loginError {
                    setupErrorHint(errorMessage)
                    // Signing in is where users get stuck by far the most, and
                    // they cannot reach Settings from here, so the answer has to
                    // come to them.
                    helpLink(for: Self.signInHelpQuestion)
                }
            }
        }
    }

    // MARK: - Client Token Auth Section

    private var clientTokenAuthSection: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "key.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(SetupTheme.amber)
                VStack(alignment: .leading, spacing: 4) {
                    Text("API Token")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Connect using a token from your RomM server settings")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
            )

            Button {
                viewModel.showQRScanner = true
            } label: {
                HStack {
                    Image(systemName: "qrcode.viewfinder")
                    Text("Scan QR Code")
                }
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white.opacity(0.07))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            HStack {
                Rectangle().frame(height: 1).foregroundStyle(.white.opacity(0.12))
                Text("or").font(.caption).foregroundStyle(.white.opacity(0.4))
                Rectangle().frame(height: 1).foregroundStyle(.white.opacity(0.12))
            }

            VStack(alignment: .leading, spacing: 8) {
                SetupFieldLabel(text: "Paste Token")

                HStack(spacing: 10) {
                    Image(systemName: "key")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.4))
                        .frame(width: 20)

                    TextField("", text: $viewModel.clientTokenInput, prompt: Text("rmm_...")
                        .foregroundColor(.white.opacity(0.3)))
                        .font(.system(size: 13.5, design: .monospaced))
                        .foregroundStyle(.white)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .focused($focusedField, equals: .token)
                }
                .setupField(focusedField == .token ? .focused : .normal)
            }

            if let error = viewModel.clientTokenError {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(SetupTheme.errorIcon)
                    Text(error)
                        .font(.system(size: 12.5))
                        .foregroundStyle(SetupTheme.errorText)
                        .multilineTextAlignment(.leading)
                }
            }
        }
    }

    // MARK: - Device Flow (Browser) Section

    @ViewBuilder
    private var deviceFlowSection: some View {
        VStack(spacing: 12) {
            if let info = viewModel.deviceFlowInit, viewModel.isDeviceFlowRunning {
                deviceFlowWaitingView(info: info)
            } else {
                Button {
                    Task { await viewModel.startDeviceFlow() }
                } label: {
                    HStack(spacing: 8) {
                        if viewModel.isDeviceFlowRunning {
                            ProgressView()
                                .tint(SetupTheme.onAccent)
                                .frame(width: 18, height: 18)
                        } else {
                            Image(systemName: "safari")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        Text("Sign in with Browser")
                            .font(.system(size: 16, weight: .bold))
                    }
                    .foregroundStyle(viewModel.deviceFlowButtonEnabled ? SetupTheme.onAccent : .white.opacity(0.4))
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(deviceFlowButtonBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: viewModel.deviceFlowButtonEnabled ? SetupTheme.coralLight.opacity(0.4) : .clear, radius: 10, x: 0, y: 4)
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.deviceFlowButtonEnabled)

                Text("Approve this device in your browser — no password needed.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }

            if let deviceFlowError = viewModel.deviceFlowError {
                setupErrorHint(deviceFlowError)
                helpLink(for: Self.reachServerHelpQuestion)
            }
        }
    }

    @ViewBuilder
    private var deviceFlowButtonBackground: some View {
        if viewModel.deviceFlowButtonEnabled {
            SetupTheme.coralGradient
        } else {
            Color.white.opacity(0.06)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                )
        }
    }

    private func deviceFlowWaitingView(info: DeviceAuthInitResponse) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                ProgressView().tint(SetupTheme.coralLight)
                Text("Waiting for approval…")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }

            Text("Approve this device in the browser. If it didn't open, reopen it below.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)

            HStack(spacing: 8) {
                Text("Code")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                Text(info.userCode)
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .kerning(2)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.white.opacity(0.06)))

            HStack(spacing: 10) {
                Button {
                    viewModel.openApprovalBrowser(info: info)
                } label: {
                    Label("Reopen Browser", systemImage: "safari")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.07)))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
                }
                .buttonStyle(.plain)

                Button {
                    viewModel.cancelDeviceFlow()
                } label: {
                    Text("Cancel")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(SetupTheme.errorText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04)))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(SetupTheme.errorBorder.opacity(0.35), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
    }

    // MARK: - Other Sign-In Options

    @ViewBuilder
    private var otherOptionsSection: some View {
        if viewModel.showDeviceFlowPrimary {
            if !viewModel.otherMethods.isEmpty {
                VStack(spacing: 14) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { viewModel.showOtherOptions.toggle() }
                    } label: {
                        HStack {
                            Text("Other sign-in options")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.7))
                            Spacer()
                            Image(systemName: viewModel.showOtherOptions ? "chevron.up" : "chevron.down")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.4))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if viewModel.showOtherOptions {
                        otherMethodsContent
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
        } else {
            // Server has no browser flow — show the fallback methods directly.
            otherMethodsContent
        }
    }

    @ViewBuilder
    private var otherMethodsContent: some View {
        VStack(spacing: 16) {
            if viewModel.otherMethods.count > 1 {
                authMethodPicker
            }

            if viewModel.selectedAuthMethod == .classic {
                classicAuthFields
            } else {
                clientTokenAuthSection
            }

            loginButton
        }
    }

    /// Opening lines of the two questions the setup screen can send users to.
    /// Prefixes, not full headlines, so editing `FAQ.md` cannot break the link.
    private static let signInHelpQuestion = "I can sign in from Safari"
    private static let reachServerHelpQuestion = "The app cannot reach my server"

    /// Way out of a failed sign-in: opens the help on the question that matches
    /// the error the user is looking at.
    private func helpLink(for question: String) -> some View {
        Button {
            helpTopic = HelpTopic(question: question)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 11))
                Text("Why does this happen?")
                    .font(.system(size: 12.5))
                    .underline()
            }
            .foregroundStyle(.white.opacity(0.7))
        }
        .buttonStyle(.plain)
    }

    /// Small inline error row reused across auth sections.
    private func setupErrorHint(_ message: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(SetupTheme.errorIcon)
            Text(message)
                .font(.system(size: 12.5))
                .foregroundStyle(SetupTheme.errorText)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Login Button

    private var loginButton: some View {
        Button {
            Task { await viewModel.handlePrimaryAction() }
        } label: {
            ZStack {
                if viewModel.isBusy {
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(SetupTheme.onAccent)
                            .frame(width: 18, height: 18)
                        Text(viewModel.isExchangingToken ? "Connecting…" : "Logging in…")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(SetupTheme.onAccent)
                    }
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: buttonIcon)
                            .font(.system(size: 15, weight: .semibold))
                        Text(buttonLabel)
                            .font(.system(size: 16, weight: .bold))
                    }
                    .foregroundStyle(viewModel.canSubmit ? SetupTheme.onAccent : .white.opacity(0.4))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(buttonBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: viewModel.canSubmit && !viewModel.isBusy ? buttonShadowColor.opacity(0.4) : .clear, radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.canSubmit)
        .animation(.easeInOut(duration: 0.2), value: viewModel.canSubmit)
        .animation(.easeInOut(duration: 0.2), value: viewModel.isBusy)
        .animation(.easeInOut(duration: 0.2), value: viewModel.isVersionWarning)
    }

    private var buttonIcon: String {
        if viewModel.isVersionWarning { return "arrow.right" }
        if viewModel.selectedAuthMethod == .clientToken { return "key.fill" }
        return "rectangle.portrait.and.arrow.right"
    }

    private var buttonLabel: String {
        if viewModel.hasLoginError { return "Try Again" }
        if viewModel.isVersionWarning { return "Login Anyway" }
        if viewModel.selectedAuthMethod == .clientToken { return "Connect with Token" }
        return "Login"
    }

    private var buttonShadowColor: Color {
        viewModel.isVersionWarning ? SetupTheme.amber : SetupTheme.coralLight
    }

    @ViewBuilder
    private var buttonBackground: some View {
        if viewModel.canSubmit && !viewModel.isBusy {
            if viewModel.isVersionWarning {
                SetupTheme.amberGradient
            } else {
                SetupTheme.coralGradient
            }
        } else {
            Color.white.opacity(0.06)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                )
        }
    }
}

// MARK: - QuickInputChip Component

struct QuickInputChip: View {
    let text: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.07))
                .foregroundStyle(Color.white.opacity(0.6))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.11), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Connection Debug Panel

struct ConnectionDebugPanel: View {
    let logs: [ConnectionLogEntry]
    @Binding var isExpanded: Bool
    @State private var copied = false

    static func formatLogsForClipboard(_ logs: [ConnectionLogEntry], appVersion: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let header = "RomM iOS v\(appVersion)\n\n"
        let body = logs.map { entry in
            var line = "\(formatter.string(from: entry.timestamp)) [\(entry.type.label)] \(entry.message)"
            if let details = entry.details {
                line += "\n  \(details)"
            }
            return line
        }.joined(separator: "\n")
        return header + body
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "ant.fill")
                        .foregroundStyle(.white.opacity(0.5))
                    Text("Connection Details")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.75))
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.white.opacity(0.4))
                        .font(.caption)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(logs) { log in
                                ConnectionLogRow(entry: log)
                                    .id(log.id)
                            }
                        }
                    }
                    .frame(maxHeight: 150)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .onChange(of: logs.count) { _, _ in
                        if let lastLog = logs.last {
                            withAnimation {
                                proxy.scrollTo(lastLog.id, anchor: .bottom)
                            }
                        }
                    }
                }

                Button {
                    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
                    UIPasteboard.general.string = ConnectionDebugPanel.formatLogsForClipboard(logs, appVersion: version)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        copied = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.caption)
                        Text(copied ? "Copied ✓" : "Copy log")
                            .font(.caption)
                    }
                    .foregroundStyle(copied ? SetupTheme.green : .white.opacity(0.45))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Connection Log Row

struct ConnectionLogRow: View {
    let entry: ConnectionLogEntry

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: entry.timestamp)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(timeString)
                .font(.caption2.monospaced())
                .foregroundStyle(.white.opacity(0.4))

            Image(systemName: entry.type.icon)
                .font(.caption)
                .foregroundStyle(entry.type.color)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.message)
                    .font(.caption.monospaced())
                    .foregroundStyle(.white.opacity(0.85))

                if let details = entry.details {
                    Text(details)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.45))
                }
            }

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}
