import AVKit
import MediaPlayer
import SwiftUI

/// Full-screen player modeled on Apple Music: artwork (or Info / Up Next panels), ⋯ menu,
/// scrubber, transport, volume, and the three-button bottom bar.
struct NowPlayingView: View {
    @Environment(AudioPlayer.self) private var player
    @State private var scrubbing: Double?
    @State private var mode: Mode = .artwork

    enum Mode { case artwork, info, queue }

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(.white.opacity(0.4)).frame(width: 40, height: 5).padding(.top, 10)

            if mode == .artwork {
                Spacer(minLength: 16)
                Artwork(url: player.episode?.artworkURL, cornerRadius: 14)
                    .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
                    .scaleEffect(player.isPlaying ? 1 : 0.82)
                    .animation(.spring(response: 0.45, dampingFraction: 0.75), value: player.isPlaying)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: 420)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                Spacer(minLength: 20)
                titleRow
            } else {
                compactHeader.padding(.top, 18)
                Divider().overlay(.white.opacity(0.15)).padding(.vertical, 10)
                Group {
                    if mode == .info { InfoPanel() } else { QueuePanel() }
                }
                .frame(maxHeight: .infinity)
                .transition(.opacity)
            }

            scrubber.padding(.top, 16)
            transport.padding(.top, 14)
            VolumeSlider().frame(height: 34).padding(.top, 14)
            bottomBar.padding(.top, 14).padding(.bottom, 8)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white)
        .background { background }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: mode)
        .presentationDragIndicator(.hidden)
        .presentationBackground(Color.aioNavy)
    }

    // MARK: Pieces

    private var background: some View {
        Color.aioNavy
            .overlay {
                AsyncImage(url: player.episode?.artworkURL) { $0.resizable().scaledToFill() } placeholder: { Color.clear }
                    .blur(radius: 60)
                    .opacity(0.55)
            }
            .overlay(LinearGradient(colors: [.clear, .black.opacity(0.35)], startPoint: .top, endPoint: .bottom))
            .clipped()
            .ignoresSafeArea()
    }

    private var titleRow: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(player.episode?.title ?? "")
                    .font(.universBold(22, relativeTo: .title2))
                    .lineLimit(2)
                Text(player.episode?.albumTitle ?? "Adventures in Odyssey")
                    .font(.univers(17))
                    .opacity(0.7)
                    .lineLimit(1)
            }
            Spacer()
            EpisodeMenu()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Small artwork + title shown above the Info / Up Next panels, like Apple Music's queue view.
    private var compactHeader: some View {
        HStack(spacing: 14) {
            Artwork(url: player.episode?.smallArtworkURL, cornerRadius: 8)
                .frame(width: 64, height: 64)
                .onTapGesture { mode = .artwork }
            VStack(alignment: .leading, spacing: 2) {
                Text(player.episode?.title ?? "").font(.universBold(17)).lineLimit(1)
                Text(player.episode?.albumTitle ?? "Adventures in Odyssey").font(.univers(15)).opacity(0.7).lineLimit(1)
            }
            Spacer()
            EpisodeMenu()
        }
    }

    private var scrubber: some View {
        let shown = scrubbing ?? player.position
        let total = max(player.duration, 1)
        return VStack(spacing: 6) {
            Slider(value: Binding(get: { shown }, set: { scrubbing = $0 }), in: 0...total) { editing in
                if !editing, let target = scrubbing {
                    player.seek(to: target)
                    scrubbing = nil
                }
            }
            .tint(.white)
            HStack {
                Text(Self.time(shown))
                Spacer()
                Text("-" + Self.time(max(0, total - shown)))
            }
            .font(.system(size: 12, weight: .medium, design: .rounded).monospacedDigit())
            .opacity(0.65)
        }
    }

    private var transport: some View {
        HStack {
            Spacer()
            Button { player.skip(by: -15) } label: { Image(systemName: "gobackward.15").font(.system(size: 30)) }
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
                .frame(width: 72, height: 64)
            }
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            Spacer()
            Button { player.skip(by: 30) } label: { Image(systemName: "goforward.30").font(.system(size: 30)) }
                .accessibilityLabel("Forward 30 seconds")
            Spacer()
        }
        .buttonStyle(.plain)
    }

    /// Info (where Apple Music has Lyrics), AirPlay with the output name, and Up Next / History.
    private var bottomBar: some View {
        HStack(alignment: .top) {
            toggle(.info, symbol: "info.circle", label: "About This Episode")
            Spacer()
            VStack(spacing: 2) {
                RoutePicker().frame(width: 36, height: 30)
                Text(player.outputName)
                    .font(.univers(12, relativeTo: .caption))
                    .opacity(0.7)
                    .lineLimit(1)
            }
            Spacer()
            toggle(.queue, symbol: "list.bullet", label: "Up Next")
        }
    }

    private func toggle(_ target: Mode, symbol: String, label: String) -> some View {
        Button { mode = (mode == target) ? .artwork : target } label: {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .frame(width: 44, height: 44)
                .foregroundStyle(mode == target ? Color.aioNavy : .white)
                .background { if mode == target { Circle().fill(.white.opacity(0.85)) } }
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

/// The ⋯ menu: share, go to album/episode, download, playback speed.
private struct EpisodeMenu: View {
    @Environment(AudioPlayer.self) private var player
    @Environment(DownloadStore.self) private var downloads

    private let speeds: [Float] = [0.75, 1.0, 1.25, 1.5, 2.0]

    var body: some View {
        @Bindable var player = player
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
                Menu {
                    Picker("Playback Speed", selection: $player.rate) {
                        ForEach(speeds, id: \.self) { s in Text(s == 1 ? "1× (Normal)" : String(format: "%g×", s)).tag(s) }
                    }
                } label: {
                    Label("Playback Speed (\(String(format: "%g×", player.rate)))", systemImage: "gauge.with.dots.needle.50percent")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 18, weight: .bold))
                .frame(width: 36, height: 36)
                .glassEffect(.regular, in: .circle)
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

/// System volume slider (MPVolumeView) styled for the dark player.
private struct VolumeSlider: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.fill").font(.caption).opacity(0.7)
            SystemVolume()
            Image(systemName: "speaker.wave.3.fill").font(.caption).opacity(0.7)
        }
    }

    private struct SystemVolume: UIViewRepresentable {
        func makeUIView(context: Context) -> MPVolumeView {
            let v = MPVolumeView()
            v.tintColor = .white
            return v
        }
        func updateUIView(_ uiView: MPVolumeView, context: Context) {}
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
