import SwiftUI

/// Apple Music-style shell: Liquid Glass tab bar with the mini player docked as its bottom accessory.
struct MainTabView: View {
    @Environment(AudioPlayer.self) private var player
    @Environment(DownloadStore.self) private var downloads

    enum TabID: Hashable { case home, browse, library, search }
    @Environment(NetworkMonitor.self) private var network
    @Environment(BookmarkStore.self) private var bookmarks
    @State private var tab: TabID = NetworkMonitor.shared.isOnline ? .home : .library
    @State private var paths: [TabID: NavigationPath] = [:]

    private func path(_ id: TabID) -> Binding<NavigationPath> {
        Binding(get: { paths[id] ?? NavigationPath() }, set: { paths[id] = $0 })
    }

    var body: some View {
        tabs
            // Now Playing card (Apple Music-style slide-then-collapse into the mini player).
            .overlay { PlayerCardHost() }
            // The mini player is always there: bring back whatever was playing last (paused).
            .task { player.restoreLastSession() }
        #if DEBUG
        // Developer convenience: `-debugResumeLast` resumes the most recent episode on launch (progress sync is off in debug).
        .task {
            let args = ProcessInfo.processInfo.arguments
            if args.contains("-debugResumeLast"), !player.hasItem,
               let last = player.history.first {
                player.playFromHistory(last)
            }
            // `-debugTab browse|library|search` opens that tab on launch.
            if let i = args.firstIndex(of: "-debugTab"), i + 1 < args.count {
                tab = ["browse": .browse, "library": .library, "search": .search][args[i + 1]] ?? .home
            }
            // `-debugEpisode <episodeID>` opens that episode's page.
            if let i = args.firstIndex(of: "-debugEpisode"), i + 1 < args.count,
               let ep = try? await AIOService.episode(args[i + 1]) {
                paths[tab, default: NavigationPath()].append(Route.episode(ep, groupingID: nil))
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
            paths[tab, default: NavigationPath()].append(route)
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

    var body: some View {
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
            Spacer(minLength: 4)
            if player.isLoading {
                ProgressView().controlSize(.small)
            } else {
                Button { player.togglePlayPause() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.title3)
                }
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            }
            if placement != .inline {
                Button { player.skip(by: 30) } label: { Image(systemName: "goforward.30").font(.title3) }
                    .accessibilityLabel("Skip forward 30 seconds")
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .contentShape(.rect)
        .onTapGesture { player.showNowPlaying = true }
        // A quick upward flick opens Now Playing (like Apple Music, the card isn't dragged up with the finger;
        // it plays the same open animation as a tap).
        .gesture(isCardFace ? nil : DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .onEnded { v in
                let up = -v.translation.height
                let speed = -v.velocity.height
                if up > 24 && (speed > 250 || up > 60) { player.showNowPlaying = true }
            })
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            if !isCardFace { card.miniFrame = frame }
        }
        // The card stands in for the mini player while it's open or animating.
        .opacity(!isCardFace && card.visible ? 0 : 1)
    }
}
