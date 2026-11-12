import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var app
    @Environment(AudioPlayer.self) private var player
    @Environment(BookmarkStore.self) private var bookmarks
    @State private var nextUp = NextUpStore.shared
    @State private var home: HomeResponse?
    @State private var error: String?
    @State private var showAccount = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                OfflineBanner()
                if let carousel = home?.carousel, !carousel.isEmpty {
                    CarouselView(items: carousel)
                }
                if let shelves = home?.playlists {
                    ForEach(Array(shelves.enumerated()), id: \.element.id) { i, shelf in
                        Shelf(shelf: shelf)
                        // Next Up and Bookmarks sit right after "Continue Listening" (or first if there isn't one).
                        if i == 0 {
                            NextUpShelf(store: nextUp)
                            BookmarksShelf()
                        }
                    }
                    if shelves.isEmpty {
                        NextUpShelf(store: nextUp)
                        BookmarksShelf()
                    }
                } else if let error {
                    ErrorView(message: error) { await load() }
                } else {
                    LoadingView()
                }
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
                .accessibilityLabel("Account")
            }
            // Drop the toolbar's shared capsule so the button is a circle matching the avatar.
            .sharedBackgroundVisibility(.hidden)
        }
        .sheet(isPresented: $showAccount) { AccountView() }
        .refreshable { await load() }
        .task { if home == nil { await load() } }
    }

    private func load() async {
        async let marks: Void = bookmarks.load()
        do {
            home = try await AIOService.home()
            error = nil
            let continuing = home?.playlists?.first { $0.name?.hasPrefix("Continue where you left off") == true }
            await nextUp.refresh(continuing: continuing?.contentList ?? [], history: player.history.map { ($0.id, $0.playedAt) }) {
                player.progress(for: $0)?.isComplete ?? false
            }
        } catch {
            self.error = error.localizedDescription
        }
        await marks
    }

}

/// A horizontal shelf of episodes, titled by its album/collection, linking to the full grouping.
private struct Shelf: View {
    @Environment(AudioPlayer.self) private var player
    let shelf: Grouping

    var body: some View {
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
                    ForEach(shelf.contentList) { episode in
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

    private var isContinue: Bool { shelf.name?.hasPrefix("Continue where you left off") == true }

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
                            AsyncImage(url: .aio(item.imageUrl)) { $0.resizable().scaledToFill() } placeholder: {
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
    /// Every numbered episode in every album, in broadcast order. Loaded once per launch.
    private var catalog: [Episode] = []
    private var lastSeeds: [String] = []

    func refresh(continuing: [Episode], history: [(id: String, at: Date)], isDone: (Episode) -> Bool) async {
        if catalog.isEmpty { catalog = await Self.loadCatalog() }
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

        let inProgress = Set(continuing.map(\.id))
        var next: [Episode] = []
        for seed in seeds {
            guard let i = catalog.firstIndex(where: { $0.id == seed }) else { continue }
            let candidate = catalog[(i + 1)...].first { e in
                !inProgress.contains(e.id) && !isDone(e) && !(e.progress?.isInProgress ?? false)
            }
            if let candidate, !next.contains(where: { $0.id == candidate.id }) { next.append(candidate) }
        }
        episodes = next
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
        let items = store.episodes.filter { !(player.progress(for: $0)?.isComplete ?? false) }
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
