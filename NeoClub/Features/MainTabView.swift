import SwiftUI

/// Apple Music-style shell: Liquid Glass tab bar with the mini player docked as its bottom accessory.
struct MainTabView: View {
    @Environment(AudioPlayer.self) private var player
    @Environment(DownloadStore.self) private var downloads

    enum TabID: String, Hashable { case home, browse, library, search }
    @Environment(NetworkMonitor.self) private var network
    @Environment(BookmarkStore.self) private var bookmarks
    @State private var tab: TabID = SceneMemory.tab ?? (NetworkMonitor.shared.isOnline ? .home : .library)
    @State private var paths: [TabID: [Route]] = SceneMemory.paths

    /// The app's place lives as long as the process, not longer: it survives the window being recreated (unfolding
    /// the iPhone Duo moves the app to the inner screen), but a fresh launch always opens on Home.
    private enum SceneMemory {
        static var tab: TabID?
        static var paths: [TabID: [Route]] = [:]
    }

    private func path(_ id: TabID) -> Binding<[Route]> {
        Binding(get: { paths[id] ?? [] }, set: { paths[id] = $0 })
    }

    var body: some View {
        tabs
            // Now Playing. Apple Music presents it with UIKit's zoom transition from the tab bar accessory (traced:
            // its PalettePresentationAnimationController runs on _UIZoomTransitionController, and the accessory's
            // Liquid Glass is matched to the card as it lands), so the native version is the same mechanism.
            // Presented from UIKit: Music's open animator, the system zoom transition for the close.
            .onChange(of: player.showNowPlaying) { _, show in NowPlayingPresenter.shared.update(show: show) }
            // The mini player is always there: bring back whatever was playing last (paused).
            .task {
                player.restoreLastSession()
                // Have Now Playing built and laid out before it's first opened.
                try? await Task.sleep(for: .seconds(1))
                NowPlayingPresenter.shared.prepare()
            }
            .onChange(of: paths) { SceneMemory.paths = paths }
            .onChange(of: tab) { SceneMemory.tab = tab }
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
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    /// The bar's own width: wide (the iPhone Duo unfolded in landscape) gets Apple Music's full control bar.
    @State private var width: CGFloat = 0
    private var isWide: Bool { width >= 640 }

    var body: some View {
        Group {
            if isWide { wideBar } else { compactBar }
        }
        // Hidden while Now Playing lands in the bar and faded back in after it (see NowPlayingPresenter).
        .opacity(NowPlayingPresenter.shared.barContentHidden ? 0 : 1)
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .contentShape(.rect)
        .onTapGesture { NowPlayingPresenter.shared.open() }
        // Swiping up opens Now Playing as soon as the swipe is clearly upward: the card animates open on its own,
        // like a tap, rather than following the finger.
        .gesture(DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { v in
                let up = -v.translation.height
                if up > 12, up > abs(v.translation.width) {
                    NowPlayingPresenter.shared.healIfStale()
                    if !NowPlayingPresenter.shared.isPresented { NowPlayingPresenter.shared.open() }
                }
            })
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
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

/// Now Playing as Apple Music presents it: a full-screen form sheet whose source is the mini player (see
/// NowPlayingPresenter). The sheet's own drag closes it, and the close morphs the card into the bar's Liquid Glass.
/// Laid out edge to edge with the screen's insets passed in, as on the card.
///
/// While the card shrinks into the bar its views are resized to the bar's size; the player is laid out at the
/// window's size and pinned to the card's top-left corner, so it's clipped by the shrinking card rather than
/// squeezed into it (Music's content does the same, and fades out as it goes).
struct NowPlayingPresentation: View {
    @Environment(AudioPlayer.self) private var player
    /// The screen's insets and size, from the window: inside the growing card the view's own safe area is measured in
    /// its scaled space and comes out huge, which pushed the player's contents off the card while it opened. Kept
    /// current when the window changes (split view on the Duo, rotation): this view is built once and reused.
    @State private var window = WindowInsetsProbe.current
    /// The player's own coordinate space (its origin is the presented view's top-left).
    static let space = "nowPlaying"

    var body: some View {
        // The player is laid out at the window's size and pinned to the card's top-left, however small the card gets
        // while it shrinks into the bar (Music's content never moves or scales in the card; the card clips it). A
        // fixed-size frame inside a flexible one is centred by SwiftUI once the host is smaller than it, which showed
        // the middle of the player and the artwork's bottom edge as a strip while the card closed (device recording
        // 2026-11-12). An overlay on a clear base is sized by the host and always aligns the content's top-left to it.
        Color.clear
            .overlay(alignment: .topLeading) {
                NowPlayingView(drawsBackground: false, insets: window.insets)
                    .padding(window.insets)
                    // Edge to edge behind the padded player (there's no system safe area here for it to extend into).
                    .background { NowPlayingBackdrop() }
                    .frame(width: window.size.width, height: window.size.height, alignment: .topLeading)
                    .coordinateSpace(.named(Self.space))
            }
            .ignoresSafeArea()
            // Kept built between opens: idle (no scrolling titles, no scrubber updates) while it's closed.
            .environment(\.isOnScreen, NowPlayingPresenter.shared.isPresented)
            .background(WindowInsetsProbe { if $0 != window { window = $0 } })
    }
}

/// Reports the window's safe-area insets and size whenever the window's layout changes.
private struct WindowInsetsProbe: UIViewRepresentable {
    struct Metrics: Equatable { var insets: EdgeInsets; var size: CGSize }
    let changed: (Metrics) -> Void

    @MainActor static var current: Metrics {
        let w = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first { $0.isKeyWindow }
        return Metrics(insets: edge(w?.safeAreaInsets ?? .zero), size: w?.bounds.size ?? .zero)
    }

    static func edge(_ i: UIEdgeInsets) -> EdgeInsets { EdgeInsets(top: i.top, leading: i.left, bottom: i.bottom, trailing: i.right) }

    func makeUIView(context: Context) -> Probe { Probe(changed: changed) }
    func updateUIView(_ view: Probe, context: Context) { view.changed = changed }

    final class Probe: UIView {
        var changed: (Metrics) -> Void
        init(changed: @escaping (Metrics) -> Void) { self.changed = changed; super.init(frame: .zero); isUserInteractionEnabled = false }
        required init?(coder: NSCoder) { fatalError() }
        private func report() {
            guard let w = window else { return }
            let m = Metrics(insets: WindowInsetsProbe.edge(w.safeAreaInsets), size: w.bounds.size)
            DispatchQueue.main.async { [changed] in changed(m) }
        }
        override func didMoveToWindow() { super.didMoveToWindow(); report() }
        override func layoutSubviews() { super.layoutSubviews(); report() }
        override func safeAreaInsetsDidChange() { super.safeAreaInsetsDidChange(); report() }
    }
}
