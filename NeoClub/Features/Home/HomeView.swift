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
            await nextUp.refresh(continuing: continuing?.contentList ?? [], history: player.history.map(\.id))
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
            } else {
                ShelfHeader(title: displayTitle)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(shelf.contentList) { episode in
                        NavigationLink(value: Route.episode(episode, groupingID: shelf.groupingID)) {
                            EpisodeCard(episode: episode, width: isContinue ? 200 : 150)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Play", systemImage: "play.fill") {
                                player.play(episode, queue: queue(after: episode), groupingID: shelf.groupingID)
                            }
                        }
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
                                EpisodeCard(episode: episode, width: 150)
                            }
                            .buttonStyle(.plain)
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

/// "Next Up": the next unplayed episode after each one you're in the middle of or played recently, in album order.
/// Reads the album track list that comes with each episode's details (with this profile's progress on every track).
@MainActor
@Observable
final class NextUpStore {
    static let shared = NextUpStore()
    private(set) var episodes: [Episode] = []
    private var lastSeeds: [String] = []

    func refresh(continuing: [Episode], history: [String]) async {
        // Most recent first: what's in progress on the account, then what was played here.
        var seeds: [String] = []
        for id in continuing.map(\.id) + history where !seeds.contains(id) { seeds.append(id) }
        seeds = Array(seeds.prefix(5))
        guard seeds != lastSeeds || episodes.isEmpty else { return }
        lastSeeds = seeds

        let details = await withTaskGroup(of: (Int, Episode?).self) { group in
            for (i, id) in seeds.enumerated() {
                group.addTask { (i, try? await AIOService.episode(id)) }
            }
            var out: [(Int, Episode?)] = []
            for await r in group { out.append(r) }
            return out.sorted { $0.0 < $1.0 }.compactMap(\.1)
        }
        let inProgress = Set(continuing.map(\.id))
        var next: [Episode] = []
        for detail in details {
            guard let album = detail.inAlbum, let i = album.firstIndex(where: { $0.id == detail.id }) else { continue }
            let candidate = album.dropFirst(i + 1).first { e in
                !(e.progress?.isComplete ?? false) && !(e.progress?.isInProgress ?? false) && !inProgress.contains(e.id)
            }
            if let candidate, !next.contains(where: { $0.id == candidate.id }) { next.append(candidate) }
        }
        episodes = next
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
                                EpisodeCard(episode: episode, width: 150)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Play", systemImage: "play.fill") { player.play(episode) }
                            }
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
