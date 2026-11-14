import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var app
    @Environment(AudioPlayer.self) private var player
    @Environment(BookmarkStore.self) private var bookmarks
    @State private var nextUp = NextUpStore.shared
    @State private var home: HomeResponse?
    @State private var error: String?
    @State private var showAccount = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var loadedAt: Date?

    private var shelvesToShow: [Grouping]? { home?.playlists }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                #if SCREENSHOT_DEMO
                DemoHome()
                #else
                OfflineBanner()
                if let carousel = home?.carousel, !carousel.isEmpty {
                    CarouselView(items: carousel)
                }
                if let shelves = shelvesToShow {
                    // Offline banner and carousel, then Next Up, Continue Listening, the podcast shelves, Bookmarks and
                    // whatever else the server sends (in its order).
                    NextUpShelf(store: nextUp)
                    if shelves.contains(where: { $0.isContinue && $0.contentList.contains { !$0.isBonus } }) {
                        ForEach(shelves.filter(\.isContinue)) { Shelf(shelf: $0) }
                    } else if !nextUp.inProgress.isEmpty {
                        // The server's shelf is missing or empty: built here from what's started and not finished.
                        Shelf(shelf: Grouping(name: "Continue where you left off", contentList: nextUp.inProgress))
                    }
                    ForEach(shelves.filter(\.isPodcast)) { Shelf(shelf: $0) }
                    BookmarksShelf()
                    ForEach(shelves.filter { !$0.isContinue && !$0.isPodcast }) { Shelf(shelf: $0) }
                } else if let error {
                    ErrorView(message: error) { await load() }
                } else {
                    LoadingView()
                }
                #endif
            }
            .padding(.bottom, 24)
        }
        .aioBackground("bg_town.jpg")
        .navigationTitle("Home")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAccount = true } label: {
                    if let profile = app.profile {
                        ProfileBadge(profile: profile, size: 36, showsName: false)
                            .padding(4)
                            .glassEffect(.regular.interactive(), in: .circle)
                    }
                }
                .buttonStyle(.plain)
                .contextMenu { DebugMenu() }
                .accessibilityLabel("Account")
            }
            // Drop the toolbar's shared capsule so the button is a circle matching the avatar.
            .sharedBackgroundVisibility(.hidden)
        }
        .sheet(isPresented: $showAccount) { AccountView() }
        .refreshable { await load(force: true) }
        .task { if home == nil { await load() } }
        // Coming back to the app after a while: the saved Home from before is stale (a shelf like Continue Listening
        // may have appeared since), so it's fetched again rather than waiting for a pull to refresh.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, let loadedAt, -loadedAt.timeIntervalSinceNow > 120 { Task { await load() } }
        }
    }

    /// `force` (pull to refresh) also refetches the album catalog behind Next Up.
    private func load(force: Bool = false) async {
        // The last copy saved on this device shows at once; the fresh one replaces it when it arrives.
        if home == nil { home = AIOService.cachedHome() }
        async let marks: Void = bookmarks.load()
        do {
            home = try await AIOService.home()
            loadedAt = Date()
            error = nil
            let continuing = home?.playlists?.first { $0.name?.hasPrefix("Continue where you left off") == true }
            await nextUp.refresh(continuing: continuing?.contentList ?? [], history: player.history.map { ($0.id, $0.playedAt) },
                                 force: force) {
                player.progress(for: $0)?.isComplete ?? false
            }
        } catch {
            // Keep showing the saved copy when offline; only show the error when there's nothing to show.
            self.error = home == nil ? error.localizedDescription : nil
        }
        await marks
    }

}

/// A horizontal shelf of episodes, titled by its album/collection, linking to the full grouping.
private struct Shelf: View {
    @Environment(AudioPlayer.self) private var player
    let shelf: Grouping

    var body: some View {
        if !(isContinue && episodes.isEmpty) { content }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let gid = shelf.groupingID {
                NavigationLink(value: Route.grouping(id: gid, preview: shelf)) {
                    HStack(spacing: 4) {
                        Text(displayTitle)
                            .font(.universBold(22, relativeTo: .title2))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Image(systemName: "chevron.right").font(.headline).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 20)
                }
                .buttonStyle(.plain)
                .groupingContextMenu(id: gid, grouping: shelf)
            } else {
                ShelfHeader(title: displayTitle)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(episodes) { episode in
                        NavigationLink(value: Route.episode(episode, groupingID: shelf.groupingID)) {
                            EpisodeCard(episode: episode)
                                .shelfItem(large: isContinue)
                        }
                        .buttonStyle(.plain)
                        .episodeContextMenu(episode, queue: queue(after: episode), groupingID: shelf.groupingID)
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, 20)
            }
            .scrollTargetBehavior(.viewAligned)
        }
    }

    /// Continue Listening leaves out bonus content.
    private var episodes: [Episode] { isContinue ? shelf.contentList.filter { !$0.isBonus } : shelf.contentList }

    private var isContinue: Bool { shelf.isContinue }

    private var displayTitle: String {
        isContinue ? "Continue Listening" : shelf.title
    }

    private func queue(after episode: Episode) -> [Episode] {
        guard !isContinue, let i = shelf.contentList.firstIndex(of: episode) else { return [] }
        return Array(shelf.contentList.dropFirst(i + 1))
    }
}

/// Large featured cards, like Apple Music's top-of-Home banners.
private struct CarouselView: View {
    let items: [CarouselItem]
    @State private var webPage: IdentifiableURL?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 12) {
                ForEach(items) { item in
                    let card = Color.clear
                        .aspectRatio(16 / 7, contentMode: .fit)
                        .overlay {
                            CachedImage(url: .aio(item.imageUrl)) {
                                LinearGradient(colors: [.aioOcean, .aioNavy], startPoint: .top, endPoint: .bottom)
                            }
                        }
                        .clipShape(.rect(cornerRadius: 16))
                        .containerRelativeFrame(.horizontal) { w, _ in
                            // Two banners side by side on wide screens (iPhone Duo inner screen, iPad).
                            w > 700 ? (w - 52) / 2 : w - 40
                        }

                    if let route = CarouselView.route(for: item.hyperlink) {
                        NavigationLink(value: route) { card }.buttonStyle(.plain)
                    } else if let url = CarouselView.webURL(for: item.hyperlink) {
                        // Badges, contests and other club pages that only exist on the website.
                        Button { webPage = IdentifiableURL(url: url) } label: { card }.buttonStyle(.plain)
                    } else {
                        card
                    }
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, 20)
        }
        .scrollTargetBehavior(.viewAligned)
        .sheet(item: $webPage) { SafariView(url: $0.url).ignoresSafeArea() }
    }

    static func webURL(for link: String?) -> URL? {
        guard let link, !link.isEmpty else { return nil }
        if link.hasPrefix("http") { return URL(string: link) }
        return URL(string: "https://app.adventuresinodyssey.com" + (link.hasPrefix("/") ? link : "/" + link))
    }

    /// Maps AIO web routes (/contentGroup/{id}, /content/{id}, /contentGroup/{g}/content/{c}) to app routes.
    static func route(for link: String?) -> Route? {
        guard let link, let comps = URLComponents(string: link) else { return nil }
        let parts = comps.path.split(separator: "/").map(String.init)
        if parts.count >= 4, parts[0] == "contentGroup", parts[2] == "content" {
            return .episode(placeholder(parts[3]), groupingID: parts[1])
        }
        if parts.count >= 2, parts[0] == "contentGroup" { return .grouping(id: parts[1], preview: nil) }
        if parts.count >= 2, parts[0] == "content" {
            let gid = comps.queryItems?.first { $0.name == "content_grouping_id" }?.value
            return .episode(placeholder(parts[1]), groupingID: gid)
        }
        return nil
    }

    private static func placeholder(_ id: String) -> Episode {
        // Minimal stub; EpisodeView fetches the full detail.
        try! JSONDecoder().decode(Episode.self, from: Data(#"{"id":"\#(id)"}"#.utf8))
    }
}

/// Horizontal shelf of the profile's bookmarked episodes, linking to the full Bookmarks page.
private struct BookmarksShelf: View {
    @Environment(BookmarkStore.self) private var bookmarks

    var body: some View {
        if !bookmarks.items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                NavigationLink(value: Route.bookmarks) {
                    HStack(spacing: 4) {
                        Text("Bookmarks").font(.universBold(22, relativeTo: .title2))
                        Image(systemName: "chevron.right").font(.headline).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 20)
                }
                .buttonStyle(.plain)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(bookmarks.items) { episode in
                            NavigationLink(value: Route.episode(episode, groupingID: nil)) {
                                EpisodeCard(episode: episode)
                                    .shelfItem()
                            }
                            .buttonStyle(.plain)
                            .episodeContextMenu(episode)
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, 20)
                }
                .scrollTargetBehavior(.viewAligned)
            }
        }
    }
}

/// "Next Up": for each episode you're in the middle of or played recently, the next episode in broadcast order
/// (episode number, across albums, skipping bonus tracks) that you haven't finished or started.
///
/// Progress comes from the album list (which carries this profile's real progress; the track list inside episode
/// details doesn't) plus episodes finished in this app on this device.
@MainActor
@Observable
final class NextUpStore {
    static let shared = NextUpStore()
    private(set) var episodes: [Episode] = []
    /// Started and not finished, newest first (from the album lists' progress and this app's history): Continue
    /// Listening's stand-in when the server's shelf is missing.
    private(set) var inProgress: [Episode] = []
    /// Every numbered episode in every album, in broadcast order. Fetched at most once an hour (the saved copy on
    /// this device is used in between, and shown instantly at launch while a stale one refreshes).
    private var catalog: [Episode] = []
    private var catalogFresh = false
    private var lastSeeds: [String] = []
    static let catalogMaxAge: TimeInterval = 3600

    func refresh(continuing: [Episode], history: [(id: String, at: Date)], force: Bool = false,
                 isDone: (Episode) -> Bool) async {
        if force { catalogFresh = false }
        if catalog.isEmpty, let saved = Self.savedCatalog() {
            catalog = saved.episodes
            catalogFresh = saved.age < Self.catalogMaxAge
            compute(continuing: continuing, history: history, isDone: isDone)
        }
        if !catalogFresh {
            let fresh = await Self.loadCatalog()
            if !fresh.isEmpty { catalog = fresh; catalogFresh = true }
        }
        compute(continuing: continuing, history: history, isDone: isDone)
    }

    private func compute(continuing: [Episode], history: [(id: String, at: Date)], isDone: (Episode) -> Bool) {
        guard !catalog.isEmpty else { return }
        // The most recent listens, from the account (album progress timestamps) and from this app (its history),
        // newest first.
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var recent: [(id: String, at: Date)] = history.prefix(10).map { $0 }
        for e in catalog {
            if let s = e.progress?.activityAt, let d = iso.date(from: s) ?? ISO8601DateFormatter().date(from: s) {
                recent.append((e.id, d))
            }
        }
        recent.sort { $0.at > $1.at }
        var seeds: [String] = []
        for r in recent where !seeds.contains(r.id) {
            seeds.append(r.id)
            if seeds.count == 6 { break }
        }
        lastSeeds = seeds

        let heard = Dictionary(history.map { ($0.id, $0.at) }, uniquingKeysWith: max)
        inProgress = catalog
            .compactMap { e -> (Episode, Date)? in
                guard !e.isBonus, !isDone(e) else { return nil }
                let account = e.progress?.isInProgress == true
                    ? e.progress?.activityAt.flatMap { iso.date(from: $0) ?? ISO8601DateFormatter().date(from: $0) } : nil
                guard let at = [account, heard[e.id]].compactMap({ $0 }).max() else { return nil }
                return (e, at)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(10).map(\.0)

        episodes = Self.nextEpisodes(catalog: catalog, seeds: seeds, inProgress: Set(continuing.map(\.id)), isDone: isDone)
    }

    /// For each recently heard episode (newest first), the first later episode in broadcast order that isn't
    /// finished, started, or in Continue Listening; no duplicates.
    static func nextEpisodes(catalog: [Episode], seeds: [String], inProgress: Set<String>,
                             isDone: (Episode) -> Bool) -> [Episode] {
        var next: [Episode] = []
        for seed in seeds {
            guard let i = catalog.firstIndex(where: { $0.id == seed }) else { continue }
            let candidate = catalog[(i + 1)...].first { e in
                !inProgress.contains(e.id) && !isDone(e) && !(e.progress?.isInProgress ?? false)
            }
            if let candidate, !next.contains(where: { $0.id == candidate.id }) { next.append(candidate) }
        }
        return next
    }

    /// All album pages (the same requests the Albums grid makes), flattened into broadcast order.
    private static func loadCatalog() async -> [Episode] {
        var all: [Episode] = []
        var page = 1, pages = 1
        repeat {
            guard let r = try? await AIOService.groupings(type: "Album", page: page, pageSize: 25) else { break }
            for g in r.contentGroupings ?? [] { all += g.contentList }
            pages = r.metadata?.totalPageCount ?? page
            page += 1
        } while page <= pages && page <= 10
        return ordered(all)
    }

    /// The catalog from the album pages saved on this device, if they're all there, with the oldest page's age.
    private static func savedCatalog() -> (episodes: [Episode], age: TimeInterval)? {
        var all: [Episode] = []
        var page = 1, pages = 1, oldest: TimeInterval = 0
        repeat {
            guard let (r, age) = AIOService.cachedGroupings(type: "Album", page: page, pageSize: 25) else { return nil }
            for g in r.contentGroupings ?? [] { all += g.contentList }
            pages = r.metadata?.totalPageCount ?? page
            oldest = max(oldest, age)
            page += 1
        } while page <= pages && page <= 10
        let episodes = ordered(all)
        return episodes.isEmpty ? nil : (episodes, oldest)
    }

    /// Numbered episodes only, deduplicated, in broadcast order.
    static func ordered(_ all: [Episode]) -> [Episode] {
        var seen = Set<String>()
        return all
            .filter { seen.insert($0.id).inserted }
            .compactMap { e -> (Int, Episode)? in
                // Plain numbers only: "1041" yes, "1041a"/"572b" (bonus tracks) no. Album lists leave
                // episode_number empty, so fall back to the "#1041: Title" prefix.
                let raw = e.episodeNumber?.trimmingCharacters(in: .whitespaces) ?? ""
                if let n = Int(raw) { return (n, e) }
                guard raw.isEmpty, let name = e.shortName, name.hasPrefix("#"),
                      let colon = name.firstIndex(of: ":"),
                      let n = Int(name[name.index(after: name.startIndex)..<colon]) else { return nil }
                return (n, e)
            }
            .sorted { $0.0 < $1.0 }
            .map(\.1)
    }
}

/// Home shelf for `NextUpStore`.
private struct NextUpShelf: View {
    @Environment(AudioPlayer.self) private var player
    let store: NextUpStore

    var body: some View {
        let items = store.episodes.filter { !$0.isBonus && !(player.progress(for: $0)?.isComplete ?? false) }
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                ShelfHeader(title: "Next Up")
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(items) { episode in
                            NavigationLink(value: Route.episode(episode, groupingID: nil)) {
                                EpisodeCard(episode: episode)
                                    .shelfItem()
                            }
                            .buttonStyle(.plain)
                            .episodeContextMenu(episode)
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, 20)
                }
                .scrollTargetBehavior(.viewAligned)
            }
        }
    }
}

#if SCREENSHOT_DEMO
/// The screenshot demo's Home: only the newest albums and the newest episodes, nothing promotional or personal.
private struct DemoHome: View {
    @State private var store = BrowseStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            VStack(alignment: .leading, spacing: 12) {
                ShelfHeader(title: "New Albums")
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(store.newAlbums) { g in
                            NavigationLink(value: Route.grouping(id: g.groupingID ?? "", preview: g)) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Artwork(url: g.artworkURL, cornerRadius: 12)
                                        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
                                    Text(g.title).font(.univers(13, relativeTo: .footnote)).lineLimit(2, reservesSpace: true)
                                }
                                .shelfItem()
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                ShelfHeader(title: "Latest Episodes")
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(latestEpisodes) { e in
                            NavigationLink(value: Route.episode(e, groupingID: store.newAlbums.first?.groupingID)) {
                                EpisodeCard(episode: e).shelfItem()
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
        .task { await store.load() }
    }

    /// The newest album's episodes, newest first.
    private var latestEpisodes: [Episode] { Array((store.newAlbums.first?.contentList ?? []).reversed().prefix(10)) }
}
#endif

private extension Grouping {
    var isContinue: Bool { name?.hasPrefix("Continue where you left off") == true }
    /// The podcast shelves ("Podcast Year" groupings, or a shelf named for podcasts).
    var isPodcast: Bool { type == "Podcast Year" || name?.localizedCaseInsensitiveContains("podcast") == true }
}
