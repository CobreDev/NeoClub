import SwiftUI

/// Album/series page in the Apple Music album style, with an Apple Podcasts-style episode list.
struct GroupingView: View {
    @Environment(AudioPlayer.self) private var player
    let groupingID: String
    let preview: Grouping?
    @State private var grouping: Grouping?
    @State private var error: String?
    @State private var expanded = false

    private var shown: Grouping? { grouping ?? preview }
    private var episodes: [Episode] { shown?.contentList ?? [] }
    private var playable: [Episode] { episodes.filter(\.isPlayable) }

    var body: some View {
        List {
            header
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
            if grouping == nil && error == nil && episodes.isEmpty {
                LoadingView().listRowSeparator(.hidden)
            }
            if let error, grouping == nil {
                ErrorView(message: error) { await load() }.listRowSeparator(.hidden)
            }
            ForEach(episodes) { episode in
                NavigationLink(value: Route.episode(episode, groupingID: groupingID)) {
                    EpisodeRow(episode: episode) { play(episode) }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(shown?.title ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }

    private var header: some View {
        VStack(spacing: 14) {
            Artwork(url: shown?.artworkURL, cornerRadius: 12)
                .frame(width: 230, height: 230)
                .shadow(color: .black.opacity(0.2), radius: 16, y: 8)
                .padding(.top, 12)
            VStack(spacing: 4) {
                Text(shown?.title ?? " ")
                    .font(.jacoby(26, relativeTo: .title))
                    .multilineTextAlignment(.center)
                Text(metaLine)
                    .font(.univers(15))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            if let next = continueEpisode {
                Button { play(next) } label: {
                    Label(continueLabel(next), systemImage: "play.fill")
                        .font(.universBold(17))
                        .frame(maxWidth: 280)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.glassProminent)
            }
            if let text = shown?.fullDescription ?? shown?.description, !text.isEmpty {
                Text(text)
                    .font(.univers(15))
                    .foregroundStyle(.secondary)
                    .lineLimit(expanded ? nil : 3)
                    .onTapGesture { withAnimation { expanded.toggle() } }
                    .padding(.horizontal, 20)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 12)
    }

    private var metaLine: String {
        var parts: [String] = []
        if let type = shown?.type { parts.append(type == "Podcast Year" ? "Podcasts" : type) }
        if !episodes.isEmpty { parts.append(episodes.count == 1 ? "1 episode" : "\(episodes.count) episodes") }
        let total = episodes.compactMap(\.mediaLength).reduce(0, +)
        if total > 0 { parts.append(total.msDurationText) }
        return parts.joined(separator: " · ")
    }

    /// Where the profile is in this album: the episode in progress, else the first unplayed one.
    private var continueEpisode: Episode? {
        playable.first { player.progress(for: $0)?.isInProgress == true }
            ?? playable.first { player.progress(for: $0)?.isComplete != true }
            ?? playable.first
    }

    private func continueLabel(_ e: Episode) -> String {
        if player.progress(for: e)?.isInProgress == true { return "Resume" }
        if episodes.contains(where: { player.progress(for: $0)?.isComplete == true }) { return "Play Next" }
        return "Play"
    }

    private func play(_ episode: Episode) {
        if player.episode?.id == episode.id { player.togglePlayPause(); return }
        let i = playable.firstIndex(of: episode) ?? 0
        player.play(episode, queue: Array(playable.dropFirst(i + 1)), groupingID: groupingID)
    }

    private func load() async {
        guard !groupingID.isEmpty else { return }
        do {
            grouping = try await AIOService.grouping(groupingID)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
