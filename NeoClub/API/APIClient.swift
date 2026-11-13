import CryptoKit
import Foundation

enum APIError: LocalizedError {
    case http(Int, String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .http(let code, let body): "Server error \(code): \(body.prefix(200))"
        case .decoding(let msg): "Unexpected response: \(msg)"
        }
    }
}

/// Thin client for the AIO apexrest API.
final class APIClient: @unchecked Sendable {
    static let shared = APIClient()

    /// Selected child/viewer profile, sent as X-VIEWER-ID.
    var viewerID: String?
    /// PIN for the selected profile when it has one, sent as X-PIN.
    var viewerPIN: String?

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        return URLSession(configuration: config)
    }()

    let decoder: JSONDecoder = JSONDecoder()

    func get<T: Decodable>(_ path: String, query: [String: String?] = [:], as type: T.Type = T.self) async throws -> T {
        try await send("GET", path, query: query, body: Optional<String>.none)
    }

    func post<T: Decodable, B: Encodable>(_ path: String, body: B, as type: T.Type = T.self) async throws -> T {
        try await send("POST", path, body: body)
    }

    func put<T: Decodable, B: Encodable>(_ path: String, body: B, as type: T.Type = T.self) async throws -> T {
        try await send("PUT", path, body: body)
    }

    func send<T: Decodable, B: Encodable>(_ method: String, _ path: String, query: [String: String?] = [:], body: B?) async throws -> T {
        let bodyData = try body.map { try JSONEncoder().encode($0) }
        let data = try await raw(method, path, query: query, body: bodyData)
        // Reads (never progress writes) are kept on disk so screens can show the last copy instantly or offline.
        if method != "PUT" { ResponseCache.write(data, key: cacheKey(method, path, query: query, body: bodyData)) }
        if T.self == Data.self { return data as! T }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding("\(path): \(error)")
        }
    }

    /// The last saved response for this request (for this profile), and how old it is.
    func cached<T: Decodable>(_ method: String, _ path: String, query: [String: String?] = [:], body: (some Encodable)? = Optional<String>.none,
                              as type: T.Type = T.self) -> (value: T, age: TimeInterval)? {
        let bodyData = body.flatMap { try? JSONEncoder().encode($0) }
        guard let (data, age) = ResponseCache.read(key: cacheKey(method, path, query: query, body: bodyData)),
              let value = try? decoder.decode(T.self, from: data) else { return nil }
        return (value, age)
    }

    private func cacheKey(_ method: String, _ path: String, query: [String: String?], body: Data?) -> String {
        let q = query.compactMap { k, v in v.map { "\(k)=\($0)" } }.sorted().joined(separator: "&")
        let raw = "\(viewerID ?? "-")|\(method)|\(path)?\(q)|" + (body.map { String(decoding: $0, as: UTF8.self) } ?? "")
        return SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Performs a request, refreshing the token once on 401.
    func raw(_ method: String, _ path: String, query: [String: String?] = [:], body: Data? = nil) async throws -> Data {
        var tokens = await AuthService.shared.tokens
        guard tokens != nil else { throw AuthError.notSignedIn }
        for attempt in 0..<2 {
            let req = makeRequest(method, path, query: query, body: body, token: tokens!.accessToken)
            let (data, response) = try await session.data(for: req)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 401 && attempt == 0 {
                tokens = try await AuthService.shared.refresh()
                continue
            }
            guard (200..<300).contains(status) else {
                throw APIError.http(status, String(decoding: data, as: UTF8.self))
            }
            return data
        }
        throw APIError.http(401, "Unauthorized")
    }

    private func makeRequest(_ method: String, _ path: String, query: [String: String?], body: Data?, token: String) -> URLRequest {
        var c = URLComponents(url: OAuthConfig.apiBaseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        let items = query.compactMap { k, v in v.map { URLQueryItem(name: k, value: $0) } }
        if !items.isEmpty { c.queryItems = items.sorted { $0.name < $1.name } }
        var req = URLRequest(url: c.url!)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("Adventures In Odyssey", forHTTPHeaderField: "X-Experience-Name")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let viewerID { req.setValue(viewerID, forHTTPHeaderField: "X-VIEWER-ID") }
        if let viewerPIN { req.setValue(viewerPIN, forHTTPHeaderField: "X-PIN") }
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return req
    }
}

/// Last successful response per request, in Caches (iOS may clear it; it's only a head start).
enum ResponseCache {
    private static let dir: URL = {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("API", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    static func write(_ data: Data, key: String) {
        try? data.write(to: dir.appendingPathComponent(key), options: .atomic)
    }

    static func read(key: String) -> (Data, TimeInterval)? {
        let url = dir.appendingPathComponent(key)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        return (data, Date().timeIntervalSince(modified))
    }

    /// Signing out or switching profiles shouldn't show the previous profile's lists.
    static func clear() {
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
}
