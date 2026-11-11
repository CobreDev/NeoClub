import Foundation
import SwiftUI

/// Offline episodes: the signed AAC download for each episode, plus its metadata, in Application Support.
@MainActor
@Observable
final class DownloadStore: NSObject {
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
    var lastError: String?

    private let directory: URL
    private var session: URLSession!
    private var pending: [Int: (episode: Episode, raw: Data)] = [:]

    override private init() {
        directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Downloads", isDirectory: true)
        super.init()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var dir = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? dir.setResourceValues(values)
        session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
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
        Task {
            do {
                // Fresh detail: download URLs are signed and expire.
                let raw = try await APIClient.shared.raw("GET", "/content/\(episode.id)", query: [
                    "player": "true", "recommendations": "false", "tag": "false", "series": "false", "parent": "false",
                ])
                let detail = try JSONDecoder().decode(Episode.self, from: raw)
                guard let url = URL.aio(detail.downloadURL) else { throw APIError.decoding("No download available for this episode.") }
                let task = session.downloadTask(with: url)
                pending[task.taskIdentifier] = (detail, raw)
                task.resume()
            } catch {
                active[episode.id] = nil
                lastError = error.localizedDescription
            }
        }
    }

    func delete(_ id: String) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(item.fileName))
        items.removeAll { $0.id == id }
        save()
    }

    var totalBytes: Int64 { items.reduce(0) { $0 + $1.bytes } }

    private func finish(task: Int, at location: URL) {
        guard let (episode, raw) = pending.removeValue(forKey: task) else { return }
        let fileName = "\(episode.id).m4a"
        let dest = directory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.moveItem(at: location, to: dest)
            let bytes = (try? FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? Int64) ?? 0
            items.insert(Item(id: episode.id, fileName: fileName, title: episode.title, albumName: episode.albumName,
                              subtitle: episode.subtitle, artwork: episode.thumbnailMedium ?? episode.thumbnailSmall,
                              bytes: bytes, downloadedAt: Date(), episodeJSON: raw), at: 0)
            save()
        } catch {
            lastError = error.localizedDescription
        }
        active[episode.id] = nil
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

extension DownloadStore: URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // The temp file is deleted when this returns, so move it synchronously first.
        let keep = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.moveItem(at: location, to: keep)
        let id = downloadTask.taskIdentifier
        MainActor.assumeIsolated { finish(task: id, at: keep) }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64,
                                totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let id = downloadTask.taskIdentifier
        let fraction = totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0
        MainActor.assumeIsolated {
            if let episodeID = pending[id]?.episode.id { active[episodeID] = fraction }
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        let id = task.taskIdentifier
        MainActor.assumeIsolated {
            if let entry = pending.removeValue(forKey: id) { active[entry.episode.id] = nil }
            lastError = error.localizedDescription
        }
    }
}
