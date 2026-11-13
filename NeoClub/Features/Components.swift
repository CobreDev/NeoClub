import SafariServices
import SwiftUI

/// Navigation destinations shared by every tab.
enum Route: Hashable {
    case episode(Episode, groupingID: String?)
    case grouping(id: String, preview: Grouping?)
    case groupingList(type: String, title: String, filter: GroupingFilter = .all)
    case character(id: String, preview: CastMember?)
    case author(id: String, preview: Author?)
    case bookmarks
}

extension View {
    func aioDestinations() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .episode(let e, let gid): EpisodeView(episode: e, groupingID: gid)
            case .grouping(let id, let preview): GroupingView(groupingID: id, preview: preview)
            case .groupingList(let type, let title, let filter): GroupingGridView(type: type, title: title, filter: filter)
            case .character(let id, let preview): CharacterView(characterID: id, preview: preview)
            case .author(let id, let preview): AuthorView(authorID: id, preview: preview)
            case .bookmarks: BookmarksView()
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
                CachedImage(url: url) {
                    ZStack {
                        LinearGradient(colors: [.aioOcean, .aioNavy], startPoint: .topLeading, endPoint: .bottomTrailing)
                        Image(systemName: "headphones").font(.title).foregroundStyle(.white.opacity(0.5))
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
    var barWidth: CGFloat = 44

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
                    .frame(width: barWidth, height: 4)
                Text("\(max(1, (total - (progress.currentProgress ?? 0)) / 60_000)) min left")
                    .font(.univers(12, relativeTo: .caption))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
    }
}

/// Apple Music-style shelf card: artwork above a two-line caption.
struct EpisodeCard: View {
    @Environment(AudioPlayer.self) private var player
    let episode: Episode
    /// Fixed width, or nil to fill the width it's given (shelves size it with `shelfItem()`).
    var width: CGFloat? = nil

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
                .lineLimit(2, reservesSpace: true)
                .frame(maxWidth: width ?? .infinity, alignment: .leading)
            Group {
                if let p = player.progress(for: episode), p.isInProgress || p.isComplete {
                    ProgressIndicator(progress: p, durationMs: episode.mediaLength)
                } else {
                    Text(episode.subtitle)
                        .font(.univers(12, relativeTo: .caption))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: width ?? .infinity, alignment: .leading)
        }
    }
}

extension View {
    /// Apple Music's shelf sizing: items scale with the screen so about 2½ show on a phone-width screen, 3½ on the
    /// iPhone Duo unfolded in portrait and 4½ in landscape (one fewer for the larger "Continue Listening" cards),
    /// with the next item peeking in. Assumes 20 pt margins and 14 pt spacing.
    func shelfItem(large: Bool = false) -> some View {
        containerRelativeFrame(.horizontal) { width, _ in
            var count: CGFloat = width < 520 ? 2 : width < 760 ? 3 : 4
            if large { count = max(1.5, count - 0.5) }
            return (width - 20 - 14 * count) / (count + 0.5)
        }
    }
}

/// Apple Music's grids: 2 columns on a phone-width screen, 3 on the iPhone Duo unfolded in portrait, 4 in
/// landscape, decided by the width the grid actually has.
struct AdaptiveGrid<Content: View>: View {
    var spacing: CGFloat = 14
    var rowSpacing: CGFloat = 20
    @ViewBuilder var content: Content
    @State private var width: CGFloat = 0

    var body: some View {
        let count = width < 520 ? 2 : width < 760 ? 3 : 4
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: spacing, alignment: .top), count: count),
                  alignment: .leading, spacing: rowSpacing) {
            content
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
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
                    DownloadStatusIcon(id: episode.id)
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

struct IdentifiableURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// In-app Safari for club pages that only exist on the website.
struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let vc = SFSafariViewController(url: url)
        vc.preferredControlTintColor = UIColor(Color.aioBlue)
        return vc
    }
    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}

extension Episode {
    /// The episode on the AIO Club website, for sharing.
    var shareURL: URL { URL(string: "https://app.adventuresinodyssey.com/content/\(id)")! }
}

/// Long-press menu for an episode anywhere in the app: Play, Mark as Played/Unplayed, Share, plus any extra items.
private struct EpisodeContextMenu<Extra: View>: ViewModifier {
    @Environment(AudioPlayer.self) private var player
    let episode: Episode
    let queue: [Episode]
    let groupingID: String?
    let extra: Extra

    func body(content: Content) -> some View {
        content.contextMenu {
            Button("Play", systemImage: "play.fill") { player.play(episode, queue: queue, groupingID: groupingID) }
            if episode.isPlayable {
                Section {
                    Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") { player.queueNext(episode) }
                    Button("Play Last", systemImage: "text.line.last.and.arrowtriangle.forward") { player.queueLast(episode) }
                }
            }
            if player.progress(for: episode)?.isComplete == true {
                Button("Mark as Unplayed", systemImage: "arrow.uturn.backward.circle") { player.markUnplayed(episode) }
            } else {
                Button("Mark as Played", systemImage: "checkmark.circle") { player.markPlayed(episode) }
            }
            ShareLink(item: episode.shareURL) { Label("Share Episode", systemImage: "square.and.arrow.up") }
            extra
        }
    }
}

/// Apple Music's swipes on a song row (traced in Music on iOS 27.2: one icon-only action each way, full swipe runs
/// it): leading, Play Next (`text.line.first.and.arrowtriangle.forward`, system indigo); trailing, Music's Delete
/// (`trash.fill`, system red), which here is the bookmark toggle.
private struct EpisodeSwipeActions: ViewModifier {
    @Environment(AudioPlayer.self) private var player
    @Environment(BookmarkStore.self) private var bookmarks
    let episode: Episode

    func body(content: Content) -> some View {
        let marked = bookmarks.isBookmarked(episode)
        content
            .swipeActions(edge: .leading) {
                if episode.isPlayable {
                    Button { player.queueNext(episode) } label: {
                        Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward").labelStyle(.iconOnly)
                    }
                    .tint(.indigo)
                }
            }
            .swipeActions(edge: .trailing) {
                Button { bookmarks.toggle(episode) } label: {
                    Label(marked ? "Remove Bookmark" : "Bookmark", systemImage: marked ? "bookmark.slash.fill" : "bookmark.fill")
                        .labelStyle(.iconOnly)
                }
                .tint(marked ? .red : .orange)
            }
    }
}

extension View {
    /// Apple Music's row swipes: Play Next leading, bookmark trailing (rows in a `List`).
    func episodeSwipeActions(_ episode: Episode) -> some View { modifier(EpisodeSwipeActions(episode: episode)) }

    func episodeContextMenu<Extra: View>(_ episode: Episode, queue: [Episode] = [], groupingID: String? = nil,
                                         @ViewBuilder extra: () -> Extra = { EmptyView() }) -> some View {
        modifier(EpisodeContextMenu(episode: episode, queue: queue, groupingID: groupingID, extra: extra()))
    }
}

/// One line of text that scrolls when it doesn't fit, like Apple Music's Now Playing titles: it rests for a few
/// seconds, glides left at a steady pace until a second copy has taken the first one's place, and repeats. Text
/// that fits just sits still.
private struct IsOnScreenKey: EnvironmentKey { static let defaultValue = true }
extension EnvironmentValues {
    /// False while a view is kept built but hidden (Now Playing while it's closed), so it can skip
    /// animations and per-second updates.
    var isOnScreen: Bool {
        get { self[IsOnScreenKey.self] }
        set { self[IsOnScreenKey.self] = newValue }
    }
}

struct MarqueeText: View {
    let text: String
    let font: Font
    /// Gap between the end of the text and the start of the next copy.
    var gap: CGFloat = 40
    /// Scrolling speed, points per second.
    var speed: CGFloat = 30
    /// Seconds at rest before each pass.
    var pause: Double = 3

    @State private var fullWidth: CGFloat = 0
    @State private var boxWidth: CGFloat = 0
    /// Off while the view is hidden (e.g. the Now Playing card behind the mini player): no animation runs, and
    /// coming back on screen starts the scroll over from the beginning.
    @Environment(\.isOnScreen) private var isOnScreen
    /// When the current cycle began; the position is computed from it, so restarting is just a reset.
    @State private var start = Date()

    /// The screenshot demo shows long titles at rest, not caught mid-scroll.
    private static var staticForDemo: Bool {
        #if SCREENSHOT_DEMO
        return true
        #else
        return false
        #endif
    }

    private var overflows: Bool { fullWidth > boxWidth + 0.5 }

    var body: some View {
        // The visible layout: one line at the available width (the scrolling copy is drawn over it).
        Text(text).font(font).lineLimit(1)
            .opacity(0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { boxWidth = $0 }
            .background(alignment: .leading) {
                Text(text).font(font).fixedSize().hidden()
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { fullWidth = $0 }
            }
            .overlay(alignment: .leading) {
                let distance = fullWidth + gap
                if isOnScreen && !Self.staticForDemo {
                    scrolling(distance: distance)
                } else {
                    Text(text).font(font).fixedSize()
                }
            }
            .clipped()
            .mask {
                if overflows {
                    HStack(spacing: 0) {
                        Color.black
                        LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: 16)
                    }
                } else {
                    Color.black
                }
            }
            .onChange(of: text) { start = Date() }
            .accessibilityLabel(text)
    }

    private func scrolling(distance: CGFloat) -> some View {
                HStack(spacing: gap) {
                    Text(text).font(font).fixedSize()
                    if overflows { Text(text).font(font).fixedSize() }
                }
                // Rest, glide one text-plus-gap left, repeat. A new identity starts it over from the beginning.
                .keyframeAnimator(initialValue: CGFloat(0), repeating: overflows) { content, x in
                    // The leading edge fades only while the text is moving, so at rest the first letter is
                    // crisp (Apple Music). The mask isn't offset, so it stays on the box's leading edge.
                    content.offset(x: overflows ? x : 0)
                        .mask(alignment: .leading) {
                            HStack(spacing: 0) {
                                LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                                    .frame(width: min(8, max(0, -x)))
                                Color.black
                            }
                        }
                } keyframes: { _ in
                    KeyframeTrack {
                        LinearKeyframe(0, duration: pause)
                        LinearKeyframe(-distance, duration: Double(max(distance, 1) / speed))
                    }
                }
                .id(start)
    }
}

extension Grouping {
    /// The album/collection on the AIO Club website, for sharing.
    var shareURL: URL? { groupingID.flatMap { URL(string: "https://app.adventuresinodyssey.com/contentGroup/\($0)") } }
}

/// Menu items for an album or collection: Play, Mark Album as Played/Unplayed, Share. Uses the episodes the
/// grouping came with, or loads them when an action is chosen (search results arrive without them).
struct GroupingActions: View {
    @Environment(AudioPlayer.self) private var player
    let id: String
    let grouping: Grouping?

    private var episodes: [Episode] { grouping?.contentList ?? [] }

    var body: some View {
        Button("Play", systemImage: "play.fill") {
            withEpisodes { list in
                guard let first = list.first else { return }
                player.play(first, queue: Array(list.dropFirst()), groupingID: id)
            }
        }
        let known = !episodes.isEmpty
        let played = episodes.filter { player.progress(for: $0)?.isComplete ?? false }.count
        if !known || played < episodes.count {
            Button("Mark Album as Played", systemImage: "checkmark.circle") {
                withEpisodes { player.markAll($0, played: true) }
            }
        }
        if !known || played > 0 {
            Button("Mark Album as Unplayed", systemImage: "arrow.uturn.backward.circle") {
                withEpisodes { player.markAll($0, played: false) }
            }
        }
        if let url = grouping?.shareURL ?? URL(string: "https://app.adventuresinodyssey.com/contentGroup/\(id)") {
            ShareLink(item: url) { Label("Share Album", systemImage: "square.and.arrow.up") }
        }
    }

    private func withEpisodes(_ action: @escaping @MainActor ([Episode]) -> Void) {
        if !episodes.isEmpty { action(episodes); return }
        Task {
            if let list = try? await AIOService.grouping(id)?.contentList, !list.isEmpty { action(list) }
        }
    }
}

extension View {
    /// Long-press menu for an album or collection.
    func groupingContextMenu(id: String, grouping: Grouping?) -> some View {
        contextMenu { GroupingActions(id: id, grouping: grouping) }
    }
}

/// Apple Music's download control, for one episode or a whole album: a circle button showing a down arrow, then a
/// progress ring with a stop square while downloading (tap to stop), then a checkmark (tap to remove, after asking).
struct DownloadButton: View {
    @Environment(DownloadStore.self) private var downloads
    let episodes: [Episode]
    var size: CGFloat = 50
    @State private var confirmRemove = false

    private var ids: [String] { episodes.map(\.id) }
    private var allDone: Bool { !episodes.isEmpty && episodes.allSatisfy { downloads.isDownloaded($0.id) } }
    /// Overall progress while any are downloading or queued (finished episodes count as complete).
    private var progress: Double? {
        let running = ids.compactMap { downloads.active[$0] }
        guard !running.isEmpty else { return nil }
        let done = ids.filter { downloads.isDownloaded($0) }.count
        return (Double(done) + running.reduce(0, +)) / Double(max(1, done + running.count))
    }

    var body: some View {
        Button {
            if allDone { confirmRemove = true }
            else if progress != nil { downloads.cancel(all: ids) }
            else { downloads.download(all: episodes) }
        } label: {
            ZStack {
                if allDone {
                    Image(systemName: "checkmark").font(.system(size: size * 0.38, weight: .semibold))
                } else if let progress {
                    Circle().stroke(.white.opacity(0.25), lineWidth: 2.5).frame(width: size * 0.5)
                    Circle().trim(from: 0, to: max(0.03, progress))
                        .stroke(.white, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: size * 0.5)
                        .animation(.linear(duration: 0.2), value: progress)
                    RoundedRectangle(cornerRadius: 2).frame(width: size * 0.17, height: size * 0.17)
                } else {
                    Image(systemName: "arrow.down").font(.system(size: size * 0.38, weight: .semibold))
                }
            }
            .frame(width: size, height: size)
            .foregroundStyle(.white)
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(allDone ? "Downloaded" : progress != nil ? "Stop Downloading" : "Download")
        .confirmationDialog(episodes.count == 1 ? "Remove this download?" : "Remove these downloads?",
                            isPresented: $confirmRemove, titleVisibility: .visible) {
            Button(episodes.count == 1 ? "Remove Download" : "Remove Downloads", role: .destructive) {
                downloads.delete(all: ids)
            }
        }
    }
}

/// Small per-row indicator: a filled down-arrow circle once downloaded (Apple Music), a thin ring while downloading.
struct DownloadStatusIcon: View {
    @Environment(DownloadStore.self) private var downloads
    let id: String

    var body: some View {
        if downloads.isDownloaded(id) {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(.secondary)
                .accessibilityLabel("Downloaded")
        } else if let f = downloads.active[id] {
            ZStack {
                Circle().stroke(.secondary.opacity(0.4), lineWidth: 2)
                Circle().trim(from: 0, to: max(0.03, f))
                    .stroke(.secondary, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 16, height: 16)
            .accessibilityLabel("Downloading")
        }
    }
}
