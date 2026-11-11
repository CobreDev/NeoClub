import SwiftUI

struct DownloadsView: View {
    @Environment(DownloadStore.self) private var downloads
    @Environment(AudioPlayer.self) private var player

    var body: some View {
        List {
            if !downloads.downloading.isEmpty {
                Section("Downloading") {
                    ForEach(downloads.downloading) { DownloadingRow(episode: $0).aioRow() }
                }
            }
            Section(downloads.downloading.isEmpty ? "" : "Downloaded") {
            ForEach(downloads.items) { item in
                Button {
                    if let e = downloads.episode(for: item.id) { player.play(e) }
                } label: {
                    HStack(spacing: 12) {
                        Artwork(url: .aio(item.artwork), cornerRadius: 6).frame(width: 52, height: 52)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).font(.universBold(16, relativeTo: .headline)).lineLimit(2)
                            Text([item.albumName, item.subtitle].compactMap { $0 }.joined(separator: " · "))
                                .font(.univers(13, relativeTo: .subheadline)).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
                .buttonStyle(.plain)
                .aioRow()
            }
            .onDelete { idx in idx.map { downloads.items[$0].id }.forEach(downloads.delete) }
            }
        }
        .overlay {
            if downloads.items.isEmpty && downloads.downloading.isEmpty {
                ContentUnavailableView("No Downloads", systemImage: "arrow.down.circle",
                                       description: Text("Download episodes to listen without a connection."))
            }
        }
        .aioBackground("bg_treasure.jpg")
        .navigationTitle("Downloads")
        .toolbar {
            if !downloads.items.isEmpty {
                Text(ByteCountFormatter.string(fromByteCount: downloads.totalBytes, countStyle: .file))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// A row for an episode that's still downloading: artwork, title, live progress, swipe to cancel.
struct DownloadingRow: View {
    @Environment(DownloadStore.self) private var downloads
    let episode: Episode

    var body: some View {
        let fraction = downloads.active[episode.id] ?? 0
        HStack(spacing: 12) {
            Artwork(url: episode.smallArtworkURL, cornerRadius: 6).frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 6) {
                Text(episode.title).font(.universBold(16, relativeTo: .headline)).lineLimit(1)
                ProgressView(value: fraction).tint(.aioYellow)
                Text(fraction > 0 ? "Downloading… \(Int(fraction * 100))%" : "Waiting to download…")
                    .font(.univers(12, relativeTo: .caption)).foregroundStyle(.secondary)
            }
        }
        .swipeActions {
            Button("Cancel", role: .destructive) { downloads.cancel(episode.id) }
        }
    }
}
