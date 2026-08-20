//
//  EmulatorView.swift
//  romm
//
//  Created by Ilyas Hallak on 11.12.25.
//

import AVFoundation
import SwiftUI
import WebKit

struct EmulatorView: View {
    let rom: Rom
    @State private var viewModel: EmulatorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showExitConfirmation = false
    @State private var showMenu = false

    init(rom: Rom) {
        self.rom = rom
        _viewModel = State(initialValue: EmulatorViewModel(rom: rom))
    }

    var body: some View {
        NavigationView {
            ZStack {
                // WebView - Full screen
                EmulatorWebView(viewModel: viewModel)
                    .id(viewModel.emulatorURL?.absoluteString ?? "webview")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .edgesIgnoringSafeArea(.bottom)  // Ignore bottom, navbar handles top

                // Overlay Controls (optional, for later)
                if viewModel.showControls {
                    EmulatorControlsOverlay(
                        viewModel: viewModel,
                        onExit: { showExitConfirmation = true }
                    )
                    .transition(.opacity)
                }

                // Error Alert
                if let error = viewModel.errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.red)

                        Text(error)
                            .font(.body)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)

                        Button("Close") {
                            viewModel.clearError()
                            dismiss()
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .foregroundColor(.white)
                    }
                    .padding(32)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.black.opacity(0.9))
                    )
                    .padding()
                }
            }
            .navigationTitle(rom.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(
                            role: .destructive,
                            action: {
                                showExitConfirmation = true
                            }
                        ) {
                            Label("Exit", systemImage: "xmark.circle")
                        }

                        Button(action: {
                            viewModel.clearCacheAndReload()
                        }) {
                            Label("Clear Cache & Reload", systemImage: "arrow.clockwise")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                    }
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color.black.opacity(0.9), for: .navigationBar)
        }
        .navigationViewStyle(.stack)
        .statusBar(hidden: false)
        .preferredColorScheme(.dark)
        .alert("Quit Emulator?", isPresented: $showExitConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Quit", role: .destructive) {
                dismiss()
            }
        } message: {
            Text("Do you really want to quit the emulator?")
        }
        .onAppear {
            print("🎮 EmulatorView appeared - enabling landscape + portrait")
            OrientationLock.set([.portrait, .landscapeLeft, .landscapeRight])
        }
        .task {
            // Start emulator when view appears
            viewModel.startEmulator()
        }
        .onChange(of: viewModel.emulatorURL) { _, newURL in
            if let newURL {
                print("🔗 EmulatorView detected emulatorURL change: \(newURL.absoluteString)")
            } else {
                print("🔗 EmulatorView detected emulatorURL cleared")
            }
        }
        .onDisappear {
            print("🎮 EmulatorView disappeared - running cleanup")
            viewModel.cleanup()
        }
    }
}

struct EmulatorWebView: UIViewRepresentable {
    var viewModel: EmulatorViewModel

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        print("🧩 WKWebView makeUIView created")

        // Use persistent data store to keep cookies and login between app restarts
        config.websiteDataStore = WKWebsiteDataStore.default()

        // SYNC: Copy all cookies from HTTPCookieStorage to WKWebView
        // This ensures app's login cookies are available in WebView
        let sharedCookies = HTTPCookieStorage.shared.cookies ?? []
        print("🍪 Syncing \(sharedCookies.count) cookies from HTTPCookieStorage to WKWebView")
        for cookie in sharedCookies {
            config.websiteDataStore.httpCookieStore.setCookie(cookie)
        }

        // Audio & Media playback configuration
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        // Enable JavaScript and audio output in WebView
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        // Disable zoom
        let source = """
                var meta = document.createElement('meta');
                meta.name = 'viewport';
                meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no';
                var head = document.getElementsByTagName('head')[0];
                if (head) {
                    head.appendChild(meta);
                }
            """
        let script = WKUserScript(
            source: source,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(script)

        // Console.log forwarding for debugging
        let consoleScript = WKUserScript(
            source: """
                console.log = (function(oldLog) {
                    return function(message) {
                        oldLog.apply(console, arguments);
                        window.webkit.messageHandlers.consoleLog.postMessage(String(message));
                    };
                })(console.log);
                console.error = (function(oldError) {
                    return function(message) {
                        oldError.apply(console, arguments);
                        window.webkit.messageHandlers.consoleError.postMessage(String(message));
                    };
                })(console.error);
                """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        config.userContentController.addUserScript(consoleScript)

        // Message handlers
        config.userContentController.add(context.coordinator, name: "consoleLog")
        config.userContentController.add(context.coordinator, name: "consoleError")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.isScrollEnabled = true
        webView.scrollView.bounces = true
        webView.backgroundColor = .black

        // Configure audio session for playback (non-simulator only)
        #if !targetEnvironment(simulator)
            do {
                try AVAudioSession.sharedInstance().setCategory(
                    .playback, mode: .default, options: [])
                try AVAudioSession.sharedInstance().setActive(true)
                print("🔊 Audio session activated for playback")
            } catch {
                print("⚠️ Failed to activate audio session: \(error)")
            }
        #endif

        // Enable inspection in iOS Simulator
        #if DEBUG
            if #available(iOS 16.4, *) {
                webView.isInspectable = true
            }
        #endif

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        print("🔁 updateUIView called - hasLoaded: \(context.coordinator.hasLoaded), emulatorURL: \(String(describing: viewModel.emulatorURL))")

        guard let emulatorURL = viewModel.emulatorURL,
            context.coordinator.hasLoaded == false
        else {
            return
        }

        print("📱 Loading ROMM EmulatorJS from: \(emulatorURL.absoluteString)")

        // Store webView reference first
        context.coordinator.webView = webView
        context.coordinator.hasLoaded = true

        // Sync cookies from HTTPCookieStorage before loading
        Task { @MainActor in
            await context.coordinator.syncCookiesFromHTTPStorage(for: webView, url: emulatorURL)

            // Create request
            let request = URLRequest(url: emulatorURL)

            // Load the ROMM EmulatorJS page
            print("📱 Loading page now...")
            webView.load(request)

            context.coordinator.startReadyProbe(on: webView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        // Sync cookies FROM WebView back to HTTPCookieStorage before view is destroyed
        print("🍪 Syncing cookies from WKWebView back to HTTPCookieStorage")
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            for cookie in cookies {
                HTTPCookieStorage.shared.setCookie(cookie)
            }
            print("🍪 Synced \(cookies.count) cookies back to HTTPCookieStorage")
        }
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let viewModel: EmulatorViewModel
        var hasLoaded = false
        private var didRetryAfterProcessTermination = false
        weak var webView: WKWebView?
        private let logger = Logger.viewModel

        private var loadTimeoutTask: Task<Void, Never>?

        init(viewModel: EmulatorViewModel) {
            self.viewModel = viewModel
        }

        func startLoadTimeout(seconds: UInt64 = 25) {
            loadTimeoutTask?.cancel()
            loadTimeoutTask = Task { [weak self] in
                let ns = seconds * 1_000_000_000
                try? await Task.sleep(nanoseconds: ns)
                await MainActor.run {
                    guard let self, self.viewModel.isLoading else { return }
                    self.logger.error("⏱️ Load timed out after \(seconds)s")
                    self.viewModel.isLoading = false
                    self.viewModel.errorMessage = "Emulator start timed out. Please try again."
                }
            }
        }

        func cancelLoadTimeout() {
            loadTimeoutTask?.cancel()
            loadTimeoutTask = nil
        }

        func startReadyProbe(on webView: WKWebView) {
            let js = """
            (function() {
                try {
                    function postReady() {
                        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.consoleLog) {
                            window.webkit.messageHandlers.consoleLog.postMessage('EMULATOR_READY');
                        } else {
                            console.log('consoleLog handler not available');
                        }
                    }
                    function checkReady() {
                        try {
                            if (window.Emulator && (window.Emulator.isReady || window.Emulator.ready)) {
                                postReady();
                            } else if (window.Module && (window.Module.calledRun || window.Module.ready)) {
                                postReady();
                            } else {
                                setTimeout(checkReady, 500);
                            }
                        } catch (e) {
                            setTimeout(checkReady, 500);
                        }
                    }
                    setTimeout(checkReady, 500);
                } catch (e) {
                    console.error('READY probe install failed', e);
                }
            })();
            """
            webView.evaluateJavaScript(js, completionHandler: { _, error in
                if let error = error {
                    print("⚠️ Failed to inject READY probe: \(error.localizedDescription)")
                } else {
                    print("🔎 READY probe injected")
                }
            })
        }

        func syncCookiesFromHTTPStorage(for webView: WKWebView, url: URL) async {
            logger.info("🍪 Syncing cookies from HTTPCookieStorage to WKWebView")

            guard let domain = url.host else {
                logger.warning("⚠️ Cannot extract domain from URL: \(url.absoluteString)")
                return
            }

            // Get ALL cookies from shared storage (used by URLSession/API calls)
            let sharedCookies = HTTPCookieStorage.shared.cookies ?? []

            // Filter cookies relevant for this domain
            let relevantCookies = sharedCookies.filter { cookie in
                // Match if cookie domain contains URL domain or vice versa
                cookie.domain.contains(domain) || domain.contains(cookie.domain)
            }

            logger.info("🍪 Found \(sharedCookies.count) total cookies in HTTPCookieStorage")
            logger.info("🍪 \(relevantCookies.count) cookies match domain '\(domain)'")

            // Copy each relevant cookie to WKWebView
            for cookie in relevantCookies {
                await webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie)
                logger.info(
                    "   ✅ Synced: \(cookie.name) (domain: \(cookie.domain), expires: \(cookie.expiresDate?.description ?? "session"))"
                )
            }

            let store = webView.configuration.websiteDataStore.httpCookieStore
            store.getAllCookies { cookies in
                self.logger.info("🍪 WKWebView now has \(cookies.count) cookies")
                for c in cookies {
                    self.logger.info("   • \(c.name) (domain: \(c.domain), path: \(c.path))")
                }
            }

            logger.info("✅ Cookie sync complete - WKWebView should now be authenticated")
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!)
        {
            logger.info("🌐 WebView started loading navigation")
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            logger.info("🌐 WebView committed navigation (HTML parsing started)")
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            logger.info("✅ WebView finished loading navigation")
            didRetryAfterProcessTermination = false

            cancelLoadTimeout()

            // Inject CSS to hide ROMM UI and make emulator fullscreen
            injectFullscreenCSS(webView)

            startReadyProbe(on: webView)

            // Check if JavaScript is working
            webView.evaluateJavaScript("document.body ? 'body exists' : 'no body'") {
                result, error in
                if let error = error {
                    self.logger.error("❌ JavaScript test failed: \(error.localizedDescription)")
                } else if let result = result {
                    self.logger.info("✅ JavaScript working: \(result)")
                }
            }

            Task { @MainActor in
                viewModel.isLoading = false
            }
        }

        private func injectFullscreenCSS(_ webView: WKWebView) {
            // CSS to hide RomM UI elements and make the emulator fullscreen.
            // Two rule blocks cover both server generations simultaneously —
            // a selector that matches nothing is a no-op, so both can be
            // active at once without a version check.
            let css = """
                /* RomM 4.x (Vuetify-based layout) */
                header.v-toolbar,
                header.v-bottom-navigation,
                nav.v-navigation-drawer,
                .v-toolbar,
                .v-navigation-drawer,
                .v-bottom-navigation,
                div.my-4,
                div.mt-4.align-center > div:first-child,
                div.sticky-bottom {
                    display: none !important;
                    visibility: hidden !important;
                }

                /* RomM 5.x (v2 shell — AppNav top bar, BottomNav floating pill, UserMenu chip) */
                .r-v2-nav-bar,
                .r-v2-bottom-nav-anchor,
                .r-v2-user {
                    display: none !important;
                    visibility: hidden !important;
                }
                """

            // After injecting the styles, count how many elements were
            // actually hidden. Zero matches means the server layout has
            // changed again and the selectors need updating.
            let selectorList = [
                // 4.x selectors
                "header.v-toolbar", "header.v-bottom-navigation",
                "nav.v-navigation-drawer", ".v-toolbar",
                ".v-navigation-drawer", ".v-bottom-navigation",
                "div.my-4", "div.sticky-bottom",
                // 5.x selectors
                ".r-v2-nav-bar", ".r-v2-bottom-nav-anchor", ".r-v2-user",
            ].joined(separator: ", ")

            let javascript = """
                (function() {
                    try {
                        var style = document.createElement('style');
                        style.textContent = `\(css)`;
                        document.head.appendChild(style);

                        var matched = document.querySelectorAll('\(selectorList)').length;
                        return matched;
                    } catch(e) {
                        console.error('❌ CSS injection failed:', e);
                        return -1;
                    }
                })();
                """

            webView.evaluateJavaScript(javascript) { result, error in
                if let error = error {
                    self.logger.error("❌ Failed to inject CSS: \(error.localizedDescription)")
                } else if let count = result as? Int {
                    if count == 0 {
                        self.logger.warning(
                            "⚠️ CSS injected but no UI elements matched — RomM layout may have changed"
                        )
                    } else {
                        self.logger.info("✅ CSS injected, \(count) UI element(s) hidden")
                    }
                } else {
                    self.logger.info("✅ CSS injected")
                }
            }
        }

        func webView(
            _ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error
        ) {
            logger.error("❌ WebView navigation failed: \(error.localizedDescription)")

            cancelLoadTimeout()

            // Ignore cancelled navigation (common during normal operation)
            let nsError = error as NSError
            if nsError.code == NSURLErrorCancelled {
                logger.info("ℹ️ Navigation cancelled, safe to ignore")
                return
            }

            Task { @MainActor in
                viewModel.errorMessage = "Failed to load emulator: \(error.localizedDescription)"
                viewModel.isLoading = false
            }
        }

        func webView(
            _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            logger.error("❌ WebView provisional navigation failed: \(error.localizedDescription)")

            cancelLoadTimeout()

            Task { @MainActor in
                viewModel.errorMessage =
                    "Failed to connect to server: \(error.localizedDescription)"
                viewModel.isLoading = false
            }
        }

        // Handle WebView process termination (memory crash)
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            logger.error("⚠️ WebView process terminated")

            guard !didRetryAfterProcessTermination else {
                Task { @MainActor in
                    viewModel.errorMessage =
                        "Emulator crashed. This might be caused by:\n• ROM file too large\n• Not enough memory\n• Corrupted ROM\n\nTry restarting or use a smaller ROM."
                    viewModel.isLoading = false
                }
                return
            }

            Task { @MainActor in
                viewModel.errorMessage = nil
                viewModel.isLoading = true
            }

            didRetryAfterProcessTermination = true
            logger.warning("↻ Retrying web content load once after termination")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                webView.reload()
            }
        }

        func webView(
            _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if let url = navigationAction.request.url {
                logger.info("📍 Navigation request: \(url.absoluteString)")
            }
            decisionHandler(.allow)
        }

        func userContentController(
            _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
        ) {
            logger.info("📨 Received message from WebView: \(message.name)")

            switch message.name {
            case "consoleLog":
                if let msg = message.body as? String {
                    logger.info("🎮 [JS] \(msg)")

                    if msg == "EMULATOR_READY" {
                        self.logger.info("✅ JS reported EMULATOR_READY")
                        self.cancelLoadTimeout()
                        Task { @MainActor in
                            self.viewModel.isLoading = false
                        }
                    }
                }

            case "consoleError":
                if let msg = message.body as? String {
                    logger.error("❌ [JS Error] \(msg)")
                }

            default:
                logger.warning("⚠️ Unknown message: \(message.name)")
                break
            }
        }
    }
}

