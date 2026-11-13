import AVKit
import MediaPlayer
import SwiftUI

// Now Playing's Info and Up Next panels, their bottom fade, and the backdrop.

/// "About This Episode": details for what's playing (replaces Apple Music's Lyrics).
struct InfoPanel: View {
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
                                        CachedImage(url: .aio(c.thumbnailSmall)) { Color.white.opacity(0.15) }
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
struct QueuePanel: View {
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
        .padding(.vertical, 4)  // Music's rows: 48 pt artwork on a 56 pt pitch
        .contentShape(.rect)
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
    static let blurRadius: Double = 26
    static let saturation: Double = 1.3

    var body: some View {
        Color.aioNavy
            .overlay {
                // Blurred once from a 64 px copy (was a live 80 pt blur over the full cover, redrawn on every frame
                // of the card's open/close animation).
                BlurredArtwork(url: player.episode?.artworkURL, radius: Self.blurRadius, saturation: Self.saturation)
                    .opacity(0.7)
            }
            .overlay(LinearGradient(colors: [.black.opacity(0.1), .black.opacity(0.45)], startPoint: .top, endPoint: .bottom))
            .clipped()
            .ignoresSafeArea()
    }
}
