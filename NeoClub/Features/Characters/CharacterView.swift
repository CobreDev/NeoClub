import SwiftUI

/// Character page: portrait, name, voice actor, bio, art, and the episodes they're featured in.
struct CharacterView: View {
    @Environment(AudioPlayer.self) private var player
    let characterID: String
    let preview: CastMember?
    @State private var character: CastMember?
    @State private var error: String?
    @State private var expanded = false

    private var shown: CastMember? { character ?? preview }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(spacing: 12) {
                    CachedImage(url: shown?.largeURL) { Color.white.opacity(0.12) }
                        .frame(width: 180, height: 180)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(.white.opacity(0.85), lineWidth: 3))
                        .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
                    Text(shown?.name ?? " ")
                        .font(.jacoby(32, relativeTo: .title))
                        .multilineTextAlignment(.center)
                    if let job = shown?.job, !job.isEmpty {
                        Text(job).font(.univers(16)).foregroundStyle(.secondary)
                    }
                    if let actor = shown?.voicedBy, !actor.isEmpty {
                        if let actorID = shown?.voicedByID, !actorID.isEmpty {
                            NavigationLink(value: Route.author(id: actorID, preview: nil)) {
                                Label("Voiced by \(actor)", systemImage: "mic.fill").font(.universBold(15))
                                    }
                            .buttonStyle(.bordered)
                        } else {
                            Label("Voiced by \(actor)", systemImage: "mic.fill").font(.univers(15)).foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                if let bio = shown?.bio, !bio.isEmpty {
                    Text(bio)
                        .font(.univers(17))
                        .lineLimit(expanded ? nil : 6)
                        .onTapGesture { withAnimation { expanded.toggle() } }
                }

                if let photos = shown?.photos?.compactMap({ URL.aio($0.medium ?? $0.small ?? $0.large) }), photos.count > 1 {
                    ShelfHeader(title: "Gallery").padding(.horizontal, -20)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(photos, id: \.self) { url in
                                Artwork(url: url, cornerRadius: 12).frame(width: 150, height: 150)
                            }
                        }
                    }
                }

                if let eps = shown?.featuredIn?.filter(\.isPlayable), !eps.isEmpty {
                    ShelfHeader(title: "Featured In", subtitle: "\(eps.count) episodes").padding(.horizontal, -20)
                    LazyVStack(spacing: 0) {
                        ForEach(eps) { e in
                            NavigationLink(value: Route.episode(e, groupingID: nil)) {
                                EpisodeRow(episode: e) { player.play(e) }
                            }
                            .buttonStyle(.plain)
                            .episodeContextMenu(e)
                            Divider()
                        }
                    }
                }

                if let error, character == nil { ErrorView(message: error) { await load() } }
            }
            .padding(20)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .aioBackground(artworkURL: shown?.largeURL)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        do {
            character = try await AIOService.character(characterID)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Cast & crew page: a real person who voices, writes or directs the show.
struct AuthorView: View {
    let authorID: String
    let preview: Author?
    @State private var author: Author?
    @State private var error: String?

    private var shown: Author? { author ?? preview }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                CachedImage(url: shown?.imageURL) {
                    Image(systemName: "person.fill").font(.system(size: 64)).foregroundStyle(.white.opacity(0.5))
                        .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.white.opacity(0.12))
                }
                .frame(width: 180, height: 180)
                .clipShape(Circle())
                .overlay(Circle().stroke(.white.opacity(0.85), lineWidth: 3))
                .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
                Text(shown?.name ?? " ")
                    .font(.jacoby(32, relativeTo: .title))
                    .multilineTextAlignment(.center)
                if let role = shown?.role, !role.isEmpty {
                    Text(role).font(.univers(16)).foregroundStyle(.secondary)
                }
                if let bio = shown?.bio, !bio.isEmpty {
                    Text(bio)
                        .font(.univers(17))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                }
                if let error, author == nil { ErrorView(message: error) { await load() } }
            }
            .padding(20)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .aioBackground("bg_celebration.jpg")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        do {
            author = try await AIOService.author(authorID)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Round portrait + name, used in Characters / Cast & Crew rows.
struct PersonChip: View {
    let name: String
    let detail: String?
    let imageURL: URL?

    var body: some View {
        VStack(spacing: 6) {
            CachedImage(url: imageURL) {
                Image(systemName: "person.fill").foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.white.opacity(0.12))
            }
            .frame(width: 76, height: 76)
            .clipShape(Circle())
            Text(name)
                .font(.univers(13, relativeTo: .caption))
                .lineLimit(2)
                .multilineTextAlignment(.center)
            if let detail, !detail.isEmpty {
                Text(detail).font(.univers(11, relativeTo: .caption2)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(width: 92)
    }
}
