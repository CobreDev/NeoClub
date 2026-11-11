import SwiftUI

@main
struct NeoClubApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .task { await app.bootstrap() }
        }
    }
}

@MainActor
@Observable
final class AppModel {
    enum Phase { case loading, signedOut, signedIn }
    var phase: Phase = .loading

    func bootstrap() async {
        phase = await AuthService.shared.isSignedIn ? .signedIn : .signedOut
    }

    func didSignIn() async {
        phase = .signedIn
    }

    func signOut() async {
        await AuthService.shared.signOut()
        APIClient.shared.viewerID = nil
        APIClient.shared.viewerPIN = nil
        phase = .signedOut
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        switch app.phase {
        case .loading: ProgressView()
        case .signedOut: SignInView()
        case .signedIn: APIExplorerView()
        }
    }
}
