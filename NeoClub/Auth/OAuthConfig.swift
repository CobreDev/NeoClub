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

struct PKCE {
    let verifier: String
    let challenge: String

    init() {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        verifier = Data(bytes).base64URLEncoded()
        challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded()
    }

    func authorizeURL() -> URL {
        var c = URLComponents(url: OAuthConfig.authorizeURL, resolvingAgainstBaseURL: false)!
        c.queryItems = [
            .init(name: "response_type", value: "code"),
            .init(name: "client_id", value: OAuthConfig.clientID),
            .init(name: "redirect_uri", value: OAuthConfig.redirectURI),
            .init(name: "code_challenge", value: challenge),
            .init(name: "scope", value: OAuthConfig.scope),
        ]
        return c.url!
    }
}

extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
