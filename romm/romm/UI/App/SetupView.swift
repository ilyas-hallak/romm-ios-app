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
    @State private var serverURL = ""
    @State private var username = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var showConnectionDetails = false

    // Connection validation states
    @State private var isConnecting = false
    @State private var serverValidated = false
    @State private var detectedServerVersion: String?
    @State private var connectionError: String?
    @State private var connectionErrorDetails: String?
    @State private var isErrorExpanded = false
    @State private var isVersionWarning = false
    @State private var didAcceptIncompatibleVersion = false

    // Version warning detail text
    @State private var versionWarningTitle: String?
    @State private var versionWarningDetails: String?

    // Auth capability detection
    @State private var detectedAuthCapability: HeartbeatRepository.AuthCapabilities?
    @State private var selectedAuthMethod: AuthMethod = .classic

    // Client Token states
    @State private var clientTokenInput = ""
    @State private var isExchangingToken = false
    @State private var clientTokenError: String?
    @State private var showQRScanner = false

    // Device flow (browser) states
    @State private var deviceFlowInit: DeviceAuthInitResponse?
    @State private var isDeviceFlowRunning = false
    @State private var deviceFlowError: String?
    @State private var deviceFlowTask: Task<Void, Never>?

    // "Other sign-in options" disclosure
    @State private var showOtherOptions = false

    // Focus
    @FocusState private var focusedField: SetupField?

    private var connectionLogger: ConnectionLogger { ConnectionLogger.shared }
    private let launchArguments = ProcessInfo.processInfo.arguments
    private var shouldShowLoginForUITests: Bool { launchArguments.contains("-ui_testing_show_login") }

    // MARK: - Computed helpers

    private var isBusy: Bool {
        appViewModel.appData.isLoading || isExchangingToken || isConnecting || isDeviceFlowRunning
    }

    /// Whether the browser device-flow is the primary path. Optimistic before the
    /// server is validated; after validation, only when the server supports it.
    private var showDeviceFlowPrimary: Bool {
        guard let cap = detectedAuthCapability else { return true }
        return cap.deviceFlow
    }

    /// Fallback methods (username/password, API token) shown under "Other options".
    private var otherMethods: [AuthMethod] {
        guard let cap = detectedAuthCapability else { return [.classic, .clientToken] }
        return AuthMethod.availableMethods(for: cap).filter { $0 != .deviceFlow }
    }

    private var canSubmit: Bool {
        guard !isBusy && !serverURL.isEmpty else { return false }
        switch selectedAuthMethod {
        case .deviceFlow:
            return false // Browser sign-in has its own button, not this one.
        case .classic:
            return !username.isEmpty && !password.isEmpty
        case .clientToken:
            return !clientTokenInput.isEmpty
        }
    }

    private var hasLoginError: Bool {
        appViewModel.appData.errorMessage != nil
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
                        .padding(.horizontal, 20)

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

                    // Connection Debug Panel
                    if !connectionLogger.logs.isEmpty || connectionLogger.isConnecting {
                        ConnectionDebugPanel(
                            logs: connectionLogger.logs,
                            isExpanded: $showConnectionDetails
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
            seedUITestLoginStateIfNeeded()
            preloadLastServerURL()
        }
        .onDisappear {
            deviceFlowTask?.cancel()
        }
        .onTapGesture {
            hideKeyboard()
        }
        .onChange(of: focusedField) { _, newValue in
            // Auto-validate when URL field loses focus
            if newValue != .url && !serverURL.isEmpty && !serverValidated && !isConnecting {
                Task { await validateServer() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .clientTokenPairingCode)) { notification in
            if let code = notification.userInfo?["code"] as? String {
                Task {
                    await performClientTokenPairing(code: code)
                }
            }
        }
        .sheet(isPresented: $showQRScanner) {
            QRScannerView { code in
                showQRScanner = false
                Task {
                    await performClientTokenPairing(code: code)
                }
            }
        }
    }

    // MARK: - Glass Card

    private var glassCard: some View {
        VStack(spacing: 16) {
            // Server URL field
            urlFieldSection

            // Version warning banner
            if isVersionWarning, let title = versionWarningTitle {
                versionWarningBanner(title: title, details: versionWarningDetails)
            }

            // Primary: browser device-flow sign-in
            if showDeviceFlowPrimary {
                deviceFlowSection
            }

            // Fallback methods (username/password, API token)
            otherOptionsSection
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
            let urlState: SetupFieldState = connectionError != nil ? .error : (focusedField == .url ? .focused : .normal)

            HStack(spacing: 10) {
                Image(systemName: "link")
                    .font(.system(size: 15))
                    .foregroundStyle(serverValidated ? .white.opacity(0.55) : .white.opacity(0.4))
                    .frame(width: 20)

                TextField("", text: $serverURL, prompt: Text(verbatim: "https://romm.example.com")
                    .foregroundColor(.white.opacity(0.3)))
                    .font(.system(size: 14.5))
                    .foregroundStyle(.white)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .focused($focusedField, equals: .url)
                    .onSubmit {
                        Task {
                            await validateServer()
                            focusedField = .username
                        }
                    }
                    .onChange(of: serverURL) { _, _ in
                        if serverValidated || isVersionWarning || connectionError != nil {
                            resetServerValidation()
                        }
                    }

                // Version badge (shown when validated or version warning)
                if (serverValidated || isVersionWarning), let version = detectedServerVersion {
                    versionBadge(version: version)
                }

                // Spinner while connecting
                if isConnecting {
                    ProgressView()
                        .scaleEffect(0.75)
                        .tint(.white.opacity(0.6))
                }
            }
            .setupField(urlState)

            // Quick input chips — only when not validated and no error/warning
            if !serverValidated && connectionError == nil && !isVersionWarning {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        QuickInputChip(text: "192.168.", action: { insertText("192.168.") })
                        QuickInputChip(text: "http://", action: { insertText("http://") })
                        QuickInputChip(text: "https://", action: { insertText("https://") })
                        QuickInputChip(text: ":8080", action: { insertText(":8080") })
                        QuickInputChip(text: ".com", action: { insertText(".com") })
                        QuickInputChip(text: ".de", action: { insertText(".de") })
                    }
                    .padding(.vertical, 2)
                }
            }

            // Connection error banner (hard error only — not version warning)
            if connectionError != nil && !isVersionWarning {
                connectionErrorBanner
            }
        }
    }

    // MARK: - Version Badge

    private func versionBadge(version: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: isVersionWarning ? "exclamationmark.triangle.fill" : "checkmark")
                .font(.system(size: 9, weight: .bold))
            Text("v\(version)")
                .font(.system(size: 10.5, weight: .semibold))
        }
        .foregroundStyle(isVersionWarning ? SetupTheme.amber : SetupTheme.greenText)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(isVersionWarning ? SetupTheme.amber.opacity(0.15) : SetupTheme.green.opacity(0.15))
        )
        .overlay(
            Capsule()
                .strokeBorder(isVersionWarning ? SetupTheme.amber.opacity(0.4) : SetupTheme.green.opacity(0.4), lineWidth: 1)
        )
    }

    // MARK: - Connection Error Banner

    private var connectionErrorBanner: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isErrorExpanded.toggle()
                }
            } label: {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(SetupTheme.errorIcon)
                        .font(.system(size: 13))

                    Text(connectionError ?? "")
                        .font(.system(size: 12.5))
                        .foregroundStyle(SetupTheme.errorText)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)

                    Spacer()

                    if connectionErrorDetails != nil {
                        Image(systemName: isErrorExpanded ? "chevron.up" : "chevron.down")
                            .foregroundStyle(.white.opacity(0.4))
                            .font(.caption)
                    }
                }
            }
            .buttonStyle(.plain)

            if isErrorExpanded, let details = connectionErrorDetails {
                Text(details)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.leading, 21)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
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

            Picker("Auth Method", selection: $selectedAuthMethod) {
                ForEach(otherMethods, id: \.self) { method in
                    Label(method.displayName, systemImage: method.iconName)
                        .tag(method)
                }
            }
            .pickerStyle(.segmented)

            Text(selectedAuthMethod.description)
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

                    TextField("", text: $username, prompt: Text("Username")
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

                let pwState: SetupFieldState = hasLoginError ? .error : (focusedField == .password ? .focused : .normal)

                HStack(spacing: 10) {
                    Image(systemName: "lock")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.4))
                        .frame(width: 20)

                    Group {
                        if showPassword {
                            TextField("", text: $password, prompt: Text("Password")
                                .foregroundColor(.white.opacity(0.3)))
                        } else {
                            SecureField("", text: $password, prompt: Text("Password")
                                .foregroundColor(.white.opacity(0.3)))
                        }
                    }
                    .font(.system(size: 14.5))
                    .foregroundStyle(.white)
                    .textContentType(.password)
                    .focused($focusedField, equals: .password)
                    .onSubmit {
                        Task { await handlePrimaryAction() }
                    }

                    Button {
                        showPassword.toggle()
                    } label: {
                        Image(systemName: showPassword ? "eye.slash" : "eye")
                            .font(.system(size: 15))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                }
                .setupField(pwState)

                // Login error hint
                if hasLoginError, let errorMessage = appViewModel.appData.errorMessage {
                    HStack(spacing: 5) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(SetupTheme.errorIcon)
                        Text(errorMessage)
                            .font(.system(size: 12.5))
                            .foregroundStyle(SetupTheme.errorText)
                    }
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
                showQRScanner = true
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

                    TextField("", text: $clientTokenInput, prompt: Text("rmm_...")
                        .foregroundColor(.white.opacity(0.3)))
                        .font(.system(size: 13.5, design: .monospaced))
                        .foregroundStyle(.white)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .focused($focusedField, equals: .token)
                }
                .setupField(focusedField == .token ? .focused : .normal)
            }

            if let error = clientTokenError {
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
            if let info = deviceFlowInit, isDeviceFlowRunning {
                deviceFlowWaitingView(info: info)
            } else {
                Button {
                    Task { await startDeviceFlow() }
                } label: {
                    HStack(spacing: 8) {
                        if isDeviceFlowRunning {
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
                    .foregroundStyle(deviceFlowButtonEnabled ? SetupTheme.onAccent : .white.opacity(0.4))
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(deviceFlowButtonBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: deviceFlowButtonEnabled ? SetupTheme.coralLight.opacity(0.4) : .clear, radius: 10, x: 0, y: 4)
                }
                .buttonStyle(.plain)
                .disabled(!deviceFlowButtonEnabled)

                Text("Approve this device in your browser — no password needed.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }

            if let deviceFlowError {
                setupErrorHint(deviceFlowError)
            }
        }
    }

    private var deviceFlowButtonEnabled: Bool {
        !serverURL.isEmpty && !isBusy
    }

    @ViewBuilder
    private var deviceFlowButtonBackground: some View {
        if deviceFlowButtonEnabled {
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
                    openApprovalBrowser(info: info)
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
                    cancelDeviceFlow()
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
        if showDeviceFlowPrimary {
            if !otherMethods.isEmpty {
                VStack(spacing: 14) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showOtherOptions.toggle() }
                    } label: {
                        HStack {
                            Text("Other sign-in options")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.7))
                            Spacer()
                            Image(systemName: showOtherOptions ? "chevron.up" : "chevron.down")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.4))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if showOtherOptions {
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
            if otherMethods.count > 1 {
                authMethodPicker
            }

            if selectedAuthMethod == .classic {
                classicAuthFields
            } else {
                clientTokenAuthSection
            }

            loginButton
        }
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
            Task { await handlePrimaryAction() }
        } label: {
            ZStack {
                if isBusy {
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(SetupTheme.onAccent)
                            .frame(width: 18, height: 18)
                        Text(isExchangingToken ? "Connecting…" : "Logging in…")
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
                    .foregroundStyle(canSubmit ? SetupTheme.onAccent : .white.opacity(0.4))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(buttonBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: canSubmit && !isBusy ? buttonShadowColor.opacity(0.4) : .clear, radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit)
        .animation(.easeInOut(duration: 0.2), value: canSubmit)
        .animation(.easeInOut(duration: 0.2), value: isBusy)
        .animation(.easeInOut(duration: 0.2), value: isVersionWarning)
    }

    private var buttonIcon: String {
        if isVersionWarning { return "arrow.right" }
        if selectedAuthMethod == .clientToken { return "key.fill" }
        return "rectangle.portrait.and.arrow.right"
    }

    private var buttonLabel: String {
        if hasLoginError { return "Try Again" }
        if isVersionWarning { return "Login Anyway" }
        if selectedAuthMethod == .clientToken { return "Connect with Token" }
        return "Login"
    }

    private var buttonShadowColor: Color {
        isVersionWarning ? SetupTheme.amber : SetupTheme.coralLight
    }

    @ViewBuilder
    private var buttonBackground: some View {
        if canSubmit && !isBusy {
            if isVersionWarning {
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

    // MARK: - Primary Action Handler

    private func handlePrimaryAction() async {
        if !serverValidated {
            await validateServer()
        }
        // Only proceed to login when server is validated, no hard error, and no unaccepted warning
        guard serverValidated && connectionError == nil else { return }
        // If version warning: accept incompatible version and remember it so the
        // foreground version check doesn't immediately warn about the same version.
        if isVersionWarning {
            didAcceptIncompatibleVersion = true
            if let version = detectedServerVersion {
                appViewModel.acknowledgeServerVersion(version)
            }
        }
        if selectedAuthMethod == .clientToken {
            await performClientTokenLogin()
        } else {
            await performClassicLogin()
        }
    }

    // MARK: - Actions

    private func validateServer() async {
        hideKeyboard()
        isConnecting = true
        connectionError = nil
        connectionErrorDetails = nil
        isErrorExpanded = false
        isVersionWarning = false
        versionWarningTitle = nil
        versionWarningDetails = nil
        didAcceptIncompatibleVersion = false
        detectedAuthCapability = nil

        do {
            let version = try await appViewModel.fetchServerVersion(from: serverURL)
            detectedServerVersion = version

            if appViewModel.isVersionCompatible(version) {
                serverValidated = true
                connectionError = nil
                didAcceptIncompatibleVersion = false
                await detectAuthenticationMethod()
            } else if version == "development" {
                versionWarningTitle = "Development Build"
                versionWarningDetails = "This server is running a development version of RomM. Compatibility is not guaranteed."
                isVersionWarning = true
                serverValidated = true
                await detectAuthenticationMethod()
            } else {
                versionWarningTitle = "Incompatible Server Version"
                versionWarningDetails = "Server v\(version) is outside the supported range (\(appViewModel.minSupportedServerVersion) – \(appViewModel.maxSupportedServerVersion)). Some features may not work correctly."
                isVersionWarning = true
                serverValidated = true
                await detectAuthenticationMethod()
            }
        } catch let error as APIClientError {
            if case .cloudflareProtection = error {
                connectionError = "Server is protected by Cloudflare"
                connectionErrorDetails = "This server is behind Cloudflare protection and cannot be accessed directly."
                isVersionWarning = false
            } else {
                let (message, details) = parseConnectionError(error)
                connectionError = message
                connectionErrorDetails = details
                isVersionWarning = false
            }
            serverValidated = false
            didAcceptIncompatibleVersion = false
        } catch let error as HeartbeatError {
            switch error {
            case .decodingError:
                connectionError = "Invalid Response"
                connectionErrorDetails = "The server did not return a valid RomM response. Is this a RomM server?"
            default:
                let (message, details) = parseConnectionError(error)
                connectionError = message
                connectionErrorDetails = details
            }
            isVersionWarning = false
            serverValidated = false
            didAcceptIncompatibleVersion = false
        } catch {
            let (message, details) = parseConnectionError(error)
            connectionError = message
            connectionErrorDetails = details
            isVersionWarning = false
            serverValidated = false
            didAcceptIncompatibleVersion = false
        }

        isConnecting = false
    }

    // MARK: - Auth Detection

    private func detectAuthenticationMethod() async {
        let heartbeatRepo = HeartbeatRepository()
        Logger.auth.info("Detecting authentication methods...")
        let capabilities = await heartbeatRepo.detectAuthCapabilities(serverURL: serverURL)
        detectedAuthCapability = capabilities
        Logger.auth.info("Detected capabilities: \(capabilities.description)")
        connectionError = nil
        connectionErrorDetails = nil

        if capabilities.unreachable {
            serverValidated = false
            connectionError = "Server is unreachable"
            connectionErrorDetails = "Could not connect to the server."
            return
        }
        if capabilities.cloudflareBlocked {
            serverValidated = false
            connectionError = "Server is protected by Cloudflare"
            connectionErrorDetails = "This server is behind Cloudflare protection and cannot be accessed directly."
            return
        }
        serverValidated = true
        if capabilities.classic {
            selectedAuthMethod = .classic
        } else if capabilities.clientTokens {
            selectedAuthMethod = .clientToken
        }
    }

    private func parseConnectionError(_ error: Error) -> (message: String, details: String?) {
        if let apiError = error as? APIClientError {
            switch apiError {
            case .cloudflareProtection:
                return ("Server is protected by Cloudflare", "This server is behind Cloudflare protection and cannot be accessed directly.")
            case .authenticationRequired:
                return ("Authentication failed", "Invalid username or password")
            case .invalidURL(let url):
                return ("Invalid URL", "The URL '\(url)' is not valid")
            case .noConfiguration:
                return ("Configuration error", "Server configuration is missing")
            case .noCredentials:
                return ("Credentials missing", "Please provide username and password")
            case .invalidResponse(let code, _):
                return ("Server error (\(code))", "The server returned an error response")
            case .decodingError:
                return ("Invalid response", "The server did not return a valid RomM response")
            case .networkError(let underlyingError):
                return parseGeneralConnectionError(underlyingError)
            }
        }
        return parseGeneralConnectionError(error)
    }

    private func parseGeneralConnectionError(_ error: Error) -> (message: String, details: String?) {
        let errorString = error.localizedDescription

        if errorString.contains("certificate") || errorString.contains("SSL") || errorString.contains("TLS") {
            return ("SSL/TLS certificate error", "Check if the server has a valid certificate or use http:// instead of https://")
        }
        if errorString.contains("Could not connect") || errorString.contains("Connection refused") {
            return ("Connection failed", "Check if the server is running and the URL is correct.")
        }
        if errorString.contains("timed out") || errorString.contains("timeout") {
            return ("Connection timed out", "The server did not respond in time. Check if the server is reachable.")
        }
        if errorString.contains("host") || errorString.contains("DNS") || errorString.contains("resolve") {
            return ("Server not found", "DNS resolution failed. Check the server URL.")
        }
        if errorString.contains("network") || errorString.contains("internet") {
            return ("Network error", "Check your internet connection.")
        }
        if errorString.contains("decode") || errorString.contains("JSON") || errorString.contains("invalid") {
            return ("Invalid response", "The server did not return a valid RomM response. Is this a RomM server?")
        }
        return ("Connection error", errorString)
    }

    private func resetServerValidation() {
        serverValidated = false
        detectedServerVersion = nil
        connectionError = nil
        connectionErrorDetails = nil
        isErrorExpanded = false
        isVersionWarning = false
        versionWarningTitle = nil
        versionWarningDetails = nil
        didAcceptIncompatibleVersion = false
        // Abort any in-flight browser pairing — it's tied to the old server.
        cancelDeviceFlow()
        // NOTE: username/password are intentionally NOT cleared here
    }

    private func performClassicLogin() async {
        if let version = detectedServerVersion {
            appViewModel.saveServerVersion(version)
        }
        await appViewModel.saveConfiguration(
            serverURL: serverURL,
            username: username,
            password: password
        )
    }

    // MARK: - Client Token Login

    @MainActor
    private func performClientTokenLogin() async {
        isExchangingToken = true
        clientTokenError = nil
        let service = ClientTokenAuthService()
        do {
            let tokenInfo = try await service.validateToken(serverURL: serverURL, token: clientTokenInput)
            try service.saveToken(clientTokenInput, info: tokenInfo)
            let setupRepo = SetupRepository()
            if let version = detectedServerVersion {
                appViewModel.saveServerVersion(version)
            }
            try setupRepo.saveClientTokenSetup(
                serverURL: serverURL,
                tokenName: tokenInfo.name,
                version: detectedServerVersion ?? "unknown",
                allowIncompatibleVersionLogin: didAcceptIncompatibleVersion
            )
            Logger.auth.info("Client token login complete")
            appViewModel.appData.isLoading = false
            appViewModel.appData.errorMessage = nil
            await appViewModel.checkInitialState()
        } catch {
            Logger.auth.error("Client token login failed: \(error)")
            clientTokenError = error.localizedDescription
        }
        isExchangingToken = false
    }

    @MainActor
    private func performClientTokenPairing(code: String) async {
        isExchangingToken = true
        clientTokenError = nil
        let service = ClientTokenAuthService()
        do {
            let (token, tokenInfo) = try await service.exchangeCode(serverURL: serverURL, code: code)
            try service.saveToken(token, info: tokenInfo)
            let setupRepo = SetupRepository()
            if let version = detectedServerVersion {
                appViewModel.saveServerVersion(version)
            }
            try setupRepo.saveClientTokenSetup(
                serverURL: serverURL,
                tokenName: tokenInfo.name,
                version: detectedServerVersion ?? "unknown",
                allowIncompatibleVersionLogin: didAcceptIncompatibleVersion
            )
            Logger.auth.info("Client token pairing complete")
            appViewModel.appData.isLoading = false
            appViewModel.appData.errorMessage = nil
            await appViewModel.checkInitialState()
        } catch {
            Logger.auth.error("Client token pairing failed: \(error)")
            clientTokenError = error.localizedDescription
        }
        isExchangingToken = false
    }

    // MARK: - Device Flow Actions

    @MainActor
    private func startDeviceFlow() async {
        hideKeyboard()
        deviceFlowError = nil

        if !serverValidated {
            await validateServer()
        }
        guard serverValidated && connectionError == nil else { return }

        if isVersionWarning {
            didAcceptIncompatibleVersion = true
            if let version = detectedServerVersion {
                appViewModel.acknowledgeServerVersion(version)
            }
        }

        // Server validated but doesn't offer the browser flow — point the user
        // at the fallback methods instead of failing silently.
        if let cap = detectedAuthCapability, !cap.deviceFlow {
            deviceFlowError = "This server doesn't support browser sign-in. Use another method below."
            withAnimation { showOtherOptions = true }
            return
        }

        isDeviceFlowRunning = true
        let service = DeviceAuthService()
        do {
            let info = try await service.initPairing(serverURL: serverURL)
            deviceFlowInit = info
            openApprovalBrowser(info: info)
            deviceFlowTask = Task { await pollDeviceFlow(service: service, info: info) }
        } catch {
            isDeviceFlowRunning = false
            deviceFlowInit = nil
            deviceFlowError = error.localizedDescription
        }
    }

    private func openApprovalBrowser(info: DeviceAuthInitResponse) {
        guard let url = DeviceAuthService().verificationURL(serverURL: serverURL, init: info) else { return }
        UIApplication.shared.open(url)
    }

    @MainActor
    private func pollDeviceFlow(service: DeviceAuthService, info: DeviceAuthInitResponse) async {
        do {
            let token = try await service.pollForToken(serverURL: serverURL, init: info)
            await finishDeviceFlow(token: token)
        } catch {
            if case DeviceAuthError.cancelled = error {
                // User cancelled — no error message needed.
            } else {
                deviceFlowError = error.localizedDescription
            }
            isDeviceFlowRunning = false
            deviceFlowInit = nil
        }
    }

    @MainActor
    private func finishDeviceFlow(token: DeviceAuthTokenResponse) async {
        let clientService = ClientTokenAuthService()
        let info = ClientTokenInfo(
            tokenId: 0,
            name: "Browser Sign-In",
            scopes: token.scopes,
            expiresAt: Self.parseISODate(token.expiresAt)
        )
        do {
            try clientService.saveToken(token.accessToken, info: info)
            // The device-flow token is bound to a server device — reuse its id
            // for the save-sync device layer so we don't register twice.
            UserDefaults.standard.set(token.deviceId, forKey: "sync.deviceId")

            let setupRepo = SetupRepository()
            if let version = detectedServerVersion {
                appViewModel.saveServerVersion(version)
            }
            try setupRepo.saveClientTokenSetup(
                serverURL: serverURL,
                tokenName: info.name,
                version: detectedServerVersion ?? "unknown",
                allowIncompatibleVersionLogin: didAcceptIncompatibleVersion
            )
            Logger.auth.info("Browser device-flow login complete")
            appViewModel.appData.isLoading = false
            appViewModel.appData.errorMessage = nil
            isDeviceFlowRunning = false
            deviceFlowInit = nil
            await appViewModel.checkInitialState()
        } catch {
            Logger.auth.error("Failed to store device-flow token: \(error)")
            deviceFlowError = error.localizedDescription
            isDeviceFlowRunning = false
            deviceFlowInit = nil
        }
    }

    private func cancelDeviceFlow() {
        deviceFlowTask?.cancel()
        deviceFlowTask = nil
        isDeviceFlowRunning = false
        deviceFlowInit = nil
        deviceFlowError = nil
    }

    private static func parseISODate(_ string: String?) -> Date? {
        guard let string else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }

    private func preloadLastServerURL() {
        guard serverURL.isEmpty, !shouldShowLoginForUITests else { return }
        if let config = SetupRepository().getSetupConfiguration(), !config.serverURL.isEmpty {
            serverURL = config.serverURL
        }
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func insertText(_ text: String) {
        serverURL += text
    }

    private func seedUITestLoginStateIfNeeded() {
        guard shouldShowLoginForUITests else { return }

        if serverURL.isEmpty { serverURL = "https://demo.romm.app" }
        if username.isEmpty { username = "snapshot-user" }
        if password.isEmpty { password = "snapshot-password" }

        detectedServerVersion = "3.0.0"
        serverValidated = true
        connectionError = nil
        connectionErrorDetails = nil
        isVersionWarning = false
        versionWarningTitle = nil
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
