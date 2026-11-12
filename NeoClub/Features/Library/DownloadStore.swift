import AVFoundation
import Foundation
import SwiftUI

/// Offline episodes. Saves the episode's signed `download_url` file (AAC in MP4) exactly the way the official app
/// does: one plain GET with the same headers its HTTP client sends (traced from the official app on 2026-11-11),
/// no cookies, no API token, in a background session so it carries on while the app isn't open.
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

    fileprivate let directory: URL
    private init() {
        directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var dir = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? dir.setResourceValues(values)
        load()
        reattach()
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
        Task { await start(episode) }
    }

    func cancel(_ id: String) {
        Task {
            foreground[id]?.cancel()
            if let bg = readyDownloader {
                for task in await bg.session.allTasks where task.taskDescription == id { task.cancel() }
            }
            finish(id)
        }
    }

    func delete(_ id: String) {
        if let url = localFile(for: id) { try? FileManager.default.removeItem(at: url) }
        items.removeAll { $0.id == id }
        save()
    }

    var totalBytes: Int64 { items.reduce(0) { $0 + $1.bytes } }

    // MARK: Download pipeline
    //
    // Files come down in a background URLSession, so iOS keeps downloading while NeoClub is suspended or closed and
    // relaunches it to hand over finished files. The request is still exactly the official app's: one GET of the
    // signed download URL with its HTTP client's headers, no cookies, no API token.

    /// Created off the main thread: making a background session waits on a system service (synchronously), which
    /// must never hold up launch.
    @ObservationIgnored private lazy var downloader: Task<BackgroundDownloader, Never> = {
        let directory = directory
        let store = self
        return Task.detached(priority: .utility) {
            let made = BackgroundDownloader(store: store, directory: directory)
            await MainActor.run { store.readyDownloader = made }
            return made
        }
    }()
    @ObservationIgnored private var readyDownloader: BackgroundDownloader?
    private var background: BackgroundDownloader { get async { await downloader.value } }

    /// The background session if the system has set it up within `timeout` seconds. (In the simulator it can wait
    /// forever; then downloads fall back to an in-app download, as before.)
    private func backgroundIfReady(timeout: Double = 5) async -> BackgroundDownloader? {
        _ = downloader
        let deadline = Date().addingTimeInterval(timeout)
        while readyDownloader == nil, Date() < deadline { try? await Task.sleep(for: .milliseconds(100)) }
        return readyDownloader
    }

    /// Episode details for downloads in progress, so a finished file can be registered even after a relaunch.
    private var pendingDirectory: URL { directory.appendingPathComponent("pending", isDirectory: true) }

    private func start(_ episode: Episode) async {
        do {
            // Fresh detail: the download URL is signed and expires.
            let raw = try await APIClient.shared.raw("GET", "/content/\(episode.id)", query: [
                "player": "true", "recommendations": "false", "tag": "false", "series": "false", "parent": "false",
            ])
            let detail = try JSONDecoder().decode(Episode.self, from: raw)
            guard let remote = URL.aio(detail.downloadURL) else { throw APIError.decoding("This episode can't be downloaded.") }
            guard active[episode.id] != nil else { return }  // cancelled meanwhile
            try FileManager.default.createDirectory(at: pendingDirectory, withIntermediateDirectories: true)
            try raw.write(to: pendingDirectory.appendingPathComponent("\(episode.id).json"), options: .atomic)
            var request = URLRequest(url: remote)
            Self.officialHeaders.forEach { request.setValue($1, forHTTPHeaderField: $0) }
            if let bg = await backgroundIfReady() {
                let task = bg.session.downloadTask(with: request)
                task.taskDescription = episode.id
                task.resume()
            } else {
                SignInLog.write("background downloads unavailable; downloading in the app")
                foreground[episode.id] = Task { await downloadInApp(episode.id, request: request) }
            }
        } catch {
            lastError = error.localizedDescription
            SignInLog.write("download failed: \(error.localizedDescription)")
            finish(episode.id)
        }
    }

    /// Called by the session (on the main actor) when a file has been moved into place.
    fileprivate func completed(id: String, fileName: String) {
        let pending = pendingDirectory.appendingPathComponent("\(id).json")
        guard let raw = try? Data(contentsOf: pending), let detail = try? JSONDecoder().decode(Episode.self, from: raw) else {
            finish(id); return
        }
        let dest = directory.appendingPathComponent(fileName)
        let bytes = (try? FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? Int64) ?? 0
        items.removeAll { $0.id == id }
        items.insert(Item(id: detail.id, fileName: fileName, title: detail.title, albumName: detail.albumTitle,
                          subtitle: detail.subtitle, artwork: detail.thumbnailMedium ?? detail.thumbnailSmall,
                          bytes: bytes, downloadedAt: Date(), episodeJSON: raw), at: 0)
        save()
        try? FileManager.default.removeItem(at: pending)
        SignInLog.write("download saved: \(bytes) bytes")
        finish(id)
    }

    fileprivate func failed(id: String, message: String?) {
        if let message {
            lastError = message
            SignInLog.write("download failed: \(message)")
        }
        try? FileManager.default.removeItem(at: pendingDirectory.appendingPathComponent("\(id).json"))
        finish(id)
    }

    fileprivate func progressed(id: String, fraction: Double) {
        if active[id] != nil { active[id] = fraction }
    }

    private func finish(_ id: String) {
        active[id] = nil
        downloading.removeAll { $0.id == id }
    }

    @ObservationIgnored private var foreground: [String: Task<Void, Never>] = [:]

    /// Fallback when the background session isn't available: the same request in an in-app session (stops if the
    /// app is suspended).
    private func downloadInApp(_ id: String, request: URLRequest) async {
        defer { foreground[id] = nil }
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.httpAdditionalHeaders = Self.officialHeaders
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }
        do {
            let (temp, response) = try await session.download(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else {
                try? FileManager.default.removeItem(at: temp)
                SignInLog.write("download refused: HTTP \(status)")
                failed(id: id, message: "The server refused the download (HTTP \(status)).")
                return
            }
            let ext = request.url?.pathExtension.lowercased() ?? ""
            let fileName = "\(id).\(ext.isEmpty ? "m4a" : ext)"
            let dest = directory.appendingPathComponent(fileName)
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: temp, to: dest)
            completed(id: id, fileName: fileName)
        } catch {
            failed(id: id, message: (error as? URLError)?.code == .cancelled ? nil : error.localizedDescription)
        }
    }

    /// After a relaunch: show downloads iOS is still running for us.
    private func reattach() {
        Task {
            guard let bg = await backgroundIfReady(timeout: 10) else { return }
            for task in await bg.session.allTasks {
                guard let id = task.taskDescription, active[id] == nil,
                      let raw = try? Data(contentsOf: pendingDirectory.appendingPathComponent("\(id).json")),
                      let episode = try? JSONDecoder().decode(Episode.self, from: raw) else { continue }
                active[id] = task.countOfBytesExpectedToReceive > 0
                    ? Double(task.countOfBytesReceived) / Double(task.countOfBytesExpectedToReceive) : 0
                downloading.append(episode)
            }
        }
    }

    /// iOS relaunched the app for finished background downloads; call `done` once their events are handled.
    func handleBackgroundEvents(_ done: @escaping () -> Void) {
        Task {
            let downloader = await background
            downloader.eventsDone = done
        }
        _ = downloader
    }

    /// The official app's download request headers (its Dart HTTP client's defaults).
    nonisolated static let officialHeaders = ["User-Agent": "Dart/3.5 (dart:io)", "Accept-Encoding": "gzip"]

    /// Owns the background session and receives its callbacks (on a background queue), moving finished files into
    /// place right away (iOS deletes the temporary file when the callback returns).
    fileprivate final class BackgroundDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
        static let identifier = "com.cooperhull.neoclub.downloads"
        weak var store: DownloadStore?
        let directory: URL
        var eventsDone: (() -> Void)?

        private(set) lazy var session: URLSession = {
            let config = URLSessionConfiguration.background(withIdentifier: Self.identifier)
            config.httpCookieStorage = nil
            config.httpShouldSetCookies = false
            config.httpCookieAcceptPolicy = .never
            config.urlCache = nil
            config.httpAdditionalHeaders = DownloadStore.officialHeaders
            config.sessionSendsLaunchEvents = true
            config.isDiscretionary = false
            return URLSession(configuration: config, delegate: self, delegateQueue: nil)
        }()

        init(store: DownloadStore, directory: URL) {
            self.store = store
            self.directory = directory
            super.init()
            _ = session
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                        totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
            guard let id = downloadTask.taskDescription, totalBytesExpectedToWrite > 0 else { return }
            let fraction = min(0.99, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
            Task { @MainActor [weak store] in store?.progressed(id: id, fraction: fraction) }
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
            guard let id = downloadTask.taskDescription else { return }
            let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else {
                SignInLog.write("download refused: HTTP \(status)")
                Task { @MainActor [weak store] in store?.failed(id: id, message: "The server refused the download (HTTP \(status)).") }
                return
            }
            // Episodes are AAC in MP4, some songs are MP3: keep the file's own type so AVFoundation reads it right.
            let remoteExt = downloadTask.originalRequest?.url?.pathExtension.lowercased() ?? ""
            let ext = remoteExt.isEmpty ? "m4a" : remoteExt
            let fileName = "\(id).\(ext)"
            let dest = directory.appendingPathComponent(fileName)
            try? FileManager.default.removeItem(at: dest)
            do {
                try FileManager.default.moveItem(at: location, to: dest)
                Task { @MainActor [weak store] in store?.completed(id: id, fileName: fileName) }
            } catch {
                Task { @MainActor [weak store] in store?.failed(id: id, message: error.localizedDescription) }
            }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            guard let error, let id = task.taskDescription else { return }
            let cancelled = (error as? URLError)?.code == .cancelled
            Task { @MainActor [weak store] in store?.failed(id: id, message: cancelled ? nil : error.localizedDescription) }
        }

        func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
            DispatchQueue.main.async { [self] in
                eventsDone?()
                eventsDone = nil
            }
        }
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
