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
                OAuthWebView(url: pkce.authorizeURL(), expectedState: pkce.state) { code in
                    showingWeb = false
                    Task { await finish(code: code) }
                }
                .ignoresSafeArea(edges: .bottom)
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

    func makeCoordinator() -> Coordinator { Coordinator(expectedState: expectedState, onCode: onCode) }

    func makeUIView(context: Context) -> WKWebView {
        let web = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        web.navigationDelegate = context.coordinator
        web.load(URLRequest(url: url))
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let expectedState: String
        let onCode: (String) -> Void
        private var handled = false
        init(expectedState: String, onCode: @escaping (String) -> Void) {
            self.expectedState = expectedState
            self.onCode = onCode
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
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
