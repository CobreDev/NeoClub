import AVFoundation
import Foundation
import SwiftUI

/// Offline episodes. Like the official app, saves the episode's signed `download_url` file (AAC in MP4).
/// The file is read through AVFoundation, the same media stack that streams playback, and written
/// to disk with a passthrough export (no re-encoding).
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
            let fileName = "\(episode.id).m4a"
            let dest = directory.appendingPathComponent(fileName)
            try? FileManager.default.removeItem(at: dest)

            let id = episode.id
            try await Self.copyAudio(from: AVURLAsset(url: remote), to: dest) { fraction in
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

    /// Reads the remote file's AAC samples through AVFoundation and writes them to a local .m4a unchanged
    /// (passthrough). Export sessions can't read remote files, but AVAssetReader can.
    nonisolated static func copyAudio(from asset: AVURLAsset, to dest: URL,
                                      progress: @escaping @Sendable (Double) -> Void) async throws {
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw APIError.decoding("This episode has no audio to download.")
        }
        let duration = try await asset.load(.duration).seconds
        let format = try await track.load(.formatDescriptions).first

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        output.alwaysCopiesSampleData = false
        reader.add(output)

        let writer = try AVAssetWriter(outputURL: dest, fileType: .m4a)
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: format)
        input.expectsMediaDataInRealTime = false
        writer.add(input)

        guard reader.startReading(), writer.startWriting() else {
            throw reader.error ?? writer.error ?? APIError.decoding("Couldn't start the download.")
        }
        writer.startSession(atSourceTime: .zero)

        var lastReported = 0.0
        while let sample = output.copyNextSampleBuffer() {
            if Task.isCancelled {
                reader.cancelReading()
                writer.cancelWriting()
                try? FileManager.default.removeItem(at: dest)
                throw CancellationError()
            }
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(10)) }
            input.append(sample)
            let t = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            if duration > 0, t - lastReported > 5 {
                lastReported = t
                progress(min(0.99, t / duration))
            }
        }
        input.markAsFinished()
        await writer.finishWriting()
        if reader.status == .failed || writer.status != .completed {
            try? FileManager.default.removeItem(at: dest)
            throw reader.error ?? writer.error ?? APIError.decoding("The download didn't finish.")
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
