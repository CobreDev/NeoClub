import SwiftUI

/// Apple Music-style shell: Liquid Glass tab bar with the mini player docked as its bottom accessory.
struct MainTabView: View {
    @Environment(AudioPlayer.self) private var player
    @Environment(DownloadStore.self) private var downloads

    enum TabID: String, Hashable { case home, browse, library, search }
    /// #001 Whit's Flop: the only episode to play while testing (progress syncs to the account).
    static let testEpisodeID = "a354W0000046TjUQAU"
    @Environment(NetworkMonitor.self) private var network
    @Environment(BookmarkStore.self) private var bookmarks
    @State private var tab: TabID = NetworkMonitor.shared.isOnline ? .home : .library
    @State private var paths: [TabID: [Route]] = [:]
    /// The app's place, kept with the window so it survives the window being recreated (unfolding the iPhone Duo
    /// moves the app to the inner screen).
    @SceneStorage("sceneState") private var storedScene: Data?
    @State private var restored = false

    private func path(_ id: TabID) -> Binding<[Route]> {
        Binding(get: { paths[id] ?? [] }, set: { paths[id] = $0 })
    }

    private func saveScene() {
        guard restored else { return }
        let state = SceneState(tab: tab.rawValue,
                               paths: Dictionary(uniqueKeysWithValues: paths.map { ($0.key.rawValue, $0.value.compactMap(StoredRoute.init)) }),
                               nowPlayingOpen: player.showNowPlaying)
        storedScene = try? JSONEncoder().encode(state)
    }

    private func restoreScene() {
        defer { restored = true }
        guard !restored, let data = storedScene, let state = try? JSONDecoder().decode(SceneState.self, from: data) else { return }
        if let t = TabID(rawValue: state.tab) { tab = t }
        for (key, routes) in state.paths {
            if let id = TabID(rawValue: key) { paths[id] = routes.compactMap(\.route) }
        }
        if state.nowPlayingOpen && player.hasItem { player.showNowPlaying = true }
    }

    var body: some View {
        tabs
            // Now Playing card (Apple Music-style slide-then-collapse into the mini player).
            .overlay { PlayerCardHost() }
            // The mini player is always there: bring back whatever was playing last (paused).
            .task {
                player.restoreLastSession()
                restoreScene()
            }
            .onChange(of: paths) { saveScene() }
            .onChange(of: tab) { saveScene() }
            .onChange(of: player.showNowPlaying) { saveScene() }
        #if DEBUG
        // Developer convenience. Progress syncs, so test playback is always Whit's Flop: `-debugPlayTest` plays it.
        .task {
            let args = ProcessInfo.processInfo.arguments
            if args.contains("-debugPlayTest"), let test = try? await AIOService.episode(Self.testEpisodeID) {
                // Queue the rest of its album so Up Next has a full list to look at.
                let album = test.inAlbum ?? []
                let after = album.firstIndex { $0.id == test.id }.map { Array(album.dropFirst($0 + 1)) } ?? []
                player.play(test, queue: after)
            }
            // `-debugTab browse|library|search` opens that tab on launch.
            if let i = args.firstIndex(of: "-debugTab"), i + 1 < args.count {
                tab = ["browse": .browse, "library": .library, "search": .search][args[i + 1]] ?? .home
            }
            // `-debugEpisode <episodeID>` opens that episode's page.
            if let i = args.firstIndex(of: "-debugEpisode"), i + 1 < args.count,
               let ep = try? await AIOService.episode(args[i + 1]) {
                paths[tab, default: []].append(Route.episode(ep, groupingID: nil))
            }
            // `-debugDownload <episodeID>` starts a download on launch (testing without UI input).
            if let i = args.firstIndex(of: "-debugDownload"), i + 1 < args.count,
               let ep = try? await AIOService.episode(args[i + 1]) {
                downloads.download(ep)
            }
        }
        #endif
    }

    private var tabs: some View {
        @Bindable var player = player
        return TabView(selection: $tab) {
            Tab("Home", systemImage: "house.fill", value: .home) {
                NavigationStack(path: path(.home)) { HomeView().aioDestinations() }
            }
            Tab("Browse", systemImage: "square.grid.2x2.fill", value: .browse) {
                NavigationStack(path: path(.browse)) { BrowseView().aioDestinations() }
            }
            Tab("Library", systemImage: "books.vertical.fill", value: .library) {
                NavigationStack(path: path(.library)) { LibraryView().aioDestinations() }
            }
            Tab(value: .search, role: .search) {
                NavigationStack(path: path(.search)) { SearchView().aioDestinations() }
            }
        }
        // "Go to Album" / "Go to Episode" from Now Playing: close the player and open it on the current tab.
        .onChange(of: player.navigationRequest) { _, route in
            guard let route else { return }
            player.showNowPlaying = false
            paths[tab, default: []].append(route)
            player.navigationRequest = nil
        }
        // Launching or dropping offline: the Library (Downloads) is what still works.
        .onChange(of: network.isOnline) { _, online in
            if !online && tab != .library { tab = .library }
        }
        // Tab bar on phones and the outer screen; sidebar on the big inner screen.
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory(isEnabled: player.hasItem) {
            MiniPlayer()
        }
        .alert("Bookmark", isPresented: Binding(
            get: { bookmarks.actionError != nil },
            set: { if !$0 { bookmarks.actionError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(bookmarks.actionError ?? "")
        }
        .alert("Download Failed", isPresented: Binding(
            get: { downloads.lastError != nil },
            set: { if !$0 { downloads.lastError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(downloads.lastError ?? "")
        }
    }
}

/// Compact player shown in the tab bar accessory; tap to open Now Playing.
struct MiniPlayer: View {
    @Environment(AudioPlayer.self) private var player
    /// The copy drawn on the Now Playing card as it lands; the real one measures itself and hides meanwhile.
    var isCardFace = false
    @State private var card = PlayerCardModel.shared
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    /// The bar's own width: wide (the iPhone Duo unfolded in landscape) gets Apple Music's full control bar.
    @State private var width: CGFloat = 0
    private var isWide: Bool { width >= 640 }

    var body: some View {
        Group {
            if isWide { wideBar } else { compactBar }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .contentShape(.rect)
        .onTapGesture { player.showNowPlaying = true }
        // Swiping up opens Now Playing as soon as the swipe is clearly upward: the card animates open on its own,
        // like a tap, rather than following the finger.
        .gesture(isCardFace ? nil : DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { v in
                let up = -v.translation.height
                if up > 12, up > abs(v.translation.width), !player.showNowPlaying { player.showNowPlaying = true }
            })
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            if !isCardFace { card.miniFrame = frame }
            width = frame.width
        }
        // The card stands in for the mini player while it's open or animating.
        .opacity(!isCardFace && card.visible ? 0 : 1)
    }

    /// Artwork, title and album/collection.
    private var nowPlaying: some View {
        HStack(spacing: 12) {
            Artwork(url: player.episode?.smallArtworkURL, cornerRadius: 6)
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 0) {
                Text(player.episode?.title ?? "")
                    .font(.universBold(14, relativeTo: .subheadline))
                    .lineLimit(1)
                if placement != .inline, let album = player.episode?.albumTitle {
                    Text(album).font(.univers(12, relativeTo: .caption)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }

    @ViewBuilder private var playPause: some View {
        if player.isLoading {
            ProgressView().controlSize(.small)
        } else {
            Button { player.togglePlayPause() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.title3)
                    .contentTransition(.symbolEffect(.replace))
            }
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
        }
    }

    /// Phone-width bar: what's playing, then play/pause and skip forward (like Apple Music's mini player).
    private var compactBar: some View {
        HStack(spacing: 12) {
            nowPlaying
            Spacer(minLength: 4)
            playPause
            if placement != .inline {
                Button { player.skip(by: 30) } label: { Image(systemName: "goforward.30").font(.title3) }
                    .accessibilityLabel("Skip forward 30 seconds")
            }
        }
    }

    /// Wide bar, laid out like Apple Music's on a wide screen: transport controls, what's playing, then more.
    private var wideBar: some View {
        HStack(spacing: 22) {
            Button { player.skip(by: -15) } label: { Image(systemName: "gobackward.15").font(.title3) }
                .accessibilityLabel("Skip back 15 seconds")
            playPause.font(.title2)
            Button { player.skip(by: 30) } label: { Image(systemName: "goforward.30").font(.title3) }
                .accessibilityLabel("Skip forward 30 seconds")
            nowPlaying.padding(.leading, 8)
            Spacer(minLength: 8)
            if let episode = player.episode {
                Menu {
                    Button("Go to Episode", systemImage: "info.circle") {
                        player.navigationRequest = .episode(episode, groupingID: player.groupingID)
                    }
                    if player.progress(for: episode)?.isComplete == true {
                        Button("Mark as Unplayed", systemImage: "arrow.uturn.backward.circle") { player.markUnplayed(episode) }
                    } else {
                        Button("Mark as Played", systemImage: "checkmark.circle") { player.markPlayed(episode) }
                    }
                    ShareLink(item: episode.shareURL) { Label("Share Episode", systemImage: "square.and.arrow.up") }
                } label: {
                    Image(systemName: "ellipsis").font(.title3).frame(width: 32, height: 32).contentShape(.rect)
                }
                .accessibilityLabel("More")
            }
        }
    }
}
