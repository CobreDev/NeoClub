import SwiftUI

/// Account sheet opened from the Home profile button: profile, sync setting, developer tools, sign out.
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
                    Text("AIO Club \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
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
