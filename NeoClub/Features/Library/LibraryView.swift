import SwiftUI

/// Library tab: Bookmarks and Downloads in place, switched with a segmented control (Apple Music style). Opens to
/// Bookmarks, or to Downloads when offline (the only thing that still plays), and jumps to Downloads if the
/// connection drops.
struct LibraryView: View {
    @Environment(BookmarkStore.self) private var bookmarks
    @Environment(DownloadStore.self) private var downloads
    @Environment(NetworkMonitor.self) private var network

    enum Section: String, CaseIterable, Identifiable {
        case bookmarks = "Bookmarks", downloads = "Downloads"
        var id: Self { self }
    }
    @State private var section: Section?

    var body: some View {
        let current = section ?? (network.isOnline ? .bookmarks : .downloads)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Picker("Section", selection: Binding(get: { current }, set: { section = $0 })) {
                    ForEach(Section.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 420)

                switch current {
                case .bookmarks: BookmarksGrid()
                case .downloads: DownloadsGrid()
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .aioBackground("bg_treasure.jpg")
        .navigationTitle("Library")
        .refreshable { await bookmarks.load() }
        .task { if !bookmarks.loaded && network.isOnline { await bookmarks.load() } }
        .onChange(of: network.isOnline) { _, online in
            if !online { section = .downloads }
        }
    }
}

/// Bookmarked episodes as an artwork grid; long-press to remove.
private struct BookmarksGrid: View {
    @Environment(BookmarkStore.self) private var bookmarks

    var body: some View {
        if bookmarks.loaded && bookmarks.items.isEmpty {
            ContentUnavailableView("No Bookmarks", systemImage: "bookmark",
                                   description: Text("Tap the bookmark on any episode to save it here."))
        } else if !bookmarks.loaded {
            if let error = bookmarks.lastError {
                ContentUnavailableView("Couldn't Load Bookmarks", systemImage: "wifi.slash", description: Text(error))
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
            }
        } else {
            AdaptiveGrid {
                ForEach(bookmarks.items) { episode in
                    NavigationLink(value: Route.episode(episode, groupingID: nil)) {
                        EpisodeCard(episode: episode)
                    }
                    .buttonStyle(.plain)
                    .episodeContextMenu(episode) {
                        Button("Remove Bookmark", systemImage: "bookmark.slash", role: .destructive) {
                            bookmarks.toggle(episode)
                        }
                    }
                }
            }
        }
    }
}

/// Downloaded and downloading episodes as an artwork grid. Tapping plays (works offline); long-press to remove.
private struct DownloadsGrid: View {
    @Environment(DownloadStore.self) private var downloads
    @Environment(AudioPlayer.self) private var player

    var body: some View {
        let saved = downloads.items.compactMap { downloads.episode(for: $0.id) }
        if saved.isEmpty && downloads.downloading.isEmpty {
            ContentUnavailableView("No Downloads", systemImage: "arrow.down.circle",
                                   description: Text("Download episodes to listen without a connection."))
        } else {
            VStack(alignment: .leading, spacing: 12) {
                if !saved.isEmpty {
                    Text("\(saved.count) episode\(saved.count == 1 ? "" : "s") · "
                         + ByteCountFormatter.string(fromByteCount: downloads.totalBytes, countStyle: .file))
                        .font(.univers(13, relativeTo: .footnote))
                        .foregroundStyle(.secondary)
                }
                AdaptiveGrid {
                    ForEach(downloads.downloading) { episode in
                        EpisodeCard(episode: episode)
                            .overlay {
                                let fraction = downloads.active[episode.id] ?? 0
                                ProgressView(value: fraction)
                                    .progressViewStyle(.circular)
                                    .controlSize(.large)
                                    .padding(10)
                                    .glassEffect(.regular, in: .circle)
                            }
                            .contextMenu {
                                Button("Cancel Download", systemImage: "xmark.circle", role: .destructive) {
                                    downloads.cancel(episode.id)
                                }
                            }
                    }
                    ForEach(saved) { episode in
                        Button { player.play(episode) } label: { EpisodeCard(episode: episode) }
                            .buttonStyle(.plain)
                            .episodeContextMenu(episode) {
                                Button("Remove Download", systemImage: "trash", role: .destructive) {
                                    downloads.delete(episode.id)
                                }
                            }
                    }
                }
            }
        }
    }
}
