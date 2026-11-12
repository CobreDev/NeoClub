import SwiftUI

/// Bookmarked episodes, as List content (used by the Library and the full Bookmarks page).
struct BookmarksList: View {
    @Environment(BookmarkStore.self) private var bookmarks
    @Environment(AudioPlayer.self) private var player

    var body: some View {
        if bookmarks.loaded && bookmarks.items.isEmpty {
            ContentUnavailableView("No Bookmarks", systemImage: "bookmark",
                                   description: Text("Tap the bookmark on any episode to save it here."))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        } else if !bookmarks.loaded {
            if let error = bookmarks.lastError {
                ContentUnavailableView("Couldn't Load Bookmarks", systemImage: "wifi.slash", description: Text(error))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear).listRowSeparator(.hidden)
            }
        }
        ForEach(bookmarks.items) { episode in
            NavigationLink(value: Route.episode(episode, groupingID: nil)) {
                EpisodeRow(episode: episode) { player.play(episode) }
            }
            .aioRow()
            .episodeContextMenu(episode)
            .swipeActions {
                Button("Remove", systemImage: "bookmark.slash", role: .destructive) { bookmarks.toggle(episode) }
            }
        }
    }
}

/// Full-page Bookmarks (from the Home shelf).
struct BookmarksView: View {
    @Environment(BookmarkStore.self) private var bookmarks

    var body: some View {
        List { BookmarksList() }
            .listStyle(.plain)
            .aioBackground("bg_treasure.jpg")
            .navigationTitle("Bookmarks")
            .refreshable { await bookmarks.load() }
            .task { if !bookmarks.loaded { await bookmarks.load() } }
    }
}
