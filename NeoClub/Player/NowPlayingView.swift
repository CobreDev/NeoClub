import AVKit
import SwiftUI

/// Full-screen player, modeled on Apple Music: big artwork, scrubber, transport, speed and AirPlay.
struct NowPlayingView: View {
    @Environment(AudioPlayer.self) private var player
    @Environment(\.dismiss) private var dismiss
    @State private var scrubbing: Double?

    private let speeds: [Float] = [0.75, 1.0, 1.25, 1.5, 2.0]

    var body: some View {
        ZStack {
            background
            VStack(spacing: 0) {
                Capsule().fill(.white.opacity(0.4)).frame(width: 40, height: 5).padding(.top, 10)
                Spacer(minLength: 20)
                Artwork(url: player.episode?.artworkURL, cornerRadius: 14)
                    .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
                    .scaleEffect(player.isPlaying ? 1 : 0.82)
                    .animation(.spring(response: 0.45, dampingFraction: 0.75), value: player.isPlaying)
                    .padding(.horizontal, 28)
                    .frame(maxWidth: 420)
                Spacer(minLength: 24)
                titleBlock
                scrubber.padding(.top, 20)
                transport.padding(.top, 18)
                bottomBar.padding(.top, 26)
                Spacer(minLength: 16)
            }
            .padding(.horizontal, 28)
            .foregroundStyle(.white)
        }
        .presentationDragIndicator(.hidden)
        .presentationBackground(Color.aioNavy)
    }

    private var background: some View {
        ZStack {
            Color.aioNavy
            Artwork(url: player.episode?.artworkURL, cornerRadius: 0)
                .scaledToFill()
                .blur(radius: 60)
                .opacity(0.55)
            LinearGradient(colors: [.clear, .black.opacity(0.35)], startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
    }

    private var titleBlock: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(player.episode?.title ?? "")
                    .font(.universBold(22, relativeTo: .title2))
                    .lineLimit(2)
                Text(player.episode?.albumName ?? "Adventures in Odyssey")
                    .font(.univers(17))
                    .opacity(0.7)
                    .lineLimit(1)
            }
            Spacer()
            if let error = player.errorMessage {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.aioYellow)
                    .help(error)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var scrubber: some View {
        let shown = scrubbing ?? player.position
        let total = max(player.duration, 1)
        return VStack(spacing: 6) {
            Slider(value: Binding(get: { shown }, set: { scrubbing = $0 }), in: 0...total) { editing in
                if !editing, let target = scrubbing {
                    player.seek(to: target)
                    scrubbing = nil
                }
            }
            .tint(.white)
            HStack {
                Text(Self.time(shown))
                Spacer()
                Text("-" + Self.time(max(0, total - shown)))
            }
            .font(.system(size: 12, weight: .medium, design: .rounded).monospacedDigit())
            .opacity(0.65)
        }
    }

    private var transport: some View {
        HStack {
            Spacer()
            Button { player.skip(by: -15) } label: { Image(systemName: "gobackward.15").font(.system(size: 32)) }
                .accessibilityLabel("Back 15 seconds")
            Spacer()
            Button { player.togglePlayPause() } label: {
                ZStack {
                    if player.isLoading {
                        ProgressView().tint(.white).controlSize(.large)
                    } else {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 48))
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
                .frame(width: 72, height: 72)
            }
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            Spacer()
            Button { player.skip(by: 30) } label: { Image(systemName: "goforward.30").font(.system(size: 32)) }
                .accessibilityLabel("Forward 30 seconds")
            Spacer()
        }
        .buttonStyle(.plain)
    }

    private var bottomBar: some View {
        @Bindable var player = player
        return HStack {
            Menu {
                Picker("Speed", selection: $player.rate) {
                    ForEach(speeds, id: \.self) { s in Text(Self.speedLabel(s)).tag(s) }
                }
            } label: {
                Text(Self.speedLabel(player.rate))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .frame(width: 52, height: 34)
                    .glassEffect(.regular, in: .capsule)
            }
            Spacer()
            RoutePicker().frame(width: 44, height: 44)
            Spacer()
            Button { player.playNext() } label: {
                Image(systemName: "forward.end.fill").font(.title3).frame(width: 52, height: 34)
            }
            .disabled(player.queue.isEmpty)
            .opacity(player.queue.isEmpty ? 0.35 : 1)
            .accessibilityLabel("Next episode")
        }
        .buttonStyle(.plain)
    }

    static func time(_ seconds: Double) -> String {
        let s = Int(seconds.rounded(.down))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }

    static func speedLabel(_ s: Float) -> String {
        s == 1 ? "1×" : String(format: "%g×", s)
    }
}

struct RoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.tintColor = .white
        v.activeTintColor = UIColor(Color.aioYellow)
        v.prioritizesVideoDevices = false
        return v
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
