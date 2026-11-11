import Network
import SwiftUI

/// Tracks whether the device has a usable connection, for offline states.
@MainActor
@Observable
final class NetworkMonitor {
    static let shared = NetworkMonitor()
    private(set) var isOnline = true
    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { path in
            let online = path.status == .satisfied
            Task { @MainActor in NetworkMonitor.shared.isOnline = online }
        }
        monitor.start(queue: DispatchQueue(label: "NetworkMonitor"))
    }
}

/// Small banner shown at the top of online-only screens while offline.
struct OfflineBanner: View {
    @Environment(NetworkMonitor.self) private var network
    var body: some View {
        if !network.isOnline {
            Label("You're offline. Downloads are in your Library.", systemImage: "wifi.slash")
                .font(.universBold(14, relativeTo: .subheadline))
                .padding(.horizontal, 16).padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular.tint(.aioRed.opacity(0.5)), in: .rect(cornerRadius: 14))
                .padding(.horizontal, 20)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
