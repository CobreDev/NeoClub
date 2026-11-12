import SwiftUI

/// Apple Music-style Now Playing card, drawn over the app instead of using a system presentation.
///
/// Every number here was measured from Apple Music (iOS 27.2) running in a virtual iPhone Duo, by tracing its
/// UIKit/Core Animation calls during taps, drags and flicks:
/// - **Open** (tap, or a swipe up on the mini player; there is no interactive drag-up): the card's frame
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
    /// Closing, the card takes the bar's shape on its own spring, started at release (but never ahead of its travel),
    /// so even a fast flick shrinks into the bar over ~170 ms instead of snapping in a frame. Slightly underdamped:
    /// Apple Music's card settles into the bar with a small bounce (recorded on the Duo).
    static let landSpring = Animation.spring(response: 0.36, dampingFraction: 0.6)

    /// How far the card is from full screen toward the bar (0…1).
    private var travel: CGFloat {
        min(1, max(0, (top - fullFrame.minY) / max(1, miniFrame.minY - fullFrame.minY)))
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

    /// After the finger lifts, Apple Music's card holds completely still for about 100 ms (its animator's continue
    /// phase: traced at 66–96 ms, recorded on the vphone Duo at ~110 ms) before the collapse springs start.
    static let releaseHold: TimeInterval = 0.1
    /// True from release until the card has collapsed (or is opened again).
    private(set) var closing = false

    /// Collapses into the mini player from wherever the card is, carrying `velocity` (points per second, downward).
    func close(velocity: CGFloat = 0) {
        generation += 1
        let gen = generation
        closing = true
        let v = max(0, velocity)
        // A card let go slowly holds where the finger left it, then collapses; a flick carries straight on (a pause
        // after a fast flick reads as a stutter).
        let hold = top > fullFrame.minY + 1 && morph < 1 && v < 300 ? Self.releaseHold : 0
        DispatchQueue.main.asyncAfter(deadline: .now() + hold) { [weak self] in
            guard let self, self.generation == gen else { return }
            let remaining = max(1, self.miniFrame.minY - self.top)
            // The card hands over to the real bar only once it has both arrived and finished taking the bar's shape
            // (including the bounce). Waiting on the travel alone hid it mid-shrink when it was let go near the bar.
            var running = 2
            let finished = { [weak self] in
                running -= 1
                guard running == 0, let self, self.generation == gen else { return }
                self.visible = false
                self.closing = false
            }
            withAnimation(Self.landSpring, completionCriteria: .removed) { self.morph = 1 } completion: { finished() }
            withAnimation(Self.travelSpring(initialVelocity: v / remaining)) {
                self.top = self.miniFrame.minY
            } completion: { finished() }
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
    /// Collapsing into the bar: the card keeps (nearly) full width on the way down and only takes the bar's shape
    /// at the very end, as recorded from Apple Music (about 15% narrower at 90% of the way down).
    var closing = false
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

    /// How far the card has taken the bar's size and position. Opening grows it on its own spring (fast, ahead
    /// of the position); closing ties it to the travel with a steep curve so it narrows only at the end.
    /// Once the card is at the bar, the morph alone drives it, so its bounce (past the bar's size and back) shows.
    var shape: CGFloat { closing ? (travel >= 0.999 ? morph : min(morph, pow(travel, 10))) : morph }

    /// How much a landing overshoot squashes the bar (wider and flatter, like a drop of glass settling).
    static let squash: CGFloat = 0.6

    var rect: CGRect {
        let m = shape
        // Landing bounce: past the bar's shape, the card squashes about the bar's center (a little wider and flatter)
        // and springs back, rather than shrinking smaller and drifting.
        if closing && m > 1 {
            let over = min(m - 1, 0.4)
            let w = mini.width * (1 + Self.squash * over)
            let h = mini.height * (1 - Self.squash * over * 0.5)
            return CGRect(x: mini.midX - w / 2, y: mini.midY - h / 2, width: w, height: h)
        }
        let width = full.width + (mini.width - full.width) * m
        let midX = full.midX + (mini.midX - full.midX) * m
        let height = full.height + (mini.height - full.height) * m
        // Never past the bar: a hard flick's spring would otherwise dip the card below it before settling.
        let y0 = min(top, mini.minY)
        // Closing, the shrink also pulls the card the rest of the way down, so it lands on the bar's glass exactly as
        // it takes the bar's shape instead of shrinking first and then sliding into place.
        // Fully pinned to the bar once it's nearly bar-sized, so the bounce can't drag it back up.
        let pull = closing ? min(1, max(0, m / 0.85)) : 0
        let y = y0 + (mini.minY - y0) * pull
        return CGRect(x: midX - width / 2, y: y, width: width, height: height)
    }

    /// Cross-fade between the full player and the mini player's face, driven by how close the card is to the bar
    /// (both in position and in size), so the card stays solid until the last stretch, like Apple Music.
    /// Closing, the bar's face shows as soon as the card nears the bottom (Apple Music shows it inside the card
    /// before the card has shrunk); opening, it gives way as the card grows.
    var faceProgress: CGFloat {
        closing ? Self.smoothstep(shape / 0.6) : Self.smoothstep((min(travel, shape) - 0.5) / 0.45)
    }

    /// 8 pt open, growing with travel and the morph to the mini player's capsule radius.
    var radius: CGFloat { min(8 + (mini.height / 2 - 8) * max(travel, shape), rect.height / 2) }

    func body(content: Content) -> some View {
        let r = rect
        let face = faceProgress
        content
            .environment(\.playerCardFace, face)
            // The player is laid out at full-screen size and scaled with the card's width (Apple Music scales the
            // whole player as the card grows out of the bar, rather than cropping it), pinned to the card's top…
            .frame(width: full.width, height: full.height)
            .scaleEffect(r.width / max(1, full.width), anchor: .top)
            .frame(width: r.width, height: r.height, alignment: .top)
            // …and the mini player's face cross-fades in at the top as the card turns into the bar.
            .overlay(alignment: .top) {
                MiniPlayer(isCardFace: true)
                    .frame(width: mini.width, height: mini.height)
                    .opacity(Double(face))
                    .allowsHitTesting(false)
            }
            // As the card becomes the bar its background turns into Liquid Glass (the system material the bar is made
            // of), so what lands and bounces is glass, not an opaque card over the bar.
            .background {
                if face > 0.01 {
                    Color.clear
                        .glassEffect(.regular, in: .rect(cornerRadius: radius, style: .continuous))
                        .opacity(Double(face))
                }
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
                                               closing: model.closing, full: full, mini: mini, origin: safe.origin))
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
            NowPlayingView(drawsBackground: false, insets: insets)
                .padding(insets)
                // Hidden behind the mini player it stays mounted (so opening is instant) but idle.
                .environment(\.isOnScreen, PlayerCardModel.shared.visible)
                .opacity(Double(1 - face))
        }
    }
}
