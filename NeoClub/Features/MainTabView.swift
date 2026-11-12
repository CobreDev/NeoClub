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
    /// The mini player is the zoom transition's source for Now Playing.
    @Namespace private var nowPlayingZoom
    /// Debug switch: the system zoom transition (how Apple Music presents Now Playing) vs the hand-built card.
    @AppStorage(NowPlayingPresentation.nativeKey) private var nativePresentation = true

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
        // Now Playing isn't reopened after a relaunch: the app starts on the mini player (`nowPlayingOpen` is
        // still saved, but only for older builds' sake).
    }

    var body: some View {
        tabs
            // Now Playing. Apple Music presents it with UIKit's zoom transition from the tab bar accessory (traced:
            // its PalettePresentationAnimationController runs on _UIZoomTransitionController, and the accessory's
            // Liquid Glass is matched to the card as it lands), so the native version is the same mechanism.
            .overlay { if !nativePresentation { PlayerCardHost() } }
            // Presented from UIKit: Music's open animator, the system zoom transition for the close.
            .onChange(of: player.showNowPlaying) { _, show in
                if nativePresentation { NowPlayingPresenter.shared.update(show: show) }
            }
            // The mini player is always there: bring back whatever was playing last (paused).
            .task {
                player.restoreLastSession()
                restoreScene()
                // Have Now Playing built and laid out before it's first opened.
                try? await Task.sleep(for: .seconds(1))
                if nativePresentation { NowPlayingPresenter.shared.prepare() }
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
            // `-debugRestoreTestEpisode` puts Whit's Flop back to Complete at its full length on the account (after tests).
            if args.contains("-debugRestoreTestEpisode") {
                do {
                    try await AIOService.saveProgress(episodeID: Self.testEpisodeID, status: "Complete", positionMs: 1_301_240)
                    SignInLog.write("test episode restored: Complete at 1301240")
                } catch {
                    SignInLog.write("test episode restore failed: \(error.localizedDescription)")
                }
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
            MiniPlayer(zoomNamespace: nativePresentation ? nowPlayingZoom : nil)
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
    /// When set, the bar is the source of Now Playing's zoom transition.
    var zoomNamespace: Namespace.ID? = nil
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
        .modifier(ZoomSource(namespace: zoomNamespace))
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

/// Marks the mini player as Now Playing's zoom transition source (native presentation only).
private struct ZoomSource: ViewModifier {
    let namespace: Namespace.ID?
    func body(content: Content) -> some View {
        if let namespace {
            content.matchedTransitionSource(id: NowPlayingPresentation.sourceID, in: namespace)
        } else {
            content
        }
    }
}

/// Now Playing as a full-screen presentation (the system zoom transition draws the card, its springs and the landing
/// in the bar). Laid out edge to edge with the screen's insets passed in, as on the card.
///
/// Dragging down works like Apple Music rather than the system zoom's own drag (which shrinks the card under the
/// finger): the card slides down at full size, 1:1 with the finger, and only morphs into the bar when it's let go.
/// Music does this by moving the card's container (`UIDropShadowView`) during the drag and starting the landing from
/// wherever it was released (traced 2026-11-12); this does the same with the presentation's container.
struct NowPlayingPresentation: View {
    static let nativeKey = "nativeNowPlayingTransition"
    static let sourceID = "miniPlayer"

    @Environment(AudioPlayer.self) private var player
    @State private var card = PresentedCard()
    /// Touch slop before the card starts to follow (UIKit's).
    private let slop: CGFloat = 12

    /// The screen's insets, from the window: inside the growing card the view's own safe area is measured in its
    /// scaled space and comes out huge, which pushed the player's contents off the card while it opened.
    private var screenInsets: EdgeInsets {
        let w = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first { $0.isKeyWindow }
        let i = w?.safeAreaInsets ?? .zero
        return EdgeInsets(top: i.top, leading: i.left, bottom: i.bottom, trailing: i.right)
    }

    var body: some View {
        let insets = screenInsets
        NowPlayingView(drawsBackground: true, insets: insets)
            .padding(insets)
            .ignoresSafeArea()
            .background(PresentedControllerReader { card.controller = $0 })
        // The system's drag-to-dismiss would shrink the card; the drag below replaces it.
        .interactiveDismissDisabled()
        .gesture(DragGesture(minimumDistance: slop, coordinateSpace: .global)
            .onChanged { v in
                guard v.translation.height > 0, abs(v.translation.height) > abs(v.translation.width) || card.dragging else { return }
                card.follow(max(0, v.translation.height - slop))
            }
            .onEnded { v in
                guard card.dragging else { return }
                let distance = v.translation.height - slop
                if distance > 140 || v.velocity.height > 500 {
                    // Hand over to the system dismissal from where the card is now: it lands in the bar from here.
                    card.release()
                    player.showNowPlaying = false
                } else {
                    card.snapBack()
                }
            })
    }
}

/// The presented card's container view, moved directly during the drag (as Apple Music moves its `UIDropShadowView`).
@MainActor
final class PresentedCard {
    weak var controller: UIViewController?
    private(set) var dragging = false
    private var restCenter: CGPoint?

    /// The view the zoom transition animates: the presentation's outermost container under the transition view.
    private var container: UIView? {
        guard var v = controller?.view else { return nil }
        while let s = v.superview, !(String(describing: type(of: s)).contains("TransitionView")), !(s is UIWindow) { v = s }
        return v
    }

    /// Apple Music's card corner while it's dragged (traced: the card's corner radii are 14.16 pt at release, then
    /// animate to the bar's 24 pt as it lands).
    static let dragCornerRadius: CGFloat = 14.16

    func follow(_ dy: CGFloat) {
        guard let c = container else { return }
        if !dragging {
            dragging = true
            restCenter = c.center
            c.layer.cornerCurve = .continuous
            c.layer.masksToBounds = true
            UIView.animate(withDuration: 0.15) { c.layer.cornerRadius = Self.dragCornerRadius }
        }
        guard let rest = restCenter else { return }
        c.center = CGPoint(x: rest.x, y: rest.y + dy)
    }

    /// Finger lifted to dismiss: leave the card where it is (the dismissal animates from its current frame).
    func release() {
        dragging = false
        restCenter = nil
    }

    /// Finger lifted without dismissing: back up on Apple Music's critically damped spring.
    func snapBack() {
        guard let c = container, let rest = restCenter else { dragging = false; return }
        dragging = false
        restCenter = nil
        UIView.animate(springDuration: 0.3441, bounce: 0) {
            c.center = rest
            c.layer.cornerRadius = 0
        }
    }
}

/// Hands back the view controller that hosts this view (the presented Now Playing controller).
private struct PresentedControllerReader: UIViewControllerRepresentable {
    let found: (UIViewController) -> Void
    func makeUIViewController(context: Context) -> Probe { Probe(found: found) }
    func updateUIViewController(_ uiViewController: Probe, context: Context) {}

    final class Probe: UIViewController {
        let found: (UIViewController) -> Void
        init(found: @escaping (UIViewController) -> Void) { self.found = found; super.init(nibName: nil, bundle: nil) }
        required init?(coder: NSCoder) { fatalError() }
        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            var top: UIViewController? = parent
            while let p = top?.parent { top = p }
            if let top { found(top) }
        }
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            var top: UIViewController = self
            while let p = top.parent { top = p }
            found(top)
        }
    }
}
