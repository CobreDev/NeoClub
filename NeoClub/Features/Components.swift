import SwiftUI

/// Navigation destinations shared by every tab.
enum Route: Hashable {
    case episode(Episode, groupingID: String?)
    case grouping(id: String, preview: Grouping?)
    case groupingList(type: String, title: String)
    case downloads
}

extension View {
    func aioDestinations() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .episode(let e, let gid): EpisodeView(episode: e, groupingID: gid)
            case .grouping(let id, let preview): GroupingView(groupingID: id, preview: preview)
            case .groupingList(let type, let title): GroupingGridView(type: type, title: title)
            case .downloads: DownloadsView()
            }
        }
    }
}

/// Rounded square artwork with a branded placeholder.
struct Artwork: View {
    let url: URL?
    var cornerRadius: CGFloat = 10

    var body: some View {
        // A fixed square container that the image fills, so scaled-to-fill art can't overflow its frame.
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        ZStack {
                            LinearGradient(colors: [.aioOcean, .aioNavy], startPoint: .topLeading, endPoint: .bottomTrailing)
                            Image(systemName: "headphones").font(.title).foregroundStyle(.white.opacity(0.5))
                        }
                    }
                }
            }
            .clipShape(.rect(cornerRadius: cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(.primary.opacity(0.08)))
    }
}

/// Thin listening-progress bar; shows a checkmark when finished.
struct ProgressIndicator: View {
    let progress: ListenProgress?
    let durationMs: Int?

    var body: some View {
        if let progress, progress.isComplete {
            Label("Played", systemImage: "checkmark.circle.fill")
                .labelStyle(.iconOnly)
                .foregroundStyle(Color.aioYellow)
                .font(.caption)
        } else if let progress, progress.isInProgress, let total = durationMs, total > 0 {
            let fraction = min(1, Double(progress.currentProgress ?? 0) / Double(total))
            HStack(spacing: 6) {
                Capsule().fill(.white.opacity(0.25))
                    .overlay(alignment: .leading) {
                        GeometryReader { g in Capsule().fill(Color.aioYellow).frame(width: g.size.width * fraction) }
                    }
                    .frame(width: 44, height: 4)
                Text("\(max(1, (total - (progress.currentProgress ?? 0)) / 60_000)) min left")
                    .font(.univers(12, relativeTo: .caption))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Apple Music-style shelf card: artwork above a two-line caption.
struct EpisodeCard: View {
    @Environment(AudioPlayer.self) private var player
    let episode: Episode
    var width: CGFloat = 160

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Artwork(url: episode.smallArtworkURL)
                .frame(width: width, height: width)
                .overlay(alignment: .bottomTrailing) {
                    if player.episode?.id == episode.id {
                        Image(systemName: player.isPlaying ? "waveform" : "pause.fill")
                            .symbolEffect(.variableColor.iterative, isActive: player.isPlaying)
                            .font(.caption.bold())
                            .padding(6)
                            .glassEffect(.regular, in: .circle)
                            .padding(6)
                    }
                }
            Text(episode.title)
                .font(.univers(14, relativeTo: .subheadline))
                .lineLimit(2)
                .frame(width: width, alignment: .leading)
            Group {
                if let p = player.progress(for: episode), p.isInProgress || p.isComplete {
                    ProgressIndicator(progress: p, durationMs: episode.mediaLength)
                } else {
                    Text(episode.subtitle)
                        .font(.univers(12, relativeTo: .caption))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: width, alignment: .leading)
        }
    }
}

/// Apple Podcasts-style episode row with inline play and download state.
struct EpisodeRow: View {
    @Environment(AudioPlayer.self) private var player
    @Environment(DownloadStore.self) private var downloads
    let episode: Episode
    let onPlay: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Artwork(url: episode.smallArtworkURL, cornerRadius: 8)
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 4) {
                if let n = episode.episodeNumber, !n.isEmpty {
                    Text("EPISODE \(n)")
                        .font(.universBold(11, relativeTo: .caption2))
                        .foregroundStyle(.secondary)
                }
                Text(episode.title)
                    .font(.universBold(16, relativeTo: .headline))
                    .lineLimit(2)
                if let d = episode.description, !d.isEmpty {
                    Text(d)
                        .font(.univers(14, relativeTo: .subheadline))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                HStack(spacing: 10) {
                    if episode.isPlayable { Button(action: onPlay) {
                        Label(playLabel, systemImage: isCurrent && player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.universBold(13, relativeTo: .footnote))
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small) }
                    ProgressIndicator(progress: player.progress(for: episode), durationMs: episode.mediaLength)
                    Spacer()
                    if downloads.isDownloaded(episode.id) {
                        Image(systemName: "arrow.down.circle.fill").foregroundStyle(.secondary)
                    } else if let f = downloads.active[episode.id] {
                        ProgressView(value: f).progressViewStyle(.circular).controlSize(.small)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 6)
        .contentShape(.rect)
    }

    private var isCurrent: Bool { player.episode?.id == episode.id }

    private var playLabel: String {
        if isCurrent && player.isPlaying { return "Playing" }
        let p = player.progress(for: episode)
        if let p, p.isInProgress { return "Resume" }
        return episode.mediaLength.map { $0.msDurationText } ?? "Play"
    }
}

/// Wide branded header using the official section art, with the title in Jacoby.
struct HeroHeader: View {
    let image: String
    let title: String
    var subtitle: String?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            BrandImage(name: image)
                .scaledToFill()
                .frame(height: 190)
                .clipped()
                .overlay(LinearGradient(colors: [.clear, .aioNavy.opacity(0.85)], startPoint: .center, endPoint: .bottom))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.jacoby(34)).foregroundStyle(.white)
                if let subtitle {
                    Text(subtitle).font(.univers(15)).foregroundStyle(.white.opacity(0.85))
                }
            }
            .padding(20)
        }
        .frame(height: 190)
    }
}

struct LoadingView: View {
    var body: some View {
        ProgressView().frame(maxWidth: .infinity, minHeight: 240)
    }
}

struct ErrorView: View {
    let message: String
    let retry: () async -> Void
    var body: some View {
        ContentUnavailableView {
            Label("Couldn't Load", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again") { Task { await retry() } }.buttonStyle(.glassProminent)
        }
    }
}
