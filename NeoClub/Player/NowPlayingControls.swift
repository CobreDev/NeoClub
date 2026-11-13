import AVKit
import MediaPlayer
import SwiftUI

// Now Playing's controls: scrubber, transport, volume, output, bookmark and menus.

/// Apple Music's scrubber (traced on iOS 27.2 in a vphone VM, 2026-11-13):
/// - Touching it, anywhere on the bar, grows the bar from 7 to 16 pt and scales the bar with its times to 105%, about
///   its centre (so it reaches past the margins); the times turn from 25% white to full white and sit 2 pt lower; the played
///   part goes from 45% to full. All on one spring (response 0.37 s, damping 0.79). Letting go springs back on a looser
///   one (response 0.39 s, damping 0.64), dipping a little under 7 pt on the way.
/// - The drag is relative: touching down doesn't move the position, moving the finger by a fraction of the bar's width
///   (as scaled up, so about 5% less than the resting width) moves it by that fraction of the duration, whatever the
///   finger's height, and only once it has moved about 8 pt. A tap does nothing.
struct ScrubberBar: View {
    @Environment(AudioPlayer.self) private var player
    @Environment(\.isOnScreen) private var isOnScreen
    /// Where the position was when the finger touched down, and how far the finger has moved along the bar. Resets
    /// automatically if the drag is cancelled (e.g. by the sheet's dismiss gesture).
    private struct Touch: Equatable {
        var start: Double
        var dx: CGFloat
        /// Music's drag only starts once the finger has moved about 8 pt (a 6 pt drag did nothing, 10 pt moved the whole
        /// distance: like a pan gesture's slop, the distance counts from where it went down).
        var moving: Bool
    }
    static let slop: CGFloat = 8
    /// The bar is 5% wider while held, and the finger's distance is measured against that wider bar (100 pt moved
    /// 43 s of 152 on Music's 338 pt bar: 100 / (338 * 1.05) of the duration).
    static let pressedScale: CGFloat = 1.05
    @GestureState private var touch: Touch?
    /// Holds the released position until the seek lands, so the bar doesn't jump back.
    @State private var pendingFraction: Double?

    static let grow = Animation.spring(response: 0.37, dampingFraction: 0.79)
    static let release = Animation.spring(response: 0.39, dampingFraction: 0.64)

    var body: some View {
        let total = max(player.duration, 1)
        // Hidden (the card behind the mini player), don't read the position at all, so ticks don't redraw it.
        let position = isOnScreen ? player.position : 0
        let resting = pendingFraction ?? min(1, position / total)
        let pressed = touch != nil
        // Where the finger would leave it; the times use it too, so it is worked out from the measured bar width.
        let fraction = touch.map { min(1, max(0, $0.start + ($0.moving ? Double($0.dx / (barWidth * Self.pressedScale)) : 0))) } ?? resting
        VStack(spacing: 5.8) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.25))
                    Capsule().fill(.white.opacity(pressed ? 1 : 0.7))
                        .frame(width: max(0, g.size.width * fraction))
                }
                .frame(height: pressed ? 16 : 7)
                .frame(maxHeight: .infinity)
                .contentShape(.rect)
                .highPriorityGesture(DragGesture(minimumDistance: 0)
                    .updating($touch) { v, state, _ in
                        let moving = (state?.moving ?? false) || abs(v.translation.width) >= Self.slop
                        state = Touch(start: state?.start ?? resting, dx: v.translation.width, moving: moving)
                    }
                    .onEnded { v in
                        guard abs(v.translation.width) >= Self.slop else { return }
                        let f = min(1, max(0, resting + Double(v.translation.width / (g.size.width * Self.pressedScale))))
                        pendingFraction = f
                        player.seek(to: f * total)
                        Task { try? await Task.sleep(for: .milliseconds(600)); pendingFraction = nil }
                    })
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { barWidth = max($0, 1) }
            }
            .frame(height: 20)
            HStack {
                Text(NowPlayingView.time(fraction * total))
                Spacer()
                Text("-" + NowPlayingView.time(max(0, total - fraction * total)))
            }
            .font(.universBold(12, relativeTo: .caption).monospacedDigit())
            .opacity(pressed ? 1 : 0.5)
            .offset(y: pressed ? 2.1 : 0)
        }
        .scaleEffect(pressed ? Self.pressedScale : 1)
        .animation(pressed ? Self.grow : Self.release, value: pressed)
        .accessibilityElement()
        .accessibilityLabel("Playback position")
        .accessibilityValue(NowPlayingView.time(position))
        .accessibilityAdjustableAction { dir in player.skip(by: dir == .increment ? 30 : -15) }
    }

    @State private var barWidth: CGFloat = 1
}

/// The system volume bar with speaker glyphs, like Apple Music.
struct VolumeBar: View {
    /// CarPlay (and other routes the phone can't set the volume of) hide MPVolumeView's slider, leaving only the
    /// speaker glyphs. Music keeps the track there, dimmed and empty, so we draw that instead.
    @State private var fixedVolume = VolumeBar.routeHasFixedVolume()

    private static func routeHasFixedVolume() -> Bool {
        AVAudioSession.sharedInstance().currentRoute.outputs.contains { $0.portType == .carAudio }
    }

    private static let glyphSize: CGFloat = 14
    private static let glyphOpacity = 0.6

    var body: some View {
        Group {
            #if targetEnvironment(simulator)
            // The simulator has no system volume control; show the track so layout matches a device.
            stand(in: Capsule().fill(.white.opacity(0.25)).frame(height: 7)
                .overlay(alignment: .leading) { GeometryReader { g in Capsule().fill(.white.opacity(0.7)).frame(width: g.size.width * 0.6) } })
            #else
            if fixedVolume {
                stand(in: Capsule().fill(.white.opacity(0.25)).frame(height: 7).frame(height: 20))
            } else {
                SystemVolume().frame(height: 20)
            }
            #endif
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { _ in
            fixedVolume = Self.routeHasFixedVolume()
        }
    }

    /// A drawn track between the speaker glyphs, laid out like Music's slider (14 pt glyphs 11 pt from the track).
    private func stand(in track: some View) -> some View {
        HStack(spacing: 11) {
            Image(systemName: "speaker.fill").font(.system(size: Self.glyphSize)).opacity(Self.glyphOpacity)
            track
            Image(systemName: "speaker.3.fill").font(.system(size: Self.glyphSize)).opacity(Self.glyphOpacity)
        }
    }

    /// Music's volume slider is UIKit's thumbless slider (`sliderStyle = .thumbless`, "typically for media playback"):
    /// touching it grows the track from 7 to 16 pt and brightens the played part on a spring, like the scrubber's.
    /// MPVolumeView's own slider is that same class, so it gets the style (it is created lazily, hence at layout).
    private final class ThumblessVolumeView: MPVolumeView {
        override func layoutSubviews() {
            super.layoutSubviews()
            for case let slider as UISlider in allSubviews where slider.sliderStyle != .thumbless {
                slider.sliderStyle = .thumbless
                slider.minimumTrackTintColor = UIColor.white.withAlphaComponent(0.7)
                slider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.25)
                // The speaker glyphs are the slider's own value images, as in Music's (14 pt `speaker.fill` and
                // `speaker.3.fill`): the thumbless slider's rubber band pushes them a few points when the volume is
                // dragged past either end.
                let config = UIImage.SymbolConfiguration(pointSize: 14)
                slider.minimumValueImage = UIImage(systemName: "speaker.fill", withConfiguration: config)
                slider.maximumValueImage = UIImage(systemName: "speaker.3.fill", withConfiguration: config)
                slider.tintColor = UIColor.white.withAlphaComponent(0.6)
            }
        }
        private var allSubviews: [UIView] {
            var all: [UIView] = [], queue = subviews
            while let v = queue.popLast() { all.append(v); queue += v.subviews }
            return all
        }
    }

    private struct SystemVolume: UIViewRepresentable {
        func makeUIView(context: Context) -> MPVolumeView {
            let v = ThumblessVolumeView()
            v.tintColor = UIColor.white.withAlphaComponent(0.7)
            return v
        }
        func updateUIView(_ uiView: MPVolumeView, context: Context) {}
    }
}

private extension View {
    /// A menu label: 44 pt square as a transport button, or Up Next's full-width 37 pt capsule.
    @ViewBuilder func capsuleLabel(_ capsule: Bool, height: CGFloat = 37) -> some View {
        if capsule {
            frame(maxWidth: .infinity).frame(height: height)
                .background(.white.opacity(0.14), in: .capsule)
                .contentShape(.capsule)
        } else {
            frame(width: 44, height: 44)
        }
    }
}

/// "1×" playback-speed control, as in Apple Podcasts.
struct SpeedButton: View {
    @Environment(AudioPlayer.self) private var player
    /// Up Next's wide capsule: the capsule itself is the menu's label, so the menu opens from (and closes back into)
    /// the capsule rather than a 44 pt circle, and the text is at full strength (dimmed it read as disabled).
    var capsule = false
    var height: CGFloat = 37
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
                .opacity(player.rate == 1 && !capsule ? 0.6 : 1)
                .capsuleLabel(capsule, height: height)
        }
        .accessibilityLabel("Playback speed")
    }
}

/// Moon sleep-timer control, as in Apple Podcasts.
struct SleepTimerButton: View {
    @Environment(AudioPlayer.self) private var player
    /// See `SpeedButton.capsule`.
    var capsule = false
    var height: CGFloat = 37

    var body: some View {
        Menu {
            Button("End of Episode") { player.setSleepTimer(.endOfEpisode) }
            ForEach([60, 45, 30, 15, 5], id: \.self) { m in
                Button("\(m) Minutes") { player.setSleepTimer(.minutes(m)) }
            }
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
                        .foregroundStyle(player.sleepTimer == .off ? Color.white.opacity(capsule ? 1 : 0.6) : Color.aioYellow)
                }
            }
            .capsuleLabel(capsule, height: height)
        }
        .accessibilityLabel("Sleep timer")
    }
}

/// The ⋯ menu: share, go to album/episode, download, playback speed.
struct EpisodeMenu: View {
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
struct NowPlayingBookmark: View {
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

/// Apple Music's play/pause button, from a 60 fps recording on the Duo: touching it fades in a faint ~60 pt
/// circle behind the glyph; on release the glyph dims and shrinks to nothing (~70 ms), swaps, and grows back while
/// brightening (~0.25 s); the circle lingers ~130 ms after release, then fades.
struct PlayPauseButton: View {
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
