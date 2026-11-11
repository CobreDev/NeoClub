import AVFoundation
import Foundation
import SwiftUI

/// Offline episodes. Fetches the same signed HLS stream the player uses (playlist + AAC segments,
/// with the CloudFront cookies), one segment at a time, joins them, and repackages the audio as a
/// seekable .m4a without re-encoding. Apple's out-of-process HLS downloader doesn't send the
/// CloudFront cookies, so the app does the fetching itself, using exactly the requests streaming makes.
@MainActor
@Observable
final class DownloadStore {
    static let shared = DownloadStore()

    struct Item: Codable, Identifiable {
        let id: String
        let fileName: String
        let title: String
        let albumName: String?
        let subtitle: String
        let artwork: String?
        let bytes: Int64
        let downloadedAt: Date
        let episodeJSON: Data
    }

    private(set) var items: [Item] = []
    /// In-flight downloads: episode ID → fraction complete.
    private(set) var active: [String: Double] = [:]
    /// Episodes currently downloading, newest first (for the Library's "Downloading" section).
    private(set) var downloading: [Episode] = []
    var lastError: String?

    private let directory: URL
    private var jobs: [String: Task<Void, Never>] = [:]
    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.httpCookieAcceptPolicy = .never
        c.httpShouldSetCookies = false
        return URLSession(configuration: c)
    }()

    private init() {
        directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var dir = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? dir.setResourceValues(values)
        load()
    }

    func isDownloaded(_ id: String) -> Bool { items.contains { $0.id == id } }

    func localFile(for id: String) -> URL? {
        guard let item = items.first(where: { $0.id == id }) else { return nil }
        let url = directory.appendingPathComponent(item.fileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func episode(for id: String) -> Episode? {
        items.first { $0.id == id }.flatMap { try? JSONDecoder().decode(Episode.self, from: $0.episodeJSON) }
    }

    func download(_ episode: Episode) {
        guard !isDownloaded(episode.id), active[episode.id] == nil else { return }
        active[episode.id] = 0
        downloading.insert(episode, at: 0)
        jobs[episode.id] = Task { await run(episode) }
    }

    func cancel(_ id: String) {
        jobs[id]?.cancel()
    }

    func delete(_ id: String) {
        if let url = localFile(for: id) { try? FileManager.default.removeItem(at: url) }
        items.removeAll { $0.id == id }
        save()
    }

    var totalBytes: Int64 { items.reduce(0) { $0 + $1.bytes } }

    // MARK: Download pipeline

    private func run(_ episode: Episode) async {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("dl-\(episode.id)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: work)
            active[episode.id] = nil
            downloading.removeAll { $0.id == episode.id }
            jobs[episode.id] = nil
        }
        do {
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            // Fresh detail: stream URL and cookies are signed and expire.
            let raw = try await APIClient.shared.raw("GET", "/content/\(episode.id)", query: [
                "player": "true", "recommendations": "false", "tag": "false", "series": "false", "parent": "false",
            ])
            let detail = try JSONDecoder().decode(Episode.self, from: raw)
            guard let master = URL.aio(detail.streamURL) else { throw APIError.decoding("This episode can't be downloaded.") }
            let cookieHeader = HTTPCookie.requestHeaderFields(with: AudioPlayer.cloudFrontCookies(from: detail.signedCookie))

            // 1. Master playlist → highest-bandwidth audio rendition.
            let variant = bestVariant(in: try await fetchText(master, cookies: cookieHeader), relativeTo: master)
            // 2. Rendition playlist → ordered segment URLs.
            let segments = Self.segmentURLs(in: try await fetchText(variant, cookies: cookieHeader), relativeTo: variant)
            guard !segments.isEmpty else { throw APIError.decoding("This episode has no audio to download.") }

            // 3. Fetch segments in order (like playback), strip each one's ID3 timing tag, and append.
            let joined = work.appendingPathComponent("audio.aac")
            FileManager.default.createFile(atPath: joined.path, contents: nil)
            let handle = try FileHandle(forWritingTo: joined)
            for (i, url) in segments.enumerated() {
                try Task.checkCancellation()
                var req = URLRequest(url: url)
                cookieHeader.forEach { req.setValue($1, forHTTPHeaderField: $0) }
                let (data, response) = try await session.data(for: req)
                guard (response as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty else {
                    try? handle.close()
                    throw APIError.http((response as? HTTPURLResponse)?.statusCode ?? 0, "Segment \(i + 1) failed")
                }
                try handle.write(contentsOf: Self.stripID3(data))
                active[episode.id] = Double(i + 1) / Double(segments.count) * 0.95
            }
            try handle.close()

            // 4. Repackage ADTS AAC into a seekable .m4a (passthrough, no re-encode).
            let fileName = "\(episode.id).m4a"
            let dest = directory.appendingPathComponent(fileName)
            try? FileManager.default.removeItem(at: dest)
            try await Self.remux(joined, to: dest)
            active[episode.id] = 1

            let bytes = (try? FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? Int64) ?? 0
            items.insert(Item(id: detail.id, fileName: fileName, title: detail.title, albumName: detail.albumTitle,
                              subtitle: detail.subtitle, artwork: detail.thumbnailMedium ?? detail.thumbnailSmall,
                              bytes: bytes, downloadedAt: Date(), episodeJSON: raw), at: 0)
            save()
            SignInLog.write("download saved: \(segments.count) segments, \(bytes) bytes")
        } catch is CancellationError {
            SignInLog.write("download cancelled")
        } catch {
            lastError = error.localizedDescription
            SignInLog.write("download failed: \(error.localizedDescription)")
        }
    }

    private func fetchText(_ url: URL, cookies: [String: String]) async throws -> String {
        var req = URLRequest(url: url)
        cookies.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        let (data, response) = try await session.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw APIError.http((response as? HTTPURLResponse)?.statusCode ?? 0, "Playlist unavailable")
        }
        return String(decoding: data, as: UTF8.self)
    }

    private func bestVariant(in master: String, relativeTo base: URL) -> URL {
        var best: (bandwidth: Int, uri: String)?
        let lines = master.components(separatedBy: .newlines)
        for (i, line) in lines.enumerated() where line.hasPrefix("#EXT-X-STREAM-INF") {
            let bw = line.range(of: #"(?<!AVERAGE-)BANDWIDTH=(\d+)"#, options: .regularExpression)
                .flatMap { Int(line[$0].split(separator: "=").last ?? "") } ?? 0
            if i + 1 < lines.count, !lines[i + 1].isEmpty, bw > (best?.bandwidth ?? -1) { best = (bw, lines[i + 1]) }
        }
        // A master with no variants is itself the media playlist.
        guard let best, let url = URL(string: best.uri, relativeTo: base)?.absoluteURL else { return base }
        return url
    }

    static func segmentURLs(in playlist: String, relativeTo base: URL) -> [URL] {
        playlist.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .compactMap { URL(string: $0, relativeTo: base)?.absoluteURL }
    }

    /// HLS packed-audio segments start with an ID3v2 timestamp tag; drop it so segments join cleanly.
    static func stripID3(_ data: Data) -> Data {
        guard data.count > 10, data.prefix(3) == Data("ID3".utf8) else { return data }
        let b = [UInt8](data[6..<10])
        let size = Int(b[0]) << 21 | Int(b[1]) << 14 | Int(b[2]) << 7 | Int(b[3])
        let footer = (data[5] & 0x10) != 0 ? 10 : 0
        let end = 10 + size + footer
        return end < data.count ? data.subdata(in: end..<data.count) : data
    }

    static func remux(_ source: URL, to dest: URL) async throws {
        let asset = AVURLAsset(url: source)
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw APIError.decoding("Couldn't package the download.")
        }
        try await export.export(to: dest, as: .m4a)
    }

    private var indexURL: URL { directory.appendingPathComponent("index.json") }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL) else { return }
        items = (try? JSONDecoder().decode([Item].self, from: data)) ?? []
    }

    private func save() {
        try? JSONEncoder().encode(items).write(to: indexURL, options: .atomic)
    }
}
