import AVKit
import MediaPlayer
import SwiftUI

/// Full-screen player matching Apple Podcasts / Music layout and proportions, in AIO typefaces:
/// artwork (or Info / Up Next), title row with ⋯, capsule scrubber, transport, volume, bottom bar.
struct NowPlayingView: View {
    @Environment(AudioPlayer.self) private var player
    @State private var mode: Mode = .artwork

    enum Mode { case artwork, info, queue }

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(.white.opacity(0.35)).frame(width: 36, height: 5).padding(.top, 7)

            if mode == .artwork {
                Spacer(minLength: 12)
                Artwork(url: player.episode?.artworkURL, cornerRadius: 10)
                    .shadow(color: .black.opacity(player.isPlaying ? 0.45 : 0.2), radius: player.isPlaying ? 28 : 10, y: 14)
                    .scaleEffect(player.isPlaying ? 1 : 0.78)
                    .animation(.spring(response: 0.5, dampingFraction: 0.7), value: player.isPlaying)
                    .frame(maxWidth: 520)
                    .transition(.scale(scale: 0.4, anchor: .topLeading).combined(with: .opacity))
                Spacer(minLength: 28)
                titleRow
            } else {
                compactHeader.padding(.top, 22)
                Group {
                    if mode == .info { InfoPanel() } else { QueuePanel() }
                }
                .padding(.top, 18)
                .frame(maxHeight: .infinity)
                .transition(.opacity)
            }

            ScrubberBar().padding(.top, mode == .artwork ? 22 : 12)
            transport.padding(.top, 22)
            VolumeBar().padding(.top, 26)
            bottomBar.padding(.top, 26).padding(.bottom, 6)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white)
        .background { background }
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: mode)
        .presentationDragIndicator(.hidden)
        .presentationBackground(Color.aioNavy)
    }

    // MARK: Pieces

    private var background: some View {
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

    /// Title over album (Apple: ~20pt semibold over ~20pt secondary), ⋯ on the right.
    private var titleRow: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 1) {
                Text(player.episode?.title ?? "")
                    .font(.universBold(20, relativeTo: .title3))
                    .lineLimit(1)
                Text(player.episode?.albumTitle ?? "Adventures in Odyssey")
                    .font(.univers(20, relativeTo: .title3))
                    .opacity(0.6)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            EpisodeMenu()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Small artwork + title shown above Info / Up Next, like Apple Music's queue view.
    private var compactHeader: some View {
        HStack(spacing: 14) {
            Artwork(url: player.episode?.smallArtworkURL, cornerRadius: 6)
                .frame(width: 64, height: 64)
                .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                .onTapGesture { mode = .artwork }
            VStack(alignment: .leading, spacing: 1) {
                Text(player.episode?.title ?? "").font(.universBold(17)).lineLimit(1)
                Text(player.episode?.albumTitle ?? "Adventures in Odyssey").font(.univers(17)).opacity(0.6).lineLimit(1)
            }
            Spacer(minLength: 0)
            EpisodeMenu()
        }
    }

    /// Podcasts transport: speed · back 15 · play · forward 30 · sleep timer.
    private var transport: some View {
        HStack {
            SpeedButton().frame(width: 44)
            Spacer()
            Button { player.skip(by: -15) } label: { Image(systemName: "gobackward.15").font(.system(size: 30, weight: .medium)) }
                .accessibilityLabel("Back 15 seconds")
            Spacer()
            Button { player.togglePlayPause() } label: {
                ZStack {
                    if player.isLoading {
                        ProgressView().tint(.white).controlSize(.large)
                    } else {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 46))
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
                .frame(width: 64, height: 56)
            }
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            Spacer()
            Button { player.skip(by: 30) } label: { Image(systemName: "goforward.30").font(.system(size: 30, weight: .medium)) }
                .accessibilityLabel("Forward 30 seconds")
            Spacer()
            SleepTimerButton().frame(width: 44)
        }
        .buttonStyle(.plain)
    }

    /// Info (where Apple has Lyrics/Transcript), AirPlay with output name, and Up Next.
    private var bottomBar: some View {
        HStack(alignment: .top) {
            toggle(.info, symbol: "info.circle", label: "About This Episode")
            Spacer()
            VStack(spacing: 4) {
                RoutePicker().frame(width: 30, height: 26)
                Text(player.outputName)
                    .font(.univers(12, relativeTo: .caption))
                    .opacity(0.6)
                    .lineLimit(1)
            }
            Spacer()
            toggle(.queue, symbol: "list.bullet", label: "Up Next")
        }
        .frame(height: 44)
    }

    private func toggle(_ target: Mode, symbol: String, label: String) -> some View {
        Button { mode = (mode == target) ? .artwork : target } label: {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .semibold))
                .frame(width: 40, height: 40)
                .foregroundStyle(mode == target ? Color.black.opacity(0.75) : .white.opacity(0.85))
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
    @State private var dragFraction: Double?

    var body: some View {
        let total = max(player.duration, 1)
        let fraction = dragFraction ?? min(1, player.position / total)
        let dragging = dragFraction != nil
        VStack(spacing: 8) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.25))
                    Capsule().fill(.white.opacity(dragging ? 0.95 : 0.7))
                        .frame(width: max(0, g.size.width * fraction))
                }
                .frame(height: dragging ? 12 : 7)
                .frame(maxHeight: .infinity)
                .contentShape(.rect)
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { v in dragFraction = min(1, max(0, v.location.x / g.size.width)) }
                    .onEnded { _ in
                        if let f = dragFraction { player.seek(to: f * total) }
                        dragFraction = nil
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
                .font(.system(size: 20, weight: .bold))
                .frame(width: 32, height: 32)
                .background(Circle().fill(.white.opacity(0.15)))
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

struct RoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.tintColor = .white
        v.activeTintColor = UIColor(Color.aioYellow)
        v.prioritizesVideoDevices = false
        return v
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
