import SwiftUI

struct LibraryView: View {
    @Environment(AppModel.self) private var app
    @Environment(DownloadStore.self) private var downloads
    @State private var syncProgress = ProgressSync.isEnabled

    var body: some View {
        List {
            if let profile = app.profile {
                Section {
                    HStack(spacing: 14) {
                        ProfileBadge(profile: profile, size: 52, showsName: false)
                        VStack(alignment: .leading) {
                            Text(profile.displayName).font(.universBold(18))
                            Text("Listening profile").font(.univers(14)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Switch") { app.switchProfile() }.buttonStyle(.bordered)
                    }
                }
            }
            Section {
                NavigationLink(value: Route.downloads) {
                    Label {
                        HStack {
                            Text("Downloads")
                            Spacer()
                            Text("\(downloads.items.count)").foregroundStyle(.secondary)
                        }
                    } icon: { Image(systemName: "arrow.down.circle.fill") }
                }
            }
            Section {
                Toggle("Sync Listening Progress", isOn: $syncProgress)
                    .onChange(of: syncProgress) { _, on in ProgressSync.isEnabled = on }
            } footer: {
                Text("Saves where you stop listening to your Adventures in Odyssey Club account, like the official app.")
            }
            #if DEBUG
            Section("Developer") {
                NavigationLink("API Explorer") { APIExplorerView() }
            }
            #endif
            Section {
                Button("Sign Out", role: .destructive) { Task { await app.signOut() } }
            }
        }
        .navigationTitle("Library")
    }
}

struct DownloadsView: View {
    @Environment(DownloadStore.self) private var downloads
    @Environment(AudioPlayer.self) private var player

    var body: some View {
        List {
            ForEach(downloads.items) { item in
                Button {
                    if let e = downloads.episode(for: item.id) { player.play(e) }
                } label: {
                    HStack(spacing: 12) {
                        Artwork(url: .aio(item.artwork), cornerRadius: 6).frame(width: 52, height: 52)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).font(.universBold(16, relativeTo: .headline)).lineLimit(2)
                            Text([item.albumName, item.subtitle].compactMap { $0 }.joined(separator: " · "))
                                .font(.univers(13, relativeTo: .subheadline)).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .onDelete { idx in idx.map { downloads.items[$0].id }.forEach(downloads.delete) }
        }
        .overlay {
            if downloads.items.isEmpty {
                ContentUnavailableView("No Downloads", systemImage: "arrow.down.circle",
                                       description: Text("Download episodes to listen without a connection."))
            }
        }
        .navigationTitle("Downloads")
        .toolbar {
            if !downloads.items.isEmpty {
                Text(ByteCountFormatter.string(fromByteCount: downloads.totalBytes, countStyle: .file))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
