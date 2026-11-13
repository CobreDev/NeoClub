import AVKit
import MediaPlayer
import SwiftUI

// Now Playing's controls: scrubber, transport, volume, output, bookmark and menus.

/// Apple-style scrubber: a thin capsule with no thumb that thickens while dragging; times below.
struct ScrubberBar: View {
    @Environment(AudioPlayer.self) private var player
    @Environment(\.isOnScreen) private var isOnScreen
    /// Resets automatically if the drag is cancelled (e.g. by the sheet's dismiss gesture).
    @GestureState private var dragFraction: Double?
    /// Holds the released position until the seek lands, so the bar doesn't jump back.
    @State private var pendingFraction: Double?

    var body: some View {
        let total = max(player.duration, 1)
        // Hidden (the card behind the mini player), don't read the position at all, so ticks don't redraw it.
        let position = isOnScreen ? player.position : 0
        let fraction = dragFraction ?? pendingFraction ?? min(1, position / total)
        let dragging = dragFraction != nil
        VStack(spacing: 5.8) {
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
        .accessibilityValue(NowPlayingView.time(position))
        .accessibilityAdjustableAction { dir in player.skip(by: dir == .increment ? 30 : -15) }
    }
}

/// Thin system volume bar between speaker glyphs, like Apple Music.
struct VolumeBar: View {
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

private extension View {
    /// A menu label: 44 pt square as a transport button, or Up Next's full-width 37 pt capsule.
    @ViewBuilder func capsuleLabel(_ capsule: Bool) -> some View {
        if capsule {
            frame(maxWidth: .infinity).frame(height: 37)
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
                .capsuleLabel(capsule)
        }
        .accessibilityLabel("Playback speed")
    }
}

/// Moon sleep-timer control, as in Apple Podcasts.
struct SleepTimerButton: View {
    @Environment(AudioPlayer.self) private var player
    /// See `SpeedButton.capsule`.
    var capsule = false

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
            .capsuleLabel(capsule)
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
