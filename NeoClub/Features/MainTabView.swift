import SwiftUI

/// Apple Music-style shell: Liquid Glass tab bar with the mini player docked as its bottom accessory.
struct MainTabView: View {
    @Environment(AudioPlayer.self) private var player

    var body: some View {
        @Bindable var player = player
        TabView {
            Tab("Home", systemImage: "house.fill") {
                NavigationStack { HomeView().aioDestinations() }
            }
            Tab("Browse", systemImage: "square.grid.2x2.fill") {
                NavigationStack { BrowseView().aioDestinations() }
            }
            Tab("Library", systemImage: "books.vertical.fill") {
                NavigationStack { LibraryView().aioDestinations() }
            }
            Tab(role: .search) {
                NavigationStack { SearchView().aioDestinations() }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory(isEnabled: player.hasItem) {
            MiniPlayer()
        }
        .sheet(isPresented: $player.showNowPlaying) {
            NowPlayingView()
        }
    }
}

/// Compact player shown in the tab bar accessory; tap to open Now Playing.
struct MiniPlayer: View {
    @Environment(AudioPlayer.self) private var player
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    var body: some View {
        HStack(spacing: 12) {
            Artwork(url: player.episode?.smallArtworkURL, cornerRadius: 6)
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 0) {
                Text(player.episode?.title ?? "")
                    .font(.universBold(14, relativeTo: .subheadline))
                    .lineLimit(1)
                if placement != .inline, let album = player.episode?.albumTitle {
                    Text(album).font(.univers(12, relativeTo: .caption)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if player.isLoading {
                ProgressView().controlSize(.small)
            } else {
                Button { player.togglePlayPause() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.title3)
                }
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            }
            if placement != .inline {
                Button { player.skip(by: 30) } label: { Image(systemName: "goforward.30").font(.title3) }
                    .accessibilityLabel("Skip forward 30 seconds")
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .contentShape(.rect)
        .onTapGesture { player.showNowPlaying = true }
    }
}
