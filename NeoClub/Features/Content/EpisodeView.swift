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

    private var shown: Episode { detail ?? episode }
    private var isCurrent: Bool { player.episode?.id == shown.id }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(spacing: 14) {
                    Artwork(url: shown.artworkURL, cornerRadius: 14)
                        // At most 280pt, and no more than ~45% of a short screen (half-folded iPhone Duo).
                        .containerRelativeFrame(.vertical) { h, _ in min(280, h * 0.45) }
                        .shadow(color: .black.opacity(0.2), radius: 18, y: 10)
                    if let album = shown.albumTitle {
                        Text(album.uppercased())
                            .font(.universBold(12, relativeTo: .caption))
                            .foregroundStyle(.secondary)
                    }
                    Text(shown.title)
                        .font(.jacoby(28, relativeTo: .title))
                        .multilineTextAlignment(.center)
                    Text(shown.subtitle)
                        .font(.univers(15))
                        .foregroundStyle(.secondary)
                    ProgressIndicator(progress: player.progress(for: shown), durationMs: shown.mediaLength)
                    actions
                }
                .frame(maxWidth: .infinity)

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
            }
            .padding(20)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
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
                    ShareLink(item: shown.shareURL) { Label("Share Episode", systemImage: "square.and.arrow.up") }
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
            }
        }
        .task { await load() }
    }

    private var actions: some View {
        HStack(spacing: 12) {
            if shown.isPlayable {
            Button {
                if isCurrent { player.togglePlayPause() } else { player.play(shown, queue: queueAfter, groupingID: groupingID) }
            } label: {
                Label(playLabel, systemImage: isCurrent && player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.universBold(17))
                    .frame(minWidth: 140)
                    .padding(.vertical, 4)
            }
            .aioPrimaryButton()

            downloadButton
            BookmarkButton(episode: shown)
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder private var downloadButton: some View {
        if downloads.isDownloaded(shown.id) {
            Button { downloads.delete(shown.id) } label: {
                Image(systemName: "arrow.down.circle.fill").font(.title2)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("Remove download")
        } else if let f = downloads.active[shown.id] {
            ProgressView(value: f).progressViewStyle(.circular).frame(width: 44, height: 44)
        } else {
            Button { downloads.download(shown) } label: {
                Image(systemName: "arrow.down.circle").font(.title2)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("Download")
            .disabled(!shown.isAudio && detail != nil)
        }
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
