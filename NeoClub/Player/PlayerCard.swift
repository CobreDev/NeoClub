import SwiftUI

/// Apple Music-style Now Playing card, drawn over the app instead of using a system presentation.
///
/// Every number here was measured from Apple Music (iOS 27.2) running in a virtual iPhone Duo, by tracing its
/// UIKit/Core Animation calls during taps, drags and flicks:
/// - **Open** (tap, or a quick upward flick on the mini player; there is no interactive drag-up): the card's frame
///   goes from the mini player's frame to full screen on a critically damped spring, response 0.3441 s.
///   The flick's velocity is not carried over.
/// - **Drag down**: the card follows the finger 1:1 (after touch slop) at full size; it does not narrow or scale.
/// - **Release to dismiss**: the card's size and horizontal position morph into the mini player on the same
///   critically damped spring, while its vertical position travels on a spring with damping ratio 0.8 and the same
///   response, starting with the finger's velocity. Corners go from 8 pt toward the capsule's radius.
/// - **Release without dismissing**: back up on the critically damped spring.
/// - Behind the card the app is dimmed with black at 20% opacity when open, fading with the card's travel.
/// - Contents cross-fade between the full player and the mini player as the card nears the bar, so it stays solid
///   until the last stretch (Apple's 0.5 s keyframe fades run alongside its 0.5 s geometry springs).
@MainActor
@Observable
final class PlayerCardModel {
    static let shared = PlayerCardModel()

    /// The card's top edge, in global coordinates.
    var top: CGFloat = 0
    /// 0 = full-screen size, 1 = the mini player's size and horizontal position.
    var morph: CGFloat = 1
    /// 0 = full player shown, 1 = mini player face shown (cross-fade).
    var face: CGFloat = 1
    /// True from the start of opening until the collapse animation finishes.
    private(set) var visible = false
    /// The mini player's frame in global coordinates.
    var miniFrame: CGRect = .zero
    /// The card's full-screen frame in global coordinates (set by the card's container).
    var fullFrame: CGRect = .zero

    private var generation = 0

    // Apple Music's springs (UIKit: response 0.3441 s → stiffness 333.33 with mass 1).
    /// Damping ratio 1.0: size/position morph, opening, and snapping back.
    static let morphSpring = Animation.spring(response: 0.3441, dampingFraction: 1.0)
    /// Damping ratio 0.8 with the finger's velocity: vertical travel when dismissing.
    static func travelSpring(initialVelocity: CGFloat) -> Animation {
        .interpolatingSpring(mass: 1, stiffness: 333.3333, damping: 29.2119, initialVelocity: initialVelocity)
    }

    func open() {
        generation += 1
        closing = false
        if !visible {
            var tx = Transaction(); tx.disablesAnimations = true
            withTransaction(tx) { top = miniFrame.minY; morph = 1; face = 1 }
            visible = true
        }
        withAnimation(Self.morphSpring) { top = fullFrame.minY; morph = 0 }
    }

    /// Follows a finger dragging the open card down by `distance` points (already past touch slop).
    func drag(to distance: CGFloat) {
        var tx = Transaction(); tx.disablesAnimations = true
        withTransaction(tx) { top = fullFrame.minY + max(0, distance) }
    }

    /// Apple Music lets the card glide at the finger's speed for about 80 ms after release (its animator's
    /// continue phase, measured 66–96 ms) before the collapse springs start.
    static let releaseCoast: TimeInterval = 0.08
    /// True from release until the card has collapsed (or is opened again).
    private(set) var closing = false

    /// Collapses into the mini player from wherever the card is, carrying `velocity` (points per second, downward).
    func close(velocity: CGFloat = 0) {
        generation += 1
        let gen = generation
        closing = true
        let v = max(0, velocity)
        // Coast first, at the release speed.
        if v > 0 {
            let coastTo = min(miniFrame.minY, top + v * Self.releaseCoast)
            withAnimation(.linear(duration: Self.releaseCoast)) { top = coastTo }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (v > 0 ? Self.releaseCoast : 0)) { [weak self] in
            guard let self, self.generation == gen else { return }
            let remaining = max(1, self.miniFrame.minY - self.top)
            withAnimation(Self.morphSpring) { self.morph = 1 } completion: { [weak self] in
                guard let self, self.generation == gen else { return }
                self.visible = false
                self.closing = false
            }
            withAnimation(Self.travelSpring(initialVelocity: v / remaining)) { self.top = self.miniFrame.minY }
        }
    }

    /// Released without dismissing: back to the top.
    func snapBack() {
        withAnimation(Self.morphSpring) { top = fullFrame.minY }
    }
}

/// The card's frame for the model's state, as an animatable modifier so the springs drive it frame by frame.
struct CardGeometry: ViewModifier, Animatable {
    var top: CGFloat
    var morph: CGFloat
    var face: CGFloat
    let full: CGRect
    let mini: CGRect
    /// Global origin of the host's coordinate space, for positioning.
    let origin: CGPoint

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(top, AnimatablePair(morph, face)) }
        set { top = newValue.first; morph = newValue.second.first; face = newValue.second.second }
    }

    static func smoothstep(_ x: CGFloat) -> CGFloat { let c = min(1, max(0, x)); return c * c * (3 - 2 * c) }

    /// How far the card has travelled toward the mini player (0 at the top, 1 at the bar).
    var travel: CGFloat { min(1, max(0, (top - full.minY) / max(1, mini.minY - full.minY))) }

    var rect: CGRect {
        let width = full.width + (mini.width - full.width) * morph
        let midX = full.midX + (mini.midX - full.midX) * morph
        let height = full.height + (mini.height - full.height) * morph
        return CGRect(x: midX - width / 2, y: top, width: width, height: height)
    }

    /// Cross-fade between the full player and the mini player's face, driven by how close the card is to the bar
    /// (both in position and in size), so the card stays solid until the last stretch, like Apple Music.
    var faceProgress: CGFloat { Self.smoothstep((min(travel, morph) - 0.5) / 0.45) }

    /// 8 pt open, growing with travel and the morph to the mini player's capsule radius.
    var radius: CGFloat { 8 + (mini.height / 2 - 8) * max(travel, morph) }

    func body(content: Content) -> some View {
        let r = rect
        let face = faceProgress
        content
            .environment(\.playerCardFace, face)
            // The player is laid out at full-screen size, pinned to the card's top edge and centered on it…
            .frame(width: full.width, height: full.height)
            .frame(width: r.width, height: r.height, alignment: .top)
            // …and the mini player's face cross-fades in at the top as the card turns into the bar.
            .overlay(alignment: .top) {
                // No glass of its own: the real bar's glass is underneath when the card lands.
                MiniPlayer(isCardFace: true)
                    .frame(width: mini.width, height: mini.height)
                    .opacity(Double(face))
                    .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .position(x: r.midX - origin.x, y: r.midY - origin.y)
    }
}

private struct PlayerCardFaceKey: EnvironmentKey { static let defaultValue: CGFloat = 0 }
extension EnvironmentValues {
    /// 0 while the card shows the full player, rising to 1 as it shows the mini player's face.
    var playerCardFace: CGFloat {
        get { self[PlayerCardFaceKey.self] }
        set { self[PlayerCardFaceKey.self] = newValue }
    }
}

/// Black dimming behind the card: 20% when open, fading with the card's travel (Apple Music's UIDimmingView).
private struct CardDimming: View, Animatable {
    var top: CGFloat
    let full: CGRect
    let mini: CGRect
    var animatableData: CGFloat {
        get { top }
        set { top = newValue }
    }
    var body: some View {
        let travel = min(1, max(0, (top - full.minY) / max(1, mini.minY - full.minY)))
        Color.black.opacity(0.2 * Double(1 - travel)).ignoresSafeArea().allowsHitTesting(false)
    }
}

/// Hosts the card over the whole window. Place as an overlay on the root of the app.
/// The card stays mounted (hidden on the mini player) while something is loaded, so opening animates out of the
/// mini player and the artwork is already loaded.
struct PlayerCardHost: View {
    @Environment(AudioPlayer.self) private var player
    @State private var model = PlayerCardModel.shared
    /// Touch slop, like UIKit's: the card starts following once the finger has moved this far.
    private let slop: CGFloat = 12

    var body: some View {
        GeometryReader { geo in
            let safe = geo.frame(in: .global)
            let insets = geo.safeAreaInsets
            let full = CGRect(x: safe.minX - insets.leading, y: safe.minY - insets.top,
                              width: safe.width + insets.leading + insets.trailing,
                              height: safe.height + insets.top + insets.bottom)
            let mini = model.miniFrame == .zero ? fallbackMini(full) : model.miniFrame
            ZStack(alignment: .topLeading) {
                if player.hasItem && model.visible {
                    CardDimming(top: model.top, full: full, mini: mini)
                }
                if player.hasItem {
                    CardContent(insets: insets)
                        .modifier(CardGeometry(top: model.top, morph: model.morph, face: model.face,
                                               full: full, mini: mini, origin: safe.origin))
                        .opacity(model.visible ? 1 : 0)
                        .allowsHitTesting(model.visible)
                        .gesture(dismissDrag())
                }
            }
            .onAppear { model.fullFrame = full }
            .onChange(of: full) { _, f in model.fullFrame = f }
        }
        .onChange(of: player.showNowPlaying) { _, show in
            if show { model.open() } else if model.visible && model.morph < 1 && !model.closing { model.close() }
        }
    }

    private func fallbackMini(_ full: CGRect) -> CGRect {
        CGRect(x: full.minX + 16, y: full.maxY - 120, width: full.width - 32, height: 54)
    }

    private func dismissDrag() -> some Gesture {
        DragGesture(minimumDistance: slop, coordinateSpace: .global)
            .onChanged { v in
                guard abs(v.translation.height) > abs(v.translation.width) else { return }
                model.drag(to: v.translation.height - slop)
            }
            .onEnded { v in
                let distance = v.translation.height - slop
                let velocity = v.velocity.height
                if distance > 140 || velocity > 500 {
                    model.close(velocity: velocity)
                    player.showNowPlaying = false
                } else {
                    model.snapBack()
                }
            }
    }
}

/// Full player that cross-fades with the mini player's face. The backdrop fills the card edge to edge;
/// the player itself is inset to the screen's safe area (status bar, camera, home indicator).
private struct CardContent: View {
    @Environment(\.playerCardFace) private var face
    let insets: EdgeInsets

    var body: some View {
        ZStack {
            // The card's own background gives way to the bar's glass only in the last part of the cross-fade.
            NowPlayingBackdrop().opacity(1 - Double(CardGeometry.smoothstep((face - 0.7) / 0.3)))
            NowPlayingView(drawsBackground: false)
                .padding(insets)
                .opacity(Double(1 - face))
        }
    }
}
