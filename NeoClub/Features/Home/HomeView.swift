import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var app
    @Environment(AudioPlayer.self) private var player
    @State private var home: HomeResponse?
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                if let carousel = home?.carousel, !carousel.isEmpty {
                    CarouselView(items: carousel)
                }
                if let shelves = home?.playlists {
                    ForEach(shelves) { shelf in
                        Shelf(shelf: shelf)
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
                Button { app.switchProfile() } label: {
                    if let profile = app.profile {
                        ProfileBadge(profile: profile, size: 36, showsName: false)
                            .padding(4)
                            .glassEffect(.regular.interactive(), in: .circle)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Switch profile")
            }
            // Drop the toolbar's shared capsule so the button is a circle matching the avatar.
            .sharedBackgroundVisibility(.hidden)
        }
        .refreshable { await load() }
        .task { if home == nil { await load() } }
    }

    private func load() async {
        do {
            home = try await AIOService.home()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
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
                            .lineLimit(1)
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
                        .containerRelativeFrame(.horizontal) { w, _ in w - 40 }

                    if let route = CarouselView.route(for: item.hyperlink) {
                        NavigationLink(value: route) { card }.buttonStyle(.plain)
                    } else {
                        card
                    }
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, 20)
        }
        .scrollTargetBehavior(.viewAligned)
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
