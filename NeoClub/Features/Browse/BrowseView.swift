import SwiftUI

/// Browse landing page: AIO section art tiles leading to album, series, collection and podcast grids.
struct BrowseView: View {
    private struct Section: Identifiable {
        let type: String, title: String, art: String
        var id: String { type }
    }

    private let sections = [
        Section(type: "Album", title: "Albums", art: "hero_albums"),
        Section(type: "Series", title: "Series", art: "hero_series"),
        Section(type: "Collection", title: "Collections", art: "hero_episodes"),
        Section(type: "Podcast Year", title: "Podcasts", art: "hero_radio"),
        Section(type: "Book Series", title: "Books", art: "hero_books"),
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 14)], spacing: 14) {
                ForEach(sections) { s in
                    NavigationLink(value: Route.groupingList(type: s.type, title: s.title)) {
                        ZStack(alignment: .bottomLeading) {
                            BrandImage(name: s.art).scaledToFill()
                                .frame(height: 120).clipped()
                                .overlay(LinearGradient(colors: [.clear, .aioNavy.opacity(0.8)], startPoint: .top, endPoint: .bottom))
                            Text(s.title)
                                .font(.jacoby(28))
                                .foregroundStyle(.white)
                                .padding(16)
                        }
                        .frame(height: 120)
                        .clipShape(.rect(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
        }
        .navigationTitle("Browse")
    }
}

/// Paged grid of albums/series/etc., newest first, loaded 24 at a time.
struct GroupingGridView: View {
    let type: String
    let title: String
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
        .navigationTitle(title)
        .task { if groupings.isEmpty { await loadMore() } }
    }

    private func loadMore() async {
        guard !loading, page < totalPages else { return }
        loading = true
        defer { loading = false }
        do {
            let response = try await AIOService.groupings(type: type, page: page + 1)
            let fresh = (response.contentGroupings ?? []).filter { g in !groupings.contains { $0.id == g.id } }
            groupings += fresh
            page += 1
            totalPages = response.metadata?.totalPageCount ?? page
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
