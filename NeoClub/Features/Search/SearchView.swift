import SwiftUI

struct SearchView: View {
    @State private var query = ""
    @State private var hits: [SearchHit] = []
    @State private var searching = false
    @State private var error: String?

    var body: some View {
        List {
            if hits.isEmpty && !searching && !query.isEmpty && error == nil {
                ContentUnavailableView.search(text: query)
            }
            let groups = hits.filter { $0.kind == .grouping }
            if !groups.isEmpty {
                Section("Albums & Collections") {
                    ForEach(groups) { hit in
                        NavigationLink(value: Route.grouping(id: hit.id, preview: nil)) { HitRow(hit: hit) }
                    }
                }
            }
            let eps = hits.filter { $0.kind == .episode }
            if !eps.isEmpty {
                Section("Episodes") {
                    ForEach(eps) { hit in
                        NavigationLink(value: Route.episode(Self.stub(hit), groupingID: nil)) { HitRow(hit: hit) }
                    }
                }
            }
            if let error { Text(error).foregroundStyle(.secondary) }
        }
        .overlay { if searching && hits.isEmpty { ProgressView() } }
        .navigationTitle("Search")
        .searchable(text: $query, prompt: "Episodes, albums, characters")
        .task(id: query) {
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
            } catch {
                if !Task.isCancelled { self.error = error.localizedDescription }
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
    var body: some View {
        HStack(spacing: 12) {
            Artwork(url: hit.imageURL, cornerRadius: 6).frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text(hit.title).font(.universBold(16, relativeTo: .headline)).lineLimit(2)
                Text(hit.detail).font(.univers(13, relativeTo: .subheadline)).foregroundStyle(.secondary)
            }
        }
    }
}
