import AVFoundation
import Foundation
import SwiftUI

/// Offline episodes. Saves the episode's signed `download_url` file (AAC in MP4) exactly the way the official app
/// does: one plain GET with the same headers its HTTP client sends (traced from the official app on 2026-11-11),
/// no cookies, no API token.
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
        defer {
            active[episode.id] = nil
            downloading.removeAll { $0.id == episode.id }
            jobs[episode.id] = nil
        }
        do {
            // Fresh detail: stream URL and cookies are signed and expire.
            let raw = try await APIClient.shared.raw("GET", "/content/\(episode.id)", query: [
                "player": "true", "recommendations": "false", "tag": "false", "series": "false", "parent": "false",
            ])
            let detail = try JSONDecoder().decode(Episode.self, from: raw)
            guard let remote = URL.aio(detail.downloadURL) else { throw APIError.decoding("This episode can't be downloaded.") }
            // Episodes are AAC in MP4, some songs are MP3: keep the file's own type so AVFoundation reads it right.
            let ext = remote.pathExtension.isEmpty ? "m4a" : remote.pathExtension.lowercased()
            let fileName = "\(episode.id).\(ext)"
            let dest = directory.appendingPathComponent(fileName)
            try? FileManager.default.removeItem(at: dest)

            let id = episode.id
            try await Self.fetchFile(from: remote, to: dest) { fraction in
                Task { @MainActor [weak self] in self?.active[id] = fraction }
            }
            try Task.checkCancellation()
            active[episode.id] = 1

            let bytes = (try? FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? Int64) ?? 0
            items.insert(Item(id: detail.id, fileName: fileName, title: detail.title, albumName: detail.albumTitle,
                              subtitle: detail.subtitle, artwork: detail.thumbnailMedium ?? detail.thumbnailSmall,
                              bytes: bytes, downloadedAt: Date(), episodeJSON: raw), at: 0)
            save()
            SignInLog.write("download saved: \(bytes) bytes")
        } catch is CancellationError {
            SignInLog.write("download cancelled")
        } catch {
            lastError = error.localizedDescription
            SignInLog.write("download failed: \(error.localizedDescription)")
        }
    }

    /// The official app's download request headers (its Dart HTTP client's defaults).
    nonisolated static let officialHeaders = ["User-Agent": "Dart/3.5 (dart:io)", "Accept-Encoding": "gzip"]

    nonisolated static func fetchFile(from remote: URL, to dest: URL,
                                      progress: @escaping @Sendable (Double) -> Void) async throws {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.httpAdditionalHeaders = officialHeaders
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }
        var request = URLRequest(url: remote)
        officialHeaders.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        let (temp, response) = try await session.download(for: request, delegate: DownloadProgress(progress))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            try? FileManager.default.removeItem(at: temp)
            SignInLog.write("download refused: HTTP \(status)")
            throw APIError.decoding("The server refused the download (HTTP \(status)).")
        }
        try FileManager.default.moveItem(at: temp, to: dest)
    }

    private final class DownloadProgress: NSObject, URLSessionDownloadDelegate, Sendable {
        let report: @Sendable (Double) -> Void
        init(_ report: @escaping @Sendable (Double) -> Void) { self.report = report }
        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                        totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
            guard totalBytesExpectedToWrite > 0 else { return }
            report(min(0.99, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
        }
        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
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
