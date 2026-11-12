import SwiftUI

/// Browse landing page, Apple Music style: a shelf of the newest albums, then colorful category cards with
/// real covers fanned across them.
struct BrowseView: View {
    struct Category: Identifiable {
        let type: String, title: String, symbol: String
        var filter: GroupingFilter = .all
        let colors: [Color]
        var id: String { "\(type)-\(filter)" }
    }

    static let categories = [
        Category(type: "Album", title: "Albums", symbol: "square.stack.fill", filter: .regularAlbums,
                 colors: [Color(hex: 0xF7B733), Color(hex: 0xE8590C)]),
        Category(type: "Album", title: "Club Adventures", symbol: "star.fill", filter: .clubAlbums,
                 colors: [Color(hex: 0xF0506E), Color(hex: 0xB0123B)]),
        Category(type: "Series", title: "Series", symbol: "rectangle.stack.fill",
                 colors: [Color(hex: 0x3CC48A), Color(hex: 0x0E7C5A)]),
        Category(type: "Collection", title: "Collections", symbol: "square.grid.2x2.fill",
                 colors: [Color(hex: 0x9B6CF0), Color(hex: 0x5631B5)]),
        Category(type: "Podcast Year", title: "Podcasts", symbol: "mic.fill",
                 colors: [Color(hex: 0x2FB8F0), Color(hex: 0x1659C7)]),
        Category(type: "Book Series", title: "Books", symbol: "book.fill",
                 colors: [Color(hex: 0x20C5C0), Color(hex: 0x0A7A8C)]),
    ]

    @State private var store = BrowseStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if !store.newAlbums.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        NavigationLink(value: Route.groupingList(type: "Album", title: "Albums", filter: .regularAlbums)) {
                            HStack(spacing: 4) {
                                Text("New Albums").font(.jacoby(24))
                                Image(systemName: "chevron.right").font(.headline.weight(.bold)).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 20)
                        ScrollView(.horizontal) {
                            LazyHStack(alignment: .top, spacing: 14) {
                                ForEach(store.newAlbums) { g in
                                    NavigationLink(value: Route.grouping(id: g.groupingID ?? "", preview: g)) {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Artwork(url: g.artworkURL, cornerRadius: 12)
                                                .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
                                            Text(g.title)
                                                .font(.univers(13, relativeTo: .footnote))
                                                .lineLimit(2, reservesSpace: true)
                                                .multilineTextAlignment(.leading)
                                        }
                                        .frame(width: 150)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .scrollTargetLayout()
                            .padding(.horizontal, 20)
                        }
                        .scrollTargetBehavior(.viewAligned)
                        .scrollIndicators(.hidden)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Categories").font(.jacoby(24)).padding(.horizontal, 20)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 14)], spacing: 14) {
                        ForEach(Self.categories) { c in
                            NavigationLink(value: Route.groupingList(type: c.type, title: c.title, filter: c.filter)) {
                                CategoryCard(category: c, covers: store.covers[c.id] ?? [])
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
            .padding(.vertical, 12)
        }
        .aioBackground("bg_celebration.jpg")
        .navigationTitle("Browse")
        .task { await store.load() }
    }
}

/// A colorful category card: gradient with covers fanned across it, and the title in the top-left corner over a blur
/// that fades out toward the opposite corner (just enough to keep the title readable).
private struct CategoryCard: View {
    let category: BrowseView.Category
    let covers: [URL]
    /// The title's size, so the blur covers all of it.
    @State private var titleSize: CGSize = .zero

    var body: some View {
        ZStack(alignment: .topLeading) {
            artwork
            // The same art, blurred, revealed behind the whole title and feathering out from its corner.
            artwork
                .blur(radius: 6)
                .mask(alignment: .topLeading) {
                    // A wide, soft feather: full blur behind the letters, easing out gradually around them.
                    Capsule()
                        .frame(width: max(0, titleSize.width - 4), height: max(0, titleSize.height - 14))
                        .offset(x: 2, y: 7)
                        .blur(radius: 16)
                }
                .allowsHitTesting(false)
            HStack(spacing: 6) {
                Image(systemName: category.symbol).font(.subheadline.weight(.semibold))
                Text(category.title)
                    .font(.jacoby(20))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
            .padding(12)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { titleSize = $0 }
        }
        .frame(height: 104)
        .clipShape(.rect(cornerRadius: 16, style: .continuous))
        .contentShape(.rect(cornerRadius: 16))
    }

    /// Gradient plus up to three covers fanned out toward the bottom-right corner.
    private var artwork: some View {
        ZStack {
            LinearGradient(colors: category.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            GeometryReader { geo in
                let side = geo.size.height * 0.74
                ZStack {
                    ForEach(Array(covers.prefix(3).enumerated().reversed()), id: \.offset) { i, url in
                        Artwork(url: url, cornerRadius: 8)
                            .frame(width: side, height: side)
                            .shadow(color: .black.opacity(0.35), radius: 6, x: -2, y: 3)
                            .rotationEffect(.degrees(16 - Double(i) * 11))
                            .offset(x: -CGFloat(i) * side * 0.46, y: CGFloat(i) * side * 0.08)
                    }
                }
                .position(x: geo.size.width - side * 0.36, y: geo.size.height * 0.68)
            }
        }
    }
}

/// Covers for the Browse page: one small page per category, loaded once per launch (the same list requests the
/// grids make).
@MainActor
@Observable
final class BrowseStore {
    static let shared = BrowseStore()
    private(set) var newAlbums: [Grouping] = []
    private(set) var covers: [String: [URL]] = [:]
    private var loaded = false

    func load() async {
        guard !loaded else { return }
        loaded = true
        // Albums: one page feeds the New Albums shelf and both album cards.
        if let albums = try? await AIOService.groupings(type: "Album", page: 1).contentGroupings {
            let regular = albums.filter { GroupingFilter.regularAlbums.includes($0) }
            newAlbums = Array(regular.prefix(12))
            covers["Album-regularAlbums"] = regular.compactMap(\.artworkURL)
            covers["Album-clubAlbums"] = albums.filter { GroupingFilter.clubAlbums.includes($0) }.compactMap(\.artworkURL)
        } else {
            loaded = false
        }
        await withTaskGroup(of: (String, [URL]).self) { group in
            for c in BrowseView.categories where c.type != "Album" {
                group.addTask {
                    let list = (try? await AIOService.groupings(type: c.type, page: 1, pageSize: 3).contentGroupings) ?? []
                    return (c.id, list.compactMap(\.artworkURL))
                }
            }
            for await (id, urls) in group { covers[id] = urls }
        }
    }
}

/// Paged grid of albums/series/etc., newest first, loaded 24 at a time.
struct GroupingGridView: View {
    let type: String
    let title: String
    var filter: GroupingFilter = .all
    @State private var groupings: [Grouping] = []
    @State private var page = 0
    @State private var totalPages = 1
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], spacing: 22) {
                ForEach(groupings) { g in
                    NavigationLink(value: Route.grouping(id: g.groupingID ?? "", preview: g)) {
                        VStack(alignment: .leading, spacing: 6) {
                            Artwork(url: g.artworkURL)
                            Text(g.title)
                                .font(.univers(14, relativeTo: .subheadline))
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    .buttonStyle(.plain)
                    .onAppear { if g.id == groupings.last?.id { Task { await loadMore() } } }
                }
            }
            .padding(20)
            if loading { LoadingView() }
            if let error, groupings.isEmpty { ErrorView(message: error) { await loadMore() } }
        }
        .aioBackground("bg_town.jpg")
        .navigationTitle(title)
        .task { if groupings.isEmpty { await loadMore() } }
    }

    private func loadMore() async {
        guard !loading, page < totalPages else { return }
        loading = true
        defer { loading = false }
        do {
            let response = try await AIOService.groupings(type: type, page: page + 1)
            let fresh = (response.contentGroupings ?? [])
                .filter { g in filter.includes(g) && !groupings.contains { $0.id == g.id } }
            groupings += fresh
            page += 1
            totalPages = response.metadata?.totalPageCount ?? page
            error = nil
            // A filtered page can come back nearly empty; keep paging so the grid fills the screen.
            if filter != .all && fresh.count < 6 && page < totalPages {
                loading = false
                await loadMore()
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Splits the AIO album list: regular numbered albums vs. the club-exclusive "½" seasons.
enum GroupingFilter: String, Hashable {
    case all, regularAlbums, clubAlbums

    func includes(_ g: Grouping) -> Bool {
        switch self {
        case .all: return true
        case .regularAlbums: return !Self.isClub(g)
        case .clubAlbums: return Self.isClub(g)
        }
    }

    /// Club seasons are numbered with a half (album_number "79.5", name "#79 ½: Club Season 12…").
    static func isClub(_ g: Grouping) -> Bool {
        if let n = g.albumNumber, n.contains(".") { return true }
        let name = g.name ?? ""
        return name.contains("½") || name.localizedCaseInsensitiveContains("Club Season")
    }
}
