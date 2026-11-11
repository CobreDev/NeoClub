import Foundation
import CryptoKit

/// Salesforce Experience Cloud OAuth settings used by the official AIO Club apps.
enum OAuthConfig {
    static let clientID = "3MVG9l2zHsylwlpTFc1ZB3ryOQlpLYIqNo0UV4d0lBRjkbb6TXbw9UNhdcJfom2nnbB.AbNpkRbGoTfruF0gB"
    static let redirectURI = "https://app.adventuresinodyssey.com/callback"
    static let scope = "api web refresh_token"
    static let authorizeURL = URL(string: "https://fotf.my.site.com/aio/services/oauth2/authorize")!
    static let tokenURL = URL(string: "https://fotf.my.site.com/aio/services/oauth2/token")!
    static let revokeURL = URL(string: "https://fotf.my.site.com/aio/services/oauth2/revoke")!
    static let apiBaseURL = URL(string: "https://fotf.my.site.com/aio/services/apexrest/v1")!
}

/// Mirrors the official app's authorize request (S256 challenge, padded base64url like Dart's `base64Url`).
struct PKCE {
    let verifier: String
    let challenge: String
    let state: String

    init() {
        verifier = Self.random(64).base64URLEncoded(padded: false)
        challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded(padded: true)
        state = Self.random(16).base64URLEncoded(padded: false)
    }

    func authorizeURL() -> URL {
        var c = URLComponents(url: OAuthConfig.authorizeURL, resolvingAgainstBaseURL: false)!
        c.queryItems = [
            .init(name: "response_type", value: "code"),
            .init(name: "client_id", value: OAuthConfig.clientID),
            .init(name: "redirect_uri", value: OAuthConfig.redirectURI),
            .init(name: "scope", value: OAuthConfig.scope),
            .init(name: "state", value: state),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
        ]
        return c.url!
    }

    private static func random(_ count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes)
    }
}

extension Data {
    func base64URLEncoded(padded: Bool) -> String {
        let s = base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
        return padded ? s : s.replacingOccurrences(of: "=", with: "")
    }
}

/// Strict application/x-www-form-urlencoded encoding (URLComponents leaves "=", "&" and "+" alone).
func formEncode(_ fields: [String: String]) -> Data {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._*")
    return fields.map { k, v in
        "\(k.addingPercentEncoding(withAllowedCharacters: allowed)!)=\(v.addingPercentEncoding(withAllowedCharacters: allowed)!)"
    }
    .joined(separator: "&")
    .data(using: .utf8)!
}
