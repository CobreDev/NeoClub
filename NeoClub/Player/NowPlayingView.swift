import AVKit
import MediaPlayer
import SwiftUI

/// Now Playing card, laid out like Apple Music (iOS 27) on every screen, in AIO typefaces:
/// - Portrait (phones, the iPhone Duo outer screen, Duo inner screen upright): artwork, title row, scrubber,
///   transport, volume, bottom bar. Up Next / Info replace the artwork under a compact header.
/// - Landscape inner screen: artwork and controls in a centered column; Up Next / Info open as a column on the right;
///   the output route sits bottom-left and the Info / Up Next buttons bottom-right.
/// - Half-folded upright (laptop): artwork or Up Next on the top half, title and controls on the bottom half.
struct NowPlayingView: View {
    @Environment(AudioPlayer.self) private var player
    /// The card host draws the backdrop itself (full-bleed), so the player can be inset to the safe area.
    var drawsBackground = true
    /// The screen's safe-area insets (the card pads the player by them). Used to place things relative to the
    /// screen's edges the way Apple Music does: the grabber, the side margins and the bottom row.
    var insets = EdgeInsets()
    @State private var mode: Mode = .artwork
    @State private var halfFolded = false
    /// Shared between the big artwork/title and the small header, so switching to Up Next moves the same artwork
    /// and title into place (Apple Music) instead of cross-fading two copies.
    @Namespace private var ns

    enum Mode { case artwork, info, queue }

    /// Apple Music's switch between the player and Up Next, measured frame by frame on iOS 27.2: the artwork and
    /// column move on a critically damped spring with a ~0.33 s response, starting at the tap.
    static let modeAnimation = Animation.spring(response: 0.33, dampingFraction: 1.0)
    /// The list doesn't move: it fades in where it sits a beat after the artwork starts moving, and on the way back
    /// stays put while the artwork slides over it, then fades out.
    static let panelTransition = AnyTransition.asymmetric(
        insertion: .opacity.animation(.easeOut(duration: 0.2).delay(0.1)),
        removal: .opacity.animation(.easeIn(duration: 0.15).delay(0.05)))

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let landscape = size.width > size.height && size.width >= 700
            Group {
                if landscape {
                    landscapeLayout(size)
                } else if halfFolded {
                    laptopLayout(size)
                } else {
                    portraitLayout(size)
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .foregroundStyle(.white)
        .background { if drawsBackground { NowPlayingBackdrop() } }
        .animation(.spring(response: 0.45, dampingFraction: 0.9), value: halfFolded)
        .readsHinge($halfFolded)
        .presentationDragIndicator(.hidden)
        .presentationBackground(Color.aioNavy)
    }

    /// Grabber centered ~21 pt below the screen's top edge on the outer screen and ~23 pt on the inner screen
    /// (Apple Music), whatever the top inset: on the inner screen upright the inset is ~89 pt and Music ignores it.
    private func grabberTop(large: Bool) -> CGFloat { (large ? 10 : 9) - insets.top }

    /// The grabber; tapping it closes Now Playing, like Apple Music.
    private func grabber(large: Bool = false) -> some View {
        Button { player.showNowPlaying = false } label: {
            Capsule().fill(.white.opacity(0.35)).frame(width: 36, height: 5)
                .frame(width: 120, height: 24)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.top, grabberTop(large: large))
        .accessibilityLabel("Close Now Playing")
    }

    // MARK: Layouts

    /// Portrait (phone width, the Duo's outer screen, or the inner screen upright), measured from Apple Music on the
    /// iPhone Duo: a column 32 pt in from the screen's edges (up to 513 pt wide, centered on the big screen); the
    /// controls are anchored to the bottom with the output label ~23 pt above the screen edge; the artwork fills
    /// what's left above, 21 pt over the title. The controls never move when Up Next opens.
    private func portraitLayout(_ size: CGSize) -> some View {
        let narrow = size.width < 500
        let lead = narrow ? max(0, 32 - insets.leading) : 28
        let trail = narrow ? max(0, 32 - insets.trailing) : 28
        let content = min(size.width - lead - trail, 513)
        let large = size.height > 800
        return VStack(spacing: 0) {
            grabber(large: large)
            VStack(spacing: 0) {
                if mode == .artwork {
                    // Music's artwork starts ~14 pt under the grabber on the Duo's 466 × 678 pt inner screen.
                    Spacer(minLength: large ? 22 : 14)
                    // Up to the column width, smaller when the screen is short, so the controls below never move.
                    bigArtwork.frame(maxWidth: content, maxHeight: content)
                    titleRow(large: large).padding(.top, 21)
                } else {
                    compactHeader.padding(.top, 18)
                    if narrow { modeCapsules.padding(.top, 16) }
                    panel.padding(.top, 16)
                }
            }
            .frame(maxHeight: .infinity, alignment: mode == .artwork ? .bottom : .top)
            controls(narrow: narrow, large: large)
        }
        .frame(width: content)
        .padding(.leading, narrow ? lead : 0)
        .frame(maxWidth: .infinity, alignment: narrow ? .leading : .center)
        // Output label ~23 pt above the screen's bottom edge, whatever the home-indicator inset.
        .padding(.bottom, 16 - insets.bottom)
    }

    /// Scrubber, transport, volume and the bottom buttons: the part that never moves. Gaps measured from Apple
    /// Music on the Duo's outer screen (compact) and its inner screen upright (large, overlaid on a vphone
    /// screenshot of Music: title caps at 673, album 699, scrubber 749, transport 822, volume 896, buttons 965).
    private func controls(narrow: Bool, large: Bool) -> some View {
        VStack(spacing: 0) {
            ScrubberBar().padding(.top, large ? 16.5 : 11)
            transport(narrow: narrow).padding(.top, large ? 11 : 0)
            VolumeBar().padding(.top, large ? 31 : 26)
            bottomBar.padding(.top, large ? 34 : 22)
        }
    }

    private func laptopLayout(_ size: CGSize) -> some View {
        // The top half stands upright to look at; the controls sit on the bottom half, below the crease.
        let content = min(size.width - 56, 513)
        let half = size.height / 2
        return VStack(spacing: 0) {
            Group {
                if mode == .artwork {
                    let side = min(content, half - 60)
                    bigArtwork.frame(width: side, height: side)
                } else {
                    VStack(spacing: 0) {
                        compactHeader
                        panel.padding(.top, 16)
                    }
                    .padding(.top, 20)
                }
            }
            .frame(height: half)

            VStack(spacing: 0) {
                if mode == .artwork { titleRow() } else { Color.clear.frame(height: 1) }
                Spacer(minLength: 10)
                ScrubberBar()
                Spacer(minLength: 10)
                transport(narrow: false)
                Spacer(minLength: 10)
                VolumeBar()
                Spacer(minLength: 10)
                bottomBar.padding(.bottom, 6)
            }
            .padding(.top, 24)
            .frame(height: half)
        }
        .frame(width: content)
        .frame(maxWidth: .infinity)
    }

    /// Landscape inner screen (Apple Music on a wide screen): a ~400 pt column with 330 pt artwork, centered; with
    /// Up Next open, the column moves to the middle of the left half and the list fills a column on the right.
    private func landscapeLayout(_ size: CGSize) -> some View {
        let column: CGFloat = 400
        let art = min(330, size.height * 0.48)
        return VStack(spacing: 0) {
            grabber()
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    Spacer(minLength: 8)
                    bigArtwork.frame(width: art, height: art)
                    Spacer(minLength: 20)
                    titleRow()
                    ScrubberBar().padding(.top, 18)
                    transport(narrow: false).padding(.top, 18)
                    VolumeBar().padding(.top, 22)
                    Spacer(minLength: 8)
                }
                .frame(width: column)
                .frame(maxWidth: .infinity)

                if mode != .artwork {
                    panel
                        .padding(.top, 20)
                        .frame(width: min(size.width * 0.4, 380))
                        .padding(.trailing, 32)
                        .transition(Self.panelTransition)
                }
            }
            landscapeBottomBar
                .padding(.horizontal, 40)
                .padding(.bottom, 8)
        }
    }

    /// Landscape: output route bottom-left, Info and Up Next bottom-right (Apple Music on a wide screen).
    private var landscapeBottomBar: some View {
        HStack(spacing: 10) {
            RoutePicker(symbol: player.route.symbol, size: 17).frame(width: 30, height: 26)
            Text(player.outputName)
                .font(.univers(13, relativeTo: .caption))
                .opacity(0.6)
                .lineLimit(1)
            Spacer()
            toggle(.info, symbol: "info.circle", label: "About This Episode")
            toggle(.queue, symbol: "list.bullet", label: "Up Next")
        }
        .frame(height: 44)
    }

    /// The player's loaded artwork (no reload while it moves), falling back to loading it.
    private func artworkImage(cornerRadius: CGFloat) -> some View {
        Group {
            if let image = player.artworkImage {
                Color.clear.aspectRatio(1, contentMode: .fit)
                    .overlay { Image(uiImage: image).resizable().scaledToFill() }
                    .clipShape(.rect(cornerRadius: cornerRadius))
            } else {
                Artwork(url: player.episode?.artworkURL, cornerRadius: cornerRadius)
            }
        }
    }

    private var bigArtwork: some View {
        artworkImage(cornerRadius: 10)
            .matchedGeometryEffect(id: "artwork", in: ns)
            .shadow(color: .black.opacity(player.isPlaying ? 0.45 : 0.2), radius: player.isPlaying ? 28 : 10, y: 14)
            // Paused, Apple Music shrinks the artwork to ~73%. Fitted from a 60 fps recording of Music on the Duo:
            // playing, it grows on a bouncy spring (~11% overshoot) a beat after the button's glyph swaps;
            // pausing, it shrinks on a nearly critically damped spring with no overshoot.
            .scaleEffect(player.isPlaying ? 1 : 0.73)
            .animation(player.isPlaying
                       ? .spring(response: 0.45, dampingFraction: 0.56).delay(0.1)
                       : .spring(response: 0.5, dampingFraction: 0.95).delay(0.05),
                       value: player.isPlaying)
    }

    private var panel: some View {
        Group {
            if mode == .info { InfoPanel() } else { QueuePanel() }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .transition(Self.panelTransition)
    }

    // MARK: Pieces

    /// Title over album (Apple: ~20pt semibold over ~20pt secondary), bookmark and ⋯ on the right.
    private func titleRow(large: Bool = false) -> some View {
        HStack(alignment: .center, spacing: 16) {
            titles(size: 20, lineSpacing: large ? -0.5 : -2)
            Spacer(minLength: 0)
            actions
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func titles(size: CGFloat, lineSpacing: CGFloat = -2) -> some View {
        VStack(alignment: .leading, spacing: lineSpacing) {
            // Long titles scroll to show the whole thing, like Apple Music.
            MarqueeText(text: player.episode?.numberedTitle ?? "", font: .universBold(size, relativeTo: .title3),
                        restartKey: PlayerCardModel.shared.visible)
            MarqueeText(text: player.episode?.albumTitle ?? "Adventures in Odyssey",
                        font: .univers(size, relativeTo: .title3), restartKey: PlayerCardModel.shared.visible)
                .opacity(0.6)
        }
        .matchedGeometryEffect(id: "titles", in: ns)
    }

    private var actions: some View {
        HStack(spacing: 16) {
            NowPlayingBookmark()
            EpisodeMenu()
        }
        .matchedGeometryEffect(id: "actions", in: ns)
    }

    /// Small artwork + title above Info / Up Next, like Apple Music's queue view (72 pt artwork).
    private var compactHeader: some View {
        HStack(spacing: 16) {
            artworkImage(cornerRadius: 8)
                .matchedGeometryEffect(id: "artwork", in: ns)
                .frame(width: 72, height: 72)
                .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                .onTapGesture { withAnimation(Self.modeAnimation) { mode = .artwork } }
            // Same size as under the big artwork (Apple Music), so the title slides instead of cross-fading.
            titles(size: 20)
            Spacer(minLength: 0)
            actions
        }
    }

    /// Narrow screens only (Apple Music's capsule row of shuffle / repeat in Up Next): speed and sleep timer
    /// move up here from the sides of the transport.
    private var modeCapsules: some View {
        HStack(spacing: 12) {
            SpeedButton().frame(maxWidth: .infinity, minHeight: 44).background(.white.opacity(0.14), in: .capsule)
            SleepTimerButton().frame(maxWidth: .infinity, minHeight: 44).background(.white.opacity(0.14), in: .capsule)
        }
        .transition(Self.panelTransition)
    }

    /// Podcasts transport: speed · back 15 · play · forward 30 · sleep timer. Narrow screens show only the middle
    /// three, like Apple Music's outer-screen player.
    private func transport(narrow: Bool) -> some View {
        HStack {
            if !narrow {
                SpeedButton().frame(width: 44)
                Spacer()
            }
            Button { player.skip(by: -15) } label: { Image(systemName: "gobackward.15").font(.system(size: 30, weight: .medium)) }
                .accessibilityLabel("Back 15 seconds")
            Spacer()
            // Music's pause bars are ~30 pt tall on the Duo's inner screen (38 pt type); larger on a big layout.
            PlayPauseButton(size: narrow ? 38 : 46)
            Spacer()
            Button { player.skip(by: 30) } label: { Image(systemName: "goforward.30").font(.system(size: 30, weight: .medium)) }
                .accessibilityLabel("Forward 30 seconds")
            if !narrow {
                Spacer()
                SleepTimerButton().frame(width: 44)
            }
        }
        .padding(.horizontal, narrow ? 54 : 0)
        .buttonStyle(.plain)
    }

    /// Info (where Apple has Lyrics/Transcript), AirPlay with the output name below it, and Up Next — the three
    /// buttons on one line, the label 25 pt below their centers (Apple Music).
    private var bottomBar: some View {
        HStack(alignment: .top) {
            toggle(.info, symbol: "info.circle", label: "About This Episode")
            Spacer()
            VStack(spacing: -2) {
                // The output's own glyph (AirPods, car, HomePod…), else AirPlay, like Apple Music.
                RoutePicker(symbol: player.route.symbol).frame(width: 40, height: 40)
                // Music names the output only when it isn't the phone itself; the line keeps its space either way,
                // so the buttons don't move.
                let name = player.route.label
                Text(name ?? " ")
                    .font(.universBold(12, relativeTo: .caption))
                    .opacity(name == nil ? 0 : 0.7)
                    .lineLimit(1)
            }
            Spacer()
            toggle(.queue, symbol: "list.bullet", label: "Up Next")
        }
    }

    private func toggle(_ target: Mode, symbol: String, label: String) -> some View {
        Button {
            withAnimation(Self.modeAnimation) { mode = (mode == target) ? .artwork : target }
        } label: {
            // Sized, weighted and tinted to Apple Music's Lyrics and Up Next buttons (vphone Duo): ~21 pt glyphs,
            // medium weight, white at ~73%.
            Image(systemName: symbol)
                .font(.system(size: 20.5, weight: .medium))
                .frame(width: 40, height: 40)
                .foregroundStyle(mode == target ? Color.black.opacity(0.75) : .white.opacity(0.73))
                .background { if mode == target { Circle().fill(.white.opacity(0.8)) } }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(mode == target ? .isSelected : [])
    }

    static func time(_ seconds: Double) -> String {
        let s = Int(seconds.rounded(.down))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// Apple-style scrubber: a thin capsule with no thumb that thickens while dragging; times below.
private struct ScrubberBar: View {
    @Environment(AudioPlayer.self) private var player
    /// Resets automatically if the drag is cancelled (e.g. by the sheet's dismiss gesture).
    @GestureState private var dragFraction: Double?
    /// Holds the released position until the seek lands, so the bar doesn't jump back.
    @State private var pendingFraction: Double?

    var body: some View {
        let total = max(player.duration, 1)
        let fraction = dragFraction ?? pendingFraction ?? min(1, player.position / total)
        let dragging = dragFraction != nil
        VStack(spacing: 4) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.25))
                    Capsule().fill(.white.opacity(dragging ? 0.95 : 0.7))
                        .frame(width: max(0, g.size.width * fraction))
                }
                .frame(height: dragging ? 12 : 7)
                .frame(maxHeight: .infinity)
                .contentShape(.rect)
                .highPriorityGesture(DragGesture(minimumDistance: 0)
                    .updating($dragFraction) { v, state, _ in state = min(1, max(0, v.location.x / g.size.width)) }
                    .onEnded { v in
                        let f = min(1, max(0, v.location.x / g.size.width))
                        pendingFraction = f
                        player.seek(to: f * total)
                        Task { try? await Task.sleep(for: .milliseconds(600)); pendingFraction = nil }
                    })
                .animation(.spring(response: 0.25, dampingFraction: 0.8), value: dragging)
            }
            .frame(height: 20)
            HStack {
                Text(NowPlayingView.time(fraction * total))
                Spacer()
                Text("-" + NowPlayingView.time(max(0, total - fraction * total)))
            }
            .font(.universBold(12, relativeTo: .caption).monospacedDigit())
            .opacity(dragging ? 0.9 : 0.5)
        }
        .accessibilityElement()
        .accessibilityLabel("Playback position")
        .accessibilityValue(NowPlayingView.time(player.position))
        .accessibilityAdjustableAction { dir in player.skip(by: dir == .increment ? 30 : -15) }
    }
}

/// Thin system volume bar between speaker glyphs, like Apple Music.
private struct VolumeBar: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "speaker.fill").font(.system(size: 12)).opacity(0.6)
            #if targetEnvironment(simulator)
            // The simulator has no system volume control; show the track so layout matches a device.
            Capsule().fill(.white.opacity(0.25)).frame(height: 7)
                .overlay(alignment: .leading) { GeometryReader { g in Capsule().fill(.white.opacity(0.7)).frame(width: g.size.width * 0.6) } }
            #else
            SystemVolume().frame(height: 20)
            #endif
            Image(systemName: "speaker.wave.3.fill").font(.system(size: 12)).opacity(0.6)
        }
    }

    private struct SystemVolume: UIViewRepresentable {
        func makeUIView(context: Context) -> MPVolumeView {
            let v = MPVolumeView()
            v.setVolumeThumbImage(UIImage(), for: .normal)
            v.tintColor = UIColor.white.withAlphaComponent(0.7)
            return v
        }
        func updateUIView(_ uiView: MPVolumeView, context: Context) {}
    }
}

/// "1×" playback-speed control, as in Apple Podcasts.
private struct SpeedButton: View {
    @Environment(AudioPlayer.self) private var player
    private let speeds: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    var body: some View {
        @Bindable var player = player
        Menu {
            Picker("Playback Speed", selection: $player.rate) {
                ForEach(speeds.reversed(), id: \.self) { s in Text(String(format: "%g×", s)).tag(s) }
            }
        } label: {
            Text(String(format: "%g×", player.rate))
                .font(.universBold(15, relativeTo: .subheadline))
                .opacity(player.rate == 1 ? 0.6 : 1)
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel("Playback speed")
    }
}

/// Moon sleep-timer control, as in Apple Podcasts.
private struct SleepTimerButton: View {
    @Environment(AudioPlayer.self) private var player

    var body: some View {
        Menu {
            Button("End of Episode") { player.setSleepTimer(.endOfEpisode) }
            ForEach([60, 45, 30, 15, 5], id: \.self) { m in
                Button("\(m) Minutes") { player.setSleepTimer(.minutes(m)) }
            }
            #if DEBUG
            Button("10 Seconds (Debug)") { player.setSleepTimer(.seconds(10)) }
            #endif
            if player.sleepTimer != .off {
                Divider()
                Button("Turn Off Timer", role: .destructive) { player.setSleepTimer(.off) }
            }
        } label: {
            Group {
                if let end = player.sleepEndsAt {
                    Text(timerInterval: Date()...end, countsDown: true)
                        .font(.universBold(12, relativeTo: .caption).monospacedDigit())
                        .foregroundStyle(Color.aioYellow)
                } else {
                    Image(systemName: player.sleepTimer == .off ? "moon.zzz" : "moon.zzz.fill")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(player.sleepTimer == .off ? Color.white.opacity(0.6) : Color.aioYellow)
                }
            }
            .frame(width: 44, height: 44)
        }
        .accessibilityLabel("Sleep timer")
    }
}

/// The ⋯ menu: share, go to album/episode, download, playback speed.
private struct EpisodeMenu: View {
    @Environment(AudioPlayer.self) private var player
    @Environment(DownloadStore.self) private var downloads
    @Environment(BookmarkStore.self) private var bookmarks

    var body: some View {
        Menu {
            if let e = player.episode {
                ShareLink(item: URL(string: "https://app.adventuresinodyssey.com/content/\(e.id)")!,
                          subject: Text(e.title)) {
                    Label("Share Episode", systemImage: "square.and.arrow.up")
                }
                if let gid = player.groupingID {
                    Button("Go to Album", systemImage: "square.stack") {
                        player.navigationRequest = .grouping(id: gid, preview: nil)
                    }
                }
                Button("Go to Episode", systemImage: "info.circle") {
                    player.navigationRequest = .episode(e, groupingID: player.groupingID)
                }
                Divider()
                if bookmarks.isBookmarked(e) {
                    Button("Remove Bookmark", systemImage: "bookmark.slash") { bookmarks.toggle(e) }
                } else {
                    Button("Bookmark", systemImage: "bookmark") { bookmarks.toggle(e) }
                }
                if downloads.isDownloaded(e.id) {
                    Button("Remove Download", systemImage: "trash", role: .destructive) { downloads.delete(e.id) }
                } else if downloads.active[e.id] != nil {
                    Button("Cancel Download", systemImage: "xmark.circle") { downloads.cancel(e.id) }
                } else if e.isPlayable {
                    Button("Download", systemImage: "arrow.down.circle") { downloads.download(e) }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 22, weight: .bold))
                .frame(width: 36, height: 36)
                .contentShape(.rect)
        }
        .accessibilityLabel("More")
    }
}

/// "About This Episode": details for what's playing (replaces Apple Music's Lyrics).
private struct InfoPanel: View {
    @Environment(AudioPlayer.self) private var player

    var body: some View {
        ScrollView {
            if let e = player.episode {
                VStack(alignment: .leading, spacing: 16) {
                    Text("About This Episode").font(.jacoby(24, relativeTo: .title2))
                    VStack(alignment: .leading, spacing: 8) {
                        if let n = e.episodeNumber, !n.isEmpty { fact("Episode", "#\(n)") }
                        if let album = e.albumTitle { fact("Album", album) }
                        if let aired = Self.airDate(e.airDate) { fact("First aired", aired) }
                        if let ms = e.mediaLength, ms > 0 { fact("Length", ms.msDurationText) }
                    }
                    if let d = e.description, !d.isEmpty {
                        Text(d).font(.univers(17)).opacity(0.9)
                    }
                    if let cast = e.characters, !cast.isEmpty {
                        Text("Characters").font(.universBold(17)).padding(.top, 4)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 14) {
                                ForEach(cast) { c in
                                    VStack(spacing: 6) {
                                        AsyncImage(url: .aio(c.thumbnailSmall)) { $0.resizable().scaledToFill() } placeholder: { Color.white.opacity(0.15) }
                                            .frame(width: 60, height: 60).clipShape(Circle())
                                        Text(c.name ?? "").font(.univers(12)).lineLimit(2).multilineTextAlignment(.center).frame(width: 72)
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .scrollIndicators(.hidden)
        .bottomFade()
    }

    private func fact(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.univers(15)).opacity(0.6).frame(width: 96, alignment: .leading)
            Text(value).font(.universBold(15))
        }
    }

    static func airDate(_ s: String?) -> String? {
        guard let s else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let d = f.date(from: s) ?? ISO8601DateFormatter().date(from: s) else { return nil }
        return d.formatted(date: .long, time: .omitted)
    }
}

/// Up Next (rest of the album) and History, like Apple Music's queue view.
private struct QueuePanel: View {
    @Environment(AudioPlayer.self) private var player

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                header("Up Next", subtitle: player.episode?.albumTitle.map { "From \($0)" })
                if player.queue.isEmpty {
                    Text("Nothing queued after this episode.").font(.univers(15)).opacity(0.6).padding(.vertical, 10)
                } else {
                    ForEach(player.queue) { e in
                        Button { player.playQueued(e) } label: {
                            row(title: e.title, subtitle: e.subtitle, art: e.smallArtworkURL)
                        }
                        .buttonStyle(.plain)
                    }
                }
                let past = player.history.filter { $0.id != player.episode?.id }
                if !past.isEmpty {
                    header("History", subtitle: nil).padding(.top, 18)
                    ForEach(past.prefix(25)) { h in
                        Button { player.playFromHistory(h) } label: {
                            row(title: h.title, subtitle: h.album ?? h.playedAt.formatted(.relative(presentation: .named)),
                                art: .aio(h.artwork))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        .bottomFade()
    }

    private func header(_ title: String, subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.universBold(20))
            if let subtitle { Text(subtitle).font(.univers(14)).opacity(0.6) }
        }
        .padding(.bottom, 8)
    }

    private func row(title: String, subtitle: String, art: URL?) -> some View {
        HStack(spacing: 12) {
            Artwork(url: art, cornerRadius: 6).frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.univers(16)).lineLimit(1)
                Text(subtitle).font(.univers(13)).opacity(0.6).lineLimit(1)
            }
            Spacer()
        }
        .padding(.vertical, 6)
        .contentShape(.rect)
    }
}

/// The system output picker (tapping it opens iOS's own route list) showing the current output's glyph, like
/// Apple Music's button: the picker's own glyph is always AirPlay, so it's drawn clear over an SF Symbol.
struct RoutePicker: View {
    var symbol: String = AudioRoute.airPlay
    /// Glyph size; ~21 pt matches Apple Music's bottom row on the Duo.
    var size: CGFloat = 21

    var body: some View {
        ZStack {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .contentTransition(.symbolEffect(.replace))
                .accessibilityHidden(true)
            SystemPicker()
        }
    }

    private struct SystemPicker: UIViewRepresentable {
        func makeUIView(context: Context) -> AVRoutePickerView {
            let v = AVRoutePickerView()
            v.tintColor = .clear
            v.activeTintColor = .clear
            v.prioritizesVideoDevices = false
            return v
        }
        func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
    }
}

/// Bookmark toggle beside ⋯, where Apple Music has its favorite star.
private struct NowPlayingBookmark: View {
    @Environment(AudioPlayer.self) private var player
    @Environment(BookmarkStore.self) private var bookmarks

    var body: some View {
        if let e = player.episode {
            let on = bookmarks.isBookmarked(e)
            Button { bookmarks.toggle(e) } label: {
                Image(systemName: on ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 22, weight: .regular))
                    .frame(width: 32, height: 32)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(on ? "Remove Bookmark" : "Bookmark")
        }
    }
}

private extension View {
    /// Tracks whether a foldable iPhone (iPhone Duo) is half-folded, via `onHingeChange` (iOS 27.1+).
    @ViewBuilder func readsHinge(_ halfFolded: Binding<Bool>) -> some View {
        if #available(iOS 27.1, *) {
            onHingeChange { _, context in
                halfFolded.wrappedValue = context.hinge?.status == .partiallyOpen
            }
        } else {
            self
        }
    }
}

extension View {
    /// Apple Music's Up Next edge: the list fades out over its last 44 pt as it runs into the scrubber, with room
    /// at the end so the last row can scroll fully clear of the fade. (The system soft scroll edge only draws
    /// under bars, and there's no bar here.)
    func bottomFade(_ height: CGFloat = 44) -> some View {
        self
            .contentMargins(.bottom, height, for: .scrollContent)
            .mask {
                VStack(spacing: 0) {
                    Color.black
                    LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                        .frame(height: height)
                }
            }
    }
}

/// Blurred cover art over the brand navy, behind the Now Playing card.
struct NowPlayingBackdrop: View {
    @Environment(AudioPlayer.self) private var player

    var body: some View {
        Color.aioNavy
            .overlay {
                AsyncImage(url: player.episode?.artworkURL) { $0.resizable().scaledToFill() } placeholder: { Color.clear }
                    .blur(radius: 80)
                    .saturation(1.3)
                    .opacity(0.7)
            }
            .overlay(LinearGradient(colors: [.black.opacity(0.1), .black.opacity(0.45)], startPoint: .top, endPoint: .bottom))
            .clipped()
            .ignoresSafeArea()
    }
}

/// Apple Music's play/pause button, from a 60 fps recording on the Duo: touching it fades in a faint ~60 pt
/// circle behind the glyph; on release the glyph dims and shrinks to nothing (~70 ms), swaps, and grows back while
/// brightening (~0.25 s); the circle lingers ~130 ms after release, then fades.
private struct PlayPauseButton: View {
    @Environment(AudioPlayer.self) private var player
    let size: CGFloat

    @State private var shownPlaying: Bool?
    @State private var glyphScale: CGFloat = 1
    @State private var dimmed = false
    @State private var pressed = false
    @State private var highlighted = false
    @State private var pressCount = 0

    var body: some View {
        Button {
            player.togglePlayPause()
            // A quick tap may never register as held; show the circle anyway (Music always does).
            if !highlighted { showHighlight() ; releaseHighlight() }
        } label: {
            ZStack {
                Circle().fill(.white.opacity(0.08))
                    .frame(width: 60, height: 60)
                    .opacity(highlighted ? 1 : 0)
                if player.isLoading {
                    ProgressView().tint(.white).controlSize(.large)
                } else {
                    Image(systemName: (shownPlaying ?? player.isPlaying) ? "pause.fill" : "play.fill")
                        .font(.system(size: size))
                        .scaleEffect(glyphScale)
                        .opacity(dimmed ? 0.7 : 1)
                }
            }
            .frame(width: 64, height: 56)
            .contentShape(.rect)
        }
        .buttonStyle(PressReporting(pressed: $pressed))
        .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
        .onChange(of: player.isPlaying) { _, playing in swapGlyph(to: playing) }
        .onChange(of: pressed) { _, down in
            if down { showHighlight() } else { releaseHighlight() }
        }
    }

    private func showHighlight() {
        pressCount += 1
        withAnimation(.easeOut(duration: 0.07)) { highlighted = true }
    }

    private func releaseHighlight() {
        pressCount += 1
        let n = pressCount
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            guard n == pressCount else { return }
            withAnimation(.easeOut(duration: 0.17)) { highlighted = false }
        }
    }

    /// Shrinks to ~20% while dimming, swaps, and grows straight back (no pause at the smallest size).
    private func swapGlyph(to playing: Bool) {
        withAnimation(.easeIn(duration: 0.07)) {
            glyphScale = 0.2
            dimmed = true
        } completion: {
            shownPlaying = playing
            withAnimation(.easeOut(duration: 0.2)) { glyphScale = 1 }
            withAnimation(.easeOut(duration: 0.22)) { dimmed = false }
        }
    }

    /// Plain button that reports whether it's held down (no system dimming; the circle shows the press).
    private struct PressReporting: ButtonStyle {
        @Binding var pressed: Bool
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .onChange(of: configuration.isPressed) { _, down in pressed = down }
        }
    }
}
