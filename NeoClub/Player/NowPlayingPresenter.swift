import SwiftUI
import UIKit

/// Presents Now Playing from UIKit the way Apple Music does (traced on iOS 27.2, see docs/original-app-analysis.md):
///
/// - **Open**: Music's own animator. The card grows out of the mini player on a critically damped spring (mass 1,
///   stiffness 333.33, damping 36.51; response 0.344 s, no overshoot), starting as Liquid Glass and filling in with the
///   player, with its content scaled to the card's width. Behind it the app only dims (black, ~12%); nothing behind
///   moves, blurs or bounces. (The system zoom transition's open overshoots and ramps a blur over the page.)
/// - **Close**: the sheet's own dismissal (traced in Music with Frida, 2026-11-12). Music's sheet has the mini player
///   as its `sourceView`, so UIKit shrinks the card (`UIDropShadowView`) into the bar's frame on its spring (mass 1,
///   stiffness 333.33, damping 36.51) while the bar's Liquid Glass follows the card's bounds, position and corners
///   (`CAMatchPropertyAnimation`s on the bar's glass element), so the card becomes the bar. Dragging is the sheet's
///   own pan. Alongside, Music flies the artwork into the bar's artwork slot on the same spring, fades its content
///   out (0.7153 s, its overdamped cubic spring: mass 3, stiffness 500, damping 1000) and fades the bar's own
///   content in (0.5 s, default curve); see `runCloseAnimations`.
@MainActor
@Observable
final class NowPlayingPresenter: NSObject {
    static let shared = NowPlayingPresenter()

    /// True while Now Playing is open (the player idles while it's closed).
    private(set) var isPresented = false
    /// True while the close flies a copy of the artwork into the bar (the player's own artwork is hidden).
    private(set) var isClosing = false
    /// Where the player's artwork is drawn, in the player's own space (NowPlayingPresentation.space), and its corner radius (reported by NowPlayingView).
    @ObservationIgnored var artworkFrame: CGRect = .zero
    @ObservationIgnored var artworkCornerRadius: CGFloat = 10

    private var presented: UIHostingController<AnyView>?
    private var openAnimator = OpenAnimator()
    /// Built once and reused, already laid out, so opening doesn't wait for the player to be created (a visible
    /// stall on slower devices).
    private var cached: UIHostingController<AnyView>?

    private func controller() -> UIHostingController<AnyView> {
        if let cached { return cached }
        let content = AnyView(NowPlayingPresentation()
            .environment(AudioPlayer.shared)
            .environment(DownloadStore.shared)
            .environment(BookmarkStore.shared)
            .environment(NetworkMonitor.shared))
        let vc = UIHostingController(rootView: content)
        // Insets come from the window (see NowPlayingPresentation), not from the view's scaled frame.
        vc.safeAreaRegions = []
        vc.view.backgroundColor = .clear
        // Apple Music's presentation (traced 2026-11-12): a form sheet made full screen with the sheet controller's
        // private `wantsFullScreen`, not `.overFullScreen`. With `.overFullScreen` the zoom close treats the page
        // behind as pushed back and springs it out (the page jumped ~13 pt and slid back); as Music's sheet it stays.
        vc.modalPresentationStyle = .formSheet
        configureSheet(vc)
        cached = vc
        return vc
    }

    private func configureSheet(_ vc: UIViewController) {
        guard let sheet = vc.sheetPresentationController else { return }
        sheet.detents = [.large()]
        sheet.prefersGrabberVisible = false
        sheet.delegate = self
        // Music's sheet, read from the running app with Frida (2026-11-12): source = the mini player's view, and
        // three private settings, set by KVC when present:
        // - `_wantsFullScreen`: the sheet fills the screen.
        // - `_allowsInteractiveDismissWhenFullScreen`: the sheet's own drag stays on while it's full screen.
        // - `_cornerRadiusForPresentationAndDismissal` 24: the card's corners as it lands in the bar.
        if let bar = barContentView() { setSource(bar, of: sheet) }
        func set(_ key: String, _ value: Any) {
            let setter = "_set" + key.prefix(1).uppercased() + key.dropFirst() + ":"
            if sheet.responds(to: NSSelectorFromString(setter)) { sheet.setValue(value, forKey: key) }
        }
        set("wantsFullScreen", true)
        set("allowsInteractiveDismissWhenFullScreen", true)
        set("cornerRadiusForPresentationAndDismissal", 24.0 as CGFloat)
    }

    /// Music's sheet source: its mini player's view. The sheet's dismissal animator reads the private `_sourceView`
    /// (not the public `sourceView`) for where to land; without it the card slides off the bottom of the screen.
    private func setSource(_ view: UIView, of sheet: UISheetPresentationController) {
        sheet.sourceView = view
        let privateSource = NSSelectorFromString("_setSourceView:")
        if sheet.responds(to: privateSource) { sheet.perform(privateSource, with: view) }
    }

    /// Builds and lays out Now Playing ahead of time (call once the app is showing).
    func prepare() {
        guard cached == nil, let window else { return }
        let vc = controller()
        vc.view.frame = window.bounds
        vc.view.setNeedsLayout()
        vc.view.layoutIfNeeded()
    }

    /// The controller while its close is still running (UIKit won't present it again until that has finished).
    private var dismissing: UIHostingController<AnyView>?
    /// What was last asked for; an open asked for during a close happens when the close finishes.
    private var wantsShow = false

    /// Shows or hides Now Playing to match `show`.
    func update(show: Bool) {
        wantsShow = show
        if show { present() } else { dismiss() }
    }

    private var window: UIWindow? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first { $0.isKeyWindow }
    }

    private var root: UIViewController? {
        var vc = window?.rootViewController
        while let next = vc?.presentedViewController, next !== presented { vc = next }
        return vc
    }

    /// The mini player's glass container in the tab bar (the source the card grows from and lands in).
    func accessoryView() -> UIView? {
        guard let window else { return nil }
        var stack: [UIView] = [window]
        while let v = stack.popLast() {
            if String(describing: type(of: v)).contains("TabAccessoryContainer") { return v }
            stack.append(contentsOf: v.subviews)
        }
        return nil
    }

    private func present() {
        // Reopened while the last close is still landing: presenting the same controller then makes UIKit throw
        // (it ran the deferred present inside the close's completion and crashed). Open once it has finished.
        guard presented == nil, dismissing == nil, let root else { return }
        let vc = controller()
        guard vc.presentingViewController == nil else { return }
        vc.preferredTransition = nil
        vc.modalPresentationStyle = .formSheet
        configureSheet(vc)
        vc.transitioningDelegate = self
        vc.view.alpha = 1
        isClosing = false
        openAnimator.source = accessoryView()?.convert(accessoryView()?.bounds ?? .zero, to: nil)
        presented = vc
        isPresented = true
        root.present(vc, animated: true)
    }

    private func dismiss() {
        guard let vc = presented else { return }
        beginClose(vc)
        // Before the dismissal starts, so the stand-ins are in the card when UIKit resizes it (they resize with it).
        runCloseAnimations(vc)
        vc.dismiss(animated: true) { [weak self] in self?.closeFinished() }
    }

    /// The bar's own content view (Music's sheet source is its mini player's view, the same view inside the bar).
    private func barContentView() -> UIView? {
        accessoryView()?.subviews.first ?? accessoryView()
    }

    /// The close has been asked for (a tap, or the sheet's drag): the sheet lands in the bar.
    private func beginClose(_ vc: UIHostingController<AnyView>) {
        presented = nil
        isPresented = false
        dismissing = vc
        // The sheet's own (non-custom) dismissal morphs the card into its source.
        vc.preferredTransition = nil
        // The bar may have been rebuilt since it opened. (Only the source: setting the detents again mid-drag made the
        // sheet spring back instead of closing.)
        if let sheet = vc.sheetPresentationController, let bar = barContentView(), sheet.sourceView !== bar {
            setSource(bar, of: sheet)
        }
    }

    private func closeFinished() {
        dismissing?.view.alpha = 1
        dismissing = nil
        flyingArtwork?.removeFromSuperview()
        flyingArtwork = nil
        closingStage?.removeFromSuperview()
        closingStage = nil
        isClosing = false
        if wantsShow { present() }
    }

    private var flyingArtwork: UIView?
    private var closingStage: UIView?

    /// Music's animations alongside the sheet's landing (traced 2026-11-12, see the type's notes).
    ///
    /// Music lays its player out again at the bar's size inside the shrinking card, so its controls ride up with the
    /// card's bottom edge while the artwork shrinks into the bar's artwork slot and everything else fades. SwiftUI
    /// can't follow the card's frame animation, so the close swaps in UIKit stand-ins: snapshots of the player above
    /// and below the artwork, pinned to the card's top and bottom edges (UIKit resizes them with the card on its
    /// spring), and a copy of the artwork that flies into the bar.
    private func runCloseAnimations(_ vc: UIViewController) {
        guard let player = vc.view, let card = player.superview else { return }
        let full = player.bounds
        let spring = { UIViewPropertyAnimator(duration: 0, timingParameters:
            UISpringTimingParameters(mass: 1, stiffness: 333.3333, damping: 36.5148, initialVelocity: .zero)) }

        // The artwork, taken as it's drawn now (the loaded image when there is one).
        let artRect = artworkFrame.intersection(full)
        var art: UIView?
        if !artRect.isEmpty {
            if let image = AudioPlayer.shared.artworkImage {
                let view = UIImageView(image: image)
                view.contentMode = .scaleAspectFill
                art = view
            } else {
                art = player.resizableSnapshotView(from: artRect, afterScreenUpdates: false, withCapInsets: .zero)
            }
        }

        // The copy goes over the artwork first (hiding the real one draws a frame without it).
        if let art {
            art.clipsToBounds = true
            art.layer.cornerCurve = .continuous
            art.layer.cornerRadius = artworkCornerRadius
            art.frame = card.convert(artRect, from: player)
            card.addSubview(art)
            flyingArtwork = art
        }

        // The rest of the player, without the artwork: hide it, draw, then snapshot above and below it.
        if art != nil {
            isClosing = true
            player.setNeedsLayout()
            player.layoutIfNeeded()
        }
        let split = artRect.isEmpty ? full.height * 0.55 : min(full.height, artRect.maxY + 8)
        let stage = UIView(frame: card.bounds)
        stage.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        stage.isUserInteractionEnabled = false
        let topRect = CGRect(x: 0, y: 0, width: full.width, height: split)
        let bottomRect = CGRect(x: 0, y: split, width: full.width, height: full.height - split)
        if let top = player.resizableSnapshotView(from: topRect, afterScreenUpdates: art != nil, withCapInsets: .zero) {
            top.frame = card.convert(topRect, from: player)
            top.autoresizingMask = [.flexibleBottomMargin, .flexibleLeftMargin, .flexibleRightMargin]
            stage.addSubview(top)
        }
        if let bottom = player.resizableSnapshotView(from: bottomRect, afterScreenUpdates: false, withCapInsets: .zero) {
            bottom.frame = card.convert(bottomRect, from: player)
            bottom.autoresizingMask = [.flexibleTopMargin, .flexibleLeftMargin, .flexibleRightMargin]
            stage.addSubview(bottom)
        }
        if let art { card.insertSubview(stage, belowSubview: art) } else { card.addSubview(stage) }
        closingStage = stage
        player.alpha = 0

        // The player fades out on Music's curve (its MPCubicSpring, sampled as this cubic).
        let fade = UIViewPropertyAnimator(duration: 0.7153, controlPoint1: CGPoint(x: 0.1878, y: 0.0023),
                                          controlPoint2: CGPoint(x: 0.5399, y: 0.9629)) { stage.alpha = 0 }
        fade.startAnimation()

        // The bar's content fades in over the landing.
        if let bar = barContentView() {
            bar.alpha = 0
            UIView.animate(withDuration: 0.5) { bar.alpha = 1 }
        }

        // The artwork flies into the bar's artwork slot on the card's spring, inside the card (so the card clips it).
        guard let art, let barSize = accessoryView()?.bounds.size else { return }
        // MiniPlayer: 32 pt artwork, 14 pt from the bar's leading edge, centred vertically.
        let end = CGRect(x: 14, y: (barSize.height - 32) / 2, width: 32, height: 32)
        let fly = spring()
        fly.addAnimations {
            art.frame = end
            art.layer.cornerRadius = 6
        }
        fly.startAnimation()
    }

}

extension NowPlayingPresenter: UISheetPresentationControllerDelegate {
    /// The sheet's drag started a close.
    func presentationControllerWillDismiss(_ presentationController: UIPresentationController) {
        guard let vc = presented, presentationController.presentedViewController === vc else { return }
        beginClose(vc)
        guard let coordinator = vc.transitionCoordinator else { return }
        if coordinator.isInteractive {
            // Music starts its own animations when the finger lifts and the close goes ahead.
            coordinator.notifyWhenInteractionChanges { [weak self] ctx in
                guard let self else { return }
                if ctx.isCancelled {
                    self.presented = vc
                    self.isPresented = true
                    self.dismissing = nil
                } else {
                    self.runCloseAnimations(vc)
                }
            }
        } else {
            runCloseAnimations(vc)
        }
    }

    /// A close by dragging finished.
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        guard dismissing === presentationController.presentedViewController else { return }
        wantsShow = false
        AudioPlayer.shared.showNowPlaying = false
        closeFinished()
    }
}

extension NowPlayingPresenter: UIViewControllerTransitioningDelegate {
    func animationController(forPresented presented: UIViewController, presenting: UIViewController,
                             source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        openAnimator
    }

    /// The close: UIKit's own sheet animator, landing in the bar. Music's delegate returns its subclass of UIKit's
    /// private `_UISheetAnimationController` with `isReversed` on and `sourceFrame` set to the bar's frame in the
    /// window (traced 2026-11-12); UIKit fills in the rest (the drag's frame, attachment point, property animator).
    /// Without a source frame the sheet slides off the bottom of the screen instead.
    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        guard let cls = NSClassFromString("_UISheetAnimationController") as? NSObject.Type,
              let bar = accessoryView() else { return nil }
        let animator = cls.init()
        guard animator.responds(to: NSSelectorFromString("setIsReversed:")),
              animator.responds(to: NSSelectorFromString("setSourceFrame:")),
              let transitioning = animator as? UIViewControllerAnimatedTransitioning else { return nil }
        animator.setValue(true, forKey: "isReversed")
        animator.setValue(NSValue(cgRect: bar.convert(bar.bounds, to: nil)), forKey: "sourceFrame")
        return transitioning
    }
}

/// Apple Music's open: card from the bar's frame to full screen on its spring, content scaled with the card's width,
/// glass first, flat dim behind.
@MainActor
private final class OpenAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    var source: CGRect?

    /// Music's spring: mass 1, stiffness 333.33, damping 36.51 (critically damped, response 0.344 s).
    static let spring = UISpringTimingParameters(mass: 1, stiffness: 333.3333, damping: 36.5148, initialVelocity: .zero)

    nonisolated func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval { 0.51 }

    nonisolated func animateTransition(using ctx: UIViewControllerContextTransitioning) {
        MainActor.assumeIsolated { run(ctx) }
    }

    private func run(_ ctx: UIViewControllerContextTransitioning) {
        guard let toView = ctx.view(forKey: .to), let toVC = ctx.viewController(forKey: .to) else { ctx.completeTransition(false); return }
        let container = ctx.containerView
        let full = ctx.finalFrame(for: toVC).isEmpty ? container.bounds : ctx.finalFrame(for: toVC)
        let start = source.map { container.convert($0, from: nil) }
            ?? CGRect(x: full.minX + 16, y: full.maxY - 110, width: full.width - 32, height: 48)

        // Flat dim behind (Music's UIDimmingView), no blur.
        let dim = UIView(frame: container.bounds)
        dim.backgroundColor = .black
        dim.alpha = 0
        container.addSubview(dim)

        // The card: a clipping view that grows from the bar, glass underneath, the player scaled to its width.
        let card = UIView(frame: start)
        card.clipsToBounds = true
        card.layer.cornerCurve = .continuous
        card.layer.cornerRadius = start.height / 2
        let glass = UIVisualEffectView(effect: UIGlassEffect())
        glass.frame = card.bounds
        glass.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        card.addSubview(glass)
        container.addSubview(card)

        // A view controller's view resizes with its parent by default; inside the growing card that made the player
        // grow by the card's growth on top of its full size (SwiftUI laid it out too tall, contents off the card).
        let mask = toView.autoresizingMask
        toView.autoresizingMask = []
        toView.frame = full
        toView.layer.anchorPoint = CGPoint(x: 0.5, y: 0)
        let s0 = start.width / max(1, full.width)
        toView.transform = CGAffineTransform(scaleX: s0, y: s0)
        toView.center = CGPoint(x: start.width / 2, y: 0)
        card.addSubview(toView)
        // The glass sits over the player and fades off it (fading the player itself in left SwiftUI not drawing its
        // contents until the transition ended).
        card.bringSubviewToFront(glass)

        let animator = UIViewPropertyAnimator(duration: 0, timingParameters: Self.spring)
        animator.addAnimations {
            card.frame = full
            card.layer.cornerRadius = 0
            toView.transform = .identity
            toView.center = CGPoint(x: full.width / 2, y: 0)
            dim.alpha = 0.12
        }
        // The player fills in over the glass quickly, as Music's content does.
        UIView.animate(withDuration: 0.12, delay: 0.03, options: [.curveEaseOut]) { glass.alpha = 0 }
        animator.addCompletion { _ in
            // Hand the presented view back to the container at full screen; drop the scaffolding.
            toView.layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            toView.transform = .identity
            toView.frame = full
            toView.autoresizingMask = mask
            container.addSubview(toView)
            card.removeFromSuperview()
            dim.removeFromSuperview()
            ctx.completeTransition(!ctx.transitionWasCancelled)
        }
        animator.startAnimation()
    }
}
