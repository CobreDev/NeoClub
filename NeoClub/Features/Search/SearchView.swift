import SwiftUI

struct SearchView: View {
    @State private var query = ""
    @State private var hits: [SearchHit] = []
    @State private var searching = false
    @State private var error: String?
    /// Recent searches that found something, newest first (kept on this device).
    @AppStorage("recentSearches") private var recentData = Data()
    @State private var browse = BrowseStore.shared

    private var recent: [String] { (try? JSONDecoder().decode([String].self, from: recentData)) ?? [] }

    private func remember(_ term: String) {
        var list = recent.filter { $0.caseInsensitiveCompare(term) != .orderedSame }
        list.insert(term, at: 0)
        recentData = (try? JSONEncoder().encode(Array(list.prefix(8)))) ?? Data()
    }

    var body: some View {
        Group {
            if query.isEmpty {
                ScrollView { emptyState.padding(.horizontal, 20).padding(.vertical, 12) }
            } else {
                results
            }
        }
        .aioBackground()
        .task { await browse.load() }
        .navigationTitle("Search")
        .searchable(text: $query, prompt: "Episodes, albums, characters, cast")
        .task(id: query) { await search() }
    }

    private var results: some View {
        List {
            if hits.isEmpty && !searching && !query.isEmpty && error == nil {
                ContentUnavailableView.search(text: query)
            }
            let groups = hits.filter { $0.kind == .grouping }
            if !groups.isEmpty {
                Section("Albums & Collections") {
                    ForEach(groups) { hit in
                        NavigationLink(value: Route.grouping(id: hit.id, preview: nil)) { HitRow(hit: hit) }
                            .aioRow()
                            .groupingContextMenu(id: hit.id, grouping: nil)
                    }
                }
            }
            let eps = hits.filter { $0.kind == .episode }
            if !eps.isEmpty {
                Section("Episodes") {
                    ForEach(eps) { hit in
                        NavigationLink(value: Route.episode(Self.stub(hit), groupingID: nil)) { HitRow(hit: hit) }
                            .aioRow()
                            .episodeContextMenu(Self.stub(hit))
                            .queueSwipeActions(Self.stub(hit))
                    }
                }
            }
            let chars = hits.filter { $0.kind == .character }
            if !chars.isEmpty {
                Section("Characters") {
                    ForEach(chars) { hit in
                        NavigationLink(value: Route.character(id: hit.id, preview: nil)) { HitRow(hit: hit, round: true) }
                            .aioRow()
                    }
                }
            }
            let people = hits.filter { $0.kind == .author }
            if !people.isEmpty {
                Section("Cast & Crew") {
                    ForEach(people) { hit in
                        NavigationLink(value: Route.author(id: hit.id, preview: nil)) { HitRow(hit: hit, round: true) }
                            .aioRow()
                    }
                }
            }
            if let error { Text(error).foregroundStyle(.secondary) }
        }
        .overlay { if searching && hits.isEmpty { ProgressView() } }
        .aioBackground()
    }

    private func search() async {
        do {
            // iOS smart punctuation turns ' into ’, which the AIO search doesn't match.
            let term = query.trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "\u{2019}", with: "'").replacingOccurrences(of: "\u{2018}", with: "'")
                .replacingOccurrences(of: "\u{201C}", with: "\"").replacingOccurrences(of: "\u{201D}", with: "\"")
            guard term.count >= 2 else { hits = []; return }
            // Debounce typing so we search once the user pauses, not on every keystroke.
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            searching = true
            defer { searching = false }
            do {
                hits = try await AIOService.search(term)
                error = nil
                if !hits.isEmpty { remember(term) }
            } catch {
                if !Task.isCancelled { self.error = error.localizedDescription }
            }
        }
    }

    /// Before typing, like Apple Music: Recently Searched, then Browse Categories.
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 28) {
            if !recent.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Recently Searched").font(.universBold(22, relativeTo: .title2))
                        Spacer()
                        Button("Clear") { recentData = Data() }
                            .font(.univers(16, relativeTo: .body))
                            .foregroundStyle(Color.aioTint)
                    }
                    AdaptiveGrid(rowSpacing: 10) {
                        ForEach(recent, id: \.self) { term in
                            Button { query = term } label: {
                                Label(term, systemImage: "magnifyingglass")
                                    .font(.univers(16, relativeTo: .body))
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 16)
                                    .frame(height: 48)
                                    .background(.white.opacity(0.14), in: .rect(cornerRadius: 14))
                                    .contentShape(.rect(cornerRadius: 14))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                Text("Browse Categories").font(.universBold(22, relativeTo: .title2))
                AdaptiveGrid(rowSpacing: 14) {
                    ForEach(BrowseView.categories) { c in
                        NavigationLink(value: Route.groupingList(type: c.type, title: c.title, filter: c.filter)) {
                            CategoryCard(category: c, covers: browse.covers[c.id] ?? [])
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    static func stub(_ hit: SearchHit) -> Episode {
        let json = try! JSONSerialization.data(withJSONObject: ["id": hit.id, "name": hit.title, "thumbnail_small": hit.imageURL?.absoluteString ?? ""])
        return try! JSONDecoder().decode(Episode.self, from: json)
    }
}

private struct HitRow: View {
    let hit: SearchHit
    var round = false
    var body: some View {
        HStack(spacing: 12) {
            Artwork(url: hit.imageURL, cornerRadius: round ? 26 : 6).frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text(hit.title).font(.universBold(16, relativeTo: .headline)).lineLimit(2)
                Text(hit.detail).font(.univers(13, relativeTo: .subheadline)).foregroundStyle(.secondary)
            }
        }
    }
}
