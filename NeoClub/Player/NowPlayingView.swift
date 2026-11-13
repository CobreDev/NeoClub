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
        // Music's grabber, on a close: opacity keyframes 1, 0, 0 at 0, 0.5, 1 of 0.5 s on the default curve, so it's
        // gone after a quarter second (traced with Frida), well before the rest of the player has faded.
        .opacity(NowPlayingPresenter.shared.isClosing ? 0 : 1)
        .animation(.timingCurve(0.25, 0.1, 0.25, 1, duration: 0.25), value: NowPlayingPresenter.shared.isClosing)
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
        // Laid out from the screen's top edge, as Music is (it ignores the inner screen's ~89 pt top inset); the
        // grabber floats over the top instead of taking room, so the header and artwork are placed from the edge.
        return VStack(spacing: 0) {
            VStack(spacing: 0) {
                if mode == .artwork {
                    // Never closer to the top than just under the grabber; with room, the artwork sits on the title
                    // (Music on the inner screen upright: artwork top ~82 pt from the screen's top edge).
                    Spacer(minLength: large ? 44 : 47)
                    // Up to the column width, smaller when the screen is short, so the controls below never move.
                    bigArtwork.frame(maxWidth: content, maxHeight: content)
                    // Music: ~43 pt from the artwork's bottom to the title's middle on the inner screen upright.
                    titleRow(large: large).padding(.top, large ? 34 : 21)
                } else {
                    // Music's Up Next header artwork: ~32 pt from the screen's top on the inner screen upright.
                    compactHeader.padding(.top, large ? 32 : 51)
                    if narrow { modeCapsules.padding(.top, 7.2) }
                    panel.padding(.top, narrow ? 12.7 : 16)
                }
            }
            .frame(maxHeight: .infinity, alignment: mode == .artwork ? .bottom : .top)
            controls(narrow: narrow, large: large)
        }
        .frame(width: content)
        .frame(maxHeight: .infinity)
        // Centered on the column, as before; its top measured from the screen's edge (grabberTop allows for the inset).
        .overlay(alignment: .top) { grabber(large: large).padding(.top, insets.top) }
        .padding(.leading, narrow ? lead : 0)
        .frame(maxWidth: .infinity, alignment: narrow ? .leading : .center)
        .padding(.top, -insets.top)
        // Output label ~23 pt above the screen's bottom edge, whatever the home-indicator inset.
        .padding(.bottom, 16 - insets.bottom)
    }

    /// Scrubber, transport, volume and the bottom buttons: the part that never moves. Gaps measured from Apple
    /// Music on the Duo's outer screen (compact) and its inner screen upright (large, overlaid on a vphone
    /// screenshot of Music: title caps at 673, album 699, scrubber 749, transport 822, volume 896, buttons 965).
    private func controls(narrow: Bool, large: Bool) -> some View {
        VStack(spacing: 0) {
            // Large: from the user's screenshots of Music on the Duo's inner screen upright (2026-11-12), NeoClub sat
            // 2.4 pt low from the bottom row up, with 1.9 pt less over the transport and 3.8 pt less over the scrubber.
            // Gaps calibrated from the owner's device screenshots of Music (see the notes in HANDOFF.md). Do not retune
            // these to Music running in the vphone VM: Music's vertical layout depends on the safe-area insets, which
            // differ between the VM and the phone (VM Music sat 1 to 3 pt lower than the phone's at the bottom row
            // and volume and 12 pt lower at the artwork, growing upward). NeoClub's is anchored to the screen's
            // edges, so only the phone's numbers are right for it.
            ScrubberBar().padding(.top, large ? 20.3 : 11)
            transport(narrow: narrow).padding(.top, large ? 12.9 : 0)
            VolumeBar().padding(.top, large ? 31 : 26)
            bottomBar.padding(.top, large ? 36.4 : 22)
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
        // The grabber at the top edge (tap to close), over the layout so the halves stay put.
        .overlay(alignment: .top) { grabber(large: true) }
    }

    /// Landscape inner screen (Apple Music on a wide screen): a ~400 pt column with 330 pt artwork, centered; with
    /// Up Next open, the column moves to the middle of the left half and the list fills a column on the right.
    /// Measured from the user's screenshots of Music on the Duo's inner screen sideways (2026-11-12, in pt): artwork
    /// 330 pt from y 40, title ~34 pt under it, scrubber 53 pt lower, transport 59, volume 58, the bottom row 47 pt
    /// under the volume; with Up Next, a 343 pt list 16 pt in from the right and the column centered in what's left.
    private func landscapeLayout(_ size: CGSize) -> some View {
        let column: CGFloat = 400
        let art = min(330, size.height * 0.5)
        return VStack(spacing: 0) {
            grabber()
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    bigArtwork.frame(width: art, height: art)
                    titleRow().padding(.top, 23)
                    ScrubberBar().padding(.top, 12)
                    transport(narrow: false).padding(.top, 3)
                    VolumeBar().padding(.top, 22)
                }
                // Anchored to the bottom row, the volume ~47 pt over its middle.
                .padding(.bottom, 15)
                .frame(width: column)
                .frame(maxWidth: .infinity)
                // With Up Next closed, Music centres the column on the whole window (Frida: artwork centre x 475.7 of
                // 951, title at 276.7), not on what's left after the status column's inset; with the list open the
                // column sits in the left area as measured (list 16 pt in from the inset edge).
                .offset(x: mode == .artwork ? (insets.trailing - insets.leading) / 2 : 0)

                if mode != .artwork {
                    panel
                        .padding(.top, 20)
                        .frame(width: 343)
                        .padding(.trailing, 16)
                        .transition(Self.panelTransition)
                }
            }
            landscapeBottomBar
                .padding(.horizontal, 40)
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
        // Where it's drawn in the player, so the close can fly it into the mini player (it's hidden while that copy flies).
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(NowPlayingPresentation.space)) } action: { frame in
            NowPlayingPresenter.shared.artworkFrame = frame
            NowPlayingPresenter.shared.artworkCornerRadius = cornerRadius
        }
        .opacity(NowPlayingPresenter.shared.artworkFlying ? 0 : 1)
    }

    private var bigArtwork: some View {
        artworkImage(cornerRadius: 10)
            .matchedGeometryEffect(id: "artwork", in: ns)
            // A fixed blur that only fades (cheap to animate) rather than a shadow whose radius changes every frame,
            // which made the play/pause resize stutter.
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.black)
                    .blur(radius: 22)
                    .offset(y: 14)
                    .opacity(player.isPlaying ? 0.5 : 0.25)
                    // Gone with the artwork while a copy of it flies into the bar.
                    .opacity(NowPlayingPresenter.shared.artworkFlying ? 0 : 1)
            }
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
            MarqueeText(text: player.episode?.numberedTitle ?? "", font: .universBold(size, relativeTo: .title3))
            MarqueeText(text: player.episode?.albumTitle ?? "Adventures in Odyssey",
                        font: .univers(size, relativeTo: .title3))
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

    /// Small artwork + title above Info / Up Next, like Apple Music's queue view (72 pt artwork). Outer screen, from
    /// Frida on Music (2026-11-12): artwork 72 pt at y 41.8, then the 38 pt buttons 8.2 pt under it (y 122), the
    /// section header 21 pt under those, rows on a 56 pt pitch with 48 pt artwork.
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
            SpeedButton().frame(maxWidth: .infinity, minHeight: 38).background(.white.opacity(0.14), in: .capsule)
            SleepTimerButton().frame(maxWidth: .infinity, minHeight: 38).background(.white.opacity(0.14), in: .capsule)
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
