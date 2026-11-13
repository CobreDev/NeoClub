import SwiftUI

/// Account sheet opened from the Home profile button: profile, switching profiles, sign out. (The developer switches
/// are in `DebugMenu`, on a hold of that button.)
struct AccountView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var confirmSignOut = false

    var body: some View {
        NavigationStack {
            List {
                if let profile = app.profile {
                    Section {
                        HStack(spacing: 14) {
                            ProfileBadge(profile: profile, size: 56, showsName: false)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.displayName).font(.universBold(20))
                                Text("Listening profile").font(.univers(14)).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                        .aioRow()
                        Button {
                            dismiss()
                            app.switchProfile()
                        } label: {
                            Label("Switch Profile", systemImage: "person.2.fill")
                        }
                        .aioRow()
                    }
                }
                Section {
                    Button("Sign Out", role: .destructive) { confirmSignOut = true }.aioRow()
                } footer: {
                    Text("AIO Club \(AppVersion.display)")
                }
            }
            .aioBackground("bg_celebration.jpg")
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Sign out of your Adventures in Odyssey Club account?", isPresented: $confirmSignOut,
                                titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) {
                    dismiss()
                    Task { await app.signOut() }
                }
            }
        }
    }
}

/// The developer switches, in the menu that opens when the Home profile button is held. Kept in release builds.
struct DebugMenu: View {
    @Environment(DownloadStore.self) private var downloads
    @State private var syncProgress = ProgressSync.isEnabled
    @State private var exportDownloads = DownloadStore.exportsToFiles

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
        }
    }
}
