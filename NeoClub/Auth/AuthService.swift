import Foundation

struct Tokens: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var identityURL: String?
}

enum AuthError: LocalizedError {
    case tokenExchangeFailed(String)
    case notSignedIn

    var errorDescription: String? {
        switch self {
        case .tokenExchangeFailed(let msg): "Sign-in failed: \(msg)"
        case .notSignedIn: "You're signed out."
        }
    }
}

/// Owns the OAuth tokens. An actor so concurrent 401s trigger a single refresh.
actor AuthService {
    static let shared = AuthService()
    private static let keychainKey = "tokens"

    private(set) var tokens: Tokens? = Keychain.getCodable(Tokens.self, for: AuthService.keychainKey)
    private var refreshTask: Task<Tokens, Error>?

    var isSignedIn: Bool { tokens != nil }

    func exchange(code: String, verifier: String) async throws {
        let json = try await postForm([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": OAuthConfig.redirectURI,
            "client_id": OAuthConfig.clientID,
            "code_verifier": verifier,
        ])
        guard let access = json["access_token"] as? String,
              let refresh = json["refresh_token"] as? String else {
            throw AuthError.tokenExchangeFailed(json["error_description"] as? String ?? "No token returned")
        }
        store(Tokens(accessToken: access, refreshToken: refresh, identityURL: json["id"] as? String))
    }

    /// Refreshes the access token, coalescing concurrent callers.
    func refresh() async throws -> Tokens {
        if let refreshTask { return try await refreshTask.value }
        guard let current = tokens else { throw AuthError.notSignedIn }
        let task = Task<Tokens, Error> {
            let json = try await postForm([
                "grant_type": "refresh_token",
                "client_id": OAuthConfig.clientID,
                "refresh_token": current.refreshToken,
            ])
            guard let access = json["access_token"] as? String else {
                throw AuthError.notSignedIn
            }
            return Tokens(accessToken: access, refreshToken: current.refreshToken, identityURL: current.identityURL)
        }
        refreshTask = task
        defer { refreshTask = nil }
        do {
            let new = try await task.value
            store(new)
            return new
        } catch {
            store(nil)
            throw error
        }
    }

    func signOut() async {
        if let token = tokens?.refreshToken {
            _ = try? await postForm(["token": token], url: OAuthConfig.revokeURL)
        }
        store(nil)
    }

    private func store(_ new: Tokens?) {
        tokens = new
        Keychain.setCodable(new, for: Self.keychainKey)
        #if DEBUG && targetEnvironment(simulator)
        DebugTokenDump.write(new)
        #endif
    }

    private func postForm(_ fields: [String: String], url: URL = OAuthConfig.tokenURL) async throws -> [String: Any] {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var c = URLComponents()
        c.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        req.httpBody = c.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
            .data(using: .utf8)
        let (data, _) = try await URLSession.shared.data(for: req)
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
}

#if DEBUG && targetEnvironment(simulator)
/// Simulator-only: writes tokens to the app container so the API can be probed from a shell during development.
enum DebugTokenDump {
    static func write(_ tokens: Tokens?) {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("debug-tokens.json")
        if let tokens, let data = try? JSONEncoder().encode(tokens) {
            try? data.write(to: url)
        } else {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
#endif
