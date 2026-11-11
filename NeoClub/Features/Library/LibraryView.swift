import SwiftUI

/// Library tab: Bookmarks (default) and Downloads (default when offline).
struct LibraryView: View {
    @Environment(BookmarkStore.self) private var bookmarks
    @Environment(NetworkMonitor.self) private var network

    enum Section: String, CaseIterable, Identifiable {
        case bookmarks = "Bookmarks", downloads = "Downloads"
        var id: Self { self }
    }
    @State private var section: Section?

    var body: some View {
        let current = section ?? (network.isOnline ? .bookmarks : .downloads)
        List {
            Picker("Section", selection: Binding(get: { current }, set: { section = $0 })) {
                ForEach(Section.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            switch current {
            case .bookmarks: BookmarksList()
            case .downloads: DownloadsList()
            }
        }
        .listStyle(.plain)
        .aioBackground("bg_treasure.jpg")
        .navigationTitle("Library")
        .refreshable { if current == .bookmarks { await bookmarks.load() } }
        .task { if !bookmarks.loaded && network.isOnline { await bookmarks.load() } }
        // Losing the connection jumps to Downloads (the only thing that still plays).
        .onChange(of: network.isOnline) { _, online in
            if !online { section = .downloads }
        }
    }
}
