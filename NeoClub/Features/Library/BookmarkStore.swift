import SwiftUI

/// Bookmarks for the selected profile, synced with the AIO account (same endpoints as the official app).
/// Toggles update the UI immediately and roll back if the server rejects them.
@MainActor
@Observable
final class BookmarkStore {
    static let shared = BookmarkStore()

    private(set) var items: [Episode] = []
    private(set) var loaded = false
    /// Why the last load failed (shown inline in the list).
    var lastError: String?
    /// Why the last add/remove failed (shown as an alert).
    var actionError: String?
    /// Local overrides while the server catches up: episode ID → bookmarked.
    private var overrides: [String: Bool] = [:]

    func isBookmarked(_ episode: Episode) -> Bool {
        overrides[episode.id] ?? episode.isBookmarked ?? items.contains { $0.id == episode.id }
    }

    func load() async {
        // The saved list shows at once (and offline); the fresh one replaces it.
        if items.isEmpty, let saved = AIOService.cachedBookmarks() { items = saved }
        do {
            items = try await AIOService.bookmarks()
            overrides = [:]
            loaded = true
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func reset() {
        items = []
        overrides = [:]
        loaded = false
    }

    func toggle(_ episode: Episode) {
        let target = !isBookmarked(episode)
        overrides[episode.id] = target
        if target {
            if !items.contains(where: { $0.id == episode.id }) { items.insert(episode, at: 0) }
        } else {
            items.removeAll { $0.id == episode.id }
        }
        Task {
            do {
                if target { try await AIOService.addBookmark(episode.id) } else { try await AIOService.removeBookmark(episode.id) }
            } catch {
                // Roll back the optimistic change.
                overrides[episode.id] = !target
                if target { items.removeAll { $0.id == episode.id } } else { items.insert(episode, at: 0) }
                actionError = "Couldn't update bookmark: \(error.localizedDescription)"
            }
        }
    }
}

/// Bookmark toggle used on episode pages and in Now Playing.
struct BookmarkButton: View {
    @Environment(BookmarkStore.self) private var bookmarks
    let episode: Episode
    /// Drawn as a glass circle of this diameter (the side buttons of Apple Music's album header).
    var size: CGFloat?

    var body: some View {
        let on = bookmarks.isBookmarked(episode)
        if let size {
            Button { bookmarks.toggle(episode) } label: {
                Image(systemName: on ? "bookmark.fill" : "bookmark")
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: size, height: size)
                    .foregroundStyle(.white)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .accessibilityLabel(on ? "Remove Bookmark" : "Bookmark")
        } else {
            Button { bookmarks.toggle(episode) } label: {
                Image(systemName: on ? "bookmark.fill" : "bookmark")
                    .font(.title2)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.glass)
            .accessibilityLabel(on ? "Remove Bookmark" : "Bookmark")
        }
    }
}
