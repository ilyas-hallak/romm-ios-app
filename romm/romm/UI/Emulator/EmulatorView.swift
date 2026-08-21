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

        /// RomM 4.x web chrome, Vuetify-based layout.
        private static let legacyUISelectors: [String] = [
            "header.v-toolbar",
            "header.v-bottom-navigation",
            "nav.v-navigation-drawer",
            ".v-toolbar",
            ".v-navigation-drawer",
            ".v-bottom-navigation",
            "div.my-4",
            "div.mt-4.align-center > div:first-child",
            "div.sticky-bottom",
        ]

        /// RomM 5.x web chrome: AppNav top bar, BottomNav pill, UserMenu chip,
        /// toast host and upload progress toast. The last two can pop up
        /// mid-game, the rest is permanent chrome.
        ///
        /// Matched on a class substring rather than an exact class name,
        /// because the shell decorates these blocks with BEM suffixes and
        /// renames them between releases: the pill shipped as
        /// `r-v2-bottom-nav-anchor` at one point and is plain
        /// `r-v2-bottom-nav` now, wrapping a `r-v2-bottom-nav__group`. An
        /// exact selector silently stops matching on such a rename, a
        /// substring survives it.
        private static let v2UISelectors: [String] = [
            "[class*=\"r-v2-nav\"]",
            "[class*=\"r-v2-bottom-nav\"]",
            "[class*=\"r-v2-user\"]",
            "[class*=\"r-v2-toast\"]",
            "[class*=\"r-v2-upload\"]",
        ]

        /// Every selector that gets hidden. A selector that matches nothing is
        /// a no-op, so both server generations stay covered at once without a
        /// version check.
        private static var hiddenUISelectors: [String] {
            legacyUISelectors + v2UISelectors
        }

        private func injectFullscreenCSS(_ webView: WKWebView) {
            let selectorList = Self.hiddenUISelectors.joined(separator: ", ")

            // Hiding the chrome is not enough on RomM 5.x: the EmulatorJS
            // stage is laid out as `inset: var(--r-nav-h) 0 0 0`, so it
            // still starts below where the navbar used to be and leaves an
            // empty strip at the top. Zeroing the variable closes that gap.
            // RomM declares it on `.r-v2`, a class it toggles on <html>, so
            // `:root` and `.r-v2` are the same element and !important wins.
            // Both are listed in case the class ever moves off the root.
            // This override is deliberately kept out of the selector list
            // above, it assigns a variable rather than hiding an element and
            // must not affect the match count.
            // Upstream has no fullscreen mode or URL parameter for this,
            // see rommapp/romm#4081.
            let css = """
                \(selectorList) {
                    display: none !important;
                    visibility: hidden !important;
                }

                :root,
                .r-v2 {
                    --r-nav-h: 0px !important;
                }
                """

            // After injecting the styles, report the match count per selector
            // rather than one total. A selector that silently stops matching
            // after an upstream rename is the failure mode here, and a total
            // hides it as long as the other selectors still match.
            let selectorsArray = Self.hiddenUISelectors
                .map { "'\($0)'" }
                .joined(separator: ", ")

            let javascript = """
                (function() {
                    try {
                        var style = document.createElement('style');
                        style.textContent = `\(css)`;
                        document.head.appendChild(style);

                        var counts = {};
                        [\(selectorsArray)].forEach(function(selector) {
                            counts[selector] = document.querySelectorAll(selector).length;
                        });
                        return counts;
                    } catch(e) {
                        console.error('❌ CSS injection failed:', e);
                        return null;
                    }
                })();
                """

            webView.evaluateJavaScript(javascript) { result, error in
                if let error = error {
                    self.logger.error("❌ Failed to inject CSS: \(error.localizedDescription)")
                    return
                }
                guard let raw = result as? [String: Any] else {
                    self.logger.info("✅ CSS injected")
                    return
                }
                let counts = raw.compactMapValues { ($0 as? NSNumber)?.intValue }
                let hidden = counts.values.reduce(0, +)

                if hidden == 0 {
                    self.logger.warning(
                        "⚠️ CSS injected but no UI elements matched, RomM layout may have changed"
                    )
                } else {
                    self.logger.info("✅ CSS injected, \(hidden) UI element(s) hidden")
                }

                // Only the generation that matched something can have dead
                // selectors worth reporting, the other one is expected to
                // match nothing on this server.
                let v2IsLive = Self.v2UISelectors.contains { (counts[$0] ?? 0) > 0 }
                let live = v2IsLive ? Self.v2UISelectors : Self.legacyUISelectors
                let dead = live.filter { (counts[$0] ?? 0) == 0 }
                if !dead.isEmpty {
                    self.logger.warning(
                        "⚠️ Selectors matched nothing: \(dead.joined(separator: ", "))"
                    )
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

