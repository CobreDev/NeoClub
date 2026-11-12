import SwiftUI

/// Library tab, laid out like Apple Music's: shortcut rows, then a grid of what you've played recently
/// (or, offline, of your downloads, since those are what still play).
struct LibraryView: View {
    @Environment(BookmarkStore.self) private var bookmarks
    @Environment(DownloadStore.self) private var downloads
    @Environment(NetworkMonitor.self) private var network
    @Environment(AudioPlayer.self) private var player

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 14)], spacing: 14) {
                    NavigationLink(value: Route.bookmarks) {
                        LibraryShortcut(title: "Bookmarks", systemImage: "bookmark",
                                        count: bookmarks.loaded ? bookmarks.items.count : nil)
                    }
                    NavigationLink(value: Route.downloads) {
                        LibraryShortcut(title: "Downloaded", systemImage: "arrow.down.circle",
                                        count: downloads.items.count)
                    }
                }
                .buttonStyle(.plain)

                if network.isOnline {
                    recentlyPlayed
                } else {
                    downloaded
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .aioBackground("bg_treasure.jpg")
        .navigationTitle("Library")
        .refreshable { await bookmarks.load() }
        .task { if !bookmarks.loaded && network.isOnline { await bookmarks.load() } }
    }

    @ViewBuilder private var recentlyPlayed: some View {
        let episodes = player.history.compactMap(\.episodeStub)
        if !episodes.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Recently Played").font(.universBold(22, relativeTo: .title2))
                LibraryGrid(episodes: episodes)
            }
        }
    }

    @ViewBuilder private var downloaded: some View {
        let episodes = downloads.items.compactMap { downloads.episode(for: $0.id) }
        VStack(alignment: .leading, spacing: 12) {
            Text("Downloaded").font(.universBold(22, relativeTo: .title2))
            if episodes.isEmpty {
                ContentUnavailableView("No Downloads", systemImage: "arrow.down.circle",
                                       description: Text("Download episodes to listen without a connection."))
            } else {
                LibraryGrid(episodes: episodes)
            }
        }
    }
}

/// A capsule shortcut row (Apple Music's Playlists / Artists / Albums rows).
private struct LibraryShortcut: View {
    let title: String
    let systemImage: String
    var count: Int?

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(Color.aioTint)
                .frame(width: 30)
            Text(title).font(.univers(18, relativeTo: .body))
            Spacer()
            if let count, count > 0 {
                Text("\(count)").font(.univers(15, relativeTo: .subheadline)).foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right").font(.subheadline.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 20)
        .frame(height: 54)
        .background(.white.opacity(0.14), in: .capsule)
        .contentShape(.capsule)
    }
}

/// Artwork grid of episodes: 2 columns on a phone-width screen, 3 unfolded in portrait, 4 in landscape.
private struct LibraryGrid: View {
    let episodes: [Episode]

    var body: some View {
        AdaptiveGrid {
            ForEach(episodes) { episode in
                NavigationLink(value: Route.episode(episode, groupingID: nil)) {
                    EpisodeCard(episode: episode)
                }
                .buttonStyle(.plain)
                .episodeContextMenu(episode)
            }
        }
    }
}

/// Full-page Downloaded (from the Library).
struct DownloadsView: View {
    var body: some View {
        List { DownloadsList() }
            .listStyle(.plain)
            .aioBackground("bg_treasure.jpg")
            .navigationTitle("Downloaded")
    }
}
