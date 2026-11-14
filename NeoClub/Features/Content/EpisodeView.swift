import SwiftUI

/// Episode page: artwork, play/resume, download, description, cast, and the rest of the album.
struct EpisodeView: View {
    @Environment(AudioPlayer.self) private var player
    @Environment(DownloadStore.self) private var downloads
    let episode: Episode
    let groupingID: String?
    @State private var detail: Episode?
    @State private var error: String?
    @State private var expanded = false
    /// The page's size and top inset, for sizing and placing the artwork like Apple Music.
    @State private var page: CGSize = .zero
    @State private var topInset: CGFloat = 0

    private var shown: Episode { detail ?? episode }
    private var isCurrent: Bool { player.episode?.id == shown.id }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header

                if let text = shown.description, !text.isEmpty {
                    Text(text)
                        .font(.univers(16))
                        .lineLimit(expanded ? nil : 5)
                        .onTapGesture { withAnimation { expanded.toggle() } }
                }

                if let cast = shown.characters, !cast.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        ShelfHeader(title: "Characters").padding(.horizontal, -20)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 12) {
                                ForEach(Array(cast.enumerated()), id: \.offset) { _, c in
                                    if let cid = c.characterID {
                                        NavigationLink(value: Route.character(id: cid, preview: c)) {
                                            PersonChip(name: c.name ?? "", detail: nil, imageURL: c.avatarURL)
                                        }
                                        .buttonStyle(.plain)
                                    } else {
                                        PersonChip(name: c.name ?? "", detail: nil, imageURL: c.avatarURL)
                                    }
                                }
                            }
                        }
                    }
                }

                if let crew = shown.authors, !crew.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        ShelfHeader(title: "Cast & Crew").padding(.horizontal, -20)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 12) {
                                ForEach(Array(crew.enumerated()), id: \.offset) { _, a in
                                    NavigationLink(value: Route.author(id: a.id, preview: a)) {
                                        PersonChip(name: a.name ?? "", detail: a.role, imageURL: a.imageURL)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }

                if let more = shown.inAlbum?.filter({ $0.id != shown.id }), !more.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ShelfHeader(title: "More in This Album").padding(.horizontal, -20)
                        ForEach(more) { e in
                            NavigationLink(value: Route.episode(e, groupingID: groupingID)) {
                                EpisodeRow(episode: e) { player.play(e, groupingID: groupingID) }
                            }
                            .buttonStyle(.plain)
                            .episodeContextMenu(e, groupingID: groupingID)
                            Divider()
                        }
                    }
                }

                if let error, detail == nil {
                    ErrorView(message: error) { await load() }
                }

                // Like Music's album footer, in the style of the episode number and length under the title.
                if let date = shown.releaseDate {
                    Text("Released \(Episode.releaseText(date))")
                        .font(.universBold(13, relativeTo: .footnote))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { page = $0 }
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { topInset = $0 }
        .aioBackground(artworkURL: shown.artworkURL)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if player.progress(for: shown)?.isComplete == true {
                        Button {
                            player.markUnplayed(shown)
                        } label: {
                            Label("Mark as Unplayed", systemImage: "arrow.uturn.backward.circle")
                        }
                    } else {
                        Button {
                            player.markPlayed(shown)
                        } label: {
                            Label("Mark as Played", systemImage: "checkmark.circle")
                        }
                    }
                    if let albumID = shown.albumID {
                        Button {
                            player.navigationRequest = .grouping(id: albumID, preview: nil)
                        } label: {
                            Label("Go to Album", systemImage: "square.stack")
                        }
                    }
                    ShareLink(item: shown.shareURL) { Label("Share Episode", systemImage: "square.and.arrow.up") }
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
            }
        }
        .task { await load() }
    }

    /// Apple Music's album header (measured on the iPhone Duo's inner screen): artwork ~69% of the width, its top
    /// tucked ~26 pt up under the toolbar (56 pt from the screen's top); the title ~26 pt under the art; the album
    /// where Music has the artist; the episode number and length where Music has genre · year · format (small, semibold,
    /// muted); then a 48 pt circle, a 160 × 48 pt play pill and a 48 pt circle, 15 pt apart.
    private var header: some View {
        let side = page == .zero ? 280 : min(page.width * 0.69, page.height * 0.5, 520)
        return VStack(spacing: 0) {
            Artwork(url: shown.artworkURL, cornerRadius: 10)
                .frame(width: side, height: side)
                .shadow(color: .black.opacity(0.25), radius: 20, y: 10)
            Text(shown.title)
                .font(.jacoby(24, relativeTo: .title2))
                .multilineTextAlignment(.center)
                .padding(.top, 20)
            if let album = shown.albumTitle {
                let name = Text(album)
                    .font(.univers(21, relativeTo: .title3))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.top, 2)
                if let albumID = shown.albumID {
                    NavigationLink(value: Route.grouping(id: albumID, preview: nil)) { name }
                        .buttonStyle(.plain)
                } else {
                    name
                }
            }
            Text(shown.subtitle)
                .font(.universBold(13, relativeTo: .footnote))
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            ProgressIndicator(progress: player.progress(for: shown), durationMs: shown.mediaLength, barWidth: 72)
                .padding(.top, 8)
            actions.padding(.top, 14)
        }
        .frame(maxWidth: .infinity)
        // Up under the toolbar, as Music's artwork is (its top sits 56 pt from the screen's top on the inner screen).
        .padding(.top, -26)
    }

    private var actions: some View {
        HStack(spacing: 15) {
            if shown.isPlayable {
                BookmarkButton(episode: shown, size: 48)
                Button {
                    if isCurrent { player.togglePlayPause() } else { player.play(shown, queue: queueAfter, groupingID: groupingID) }
                } label: {
                    Label(playLabel, systemImage: isCurrent && player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.universBold(17))
                        .frame(width: 136, height: 36)
                }
                .aioPrimaryButton()
                downloadButton
            }
        }
    }

    @ViewBuilder private var downloadButton: some View {
        DownloadButton(episodes: [shown], size: 48)
            .disabled(!shown.isAudio && detail != nil && !downloads.isDownloaded(shown.id))
    }

    private var playLabel: String {
        if isCurrent { return player.isPlaying ? "Pause" : "Play" }
        if player.progress(for: shown)?.isInProgress == true { return "Resume" }
        return "Play"
    }

    private var queueAfter: [Episode] {
        guard let list = shown.inAlbum, let i = list.firstIndex(where: { $0.id == shown.id }) else { return [] }
        return Array(list.dropFirst(i + 1))
    }

    private func load() async {
        do {
            detail = try await AIOService.episode(episode.id, groupingID: groupingID)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
