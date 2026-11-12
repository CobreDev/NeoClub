import SwiftUI

/// Testing switches, opened by holding the profile picture on Home.
struct DebugMenu: View {
    @Environment(DownloadStore.self) private var downloads
    @State private var syncProgress = ProgressSync.isEnabled
    @State private var exportDownloads = DownloadStore.exportsToFiles
    @AppStorage(NowPlayingPresentation.nativeKey) private var nativeNowPlaying = true

    var body: some View {
        Section("Debug") {
            Toggle(isOn: $syncProgress) {
                Label("Sync Listening Progress", systemImage: "arrow.triangle.2.circlepath")
            }
            .onChange(of: syncProgress) { _, on in ProgressSync.isEnabled = on }
            Toggle(isOn: $exportDownloads) {
                Label("Show Downloads in Files", systemImage: "folder")
            }
            .onChange(of: exportDownloads) { _, on in downloads.setExportsToFiles(on) }
            Toggle(isOn: $nativeNowPlaying) {
                Label("System Now Playing Transition", systemImage: "rectangle.portrait.and.arrow.forward")
            }
        }
    }
}
