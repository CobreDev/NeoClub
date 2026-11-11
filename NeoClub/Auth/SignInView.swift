import SwiftUI
import WebKit

/// Hosts the Salesforce login page and intercepts the redirect to the AIO web callback.
/// The redirect is an https URL on a domain we don't own, so ASWebAuthenticationSession can't catch it.
struct SignInView: View {
    @Environment(AppModel.self) private var app
    @State private var pkce = PKCE()
    @State private var error: String?
    @State private var isExchanging = false
    @State private var showingWeb = false
    @State private var webError: String?
    @State private var webAttempt = UUID()

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "headphones.circle.fill")
                .font(.system(size: 88))
                .foregroundStyle(.tint)
            Text("NeoClub")
                .font(.largeTitle.bold())
            Text("Sign in with your Adventures in Odyssey Club account.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            if let error {
                Text(error).foregroundStyle(.red).font(.callout)
            }
            Spacer()
            Button {
                pkce = PKCE()
                error = nil
                webError = nil
                webAttempt = UUID()
                showingWeb = true
            } label: {
                Group {
                    if isExchanging { ProgressView() } else { Text("Sign In") }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isExchanging)
        }
        .padding(32)
        .frame(maxWidth: 480)
        .sheet(isPresented: $showingWeb) {
            NavigationStack {
                ZStack {
                    OAuthWebView(url: pkce.authorizeURL(), expectedState: pkce.state,
                                 onCode: { code in
                                     showingWeb = false
                                     Task { await finish(code: code) }
                                 },
                                 onFailure: { webError = $0 })
                    .id(webAttempt)
                    .ignoresSafeArea(edges: .bottom)
                    if let webError {
                        ContentUnavailableView {
                            Label("Couldn't load sign-in", systemImage: "wifi.exclamationmark")
                        } description: {
                            Text(webError)
                        } actions: {
                            Button("Retry") {
                                pkce = PKCE()
                                self.webError = nil
                                webAttempt = UUID()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .background(.background)
                    }
                }
                .navigationTitle("Sign In")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showingWeb = false }
                    }
                }
            }
        }
    }

    private func finish(code: String) async {
        isExchanging = true
        defer { isExchanging = false }
        do {
            try await AuthService.shared.exchange(code: code, verifier: pkce.verifier)
            await app.didSignIn()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct OAuthWebView: UIViewRepresentable {
    let url: URL
    let expectedState: String
    let onCode: (String) -> Void
    let onFailure: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(expectedState: expectedState, onCode: onCode, onFailure: onFailure)
    }

    func makeUIView(context: Context) -> WKWebView {
        // A fresh, non-persistent session per attempt: no stale cookies or pooled connections carry over.
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.load(URLRequest(url: url, timeoutInterval: 20))
        context.coordinator.armTimeout()
        return web
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        coordinator.timeout?.cancel()
        uiView.stopLoading()
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let expectedState: String
        let onCode: (String) -> Void
        let onFailure: (String) -> Void
        private var handled = false
        var timeout: DispatchWorkItem?

        init(expectedState: String, onCode: @escaping (String) -> Void, onFailure: @escaping (String) -> Void) {
            self.expectedState = expectedState
            self.onCode = onCode
            self.onFailure = onFailure
        }

        /// Surfaces a stalled load instead of leaving a blank sheet.
        func armTimeout() {
            timeout?.cancel()
            let item = DispatchWorkItem { [weak self] in
                guard let self, !self.handled else { return }
                SignInLog.write("timeout")
                self.onFailure("The sign-in page took too long to respond.")
            }
            timeout = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 25, execute: item)
        }

        private func fail(_ error: Error, _ kind: String) {
            SignInLog.write("\(kind): \(error.localizedDescription)")
            // -999 is our own cancel of the callback redirect; 102 is "frame load interrupted".
            let ns = error as NSError
            guard !handled, ns.code != NSURLErrorCancelled, ns.code != 102 else { return }
            timeout?.cancel()
            onFailure(error.localizedDescription)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            fail(error, "provisional fail")
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            fail(error, "fail")
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            SignInLog.write("finished: \(SignInLog.describe(webView.url))")
            timeout?.cancel()
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            SignInLog.write("navigate: \(SignInLog.describe(action.request.url)) mainFrame=\(action.targetFrame?.isMainFrame ?? false)")
            guard let url = action.request.url,
                  url.absoluteString.hasPrefix(OAuthConfig.redirectURI) else {
                decisionHandler(.allow)
                return
            }
            decisionHandler(.cancel)
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let code = items.first { $0.name == "code" }?.value
            let state = items.first { $0.name == "state" }?.value
            if let code, state == expectedState, !handled {
                handled = true
                onCode(code)
            }
        }
    }
}

/// Debug-only sign-in trace. Logs host, path, and query parameter *names* only — never codes or tokens.
enum SignInLog {
    static func describe(_ url: URL?) -> String {
        guard let url, let c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return "nil" }
        let names = (c.queryItems ?? []).map(\.name).joined(separator: ",")
        return "\(c.host ?? "")\(c.path) [\(names)]"
    }

    static func write(_ line: String) {
        #if DEBUG
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("signin-log.txt")
        let entry = "\(Date().formatted(date: .omitted, time: .standard)) \(line)\n"
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(Data(entry.utf8)); try? h.close()
        } else {
            try? entry.write(to: url, atomically: true, encoding: .utf8)
        }
        #endif
    }
}
