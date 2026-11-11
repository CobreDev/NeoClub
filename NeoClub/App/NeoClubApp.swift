import SwiftUI

@main
struct NeoClubApp: App {
    @State private var app = AppModel()
    @State private var player = AudioPlayer.shared
    @State private var downloads = DownloadStore.shared

    init() {
        // Transparent nav bars over the branded backdrop, with titles in the official AIO faces
        // (Jacoby for large titles, Univers for inline). Set via UINavigationBarAppearance so it
        // survives SwiftUI's toolbar configuration.
        let bar = UINavigationBarAppearance()
        bar.configureWithTransparentBackground()
        if let jacoby = UIFont(name: "JacobyICGBlack", size: 34) {
            bar.largeTitleTextAttributes = [.font: UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: jacoby),
                                            .foregroundColor: UIColor.white]
        }
        if let univers = UIFont(name: "Univers-Bold", size: 17) {
            bar.titleTextAttributes = [.font: UIFontMetrics(forTextStyle: .headline).scaledFont(for: univers),
                                       .foregroundColor: UIColor.white]
        }
        UINavigationBar.appearance().standardAppearance = bar
        UINavigationBar.appearance().scrollEdgeAppearance = bar
        UINavigationBar.appearance().compactAppearance = bar
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .environment(player)
                .environment(downloads)
                .tint(.aioTint)
                // Always the branded blue look (like the AIO website), with white text on it.
                .preferredColorScheme(.dark)
                .task { await app.bootstrap() }
        }
    }
}

@MainActor
@Observable
final class AppModel {
    enum Phase { case loading, signedOut, choosingProfile, ready }
    var phase: Phase = .loading
    var profiles: [Profile] = []
    var profile: Profile?
    var profileError: String?

    private static let profileKey = "selectedViewerID"

    func bootstrap() async {
        guard await AuthService.shared.isSignedIn else { phase = .signedOut; return }
        await loadProfiles()
    }

    func didSignIn() async {
        await loadProfiles()
    }

    func loadProfiles() async {
        do {
            profiles = try await AIOService.profiles()
            profileError = nil
            // Restore the last profile if it needs no PIN, or its PIN is remembered.
            if let saved = UserDefaults.standard.string(forKey: Self.profileKey),
               let match = profiles.first(where: { $0.viewerID == saved }),
               !match.hasPIN || Keychain.get(Self.pinKey(match.viewerID)) != nil {
                activate(match, pin: Keychain.get(Self.pinKey(match.viewerID)).map { String(decoding: $0, as: UTF8.self) })
            } else {
                phase = .choosingProfile
            }
        } catch AuthError.notSignedIn {
            phase = .signedOut
        } catch {
            profileError = error.localizedDescription
            phase = .choosingProfile
        }
    }

    func activate(_ profile: Profile, pin: String?) {
        APIClient.shared.viewerID = profile.viewerID
        APIClient.shared.viewerPIN = pin
        if let pin { Keychain.set(Data(pin.utf8), for: Self.pinKey(profile.viewerID)) }
        UserDefaults.standard.set(profile.viewerID, forKey: Self.profileKey)
        self.profile = profile
        phase = .ready
    }

    func switchProfile() {
        AudioPlayer.shared.stop()
        phase = .choosingProfile
    }

    func signOut() async {
        AudioPlayer.shared.stop()
        await AuthService.shared.signOut()
        APIClient.shared.viewerID = nil
        APIClient.shared.viewerPIN = nil
        for p in profiles { Keychain.set(nil, for: Self.pinKey(p.viewerID)) }
        UserDefaults.standard.removeObject(forKey: Self.profileKey)
        profile = nil
        phase = .signedOut
    }

    private static func pinKey(_ viewerID: String) -> String { "pin-\(viewerID)" }
}

struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        switch app.phase {
        case .loading:
            ZStack { Color.aioNavy.ignoresSafeArea(); ProgressView().tint(.white) }
        case .signedOut:
            SignInView()
        case .choosingProfile:
            ProfilePickerView()
        case .ready:
            MainTabView()
        }
    }
}
